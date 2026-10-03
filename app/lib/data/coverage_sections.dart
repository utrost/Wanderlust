import 'dart:convert';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';

/// Derive short coverage geometry without changing saved-map selection identity.
/// Canonical parent OSM edge IDs make sections stable across overlapping maps.
class CoverageSections {
  static const revision = 'sections-15m-v1';

  static int _id(String value) => int.parse(
    sha256.convert(utf8.encode(value)).toString().substring(0, 13),
    radix: 16,
  );
  static double _distance(List<double> a, List<double> b) {
    final lat = (a[1] + b[1]) / 2 * math.pi / 180;
    return math.sqrt(
          math.pow((a[0] - b[0]) * math.cos(lat), 2) + math.pow(a[1] - b[1], 2),
        ) *
        111320;
  }

  static bool refine(Map<String, dynamic> json) {
    final meta = json['wanderlust_network'] as Map<String, dynamic>;
    if (meta['coverage_sections'] == revision) return true;
    // Only canonical, topology-aware OSM networks have stable parent identities.
    if (meta['edge_id_scheme'] != 'sha256-osm-way-node-chain-52bit-v2') {
      return false;
    }
    final features = <Map<String, dynamic>>[];
    for (final raw in json['features'] as List) {
      final f = raw as Map<String, dynamic>;
      final properties = f['properties'] as Map<String, dynamic>;
      final coords =
          ((f['geometry'] as Map<String, dynamic>)['coordinates'] as List)
              .map(
                (p) => (p as List).map((v) => (v as num).toDouble()).toList(),
              )
              .toList();
      if (coords.length < 2 ||
          coords.any(
            (p) =>
                p.length != 2 ||
                p.any((v) => !v.isFinite) ||
                p[0].abs() > 180 ||
                p[1].abs() > 90,
          )) {
        throw const FormatException('Invalid street geometry');
      }
      final cumulative = <double>[0];
      for (var i = 1; i < coords.length; i++) {
        cumulative.add(cumulative.last + _distance(coords[i - 1], coords[i]));
      }
      final length = cumulative.last;
      final count = math.max(
        1,
        math.max((length / 15).round(), (length / 20).ceil()),
      );
      if (count > 10000 || features.length + count > 300000) {
        throw const FormatException('Street network is too large to refine');
      }
      if (count == 1) {
        features.add(f);
        continue;
      }
      List<double> at(double distance) {
        if (distance <= 0) return coords.first;
        if (distance >= length) return coords.last;
        var i = 1;
        while (cumulative[i] < distance) {
          i++;
        }
        final span = cumulative[i] - cumulative[i - 1];
        final fraction = span == 0
            ? 0.0
            : (distance - cumulative[i - 1]) / span;
        return [
          for (var axis = 0; axis < 2; axis++)
            coords[i - 1][axis] +
                (coords[i][axis] - coords[i - 1][axis]) * fraction,
        ];
      }

      // Reserve the upper half of JSON-safe integers for synthetic nodes.
      if ((properties['from_node'] as int) >= (1 << 52) ||
          (properties['to_node'] as int) >= (1 << 52)) {
        throw const FormatException(
          'OSM node ID exceeds reserved topology range',
        );
      }
      int node(int i) => i == 0
          ? properties['from_node'] as int
          : i == count
          ? properties['to_node'] as int
          : (1 << 52) + _id('$revision/node/${f['id']}/$i');
      for (var part = 0; part < count; part++) {
        final start = length * part / count, end = length * (part + 1) / count;
        features.add({
          ...f,
          'id': _id('$revision/edge/${f['id']}/$part'),
          'properties': {
            ...properties,
            'from_node': node(part),
            'to_node': node(part + 1),
            'length_m': end - start,
            'coverage_parent': f['id'],
          },
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              at(start),
              for (var i = 1; i < coords.length - 1; i++)
                if (cumulative[i] > start && cumulative[i] < end) coords[i],
              at(end),
            ],
          },
        });
      }
    }
    json['features'] = features;
    meta['coverage_sections'] = revision;
    return true;
  }
}
