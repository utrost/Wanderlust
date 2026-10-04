import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wanderlust/recording/walk_store.dart';
import 'package:wanderlust/coverage/coverage_controller.dart';
import 'package:wanderlust/geo/geo_core_ffi.dart';
import 'package:wanderlust/transfer/walk_codec.dart';
import 'coverage_test.dart' show networkJson;
import 'recording_test.dart' show fix;

void main() {
  sqfliteFfiInit();
  test(
    'confirmation changes heatmap once, survives backup, and undo restores raw matching',
    () async {
      final dir = await Directory.systemTemp.createTemp('confirmed-gap-');
      final store = SqliteWalkStore(
        factory: databaseFactoryFfi,
        databasePath: '${dir.path}/db',
      );
      final coverage = CoverageController(
        store: store,
        loadNetwork: () async => networkJson(),
        loadWalk: store.loadWalk,
        match: (_, walks) async => [
          for (final _ in walks)
            const MatchResult(
              walked: [1],
              inferred: [],
              unmatched: [],
              gapsFilled: 0,
              gapsRejected: 0,
            ),
        ],
      );
      try {
        final id = await store.begin(fix(0).timestamp);
        await store.append(id, 0, fix(0));
        await store.append(id, 1, fix(5));
        await store.finish(id, fix(10).timestamp, 'completed');
        final walk = await store.loadWalk(id);
        final gpx = WalkCodec.exportGpx(walk);
        await coverage.synchronize(await store.listSummaries());
        expect(coverage.counts, {1: 1});
        await store.saveConfirmedSections(walk.uid, [1, 2, 2, 999]);
        await coverage.synchronize(await store.listSummaries());
        expect(coverage.counts, {1: 1, 2: 1});
        await coverage.synchronize(await store.listSummaries());
        expect(coverage.counts, {1: 1, 2: 1});
        final saved = await store.loadWalk(id);
        expect(WalkCodec.exportGpx(saved), gpx);
        final restored = WalkCodec.importBackup(
          WalkCodec.exportBackup([saved]),
        ).single;
        expect(restored.confirmedSections, [1, 2, 999]);
        final restoredStore = SqliteWalkStore(
          factory: databaseFactoryFfi,
          databasePath: '${dir.path}/restored',
        );
        try {
          await restoredStore.mergeWalks([restored]);
          expect((await restoredStore.listSaved()).single.confirmedSections, [
            1,
            2,
            999,
          ]);
        } finally {
          await restoredStore.close();
        }

        await store.saveConfirmedSections(walk.uid, []);
        await coverage.synchronize(await store.listSummaries());
        expect(coverage.counts, {1: 1});
      } finally {
        coverage.dispose();
        await coverage.settled;
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
