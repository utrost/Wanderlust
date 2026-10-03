import 'package:flutter/material.dart';
import '../data/area_network.dart';

const reviewTraceColor = Color(0xFF1976D2);
const reviewInferredColor = Color(0xFF86629C);

void paintWalkOverlay(
  Canvas canvas,
  List<AreaNetwork> maps,
  Set<int> inferred,
  List<List<Offset>> trace,
  Offset Function(Offset) project,
) {
  final seen = <int>{};
  final pen = Paint()
    ..color = reviewInferredColor
    ..style = PaintingStyle.stroke
    ..strokeWidth = 4
    ..strokeCap = StrokeCap.round;
  for (final map in maps) {
    for (final edge in map.edges) {
      if (!inferred.contains(edge.id) || !seen.add(edge.id)) continue;
      final path = Path();
      for (var i = 0; i < edge.points.length; i++) {
        final p = project(edge.points[i]);
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      for (final metric in path.computeMetrics()) {
        for (double start = 0; start < metric.length; start += 10) {
          canvas.drawPath(metric.extractPath(start, start + 6), pen);
        }
      }
    }
  }
  pen
    ..color = reviewTraceColor.withValues(alpha: 0.8)
    ..strokeWidth = 1.6;
  for (final segment in trace) {
    if (segment.isEmpty) continue;
    final path = Path();
    for (var i = 0; i < segment.length; i++) {
      final p = project(segment[i]);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(path, pen);
    canvas.drawCircle(
      project(segment.first),
      3,
      Paint()..color = reviewTraceColor,
    );
    canvas.drawCircle(
      project(segment.last),
      3,
      Paint()..color = reviewTraceColor,
    );
  }
}

/// Muted, dashed raw movement; deliberately distinct from counted street heat.
void paintUnmatchedTrails(
  Canvas canvas,
  List<List<Offset>> trails,
  Offset Function(Offset) project,
) {
  final pen = Paint()
    ..color = const Color(0xFF748C89)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.8
    ..strokeCap = StrokeCap.round;
  for (final trail in trails) {
    if (trail.length < 2) continue;
    final path = Path();
    for (var i = 0; i < trail.length; i++) {
      final point = project(trail[i]);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    for (final metric in path.computeMetrics()) {
      for (double start = 0; start < metric.length; start += 8) {
        canvas.drawPath(metric.extractPath(start, start + 4), pen);
      }
    }
  }
}
