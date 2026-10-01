import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/area_network.dart';
import '../memories/memory_backup.dart';
import '../memories/memory_photos.dart';
import '../recording/saved_walk.dart';
import '../settings/walk_preferences.dart';
import 'backup_archive.dart';
import 'backup_data.dart';
import 'walk_codec.dart';
import 'walk_files.dart';
import 'walk_importer.dart';

MemoryBackup _readBackup(Uint8List bytes) => MemoryBackup.decode(bytes);
SavedWalk _readGpx(Uint8List bytes) =>
    WalkCodec.importGpx(WalkCodec.decodeBytes(bytes));
Uint8List _writeBackup(MemoryBackup backup) =>
    MemoryBackup.encode(backup, compressed: true);
Uint8List _writeGpx(SavedWalk walk) =>
    Uint8List.fromList(utf8.encode(WalkCodec.exportGpx(walk)));

class RestoreSummary {
  const RestoreSummary({
    required this.walks,
    required this.memories,
    required this.maps,
    required this.hasSettings,
  });
  final int walks, memories, maps;
  final bool hasSettings;
}

class RestoreOptions {
  const RestoreOptions({required this.maps, this.settings = false});
  final bool maps, settings;
}

class RestoreResult {
  const RestoreResult({
    required this.added,
    required this.existing,
    required this.restoredMaps,
    this.preferences,
  });
  final int added, existing;
  final bool restoredMaps;
  final WalkPreferences? preferences;
}

typedef ChooseRestore = Future<RestoreOptions?> Function(RestoreSummary);

/// Owns file staging, validation and commit ordering. The UI supplies choices
/// and renders progress; it never owns temporary files or restore transactions.
class WalkTransfer {
  WalkTransfer({
    required this.data,
    required this.importer,
    required this.files,
    Future<void> Function(Uint8List)? checkPhoto,
    Directory? temporaryRoot,
  }) : _checkPhoto = checkPhoto ?? validatePhoto,
       _temporaryRoot = temporaryRoot ?? Directory.systemTemp;
  final BackupData data;
  final WalkImporter importer;
  final WalkFiles files;
  final Future<void> Function(Uint8List) _checkPhoto;
  final Directory _temporaryRoot;

  bool get supportsArchives => files is ArchiveFiles;
  Future<void> cancel() async {
    if (files case final ArchiveFiles archive) await archive.cancelArchive();
  }

  Future<RestoreResult?> importFile({
    required bool backup,
    required ChooseRestore choose,
    required BackupProgress progress,
    void Function()? onCommit,
  }) async {
    if (backup && files is ArchiveFiles) {
      final directory = await _temporaryRoot.createTemp('wanderlust-restore-');
      File? input;
      try {
        input = await (files as ArchiveFiles).pickArchive();
        if (input == null) return null;
        progress.check();
        if (await BackupArchive.recognizes(input)) {
          final staged = await BackupArchive.read(input, directory, progress);
          return await _restore(
            staged.metadata,
            backup: true,
            choose: choose,
            progress: progress,
            onCommit: onCommit,
            staged: staged,
          );
        }
        if (await input.length() > MemoryBackup.maxBytes) {
          throw const FormatException('Legacy backup exceeds 128 MiB.');
        }
        return await _restore(
          await compute(_readBackup, await input.readAsBytes()),
          backup: true,
          choose: choose,
          progress: progress,
          onCommit: onCommit,
        );
      } finally {
        // Both paths are private temporary copies; a selected user document is
        // never deleted. Clean staging even if deleting the input copy fails.
        try {
          if (input != null && await input.exists()) await input.delete();
        } finally {
          await directory.delete(recursive: true);
        }
      }
    }
    final bytes = await files.pick();
    if (bytes == null) return null;
    progress.check();
    final bundle = backup
        ? await compute(_readBackup, bytes)
        : MemoryBackup([await compute(_readGpx, bytes)], const []);
    return _restore(
      bundle,
      backup: backup,
      choose: choose,
      progress: progress,
      onCommit: onCommit,
    );
  }

  Future<RestoreResult?> _restore(
    MemoryBackup bundle, {
    required bool backup,
    required ChooseRestore choose,
    required BackupProgress progress,
    void Function()? onCommit,
    StagedBackup? staged,
  }) async {
    await for (final memory
        in staged?.memories() ?? Stream.fromIterable(bundle.memories)) {
      progress.check();
      if (memory.photo != null) await _checkPhoto(memory.photo!);
    }
    var options = RestoreOptions(maps: bundle.maps.isNotEmpty);
    if (backup && (bundle.maps.isNotEmpty || bundle.preferences != null)) {
      final selected = await choose(
        RestoreSummary(
          walks: bundle.walks.length,
          memories: bundle.memories.length,
          maps: bundle.maps.length,
          hasSettings: bundle.preferences != null,
        ),
      );
      if (selected == null) return null;
      options = selected;
    }
    progress.check();
    // Cancellation is allowed up to this boundary. The commit itself is atomic.
    onCommit?.call();
    final added = await importer.mergeWalks(
      bundle.walks,
      deduplicateTrace: !backup,
      memories: staged == null ? bundle.memories : const [],
      memoryStream: staged?.memories(),
      walkStream: staged?.walks(),
      maps: options.maps ? bundle.maps : const [],
      preferences: options.settings ? bundle.preferences : null,
      activeMap: options.maps ? bundle.activeMap : null,
    );
    return RestoreResult(
      added: added,
      existing: bundle.walks.length - added,
      restoredMaps: options.maps,
      preferences: options.settings ? bundle.preferences : null,
    );
  }

  Future<bool> backup(BackupProgress progress) async {
    if (files case final ArchiveFiles archive) {
      final directory = await _temporaryRoot.createTemp('wanderlust-export-');
      try {
        final file = File('${directory.path}/backup.wanderlust');
        await BackupArchive.write(file, data, progress);
        progress.check();
        return await archive.saveArchive(file);
      } finally {
        await directory.delete(recursive: true);
      }
    }
    final maps = <String>[];
    for (final area in await data.maps.listAreas()) {
      progress.check();
      final source = await data.maps.readArea(area.version);
      if (source == null) throw StateError('Saved map is unavailable');
      maps.add(source);
    }
    final selected = await data.maps.readActiveArea();
    final bytes = await compute(
      _writeBackup,
      MemoryBackup(
        await data.history.listSaved(),
        await data.memories.exportAll(),
        maps: maps,
        preferences: await data.settings.readPreferences(),
        activeMap: selected == null
            ? null
            : AreaNetwork.parse(selected).version,
      ),
    );
    progress.check();
    return files.save('wanderlust-backup.json.gz', 'application/gzip', bytes);
  }

  Future<bool> exportGpx(SavedWalk walk) async {
    final full = walk.isSummary ? await data.history.loadWalk(walk.id) : walk;
    return files.save(
      'wanderlust-walk-${walk.uid}.gpx',
      'application/gpx+xml',
      await compute(_writeGpx, full),
    );
  }
}
