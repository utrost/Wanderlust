import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sqflite/sqflite.dart';

import '../recording/activity_type.dart';
import '../recording/saved_walk.dart';
import '../recording/gps_diagnostics.dart';
import '../recording/walk_history.dart';
import '../review/gap_review_store.dart';
import '../transfer/walk_codec.dart';
import 'app_database.dart';

class WalkRepository
    implements WalkHistory, GapReviewStore, GpsDiagnosticsStore {
  WalkRepository(this.connection);
  final AppDatabase connection;
  Future<Database> get _db => connection.database;
  @override
  Future<String?> walkUid(int id) async {
    final rows = await (await _db).query(
      'recorded_walk',
      columns: ['uid'],
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : rows.single['uid'] as String;
  }

  Future<List<SavedWalk>> recoverAndList() async {
    final db = await _db;
    return db.transaction((txn) async {
      // Use the last durable fix as the recovery end, never the relaunch time.
      await recoverInterrupted(txn);
      return readFrom(txn);
    });
  }

  static Future<List<SavedWalk>> readFrom(
    DatabaseExecutor db, {
    int? id,
  }) async {
    final rows = await db.query(
      'recorded_walk',
      where: id == null ? null : 'id = ?',
      whereArgs: id == null ? null : [id],
      orderBy: 'id DESC',
    );
    final walks = <SavedWalk>[];
    for (final row in rows) {
      final points = await db.query(
        'recorded_point',
        where: 'walk_id = ?',
        whereArgs: [row['id']],
        orderBy: 'seq',
      );
      final meta = jsonDecode(row['trace_metadata'] as String) as Map;
      walks.add(
        SavedWalk(
          row['id'] as int,
          DateTime.parse(row['started_at'] as String),
          row['ended_at'] == null
              ? null
              : DateTime.parse(row['ended_at'] as String),
          row['status'] as String,
          points
              .map(
                (p) => positionAt(
                  Position.fromMap(
                    jsonDecode(p['position'] as String) as Map<String, dynamic>,
                  ),
                  DateTime.parse(p['timestamp'] as String),
                ),
              )
              .toList(),
          uid: row['uid'] as String,
          fingerprint: row['fingerprint'] as String?,
          segmentStarts: (meta['segmentStarts'] as List? ?? []).cast<int>(),
          untimed: (meta['untimed'] as List? ?? []).cast<int>(),
          favourite: meta['favourite'] == true,
          activity: WalkActivity.parse(meta['activity']),
          gpsDiagnostics: readGpsDiagnostics(meta['gpsDiagnostics']),
          confirmedSections: (meta['confirmedSections'] as List? ?? [])
              .cast<int>(),
        ),
      );
    }
    return walks;
  }

  /// Read without recovering: library operations must never stop a live journal.
  @override
  Future<List<SavedWalk>> listSaved() async =>
      (await _db).transaction(readFrom);

  @override
  Future<SavedWalk> loadWalk(int id) async =>
      (await readFrom(await _db, id: id)).single;

  /// Metadata reads lazily cache fingerprints for completed/imported traces.
  @override
  Future<List<SavedWalk>> listSummaries({bool recover = false}) async {
    return (await _db).transaction((tx) async {
      if (recover) {
        await recoverInterrupted(tx);
      }
      final rows = await tx.rawQuery(
        'SELECT w.*, (SELECT COUNT(*) FROM recorded_point p WHERE p.walk_id = w.id) AS point_count FROM recorded_walk w ORDER BY w.id DESC',
      );
      final summaries = <SavedWalk>[];
      for (final row in rows) {
        final id = row['id'] as int;
        var fingerprint = row['fingerprint'] as String?;
        if (fingerprint == null && row['status'] != 'recording') {
          final walk = (await readFrom(tx, id: id)).single;
          fingerprint = sha256
              .convert(utf8.encode(WalkCodec.exportGpx(walk)))
              .toString();
          await tx.update(
            'recorded_walk',
            {'fingerprint': fingerprint},
            where: 'id = ?',
            whereArgs: [id],
          );
        }
        final meta =
            jsonDecode(row['trace_metadata'] as String) as Map<String, dynamic>;
        summaries.add(
          SavedWalk(
            id,
            DateTime.parse(row['started_at'] as String),
            row['ended_at'] == null
                ? null
                : DateTime.parse(row['ended_at'] as String),
            row['status'] as String,
            const [],
            uid: row['uid'] as String,
            favourite: meta['favourite'] == true,
            activity: WalkActivity.parse(meta['activity']),
            gpsDiagnostics: readGpsDiagnostics(meta['gpsDiagnostics']),
            confirmedSections: (meta['confirmedSections'] as List? ?? [])
                .cast<int>(),
            fingerprint: fingerprint,
            storedPointCount: row['point_count'] as int,
            segmentStarts: (meta['segmentStarts'] as List? ?? []).cast<int>(),
            untimed: (meta['untimed'] as List? ?? []).cast<int>(),
          ),
        );
      }
      return summaries;
    });
  }

  /// A library preference only: leaves raw fixes and coverage memberships alone.
  @override
  Future<void> setFavourite(String uid, bool favourite) async {
    await (await _db).transaction((txn) async {
      final rows = await txn.query(
        'recorded_walk',
        columns: ['trace_metadata'],
        where: 'uid = ?',
        whereArgs: [uid],
      );
      if (rows.isEmpty) throw StateError('Walk is no longer available');
      final metadata =
          jsonDecode(rows.single['trace_metadata'] as String)
              as Map<String, dynamic>;
      metadata['favourite'] = favourite;
      await txn.update(
        'recorded_walk',
        {'trace_metadata': jsonEncode(metadata)},
        where: 'uid = ?',
        whereArgs: [uid],
      );
    });
  }

  @override
  Future<void> saveConfirmedSections(String uid, List<int> edges) async {
    if (edges.length > 10000 ||
        edges.any((e) => e <= 0 || e > 9007199254740991)) {
      throw const FormatException('Invalid confirmed sections');
    }
    await (await _db).transaction((tx) async {
      final rows = await tx.query(
        'recorded_walk',
        columns: ['trace_metadata', 'status'],
        where: 'uid = ?',
        whereArgs: [uid],
      );
      if (rows.isEmpty || rows.single['status'] == 'recording') {
        throw StateError('Finish the walk before reviewing gaps');
      }
      final meta =
          jsonDecode(rows.single['trace_metadata'] as String)
              as Map<String, dynamic>;
      meta['confirmedSections'] = edges.toSet().toList()..sort();
      await tx.update(
        'recorded_walk',
        {'trace_metadata': jsonEncode(meta)},
        where: 'uid = ?',
        whereArgs: [uid],
      );
    });
  }

  @override
  Future<void> setActivity(String uid, WalkActivity activity) async {
    await (await _db).transaction((tx) async {
      final rows = await tx.query(
        'recorded_walk',
        where: 'uid = ?',
        whereArgs: [uid],
      );
      if (rows.isEmpty || rows.single['status'] == 'recording') {
        throw StateError('Finish recording before changing activity');
      }
      final meta =
          jsonDecode(rows.single['trace_metadata'] as String)
              as Map<String, dynamic>;
      if (WalkActivity.parse(meta['activity']) == activity) return;
      meta['activity'] = activity.name;
      await tx.update(
        'recorded_walk',
        {'trace_metadata': jsonEncode(meta), 'fingerprint': null},
        where: 'uid = ?',
        whereArgs: [uid],
      );
    });
  }

  @override
  Future<void> saveGpsDiagnostics(
    int walkId,
    Map<String, Object?> metrics,
  ) async {
    await (await _db).transaction((tx) async {
      final rows = await tx.query(
        'recorded_walk',
        columns: ['trace_metadata'],
        where: 'id = ?',
        whereArgs: [walkId],
      );
      if (rows.isEmpty) return;
      final meta =
          jsonDecode(rows.single['trace_metadata'] as String)
              as Map<String, dynamic>;
      meta['gpsDiagnostics'] = readGpsDiagnostics(metrics);
      await tx.update(
        'recorded_walk',
        {'trace_metadata': jsonEncode(meta)},
        where: 'id = ?',
        whereArgs: [walkId],
      );
    });
  }

  Future<int> begin(
    DateTime startedAt, {
    WalkActivity activity = WalkActivity.walk,
  }) async => (await _db).insert('recorded_walk', {
    'started_at': startedAt.toUtc().toIso8601String(),
    'status': 'recording',
    'trace_metadata': jsonEncode({'activity': activity.name}),
  });

  Future<void> append(int id, int sequence, Position point) async {
    await (await _db).transaction((tx) async {
      await tx.insert('recorded_point', {
        'walk_id': id,
        'seq': sequence,
        'position': jsonEncode(point.toJson()),
        'timestamp': point.timestamp.toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await tx.update(
        'recorded_walk',
        {'fingerprint': null},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<void> finish(int id, DateTime endedAt, String status) async {
    await (await _db).update(
      'recorded_walk',
      {'ended_at': endedAt.toUtc().toIso8601String(), 'status': status},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Use the last durable fix, never the relaunch time, as recovery end.
  static Future<void> recoverInterrupted(DatabaseExecutor db) async {
    await db.rawUpdate(
      "UPDATE recorded_walk SET status = 'interrupted', ended_at = COALESCE((SELECT timestamp FROM recorded_point WHERE walk_id = recorded_walk.id ORDER BY seq DESC LIMIT 1), started_at) WHERE status = 'recording'",
    );
  }
}
