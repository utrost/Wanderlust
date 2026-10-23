import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../memories/memory.dart';
import '../memories/memory_store.dart';
import '../recording/saved_walk.dart';
import '../settings/walk_preferences.dart';
import '../transfer/walk_importer.dart';
import 'app_database.dart';
import 'offline_map_repository.dart';
import 'preferences_repository.dart';
import 'walk_repository.dart';

class BackupImporter implements WalkImporter {
  BackupImporter(this.connection);
  final AppDatabase connection;
  Future<Database> get _db => connection.database;

  /// One transaction for the whole validated file. Local IDs are remapped;
  /// backup identities survive restore and recordings with identical traces.
  @override
  Future<int> mergeWalks(
    List<SavedWalk> incoming, {
    bool deduplicateTrace = false,
    List<WalkMemory> memories = const [],
    Stream<WalkMemory>? memoryStream,
    Stream<SavedWalk>? walkStream,
    Stream<String>? mapStream,
    List<String> maps = const [],
    WalkPreferences? preferences,
    String? activeMap,
  }) async {
    return (await _db).transaction((txn) async {
      final rows = await txn.query(
        'recorded_walk',
        columns: ['id', 'uid', 'status'],
      );
      if (rows.any((w) => w['status'] == 'recording')) {
        throw StateError('Finish recording before importing or restoring.');
      }
      final byUid = {
        for (final row in rows) row['uid'] as String: row['id'] as int,
      };
      final traces = deduplicateTrace
          ? (await WalkRepository.readFrom(txn)).map((w) => w.traceKey).toSet()
          : <String>{};
      var added = 0;
      await for (final walk in walkStream ?? Stream.fromIterable(incoming)) {
        if (deduplicateTrace && traces.contains(walk.traceKey)) continue;
        final previousId = byUid[walk.uid];
        if (previousId != null) {
          final previous = (await WalkRepository.readFrom(
            txn,
            id: previousId,
          )).single;
          if (jsonEncode(
                previous.toBackup(
                  includeFavourite: false,
                  includeDiagnostics: false,
                ),
              ) !=
              jsonEncode(
                walk.toBackup(
                  includeFavourite: false,
                  includeDiagnostics: false,
                ),
              )) {
            throw const FormatException(
              'A walk identity conflicts with existing data.',
            );
          }
          continue;
        }
        final id = await txn.insert('recorded_walk', {
          'uid': walk.uid,
          'started_at': walk.startedAt.toUtc().toIso8601String(),
          'ended_at': walk.endedAt?.toUtc().toIso8601String(),
          'status': walk.status,
          'trace_metadata': jsonEncode({
            'segmentStarts': walk.segmentStarts,
            'untimed': walk.untimed,
            'favourite': walk.favourite,
            'activity': walk.activity.name,
            if (walk.gpsDiagnostics.isNotEmpty)
              'gpsDiagnostics': walk.gpsDiagnostics,
            'confirmedSections': walk.confirmedSections,
          }),
        });
        final batch = txn.batch();
        for (var i = 0; i < walk.points.length; i++) {
          final p = walk.points[i];
          batch.insert('recorded_point', {
            'walk_id': id,
            'seq': i,
            'position': jsonEncode(p.toJson()),
            'timestamp': p.timestamp.toUtc().toIso8601String(),
          });
        }
        await batch.commit(noResult: true);
        byUid[walk.uid] = id;
        if (deduplicateTrace) traces.add(walk.traceKey);
        added++;
      }
      await for (final memory
          in memoryStream ?? Stream.fromIterable(memories)) {
        final existingMemory = await txn.query(
          'memory',
          columns: ['id'],
          where: 'id = ? AND draft = ?',
          whereArgs: [memory.id, memory.draft ? 1 : 0],
        );
        if (existingMemory.isEmpty) {
          await MemoryStore.writeTo(
            txn,
            WalkMemory.fromJson({
              ...memory.toJson(),
              'pendingPhoto': false,
            }, complete: true),
          );
        }
      }
      // Maps, settings, walks and memories commit together or not at all.
      await for (final source in mapStream ?? Stream.fromIterable(maps)) {
        await OfflineMapRepository.writeTo(txn, source, keepExisting: true);
      }
      if (activeMap != null) {
        await txn.rawUpdate(
          'UPDATE offline_selection SET version = ? WHERE id = 1 AND version IS NULL AND EXISTS (SELECT 1 FROM offline_area WHERE version = ?)',
          [activeMap, activeMap],
        );
      }
      if (preferences != null) {
        await PreferencesRepository.writeTo(txn, preferences);
      }
      return added;
    });
  }
}
