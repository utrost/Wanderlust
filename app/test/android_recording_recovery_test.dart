import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanderlust/recording/walk_recorder.dart';

import 'recording_test.dart' show FakeLocation, MemoryStore, fix;

class RecoverableFakeLocation extends FakeLocation
    implements RecoverableLocationSource {
  int recoveries = 0;
  @override
  Future<void> recover() async => recoveries++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Android recorder renews the existing subscription after a stall',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final source = RecoverableFakeLocation();
      var now = fix(0).timestamp;
      final recorder = WalkRecorder(
        location: source,
        store: MemoryStore(),
        now: () => now,
      );
      await recorder.start();
      recorder.setForeground(false);
      now = now.add(const Duration(minutes: 2));
      recorder.setForeground(true); // Resume checks a stalled hidden session.
      await Future<void>.delayed(Duration.zero);
      expect(source.recoveries, 1);
      expect(source.stream.hasListener, isTrue);
      expect(recorder.isRecording, isTrue);
      expect(recorder.gpsDiagnostics['streamRestarts'], 1);
      await recorder.stop();
      expect(source.stream.hasListener, isFalse);
      recorder.dispose();
      await source.stream.close();
    },
  );

  test('device recovery uses Android channel and propagates failure', () async {
    const channel = MethodChannel('flutter.baseflow.com/geolocator_android');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (calls.length == 2) {
        throw PlatformException(code: 'recording_inactive');
      }
      return null;
    });
    final source = DeviceLocationSource();
    await source.recover();
    await expectLater(source.recover(), throwsA(isA<PlatformException>()));
    expect(calls, ['restartRecordingLocation', 'restartRecordingLocation']);
  });
}
