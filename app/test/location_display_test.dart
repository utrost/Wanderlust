import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wanderlust/data/area_network.dart';
import 'package:wanderlust/recording/walk_recorder.dart';
import 'package:wanderlust/widgets/area_map.dart';
import 'package:wanderlust/widgets/gps_hud.dart';

import 'coverage_test.dart' show networkJson;
import 'recording_test.dart' show FakeLocation, MemoryStore, fix;

void main() {
  test(
    'recorder exposes latest accepted fix and clears it for the next walk',
    () async {
      final source = FakeLocation();
      final recorder = WalkRecorder(location: source, store: MemoryStore());
      expect(recorder.latestPosition, isNull);
      await recorder.start();
      source.stream.add(fix(1));
      await Future<void>.delayed(Duration.zero);
      expect(recorder.latestPosition, fix(1));
      await recorder.stop();
      expect(recorder.latestPosition, fix(1));
      await recorder.start();
      expect(recorder.latestPosition, isNull);
      await recorder.stop();
      recorder.dispose();
      await source.stream.close();
    },
  );

  testWidgets(
    'GPS HUD distinguishes waiting, accuracy, stale and outside-area fixes',
    (tester) async {
      final network = AreaNetwork.parse(networkJson());
      Future<void> show(
        Position? point, {
        bool recording = true,
        int age = 0,
      }) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GpsHud(
              position: point,
              now: fix(1).timestamp.add(Duration(seconds: age)),
              recording: recording,
              locating: false,
              network: network,
            ),
          ),
        ),
      );
      await show(null);
      expect(find.text('Waiting for GPS…'), findsOneWidget);
      await show(null, recording: false);
      expect(find.text('GPS · tap Center on me'), findsOneWidget);
      await show(fix(1));
      expect(find.text('GPS · ±4 m · 0s ago'), findsOneWidget);
      expect(find.textContaining('53.07000'), findsOneWidget);
      await show(fix(1), age: 45);
      expect(find.text('Last fix · ±4 m · 45s ago'), findsOneWidget);
      expect(
        find.text('No recent fix · waiting for an update'),
        findsOneWidget,
      );
      final outside = Position.fromMap({...fix(1).toJson(), 'latitude': 52.0});
      await show(outside);
      expect(find.text('Outside selected offline map'), findsOneWidget);
      expect(fixAge(fix(1), fix(0).timestamp), Duration.zero);
    },
  );

  testWidgets('centering waits for GPS, keeps marker size, and resets to area', (
    tester,
  ) async {
    final network = AreaNetwork.parse(networkJson());
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Future<void> show(Position? point, {int center = 1, int area = 0}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AreaMap(
              network: network,
              counts: const {},
              position: point,
              centerRequest: center,
              areaRequest: area,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    LocationMarkerPainter marker() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter)
        .whereType<LocationMarkerPainter>()
        .single;
    await show(null);
    expect(find.bySemanticsLabel('Your location'), findsNothing);
    await show(fix(1));
    expect(
      (marker().center(const Size(400, 800)) - const Offset(200, 400)).distance,
      lessThan(0.001),
    );
    expect(marker().transform.getMaxScaleOnAxis(), 4);
    // A later fix moves the marker, but doesn't recenter behind the user's back.
    await show(fix(30));
    expect(
      (marker().center(const Size(400, 800)) - const Offset(200, 400)).distance,
      greaterThan(0.01),
    );
    await show(fix(30), center: 2);
    expect(
      (marker().center(const Size(400, 800)) - const Offset(200, 400)).distance,
      lessThan(0.001),
    );
    await show(fix(30), center: 2, area: 1);
    expect(marker().transform, Matrix4.identity());
    final outside = Position.fromMap({...fix(1).toJson(), 'latitude': 52.0});
    await show(outside, center: 3, area: 1);
    expect(
      (marker().center(const Size(400, 800)) - const Offset(200, 400)).distance,
      lessThan(0.001),
    );
    expect(tester.takeException(), isNull);
  });
}
