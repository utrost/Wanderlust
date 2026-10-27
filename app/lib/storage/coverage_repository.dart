import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
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
    implements
        CoverageStore,
        PersistentCoverageStore,
        BatchCoverageStore,
        BlockCacheStore {
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
      final rows = await tx.rawQuery(
        'SELECT DISTINCT walk_id, fingerprint FROM match_evidence',
      );
      final invalid = {
        for (final row in rows)
          if (expected[row['walk_id']] != null &&
              expected[row['walk_id']] != row['fingerprint'])
            row['walk_id'] as int,
      };
      final batch = tx.batch();
      for (final id in invalid) {
        batch.rawDelete(
          'DELETE FROM supported_section WHERE walk_id = ? AND network IN (SELECT network FROM match_evidence WHERE walk_id = ? AND fingerprint != ?)',
          [id, id, expected[id]],
        );
        batch.delete(
          'match_evidence',
          where: 'walk_id = ? AND fingerprint != ?',
          whereArgs: [id, expected[id]],
        );
      }
      await batch.commit(noResult: true);
    });
  }

  @override
  Future<Map<int, List<double>>> readWalkBoundsBatch(
    Map<int, String> traces,
  ) async {
    final rows = await (await _db).query('walk_bounds');
    return {
      for (final row in rows)
        if (traces[row['walk_id']] == row['fingerprint'] && row['bbox'] != null)
          row['walk_id'] as int: (jsonDecode(row['bbox'] as String) as List)
              .map((v) => (v as num).toDouble())
              .toList(),
    };
  }

  @override
  Future<Map<int, (StoredMatch, String?)>> readEvidenceBatch(
    String network, {
    List<int>? walks,
  }) async {
    final db = await _db;
    final result = <int, (StoredMatch, String?)>{};
    // Small batches also stay below SQLite's bind-variable limit.
    for (
      var start = 0;
      walks == null ? start == 0 : start < walks.length;
      start += 400
    ) {
      final ids = walks?.skip(start).take(400).toList();
      final filter = ids == null
          ? ''
          : 'AND e.walk_id IN (${List.filled(ids.length, '?').join(',')})';
      final rows = await db.rawQuery(
        'SELECT e.*, m.fingerprint AS display_fingerprint FROM match_evidence e '
        'LEFT JOIN walk_match m ON m.walk_id = e.walk_id AND m.network_version = e.network '
        'WHERE e.network = ? $filter',
        [network, ...?ids],
      );
      for (final r in rows) {
        result[r['walk_id'] as int] = (
          _decodeEvidence(r),
          r['display_fingerprint'] as String?,
        );
      }
    }
    return result;
  }

  StoredMatch _decodeEvidence(Map<String, Object?> r) => StoredMatch(
    r['fingerprint'] as String,
    (jsonDecode(r['supported'] as String) as List).cast<int>().toSet(),
    (jsonDecode(r['estimated'] as String) as List).cast<int>().toSet(),
    (jsonDecode(r['unmatched'] as String) as List).cast<int>(),
  );

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
          'SELECT COUNT(*) FROM block_cache WHERE complete = 1 AND revision = ?',
          [blockRevision],
        ),
      ) ??
      0;
  @override
  Future<bool> blocksPending() async {
    final db = await _db;
    final rows = await db.rawQuery(
      "SELECT EXISTS(SELECT 1 FROM offline_area WHERE indexed = 0) OR "
      "EXISTS(SELECT 1 FROM map_cell c LEFT JOIN analysis_stamp s ON s.cell = c.cell "
      "WHERE s.stamp IS NULL OR s.stamp NOT LIKE ?) AS pending",
      ['$blockRevision/true/%'],
    );
    return rows.single['pending'] == 1;
  }

  @override
  Future<void> saveBlocks(
    List<StreetBlock> blocks,
    Map<String, BlockProgress> progress,
    List<String> sources,
  ) async {
    final db = await _db;
    final encoded = await compute(_encodeDefinitions, blocks);
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
                  .map((n) => (n as num).toDouble())
                  .toList(),
            ),
      };
      final existing = <String, String>{};
      for (var start = 0; start < blocks.length; start += 400) {
        final ids = blocks.skip(start).take(400).map((b) => b.id).toList();
        final rows = await tx.rawQuery(
          'SELECT id, history FROM block_cache WHERE id IN (${List.filled(ids.length, '?').join(',')})',
          ids,
        );
        existing.addAll({
          for (final r in rows) r['id'] as String: r['history'] as String,
        });
      }
      final batch = tx.batch();
      for (var i = 0; i < blocks.length; i++) {
        final block = blocks[i], data = encoded[i];
        // Immutable definitions are not rewritten when only evidence changes.
        // Progress is reconciled against global supported evidence, not a window.
        if (existing[block.id] != data.$2) {
          final values = <String, Object?>{
            'id': block.id,
            'owner': MapCell.at(block.bounds.center).id,
            'revision': blockRevision,
            'geometry': data.$1,
            'complete': progress[block.id]?.complete == true ? 1 : 0,
            'history': data.$2,
            'dirty': 1,
            'west': block.bounds.left,
            'south': block.bounds.top,
            'east': block.bounds.right,
            'north': block.bounds.bottom,
          };
          batch.insert(
            'block_cache',
            values,
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          batch.update(
            'block_cache',
            values,
            where: 'id = ?',
            whereArgs: [block.id],
          );
          batch.delete(
            'block_section',
            where: 'block = ?',
            whereArgs: [block.id],
          );
          for (final id in {
            for (final e in block.boundary) ...e.evidence.keys,
          }) {
            batch.insert('block_section', {'block': block.id, 'section': id});
          }
        }
        for (final source in sources.where(
          (s) => footprints[s]?.overlaps(block.bounds.inflate(.0006)) ?? true,
        )) {
          batch.rawInsert(
            'INSERT OR IGNORE INTO block_source(block,source) SELECT ?,version FROM offline_area WHERE version = ?',
            [block.id, source],
          );
        }
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void>? _reconciling;
  @override
  Future<void> reconcileBlocks() => _reconciling ??= _reconcileBlocks()
      .whenComplete(() => _reconciling = null);

  Future<void> _reconcileBlocks() async {
    final db = await _db;
    while (true) {
      final updated = await db.transaction((tx) async {
        final rows = await tx.query(
          'block_cache',
          where: 'dirty = 1',
          orderBy: 'id',
          limit: 16,
        );
        if (rows.isEmpty) return false;
        final ids = rows.map((r) => r['id'] as String).toList();
        final supported = await tx.rawQuery(
          'SELECT DISTINCT s.section FROM supported_section s JOIN block_section b ON b.section = s.section '
          'WHERE b.block IN (${List.filled(ids.length, '?').join(',')})',
          ids,
        );
        final results = await compute(_reconcileBatch, (
          rows,
          supported.map((r) => r['section'] as int).toSet(),
        ));
        final batch = tx.batch();
        for (final e in results.entries) {
          batch.update(
            'block_cache',
            {'complete': e.value ? 1 : 0, 'dirty': 0},
            where: 'id = ?',
            whereArgs: [e.key],
          );
        }
        await batch.commit(noResult: true);
        return true;
      });
      if (!updated) return;
      // Yield between bounded transactions; writers cannot race a stale result.
      await Future<void>.delayed(Duration.zero);
    }
  }
}

List<(String, String)> _encodeDefinitions(List<StreetBlock> blocks) => [
  for (final block in blocks)
    (() {
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
      return (geometry, sha256.convert(utf8.encode(geometry)).toString());
    })(),
];

Map<String, bool> _reconcileBatch(
  (List<Map<String, Object?>>, Set<int>) input,
) => {
  for (final row in input.$1)
    row['id'] as String: (() {
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
      return blockProgress(
        StreetBlock(row['id'] as String, boundary),
        input.$2,
      ).complete;
    })(),
};
