import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanderlust/screens/about_screen.dart';
import 'package:wanderlust/screens/settings_screen.dart';
import 'package:wanderlust/settings/walk_preferences.dart';

void main() {
  testWidgets('Privacy is readable offline from About', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AboutScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Privacy'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Wanderlust privacy policy'), findsOneWidget);
    expect(find.textContaining('device transfer'), findsOneWidget);
  });
  testWidgets(
    'Settings opens About with installed version and offline licence',
    (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('wanderlust/about'),
        (call) async => '0.0.1 (build 1021)',
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('wanderlust/about'),
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            initial: const WalkPreferences(),
            save: (_) async {},
            diagnostic: const Text('Ready'),
          ),
        ),
      );
      await tester.scrollUntilVisible(find.text('About Wanderlust'), 400);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('About Wanderlust'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('About Wanderlust'));
      await tester.pumpAndSettle();
      expect(find.text('Uwe Trostheide'), findsOneWidget);
      expect(find.text('0.0.1 (build 1021)'), findsOneWidget);
      await tester.tap(find.text('App licence'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('GNU AFFERO GENERAL PUBLIC LICENSE'),
        findsOneWidget,
      );
    },
  );

  testWidgets('About works without platform version bridge', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AboutScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Development build'), findsOneWidget);
    await tester.tap(find.text('Open-source licences'));
    for (var i = 0; i < 20; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pumpAndSettle();
    expect(find.text('chrono 0.4.45 (Rust)'), findsOneWidget);
    await tester.tap(find.text('chrono 0.4.45 (Rust)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Permission is hereby granted'), findsWidgets);
  });

  test(
    'bundled native notices include every enabled third-party crate',
    () async {
      final entries =
          jsonDecode(File('assets/legal/rust-licenses.json').readAsStringSync())
              as List;
      expect(
        entries.map((e) => e['name']),
        containsAll([
          'autocfg',
          'chrono',
          'num-traits',
          'roxmltree',
          'memchr',
          'serde_json',
          'serde_core',
          'itoa',
          'zmij',
        ]),
      );
      expect(entries.every((e) => (e['text'] as String).length > 100), isTrue);
    },
  );
}
