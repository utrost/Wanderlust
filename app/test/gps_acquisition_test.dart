import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wanderlust/geo/location_warmup.dart';
import 'package:wanderlust/recording/activity_type.dart';
import 'package:wanderlust/recording/gps_diagnostics.dart';
import 'package:wanderlust/recording/walk_recorder.dart';
import 'package:wanderlust/recording/walk_store.dart';
import 'package:wanderlust/settings/walk_preferences.dart';
import 'package:wanderlust/transfer/walk_codec.dart';
import 'recording_test.dart' show fix, FakeLocation;

void main() {
  sqfliteFfiInit();
  test(
    'sampling follows activity unless manually overridden; legacy choices survive',
    () {
      const automatic = WalkPreferences();
      expect(automatic.effectiveGpsInterval, 5);
      expect(
        automatic.copyWith(activity: WalkActivity.cycle).effectiveGpsInterval,
        2,
      );
      final manual = automatic.copyWith(
        gpsIntervalSeconds: 20,
        activity: WalkActivity.cycle,
      );
      expect(manual.effectiveGpsInterval, 20);
      expect(
        WalkPreferences.fromJson(manual.toJson()).effectiveGpsInterval,
        20,
      );
      expect(
        WalkPreferences.fromJson({
          'gpsIntervalSeconds': 10,
        }).effectiveGpsInterval,
        10,
      );
      expect(
        WalkPreferences.fromJson({
          'gpsIntervalSeconds': 5,
          'activity': 'cycle',
        }).effectiveGpsInterval,
        2,
      );
    },
  );
  test(
    'warm-up ignores cached fixes and ends after two distinct fresh good fixes',
    () async {
      final stream = StreamController<Position>();
      final seen = <Position>[];
      var now = fix(10).timestamp;
      final w = LocationWarmup(
        open: () => stream.stream,
        onFix: seen.add,
        now: () => now,
      );
      final done = w.start();
      stream.add(positionAt(fix(0), now.subtract(const Duration(minutes: 1))));
      stream.add(positionAt(fix(0), now));
      stream.add(
        positionAt(fix(0), now),
      ); // A duplicate does not settle the receiver.
      await Future<void>.delayed(Duration.zero);
      expect(stream.hasListener, isTrue);
      now = now.add(const Duration(seconds: 2));
      stream.add(positionAt(fix(2), now));
      await done;
      expect(seen, hasLength(3));
      expect(stream.hasListener, isFalse);
      await w.close();
      await stream.close();
    },
  );
  test(
    'warm-up timeout and explicit cancellation release their subscriptions',
    () async {
      for (final cancel in [false, true]) {
        final stream = StreamController<Position>();
        final w = LocationWarmup(
          open: () => stream.stream,
          onFix: (_) {},
          duration: const Duration(milliseconds: 10),
        );
        final done = w.start();
        if (cancel) await w.close();
        await done;
        expect(stream.hasListener, isFalse);
        await stream.close();
      }
    },
  );
  test(
    'diagnostics distinguish delayed delivery from GPS timestamp spacing',
    () {
      final d = GpsDiagnostics(
        requestedIntervalSeconds: 2,
        startedAt: fix(0).timestamp,
      );
      d.add(fix(0), fix(1).timestamp);
      d.add(fix(2), fix(9).timestamp);
      d.add(fix(4), fix(40).timestamp);
      d.restarts++;
      final m = d.snapshot();
      expect(m['receivedFixes'], 3);
      expect(m['meanFixIntervalMs'], 2000);
      expect(m['maxDeliveryIntervalMs'], 31000);
      expect(m['maxFixAgeMs'], 36000);
      expect(m['staleFixes'], 1);
      expect(m['streamRestarts'], 1);
      expect(m['firstFreshFixMs'], 1000);
      expect(
        m.keys.any((k) => k.contains('latitude') || k.contains('longitude')),
        false,
      );
    },
  );
  test(
    'recording persists diagnostics and backups retain them without changing raw trace',
    () async {
      final dir = await Directory.systemTemp.createTemp('gps-metrics-');
      final store = SqliteWalkStore(
        factory: databaseFactoryFfi,
        databasePath: '${dir.path}/db',
      );
      final location = FakeLocation();
      var now = fix(0).timestamp;
      final recorder = WalkRecorder(
        store: store,
        location: location,
        now: () => now,
        gpsInterval: () => 2,
      );
      try {
        await recorder.start();
        expect(recorder.locating, true);
        location.stream.add(fix(0));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(recorder.locating, false);
        now = fix(8).timestamp;
        location.stream.add(fix(2));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await recorder.stop();
        final walk = (await store.listSaved()).single;
        expect(walk.gpsDiagnostics['requestedIntervalSeconds'], 2);
        expect(walk.gpsDiagnostics['maxDeliveryIntervalMs'], 8000);
        final restored = WalkCodec.importBackup(
          WalkCodec.exportBackup([walk]),
        ).single;
        expect(restored.gpsDiagnostics, walk.gpsDiagnostics);
        expect(restored.traceKey, walk.traceKey);
        expect(
          walk.withActivity(WalkActivity.cycle).gpsDiagnostics,
          walk.gpsDiagnostics,
        );
        expect(
          (await store.listSummaries()).single.gpsDiagnostics,
          walk.gpsDiagnostics,
        );
      } finally {
        recorder.dispose();
        await location.stream.close();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await dir.delete(recursive: true);
      }
    },
  );
}
