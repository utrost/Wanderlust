import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanderlust/recording/recording_battery.dart';
import 'package:wanderlust/screens/recording_battery_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('wanderlust/battery');
  late bool exempt, reviewed, grant, unavailable;
  late int requests, starts, settings;
  late String maker;
  Map<String, Object> state() => {
    'supported': true,
    'exempt': exempt,
    'reviewed': reviewed,
    'manufacturer': maker,
  };
  setUp(() {
    exempt = reviewed = unavailable = false;
    grant = true;
    requests = starts = settings = 0;
    maker = 'Google';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'status':
              return state();
            case 'markReviewed':
              reviewed = true;
              return null;
            case 'requestExemption':
              requests++;
              if (unavailable) throw PlatformException(code: 'unavailable');
              exempt = grant;
              return state();
            case 'openSettings':
              settings++;
              return true;
          }
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  Future<void> launch(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                if (await showRecordingBatterySetup(context)) starts++;
              },
              child: const Text('Record'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Record'));
    await tester.pumpAndSettle();
  }

  testWidgets('Not now starts recording and does not ask again', (
    tester,
  ) async {
    await launch(tester);
    expect(find.text('Keep recording when your screen is off'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(starts, 1);
    expect(requests, 0);
    expect(reviewed, isTrue);
    await tester.tap(find.text('Record'));
    await tester.pumpAndSettle();
    expect(starts, 2);
    expect(find.byType(Dialog), findsNothing);
  });
  testWidgets('granted exemption bypasses explanation without a request', (
    tester,
  ) async {
    exempt = true;
    await launch(tester);
    expect(starts, 1);
    expect(requests, 0);
    expect(find.byType(Dialog), findsNothing);
  });
  testWidgets('grant is checked and user continues explicitly', (tester) async {
    await launch(tester);
    await tester.tap(find.text('Allow reliable recording'));
    await tester.pumpAndSettle();
    expect(find.text('Android battery exemption is enabled.'), findsOneWidget);
    expect(starts, 0);
    await tester.tap(find.text('Continue to recording'));
    await tester.pumpAndSettle();
    expect(starts, 1);
    expect(requests, 1);
  });
  testWidgets('denial and unavailable dialog do not block recording', (
    tester,
  ) async {
    grant = false;
    await launch(tester);
    await tester.tap(find.text('Allow reliable recording'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Battery permission is still off.'),
      findsOneWidget,
    );
    unavailable = true;
    await tester.tap(find.text('Allow reliable recording'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('permission dialog is unavailable'),
      findsOneWidget,
    );
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(starts, 1);
  });
  testWidgets('dismissing setup does not start recording', (tester) async {
    await launch(tester);
    Navigator.of(tester.element(find.byType(RecordingBatterySetup))).pop();
    await tester.pumpAndSettle();
    expect(starts, 0);
  });
  testWidgets(
    'Honor help remains separate from Android grant, updates on resume',
    (tester) async {
      maker = 'HONOR';
      await launch(tester);
      expect(find.textContaining('Run in background'), findsOneWidget);
      await tester.ensureVisible(find.text('Open app launch settings'));
      await tester.tap(find.text('Open app launch settings'));
      await tester.pumpAndSettle();
      expect(settings, 1);
      exempt = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(
        find.text('Android battery exemption is enabled.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('cannot be checked or changed'),
        findsOneWidget,
      );
      expect(starts, 0);
    },
  );
  testWidgets('manual settings reopen after refusal and fit large text', (
    tester,
  ) async {
    reviewed = true;
    maker = 'HONOR';
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
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  showRecordingBatterySetup(context, beforeRecording: false),
              child: const Text('Battery setup'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Battery setup'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Done'));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });
  test(
    'unavailable platform is optional, not a recording requirement',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      expect(await const RecordingBattery().status(), isNull);
      await const RecordingBattery().markReviewed();
    },
  );
}
