import 'package:flutter_test/flutter_test.dart';
import 'package:wanderlust/recording/native_recording.dart';
import 'package:wanderlust/recording/walk_recorder.dart';
import 'package:wanderlust/recording/walk_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'recording_test.dart' show FakeLocation, MemoryStore, fix;

class NativeFake implements NativeRecordingBackend {
  bool active = false, running = false, failRead = false, failStop = false;
  int starts = 0, stops = 0, count = 0, pageSize = 2;
  int? resumed;
  List<int> segments = [];
  @override
  Future<void> start(
    String activity, {
    int? resumeId,
    int? intervalSeconds,
  }) async {
    starts++;
    resumed = resumeId;
    if (resumeId == null) {
      count = 0;
      segments = [];
    }
    active = running = true;
  }

  @override
  Future<void> stop(int walkId) async {
    if (failStop) throw StateError('storage');
    stops++;
    active = running = false;
  }

  @override
  Future<Map<String, dynamic>?> snapshot({int? walkId, int after = -1}) async {
    if (failRead) throw StateError('storage');
    if (!active && starts == 0) return null;
    final offset = walkId == 7 ? after + 1 : 0;
    return {
      'walkId': 7,
      'active': active,
      'running': running,
      'stale': false,
      'startedAt': fix(0).timestamp.toIso8601String(),
      'endedAt': active ? null : fix(count).timestamp.toIso8601String(),
      'activity': 'walk',
      'segments': segments,
      'meters': count * 4.0,
      'pointCount': count,
      'intervalSeconds': 3,
      'diagnostics': {'receivedFixes': count},
      'points': [
        for (var i = offset; i < count && i < offset + pageSize; i++)
          {'sequence': i, 'position': fix(i).toJson()},
      ],
    };
  }
}

Future<void> drain() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  test(
    'native service owns writes; foreground reattachment pages without duplicates',
    () async {
      final backend = NativeFake();
      final store = MemoryStore();
      final source = FakeLocation();
      final recorder = WalkRecorder(
        store: store,
        location: source,
        nativeRecording: backend,
      );
      expect(await recorder.start(), isTrue);
      expect(source.stream.hasListener, isFalse);
      expect(store.points, isEmpty);
      recorder.setForeground(false);
      backend.count = 7;
      recorder.setForeground(true);
      await drain();
      expect(recorder.pointCount, 7);
      expect(recorder.distanceMeters, 28);
      recorder.setForeground(true);
      await drain();
      expect(recorder.pointCount, 7);
      expect(backend.starts, 1);
      recorder.dispose();
      await drain();
      expect(backend.stops, 0);
      expect(backend.running, isTrue);
    },
  );

  test(
    'starting again clears the previous UI trace even if the native ID is reused',
    () async {
      final backend = NativeFake();
      final recorder = WalkRecorder(
        store: MemoryStore(),
        location: FakeLocation(),
        nativeRecording: backend,
      );
      await recorder.start();
      backend.count = 4;
      await recorder.stop();
      expect(recorder.pointCount, 4);
      expect(await recorder.start(), isTrue);
      expect(recorder.pointCount, 0);
      expect(recorder.distanceMeters, 0);
      recorder.dispose();
      await drain();
    },
  );

  test(
    'reopening attaches to running session without requesting permission or starting again',
    () async {
      final backend = NativeFake()
        ..active = true
        ..running = true
        ..count = 5;
      final source = FakeLocation()..error = RecorderError.permissionDenied;
      final recorder = WalkRecorder(
        store: MemoryStore(),
        location: source,
        nativeRecording: backend,
      );
      await recorder.initialize();
      expect(recorder.isRecording, isTrue);
      expect(recorder.pointCount, 5);
      expect(backend.starts, 0);
      recorder.dispose();
      await drain();
    },
  );

  test(
    'stopped process offers continuation of same walk and preserves segment breaks',
    () async {
      final backend = NativeFake()
        ..active = true
        ..count = 3;
      final recorder = WalkRecorder(
        store: MemoryStore(),
        location: FakeLocation(),
        nativeRecording: backend,
      );
      await recorder.initialize();
      expect(recorder.hasRecoverableWalk, isTrue);
      expect(recorder.isRecording, isFalse);
      expect(await recorder.start(), isTrue);
      expect(backend.resumed, 7);
      backend.segments = [3];
      backend.count = 5;
      recorder.setForeground(true);
      await drain();
      expect(recorder.recordingSnapshot!.segmentStarts, [3]);
      expect(recorder.toGpx().split('<trkseg>').length, 3);
      await recorder.stop();
      expect(recorder.hasRecoverableWalk, isFalse);
      recorder.dispose();
      await drain();
    },
  );

  test(
    'notification Stop is reflected on reopening and never starts a new walk',
    () async {
      final backend = NativeFake();
      final recorder = WalkRecorder(
        store: MemoryStore(),
        location: FakeLocation(),
        nativeRecording: backend,
      );
      await recorder.start();
      recorder.setForeground(false);
      backend.count = 6;
      await backend.stop(7);
      recorder.setForeground(true);
      await drain();
      expect(recorder.pointCount, 6);
      expect(recorder.isRecording, isFalse);
      expect(recorder.hasRecoverableWalk, isFalse);
      expect(backend.starts, 1);
      recorder.dispose();
      await drain();
    },
  );

  test(
    'read failures do not stop capture and failed Stop remains retryable',
    () async {
      final backend = NativeFake();
      final recorder = WalkRecorder(
        store: MemoryStore(),
        location: FakeLocation(),
        nativeRecording: backend,
      );
      await recorder.start();
      backend.failRead = true;
      recorder.setForeground(true);
      await drain();
      expect(backend.running, isTrue);
      expect(recorder.lastError, RecorderError.storageFailed);
      backend.failRead = false;
      backend.failStop = true;
      await recorder.stop();
      expect(recorder.needsSaveRetry, isTrue);
      backend.failStop = false;
      await recorder.retrySave();
      expect(recorder.needsSaveRetry, isFalse);
      expect(backend.running, isFalse);
      recorder.dispose();
      await drain();
    },
  );

  test('legacy recovery leaves native active journal untouched', () async {
    sqfliteFfiInit();
    final store = SqliteWalkStore(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final nativeId = await store.begin(fix(0).timestamp);
    final legacyId = await store.begin(fix(0).timestamp);
    await store.append(nativeId, 0, fix(1));
    await store.append(legacyId, 0, fix(1));
    final db = await store.database.database;
    await db.execute(
      'CREATE TABLE native_recording (walk_id INTEGER, active INTEGER)',
    );
    await db.insert('native_recording', {'walk_id': nativeId, 'active': 1});
    final summaries = await store.listSummaries(recover: true);
    expect(summaries.singleWhere((w) => w.id == nativeId).status, 'recording');
    expect(
      summaries.singleWhere((w) => w.id == legacyId).status,
      'interrupted',
    );
    await store.close();
  });
}
