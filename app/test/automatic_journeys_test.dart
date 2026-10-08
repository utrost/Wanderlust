import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanderlust/recording/saved_walk.dart';
import 'package:wanderlust/recording/activity_type.dart';
import 'package:wanderlust/recording/journey_motion.dart';
import 'package:wanderlust/recording/walk_distance.dart';
import 'package:wanderlust/review/walk_review.dart';
import 'package:wanderlust/screens/walk_review_screen.dart';
import 'package:wanderlust/widgets/area_map.dart';
import 'package:wanderlust/data/area_network.dart';
import 'package:wanderlust/maps/osm_network.dart';
import 'package:wanderlust/transfer/walk_codec.dart';
import 'walk_distance_test.dart' show point;
import 'coverage_test.dart' show networkJson;
import 'nearby_maps_test.dart' show smallOsm;

SavedWalk journey() => SavedWalk(
  1,
  DateTime.utc(2026),
  DateTime.utc(2026).add(const Duration(seconds: 31)),
  'completed',
  [
    point(0, 0),
    point(5, 5),
    point(10, 10),
    point(35, 13),
    point(60, 16),
    point(85, 19),
    point(160, 22),
    point(235, 25),
    point(310, 28),
    point(385, 31),
  ],
  activity: WalkActivity.auto,
  uid: '11111111111111111111111111111111',
);
void main() {
  test(
    'mixed movement is visible independently of labels and survives transfer',
    () {
      final w = journey();
      for (final label in WalkActivity.values) {
        final labelled = w.withActivity(label);
        expect(reliableJourneyPairs(labelled), {1, 2, 3, 4, 5, 6, 7, 8, 9});
        final xml = WalkCodec.exportGpx(labelled);
        expect(xml, contains('<wl:matching>auto</wl:matching>'));
        expect(WalkCodec.importGpx(xml).activity, label);
        expect(
          WalkCodec.importBackup(
            WalkCodec.exportBackup([labelled]),
          ).single.activity,
          label,
        );
      }
    },
  );
  test('online distance adapts without a manually selected mode', () {
    final d = WalkDistance(automatic: true);
    for (final p in journey().points) {
      d.add(p);
    }
    expect(d.meters, closeTo(385, 2));
  });
  test('outages and isolated spikes stay disconnected', () {
    final w = SavedWalk(1, DateTime.utc(2026), null, 'completed', [
      point(0, 0),
      point(5, 5),
      point(1000, 6),
      point(10, 7),
      point(15, 12),
      point(200, 90),
      point(205, 95),
    ]);
    expect(reliableJourneyPairs(w), {1, 4, 6});
    final d = WalkDistance(automatic: true);
    for (final p in w.points) {
      d.add(p);
    }
    expect(d.meters, lessThan(25));
  });
  test(
    'transport download adds cycle-only and rail geometry without changing old imports',
    () {
      final xml = smallOsm.replaceFirst(
        '</osm>',
        '<way id="12"><nd ref="1"/><nd ref="4"/><tag k="railway" v="tram"/></way><way id="13"><nd ref="3"/><nd ref="4"/><tag k="highway" v="cycleway"/></way></osm>',
      );
      final original = jsonDecode(
        OsmNetwork.normalize(
          xml,
          [8.79, 53.09, 8.81, 53.11],
          areaId: 'test',
          name: 'Test',
        ),
      );
      final broader = jsonDecode(
        OsmNetwork.normalize(
          xml,
          [8.79, 53.09, 8.81, 53.11],
          areaId: 'test',
          name: 'Test',
          includeTransport: true,
        ),
      );
      expect(
        original['features'].any((f) => f['properties']['osm_way_id'] == 12),
        isFalse,
      );
      expect(
        broader['features'].any(
          (f) =>
              f['properties']['railway'] == 'tram' &&
              f['properties']['highway'] == 'railway',
        ),
        isTrue,
      );
      expect(
        broader['features'].any((f) => f['properties']['osm_way_id'] == 13),
        isTrue,
      );
      expect(broader['wanderlust_network']['policy'], 'journey-transport-v1');
    },
  );
  testWidgets('review keeps unmatched movement visible with a downloaded map', (
    tester,
  ) async {
    final w = journey();
    await tester.pumpWidget(
      MaterialApp(
        home: WalkReviewScreen(
          walk: w,
          networks: [AreaNetwork.parse(networkJson())],
          match: (_, _, _) async => const WalkReviewResult(
            {},
            {},
            unmatched: {1, 2, 3, 4, 5, 6, 7, 8, 9},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final map = tester.widget<AreaMap>(find.byType(AreaMap));
    expect(map.unmatchedTrails.single.length, w.points.length);
    expect(map.trace, isEmpty);
  });
  test('native review preserves reliable unmatched vehicle movement', () async {
    final result = await matchWalkReview([networkJson()], journey(), false);
    expect(result.unmatched, isNotEmpty);
  }, skip: Platform.environment['WANDERLUST_NATIVE_TESTS'] != '1');
}
