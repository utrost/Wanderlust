import 'package:flutter/material.dart';
import '../data/area_network.dart';
import '../theme/heat_ramp.dart';

const reviewTraceColor = Color(0xFF1976D2);

void paintWalkOverlay(
  Canvas canvas,
  List<AreaNetwork> maps,
  Set<int> inferred,
  List<List<Offset>> trace,
  Offset Function(Offset) project,
) {
  final seen = <int>{};
  final pen = Paint()
    ..color = HeatRamp.color(1, dark: false)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 4
    ..strokeCap = StrokeCap.round;
  for (final map in inferred.isEmpty ? <AreaNetwork>[] : maps) {
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
      canvas.drawPath(path, pen);
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

/// Recorded movement uses the same solid ink as street coverage.
void paintUnmatchedTrails(
  Canvas canvas,
  List<List<Offset>> trails,
  Offset Function(Offset) project, {
  double width = 4,
}) {
  final pen = Paint()
    ..color = HeatRamp.color(1, dark: false)
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
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
    canvas.drawPath(path, pen);
  }
}
