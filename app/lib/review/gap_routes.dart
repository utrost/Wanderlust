import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../recording/saved_walk.dart';
import '../transfer/walk_codec.dart';

/// A suggestion is display-only until explicitly accepted. Raw fixes stay intact.
class GapRoute {
  const GapRoute(this.edges, this.coordinates, this.meters);
  final List<int> edges;
  final List<Offset> coordinates;
  final double meters;
}

class ReviewGap {
  const ReviewGap(this.start, this.end, this.routes);
  final DateTime start, end;
  final List<GapRoute> routes;
}

class _Edge {
  _Edge(this.id, this.a, this.b, this.points);
  final int id, a, b;
  final List<Offset> points;
  late final double length = List.generate(
    points.length - 1,
    (i) => _distance(points[i], points[i + 1]),
  ).fold(0, (a, b) => a + b);
}

double _distance(Offset a, Offset b) =>
    111320 *
    math.sqrt(
      math.pow((a.dx - b.dx) * math.cos((a.dy + b.dy) * math.pi / 360), 2) +
          math.pow(a.dy - b.dy, 2),
    );

Future<List<ReviewGap>> suggestGapRoutes(List<String> maps, SavedWalk walk) =>
    compute(_suggest, (maps, walk));

List<ReviewGap> _suggest((List<String>, SavedWalk) input) {
  final walk = input.$2;
  final anchors = _gapAnchors(walk).take(30).toList();
  if (anchors.isEmpty) return [];
  final edges = <int, _Edge>{};
  for (final source in input.$1) {
    final data = jsonDecode(source) as Map;
    for (final f in data['features'] as List) {
      final p = f['properties'] as Map;
      if (p['from_node'] is! int || p['to_node'] is! int) continue;
      edges[f['id'] as int] =
          _Edge(f['id'] as int, p['from_node'] as int, p['to_node'] as int, [
            for (final c in f['geometry']['coordinates'] as List)
              Offset((c[0] as num).toDouble(), (c[1] as num).toDouble()),
          ]);
    }
  }
  final nodes = <int, Offset>{}, adjacency = <int, List<_Edge>>{};
  for (final e in edges.values) {
    nodes[e.a] = e.points.first;
    nodes[e.b] = e.points.last;
    (adjacency[e.a] ??= []).add(e);
    (adjacency[e.b] ??= []).add(e);
  }
  int? nearest(Offset p) {
    int? found;
    var best = 25.0;
    for (final entry in nodes.entries) {
      final d = _distance(p, entry.value);
      if (d < best) {
        best = d;
        found = entry.key;
      }
    }
    return found;
  }

  GapRoute? route(int start, int end, double budget, Set<int> banned) {
    final distances = <int, double>{start: 0}, previous = <int, (int, _Edge)>{};
    final open = <int>{start}, visited = <int>{};
    while (open.isNotEmpty && visited.length < 12000) {
      final n = open.reduce((a, b) => distances[a]! < distances[b]! ? a : b);
      open.remove(n);
      if (n == end) {
        final path = <(int, _Edge)>[];
        var current = end;
        while (current != start) {
          final step = previous[current]!;
          path.add(step);
          current = step.$1;
        }
        final ordered = path.reversed.toList();
        return GapRoute(
          [for (final step in ordered) step.$2.id],
          [
            for (final step in ordered)
              ...(step.$1 == step.$2.a
                  ? step.$2.points
                  : step.$2.points.reversed),
          ],
          distances[end]!,
        );
      }
      visited.add(n);
      for (final e in adjacency[n] ?? <_Edge>[]) {
        if (banned.contains(e.id)) continue;
        final next = e.a == n ? e.b : e.a, cost = distances[n]! + e.length;
        if (visited.contains(next) ||
            cost > budget ||
            cost >= (distances[next] ?? double.infinity)) {
          continue;
        }
        distances[next] = cost;
        previous[next] = (n, e);
        open.add(next);
      }
    }
    return null;
  }

  final result = <ReviewGap>[];
  for (final (startIndex, endIndex) in anchors) {
    final a = walk.points[startIndex], p = walk.points[endIndex];
    final seconds = p.timestamp.difference(a.timestamp).inMilliseconds / 1000;
    final from = Offset(a.longitude, a.latitude),
        to = Offset(p.longitude, p.latitude);
    final straight = _distance(from, to);
    final start = nearest(from), end = nearest(to);
    final routes = <GapRoute>[];
    final budget = math.min(
      600.0,
      math.min(seconds * walk.activity.gapSpeed, straight * 1.8 + 30),
    );
    if (start != null && end != null && start != end) {
      final first = route(start, end, budget, {});
      if (first != null) {
        routes.add(first);
        // Search alternate connections by excluding each shortest-path edge.
        // Bounded work; these are options, never a claim of route certainty.
        for (final edge in first.edges.take(80)) {
          final alternative = route(start, end, budget, {edge});
          if (alternative != null &&
              !routes.any((r) => listEquals(r.edges, alternative.edges))) {
            routes.add(alternative);
          }
        }
        routes.sort((a, b) => a.meters.compareTo(b.meters));
      }
    }
    result.add(ReviewGap(a.timestamp, p.timestamp, routes.take(3).toList()));
  }
  return result;
}

bool hasReviewableGaps(SavedWalk walk) => _gapAnchors(walk).isNotEmpty;

Iterable<(int, int)> _gapAnchors(SavedWalk walk) sync* {
  final breaks = walk.segmentStarts.toSet(), untimed = walk.untimed.toSet();
  int? anchor;
  for (var i = 0; i < walk.points.length; i++) {
    final p = walk.points[i];
    if (breaks.contains(i) ||
        untimed.contains(i) ||
        (i > 0 && !p.timestamp.isAfter(walk.points[i - 1].timestamp))) {
      anchor = null;
    }
    if (untimed.contains(i) || !p.accuracy.isFinite || p.accuracy > 25) {
      continue;
    }
    if (anchor != null) {
      final a = walk.points[anchor];
      final seconds = p.timestamp.difference(a.timestamp).inMilliseconds / 1000;
      if (seconds > 30 &&
          seconds <= 300 &&
          _distance(
                Offset(a.longitude, a.latitude),
                Offset(p.longitude, p.latitude),
              ) >=
              25) {
        yield (anchor, i);
      }
    }
    anchor = i;
  }
}

/// Same bounded candidates as manual review; automatically choose the shortest.
/// Explicit confirmations take precedence over an automatic alternative.
Future<List<Set<int>>> automaticGapSections(
  String network,
  List<String> gpx,
  List<List<int>> confirmed,
) => compute(_automatic, (network, gpx, confirmed));

List<Set<int>> _automatic((String, List<String>, List<List<int>>) input) => [
  for (var i = 0; i < input.$2.length; i++)
    {
      for (final gap in _suggest((
        [input.$1],
        WalkCodec.importGpx(input.$2[i]),
      )))
        if (gap.routes.isNotEmpty &&
            !gap.routes.any((r) => input.$3[i].toSet().containsAll(r.edges)))
          ...gap.routes.first.edges,
    },
];
