import 'dart:math' as math;
import 'dart:ui';
import 'block_geometry.dart';

class BlockProgress {
  const BlockProgress(
    this.covered,
    this.remaining,
    this.longestGap,
    this.complete,
  );
  final double covered, remaining, longestGap;
  final bool complete;
}

List<(double, double)> missingIntervals(
  BlockBoundary edge,
  Set<int> supported,
) {
  final ranges = <(double, double)>[
    for (final entry in edge.evidence.entries)
      if (supported.contains(entry.key)) ...entry.value,
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  final missing = <(double, double)>[];
  var end = 0.0;
  for (final range in ranges) {
    if (range.$1 > end) missing.add((end, range.$1));
    end = math.max(end, range.$2);
  }
  if (end < 1) missing.add((end, 1));
  return missing;
}

BlockProgress blockProgress(StreetBlock block, Set<int> supported) {
  var missing = 0.0, longest = 0.0, run = 0.0, leading = 0.0;
  var hasCoverage = false;
  for (final boundary in block.boundary) {
    var end = 0.0;
    for (final gap in missingIntervals(boundary, supported)) {
      if (gap.$1 > end + 1e-9) {
        if (!hasCoverage) leading = run;
        hasCoverage = true;
        run = 0;
      }
      final length = (gap.$2 - gap.$1) * boundary.length;
      run += length;
      missing += length;
      longest = math.max(longest, run);
      end = gap.$2;
    }
    if (end < 1 - 1e-9) {
      if (!hasCoverage) leading = run;
      hasCoverage = true;
      run = 0;
    }
  }
  if (hasCoverage) longest = math.max(longest, leading + run);
  final covered = math.max(0.0, block.perimeter - missing);
  return BlockProgress(
    covered,
    missing,
    longest,
    block.perimeter > 0 &&
        covered / block.perimeter >= .95 - 1e-9 &&
        longest <= 20 + 1e-6,
  );
}

List<List<Offset>> missingLines(StreetBlock block, Set<int> supported) => [
  for (final boundary in block.boundary)
    for (final interval in missingIntervals(boundary, supported))
      _slice(boundary.points, interval.$1, interval.$2),
];
List<Offset> _slice(List<Offset> points, double from, double to) {
  final total = lineLength(points), result = <Offset>[];
  var start = 0.0;
  for (var i = 1; i < points.length; i++) {
    final length = metres(points[i - 1], points[i]);
    if (length == 0) continue;
    final a = math.max(0.0, (from * total - start) / length);
    final b = math.min(1.0, (to * total - start) / length);
    if (a < b) {
      result.add(points[i - 1] + (points[i] - points[i - 1]) * a);
      result.add(points[i - 1] + (points[i] - points[i - 1]) * b);
    }
    start += length;
  }
  return result;
}
