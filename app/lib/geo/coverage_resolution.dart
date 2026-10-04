import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/foundation.dart';
import '../transfer/walk_codec.dart';
import 'geo_core_ffi.dart';

/// Resolve the display against FINAL coverage, after matching, inferred routes,
/// and user confirmations. Unresolved/off-network GPS remains visible.
Future<List<MatchResult>> resolveCoverageDisplay(
  String source,
  List<String> tracks,
  List<MatchResult> results, {
  List<List<int>>? confirmed,
}) => compute(_resolve, (source, tracks, results, confirmed));

List<MatchResult> _resolve(
  (String, List<String>, List<MatchResult>, List<List<int>>?) input,
) {
  if (input.$3.every((r) => r.unmatched.isEmpty)) return input.$3;
  final index = _StreetIndex(input.$1);
  return [
    for (var n = 0; n < input.$3.length; n++)
      (() {
        final result = input.$3[n],
            walked = {...result.walked, ...?input.$4?[n]};
        final points = WalkCodec.importGpx(input.$2[n]).points;
        final remaining = <int>[];
        for (final i in result.unmatched) {
          if (i <= 0 || i >= points.length) {
            throw StateError('Invalid GPS pair');
          }
          final a = Offset(points[i - 1].longitude, points[i - 1].latitude);
          final b = Offset(points[i].longitude, points[i].latitude);
          // The nearest street at BOTH ends and the middle must be painted.
          // Merely being close to a painted endpoint must not hide a missing section
          // or a separate parallel path. Use the matcher's 25 m snap corridor.
          if (![
            a,
            (a + b) / 2,
            b,
          ].every((p) => walked.contains(index.nearest(p)))) {
            remaining.add(i);
          }
        }
        return MatchResult(
          walked: result.walked,
          inferred: result.inferred,
          unmatched: remaining,
          gapsFilled: result.gapsFilled,
          gapsRejected: result.gapsRejected,
        );
      })(),
  ];
}

class _StreetIndex {
  _StreetIndex(String source) {
    final features = (jsonDecode(source) as Map)['features'] as List;
    final first = features.first['geometry']['coordinates'][0] as List;
    _cos = math.cos((first[1] as num) * math.pi / 180);
    for (final f in features) {
      final coords = [
        for (final c in f['geometry']['coordinates'] as List)
          _xy(Offset((c[0] as num).toDouble(), (c[1] as num).toDouble())),
      ];
      for (var i = 1; i < coords.length; i++) {
        final a = coords[i - 1], b = coords[i];
        final edge = (f['id'] as int, a, b);
        final left = (math.min(a.dx, b.dx) / 50).floor(),
            right = (math.max(a.dx, b.dx) / 50).floor();
        final bottom = (math.min(a.dy, b.dy) / 50).floor(),
            top = (math.max(a.dy, b.dy) / 50).floor();
        if ((right - left + 1) * (top - bottom + 1) > 4096) {
          _long.add(edge);
          continue;
        }
        for (var x = left; x <= right; x++) {
          for (var y = bottom; y <= top; y++) {
            (_grid[(x, y)] ??= []).add(edge);
          }
        }
      }
    }
  }
  late final double _cos;
  final _grid = <(int, int), List<(int, Offset, Offset)>>{};
  final _long = <(int, Offset, Offset)>[];
  Offset _xy(Offset p) => Offset(p.dx * _cos * 111320, p.dy * 111320);
  int? nearest(Offset coordinate) {
    final p = _xy(coordinate);
    var best = 25.0 * 25.0;
    int? id;
    void consider((int, Offset, Offset) edge) {
      final delta = edge.$3 - edge.$2, length = delta.distanceSquared;
      final offset = p - edge.$2;
      final t = length == 0
          ? 0.0
          : ((offset.dx * delta.dx + offset.dy * delta.dy) / length).clamp(
              0.0,
              1.0,
            );
      final distance = (p - (edge.$2 + delta * t)).distanceSquared;
      if (distance < best ||
          (distance == best && (id == null || edge.$1 < id!))) {
        best = distance;
        id = edge.$1;
      }
    }

    for (
      var x = ((p.dx - 25) / 50).floor();
      x <= ((p.dx + 25) / 50).floor();
      x++
    ) {
      for (
        var y = ((p.dy - 25) / 50).floor();
        y <= ((p.dy + 25) / 50).floor();
        y++
      ) {
        for (final edge in _grid[(x, y)] ?? <(int, Offset, Offset)>[]) {
          consider(edge);
        }
      }
    }
    for (final edge in _long) {
      consider(edge);
    }
    return id;
  }
}
