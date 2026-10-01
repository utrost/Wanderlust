import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../data/area_network.dart';
import '../memories/memory.dart';
import '../memories/memory_backup.dart';
import '../recording/walk_store.dart';
import '../settings/walk_preferences.dart';
import 'walk_codec.dart';

class BackupCancelled implements Exception {}

class BackupProgress {
  bool cancelled = false;
  int records = 0;
  final void Function(int)? onProgress;
  BackupProgress({this.onProgress});
  void check() {
    if (cancelled) throw BackupCancelled();
  }

  void advance() {
    check();
    onProgress?.call(++records);
  }
}

/// Version 4: bounded records with individual SHA-256 checksums and raw photos.
/// Files are staged in private cache; never trust archive names as file paths.
class BackupArchive {
  static const magic = 'WANDERLUST4\n';
  static const maxRecord = 32 * 1024 * 1024;
  static const maxArchive = 2 * 1024 * 1024 * 1024;

  /// Recover temporary space left by a killed process; never inspect exports.
  static Future<void> cleanAbandonedFiles() async {
    final cutoff = DateTime.now().subtract(const Duration(days: 1));
    await for (final entry in Directory.systemTemp.list(followLinks: false)) {
      final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (!(name.startsWith('wanderlust-export-') ||
          name.startsWith('wanderlust-restore-') ||
          name.startsWith('wanderlust-import-'))) {
        continue;
      }
      if (entry is Link) continue;
      final stat = await entry.stat();
      if (stat.modified.isBefore(cutoff)) await entry.delete(recursive: true);
    }
  }

  static Future<bool> recognizes(File file) async {
    final input = await file.open();
    try {
      return utf8.decode(
            await input.read(magic.length),
            allowMalformed: true,
          ) ==
          magic;
    } finally {
      await input.close();
    }
  }

  static Future<void> write(
    File file,
    SqliteWalkStore store,
    BackupProgress progress,
  ) async {
    final output = await file.open(mode: FileMode.write);
    var count = 0;
    var total = magic.length;
    Future<void> record(String kind, Uint8List bytes) async {
      progress.check();
      if (bytes.length > maxRecord) {
        throw const FormatException('One backup record exceeds 32 MiB.');
      }
      final header = utf8.encode(
        jsonEncode({
          'kind': kind,
          'length': bytes.length,
          'sha256': sha256.convert(bytes).toString(),
        }),
      );
      total += 4 + header.length + bytes.length;
      if (total > maxArchive) {
        throw const FormatException('Backup exceeds 2 GiB.');
      }
      final size = ByteData(4)..setUint32(0, header.length);
      await output.writeFrom(size.buffer.asUint8List());
      await output.writeFrom(header);
      await output.writeFrom(bytes);
      count++;
      progress.advance();
    }

    Future<void> json(String kind, Object value) =>
        record(kind, Uint8List.fromList(utf8.encode(jsonEncode(value))));
    try {
      await output.writeFrom(utf8.encode(magic));
      final selected = await store.readActiveArea();
      await json('settings', {
        'preferences': (await store.readPreferences()).toJson(),
        'activeMap': selected == null
            ? null
            : AreaNetwork.parse(selected).version,
      });
      for (final area in await store.listAreas()) {
        progress.check();
        final source = await store.readArea(area.version);
        if (source == null) throw StateError('Saved map is unavailable');
        await record('map', Uint8List.fromList(utf8.encode(source)));
      }
      final summaries = await store.listSummaries();
      if (summaries.length > 100000) {
        throw const FormatException('Backup exceeds 100,000 walks.');
      }
      final walkUids = summaries.map((w) => w.uid).toSet();
      for (final summary in summaries) {
        final walk = await store.loadWalk(summary.id);
        progress.check();
        if (walk.status == 'recording') {
          throw StateError('Finish recording before backing up.');
        }
        await record(
          'walk',
          Uint8List.fromList(utf8.encode(WalkCodec.exportBackup([walk]))),
        );
      }
      final memories = await store.memories.list();
      if (memories.length > 10000) {
        throw const FormatException('Backup exceeds 10,000 memories.');
      }
      if (memories.any(
        (m) => m.walkUid != null && !walkUids.contains(m.walkUid),
      )) {
        throw const FormatException('A memory refers to a missing walk.');
      }
      for (final metadata in memories) {
        progress.check();
        final memory = await store.memories.read(metadata.id, metadata.draft);
        if (memory == null) throw StateError('Memory changed during backup');
        await json('memory', memory.toJson(includePhoto: false));
        if (memory.photo != null) await record('photo', memory.photo!);
      }
      await json('end', {'records': count});
      await output.flush();
    } finally {
      await output.close();
    }
  }

  static Future<StagedBackup> read(
    File file,
    Directory directory,
    BackupProgress progress,
  ) async {
    if (await file.length() > maxArchive) {
      throw const FormatException('Backup exceeds 2 GiB.');
    }
    final input = await file.open();
    Future<Uint8List> exact(int length) async {
      final bytes = await input.read(length);
      if (bytes.length != length) {
        throw const FormatException('Backup is incomplete.');
      }
      return bytes;
    }

    final walks = <SavedWalk>[], memories = <WalkMemory>[], maps = <String>[];
    final photos = <String, File>{};
    final walkFiles = <File>[];
    final uids = <String>{}, memoryIds = <String>{}, versions = <String>{};
    WalkPreferences? preferences;
    String? activeMap;
    WalkMemory? waitingPhoto;
    var count = 0;
    try {
      if (utf8.decode(await exact(magic.length)) != magic) {
        throw const FormatException('Unsupported backup.');
      }
      while (true) {
        progress.check();
        final size = (await exact(4)).buffer.asByteData().getUint32(0);
        if (size == 0 || size > 4096) {
          throw const FormatException('Invalid backup header.');
        }
        final header =
            jsonDecode(utf8.decode(await exact(size))) as Map<String, dynamic>;
        final kind = header['kind'] as String, length = header['length'] as int;
        if (length < 0 ||
            length > maxRecord ||
            (kind == 'photo' && length > WalkMemory.maxPhotoBytes)) {
          throw const FormatException('Backup record exceeds its size limit.');
        }
        final bytes = await exact(length);
        if (sha256.convert(bytes).toString() != header['sha256']) {
          throw const FormatException('Backup checksum does not match.');
        }
        if (waitingPhoto != null && kind != 'photo') {
          throw const FormatException('Missing memory photo.');
        }
        if (count == 0 && kind != 'settings') {
          throw const FormatException('Missing backup settings.');
        }
        if (kind == 'end') {
          final end = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
          if (end['records'] != count ||
              (await input.read(1)).isNotEmpty ||
              (activeMap != null && !versions.contains(activeMap)) ||
              memories.any(
                (m) => m.walkUid != null && !uids.contains(m.walkUid),
              )) {
            throw const FormatException(
              'Backup contents are incomplete or inconsistent.',
            );
          }
          return StagedBackup(
            MemoryBackup(
              walks,
              memories,
              maps: maps,
              preferences: preferences,
              activeMap: activeMap,
            ),
            photos,
            walkFiles,
          );
        }
        switch (kind) {
          case 'settings':
            if (count != 0) throw const FormatException('Repeated settings.');
            final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
            final values = data['preferences'] as Map<String, dynamic>;
            preferences = WalkPreferences.fromJson(values);
            final normalized = preferences.toJson();
            if (values.length != normalized.length ||
                normalized.entries.any((e) => values[e.key] != e.value)) {
              throw const FormatException('Invalid backup settings.');
            }
            activeMap = data['activeMap'] as String?;
          case 'map':
            if (maps.length >= 8 || length > 16 * 1024 * 1024) {
              throw const FormatException('Too many or oversized maps.');
            }
            final source = utf8.decode(bytes);
            final map = AreaNetwork.parse(source);
            if (!versions.add(map.version)) {
              throw const FormatException('Repeated map.');
            }
            maps.add(source);
          case 'walk':
            final walk = WalkCodec.importBackup(utf8.decode(bytes)).single;
            if (!uids.add(walk.uid) || walks.length >= 100000) {
              throw const FormatException('Repeated or too many walks.');
            }
            final traceFile = File(
              '${directory.path}/walk-${walkFiles.length}',
            );
            await traceFile.writeAsBytes(bytes, flush: true);
            walkFiles.add(traceFile);
            walks.add(
              SavedWalk(
                walk.id,
                walk.startedAt,
                walk.endedAt,
                walk.status,
                const [],
                uid: walk.uid,
                storedPointCount: walk.points.length,
              ),
            );
          case 'memory':
            final memory = WalkMemory.fromJson(
              jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
            );
            final key = '${memory.id}:${memory.draft}';
            if (!memoryIds.add(key) || memories.length >= 10000) {
              throw const FormatException('Repeated or too many memories.');
            }
            memories.add(memory);
            if (memory.hasPhoto) waitingPhoto = memory;
          case 'photo':
            final memory = waitingPhoto;
            if (memory == null || bytes.length != memory.photoLength) {
              throw const FormatException('Unexpected or incomplete photo.');
            }
            final photo = File('${directory.path}/photo-${photos.length}');
            await photo.writeAsBytes(bytes, flush: true);
            photos['${memory.id}:${memory.draft}'] = photo;
            waitingPhoto = null;
          default:
            throw const FormatException('Unknown backup record.');
        }
        count++;
        progress.advance();
      }
    } on BackupCancelled {
      rethrow;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Malformed backup archive.');
    } finally {
      await input.close();
    }
  }
}

class StagedBackup {
  StagedBackup(this.metadata, this.photos, this.walkFiles);
  final List<File> walkFiles;
  Stream<SavedWalk> walks() async* {
    for (final file in walkFiles) {
      yield WalkCodec.importBackup(await file.readAsString()).single;
    }
  }

  final MemoryBackup metadata;
  final Map<String, File> photos;
  Stream<WalkMemory> memories() async* {
    for (final m in metadata.memories) {
      final photo = photos['${m.id}:${m.draft}'];
      yield WalkMemory.fromJson({
        ...m.toJson(includePhoto: false),
        'photo': photo == null ? null : base64Encode(await photo.readAsBytes()),
        'pendingPhoto': false,
      }, complete: true);
    }
  }
}
