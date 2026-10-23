import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'backup_contents.dart';
import '../memories/memory_photos.dart';
import '../recording/saved_walk.dart';
import '../settings/walk_preferences.dart';
import 'backup_archive.dart';
import 'backup_data.dart';
import 'walk_codec.dart';
import 'walk_files.dart';
import 'walk_importer.dart';

SavedWalk _readGpx(Uint8List bytes) =>
    WalkCodec.importGpx(WalkCodec.decodeBytes(bytes));
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

  Future<void> cancel() => files.cancelArchive();

  Future<RestoreResult?> importFile({
    required bool backup,
    required ChooseRestore choose,
    required BackupProgress progress,
    void Function()? onCommit,
  }) async {
    if (backup) {
      final directory = await _temporaryRoot.createTemp('wanderlust-restore-');
      File? input;
      try {
        input = await files.pickArchive();
        if (input == null) return null;
        progress.check();
        if (!await BackupArchive.recognizes(input)) {
          throw const FormatException(
            'Choose a .wanderlust backup. Old JSON/gzip backups are no longer supported.',
          );
        }
        final staged = await BackupArchive.read(input, directory, progress);
        return await _restore(
          staged.metadata,
          backup: true,
          choose: choose,
          progress: progress,
          onCommit: onCommit,
          staged: staged,
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
    final bundle = BackupContents([await compute(_readGpx, bytes)], const []);
    return _restore(
      bundle,
      backup: backup,
      choose: choose,
      progress: progress,
      onCommit: onCommit,
    );
  }

  Future<RestoreResult?> _restore(
    BackupContents bundle, {
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
    final mapCount = staged?.mapFiles.length ?? bundle.maps.length;
    var options = RestoreOptions(maps: mapCount > 0);
    if (backup && (mapCount > 0 || bundle.preferences != null)) {
      final selected = await choose(
        RestoreSummary(
          walks: bundle.walks.length,
          memories: bundle.memories.length,
          maps: mapCount,
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
      mapStream: options.maps ? staged?.maps() : null,
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
    final directory = await _temporaryRoot.createTemp('wanderlust-export-');
    try {
      final file = File('${directory.path}/backup.wanderlust');
      await BackupArchive.write(file, data, progress);
      progress.check();
      return await files.saveArchive(file);
    } finally {
      await directory.delete(recursive: true);
    }
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
