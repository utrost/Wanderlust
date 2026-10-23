import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';
import 'map_scenery.dart';
import 'map_place.dart';
import 'coverage_sections.dart';

class AreaEdge {
  const AreaEdge(
    this.id,
    this.points,
    this.name, {
    this.wayId,
    this.fromNode,
    this.toNode,
    this.access = '',
    this.highway = '',
    this.footway = '',
    this.layer = '',
    this.bridge = '',
    this.tunnel = '',
  });
  final int id;
  final List<Offset> points; // longitude, latitude
  final String? name;
  final int? wayId;
  final int? fromNode, toNode;
  final String access;
  final String highway, footway, layer, bridge, tunnel;
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
    this.scenery,
    this.places, [
    this._coverageRevision,
    this.sourceVersions = const [],
    this.footprints = const [],
  ]);
  final List<String> sourceVersions;
  final List<Rect> footprints;
  List<Rect> get coveredFootprints => footprints.isEmpty
      ? [Rect.fromLTRB(bbox[0], bbox[1], bbox[2], bbox[3])]
      : footprints;
  final String geojson;
  final String areaId;
  final String name;
  final String version;
  final List<double> bbox;
  final List<AreaEdge> edges;
  final String attribution;
  final List<MapScenery> scenery;
  final List<MapPlace> places;
  final String? _coverageRevision;
  String get coverageVersion =>
      _coverageRevision == null ? version : '$version/$_coverageRevision';
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
    if (CoverageSections.refine(json)) source = jsonEncode(json);
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
          final properties = f['properties'] as Map<String, dynamic>;
          return AreaEdge(
            id,
            points,
            properties['name'] as String?,
            wayId: (properties['osm_way_id'] as num?)?.toInt(),
            fromNode: (properties['from_node'] as num?)?.toInt(),
            toNode: (properties['to_node'] as num?)?.toInt(),
            access: properties['access']?.toString() ?? '',
            highway: properties['highway']?.toString() ?? '',
            footway: properties['footway']?.toString() ?? '',
            layer: properties['layer']?.toString() ?? '',
            bridge: properties['bridge']?.toString() ?? '',
            tunnel: properties['tunnel']?.toString() ?? '',
          );
        })
        .toList(growable: false);
    if (edges.isEmpty && meta['view_only'] != true) {
      throw const FormatException('Empty street network');
    }
    return AreaNetwork._(
      source,
      meta['area_id'] as String,
      meta['name'] as String,
      meta['network_version'] as String,
      bbox,
      edges,
      meta['attribution'] as String,
      [
        for (final s in json['wanderlust_scenery'] as List? ?? [])
          MapScenery.parse(s as Map<String, dynamic>),
      ],
      [
        for (final p
            in json['wanderlust_places'] is List
                ? json['wanderlust_places'] as List
                : [])
          if (MapPlace.tryParse(p) case final place?) place,
      ],
      meta['coverage_sections'] as String?,
      (meta['source_versions'] as List? ?? [meta['network_version']])
          .cast<String>(),
      [
        for (final b in meta['footprints'] as List? ?? [])
          Rect.fromLTRB(
            (b[0] as num).toDouble(),
            (b[1] as num).toDouble(),
            (b[2] as num).toDouble(),
            (b[3] as num).toDouble(),
          ),
      ],
    );
  }

  factory AreaNetwork.emptyViewport() => AreaNetwork._(
    '',
    'no-map',
    'No downloaded map',
    'no-map',
    [-1, -1, 1, 1],
    [],
    '',
    [],
    [],
  );

  /// Projection-only bounds for reviewing a trace; source geometry stays intact.
  AreaNetwork withViewport(List<double> bounds) => AreaNetwork._(
    geojson,
    areaId,
    name,
    version,
    bounds,
    edges,
    attribution,
    scenery,
    places,
    _coverageRevision,
    sourceVersions,
    footprints,
  );

  bool contains(Offset coordinate) =>
      coordinate.dx >= bbox[0] &&
      coordinate.dx <= bbox[2] &&
      coordinate.dy >= bbox[1] &&
      coordinate.dy <= bbox[3];

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
