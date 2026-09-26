import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wanderlust/recording/walk_recorder.dart';
import 'package:wanderlust/recording/walk_store.dart';

Position fix(int seconds) => Position(
    longitude: 8.8 + seconds * 0.00001,
    latitude: 53.07,
    timestamp: DateTime.utc(2026, 7, 11, 9, 0, seconds),
    accuracy: 4,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0);

class FakeLocation implements LocationSource {
  final stream = StreamController<Position>.broadcast();
  Completer<RecorderError?>? authorization;
  RecorderError? error;
  @override
  Future<RecorderError?> authorize() async =>
      authorization == null ? error : await authorization!.future;
  @override
  Stream<Position> positions() => stream.stream;
}

class MemoryStore implements WalkStore {
  int nextId = 0;
  final points = <int, List<Position>>{};
  final starts = <int, DateTime>{};
  final statuses = <int, String>{};
  bool failAppend = false;
  @override
  Future<int> begin(DateTime start) async {
    final id = ++nextId;
    starts[id] = start;
    points[id] = [];
    statuses[id] = 'recording';
    return id;
  }

  @override
  Future<void> append(int id, int sequence, Position point) async {
    if (failAppend) throw StateError('disk full');
    if (sequence < points[id]!.length) {
      points[id]![sequence] = point;
    } else {
      points[id]!.add(point);
    }
  }

  @override
  Future<void> finish(int id, DateTime end, String status) async {
    statuses[id] = status;
  }

  @override
  Future<List<SavedWalk>> recoverAndList() async => [
        for (final id in points.keys)
          SavedWalk(id, starts[id]!, null, statuses[id]!, points[id]!)
      ];
  @override
  Future<void> close() async {}
}

void main() {
  test('overlapping starts authorize and create only one walk', () async {
    final source = FakeLocation()..authorization = Completer();
    final store = MemoryStore();
    final recorder = WalkRecorder(location: source, store: store);
    final first = recorder.start();
    expect(await recorder.start(), isFalse);
    source.authorization!.complete(null);
    expect(await first, isTrue);
    expect(store.nextId, 1);
    await recorder.stop();
    recorder.dispose();
    await source.stream.close();
  });

  test('stop freezes elapsed, drains writes, and preserves GPX metadata',
      () async {
    final source = FakeLocation();
    final store = MemoryStore();
    var now = DateTime.utc(2026, 7, 11, 9);
    final recorder =
        WalkRecorder(location: source, store: store, now: () => now);
    await recorder.start();
    source.stream.add(fix(1));
    source.stream.add(fix(5));
    await Future<void>.delayed(Duration.zero);
    now = now.add(const Duration(seconds: 10));
    await recorder.stop();
    now = now.add(const Duration(minutes: 1));
    expect(recorder.elapsed, const Duration(seconds: 10));
    expect(store.points[1], hasLength(2));
    expect(recorder.toGpx(), contains('<time>2026-07-11T09:00:01.000Z</time>'));
    expect(recorder.toGpx(), contains('<wl:accuracy>4.0</wl:accuracy>'));
    recorder.dispose();
    await source.stream.close();
  });

  for (final diskFailure in [false, true]) {
    test('${diskFailure ? 'storage' : 'GPS'} failure stops safely', () async {
      final source = FakeLocation();
      final store = MemoryStore()..failAppend = diskFailure;
      final recorder = WalkRecorder(location: source, store: store);
      await recorder.start();
      if (diskFailure) {
        source.stream.add(fix(1));
      } else {
        source.stream.addError(StateError('GPS gone'));
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(recorder.state, RecorderState.idle);
      expect(
          recorder.lastError,
          diskFailure
              ? RecorderError.storageFailed
              : RecorderError.locationFailed);
      expect(store.statuses[1], 'interrupted');
      recorder.dispose();
      await source.stream.close();
    });
  }

  test('failed save retains trace and retries without duplicating points',
      () async {
    final source = FakeLocation();
    final store = MemoryStore();
    final recorder = WalkRecorder(location: source, store: store);
    await recorder.start();
    source.stream.add(fix(1));
    await Future<void>.delayed(Duration.zero);
    store.failAppend = true;
    source.stream.add(fix(2));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(recorder.needsSaveRetry, isTrue);
    expect(await recorder.start(), isFalse);
    expect(recorder.pointCount, 2);
    store.failAppend = false;
    await recorder.retrySave();
    expect(store.points[1], hasLength(2));
    expect(recorder.needsSaveRetry, isFalse);
    expect(await recorder.start(), isTrue);
    await recorder.stop();
    expect(store.points[1], hasLength(2));
    recorder.dispose();
    await source.stream.close();
  });

  test('stream completion retains a recoverable interrupted walk', () async {
    final source = FakeLocation();
    final store = MemoryStore();
    final recorder = WalkRecorder(location: source, store: store);
    await recorder.start();
    source.stream.add(fix(1));
    await source.stream.close();
    await Future<void>.delayed(Duration.zero);
    expect(recorder.state, RecorderState.idle);
    expect(store.statuses[1], 'interrupted');
    expect(store.points[1], hasLength(1));
    recorder.dispose();
  });

  test('disposing during permission request never starts GPS or creates a walk',
      () async {
    final source = FakeLocation()..authorization = Completer();
    final store = MemoryStore();
    final recorder = WalkRecorder(location: source, store: store);
    final starting = recorder.start();
    await Future<void>.delayed(Duration.zero);
    recorder.dispose();
    source.authorization!.complete(null);
    expect(await starting, isFalse);
    expect(store.nextId, 0);
    await source.stream.close();
  });

  test('permission denial creates no session and can be retried', () async {
    final source = FakeLocation()..error = RecorderError.permissionDenied;
    final store = MemoryStore();
    final recorder = WalkRecorder(location: source, store: store);
    expect(await recorder.start(), isFalse);
    expect(store.nextId, 0);
    source.error = null;
    expect(await recorder.start(), isTrue);
    await recorder.stop();
    recorder.dispose();
    await source.stream.close();
  });

  test('new walk retains previous saved walk', () async {
    final source = FakeLocation();
    final store = MemoryStore();
    final recorder = WalkRecorder(location: source, store: store);
    await recorder.start();
    source.stream.add(fix(1));
    await Future<void>.delayed(Duration.zero);
    await recorder.stop();
    // A fresh source stream is needed after canceling a single-subscription stream.
    recorder.dispose();
    await source.stream.close();
    final nextSource = FakeLocation();
    final next = WalkRecorder(location: nextSource, store: store);
    await next.start();
    await next.stop();
    expect(store.points[1], hasLength(1));
    expect(store.points, hasLength(2));
    next.dispose();
    await nextSource.stream.close();
  });
}
