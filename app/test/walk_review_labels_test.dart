import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanderlust/data/area_network.dart';
import 'package:wanderlust/maps/map_download.dart';
import 'package:wanderlust/maps/osm_network.dart';
import 'package:wanderlust/recording/saved_walk.dart';
import 'package:wanderlust/review/walk_review.dart';
import 'package:wanderlust/screens/walk_review_screen.dart';
import 'package:wanderlust/transfer/walk_codec.dart';
import 'package:wanderlust/widgets/area_map.dart';
import 'package:wanderlust/widgets/map_labels.dart';
import 'gap_interpolation_test.dart' show gapNetwork, gapGpx;
import 'nearby_maps_test.dart' show smallOsm;

void main() {
  testWidgets(
    'walks can be reviewed without any downloaded map or Bremen fallback',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: WalkReviewScreen(walk: WalkCodec.importGpx(gapGpx())),
        ),
      );
      await tester.pumpAndSettle();
      final map = tester.widget<AreaMap>(find.byType(AreaMap));
      expect(map.network.edges, isEmpty);
      expect(map.networks, isEmpty);
      expect(map.unmatchedTrails, isNotEmpty);
      expect(map.trace, isEmpty);
      expect(
        find.text('Part of this trace is outside your saved street maps.'),
        findsOneWidget,
      );
      expect(find.textContaining('could not load'), findsNothing);
    },
  );

  test(
    'native review distinguishes all inferred edges without mutating the walk',
    () async {
      final walk = WalkCodec.importGpx(gapGpx());
      final raw = WalkCodec.exportGpx(walk);
      final off = await matchWalkReview([gapNetwork()], walk, false);
      final on = await matchWalkReview(
        [gapNetwork(), gapNetwork()],
        walk,
        true,
      );
      expect(off.direct, {1, 3});
      expect(off.inferred, isEmpty);
      expect(on.direct, {1, 3});
      expect(on.inferred, {2});
      expect(WalkCodec.exportGpx(walk), raw);
    },
    skip: Platform.environment['WANDERLUST_NATIVE_TESTS'] != '1'
        ? 'Requires native library'
        : false,
  );

  test('raw overlay preserves segment boundaries and recording outages', () {
    final w = WalkCodec.importGpx(gapGpx());
    final broken = SavedWalk(
      1,
      w.startedAt,
      w.endedAt,
      w.status,
      w.points,
      segmentStarts: [3],
    );
    expect(reviewTrace(broken).map((s) => s.length), [3, 4]);
    final points = w.points.toList();
    points[3] = positionAt(
      points[3],
      points[3].timestamp.add(const Duration(minutes: 2)),
    );
    final outage = SavedWalk(1, w.startedAt, w.endedAt, w.status, points);
    expect(reviewTrace(outage).map((s) => s.length), [3, 1, 3]);
    expect(
      reviewTrace(SavedWalk(1, w.startedAt, null, 'completed', [])),
      isEmpty,
    );
  });

  testWidgets('review layers and gap preview are independent and retryable', (
    tester,
  ) async {
    final requests = <bool>[];
    var fail = false;
    await tester.pumpWidget(
      MaterialApp(
        home: WalkReviewScreen(
          walk: WalkCodec.importGpx(gapGpx()),
          networks: [AreaNetwork.parse(gapNetwork())],
          match: (_, __, fill) async {
            requests.add(fill);
            if (fail) throw StateError('matching');
            return WalkReviewResult({1, 3}, fill ? {2} : {});
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    AreaMap map() => tester.widget<AreaMap>(find.byType(AreaMap));
    expect(map().counts.keys, {1, 3});
    expect(map().trace, isEmpty);
    expect(map().inferred, isEmpty);
    await tester.tap(find.text('Preview gap filling'));
    await tester.pumpAndSettle();
    expect(requests, [false, true]);
    expect(map().counts.keys, {1, 2, 3});
    await tester.tap(find.text('GPS trace'));
    await tester.pumpAndSettle();
    expect(map().trace, isNotEmpty);
    await tester.tap(find.text('Route'));
    await tester.pumpAndSettle();
    expect(map().counts, isEmpty);
    expect(map().inferred, isEmpty);
    fail = true;
    await tester.tap(find.text('Preview gap filling'));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test(
    'place labels and area names use offline OSM data without changing graph ids',
    () {
      const bounds = [8.79, 53.09, 8.81, 53.11];
      final old = AreaNetwork.parse(
        OsmNetwork.normalize(
          smallOsm,
          bounds,
          areaId: 'test',
          name: 'Near 53.100, 8.800 · 4 × 4 km',
        ),
      );
      final xml = smallOsm.replaceFirst(
        '</osm>',
        '<node id="991" lon="8.8" lat="53.1"><tag k="place" v="suburb"/><tag k="name" v="Test neighbourhood"/></node></osm>',
      );
      final named = AreaNetwork.parse(
        OsmNetwork.normalize(
          xml,
          bounds,
          areaId: 'test',
          name: 'Near 53.100, 8.800 · 4 × 4 km',
        ),
      );
      expect(named.name, 'Around Test neighbourhood · 4 × 4 km');
      expect(named.places.single.name, 'Test neighbourhood');
      expect(named.edgeIds, old.edgeIds);
      expect(named.version, old.version);
      expect(
        AreaNetwork.parse(
          OsmNetwork.normalize(xml, bounds, areaId: 'test', name: 'My map'),
        ).name,
        'My map',
      );
      expect(NearbyArea.around(53.1, 8.8).query, contains('node["place"'));
      final malformed = jsonDecode(gapNetwork()) as Map<String, dynamic>;
      malformed['wanderlust_places'] = [
        {
          'name': 'Bad',
          'point': [999, 0],
        },
      ];
      expect(AreaNetwork.parse(jsonEncode(malformed)).places, isEmpty);
    },
  );

  testWidgets(
    'labels are deduplicated, separated, screen sized and zoom gated',
    (tester) async {
      final json = jsonDecode(gapNetwork()) as Map<String, dynamic>;
      for (final f in json['features'] as List) {
        (f['properties'] as Map)['name'] = 'Long street';
      }
      json['wanderlust_places'] = [
        {
          'name': 'Quiet park',
          'kind': 'park',
          'point': [0.0004, 0.0002],
        },
      ];
      final area = AreaNetwork.parse(jsonEncode(json));
      Offset project(Offset p) =>
          Offset(30 + p.dx * 500000, 150 - p.dy * 100000);
      final labels = layoutMapLabels(
        [area, area],
        const Size(600, 400),
        project,
        streets: true,
      );
      expect(labels.map((l) => l.text).toSet().length, labels.length);
      expect(
        labels.map((l) => l.text),
        containsAll(['Quiet park', 'Long street']),
      );
      for (var i = 0; i < labels.length; i++) {
        expect(labels[i].bounds.height, lessThan(30));
        for (var j = i + 1; j < labels.length; j++) {
          expect(
            labels[i].bounds.inflate(10).overlaps(labels[j].bounds),
            isFalse,
          );
        }
      }
      expect(
        layoutMapLabels(
          [area],
          const Size(600, 400),
          project,
          streets: false,
        ).every((l) => l.place),
        isTrue,
      );
      expect(
        layoutMapLabels(
          [area],
          const Size(600, 400),
          (_) => const Offset(-100, -100),
          streets: true,
        ),
        isEmpty,
      );
    },
  );
  testWidgets(
    'short named geometry legs still receive one readable street label',
    (tester) async {
      final json = jsonDecode(gapNetwork()) as Map<String, dynamic>;
      final feature = (json['features'] as List).first as Map;
      (feature['properties'] as Map)['name'] = 'Small Street';
      (feature['geometry'] as Map)['coordinates'] = [
        for (var i = 0; i <= 10; i++) [i * 3 / 111195, 0],
      ];
      final area = AreaNetwork.parse(jsonEncode(json));
      final labels = layoutMapLabels(
        [area],
        const Size(600, 400),
        (p) => Offset(50 + p.dx * 600000, 200),
        streets: true,
      );
      expect(labels.map((l) => l.text), contains('Small Street'));
    },
  );
}
