import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wanderlust/recording/location_watchdog.dart';
import 'package:wanderlust/recording/saved_walk.dart';
import 'recording_test.dart' show fix;

void main() {
  test(
    'stale stream retries once per minute, recovers, and stops on close',
    () async {
      var now = fix(0).timestamp;
      final streams = <StreamController<Position>>[];
      final received = <Position>[];
      var stale = false;
      final watcher = LocationWatchdog(
        open: () {
          final stream = StreamController<Position>.broadcast();
          streams.add(stream);
          return stream.stream;
        },
        onPoint: received.add,
        onStale: (v) => stale = v,
        now: () => now,
      )..start();
      expect(streams, hasLength(1));
      now = now.add(const Duration(seconds: 50));
      watcher.check();
      await Future<void>.delayed(Duration.zero);
      expect(stale, isTrue);
      expect(streams, hasLength(1));
      now = now.add(const Duration(seconds: 10));
      watcher.check();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(streams, hasLength(2));
      expect(streams.first.hasListener, isFalse);
      streams.last.add(fix(0));
      await Future<void>.delayed(Duration.zero);
      expect(stale, isTrue); // Cached position does not count as recovery.
      streams.last.add(positionAt(fix(1), now));
      await Future<void>.delayed(Duration.zero);
      expect(stale, isFalse);
      expect(received, hasLength(2));
      await watcher.close();
      now = now.add(const Duration(minutes: 5));
      watcher.check();
      await Future<void>.delayed(Duration.zero);
      expect(streams, hasLength(2));
      expect(streams.last.hasListener, isFalse);
      for (final stream in streams) {
        await stream.close();
      }
    },
  );
  test(
    'errors and synchronous open failures are retried without timers leaking',
    () async {
      var now = fix(0).timestamp, attempts = 0;
      var stale = false;
      final watcher = LocationWatchdog(
        open: () {
          attempts++;
          throw StateError('unavailable');
        },
        onPoint: (_) {},
        onStale: (v) => stale = v,
        now: () => now,
      )..start();
      expect(stale, isTrue);
      now = now.add(const Duration(minutes: 1));
      watcher.check();
      await Future<void>.delayed(Duration.zero);
      expect(attempts, 2);
      await watcher.close();
    },
  );
  test('stop during cancellation cannot open a replacement stream', () async {
    var now = fix(0).timestamp;
    var attempts = 0;
    final cancelled = Completer<void>();
    final stream = StreamController<Position>(onCancel: () => cancelled.future);
    final watcher = LocationWatchdog(
      open: () {
        attempts++;
        return stream.stream;
      },
      onPoint: (_) {},
      onStale: (_) {},
      now: () => now,
    )..start();
    now = now.add(const Duration(minutes: 1));
    watcher.check();
    final closing = watcher.close();
    cancelled.complete();
    await closing;
    expect(attempts, 1);
    await stream.close();
  });
}
