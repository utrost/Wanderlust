import 'dart:math' as math;
import 'dart:ui';

/// The walk-count heat ramp — the brand's core visual language, ported from
/// design/mood-map/map-data.js. Warm single-hue OKLCH ink on a log scale: faint
/// and thin at 1×, deep and broad near 1000×. Width always carries the same
/// signal as colour, so the ramp survives colour-vision deficiencies.
///
/// Flutter has no OKLCH colour, so we convert OKLCH → linear sRGB → gamma sRGB
/// (Björn Ottosson's transform) to reproduce the exact palette from the mocks.
class HeatRamp {
  static const double _rampMax = 1000;
  static final double _logMax = _log10(_rampMax + 1);

  static double _ease(double t) => math.pow(t, 0.88).toDouble();

  static double _logT(num count) {
    final c = count.clamp(0, _rampMax).toDouble();
    return _ease(_log10(c + 1) / _logMax);
  }

  /// Stroke width in the mock's coordinate space (1.05 → 6.5).
  static double width(num count) {
    if (count <= 0) return 0.55;
    return double.parse((1.05 + _logT(count) * 5.45).toStringAsFixed(2));
  }

  /// Ink colour for a walk count, light or dark basemap.
  static Color color(num count, {required bool dark}) {
    if (count <= 0) {
      return dark ? oklch(0.32, 0.012, 75) : oklch(0.86, 0.008, 75);
    }
    final t = _logT(count);
    final hue = 66 - t * 20; // gold → rust-brown as it deepens
    if (dark) {
      return oklch(0.44 + t * 0.46, 0.065 + t * 0.115, hue);
    }
    return oklch(0.82 - t * 0.52, 0.04 + t * 0.125, hue);
  }
}

double _log10(double x) => math.log(x) / math.ln10;

/// Convert an OKLCH colour (L 0..1, C, hue degrees) to a Flutter [Color].
Color oklch(double l, double c, double hueDeg, [double alpha = 1.0]) {
  final h = hueDeg * math.pi / 180.0;
  final a = c * math.cos(h);
  final b = c * math.sin(h);

  // oklab → linear sRGB
  final lp = l + 0.3963377774 * a + 0.2158037573 * b;
  final mp = l - 0.1055613458 * a - 0.0638541728 * b;
  final sp = l - 0.0894841775 * a - 1.2914855480 * b;
  final l3 = lp * lp * lp, m3 = mp * mp * mp, s3 = sp * sp * sp;

  final r = 4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3;
  final g = -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3;
  final bl = -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3;

  int chan(double lin) {
    final v = lin <= 0.0031308
        ? 12.92 * lin
        : 1.055 * math.pow(lin, 1 / 2.4) - 0.055;
    return (v.clamp(0.0, 1.0) * 255).round();
  }

  return Color.fromARGB((alpha * 255).round(), chan(r), chan(g), chan(bl));
}
