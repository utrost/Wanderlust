import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../geo/matching_session.dart';
import '../geo/coverage_resolution.dart';
import '../coverage/unmatched_trails.dart';
import '../recording/journey_motion.dart';
import '../recording/saved_walk.dart';
import '../transfer/walk_codec.dart';

class WalkReviewResult {
  const WalkReviewResult(
    this.direct,
    this.inferred, {
    this.unmatched = const {},
  });
  final Set<int> unmatched;
  final Set<int> direct;
  final Set<int> inferred;
}

Future<WalkReviewResult> _matchReview(
  (List<String>, String, bool) input,
) async {
  final session = MatchingSession();
  final direct = <int>{}, inferred = <int>{};
  final unmatched = <Set<int>>[];
  try {
    for (final network in input.$1) {
      final results = session.match(network, [
        input.$2,
      ], fillSmallGaps: input.$3);
      final result = (await resolveCoverageDisplay(network, [
        input.$2,
      ], results)).single;
      unmatched.add(result.unmatched.toSet());
      final estimates = result.inferred.toSet();
      direct.addAll(result.walked.where((id) => !estimates.contains(id)));
      inferred.addAll(estimates);
    }
    return WalkReviewResult(
      direct,
      inferred.difference(direct),
      unmatched: UnmatchedTrails.common(unmatched),
    );
  } finally {
    session.dispose();
  }
}

Future<WalkReviewResult> matchWalkReview(
  List<String> networks,
  SavedWalk walk,
  bool fill,
) => walk.points.isEmpty || networks.isEmpty
    ? Future.value(const WalkReviewResult({}, {}))
    : compute(_matchReview, (networks, WalkCodec.exportGpx(walk), fill));

/// Show actual readings without drawing invented lines over recording breaks.
List<List<Offset>> reviewTrace(SavedWalk walk) {
  final result = <List<Offset>>[];
  final breaks = walk.segmentStarts.toSet(), untimed = walk.untimed.toSet();
  for (var i = 0; i < walk.points.length; i++) {
    final p = walk.points[i];
    var split = i == 0 || breaks.contains(i);
    if (i > 0 && !untimed.contains(i) && !untimed.contains(i - 1)) {
      final dt = p.timestamp.difference(walk.points[i - 1].timestamp);
      split = split || dt > const Duration(seconds: 30) || dt <= Duration.zero;
    }
    if (split) result.add([]);
    result.last.add(Offset(p.longitude, p.latitude));
  }
  return result;
}

/// Safe route fallback when no street map is installed.
List<List<Offset>> reliableJourneyTrace(SavedWalk walk) =>
    UnmatchedTrails.fromIndices(walk, reliableJourneyPairs(walk));
