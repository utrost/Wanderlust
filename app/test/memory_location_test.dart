import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wanderlust/memories/memory.dart';
import 'package:wanderlust/memories/memory_location.dart';
import 'package:wanderlust/recording/walk_recorder.dart';
import 'package:wanderlust/recording/saved_walk.dart';
import 'package:wanderlust/screens/memories_screen.dart';
import 'recording_test.dart' show fix;
import 'memory_fakes.dart';

void main() {
  test('a fresh recording fix needs no extra GPS request', () async {
    final now = DateTime.now(), p = positionAt(fix(1), DateTime.now());
    expect(
      await locateMemory(
        current: () => p,
        now: () => now,
        authorize: () async => throw StateError('must not request'),
      ),
      p,
    );
  });
  test(
    'waits past stale and inaccurate readings and cancels its own subscription on success',
    () async {
      var cancelled = false;
      final source = StreamController<Position>(
        onCancel: () => cancelled = true,
      );
      final now = DateTime.now();
      final result = locateMemory(
        authorize: () async => null,
        positions: () => source.stream,
        now: () => now,
      );
      source.add(fix(1));
      source.add(
        positionAt(
          Position.fromMap({...fix(2).toJson(), 'accuracy': 140.0}),
          now,
        ),
      );
      final fresh = positionAt(fix(2), now);
      source.add(fresh);
      expect(await result, fresh);
      expect(cancelled, isTrue);
      await source.close();
    },
  );
  test(
    'timeout releases listener without stopping the recording listener',
    () async {
      final source = StreamController<Position>.broadcast();
      var recordingReadings = 0;
      final recording = source.stream.listen((_) => recordingReadings++);
      await expectLater(
        locateMemory(
          authorize: () async => null,
          positions: () => source.stream,
          timeout: const Duration(milliseconds: 10),
        ),
        throwsA(
          isA<MemoryLocationError>().having(
            (e) => e.message,
            'message',
            contains('No recent GPS fix'),
          ),
        ),
      );
      source.add(fix(1));
      await Future<void>.delayed(Duration.zero);
      expect(recordingReadings, 1);
      expect(source.hasListener, isTrue);
      await recording.cancel();
      await source.close();
    },
  );
  test(
    'disabled GPS and permission denial are explained before subscribing',
    () async {
      for (final problem in [
        RecorderError.locationServiceDisabled,
        RecorderError.permissionDenied,
      ]) {
        await expectLater(
          locateMemory(
            authorize: () async => problem,
            positions: () => throw StateError('must not subscribe'),
          ),
          throwsA(
            isA<MemoryLocationError>().having(
              (e) => e.message,
              'message',
              contains(
                problem == RecorderError.permissionDenied
                    ? 'permission'
                    : 'switched off',
              ),
            ),
          ),
        );
      }
    },
  );
  testWidgets(
    'failed location can be retried without losing note; successful pin persists',
    (tester) async {
      final store = FakeMemoryStore(), memory = WalkMemory.create();
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: MemoryEditor(
            store: store,
            memory: memory,
            isNew: true,
            locate: () async {
              if (++calls == 1) {
                throw const MemoryLocationError(
                  'Location is switched off. Turn on GPS, then retry.',
                );
              }
              return positionAt(fix(1), DateTime.now());
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'A quiet place');
      await tester.ensureVisible(find.text('Use current location'));
      await tester.tap(find.text('Use current location'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Location is switched off'), findsOneWidget);
      expect(find.text('A quiet place'), findsOneWidget);
      await tester.tap(find.text('Use current location'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Location attached'), findsOneWidget);
      await tester.tap(find.text('Save memory'));
      await tester.pumpAndSettle();
      expect((await store.read(memory.id, false))!.hasLocation, isTrue);
      expect((await store.read(memory.id, false))!.note, 'A quiet place');
    },
  );
}
