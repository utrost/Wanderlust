import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanderlust/coverage/street_display.dart';
import 'package:wanderlust/data/area_network.dart';
import 'coverage_sections_test.dart' show longStreet;

Offset p(double x, double y) => Offset(x / 111195, y / 111195);
AreaEdge road(
  int id,
  double x,
  double end,
  double y, {
  String name = 'Main',
  String highway = 'secondary',
  String layer = '',
  String bridge = '',
  String footway = '',
  int? way,
}) => AreaEdge(
  id,
  [p(x, y), p(end, y)],
  name,
  wayId: way ?? id,
  highway: highway,
  layer: layer,
  bridge: bridge,
  footway: footway,
);

void main() {
  test('legacy maps without stable way IDs keep their geometry', () {
    final a = AreaEdge(1, [p(0, 0), p(60, 0)], 'Main', highway: 'secondary');
    final b = AreaEdge(2, [p(10, 12), p(40, 12)], 'Main', highway: 'secondary');
    final result = StreetDisplay([a, b]).geometry(b);
    expect(result.single.points.first.dy * 111195, closeTo(12, 0.01));
  });
  test('map refinement retains identity and level metadata for display', () {
    final data = jsonDecode(longStreet());
    data['features'][0]['properties'].addAll({
      'osm_way_id': 42,
      'highway': 'footway',
      'footway': 'sidewalk',
      'layer': '1',
      'bridge': 'yes',
      'tunnel': 'no',
    });
    final area = AreaNetwork.parse(jsonEncode(data));
    expect(area.edges.length, greaterThan(1));
    for (final edge in area.edges) {
      expect(edge.wayId, 42);
      expect(edge.highway, 'footway');
      expect(edge.footway, 'sidewalk');
      expect(edge.layer, '1');
      expect(edge.bridge, 'yes');
      expect(edge.tunnel, 'no');
    }
  });
  test(
    'parallel roads use one stable geometry independent of visited side',
    () {
      final a = road(1, 0, 60, 0);
      final b = road(2, 10, 40, 12);
      final display = StreetDisplay([b, a]);
      final result = display.geometry(b);
      expect(result.single.id, b.id);
      expect(result.single.points.first.dx * 111195, closeTo(10, 0.01));
      expect(result.single.points.last.dx * 111195, closeTo(40, 0.01));
      expect(result.single.points.every((p) => p.dy.abs() < 1e-8), isTrue);
      expect(identical(result, display.geometry(b)), isTrue);
    },
  );
  test('misaligned subdivisions clip to the actually visited interval', () {
    final a = road(1, 0, 15, 0, way: 1);
    final b = road(2, 15, 30, 0, way: 1);
    final side = road(3, 8, 23, 10, way: 2);
    final result = StreetDisplay([a, b, side]).geometry(side);
    expect(result.length, 2);
    expect(result.first.points.first.dx * 111195, closeTo(8, 0.01));
    expect(result.first.points.last.dx * 111195, closeTo(15, 0.01));
    expect(result.last.points.last.dx * 111195, closeTo(23, 0.01));
    expect(
      result.expand((e) => e.points).every((p) => p.dy.abs() < 1e-8),
      isTrue,
    );
  });
  test('a named roadside sidewalk projects onto the road', () {
    final a = road(10, 0, 60, 0);
    final side = road(1, 10, 40, 8, highway: 'footway', footway: 'sidewalk');
    expect(StreetDisplay([a, side]).geometry(side).single.points.first.dy, 0);
  });
  test(
    'distinct streets, park paths, levels and distant roads stay separate',
    () {
      final a = road(1, 0, 60, 0);
      for (final b in [
        road(2, 10, 40, 12, name: 'Other'),
        road(2, 10, 40, 12, highway: 'path'),
        road(2, 10, 40, 12, highway: 'footway'),
        road(2, 10, 40, 12, layer: '1'),
        road(2, 10, 40, 12, bridge: 'yes'),
        road(2, 10, 40, 30),
      ]) {
        final result = StreetDisplay([a, b]).geometry(b);
        expect(
          result.single.points.first.dy,
          closeTo(b.points.first.dy, 1e-10),
        );
      }
    },
  );
  test('perpendicular branches retain their own geometry', () {
    final a = road(1, 0, 60, 0);
    final b = AreaEdge(2, [p(20, 0), p(20, 15)], 'Main', highway: 'secondary');
    final result = StreetDisplay([a, b]).geometry(b);
    expect(result.single.points.last.dy * 111195, closeTo(15, 0.01));
  });
  test('uncovered continuation is never extended to the end of a road', () {
    final a = road(1, 0, 15, 0);
    final b = road(2, 8, 23, 10);
    final result = StreetDisplay([a, b]).geometry(b);
    expect(result.length, 2);
    expect(result.first.points.last.dx * 111195, closeTo(15, 0.01));
    expect(result.last.points.last.dx * 111195, closeTo(23, 0.01));
    expect(result.last.points.last.dy * 111195, closeTo(10, 0.01));
  });
}
