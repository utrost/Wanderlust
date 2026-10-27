import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wanderlust/blocks/block_geometry.dart';
import 'package:wanderlust/blocks/block_progress.dart';
import 'package:wanderlust/coverage/coverage_store.dart';
import 'package:wanderlust/storage/app_database.dart';
import 'package:wanderlust/recording/walk_store.dart';
import 'blocks_test.dart' show square, network;
import 'recording_test.dart' show fix;

void main() {
  sqfliteFfiInit();

  test(
    'algorithm upgrade removes obsolete parents and resumes partial rebuilding',
    () async {
      final dir = await Directory.systemTemp.createTemp('block-revision-');
      final path = '${dir.path}/db';
      var store = SqliteWalkStore(
        factory: databaseFactoryFfi,
        databasePath: path,
      );
      try {
        final map = network(square());
        await store.saveArea(map.geojson);
        while (await store.indexNext(null)) {}
        final block = buildBlockTopology([map]).blocks.single;
        await store.saveBlocks(
          [block],
          {
            block.id: blockProgress(block, {1, 2, 3, 4}),
          },
          ['test'],
        );
        await store.writeTopology('old', BlockTopology([block]));
        final db = await store.database.database;
        await db.update('block_cache', {'revision': 'old-revision'});
        await store.saveAnalysisStamp('__block_revision__', 'old-revision');
        await store.saveAnalysisStamp('old-cell', 'old-stamp');
        await store.close();
        store = SqliteWalkStore(
          factory: databaseFactoryFfi,
          databasePath: path,
        );
        expect(await store.completedCount(), 0);
        expect(await store.readTopology('old'), isNull);
        expect(await store.blocksPending(), true);
        expect((await store.database.database).path, path);
        expect(
          await (await store.database.database).query('block_cache'),
          isEmpty,
        );
        expect((await store.listAreas()).length, 1);
        final cells = (await store.listCells())
            .map((e) => e.cell)
            .toSet()
            .toList();
        await store.saveAnalysisStamp(
          cells.first,
          '$blockRevision/true/current',
        );
        await store.close();
        store = SqliteWalkStore(
          factory: databaseFactoryFfi,
          databasePath: path,
        );
        expect(
          (await store.analysisStamps())[cells.first],
          '$blockRevision/true/current',
        );
        for (final cell in cells.skip(1)) {
          await store.saveAnalysisStamp(cell, '$blockRevision/true/current');
        }
        expect(await store.blocksPending(), false);
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'version-one upgrade retains raw maps and recordings, indexes stay rebuildable',
    () async {
      final dir = await Directory.systemTemp.createTemp('map-migration-');
      final path = '${dir.path}/db';
      final original = network(square()).geojson;
      final old = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute(
              'PRAGMA application_id = ${AppDatabase.applicationId}',
            );
            await db.execute(
              'CREATE TABLE offline_area(version TEXT PRIMARY KEY,name TEXT,geojson TEXT,downloaded_at TEXT,bytes INTEGER)',
            );
            await db.execute(
              'CREATE TABLE recorded_walk(id INTEGER PRIMARY KEY,fingerprint TEXT,trace_metadata TEXT)',
            );
            await db.insert('offline_area', {
              'version': 'test',
              'name': 'Test',
              'geojson': original,
              'downloaded_at': '2026-01-01',
              'bytes': original.length,
            });
            await db.insert('recorded_walk', {
              'id': 1,
              'fingerprint': 'keep',
              'trace_metadata': '{}',
            });
          },
        ),
      );
      await old.close();
      final upgraded = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: path,
      );
      try {
        final db = await upgraded.database;
        expect(await db.getVersion(), 2);
        expect((await db.query('offline_area')).single['geojson'], original);
        expect((await db.query('recorded_walk')).single['fingerprint'], 'keep');
        expect((await db.query('offline_area')).single['indexed'], 0);
        expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      } finally {
        await upgraded.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'supported evidence, blocks and topology survive restart; deletion revokes completion',
    () async {
      final dir = await Directory.systemTemp.createTemp('block-cache-');
      final path = '${dir.path}/db';
      var store = SqliteWalkStore(
        factory: databaseFactoryFfi,
        databasePath: path,
      );
      final map = network(square());
      final topology = buildBlockTopology([map]);
      final block = topology.blocks.single;
      try {
        await store.saveArea(map.geojson);
        final id = await store.begin(fix(0).timestamp);
        await store.finish(id, fix(1).timestamp, 'completed');
        await store.writeEvidence(
          id,
          map.version,
          const StoredMatch('fp', {1, 2, 3, 4}, {}, []),
        );
        await store.saveBlocks(
          [block],
          {
            block.id: blockProgress(block, {1, 2, 3, 4}),
          },
          ['test'],
        );
        await store.reconcileBlocks();
        await store.writeTopology('topology', topology);
        expect(await store.completedCount(), 1);
        final beforeChanges = (await (await store.database.database).rawQuery(
          'SELECT total_changes() AS n',
        )).single['n'];
        await store.saveBlocks([block], {block.id: blockProgress(block, {})}, [
          'test',
        ]);
        await store.reconcileBlocks();
        expect(
          await store.completedCount(),
          1,
          reason: 'a partial window cannot overwrite global progress',
        );
        expect(
          (await (await store.database.database).rawQuery(
            'SELECT total_changes() AS n',
          )).single['n'],
          beforeChanges,
          reason: 'unchanged definitions and clean progress perform no writes',
        );
        await store.close();
        store = SqliteWalkStore(
          factory: databaseFactoryFfi,
          databasePath: path,
        );
        expect(await store.completedCount(), 1);
        expect(
          (await store.readTopology('topology'))!.blocks.single.id,
          block.id,
        );
        expect((await store.readEvidence(id, map.version))!.supported, {
          1,
          2,
          3,
          4,
        });
        // Repeated travel and inferred-only sections cannot turn into extra awards.
        await store.writeEvidence(
          id,
          map.version,
          const StoredMatch('fp', {1, 2, 3}, {4}, []),
        );
        await store.reconcileBlocks();
        expect(await store.completedCount(), 0);
        await store.writeEvidence(
          id,
          map.version,
          const StoredMatch('fp', {1, 2, 3, 4}, {}, []),
        );
        await store.reconcileBlocks();
        expect(await store.completedCount(), 1);
        final db = await store.database.database;
        await db.delete('recorded_walk', where: 'id = ?', whereArgs: [id]);
        await store.reconcileBlocks();
        expect(await store.completedCount(), 0);
        expect(await store.readEvidence(id, map.version), isNull);
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
