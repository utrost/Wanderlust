import 'package:flutter/material.dart';

import '../data/street_network.dart';
import '../theme/heat_ramp.dart';
import '../theme/wanderlust_theme.dart';

/// Renders the filling map: the street network coloured and widened by walk
/// count, on a quiet basemap. This is the Flutter equivalent of the SVG hero in
/// design/mood-map — same data, same heat ramp. Today it paints the bundled
/// sample counts; once the Rust geo-core is wired via FFI, the counts come live
/// from the on-device tally.
class FillingMapPainter extends CustomPainter {
  FillingMapPainter({required this.level, required this.dark});

  final FillLevel level;
  final bool dark;

  // The mock design space is 0..440; we scale to fill the widget.
  static const double _designSize = 440;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.longestSide / _designSize;
    canvas.save();
    canvas.scale(scale);

    final colors = _BasemapColors(dark: dark);

    // Water ribbon.
    final water = Paint()
      ..color = colors.water
      ..style = PaintingStyle.stroke
      ..strokeWidth = 20
      ..strokeCap = StrokeCap.round;
    final waterPath = Path()
      ..moveTo(0, 300)
      ..quadraticBezierTo(160, 180, 260, 320)
      ..cubicTo(310, 385, 390, 300, 440, 250);
    canvas.drawPath(waterPath, water);

    // Parks.
    final park = Paint()..color = colors.park;
    canvas.drawOval(const Rect.fromLTWH(30, 34, 160, 92), park);
    canvas.drawOval(const Rect.fromLTWH(304, 336, 92, 68), park);

    // Streets, back-to-front by count so busier ink lands on top.
    final segments = [...kStreetSegments]
      ..sort((a, b) => a.countFor(level).compareTo(b.countFor(level)));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final s in segments) {
      final count = s.countFor(level);
      if (count <= 0) continue;
      paint
        ..color = HeatRamp.color(count, dark: dark)
        ..strokeWidth = HeatRamp.width(count);
      canvas.drawLine(Offset(s.x1, s.y1), Offset(s.x2, s.y2), paint);
    }

    // "You are here".
    final here = HeatRamp.color(dark ? 400 : 20, dark: dark);
    canvas.drawCircle(const Offset(220, 255), 5.5, Paint()..color = here);
    canvas.drawCircle(
      const Offset(220, 255),
      9,
      Paint()
        ..color = here.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(FillingMapPainter old) =>
      old.level != level || old.dark != dark;
}

class _BasemapColors {
  _BasemapColors({required bool dark})
      : water = dark ? WanderlustColors.darkWater : WanderlustColors.water,
        park = dark ? WanderlustColors.darkPark : WanderlustColors.park;
  final Color water;
  final Color park;
}
