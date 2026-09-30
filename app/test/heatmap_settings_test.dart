import 'package:flutter/material.dart';
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
}
