import 'package:wanderlust/coverage/coverage_controller.dart';
import 'package:wanderlust/widgets/route_update_notice.dart';
import 'package:wanderlust/screens/walk_review_screen.dart';
import 'package:wanderlust/review/walk_review.dart';
import 'widget_test.dart' show BootStore;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanderlust/recording/saved_walk.dart';
import 'package:wanderlust/recording/recording_health.dart';
import 'package:wanderlust/widgets/map_compass.dart';
import 'package:wanderlust/screens/memories_screen.dart';
import 'package:wanderlust/screens/memory_view_screen.dart';
import 'package:wanderlust/memories/memory.dart';
import 'memory_fakes.dart';
import 'walk_distance_test.dart' show point;

SavedWalk walk(
  List<int> seconds, {
  List<int> untimed = const [],
  List<int> breaks = const [],
  int start = 0,
  int? end,
}) => SavedWalk(
  1,
  point(0, start).timestamp,
  point(0, end ?? seconds.last).timestamp,
  'completed',
  [for (final s in seconds) point(s.toDouble(), s)],
  untimed: untimed,
  segmentStarts: breaks,
);

class SignalCoverage extends CoverageController {
  SignalCoverage() : super(store: BootStore());
  void update({bool working = false, bool success = false, bool fail = false}) {
    rematching = working;
    error = fail ? const CoverageFailure('Test failure', 'Test') : null;
    if (success) routeUpdateRevision++;
    notifyListeners();
  }
}

void main() {
  test(
    'health separates continuity, actual gaps, initial delay and untimed imports',
    () {
      expect(
        RecordingHealth.fromWalk(walk([0, 3, 6])).title,
        'Recorded continuously',
      );
      expect(
        RecordingHealth.fromWalk(walk([0, 3, 93, 96])).title,
        'GPS gaps · about 2 min',
      );
      expect(
        RecordingHealth.fromWalk(walk([60, 63], end: 123)).title,
        'GPS gaps · about 2 min',
      );
      expect(
        RecordingHealth.fromWalk(walk([0, 3], breaks: [1])).hasGaps,
        isTrue,
      );
      expect(
        RecordingHealth.fromWalk(walk([0, 3], untimed: [1])).title,
        'Recording quality unknown',
      );
      expect(RecordingHealth.fromWalk(walk([5, 3])).hasGaps, isTrue);
    },
  );

  testWidgets(
    'compass crosses north by short arc and reports unreliable readings',
    (tester) async {
      final events = StreamController<dynamic>.broadcast();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MapCompass(events: events.stream)),
        ),
      );
      events.add({'available': true, 'heading': 359, 'accuracy': 3});
      await tester.pump();
      final before = tester
          .widget<AnimatedRotation>(find.byType(AnimatedRotation))
          .turns;
      events.add({'available': true, 'heading': 1, 'accuracy': 3});
      await tester.pump();
      final after = tester
          .widget<AnimatedRotation>(find.byType(AnimatedRotation))
          .turns;
      expect(after - before, closeTo(2 / 360, 0.0001));
      events.add({'available': true, 'heading': 5, 'accuracy': 0});
      await tester.pump();
      expect(
        find.byTooltip(
          'Compass needs calibration. Move your phone in a figure eight.',
        ),
        findsOneWidget,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(events.hasListener, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(events.hasListener, isTrue);
      await tester.pumpWidget(const SizedBox());
      await events.close();
    },
  );

  testWidgets(
    'saved memories open reader, swipe, and edit',
    (tester) async {
      final store = FakeMemoryStore();
      for (final title in ['A quiet bench', 'Evening light']) {
        await store.put(
          WalkMemory.create().copyWith(note: title, draft: false),
        );
      }
      await tester.pumpWidget(MaterialApp(home: MemoriesScreen(store: store)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A quiet bench'));
      await tester.pumpAndSettle();
      expect(find.byType(MemoryViewScreen), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await tester.drag(find.byType(PageView), const Offset(-650, 0));
      await tester.pumpAndSettle();
      expect(find.text('2 of 2'), findsOneWidget);
      await tester.tap(find.byTooltip('Edit memory'));
      await tester.pumpAndSettle();
      expect(find.byType(MemoryEditor), findsOneWidget);
      expect(find.text('Evening light'), findsOneWidget);
    },
  );
  testWidgets(
    'route update notice completes, dismisses, and never calls failure success',
    (tester) async {
      final coverage = SignalCoverage();
      var retried = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RouteUpdateNotice(
              coverage: coverage,
              onRetry: () => retried = true,
            ),
          ),
        ),
      );
      coverage.update(working: true);
      await tester.pump();
      expect(find.text('Updating saved routes…'), findsOneWidget);
      coverage.update(success: true);
      await tester.pumpAndSettle();
      expect(find.text('Saved routes updated'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('Saved routes updated'), findsNothing);
      coverage.update(fail: true);
      await tester.pumpAndSettle();
      expect(find.text('Saved routes updated'), findsNothing);
      await tester.tap(find.text('Retry'));
      expect(retried, isTrue);
      await tester.pumpWidget(const SizedBox());
      coverage.dispose();
    },
  );

  testWidgets('review health and memory cards remain usable with large text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: WalkReviewScreen(
          walk: walk([0, 3, 6]),
          match: (_, _, _) async => const WalkReviewResult({}, {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recorded continuously'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final store = FakeMemoryStore();
    await store.put(
      WalkMemory.create().copyWith(
        note: 'A long memory with a peaceful view across the river',
        draft: false,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: MemoriesScreen(store: store),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
