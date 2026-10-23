import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../data/area_network.dart';
import '../theme/wanderlust_theme.dart';

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
  Iterable<AreaEdge>? visibleEdges,
  MapLabelCache? cache,
}) {
  final candidates = <(String, Offset, bool, double, Offset)>[];
  final visibleLengths = <String, double>{};
  final seenEdges = <int>{};
  var edgesHandled = false;
  for (final map in maps) {
    for (final p in map.places) {
      candidates.add((p.name, project(p.point), true, 0, Offset.zero));
    }
    if (!streets || edgesHandled) continue;
    edgesHandled = visibleEdges != null;
    for (final edge in visibleEdges ?? map.edges) {
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
        if (length == 0) continue;
        final direction = b - a;
        var normal = Offset(-direction.dy, direction.dx) / length;
        // Stable placement even when an OSM way has the opposite direction.
        if (normal.dy > 0 || (normal.dy == 0 && normal.dx < 0)) {
          normal = -normal;
        }
        candidates.add((name, mid, false, length, normal));
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
    final painter =
        cache?.text(c.$1, c.$3, textScale) ??
        mapLabelText(c.$1, c.$3, textScale);
    final width = painter.width, height = painter.height;
    if (cache == null) painter.dispose();
    if (!c.$3 && (visibleLengths[c.$1] ?? 0) < math.max(60, width * 1.3)) {
      continue;
    }
    final rect = Rect.fromCenter(
      center:
          c.$2 +
          c.$5 *
              (c.$5.dx.abs() * (width + 8) / 2 +
                  c.$5.dy.abs() * (height + 4) / 2 +
                  5),
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
      fontSize: place ? 12 : 10,
      color: WanderlustColors.mapLabel,
      fontWeight: place ? FontWeight.w500 : FontWeight.normal,
    ),
  ),
  textDirection: TextDirection.ltr,
  textScaler: TextScaler.linear(scale),
  maxLines: 1,
)..layout();
void paintMapLabels(
  Canvas canvas,
  List<PlacedMapLabel> labels,
  double scale, {
  MapLabelCache? cache,
}) {
  for (final label in labels) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(label.bounds, const Radius.circular(3)),
      Paint()..color = WanderlustColors.paperBg.withValues(alpha: 0.85),
    );
    final text =
        cache?.text(label.text, label.place, scale) ??
        mapLabelText(label.text, label.place, scale);
    text.paint(
      canvas,
      label.bounds.center - Offset(text.width / 2, text.height / 2),
    );
    if (cache == null) text.dispose();
  }
}

/// Bounded LRU: text shaping is reused across pan frames, with explicit disposal.
class MapLabelCache {
  final _text = <(String, bool, double), TextPainter>{};
  TextPainter text(String value, bool place, double scale) {
    final key = (value, place, scale);
    final painter = _text.remove(key) ?? mapLabelText(value, place, scale);
    _text[key] = painter;
    if (_text.length > 256) _text.remove(_text.keys.first)!.dispose();
    return painter;
  }

  void dispose() {
    for (final painter in _text.values) {
      painter.dispose();
    }
    _text.clear();
  }
}
