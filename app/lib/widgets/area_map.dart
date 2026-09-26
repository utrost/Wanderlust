import 'package:flutter/material.dart';

import '../data/area_network.dart';
import '../theme/heat_ramp.dart';

/// Offline street geometry, with exactly the ids and coordinates used by Rust.
/// This is a street coverage view; the richer PMTiles basemap is still pending.
class AreaMap extends StatelessWidget {
  const AreaMap({super.key, required this.network, required this.counts});
  final AreaNetwork network;
  final Map<int, int> counts;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) => InteractiveViewer(
      minScale: 1,
      maxScale: 12,
      child: RepaintBoundary(
        child: CustomPaint(
          size: bounds.biggest,
          painter: AreaMapPainter(network: network, counts: counts),
        ),
      ),
    ),
  );
}

class AreaMapPainter extends CustomPainter {
  AreaMapPainter({required this.network, required this.counts});
  final AreaNetwork network;
  final Map<int, int> counts;

  @override
  void paint(Canvas canvas, Size size) {
    // Leave space for map controls without shifting geographic coordinates.
    final mapSize = Size(size.width - 24, size.height - 180);
    canvas.save();
    canvas.translate(12, 80);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    void draw(AreaEdge edge, int count) {
      stroke
        ..color = HeatRamp.color(count, dark: false)
        ..strokeWidth = count == 0 ? 0.65 : HeatRamp.width(count);
      final path = Path();
      for (var i = 0; i < edge.points.length; i++) {
        final p = network.project(edge.points[i], mapSize);
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(path, stroke);
    }

    for (final edge in network.edges) {
      draw(edge, 0);
    }
    final painted =
        network.edges.where((edge) => (counts[edge.id] ?? 0) > 0).toList()
          ..sort((a, b) => counts[a.id]!.compareTo(counts[b.id]!));
    for (final edge in painted) {
      draw(edge, counts[edge.id]!);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(AreaMapPainter oldDelegate) =>
      oldDelegate.network != network || oldDelegate.counts != counts;
}
