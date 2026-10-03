import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wanderlust/recording/walk_store.dart';
import 'package:wanderlust/transfer/walk_codec.dart';
import 'package:wanderlust/coverage/coverage_controller.dart';
import 'package:wanderlust/geo/geo_core_ffi.dart';
import 'coverage_test.dart' show networkJson;
import 'transfer_test.dart' show segmentedGpx;

void main() {
  sqfliteFfiInit();
  test(
    'summaries persist fingerprints and fetch full traces only when matching is pending',
    () async {
      final dir = await Directory.systemTemp.createTemp('summary-test-');
      final store = SqliteWalkStore(
        factory: databaseFactoryFfi,
        databasePath: '${dir.path}/db',
      );
      var loads = 0;
      final coverage = CoverageController(
        store: store,
        loadNetwork: () async => networkJson(),
        loadWalk: (id) {
          loads++;
          return store.loadWalk(id);
        },
        match: (_, walks) async => [
          for (final _ in walks)
            const MatchResult(walked: [], gapsFilled: 0, gapsRejected: 0),
        ],
      );
      try {
        await store.mergeWalks([WalkCodec.importGpx(segmentedGpx)]);
        final summary = (await store.listSummaries()).single;
        expect(summary.points, isEmpty);
        expect(summary.pointCount, greaterThan(0));
        expect(summary.fingerprint, hasLength(64));
        expect(() => WalkCodec.exportGpx(summary), throwsStateError);
        await coverage.synchronize([summary]);
        expect(loads, 1);
        await coverage.synchronize(await store.listSummaries());
        expect(loads, 1);
        await store.setFavourite(summary.uid, true);
        expect(
          (await store.listSummaries()).single.fingerprint,
          summary.fingerprint,
        );
        await coverage.setFillSmallGaps(true, await store.listSummaries());
        expect(loads, 2);
      } finally {
        coverage.dispose();
        await coverage.settled;
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
