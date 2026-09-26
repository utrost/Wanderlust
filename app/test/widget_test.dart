import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'recording_test.dart' show fix;
import 'package:wanderlust/main.dart';

void main() {
  testWidgets('boots to the map screen with the area chrome', (tester) async {
    await tester.pumpWidget(const WanderlustApp());

    // The calm map chrome renders regardless of whether the native geo-core is
    // present (the FFI status resolves asynchronously and degrades gracefully).
    expect(find.text('Bremen center'), findsOneWidget);
    expect(find.text('Start walk'), findsOneWidget);
  });
  testWidgets('Center on me requests a one-off fix without starting a walk', (
    tester,
  ) async {
    const channel = MethodChannel('flutter.baseflow.com/geolocator');
    var requests = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      switch (call.method) {
        case 'isLocationServiceEnabled':
          return true;
        case 'checkPermission':
          return 2;
        case 'getCurrentPosition':
          requests++;
          return {
            ...fix(1).toJson(),
            'latitude': 53.0759058,
            'longitude': 8.8073262,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          };
        default:
          throw StateError(call.method);
      }
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const WanderlustApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Center on me'));
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(find.textContaining('±4 m'), findsOneWidget);
    expect(find.text('53.07591, 8.80733'), findsOneWidget);
    expect(find.text('Start walk'), findsOneWidget);
    expect(find.text('Stop'), findsNothing);
    expect(find.byTooltip('Show map area'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Center on me reports disabled GPS without creating a fake position',
    (tester) async {
      const channel = MethodChannel('flutter.baseflow.com/geolocator');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'isLocationServiceEnabled') return false;
        fail('Must not request a fix when GPS is disabled');
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(const WanderlustApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Center on me'));
      await tester.pumpAndSettle();
      expect(
        find.text('Turn on location to find your position.'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Your location'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
