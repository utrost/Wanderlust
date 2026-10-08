import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wanderlust/recording/activity_type.dart';
import 'package:wanderlust/recording/walk_store.dart';
import 'package:wanderlust/recording/walk_distance.dart';
import 'package:wanderlust/settings/walk_preferences.dart';
import 'package:wanderlust/transfer/walk_codec.dart';
import 'package:wanderlust/screens/walk_review_screen.dart';
import 'package:wanderlust/review/walk_review.dart';
import 'recording_test.dart' show fix;

String rideGpx() =>
    '''<gpx xmlns="http://www.topografix.com/GPX/1/1" xmlns:wl="https://wanderlust.local/gpx/1"><trk><trkseg>
<trkpt lat="0" lon="0"><time>2026-10-04T10:00:00Z</time></trkpt>
<trkpt lat="0" lon="0.00027"><time>2026-10-04T10:00:05Z</time></trkpt>
<trkpt lat="0" lon="0.00054"><time>2026-10-04T10:00:10Z</time></trkpt>
</trkseg></trk><extensions><wl:activity>cycle</wl:activity></extensions></gpx>''';
void main() {
  sqfliteFfiInit();
  test(
    'mode survives journal recovery, preferences, backups and GPX; relabelling preserves fixes',
    () async {
      final dir = await Directory.systemTemp.createTemp('activity-');
      final store = SqliteWalkStore(
        factory: databaseFactoryFfi,
        databasePath: '${dir.path}/db',
      );
      try {
        final id = await store.begin(
          fix(0).timestamp,
          activity: WalkActivity.cycle,
        );
        await store.append(id, 0, fix(0));
        await store.append(id, 1, fix(5));
        await expectLater(
          store.setActivity((await store.walkUid(id))!, WalkActivity.walk),
          throwsStateError,
        );
        final original = (await store.recoverAndList()).single;
        expect(original.activity, WalkActivity.cycle);
        expect(
          WalkCodec.importGpx(WalkCodec.exportGpx(original)).activity,
          WalkActivity.cycle,
        );
        expect(
          WalkCodec.importBackup(
            WalkCodec.exportBackup([original]),
          ).single.activity,
          WalkActivity.cycle,
        );
        final before = (await store.listSummaries()).single;
        await store.setActivity(original.uid, WalkActivity.walk);
        final after = (await store.listSummaries()).single;
        expect(after.activity, WalkActivity.walk);
        expect(after.fingerprint, isNot(before.fingerprint));
        expect((await store.loadWalk(id)).traceKey, original.traceKey);
        expect(after.pointCount, before.pointCount);
        expect(after.uid, before.uid);
        await store.savePreferences(
          const WalkPreferences(activity: WalkActivity.cycle),
        );
        expect((await store.readPreferences()).activity, WalkActivity.cycle);
        expect(WalkPreferences.fromJson({}).activity, WalkActivity.walk);
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'cycle distance accepts riding speed while walking remains conservative',
    () {
      final w = WalkCodec.importGpx(rideGpx());
      final walking = WalkDistance(),
          cycling = WalkDistance(maxSpeed: WalkActivity.cycle.maxSpeed);
      for (final p in w.points) {
        walking.add(p);
        cycling.add(p);
      }
      expect(walking.meters, 0);
      expect(cycling.meters, closeTo(60, 1));
    },
  );
  testWidgets('saved activity selector persists and rematches cycle mode', (
    tester,
  ) async {
    final modes = <WalkActivity>[];
    WalkActivity? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: WalkReviewScreen(
          walk: WalkCodec.importGpx(rideGpx()).withActivity(WalkActivity.walk),
          saveActivity: (v) async {
            saved = v;
          },
          match: (_, w, _) async {
            modes.add(w.activity);
            return const WalkReviewResult({}, {});
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Optional activity label'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cycle'));
    await tester.pumpAndSettle();
    expect(saved, WalkActivity.cycle);
    expect(modes, [WalkActivity.walk, WalkActivity.cycle]);
    expect(find.text('Review journey'), findsOneWidget);
  });
}
