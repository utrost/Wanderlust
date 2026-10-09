import 'saved_walk.dart';

/// Describes observed recording continuity, never street-matching confidence.
class RecordingHealth {
  const RecordingHealth(this.title, this.detail, {this.hasGaps = false});
  final String title, detail;
  final bool hasGaps;

  factory RecordingHealth.fromWalk(SavedWalk walk) {
    if (walk.isSummary || walk.points.length < 2 || walk.untimed.isNotEmpty) {
      return const RecordingHealth(
        'Recording quality unknown',
        'Not enough timestamped GPS fixes to assess continuity.',
      );
    }
    var missing = Duration.zero;
    var breaks = walk.segmentStarts.where((i) => i > 0).isNotEmpty;
    final times = [
      walk.startedAt,
      ...walk.points.map((p) => p.timestamp),
      if (walk.endedAt != null) walk.endedAt!,
    ];
    for (var i = 1; i < times.length; i++) {
      final gap = times[i].difference(times[i - 1]);
      if (gap.isNegative) breaks = true;
      if (gap > const Duration(seconds: 30)) missing += gap;
    }
    if (missing > Duration.zero) {
      final minutes = (missing.inSeconds / 60).ceil();
      return RecordingHealth(
        'GPS gaps · about $minutes min',
        'Total time across intervals longer than 30 seconds without a saved fix. Your recorded sections are safe.',
        hasGaps: true,
      );
    }
    if (breaks || walk.status == 'interrupted' || walk.endedAt == null) {
      return const RecordingHealth(
        'Recording has breaks',
        'The recording was interrupted or contains separate track sections.',
        hasGaps: true,
      );
    }
    final poor = walk.points.any(
      (p) => !p.accuracy.isFinite || p.accuracy > 50,
    );
    return RecordingHealth(
      'Recorded continuously',
      'No gaps longer than 30 seconds.${poor ? ' Some fixes had low accuracy.' : ' Street matching may still be uncertain.'}',
    );
  }
}
