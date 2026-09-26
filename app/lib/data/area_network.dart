import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

class AreaEdge {
  const AreaEdge(this.id, this.points, this.name);
  final int id;
  final List<Offset> points; // longitude, latitude
  final String? name;
}

/// The exact same normalized GeoJSON is used by the renderer and Rust matcher.
class AreaNetwork {
  AreaNetwork._(
    this.geojson,
    this.areaId,
    this.name,
    this.version,
    this.bbox,
    this.edges,
    this.attribution,
  );
  final String geojson;
  final String areaId;
  final String name;
  final String version;
  final List<double> bbox;
  final List<AreaEdge> edges;
  final String attribution;
  late final Set<int> edgeIds = edges.map((e) => e.id).toSet();

  factory AreaNetwork.parse(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    final meta = json['wanderlust_network'] as Map<String, dynamic>;
    if (json['type'] != 'FeatureCollection' || meta['version'] != 1) {
      throw const FormatException('Unsupported area network');
    }
    final bbox = (json['bbox'] as List)
        .map((n) => (n as num).toDouble())
        .toList();
    if (bbox.length != 4 ||
        bbox.any((n) => !n.isFinite) ||
        bbox[0] >= bbox[2] ||
        bbox[1] >= bbox[3]) {
      throw const FormatException('Invalid area bounds');
    }
    final ids = <int>{};
    final edges = (json['features'] as List)
        .map((value) {
          final f = value as Map<String, dynamic>;
          final id = f['id'] as int;
          if (id <= 0 || id > 9007199254740991 || !ids.add(id)) {
            throw const FormatException('Invalid or duplicate street id');
          }
          final geometry = f['geometry'] as Map<String, dynamic>;
          if (geometry['type'] != 'LineString') {
            throw const FormatException('Expected LineString');
          }
          final points = (geometry['coordinates'] as List)
              .map((p) {
                final pair = p as List;
                if (pair.length != 2) {
                  throw const FormatException('Invalid coordinate');
                }
                final point = Offset(
                  (pair[0] as num).toDouble(),
                  (pair[1] as num).toDouble(),
                );
                if (!point.dx.isFinite ||
                    !point.dy.isFinite ||
                    point.dx.abs() > 180 ||
                    point.dy.abs() > 90) {
                  throw const FormatException('Coordinate out of range');
                }
                return point;
              })
              .toList(growable: false);
          if (points.length < 2) {
            throw const FormatException('Street has no geometry');
          }
          return AreaEdge(
            id,
            points,
            (f['properties'] as Map<String, dynamic>)['name'] as String?,
          );
        })
        .toList(growable: false);
    if (edges.isEmpty) throw const FormatException('Empty street network');
    return AreaNetwork._(
      source,
      meta['area_id'] as String,
      meta['name'] as String,
      meta['network_version'] as String,
      bbox,
      edges,
      meta['attribution'] as String,
    );
  }

  /// Local equirectangular projection: north is up, aspect ratio is preserved.
  Offset project(Offset coordinate, Size size) {
    final cosine = math.cos((bbox[1] + bbox[3]) / 2 * math.pi / 180);
    final width = (bbox[2] - bbox[0]) * cosine;
    final height = bbox[3] - bbox[1];
    final scale = math.min(size.width / width, size.height / height);
    return Offset(
      (size.width - width * scale) / 2 +
          (coordinate.dx - bbox[0]) * cosine * scale,
      (size.height - height * scale) / 2 + (bbox[3] - coordinate.dy) * scale,
    );
  }
}
