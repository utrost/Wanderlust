import 'dart:math' as math;
import 'dart:ui';

import '../data/area_network.dart';

/// Distance to the exposed boundary of the union, not internal map seams.
class MapExtent {
  MapExtent(Iterable<AreaNetwork> maps)
    : boxes = maps
          .map((m) => Rect.fromLTRB(m.bbox[0], m.bbox[1], m.bbox[2], m.bbox[3]))
          .toList();
  final List<Rect> boxes;

  bool contains(Offset p) => boxes.any(
    (b) =>
        p.dx >= b.left && p.dx <= b.right && p.dy >= b.top && p.dy <= b.bottom,
  );

  double distanceToBoundary(Offset p) {
    if (!contains(p)) return 0;
    var distance = double.infinity;
    final sx = 111320 * math.cos(p.dy * math.pi / 180);
    const sy = 111320.0;
    for (final b in boxes) {
      for (final vertical in [true, false]) {
        for (final high in [false, true]) {
          final fixed = vertical
              ? (high ? b.right : b.left)
              : (high ? b.bottom : b.top);
          final lo = vertical ? b.top : b.left;
          final hi = vertical ? b.bottom : b.right;
          final cuts = <double>{lo, hi};
          final covering = <(double, double)>[];
          for (final other in boxes) {
            final lowAxis = vertical ? other.left : other.top;
            final highAxis = vertical ? other.right : other.bottom;
            // Only rectangles extending beyond this side hide its boundary.
            if (high
                ? (lowAxis <= fixed && highAxis > fixed)
                : (lowAxis < fixed && highAxis >= fixed)) {
              final a = math.max(lo, vertical ? other.top : other.left);
              final z = math.min(hi, vertical ? other.bottom : other.right);
              if (a < z) {
                covering.add((a, z));
                cuts.addAll([a, z]);
              }
            }
          }
          final sorted = cuts.toList()..sort();
          for (var i = 1; i < sorted.length; i++) {
            final a = sorted[i - 1], z = sorted[i];
            final mid = (a + z) / 2;
            if (covering.any((c) => c.$1 < mid && c.$2 > mid)) continue;
            final variable = (vertical ? p.dy : p.dx).clamp(a, z);
            final q = vertical
                ? Offset(fixed, variable)
                : Offset(variable, fixed);
            final dx = (p.dx - q.dx) * sx, dy = (p.dy - q.dy) * sy;
            distance = math.min(distance, math.sqrt(dx * dx + dy * dy));
          }
        }
      }
    }
    return distance;
  }
}
