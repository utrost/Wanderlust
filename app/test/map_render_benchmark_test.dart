import 'package:wanderlust/maps/map_cells.dart';
import 'package:wanderlust/blocks/block_geometry.dart';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanderlust/data/area_network.dart';
import 'package:wanderlust/widgets/area_map.dart';

void main() {
  testWidgets('10 km synthetic map pan benchmark', (tester) async {
    final features = <Object>[];
    var id = 1;
    for (var x = 0; x < 100; x++) {
      for (var y = 0; y < 100; y++) {
        final lon = 8.7 + x * .0015, lat = 53.0 + y * .0009;
        for (final end in [
          [lon + .0015, lat],
          [lon, lat + .0009],
        ]) {
          features.add({
            'type': 'Feature',
            'id': id++,
            'geometry': {
              'type': 'LineString',
              'coordinates': [
                [lon, lat],
                end,
              ],
            },
            'properties': {'name': 'Street $x', 'highway': 'residential'},
          });
        }
      }
    }
    final map = AreaNetwork.parse(
      jsonEncode({
        'type': 'FeatureCollection',
        'bbox': [8.7, 53.0, 8.85, 53.09],
        'wanderlust_network': {
          'version': 1,
          'area_id': 'benchmark',
          'name': '10 km sample',
          'network_version': 'bench',
          'attribution': 'Synthetic',
        },
        'features': features,
      }),
    );
    final cache = MapGeometryCache();
    const size = Size(440, 850);
    final counts = {
      for (final e in map.edges.where((e) => e.id % 30 == 0)) e.id: 1,
    };
    final blocks = <StreetBlock>[
      for (var x = 0; x < 99; x++)
        for (var y = 0; y < 99; y++)
          StreetBlock('$x-$y', [
            BlockBoundary(
              [
                Offset(8.7 + x * .0015, 53 + y * .0009),
                Offset(8.7 + (x + 1) * .0015, 53 + y * .0009),
                Offset(8.7 + (x + 1) * .0015, 53 + (y + 1) * .0009),
                Offset(8.7 + x * .0015, 53 + (y + 1) * .0009),
                Offset(8.7 + x * .0015, 53 + y * .0009),
              ],
              400,
              {},
            ),
          ]),
    ];
    final windowCache = MapGeometryCache();
    final chunks = indexMapCells(map.geojson).toList();
    final windows = [
      for (final c in chunks)
        AreaNetwork.parse(
          mergeCellSources(c['cell'] as String, [c['geojson'] as String]),
        ),
    ];
    final anchor = AreaNetwork.parse(
      emptyMap(map.name, map.bbox, 'benchmark-view'),
    );
    final completed = {for (final b in blocks) b.id};
    int run({bool withBlocks = false, bool windowed = false}) {
      final watch = Stopwatch()..start();
      for (var i = 0; i < 25; i++) {
        final r = ui.PictureRecorder();
        // Warm caches separately; only record this frame into r.
        final canvas = Canvas(r);
        final t = Matrix4.diagonal3Values(12, 12, 1)
          ..setTranslationRaw(-1800 + i * 3, -3300 + i * 2, 0);
        AreaMapPainter(
          blocks: withBlocks ? blocks : const [],
          completedBlocks: withBlocks ? completed : const {},
          network: windowed ? anchor : map,
          networks: windowed ? windows : const [],
          counts: counts,
          geometry: windowed ? windowCache : cache,
          transform: t,
        ).paint(canvas, size);
        r.endRecording().dispose();
      }
      watch.stop();
      return watch.elapsedMilliseconds;
    }

    run();
    run(withBlocks: true);
    run(windowed: true);
    final baseline = <int>[], enabled = <int>[], windowedTimes = <int>[];
    for (var i = 0; i < 7; i++) {
      baseline.add(run());
      enabled.add(run(withBlocks: true));
      windowedTimes.add(run(windowed: true));
    }
    baseline.sort();
    enabled.sort();
    windowedTimes.sort();
    final after = baseline[3], blocksTime = enabled[3];
    debugPrint(
      'BLOCK_PAN_BENCHMARK baseline_ms=$after blocks_ms=$blocksTime polygons=${blocks.length}',
    );
    expect(blocksTime, lessThanOrEqualTo(after * 1.2));
    debugPrint(
      'ACTIVE_MAP_PAN_BENCHMARK baseline_ms=$after windowed_ms=${windowedTimes[3]} cells=${windows.length}',
    );
    expect(windowedTimes[3], lessThanOrEqualTo(after * 1.2));
    debugPrint(
      'PAN_BENCHMARK edges=${map.edges.length} frames=25 indexed_ms=$after',
    );
    expect(
      cache.edgeIndex.query(const Rect.fromLTWH(150, 270, 40, 80)).length,
      lessThan(map.edges.length ~/ 10),
    );
    cache.dispose();
    windowCache.dispose();
  });
}
