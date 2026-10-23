import 'package:flutter/foundation.dart';
import 'dart:ui';
import '../blocks/block_store.dart';
import '../blocks/block_geometry.dart';
import '../blocks/block_progress.dart';
import '../maps/map_cells.dart';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';

import '../coverage/coverage_store.dart';
import '../data/area_network.dart';
import 'app_database.dart';

class CoverageRepository
    implements CoverageStore, PersistentCoverageStore, BlockCacheStore {
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
        whereArgs: [network.coverageVersion],
      );
      for (final source in network.sourceVersions) {
        await txn.rawInsert(
          'INSERT OR IGNORE INTO network_source(network,source) SELECT ?,version FROM offline_area WHERE version = ?',
          [network.coverageVersion, source],
        );
      }
      if (existing.isNotEmpty) return;
      await txn.insert('coverage_network', {
        'version': network.coverageVersion,
        'area_id': network.areaId,
      });
      final batch = txn.batch();
      for (final id in network.edgeIds) {
        batch.insert('coverage_edge', {
          'network_version': network.coverageVersion,
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
  Future<void> syncEvidenceFingerprints(Map<int, String> expected) async {
    await (await _db).transaction((tx) async {
      for (final e in expected.entries) {
        await tx.rawDelete(
          'DELETE FROM supported_section WHERE walk_id = ? AND network IN (SELECT network FROM match_evidence WHERE walk_id = ? AND fingerprint != ?)',
          [e.key, e.key, e.value],
        );
        await tx.delete(
          'match_evidence',
          where: 'walk_id = ? AND fingerprint != ?',
          whereArgs: [e.key, e.value],
        );
      }
    });
  }

  @override
  Future<StoredMatch?> readEvidence(int walk, String network) async {
    final rows = await (await _db).query(
      'match_evidence',
      where: 'walk_id = ? AND network = ?',
      whereArgs: [walk, network],
    );
    if (rows.isEmpty) return null;
    final r = rows.single;
    return StoredMatch(
      r['fingerprint'] as String,
      (jsonDecode(r['supported'] as String) as List).cast<int>().toSet(),
      (jsonDecode(r['estimated'] as String) as List).cast<int>().toSet(),
      (jsonDecode(r['unmatched'] as String) as List).cast<int>(),
    );
  }

  @override
  Future<void> writeEvidence(
    int walk,
    String network,
    StoredMatch result,
  ) async {
    final db = await _db;
    await db.transaction((tx) async {
      await tx.delete(
        'supported_section',
        where: 'walk_id = ? AND network = ?',
        whereArgs: [walk, network],
      );
      final batch = tx.batch();
      for (final section in result.supported) {
        batch.insert('supported_section', {
          'walk_id': walk,
          'network': network,
          'section': section,
        });
      }
      await batch.commit(noResult: true);
      await tx.insert('match_evidence', {
        'walk_id': walk,
        'network': network,
        'fingerprint': result.fingerprint,
        'supported': jsonEncode(result.supported.toList()),
        'estimated': jsonEncode(result.estimated.toList()),
        'unmatched': jsonEncode(result.unmatched),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  @override
  Future<List<double>?> readWalkBounds(int walk, String fingerprint) async {
    final rows = await (await _db).query(
      'walk_bounds',
      where: 'walk_id = ? AND fingerprint = ?',
      whereArgs: [walk, fingerprint],
    );
    return rows.isEmpty
        ? null
        : (jsonDecode(rows.single['bbox'] as String) as List)
              .cast<num>()
              .map((n) => n.toDouble())
              .toList();
  }

  @override
  Future<void> writeWalkBounds(
    int walk,
    String fingerprint,
    List<double> bounds,
  ) async {
    await (await _db).insert('walk_bounds', {
      'walk_id': walk,
      'fingerprint': fingerprint,
      'bbox': jsonEncode(bounds),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<BlockTopology?> readTopology(String key) async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT length(data) AS n FROM topology_cache WHERE key = ?',
      [key],
    );
    if (rows.isEmpty) return null;
    final text = StringBuffer();
    for (var i = 1; i <= (rows.single['n'] as int); i += 128 * 1024) {
      final part = await db.rawQuery(
        'SELECT substr(data,?,?) AS chunk FROM topology_cache WHERE key = ?',
        [i, 128 * 1024, key],
      );
      if (part.isEmpty) return null;
      text.write(part.single['chunk']);
    }
    await db.update(
      'topology_cache',
      {'used': DateTime.now().millisecondsSinceEpoch},
      where: 'key = ?',
      whereArgs: [key],
    );
    return compute(decodeBlockTopology, text.toString());
  }

  @override
  Future<void> writeTopology(String key, BlockTopology topology) async {
    final data = await compute(encodeBlockTopology, topology);
    final db = await _db;
    await db.insert('topology_cache', {
      'key': key,
      'data': data,
      'used': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await db.rawDelete(
      'DELETE FROM topology_cache WHERE key NOT IN (SELECT key FROM topology_cache ORDER BY used DESC LIMIT 64)',
    );
  }

  @override
  Future<Map<String, String>> analysisStamps() async => {
    for (final r in await (await _db).query('analysis_stamp'))
      r['cell'] as String: r['stamp'] as String,
  };
  @override
  Future<void> saveAnalysisStamp(String cell, String stamp) async {
    await (await _db).insert('analysis_stamp', {
      'cell': cell,
      'stamp': stamp,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<int> completedCount() async =>
      Sqflite.firstIntValue(
        await (await _db).rawQuery(
          'SELECT COUNT(*) FROM block_cache WHERE complete = 1',
        ),
      ) ??
      0;
  @override
  Future<void> saveBlocks(
    List<StreetBlock> blocks,
    Map<String, BlockProgress> progress,
    List<String> sources,
  ) async {
    final db = await _db;
    await db.transaction((tx) async {
      final areas = await tx.query(
        'offline_area',
        columns: ['version', 'bbox'],
      );
      final footprints = {
        for (final a in areas)
          if (a['bbox'] != null)
            a['version'] as String: geographicBounds(
              (jsonDecode(a['bbox'] as String) as List)
                  .cast<num>()
                  .map((n) => n.toDouble())
                  .toList(),
            ),
      };
      for (final block in blocks) {
        final geometry = jsonEncode([
          for (final e in block.boundary)
            {
              'points': [
                for (final p in e.points) [p.dx, p.dy],
              ],
              'length': e.length,
              'evidence': {
                for (final v in e.evidence.entries)
                  '${v.key}': [
                    for (final r in v.value) [r.$1, r.$2],
                  ],
              },
            },
        ]);
        await tx.insert('block_cache', {
          'id': block.id,
          'owner': MapCell.at(block.bounds.center).id,
          'revision': blockRevision,
          'geometry': geometry,
          'complete': progress[block.id]?.complete == true ? 1 : 0,
          'history': '',
          'west': block.bounds.left,
          'south': block.bounds.top,
          'east': block.bounds.right,
          'north': block.bounds.bottom,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        final sectionBatch = tx.batch();
        for (final id in {for (final e in block.boundary) ...e.evidence.keys}) {
          sectionBatch.insert('block_section', {
            'block': block.id,
            'section': id,
          });
        }
        await sectionBatch.commit(noResult: true);
        for (final source in sources.where(
          (s) => footprints[s]?.overlaps(block.bounds.inflate(.0006)) ?? true,
        )) {
          await tx.rawInsert(
            'INSERT OR IGNORE INTO block_source(block,source) SELECT ?,version FROM offline_area WHERE version = ?',
            [block.id, source],
          );
        }
      }
    });
  }

  @override
  Future<void> reconcileBlocks() async {
    final db = await _db;
    String after = '';
    // Stream definitions, never load the worldwide block collection into RAM.
    while (true) {
      final rows = await db.query(
        'block_cache',
        where: 'id > ? AND dirty = 1',
        whereArgs: [after],
        orderBy: 'id',
        limit: 1,
      );
      if (rows.isEmpty) break;
      final row = rows.single;
      after = row['id'] as String;
      final boundary = [
        for (final e in jsonDecode(row['geometry'] as String) as List)
          BlockBoundary(
            [
              for (final p in e['points'] as List)
                Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()),
            ],
            (e['length'] as num).toDouble(),
            {
              for (final entry in (e['evidence'] as Map).entries)
                int.parse(entry.key as String): [
                  for (final r in entry.value as List)
                    ((r[0] as num).toDouble(), (r[1] as num).toDouble()),
                ],
            },
          ),
      ];
      final ids = {for (final b in boundary) ...b.evidence.keys}.toList();
      final supported = <int>{};
      for (var start = 0; start < ids.length; start += 400) {
        final batch = ids.skip(start).take(400).toList();
        final found = await db.rawQuery(
          'SELECT DISTINCT section FROM supported_section WHERE section IN (${List.filled(batch.length, '?').join(',')})',
          batch,
        );
        supported.addAll(found.map((r) => r['section'] as int));
      }
      final progress = blockProgress(StreetBlock(after, boundary), supported);
      await db.update(
        'block_cache',
        {'complete': progress.complete ? 1 : 0, 'dirty': 0},
        where: 'id = ?',
        whereArgs: [after],
      );
    }
  }
}
