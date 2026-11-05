import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanderlust/diagnostics/map_diagnostics.dart';
import 'package:wanderlust/diagnostics/map_report_dialog.dart';
import 'package:wanderlust/screens/offline_maps_screen.dart';
import 'offline_maps_screen_test.dart' show MemoryAreas;
import 'nearby_maps_test.dart' show smallNetwork;
import 'recording_test.dart' show fix;
import 'walk_library_test.dart' show TestFiles;

void main() {
  testWidgets(
    'activation failure retains saved map and exposes a private report',
    (tester) async {
      final store = MemoryAreas();
      final logs = MapDiagnostics(metadata: () async => {'build': 'test'});
      await tester.pumpWidget(
        MaterialApp(
          home: OfflineMapsScreen(
            store: store,
            diagnostics: logs,
            position: fix(1),
            activeVersion: null,
            fetch: (_) async => smallNetwork(),
            onSelect: (_, __) async => throw PlatformException(
              code: 'native',
              message: 'Private Road 53.1, 8.8',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Download nearby map'));
      await tester.tap(find.text('Download nearby map'));
      await tester.pumpAndSettle();
      expect(store.maps.length, 1);
      expect(find.textContaining('Map saved, but'), findsOneWidget);
      expect(find.text('Details'), findsOneWidget);
      final report = await logs.report();
      expect(report, contains('activation'));
      expect(report, isNot(contains('Private Road')));
      expect(report, isNot(contains('53.1')));
      await tester.ensureVisible(find.text('Details'));
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(find.text('Copy report'), findsOneWidget);
      expect(find.text('Save report'), findsOneWidget);
    },
  );

  testWidgets(
    'copy and save report work; picker cancellation and failure are harmless',
    (tester) async {
      final logs = MapDiagnostics(metadata: () async => {});
      await logs.finish(
        MapAttempt('download')
          ..capture(StateError('secret'), StackTrace.current),
      );
      final files = TestFiles();
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showMapReports(context, logs, files: files),
                child: const Text('Reports'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Reports'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy report'));
      await tester.pumpAndSettle();
      expect(clipboard, contains('failed'));
      await tester.tap(find.text('Save report'));
      await tester.pumpAndSettle();
      expect(files.name, 'wanderlust-map-diagnostics.json');
      expect(utf8.decode(files.saved!), clipboard);
      files.cancelSave = true;
      await tester.tap(find.text('Save report'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      files.failSave = true;
      await tester.tap(find.text('Save report'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not save report. Use Copy report instead.'),
        findsOneWidget,
      );
    },
  );
}
