import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanderlust/data/area_network.dart';
import 'package:wanderlust/geo/geo_core_ffi.dart';
import 'coverage_test.dart' show networkJson;

String longStreet({String version = 'source'}) {
  final data =
      jsonDecode(networkJson(version: version)) as Map<String, dynamic>;
  data['wanderlust_network']['edge_id_scheme'] =
      'sha256-osm-way-node-chain-52bit-v2';
  data['features'] = [
    {
      'type': 'Feature',
      'id': 123,
      'properties': {'from_node': 100, 'to_node': 101, 'name': 'Test street'},
      'geometry': {
        'type': 'LineString',
        'coordinates': [
          [0, 0],
          [0.0003, 0],
          [0.0009, 0],
        ],
      },
    },
  ];
  data['bbox'] = [-0.01, -0.01, 0.01, 0.01];
  return jsonEncode(data);
}

void main() {
  test(
    'existing maps refine into connected 10–20 m portions without changing selection identity',
    () {
      final a = AreaNetwork.parse(longStreet());
      final b = AreaNetwork.parse(longStreet(version: 'overlap'));
      expect(a.version, 'source');
      expect(a.coverageVersion, isNot(a.version));
      expect(a.edgeIds, b.edgeIds);
      expect(AreaNetwork.parse(a.geojson).geojson, a.geojson);
      final features = jsonDecode(a.geojson)['features'] as List;
      expect(features.length, greaterThan(5));
      for (var i = 0; i < features.length; i++) {
        final p = features[i]['properties'];
        expect(p['length_m'], inInclusiveRange(10, 20));
        if (i > 0) {
          expect(features[i - 1]['properties']['to_node'], p['from_node']);
          expect(
            features[i - 1]['geometry']['coordinates'].last,
            features[i]['geometry']['coordinates'].first,
          );
        }
      }
      expect(features.first['properties']['from_node'], 100);
      expect(features.last['properties']['to_node'], 101);
      expect(
        a.edges.expand((e) => e.points).where((p) => p.dx == 0.0003),
        isNotEmpty,
      );
    },
  );
  test('native matching credits only the walked portion of a long street', () {
    final area = AreaNetwork.parse(longStreet());
    final matcher = WanderlustGeo.open().loadNetwork(area.geojson);
    try {
      final gpx =
          '<gpx><trk><trkseg>${[2, 5, 8, 10].asMap().entries.map((e) => '<trkpt lon="${e.value / 111320}" lat="0"><time>2026-10-03T10:00:${(e.key * 5).toString().padLeft(2, '0')}Z</time></trkpt>').join()}</trkseg></trk></gpx>';
      final result = matcher.matchGpx(gpx, fillSmallGaps: true);
      expect(result.walked, [area.edges.first.id]);
    } finally {
      matcher.dispose();
    }
  }, skip: Platform.environment['WANDERLUST_NATIVE_TESTS'] != '1');
}
