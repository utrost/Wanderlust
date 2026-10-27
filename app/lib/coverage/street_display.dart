import 'dart:math' as math;
import 'dart:ui';

import '../data/area_network.dart';

/// A source interval and its equivalent displayed street interval.
class StreetProjection {
  const StreetProjection(
    this.source,
    this.target,
    this.sourceFrom,
    this.sourceTo,
    this.points,
  );
  final int source, target;

  /// Fractions along the source segment, before presentation projection.
  final double sourceFrom, sourceTo;
  final List<Offset> points;
}

/// A presentation-only projection onto equivalent road geometry. Coverage IDs,
/// counts and saved GPS remain untouched. A grid bounds work to nearby pieces.
class StreetDisplay {
  StreetDisplay(Iterable<AreaEdge> edges) {
    final list = edges.toList();
    _cos = math.cos(
      (list.isEmpty ? 0 : list.first.points.first.dy) * math.pi / 180,
    );
    for (final edge in list) {
      for (var i = 1; i < edge.points.length; i++) {
        final part = _Part(edge, _xy(edge.points[i - 1]), _xy(edge.points[i]));
        if (part.length < 0.01) continue;
        final bounds = Rect.fromPoints(part.a, part.b).inflate(18);
        for (
          var x = (bounds.left / 50).floor();
          x <= (bounds.right / 50).floor();
          x++
        ) {
          for (
            var y = (bounds.top / 50).floor();
            y <= (bounds.bottom / 50).floor();
            y++
          ) {
            (_grid[(x, y)] ??= []).add(part);
          }
        }
      }
    }
  }

  late final double _cos;
  final _grid = <(int, int), List<_Part>>{};
  final _cache = <AreaEdge, List<StreetProjection>>{};
  final _geometry = <AreaEdge, List<AreaEdge>>{};
  Offset _xy(Offset p) => Offset(p.dx * 111195 * _cos, p.dy * 111195);
  Offset _lngLat(Offset p) => Offset(p.dx / (111195 * _cos), p.dy / 111195);

  List<AreaEdge> geometry(AreaEdge edge) => _geometry.putIfAbsent(
    edge,
    () => [
      for (final p in projections(edge)) AreaEdge(edge.id, p.points, edge.name),
    ],
  );

  List<StreetProjection> projections(
    AreaEdge edge,
  ) => _cache.putIfAbsent(edge, () {
    final result = <StreetProjection>[];
    for (var i = 1; i < edge.points.length; i++) {
      final source = _Part(edge, _xy(edge.points[i - 1]), _xy(edge.points[i]));
      if (source.length < 0.01) continue;
      final middle = (source.a + source.b) / 2;
      final candidates = <_Part>{};
      // Source sections are normally <=15 m. Query the full bounds as well
      // so older imported maps with longer pieces behave identically.
      final bounds = Rect.fromPoints(source.a, source.b);
      for (
        var x = (bounds.left / 50).floor();
        x <= (bounds.right / 50).floor();
        x++
      ) {
        for (
          var y = (bounds.top / 50).floor();
          y <= (bounds.bottom / 50).floor();
          y++
        ) {
          candidates.addAll(_grid[(x, y)] ?? const []);
        }
      }
      final choices =
          candidates
              .where(
                (target) =>
                    _rank(target.edge, edge) < 0 &&
                    equivalentStreetGeometry(edge, target.edge) &&
                    _dot(source.unit, target.unit).abs() >= 0.97 &&
                    (middle - target.project(middle)).distance <=
                        18 + source.length / 2,
              )
              .toList()
            ..sort((a, b) => _rank(a.edge, b.edge));
      final cuts = <double>{0, 1};
      for (final target in choices) {
        cuts.add(source.fraction(target.a).clamp(0.0, 1.0));
        cuts.add(source.fraction(target.b).clamp(0.0, 1.0));
      }
      final ordered = cuts.toList()..sort();
      for (var j = 1; j < ordered.length; j++) {
        final a = source.at(ordered[j - 1]);
        final b = source.at(ordered[j]);
        if ((b - a).distance < 0.01) continue;
        _Part? selected;
        for (final target in choices) {
          final t = target.fraction((a + b) / 2);
          if (t >= 0 &&
              t <= 1 &&
              (a - target.project(a)).distance <= 18 &&
              (b - target.project(b)).distance <= 18) {
            selected = target;
            break;
          }
        }
        result.add(
          StreetProjection(
            edge.id,
            selected?.edge.id ?? edge.id,
            ordered[j - 1],
            ordered[j],
            [
              _lngLat(selected?.project(a) ?? a),
              _lngLat(selected?.project(b) ?? b),
            ],
          ),
        );
      }
    }
    return result;
  });
}

bool _road(AreaEdge e) => const {
  'primary',
  'primary_link',
  'secondary',
  'secondary_link',
  'tertiary',
  'tertiary_link',
  'unclassified',
  'residential',
  'living_street',
}.contains(e.highway);
bool _roadside(AreaEdge e) =>
    e.highway == 'cycleway' ||
    (e.highway == 'footway' && e.footway == 'sidewalk');

/// Whether two mapped sections represent the same street corridor.
bool equivalentStreetGeometry(AreaEdge a, AreaEdge b) {
  // Edge IDs are hashes of short pieces, so cannot choose a consistent side
  // of a street. Legacy maps without way identity keep their original lines.
  if (a.wayId == null || b.wayId == null) return false;
  final identity =
      (a.wayId != null && a.wayId == b.wayId) ||
      (a.name != null && a.name!.isNotEmpty && a.name == b.name);
  String level(String s) => s.isEmpty ? '0' : s;
  bool structure(String s) => s.isNotEmpty && s != 'no';
  return identity &&
      level(a.layer) == level(b.layer) &&
      structure(a.bridge) == structure(b.bridge) &&
      structure(a.tunnel) == structure(b.tunnel) &&
      ((_road(a) &&
              _road(b) &&
              a.highway.replaceFirst('_link', '') ==
                  b.highway.replaceFirst('_link', '')) ||
          (_road(a) && _roadside(b)) ||
          (_road(b) && _roadside(a)));
}

int _rank(AreaEdge a, AreaEdge b) {
  final road = (_road(a) ? 0 : 1).compareTo(_road(b) ? 0 : 1);
  if (road != 0) return road;
  final way = (a.wayId ?? a.id).compareTo(b.wayId ?? b.id);
  return way != 0 ? way : a.id.compareTo(b.id);
}

double _dot(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;

class _Part {
  _Part(this.edge, this.a, this.b);
  final AreaEdge edge;
  final Offset a, b;
  double get length => (b - a).distance;
  Offset get unit => (b - a) / length;
  double fraction(Offset p) => _dot(p - a, b - a) / (b - a).distanceSquared;
  Offset at(double t) => a + (b - a) * t;
  Offset project(Offset p) => at(fraction(p).clamp(0.0, 1.0));
}
