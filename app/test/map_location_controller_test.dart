import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wanderlust/application/map_location_controller.dart';
import 'package:wanderlust/recording/saved_walk.dart';
import 'package:wanderlust/recording/walk_recorder.dart';

import 'recording_test.dart' show FakeLocation, MemoryStore, fix;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter.baseflow.com/geolocator');
  late FakeLocation source;
  late WalkRecorder recorder;
  setUp(() {
    source = FakeLocation();
    recorder = WalkRecorder(
      store: MemoryStore(),
      location: source,
      showElapsed: () => false,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'isLocationServiceEnabled') return true;
          if (call.method == 'checkPermission') return 2;
          fail(
            'Automatic centering must not request permissions: ${call.method}',
          );
        });
  });
  tearDown(() async {
    recorder.dispose();
    await source.stream.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  for (final hide in [false, true]) {
    test(
      'late GPS result respects ${hide ? 'hide/reopen' : 'browsing'} intent',
      () async {
        final pending = Completer<Position>();
        final requested = Completer<void>();
        final controller = MapLocationController(
          recorder: recorder,
          locate: () {
            requested.complete();
            return pending.future;
          },
        );
        addTearDown(controller.dispose);
        final task = controller.centerOnMe(automatic: true);
        await requested.future;
        if (hide) {
          controller.setVisible(false);
          controller.setVisible(true);
        } else {
          controller.browseMap();
        }
        final position = positionAt(fix(1), DateTime.now());
        pending.complete(position);
        await task;
        expect(controller.currentFix, position);
        expect(controller.centerRequest, 0);
        expect(controller.locating, isFalse);
      },
    );
  }

  test(
    'disposing while a fix is pending suppresses late notifications',
    () async {
      final pending = Completer<Position>();
      final requested = Completer<void>();
      final controller = MapLocationController(
        recorder: recorder,
        locate: () {
          requested.complete();
          return pending.future;
        },
      );
      var notifications = 0;
      controller.addListener(() => notifications++);
      final task = controller.centerOnMe(automatic: true);
      await requested.future;
      controller.dispose();
      final previous = notifications;
      pending.complete(positionAt(fix(1), DateTime.now()));
      await task;
      expect(notifications, previous);
    },
  );

  test(
    'recording centering waits for fresh GPS and consumes intent once',
    () async {
      final controller = MapLocationController(recorder: recorder);
      addTearDown(controller.dispose);
      await recorder.start();
      await controller.centerOnMe();
      source.stream.add(
        positionAt(fix(1), DateTime.now().subtract(const Duration(minutes: 1))),
      );
      await Future<void>.delayed(Duration.zero);
      controller.onRecordingChanged();
      expect(controller.centerRequest, 0);
      source.stream.add(positionAt(fix(2), DateTime.now()));
      await Future<void>.delayed(Duration.zero);
      controller.onRecordingChanged();
      controller.onRecordingChanged();
      expect(controller.centerRequest, 1);
      await recorder.stop();
    },
  );
}
