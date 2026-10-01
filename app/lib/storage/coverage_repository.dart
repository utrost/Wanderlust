import 'package:sqflite/sqflite.dart';

import '../coverage/coverage_store.dart';
import '../data/area_network.dart';
import 'app_database.dart';

class CoverageRepository implements CoverageStore {
  CoverageRepository(this.connection);
  final AppDatabase connection;
  Future<Database> get _db => connection.database;
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
}
