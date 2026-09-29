import 'dart:ui';
import 'package:flutter/foundation.dart';
import '../geo/geo_core_ffi.dart';
import '../recording/saved_walk.dart';
import '../transfer/walk_codec.dart';

class WalkReviewResult {
  const WalkReviewResult(this.direct, this.inferred);
  final Set<int> direct;
  final Set<int> inferred;
}

WalkReviewResult _matchReview((List<String>, String, bool) input) {
  final geo = WanderlustGeo.open();
  final direct = <int>{}, inferred = <int>{};
  for (final network in input.$1) {
    final matcher = geo.loadNetwork(network);
    try {
      final result = matcher.matchGpx(input.$2, fillSmallGaps: input.$3);
      final estimates = result.inferred.toSet();
      direct.addAll(result.walked.where((id) => !estimates.contains(id)));
      inferred.addAll(estimates);
    } finally {
      matcher.dispose();
    }
  }
  return WalkReviewResult(direct, inferred.difference(direct));
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
