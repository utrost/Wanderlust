import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wanderlust/coverage/coverage_controller.dart';
import 'package:wanderlust/geo/geo_core_ffi.dart';
import 'package:wanderlust/recording/walk_store.dart';
import 'coverage_test.dart' show networkJson;
import 'recording_test.dart' show fix;

void main() {
  sqfliteFfiInit();
  test(
    'later evidence replaces provisional coverage rather than accumulating mistakes',
    () async {
      final dir = await Directory.systemTemp.createTemp('sequence-live-');
      final store = SqliteWalkStore(
        factory: databaseFactoryFfi,
        databasePath: '${dir.path}/db',
      );
      var calls = 0;
      final c = CoverageController(
        store: store,
        loadNetwork: () async => networkJson(),
        liveInterval: Duration.zero,
        match: (_, _) async => [
          MatchResult(
            walked: ++calls == 1 ? [1] : [2],
            gapsFilled: 0,
            gapsRejected: 0,
          ),
        ],
      );
      try {
        final id = await store.begin(fix(0).timestamp);
        await store.append(id, 0, fix(0));
        await store.append(id, 1, fix(5));
        c.updateLive(await store.loadWalk(id));
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await c.settled;
        expect(c.displayCounts, {1: 1});
        await store.append(id, 2, fix(10));
        c.updateLive(await store.loadWalk(id));
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await c.settled;
        expect(c.displayCounts, {2: 1});
        expect(c.counts, isEmpty);
      } finally {
        c.dispose();
        await c.settled;
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
