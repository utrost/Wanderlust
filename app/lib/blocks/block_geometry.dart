import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'dart:math' as math;
import 'dart:ui';

import '../coverage/street_display.dart';
import '../data/area_network.dart';
import '../widgets/map_spatial_index.dart';

const blockRevision = 'street-blocks-v2';

class BlockBoundary {
  BlockBoundary(
    List<Offset> points,
    this.length,
    Map<int, List<(double, double)>> evidence,
  ) : points = List.unmodifiable(points),
      evidence = Map.unmodifiable(
        evidence.map(
          (k, v) => MapEntry(k, List<(double, double)>.unmodifiable(v)),
        ),
      );
  final List<Offset> points;
  final double length;

  /// Supported source sections cover these fractions of this boundary.
  final Map<int, List<(double, double)>> evidence;
}

class StreetBlock {
  StreetBlock(this.id, List<BlockBoundary> boundary)
    : boundary = List.unmodifiable(boundary),
      points = List.unmodifiable(
        boundary.expand((b) => b.points.take(b.points.length - 1)),
      ) {
    bounds = boundsOf(points);
    perimeter = boundary.fold(0.0, (a, b) => a + b.length);
  }
  final String id;
  final List<BlockBoundary> boundary;
  final List<Offset> points;
  late final Rect bounds;
  late final double perimeter;
}

Rect boundsOf(Iterable<Offset> points) {
  final it = points.iterator;
  if (!it.moveNext()) return Rect.zero;
  var r = Rect.fromPoints(it.current, it.current);
  while (it.moveNext()) {
    r = r.expandToInclude(Rect.fromPoints(it.current, it.current));
  }
  return r;
}

class BlockTopology {
  const BlockTopology(this.blocks, {this.needsRefresh = false});
  final List<StreetBlock> blocks;
  final bool needsRefresh;
}

bool _boundaryRoad(AreaEdge e) =>
    const {
      'residential',
      'living_street',
      'unclassified',
      'primary',
      'secondary',
      'tertiary',
      'pedestrian',
    }.contains(e.highway) &&
    const {'', 'yes', 'permissive', 'designated'}.contains(e.access) &&
    const {'', '0'}.contains(e.layer) &&
    const {'', 'no'}.contains(e.bridge) &&
    const {'', 'no'}.contains(e.tunnel);

// Public connectors can close a street perimeter, but cannot split its interior.
// Sidewalks/crossings remain coverage equivalents, not separate boundaries.
bool _connectorRoad(AreaEdge e) =>
    const {'path', 'footway', 'cycleway', 'service'}.contains(e.highway) &&
    !const {'sidewalk', 'crossing'}.contains(e.footway) &&
    const {
      '',
      'yes',
      'permissive',
      'designated',
      'destination',
    }.contains(e.access) &&
    const {'', '0'}.contains(e.layer) &&
    const {'', 'no'}.contains(e.bridge) &&
    const {'', 'no'}.contains(e.tunnel);

double metres(Offset a, Offset b) =>
    math.sqrt(
      math.pow((a.dx - b.dx) * math.cos((a.dy + b.dy) * math.pi / 360), 2) +
          math.pow(a.dy - b.dy, 2),
    ) *
    111320;

double lineLength(List<Offset> points) {
  var result = 0.0;
  for (var i = 1; i < points.length; i++) {
    result += metres(points[i - 1], points[i]);
  }
  return result;
}

/// Runs on the worker isolate. Original node identities define connectivity;
/// visual proximity alone can never create a junction.
BlockTopology buildBlockTopology(List<AreaNetwork> networks) =>
    _buildBlockTopology(networks, includeConnectors: true);

BlockTopology _buildBlockTopology(
  List<AreaNetwork> networks, {
  required bool includeConnectors,
}) {
  final all = <int, AreaEdge>{};
  for (final n in networks) {
    for (final e in n.edges) {
      all.putIfAbsent(e.id, () => e);
    }
  }
  // Existing street enclosures take precedence over paths inside them. New
  // connecting corridors can close otherwise open street boundaries.
  final existing = includeConnectors
      ? _buildBlockTopology(networks, includeConnectors: false).blocks
      : <StreetBlock>[];
  final existingIndex = MapSpatialIndex<StreetBlock>(cellSize: .001);
  for (final block in existing) {
    existingIndex.add(block, block.bounds);
  }
  bool internal(AreaEdge e) {
    for (var i = 1; i < e.points.length; i++) {
      final midpoint = (e.points[i - 1] + e.points[i]) / 2;
      for (final block in existingIndex.query(
        Rect.fromCircle(center: midpoint, radius: 1e-10),
      )) {
        if (_containsPoint(block.points, midpoint)) return true;
      }
    }
    return false;
  }

  var needsRefresh = false;
  final roads = <int, AreaEdge>{};
  for (final e in all.values.where(
    (e) =>
        _boundaryRoad(e) ||
        (includeConnectors && _connectorRoad(e) && !internal(e)),
  )) {
    if (e.fromNode == null || e.toNode == null || e.wayId == null) {
      needsRefresh = true;
      continue;
    }
    if (e.fromNode != e.toNode || e.points.length > 2) roads[e.id] = e;
  }
  if (roads.isEmpty) return BlockTopology(const [], needsRefresh: needsRefresh);
  final adjacency = <int, List<(int, bool)>>{};
  for (final e in roads.values) {
    (adjacency[e.fromNode!] ??= []).add((e.id, true));
    (adjacency[e.toNode!] ??= []).add((e.id, false));
  }
  int from((int, bool) d) =>
      d.$2 ? roads[d.$1]!.fromNode! : roads[d.$1]!.toNode!;
  int to((int, bool) d) => from((d.$1, !d.$2));
  List<Offset> points((int, bool) d) =>
      d.$2 ? roads[d.$1]!.points : roads[d.$1]!.points.reversed.toList();
  // Peel trees before tracing faces. No cul-de-sac becomes a required detour.
  final leaves = adjacency.keys
      .where((n) => adjacency[n]!.length == 1)
      .toList();
  final removed = <int>{};
  for (var i = 0; i < leaves.length; i++) {
    final list = adjacency[leaves[i]]!;
    if (list.length != 1) continue;
    final d = list.single;
    removed.add(d.$1);
    list.clear();
    final other = adjacency[to(d)]!;
    other.remove((d.$1, !d.$2));
    if (other.length == 1) leaves.add(to(d));
  }
  for (final list in adjacency.values) {
    double angle((int, bool) d) {
      final p = points(d);
      final v =
          p.skip(1).firstWhere((v) => v != p.first, orElse: () => p.last) -
          p.first;
      return math.atan2(v.dy, v.dx * math.cos(p.first.dy * math.pi / 180));
    }

    list.sort((a, b) => angle(a).compareTo(angle(b)));
  }

  // Transfer coverage only where StreetDisplay actually projects corresponding
  // geometry. Both source and target are projected, allowing either carriageway.
  final display = StreetDisplay(all.values);
  final canonicalIndex = MapSpatialIndex<(int, Offset, Offset, double, double)>(
    cellSize: .001,
  );
  for (final e in roads.values.where((e) => !removed.contains(e.id))) {
    final total = lineLength(e.points);
    var walked = 0.0;
    for (var i = 1; i < e.points.length; i++) {
      final segment = AreaEdge(
        e.id,
        [e.points[i - 1], e.points[i]],
        e.name,
        wayId: e.wayId,
        highway: e.highway,
        footway: e.footway,
        layer: e.layer,
        bridge: e.bridge,
        tunnel: e.tunnel,
      );
      final length = metres(e.points[i - 1], e.points[i]);
      for (final p in display.projections(segment)) {
        // Recover the source fraction along this segment, not the target's.
        final a = p.sourceFrom;
        final b = p.sourceTo;
        canonicalIndex.add((
          e.id,
          p.points.first,
          p.points.last,
          (walked + a * length) / total,
          (walked + b * length) / total,
        ), boundsOf(p.points).inflate(.000001));
      }
      walked += length;
    }
  }
  final evidence = <int, Map<int, List<(double, double)>>>{
    for (final e in roads.values)
      e.id: {
        e.id: [(0, 1)],
      },
  };
  for (final source in all.values) {
    if (!const {
      '',
      'yes',
      'permissive',
      'designated',
    }.contains(source.access)) {
      continue;
    }
    for (final p in display.projections(source)) {
      for (final target in canonicalIndex.query(
        boundsOf(p.points).inflate(.000001),
      )) {
        if (target.$1 == source.id ||
            !equivalentStreetGeometry(source, roads[target.$1]!)) {
          continue;
        }
        final a = p.points.first, b = p.points.last;
        final c = target.$2, d = target.$3;
        // The shared canonical line must coincide, not merely run nearby.
        final length = metres(c, d);
        if (length < .01 ||
            _lineDistance(c, d, a) > .05 ||
            _lineDistance(c, d, b) > .05) {
          continue;
        }
        final t1 = _fraction(c, d, a, clamp: false),
            t2 = _fraction(c, d, b, clamp: false);
        final lo = math.max(0.0, math.min(t1, t2)),
            hi = math.min(1.0, math.max(t1, t2));
        if (hi <= lo) continue;
        final u = target.$4 + lo * (target.$5 - target.$4);
        final v = target.$4 + hi * (target.$5 - target.$4);
        (evidence[target.$1]![source.id] ??= []).add((
          math.min(u, v),
          math.max(u, v),
        ));
      }
    }
  }

  final ambiguous = _ambiguousEdges(roads.values);
  final seen = <(int, bool)>{};
  final blocks = <StreetBlock>[];
  for (final start in adjacency.values.expand((l) => l)) {
    if (seen.contains(start)) continue;
    final ring = <(int, bool)>[];
    var current = start;
    while (!seen.contains(current)) {
      seen.add(current);
      ring.add(current);
      final next = adjacency[to(current)]!;
      final reverse = next.indexOf((current.$1, !current.$2));
      if (reverse < 0 || next.isEmpty) break;
      current = next[(reverse - 1 + next.length) % next.length];
    }
    if (!ring.any((d) => _boundaryRoad(roads[d.$1]!)) ||
        ring.any((d) => ambiguous.contains(d.$1)) ||
        current != start ||
        ring.length < 2 ||
        ring.map(from).toSet().length != ring.length) {
      continue;
    }
    final polygon = [
      for (final d in ring) ...points(d).take(points(d).length - 1),
    ];
    if (polygon.length < 3) continue;
    final origin = polygon.first;
    Offset xy(Offset p) => Offset(
      (p.dx - origin.dx) * 111320 * math.cos(origin.dy * math.pi / 180),
      (p.dy - origin.dy) * 111320,
    );
    final metric = polygon.map(xy).toList();
    var signedArea = 0.0;
    for (var i = 0; i < metric.length; i++) {
      signedArea += _cross(metric[i], metric[(i + 1) % metric.length]);
    }
    final area = signedArea / 2;
    final perimeter = ring.fold(0.0, (n, d) => n + lineLength(points(d)));
    if (area < 1000 || 2 * area / perimeter < 10 || !_simple(metric)) continue;
    // Equivalent carriageways can enclose a median wider than the raw width
    // cutoff. Collapse their display geometry before accepting the face, so a
    // road divider cannot become an extra challenge or award.
    final projected = <Offset>[];
    for (final d in ring) {
      final parts = display.geometry(roads[d.$1]!);
      for (final part in d.$2 ? parts : parts.reversed) {
        projected.addAll(d.$2 ? part.points : part.points.reversed);
      }
    }
    final projectedMetric = projected.map(xy).toList();
    var projectedArea = 0.0, projectedLength = 0.0;
    for (var i = 0; i < projectedMetric.length; i++) {
      final a = projectedMetric[i],
          b = projectedMetric[(i + 1) % projectedMetric.length];
      projectedArea += _cross(a, b);
      projectedLength += (b - a).distance;
    }
    if (projectedArea / 2 < 1000 ||
        projectedLength == 0 ||
        projectedArea / projectedLength < 10) {
      continue;
    }
    // A 30 m safety neighbourhood must lie inside the union of downloaded boxes.
    if (!_insideUnion(polygon, networks)) continue;
    final ids = ring.map((d) => d.$1).toList()..sort();
    blocks.add(
      StreetBlock(
        '$blockRevision/${sha256.convert(utf8.encode(ids.join("-")))}',
        [
          for (final d in ring)
            BlockBoundary(points(d), lineLength(points(d)), {
              for (final entry in evidence[d.$1]!.entries)
                entry.key: [
                  for (final interval in entry.value)
                    if (d.$2) interval else (1 - interval.$2, 1 - interval.$1),
                ],
            }),
        ],
      ),
    );
  }
  // Disconnected interior street loops would require polygon holes. Omit the
  // containing face rather than fill over another block or count overlapping area.
  final faceIndex = MapSpatialIndex<StreetBlock>(cellSize: .001);
  for (final block in blocks) {
    faceIndex.add(block, block.bounds);
  }
  final nestedParents = <String>{};
  for (final child in blocks) {
    for (final parent in faceIndex.query(child.bounds)) {
      if (parent == child || parent.points.any(child.points.contains)) continue;
      if (_containsPoint(parent.points, child.points.first)) {
        nestedParents.add(parent.id);
      }
    }
  }
  return BlockTopology(
    List.unmodifiable(blocks.where((b) => !nestedParents.contains(b.id))),
    needsRefresh: needsRefresh,
  );
}

double _cross(Offset a, Offset b) => a.dx * b.dy - a.dy * b.dx;
double _fraction(Offset a, Offset b, Offset p, {bool clamp = true}) {
  final cos = math.cos(a.dy * math.pi / 180);
  final v = Offset((b.dx - a.dx) * cos, b.dy - a.dy),
      w = Offset((p.dx - a.dx) * cos, p.dy - a.dy);
  final value = v.distanceSquared == 0
      ? 0.0
      : (w.dx * v.dx + w.dy * v.dy) / v.distanceSquared;
  return clamp ? value.clamp(0.0, 1.0) : value;
}

double _lineDistance(Offset a, Offset b, Offset p) =>
    metres(a + (b - a) * _fraction(a, b, p, clamp: false), p);

bool _simple(List<Offset> p) {
  final index = MapSpatialIndex<int>();
  for (var i = 0; i < p.length; i++) {
    final a = p[i], b = p[(i + 1) % p.length];
    final bounds = Rect.fromPoints(a, b).inflate(.001);
    for (final j in index.query(bounds)) {
      if (j == i - 1 || (i == p.length - 1 && j == 0)) continue;
      final c = p[j], d = p[(j + 1) % p.length];
      if (_cross(b - a, c - a) * _cross(b - a, d - a) <= 0 &&
          _cross(d - c, a - c) * _cross(d - c, b - c) <= 0) {
        return false;
      }
    }
    index.add(i, bounds);
  }
  return true;
}

bool _insideUnion(List<Offset> polygon, List<AreaNetwork> maps) {
  // Cover each expanded segment box exactly with the union of map rectangles.
  for (var i = 0; i < polygon.length; i++) {
    final a = polygon[i], b = polygon[(i + 1) % polygon.length];
    final dx = 30 / (111320 * math.cos(a.dy * math.pi / 180)), dy = 30 / 111320;
    final r = Rect.fromPoints(a, b);
    var uncovered = [
      Rect.fromLTRB(r.left - dx, r.top - dy, r.right + dx, r.bottom + dy),
    ];
    for (final map in maps) {
      final box = Rect.fromLTRB(
        map.bbox[0],
        map.bbox[1],
        map.bbox[2],
        map.bbox[3],
      );
      uncovered = [for (final part in uncovered) ..._subtract(part, box)];
      if (uncovered.isEmpty) break;
    }
    if (uncovered.isNotEmpty) return false;
  }
  return true;
}

List<Rect> _subtract(Rect a, Rect b) {
  if (!a.overlaps(b)) return [a];
  final i = a.intersect(b);
  return [
    if (a.left < i.left) Rect.fromLTRB(a.left, a.top, i.left, a.bottom),
    if (i.right < a.right) Rect.fromLTRB(i.right, a.top, a.right, a.bottom),
    if (a.top < i.top) Rect.fromLTRB(i.left, a.top, i.right, i.top),
    if (i.bottom < a.bottom) Rect.fromLTRB(i.left, i.bottom, i.right, a.bottom),
  ];
}

/// Crossing lines without a shared OSM node are ambiguous, even at ground
/// level. Reject affected faces instead of inventing connectivity.
Set<int> _ambiguousEdges(Iterable<AreaEdge> edges) {
  final list = edges.toList();
  if (list.isEmpty) return {};
  final origin = list.first.points.first;
  Offset xy(Offset p) => Offset(
    (p.dx - origin.dx) * 111320 * math.cos(origin.dy * math.pi / 180),
    (p.dy - origin.dy) * 111320,
  );
  final index = MapSpatialIndex<(AreaEdge, Offset, Offset)>(cellSize: 100);
  final bad = <int>{};
  final nodePositions = <int, Offset>{};
  final nodeEdges = <int, Set<int>>{};
  for (final e in list) {
    for (final pair in [
      (e.fromNode!, e.points.first),
      (e.toNode!, e.points.last),
    ]) {
      (nodeEdges[pair.$1] ??= {}).add(e.id);
      final existing = nodePositions.putIfAbsent(pair.$1, () => pair.$2);
      if (metres(existing, pair.$2) > .5) bad.addAll(nodeEdges[pair.$1]!);
    }
    for (var i = 1; i < e.points.length; i++) {
      final a = xy(e.points[i - 1]), b = xy(e.points[i]);
      final bounds = Rect.fromPoints(a, b).inflate(.001);
      for (final other in index.query(bounds)) {
        if (other.$1.id == e.id) continue;
        final c = other.$2, d = other.$3;
        if (_cross(b - a, c - a) * _cross(b - a, d - a) > 0 ||
            _cross(d - c, a - c) * _cross(d - c, b - c) > 0) {
          continue;
        }
        final shared = {
          e.fromNode,
          e.toNode,
        }.intersection({other.$1.fromNode, other.$1.toNode});
        final legitimate = shared.any((node) {
          final point = xy(nodePositions[node]!);
          return ((a - point).distance < .01 || (b - point).distance < .01) &&
              ((c - point).distance < .01 || (d - point).distance < .01);
        });
        if (!legitimate) {
          bad.add(e.id);
          bad.add(other.$1.id);
        }
      }
      index.add((e, a, b), bounds);
    }
  }
  return bad;
}

bool _containsPoint(List<Offset> poly, Offset p) {
  var inside = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final a = poly[i], b = poly[j];
    if ((a.dy > p.dy) != (b.dy > p.dy) &&
        p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
      inside = !inside;
    }
  }
  return inside;
}
