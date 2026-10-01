import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wanderlust/recording/walk_store.dart';
import 'package:wanderlust/geo/matching_worker.dart';
import 'package:wanderlust/coverage/coverage_controller.dart';
import 'recording_test.dart' show fix;

void main() {
  test(
    'profile 365 daily walks and repeated Bremen matching',
    () async {
      sqfliteFfiInit();
      final dir = await Directory.systemTemp.createTemp('walking-profile-');
      final store = SqliteWalkStore(
        factory: databaseFactoryFfi,
        databasePath: '${dir.path}/db',
      );
      final worker = MatchingWorker();
      final watch = Stopwatch();
      try {
        await store.mergeWalks([
          for (var day = 0; day < 365; day++)
            SavedWalk(
              day,
              DateTime.utc(2026, 1, 1).add(Duration(days: day)),
              DateTime.utc(2026, 1, 1).add(Duration(days: day, hours: 1)),
              'completed',
              [for (var i = 0; i < 720; i++) fix(i * 5)],
              uid: day.toRadixString(16).padLeft(32, '0'),
            ),
        ]);
        await store.listSummaries(); // one-time backfill
        watch.start();
        final full = await store.listSaved();
        final eagerMs = watch.elapsedMilliseconds;
        expect(full.fold<int>(0, (n, w) => n + w.points.length), 262800);
        watch.reset();
        final summaries = await store.listSummaries();
        final summaryMs = watch.elapsedMilliseconds;
        expect(summaries.fold<int>(0, (n, w) => n + w.points.length), 0);
        final network = await File(
          'assets/geo/bremen-center.streets.geojson',
        ).readAsString();
        const gpx =
            '<gpx><trk><trkseg><trkpt lat="53.075" lon="8.807"><time>2026-01-01T00:00:00Z</time></trkpt></trkseg></trk></gpx>';
        watch.reset();
        for (var i = 0; i < 10; i++) {
          await matchBatchInBackground(network, [gpx]);
        }
        final freshMs = watch.elapsedMilliseconds;
        await worker.match(network, [gpx], fillSmallGaps: false);
        watch.reset();
        for (var i = 0; i < 10; i++) {
          await worker.match(network, [gpx], fillSmallGaps: false);
        }
        // ignore: avoid_print
        print(
          'PROFILE: 365 walks/262800 fixes: eager ${eagerMs}ms, summaries ${summaryMs}ms; 10 matches: fresh ${freshMs}ms, warm ${watch.elapsedMilliseconds}ms',
        );
      } finally {
        await worker.close();
        await store.close();
        await dir.delete(recursive: true);
      }
    },
    skip: Platform.environment['WANDERLUST_BENCHMARKS'] != '1',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
