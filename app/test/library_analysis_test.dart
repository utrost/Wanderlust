import 'dart:io';
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

void main() {
  sqfliteFfiInit();
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
