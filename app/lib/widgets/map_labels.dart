import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../data/area_network.dart';

class PlacedMapLabel {
  const PlacedMapLabel(this.text, this.bounds, this.place);
  final String text;
  final Rect bounds;
  final bool place;
}

/// Screen-space text stays small at every zoom. Deterministic collision and
/// viewport checks prevent duplicate labels on overlapping downloaded maps.
List<PlacedMapLabel> layoutMapLabels(
  List<AreaNetwork> maps,
  Size size,
  Offset Function(Offset) project, {
  required bool streets,
  double textScale = 1,
}) {
  final candidates = <(String, Offset, bool, double)>[];
  final visibleLengths = <String, double>{};
  final seenEdges = <int>{};
  for (final map in maps) {
    for (final p in map.places) {
      candidates.add((p.name, project(p.point), true, 0));
    }
    if (!streets) continue;
    for (final edge in map.edges) {
      if (!seenEdges.add(edge.id)) continue;
      final name = edge.name?.trim();
      if (name == null || name.isEmpty || name.length > 80) continue;
      // Prefer the longest visible leg of each section for a stable anchor.
      for (var i = 1; i < edge.points.length; i++) {
        final a = project(edge.points[i - 1]), b = project(edge.points[i]);
        final mid = (a + b) / 2;
        if (!(Offset.zero & size).contains(mid)) continue;
        final length = (b - a).distance;
        visibleLengths.update(name, (v) => v + length, ifAbsent: () => length);
        candidates.add((name, mid, false, length));
      }
    }
  }
  candidates.sort((a, b) {
    if (a.$3 != b.$3) return a.$3 ? -1 : 1;
    final length = b.$4.compareTo(a.$4);
    return length != 0 ? length : a.$1.compareTo(b.$1);
  });
  final placed = <PlacedMapLabel>[], names = <String>{};
  final viewport = (Offset.zero & size).deflate(8);
  for (final c in candidates) {
    if (names.contains(c.$1)) continue;
    final painter = mapLabelText(c.$1, c.$3, textScale);
    final width = painter.width, height = painter.height;
    painter.dispose();
    if (!c.$3 && (visibleLengths[c.$1] ?? 0) < math.max(60, width * 1.3))
      continue;
    final rect = Rect.fromCenter(
      center: c.$2,
      width: width + 8,
      height: height + 4,
    );
    if (!viewport.contains(rect.topLeft) ||
        !viewport.contains(rect.bottomRight) ||
        placed.any((p) => p.bounds.inflate(10).overlaps(rect))) {
      continue;
    }
    placed.add(PlacedMapLabel(c.$1, rect, c.$3));
    names.add(c.$1);
    if (placed.length >= 35) break;
  }
  return placed;
}

TextPainter mapLabelText(String text, bool place, double scale) => TextPainter(
  text: TextSpan(
    text: text,
    style: TextStyle(
      fontFamily: 'Work Sans',
      fontSize: place ? 12 : 10,
      color: const Color(0xFF665F55),
      fontWeight: place ? FontWeight.w500 : FontWeight.normal,
    ),
  ),
  textDirection: TextDirection.ltr,
  textScaler: TextScaler.linear(scale),
  maxLines: 1,
)..layout();
void paintMapLabels(Canvas canvas, List<PlacedMapLabel> labels, double scale) {
  for (final label in labels) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(label.bounds, const Radius.circular(3)),
      Paint()..color = const Color(0xFFF4EEE5).withValues(alpha: 0.85),
    );
    final text = mapLabelText(label.text, label.place, scale);
    text.paint(
      canvas,
      label.bounds.center - Offset(text.width / 2, text.height / 2),
    );
    text.dispose();
  }
}
