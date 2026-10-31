import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanderlust/transfer/backup_progress.dart';
import 'package:wanderlust/widgets/backup_progress_panel.dart';

void main() {
  test('estimates use measured stage work and reset between stages', () {
    var now = Duration.zero;
    final progress = BackupProgress(clock: () => now);
    progress.stage('Checking backup', total: 100, estimate: true);
    progress.update(25);
    expect(progress.remaining, isNull);
    now = const Duration(seconds: 4);
    expect(progress.remaining, const Duration(seconds: 12));
    progress.update(100);
    expect(progress.remaining, isNull);
    progress.stage('Preparing offline maps');
    now = const Duration(seconds: 14);
    expect(progress.fraction, isNull);
    expect(progress.remaining, isNull);
    expect(progress.elapsed, now);
    progress.stage('Restoring recordings', total: 10);
    progress.update(5);
    now = const Duration(seconds: 30);
    // Recordings can differ enormously in size; do not extrapolate their count.
    expect(progress.remaining, isNull);
  });

  test(
    'stream counts consumed records, not failed or merely yielded ones',
    () async {
      final progress = BackupProgress();
      Stream<int> source() async* {
        yield 1;
        yield 2;
        throw const FormatException('broken record');
      }

      await expectLater(() async {
        var consumed = 0;
        await for (final item in progress.track(source(), 'Restoring', 3)) {
          expect(progress.completed, consumed);
          expect(item, ++consumed);
        }
      }(), throwsFormatException);
      expect(progress.completed, 2);
      expect(progress.fraction, closeTo(2 / 3, .001));
    },
  );

  testWidgets('elapsed time advances during waiting and fits enlarged text', (
    tester,
  ) async {
    var now = Duration.zero;
    final progress = BackupProgress(clock: () => now)..canCancel = false;
    progress.stage('Preparing offline maps', detail: 'Your backup is saved.');
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: SingleChildScrollView(
              child: BackupProgressPanel(progress: progress),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Elapsed 0s'), findsOneWidget);
    now = const Duration(seconds: 65);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Elapsed 1m 5s'), findsOneWidget);
    expect(find.textContaining('Time remaining depends'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      isNull,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });
}
