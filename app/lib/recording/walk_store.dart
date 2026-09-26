import 'dart:convert';

import 'saved_walk.dart';
import '../maps/area_store.dart';
export 'saved_walk.dart';

import '../coverage/coverage_store.dart';
import '../data/area_network.dart';

import 'package:geolocator/geolocator.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

abstract class WalkStore {
  Future<List<SavedWalk>> recoverAndList();
  Future<int> begin(DateTime startedAt);
  Future<void> append(int id, int sequence, Position point);
  Future<void> finish(int id, DateTime endedAt, String status);
  Future<void> close();
}

/// Recording journal. Each fix commits independently, so a process death can
/// lose only fixes whose write has not yet committed. Open sessions are retained
/// as interrupted; recovery never invents points or silently resumes GPS.
class SqliteWalkStore implements WalkStore, CoverageStore, AreaStore {
  SqliteWalkStore({DatabaseFactory? factory, String? databasePath})
    : _providedFactory = factory,
      _path = databasePath;
  final DatabaseFactory? _providedFactory;
  DatabaseFactory get _factory => _providedFactory ?? databaseFactory;
  final String? _path;
  Future<Database>? _opening;

  Future<Database> get _db => _opening ??= _open();
  Future<Database> _open() async {
    try {
      final file =
          _path ??
          path.join(await _factory.getDatabasesPath(), 'wanderlust.db');
      return await _factory.openDatabase(
        file,
        options: OpenDatabaseOptions(
          version: 4,
          onConfigure: (db) async {
            await db.execute('PRAGMA foreign_keys = ON');
          },
          onCreate: (db, version) async {
            await db.execute(
              "CREATE TABLE recorded_walk (id INTEGER PRIMARY KEY, started_at TEXT NOT NULL, ended_at TEXT, status TEXT NOT NULL CHECK(status IN ('recording','completed','interrupted')))",
            );
            await db.execute(
              'CREATE TABLE recorded_point (walk_id INTEGER NOT NULL REFERENCES recorded_walk(id), seq INTEGER NOT NULL, position TEXT NOT NULL, timestamp TEXT NOT NULL, PRIMARY KEY(walk_id, seq))',
            );
            await _createCoverage(db);
            await _createTransfer(db);
            await _createAreas(db);
          },
          onUpgrade: (db, oldVersion, newVersion) async {
            if (oldVersion < 2) await _createCoverage(db);
            if (oldVersion < 3) await _createTransfer(db);
            if (oldVersion < 4) await _createAreas(db);
          },
        ),
      );
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  static Future<void> _createAreas(DatabaseExecutor db) async {
    await db.execute(
      'CREATE TABLE offline_area (version TEXT PRIMARY KEY, name TEXT NOT NULL, geojson TEXT NOT NULL, downloaded_at TEXT NOT NULL, bytes INTEGER NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE offline_selection (id INTEGER PRIMARY KEY CHECK(id = 1), version TEXT REFERENCES offline_area(version) ON DELETE SET NULL)',
    );
    await db.insert('offline_selection', {'id': 1});
  }

  @override
  Future<List<OfflineArea>> listAreas() async {
    final rows = await (await _db).query(
      'offline_area',
      columns: ['version', 'name', 'downloaded_at', 'bytes'],
      orderBy: 'downloaded_at DESC',
    );
    return rows
        .map(
          (r) => OfflineArea(
            version: r['version'] as String,
            name: r['name'] as String,
            downloadedAt: DateTime.parse(r['downloaded_at'] as String),
            bytes: r['bytes'] as int,
          ),
        )
        .toList();
  }

  // Android CursorWindow cannot return a multi-megabyte value in one row.
  // Keep each result below 512 KiB even for four-byte Unicode code points.
  static const _mapChunkCharacters = 128 * 1024;

  Future<String?> _readArea(DatabaseExecutor db, String version) async {
    final lengths = await db.rawQuery(
      'SELECT length(geojson) AS characters FROM offline_area WHERE version = ?',
      [version],
    );
    if (lengths.isEmpty) return null;
    final length = lengths.single['characters'] as int;
    final source = StringBuffer();
    for (var start = 1; start <= length; start += _mapChunkCharacters) {
      final rows = await db.rawQuery(
        'SELECT substr(geojson, ?, ?) AS chunk FROM offline_area WHERE version = ?',
        [start, _mapChunkCharacters, version],
      );
      source.write(rows.single['chunk'] as String);
    }
    return source.toString();
  }

  @override
  Future<String?> readArea(String version) async =>
      (await _db).transaction((txn) => _readArea(txn, version));

  @override
  Future<String?> readActiveArea() async =>
      (await _db).transaction((txn) async {
        final rows = await txn.query(
          'offline_selection',
          columns: ['version'],
          where: 'id = 1',
        );
        final version = rows.isEmpty ? null : rows.single['version'] as String?;
        return version == null ? null : _readArea(txn, version);
      });

  @override
  Future<void> saveArea(String geojson) async {
    if (utf8.encode(geojson).length > 16 * 1024 * 1024) {
      throw const FormatException('Map exceeds the 16 MiB offline limit.');
    }
    final area = AreaNetwork.parse(geojson);
    await (await _db).transaction((txn) async {
      final rows = await txn.query('offline_area', columns: ['version']);
      if (rows.length >= 8 && !rows.any((r) => r['version'] == area.version)) {
        throw StateError(
          'Eight maps are saved. Remove an unused map before downloading another.',
        );
      }
      // UPSERT preserves the selection FK; REPLACE would clear it via DELETE.
      final values = {
        'name': area.name,
        'geojson': geojson,
        'downloaded_at': DateTime.now().toUtc().toIso8601String(),
        'bytes': utf8.encode(geojson).length,
      };
      final updated = await txn.update(
        'offline_area',
        values,
        where: 'version = ?',
        whereArgs: [area.version],
      );
      if (updated == 0) {
        await txn.insert('offline_area', {'version': area.version, ...values});
      }
    });
  }

  @override
  Future<void> selectArea(String? version) async {
    await (await _db).update('offline_selection', {
      'version': version,
    }, where: 'id = 1');
  }

  @override
  Future<void> deleteArea(String version) async {
    await (await _db).delete(
      'offline_area',
      where: 'version = ?',
      whereArgs: [version],
    );
  }

  @override
  Future<List<SavedWalk>> recoverAndList() async {
    final db = await _db;
    return db.transaction((txn) async {
      // Use the last durable fix as the recovery end, never the relaunch time.
      await txn.rawUpdate(
        "UPDATE recorded_walk SET status = 'interrupted', ended_at = COALESCE((SELECT timestamp FROM recorded_point WHERE walk_id = recorded_walk.id ORDER BY seq DESC LIMIT 1), started_at) WHERE status = 'recording'",
      );
      return _list(txn);
    });
  }

  static Future<void> _createTransfer(DatabaseExecutor db) async {
    await db.execute("ALTER TABLE recorded_walk ADD COLUMN uid TEXT");
    await db.execute(
      "ALTER TABLE recorded_walk ADD COLUMN trace_metadata TEXT NOT NULL DEFAULT '{}'",
    );
    await db.execute(
      "UPDATE recorded_walk SET uid = lower(hex(randomblob(16)))",
    );
    await db.execute('CREATE UNIQUE INDEX walk_uid ON recorded_walk(uid)');
    await db.execute(
      "CREATE TRIGGER assign_walk_uid AFTER INSERT ON recorded_walk WHEN NEW.uid IS NULL BEGIN UPDATE recorded_walk SET uid = lower(hex(randomblob(16))) WHERE id = NEW.id; END",
    );
  }

  static Future<List<SavedWalk>> _list(DatabaseExecutor db) async {
    final rows = await db.query('recorded_walk', orderBy: 'id DESC');
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
          segmentStarts: (meta['segmentStarts'] as List? ?? []).cast<int>(),
          untimed: (meta['untimed'] as List? ?? []).cast<int>(),
        ),
      );
    }
    return walks;
  }

  /// Read without recovering: library operations must never stop a live journal.
  Future<List<SavedWalk>> listSaved() async => (await _db).transaction(_list);

  /// One transaction for the whole validated file. Local IDs are remapped;
  /// backup identities survive restore and recordings with identical traces.
  Future<int> mergeWalks(
    List<SavedWalk> incoming, {
    bool deduplicateTrace = false,
  }) async {
    return (await _db).transaction((txn) async {
      final existing = await _list(txn);
      if (existing.any((w) => w.status == 'recording')) {
        throw StateError('Finish recording before importing or restoring.');
      }
      final byUid = {for (final w in existing) w.uid: w};
      final traces = existing.map((w) => w.traceKey).toSet();
      var added = 0;
      for (final walk in incoming) {
        if (deduplicateTrace && traces.contains(walk.traceKey)) continue;
        final previous = byUid[walk.uid];
        if (previous != null) {
          if (jsonEncode(previous.toBackup()) != jsonEncode(walk.toBackup())) {
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
        byUid[walk.uid] = walk;
        traces.add(walk.traceKey);
        added++;
      }
      return added;
    });
  }

  @override
  Future<int> begin(DateTime startedAt) async => (await _db).insert(
    'recorded_walk',
    {'started_at': startedAt.toUtc().toIso8601String(), 'status': 'recording'},
  );

  @override
  Future<void> append(int id, int sequence, Position point) async {
    await (await _db).insert('recorded_point', {
      'walk_id': id,
      'seq': sequence,
      'position': jsonEncode(point.toJson()),
      'timestamp': point.timestamp.toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> finish(int id, DateTime endedAt, String status) async {
    await (await _db).update(
      'recorded_walk',
      {'ended_at': endedAt.toUtc().toIso8601String(), 'status': status},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> _createCoverage(DatabaseExecutor db) async {
    await db.execute(
      'CREATE TABLE coverage_network (version TEXT PRIMARY KEY, area_id TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE coverage_edge (network_version TEXT NOT NULL REFERENCES coverage_network(version), edge_id INTEGER NOT NULL, PRIMARY KEY(network_version, edge_id))',
    );
    await db.execute(
      'CREATE TABLE walk_match (walk_id INTEGER NOT NULL REFERENCES recorded_walk(id), network_version TEXT NOT NULL REFERENCES coverage_network(version), fingerprint TEXT NOT NULL, PRIMARY KEY(walk_id, network_version))',
    );
    await db.execute(
      'CREATE TABLE walk_edge (walk_id INTEGER NOT NULL, network_version TEXT NOT NULL, edge_id INTEGER NOT NULL, PRIMARY KEY(walk_id, network_version, edge_id), FOREIGN KEY(walk_id, network_version) REFERENCES walk_match(walk_id, network_version) ON DELETE CASCADE, FOREIGN KEY(network_version, edge_id) REFERENCES coverage_edge(network_version, edge_id))',
    );
    await db.execute(
      'CREATE INDEX coverage_counts ON walk_edge(network_version, edge_id)',
    );
  }

  @override
  Future<void> registerNetwork(AreaNetwork network) async {
    final db = await _db;
    await db.transaction((txn) async {
      final existing = await txn.query(
        'coverage_network',
        where: 'version = ?',
        whereArgs: [network.version],
      );
      if (existing.isNotEmpty) return;
      await txn.insert('coverage_network', {
        'version': network.version,
        'area_id': network.areaId,
      });
      final batch = txn.batch();
      for (final id in network.edgeIds) {
        batch.insert('coverage_edge', {
          'network_version': network.version,
          'edge_id': id,
        });
      }
      await batch.commit(noResult: true);
    });
  }

  @override
  Future<String?> matchFingerprint(int walkId, String networkVersion) async {
    final rows = await (await _db).query(
      'walk_match',
      where: 'walk_id = ? AND network_version = ?',
      whereArgs: [walkId, networkVersion],
    );
    return rows.isEmpty ? null : rows.single['fingerprint'] as String;
  }

  @override
  Future<void> replaceWalkMatch(
    int walkId,
    String networkVersion,
    String fingerprint,
    Set<int> edges,
  ) async {
    final db = await _db;
    await db.transaction((txn) async {
      final walk = await txn.query(
        'recorded_walk',
        where: 'id = ?',
        whereArgs: [walkId],
      );
      if (walk.isEmpty || walk.single['status'] == 'recording') {
        throw StateError('Only saved walks can contribute coverage');
      }
      // Replacement and membership validation are atomic: a bad result rolls
      // back to the previous match instead of deleting earned coverage.
      await txn.delete(
        'walk_match',
        where: 'walk_id = ? AND network_version = ?',
        whereArgs: [walkId, networkVersion],
      );
      await txn.insert('walk_match', {
        'walk_id': walkId,
        'network_version': networkVersion,
        'fingerprint': fingerprint,
      });
      final batch = txn.batch();
      for (final edge in edges) {
        batch.insert('walk_edge', {
          'walk_id': walkId,
          'network_version': networkVersion,
          'edge_id': edge,
        });
      }
      await batch.commit(noResult: true);
    });
  }

  @override
  Future<Map<int, int>> readCombinedCounts(List<String> versions) async {
    if (versions.isEmpty) return {};
    final placeholders = List.filled(versions.length, '?').join(',');
    final rows = await (await _db).rawQuery(
      'SELECT edge_id, COUNT(DISTINCT walk_id) AS count FROM walk_edge '
      'WHERE network_version IN ($placeholders) GROUP BY edge_id',
      versions,
    );
    return {for (final row in rows) row['edge_id'] as int: row['count'] as int};
  }

  @override
  Future<Map<int, int>> readCounts(String networkVersion) async {
    final rows = await (await _db).rawQuery(
      'SELECT edge_id, COUNT(*) AS count FROM walk_edge WHERE network_version = ? GROUP BY edge_id',
      [networkVersion],
    );
    return {for (final row in rows) row['edge_id'] as int: row['count'] as int};
  }

  @override
  Future<void> close() async {
    if (_opening != null) await (await _opening!).close();
  }
}
