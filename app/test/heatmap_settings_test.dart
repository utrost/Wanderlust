import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wanderlust/screens/map_screen.dart';
import 'package:wanderlust/widgets/heatmap_legend.dart';
import 'widget_test.dart' show BootStore;
import 'coverage_test.dart' show networkJson;
import 'package:flutter_test/flutter_test.dart';
import 'package:wanderlust/screens/settings_screen.dart';
import 'package:wanderlust/settings/walk_preferences.dart';
import 'package:wanderlust/theme/heat_ramp.dart';

void main() {
  test(
    'old preferences keep names on; off survives persistence and other edits',
    () {
      expect(WalkPreferences.fromJson({}).showStreetNames, isTrue);
      final saved = WalkPreferences.fromJson(
        const WalkPreferences().copyWith(showStreetNames: false).toJson(),
      );
      expect(saved.showStreetNames, isFalse);
      expect(saved.copyWith(showGps: true).showStreetNames, isFalse);
    },
  );
  testWidgets('street-name switch saves and heatmap key explains counts', (
    tester,
  ) async {
    WalkPreferences? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          initial: const WalkPreferences(),
          save: (value) async {
            saved = value;
          },
          diagnostic: const Text('Ready'),
        ),
      ),
    );
    await tester.scrollUntilVisible(find.text('Show street names'), 200);
    await tester.tap(find.text('Show street names'));
    await tester.pumpAndSettle();
    expect(saved!.showStreetNames, isFalse);
    final tile = tester.widget<SwitchListTile>(
      find.ancestor(
        of: find.text('Show street names'),
        matching: find.byType(SwitchListTile),
      ),
    );
    expect(tile.value, isFalse);
    await tester.scrollUntilVisible(find.text('Your walking heatmap'), 150);
    expect(
      find.textContaining('A section counts once per walk'),
      findsOneWidget,
    );
  });
  test('repeat walks become progressively darker on the light map', () {
    var previous = HeatRamp.color(0, dark: false).computeLuminance();
    for (final visits in [1, 2, 5, 20, 100, 1000]) {
      final current = HeatRamp.color(visits, dark: false).computeLuminance();
      expect(current, lessThan(previous));
      previous = current;
    }
    expect(
      HeatRamp.color(1001, dark: false),
      HeatRamp.color(1000, dark: false),
    );
  });
  test('early repeat visits have clearly separated luminance', () {
    var previous = HeatRamp.color(1, dark: false).computeLuminance();
    for (final count in [2, 5, 10]) {
      final current = HeatRamp.color(count, dark: false).computeLuminance();
      // A regression floor for visible relative separation, not a WCAG claim.
      expect(
        (previous + 0.05) / (current + 0.05),
        greaterThan(1.4),
        reason: '$count walks',
      );
      previous = current;
    }
    var light = HeatRamp.color(0, dark: false).computeLuminance();
    var dark = HeatRamp.color(0, dark: true).computeLuminance();
    for (final count in [1, 2, 3, 5, 10, 20, 50, 100, 500, 1000]) {
      final nextLight = HeatRamp.color(count, dark: false).computeLuminance();
      final nextDark = HeatRamp.color(count, dark: true).computeLuminance();
      expect(nextLight, lessThan(light));
      expect(nextDark, greaterThan(dark));
      light = nextLight;
      dark = nextDark;
    }
  });

  testWidgets('map legend opens on tap and scrolls at large text sizes', (
    tester,
  ) async {
    const channel = MethodChannel('flutter.baseflow.com/geolocator');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'isLocationServiceEnabled' ? false : 0,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.8)),
          child: child!,
        ),
        home: MapScreen(store: BootStore(source: networkJson())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(HeatmapLegend), findsNothing);
    await tester.tap(
      find.byTooltip('Heatmap legend · Street sections explored'),
    );
    await tester.pumpAndSettle();
    expect(find.byType(HeatmapLegend), findsOneWidget);
    expect(find.text('2 walks'), findsOneWidget);
    expect(find.text('10 walks'), findsOneWidget);
    await tester.ensureVisible(
      find.textContaining('A section counts once per walk'),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
