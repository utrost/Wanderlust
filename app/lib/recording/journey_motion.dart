import 'dart:math' as math;
import 'package:geolocator/geolocator.dart';
import 'saved_walk.dart';

double journeyDistance(Position a, Position b) => Geolocator.distanceBetween(
  a.latitude,
  a.longitude,
  b.latitude,
  b.longitude,
);
double? journeySpeed(Position a, Position b) {
  final seconds = b.timestamp.difference(a.timestamp).inMilliseconds / 1000;
  if (seconds <= 0 ||
      seconds > 30 ||
      !a.accuracy.isFinite ||
      !b.accuracy.isFinite ||
      a.accuracy < 0 ||
      b.accuracy < 0 ||
      a.accuracy > 25 ||
      b.accuracy > 25) {
    return null;
  }
  return journeyDistance(a, b) / seconds;
}

/// Online distance waits for a trustworthy speed hint or consecutive compatible
/// movement before accepting fast travel. A single jump does not raise the limit.
double journeySpeedLimit(Position? prior, Position a, Position b) {
  final v = journeySpeed(a, b);
  if (v == null) return 3;
  if (b.speed.isFinite &&
      b.speed >= 0.7 &&
      (b.speed - v).abs() <= math.max(2, b.speed * 0.5)) {
    return (b.speed * 1.8 + 2).clamp(3, 70);
  }
  if (prior != null) {
    final previous = journeySpeed(prior, a);
    final cos = math.cos(a.latitude * math.pi / 180);
    final x = (a.longitude - prior.longitude) * cos,
        y = a.latitude - prior.latitude;
    final dx = (b.longitude - a.longitude) * cos, dy = b.latitude - a.latitude;
    if (previous != null &&
        previous > 2.5 &&
        v >= previous * 0.4 &&
        v <= previous * 2.5 &&
        x * dx + y * dy > 0) {
      return (math.max(v, previous) * 1.8 + 2).clamp(3, 70);
    }
  }
  return 3;
}

/// Same bounded local evidence as automatic native matching, for mapless display.
Set<int> reliableJourneyPairs(SavedWalk walk) {
  final points = walk.points,
      breaks = walk.segmentStarts.toSet(),
      untimed = walk.untimed.toSet();
  final spikes = <int>{};
  for (var i = 1; i + 1 < points.length; i++) {
    if (breaks.contains(i) ||
        breaks.contains(i + 1) ||
        journeySpeed(points[i - 1], points[i]) == null ||
        journeySpeed(points[i], points[i + 1]) == null) {
      continue;
    }
    final a = journeyDistance(points[i - 1], points[i]),
        b = journeyDistance(points[i], points[i + 1]);
    final across = journeyDistance(points[i - 1], points[i + 1]);
    if (points[i + 1].timestamp
                .difference(points[i - 1].timestamp)
                .inMilliseconds <=
            10000 &&
        math.min(a, b) > math.max(40, points[i].accuracy.clamp(8, 50) * 3) &&
        a + b > across * 3 + 60) {
      spikes.add(i);
    }
  }
  final speeds = <double?>[null];
  for (var i = 1; i < points.length; i++) {
    speeds.add(
      breaks.contains(i) ||
              untimed.contains(i) ||
              untimed.contains(i - 1) ||
              spikes.contains(i) ||
              spikes.contains(i - 1)
          ? null
          : journeySpeed(points[i - 1], points[i]),
    );
  }
  final result = <int>{};
  for (var i = 1; i < points.length; i++) {
    final speed = speeds[i];
    if (speed == null) continue;
    final nearby = <double>[speed];
    for (var j = i - 1; j >= math.max(1, i - 2); j--) {
      if (speeds[j] == null) break;
      nearby.add(speeds[j]!);
    }
    for (var j = i + 1; j < math.min(points.length, i + 3); j++) {
      if (speeds[j] == null) break;
      nearby.add(speeds[j]!);
    }
    nearby.sort();
    if (speed <= (nearby[nearby.length ~/ 2] * 2 + 2).clamp(3, 70) &&
        journeyDistance(points[i - 1], points[i]) >= 2) {
      result.add(i);
    }
  }
  return result;
}
