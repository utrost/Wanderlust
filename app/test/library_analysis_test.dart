import 'dart:io';
import 'package:wanderlust/maps/map_cells.dart';
import 'active_maps_test.dart' show nearby;
import 'recording_test.dart' show fix;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wanderlust/blocks/block_geometry.dart';
import 'package:wanderlust/maps/active_maps.dart';
import 'package:wanderlust/maps/library_analysis.dart';
import 'package:wanderlust/recording/walk_store.dart';
import 'package:wanderlust/settings/walk_preferences.dart';
import 'blocks_test.dart' show network, square;

class TransientStore extends SqliteWalkStore {
  TransientStore(String path)
    : super(factory: databaseFactoryFfi, databasePath: path);
  bool fail = true;
  int writes = 0;
  final cellsRead = <String>[];
  @override
  Future<String?> readCell(String cell) {
    cellsRead.add(cell);
    return super.readCell(cell);
  }

  @override
  Future<void> writeTopology(String key, BlockTopology topology) async {
    writes++;
    if (fail) {
      fail = false;
      throw StateError('database is locked');
    }
    await super.writeTopology(key, topology);
  }
}

class AtCapacityMaps extends ActiveMaps {
  AtCapacityMaps(super.store);
  @override
  bool reserveProcessing(int bytes, int sections) =>
      bytes == 0 && sections == 0;
}

void main() {
  sqfliteFfiInit();
  test(
    'analysis completes at capacity by reusing the exact loaded cell',
    () async {
      final dir = await Directory.systemTemp.createTemp('library-capacity-');
      final store = TransientStore('${dir.path}/db')..fail = false;
      final active = AtCapacityMaps(store);
      final analysis = LibraryAnalysis(
        active: active,
        store: store,
        cache: store,
        loadWalk: store.loadWalk,
        walks: () => [],
        preferences: () => const WalkPreferences(completeBlocks: true),
        canRun: () => true,
        onUpdated: () async {},
      );
      try {
        await store.saveArea(network(square()).geojson);
        await active.refresh();
        expect(active.networks, isNotEmpty);
        store.cellsRead.clear();
        analysis.schedule();
        await Future<void>.delayed(const Duration(milliseconds: 700));
        await analysis.settled;
        expect(analysis.error, isNull);
        expect(analysis.remaining, 0);
        expect(store.cellsRead, isEmpty);
        final sources = await store.listCells();
        final cell = sources.first;
        expect(
          active.loadedCell(cell.cell, [
            CellSource(
              cell.cell,
              'different-revision',
              cell.bytes,
              cell.sections,
            ),
          ]),
          isNull,
        );
      } finally {
        analysis.dispose();
        active.dispose();
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'adding and deleting a local walk leaves distant analysis and topology unchanged',
    () async {
      final dir = await Directory.systemTemp.createTemp('library-local-');
      final store = TransientStore('${dir.path}/db')..fail = false;
      final active = ActiveMaps(store);
      List<SavedWalk> history = [];
      final analysis = LibraryAnalysis(
        active: active,
        store: store,
        cache: store,
        loadWalk: store.loadWalk,
        walks: () => history,
        preferences: () => const WalkPreferences(completeBlocks: true),
        canRun: () => true,
        onUpdated: () async {},
      );
      Future<void> run() async {
        analysis.schedule();
        await Future<void>.delayed(const Duration(milliseconds: 700));
        await analysis.settled;
        expect(analysis.error, isNull, reason: analysis.lastFailure.toString());
        expect(analysis.remaining, 0);
      }

      try {
        await store.saveArea(network(square()).geojson);
        await store.saveArea(nearby('far', const Offset(8.8, 53.1)));
        await active.refresh();
        await run();
        final initial = await store.analysisStamps();
        final topologyWrites = store.writes;
        final id = await store.begin(fix(0).timestamp);
        await store.finish(id, fix(1).timestamp, 'completed');
        history = await store.listSummaries();
        await store.writeWalkBounds(id, history.single.fingerprint!, [
          0,
          0,
          .001,
          .001,
        ]);
        store.cellsRead.clear();
        await run();
        final after = await store.analysisStamps();
        final changed = {
          for (final e in after.entries)
            if (initial[e.key] != e.value) e.key,
        };
        expect(changed, isNotEmpty);
        expect(store.cellsRead.every(changed.contains), isTrue);
        expect(
          changed.every((c) => MapCell.parse(c).bounds.center.dy.abs() < 1),
          true,
        );
        expect(
          store.writes,
          topologyWrites,
          reason: 'new evidence reuses immutable topology',
        );
        for (final e in initial.entries.where(
          (e) => !changed.contains(e.key),
        )) {
          expect(after[e.key], e.value);
        }
        store.cellsRead.clear();
        await run();
        expect(
          store.cellsRead,
          isEmpty,
          reason: 'unchanged reopening performs no cell analysis',
        );
        await (await store.database.database).delete(
          'walk_match',
          where: 'walk_id = ?',
          whereArgs: [id],
        );
        await (await store.database.database).delete(
          'recorded_walk',
          where: 'id = ?',
          whereArgs: [id],
        );
        history = [];
        await run();
        expect(store.cellsRead.every(changed.contains), isTrue);
        expect(await store.analysisStamps(), initial);
      } finally {
        analysis.dispose();
        active.dispose();
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'failed cell retries automatically; successful cells survive and gestures pause work',
    () async {
      final dir = await Directory.systemTemp.createTemp('library-retry-');
      final store = TransientStore('${dir.path}/db');
      final active = ActiveMaps(store);
      var updates = 0;
      final analysis = LibraryAnalysis(
        active: active,
        store: store,
        cache: store,
        loadWalk: store.loadWalk,
        walks: () => [],
        preferences: () => const WalkPreferences(completeBlocks: true),
        canRun: () => true,
        onUpdated: () async {
          updates++;
        },
      );
      try {
        await store.saveArea(network(square()).geojson);
        await active.refresh();
        active.gestureStarted();
        analysis.schedule();
        await Future<void>.delayed(const Duration(milliseconds: 700));
        expect(store.writes, 0);
        active.gesturing = false;
        analysis.schedule();
        await Future<void>.delayed(const Duration(milliseconds: 700));
        await analysis.settled;
        expect(analysis.lastFailure.toString(), contains('database is locked'));
        expect(analysis.remaining, 1);
        final stamps = await store.analysisStamps();
        expect(stamps.length, greaterThan(1));
        expect(await store.blocksPending(), true);
        // No user action is needed to trigger the bounded retry timer.
        await Future<void>.delayed(const Duration(seconds: 6));
        await analysis.settled;
        expect(analysis.error, isNull);
        expect(analysis.remaining, 0);
        expect(await store.blocksPending(), false);
        final after = await store.analysisStamps();
        for (final e in stamps.entries) {
          expect(after[e.key], e.value);
        }
        expect(updates, greaterThan(1));
      } finally {
        analysis.dispose();
        active.dispose();
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
