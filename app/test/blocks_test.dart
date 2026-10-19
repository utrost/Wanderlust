import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanderlust/blocks/block_geometry.dart';
import 'package:wanderlust/blocks/block_progress.dart';
import 'package:wanderlust/coverage/coverage_evidence.dart';
import 'package:wanderlust/data/area_network.dart';
import 'package:wanderlust/settings/walk_preferences.dart';

Offset p(double x, double y) => Offset(x / 111320, y / 111320);
Map<String, Object> edge(
  int id,
  int from,
  int to,
  List<Offset> points, {
  String highway = 'residential',
  String name = 'Road',
  Map<String, Object> extra = const {},
}) => {
  'type': 'Feature',
  'id': id,
  'properties': {
    'osm_way_id': id,
    'from_node': from,
    'to_node': to,
    'highway': highway,
    'name': name,
    ...extra,
  },
  'geometry': {
    'type': 'LineString',
    'coordinates': [
      for (final p in points) [p.dx, p.dy],
    ],
  },
};
List<Map<String, Object>> square({double size = 100}) => [
  edge(1, 1, 2, [p(0, 0), p(size, 0)], name: 'South'),
  edge(2, 2, 3, [p(size, 0), p(size, size)], name: 'East'),
  edge(3, 3, 4, [p(size, size), p(0, size)], name: 'North'),
  edge(4, 4, 1, [p(0, size), p(0, 0)], name: 'West'),
];
AreaNetwork network(
  List<Map<String, Object>> features, {
  String version = 'test',
  List<double>? bbox,
}) => AreaNetwork.parse(
  jsonEncode({
    'type': 'FeatureCollection',
    'bbox': bbox ?? [-.01, -.01, .01, .01],
    'wanderlust_network': {
      'version': 1,
      'area_id': version,
      'name': version,
      'network_version': version,
      'attribution': 'Synthetic',
    },
    'features': features,
  }),
);
StreetBlock progressBlock(List<double> lengths) => StreetBlock('progress', [
  for (var i = 0; i < lengths.length; i++)
    BlockBoundary(
      [p(i * 10, 0), p((i + 1) * 10, 0)],
      lengths[i],
      {
        i: [(0, 1)],
      },
    ),
]);
void main() {
  test('optional preference roundtrips and old backups default off', () {
    expect(WalkPreferences.fromJson({}).completeBlocks, false);
    final prefs = const WalkPreferences().copyWith(completeBlocks: true);
    expect(WalkPreferences.fromJson(prefs.toJson()).completeBlocks, true);
  });
  test('square, stable across duplicate maps, curved street and dead end', () {
    final features = square();
    features[0] = edge(1, 1, 2, [p(0, 0), p(50, -5), p(100, 0)], name: 'South');
    features.add(edge(5, 3, 5, [p(100, 100), p(130, 130)]));
    final a = network(features), b = network(features, version: 'overlap');
    final one = buildBlockTopology([a]);
    expect(one.blocks.length, 1);
    final two = buildBlockTopology([b, a]);
    expect(two.blocks.single.id, one.blocks.single.id);
    expect(two.blocks.single.boundary.length, 4);
    expect(blockProgress(one.blocks.single, {1, 2, 3, 4}).complete, true);
  });
  test('internal footpath does not subdivide; street does', () {
    final features = square()
      ..add(edge(5, 1, 3, [p(0, 0), p(100, 100)], highway: 'footway'));
    expect(buildBlockTopology([network(features)]).blocks.length, 1);
    features[4] = edge(5, 1, 3, [p(0, 0), p(100, 100)]);
    expect(buildBlockTopology([network(features)]).blocks.length, 2);
  });
  test(
    'bridge, restricted perimeter and missing metadata cannot close a block',
    () {
      for (final extra in [
        {'bridge': 'yes'},
        {'access': 'private'},
        {'layer': '1'},
      ]) {
        final features = square();
        features[0] = edge(1, 1, 2, [p(0, 0), p(100, 0)], extra: extra);
        expect(buildBlockTopology([network(features)]).blocks, isEmpty);
      }
      final features = square();
      (features[0]['properties'] as Map).remove('from_node');
      final result = buildBlockTopology([network(features)]);
      expect(result.needsRefresh, true);
      expect(result.blocks, isEmpty);
    },
  );
  test(
    'map edge is omitted, overlapping boxes jointly provide safety margin',
    () {
      final f = square();
      final left = network(f, bbox: [-.001, -.001, 50 / 111320, .002]);
      final right = network(
        f,
        version: 'right',
        bbox: [40 / 111320, -.001, .002, .002],
      );
      expect(buildBlockTopology([left]).blocks, isEmpty);
      expect(buildBlockTopology([left, right]).blocks.length, 1);
    },
  );
  test('narrow divider and tiny blocks are excluded', () {
    expect(buildBlockTopology([network(square(size: 20))]).blocks, isEmpty);
    final f = [
      edge(1, 1, 2, [p(0, 0), p(400, 0)]),
      edge(2, 2, 3, [p(400, 0), p(400, 4)]),
      edge(3, 3, 4, [p(400, 4), p(0, 4)]),
      edge(4, 4, 1, [p(0, 4), p(0, 0)]),
    ];
    expect(buildBlockTopology([network(f)]).blocks, isEmpty);
  });
  test('parallel sidewalk transfers only its overlapping length', () {
    final f = square()
      ..add(
        edge(
          5,
          5,
          6,
          [p(0, -5), p(50, -5)],
          highway: 'footway',
          name: 'South',
          extra: {'footway': 'sidewalk'},
        ),
      );
    final block = buildBlockTopology([network(f)]).blocks.single;
    final progress = blockProgress(block, {2, 3, 4, 5});
    expect(progress.covered, closeTo(350, .1));
    expect(progress.complete, false);
    expect(blockProgress(block, {1, 2, 3, 4, 5}).covered, closeTo(400, .1));
  });
  test('unrelated parallel street never supplies coverage', () {
    final f = square()
      ..add(edge(5, 5, 6, [p(0, -5), p(100, -5)], name: 'Other'));
    final block = buildBlockTopology([network(f)]).blocks.single;
    expect(blockProgress(block, {2, 3, 4, 5}).covered, closeTo(300, .1));
  });
  test('divided road accepts either lane without creating a divider block', () {
    final f = square()
      ..addAll([
        edge(5, 5, 6, [p(0, -6), p(100, -6)], name: 'South'),
        edge(6, 1, 5, [p(0, 0), p(0, -6)], highway: 'service'),
        edge(7, 2, 6, [p(100, 0), p(100, -6)], highway: 'service'),
      ]);
    final result = buildBlockTopology([network(f)]);
    expect(result.blocks.length, 1);
    expect(blockProgress(result.blocks.single, {2, 3, 4, 5}).complete, true);
  });
  test('crossing ground street without a shared node is ambiguous', () {
    final f = square()
      ..addAll([
        edge(5, 5, 6, [p(-40, 50), p(140, 50)]),
        edge(6, 6, 7, [p(140, 50), p(140, 150)]),
        edge(7, 7, 5, [p(140, 150), p(-40, 50)]),
      ]);
    expect(buildBlockTopology([network(f)]).blocks, isEmpty);
  });
  test('coincident rail or unrelated street cannot award a road', () {
    for (final highway in ['railway', 'residential']) {
      final f = square()
        ..add(
          edge(
            5,
            5,
            6,
            [p(0, 0), p(100, 0)],
            highway: highway,
            name: 'Different',
          ),
        );
      // Unrelated overlapping road geometry is ambiguous; rail is not a boundary.
      final result = buildBlockTopology([network(f)]);
      if (highway == 'railway') {
        expect(
          blockProgress(result.blocks.single, {2, 3, 4, 5}).complete,
          false,
        );
      } else {
        expect(result.blocks, isEmpty);
      }
    }
  });
  test('nested disconnected street loop omits the containing face', () {
    final f = square(size: 300)
      ..addAll([
        edge(5, 5, 6, [p(100, 100), p(200, 100)]),
        edge(6, 6, 7, [p(200, 100), p(200, 200)]),
        edge(7, 7, 8, [p(200, 200), p(100, 200)]),
        edge(8, 8, 5, [p(100, 200), p(100, 100)]),
      ]);
    final result = buildBlockTopology([network(f)]);
    expect(result.blocks.length, 1);
    expect(result.blocks.single.perimeter, closeTo(400, .1));
  });
  test('95 percent and 20 metre gap boundaries are inclusive', () {
    expect(blockProgress(progressBlock([20, 380]), {1}).complete, true);
    expect(blockProgress(progressBlock([20.1, 379.9]), {1}).complete, false);
    expect(blockProgress(progressBlock([10, 100]), {1}).complete, false);
    expect(blockProgress(progressBlock([30, 970]), {1}).complete, false);
  });
  test('gaps wrap around polygon; adjacent gaps combine', () {
    final block = progressBlock([11, 480, 10]);
    expect(blockProgress(block, {1}).longestGap, 21);
    expect(blockProgress(block, {1}).complete, false);
    expect(blockProgress(progressBlock([10, 480, 10]), {1}).complete, true);
    expect(blockProgress(block, {}).longestGap, 501);
    expect(blockProgress(block, {}).covered, 0);
  });
  test('supported evidence accumulates, deduplicates and can be removed', () {
    final evidence = CoverageEvidence();
    evidence.put(1, 'a', {1, 2}, {3, 4});
    evidence.put(2, 'b', {3, 4}, {});
    final block = buildBlockTopology([network(square())]).blocks.single;
    expect(blockProgress(block, evidence.supported(['a'])).complete, false);
    expect(blockProgress(block, evidence.supported(['a', 'b'])).complete, true);
    evidence.retain({1});
    expect(
      blockProgress(block, evidence.supported(['a', 'b'])).complete,
      false,
    );
    // Explicit confirmation enters the supported set, even if also inferred.
    evidence.put(1, 'a', {1, 2, 3, 4}, {3, 4});
    expect(evidence.estimated(['a']), isEmpty);
    expect(blockProgress(block, evidence.supported(['a'])).complete, true);
  });
}
