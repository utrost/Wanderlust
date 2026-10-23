import 'dart:isolate';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';
import 'package:crypto/crypto.dart';
import '../data/area_network.dart';

/// Latitude bands keep each core cell approximately one square kilometre.
class MapCell {
  const MapCell(this.row, this.column);
  static const latitudeStep = 1000 / 111320;
  final int row, column;
  String get id => '$row:$column';
  double get longitudeStep =>
      latitudeStep / math.cos((row + .5) * latitudeStep * math.pi / 180);
  Rect get core => Rect.fromLTWH(
    column * longitudeStep,
    row * latitudeStep,
    longitudeStep,
    latitudeStep,
  );
  Rect get bounds => Rect.fromLTRB(
    core.left - longitudeStep / 2,
    core.top - latitudeStep / 2,
    core.right + longitudeStep / 2,
    core.bottom + latitudeStep / 2,
  );
  static MapCell at(Offset point) {
    final row = (point.dy / latitudeStep).floor();
    final cell = MapCell(row, 0);
    return MapCell(row, (point.dx / cell.longitudeStep).floor());
  }

  static MapCell parse(String id) {
    final parts = id.split(':');
    return MapCell(int.parse(parts[0]), int.parse(parts[1]));
  }

  static Iterable<MapCell> covering(Rect bounds) sync* {
    for (
      var row = (bounds.top / latitudeStep).floor();
      row <= (bounds.bottom / latitudeStep).floor();
      row++
    ) {
      final step = MapCell(row, 0).longitudeStep;
      for (
        var col = (bounds.left / step).floor();
        col <= (bounds.right / step).floor();
        col++
      ) {
        yield MapCell(row, col);
      }
    }
  }
}

Rect geographicBounds(List<double> b) => Rect.fromLTRB(b[0], b[1], b[2], b[3]);
List<double> boundsList(Rect b) => [b.left, b.top, b.right, b.bottom];

class CellSource {
  const CellSource(
    this.cell,
    this.version,
    this.bytes,
    this.sections, [
    this.digest = '',
  ]);
  final String digest;
  final String cell, version;
  final int bytes, sections;
}

String emptyMap(String name, List<double> bbox, String version) => jsonEncode({
  'type': 'FeatureCollection',
  'bbox': bbox,
  'features': [],
  'wanderlust_network': {
    'version': 1,
    'view_only': true,
    'area_id': version,
    'name': name,
    'network_version': version,
    'attribution': '© OpenStreetMap contributors',
  },
});

/// Worker-only normalisation. Full sections and OSM nodes survive partitioning;
/// the 500m halo provides matching context and prevents artificial block edges.
Iterable<Map<String, Object?>> indexMapCells(String source) sync* {
  final network = AreaNetwork.parse(source);
  final json = jsonDecode(network.geojson) as Map<String, dynamic>;
  final features = (json['features'] as List).cast<Map<String, dynamic>>();
  final rects = [
    for (final e in network.edges)
      (() {
        var r = Rect.fromPoints(e.points.first, e.points.first);
        for (final p in e.points.skip(1)) {
          r = r.expandToInclude(Rect.fromPoints(p, p));
        }
        return r;
      })(),
  ];
  final mapBounds = geographicBounds(network.bbox);
  for (final cell in MapCell.covering(mapBounds)) {
    yield (() {
      final bounds = cell.bounds.intersect(mapBounds);
      final picked = [
        for (var i = 0; i < features.length; i++)
          if (rects[i].inflate(1e-10).overlaps(bounds)) features[i],
      ];
      final value = <String, dynamic>{
        ...json,
        'bbox': boundsList(bounds),
        'features': picked,
      };
      // Scenery/places are spatially filtered too, never copied wholesale per cell.
      for (final key in ['wanderlust_scenery', 'wanderlust_places']) {
        if (json[key] is List) {
          value[key] = [
            for (final item in json[key] as List)
              if (_intersects(item, bounds)) item,
          ];
        }
      }
      final text = jsonEncode(value);
      return <String, Object?>{
        'cell': cell.id,
        'source': network.version,
        'geojson': text,
        'bytes': utf8.encode(text).length,
        'sections': picked.length,
        'digest': sha256
            .convert(
              utf8.encode(
                jsonEncode([
                  boundsList(bounds),
                  picked,
                  value['wanderlust_scenery'],
                  value['wanderlust_places'],
                ]),
              ),
            )
            .toString(),
      };
    })();
  }
}

bool _intersects(dynamic item, Rect bounds) {
  final coords = <Offset>[];
  void visit(dynamic value) {
    if (value is List) {
      if (value.length >= 2 && value[0] is num && value[1] is num) {
        coords.add(
          Offset((value[0] as num).toDouble(), (value[1] as num).toDouble()),
        );
      } else {
        for (final v in value) {
          visit(v);
        }
      }
    } else if (value is Map) {
      for (final key in [
        'point',
        'points',
        'coordinates',
        'geometry',
        'rings',
        'paths',
      ]) {
        visit(value[key]);
      }
    }
  }

  visit(item);
  if (coords.isEmpty) return false;
  var r = Rect.fromPoints(coords.first, coords.first);
  for (final p in coords.skip(1)) {
    r = r.expandToInclude(Rect.fromPoints(p, p));
  }
  return r.inflate(1e-10).overlaps(bounds);
}

String mergeCellSources(
  String cell,
  List<String> sources, [
  List<String>? provenance,
]) {
  final features = <int, dynamic>{};
  final scenery = <String, dynamic>{}, places = <String, dynamic>{};
  final versions = <String>[];
  final footprints = <List<double>>[];
  Rect? bounds;
  Map<String, dynamic>? template;
  for (final source in sources) {
    final j = jsonDecode(source) as Map<String, dynamic>;
    template ??= j;
    versions.add(j['wanderlust_network']['network_version'] as String);
    final b = geographicBounds(
      (j['bbox'] as List).cast<num>().map((n) => n.toDouble()).toList(),
    );
    footprints.add(boundsList(b));
    bounds = bounds?.expandToInclude(b) ?? b;
    for (final f in j['features'] as List) {
      features.putIfAbsent(f['id'] as int, () => f);
    }
    for (final f in j['wanderlust_scenery'] as List? ?? []) {
      scenery[jsonEncode(f)] = f;
    }
    for (final f in j['wanderlust_places'] as List? ?? []) {
      places[jsonEncode(f)] = f;
    }
  }
  if (provenance != null) {
    versions
      ..clear()
      ..addAll(provenance);
  }
  versions.sort();
  final version =
      'cell-v1/$cell/${sha256.convert(utf8.encode(jsonEncode([versions, features.values.toList(), scenery.values.toList(), places.values.toList()])))}';
  return jsonEncode({
    ...template!,
    'bbox': boundsList(bounds!),
    'features': features.values.toList(),
    'wanderlust_scenery': scenery.values.toList(),
    'wanderlust_places': places.values.toList(),
    'wanderlust_network': {
      ...template['wanderlust_network'] as Map,
      'network_version': version,
      'area_id': 'cell/$cell',
      'source_versions': versions,
      'footprints': footprints,
      'view_only': features.isEmpty,
    },
  });
}

/// Backpressure keeps only one output cell in flight, even for a large map.
Stream<Map<String, Object?>> streamMapCells(String source) async* {
  final receive = ReceivePort();
  final isolate = await Isolate.spawn(_indexWorker, (source, receive.sendPort));
  SendPort? acknowledge;
  try {
    await for (final message in receive) {
      if (message is SendPort) {
        acknowledge = message;
        continue;
      }
      if (message == null) break;
      if (message is String) throw FormatException(message);
      yield (message as Map).cast<String, Object?>();
      acknowledge!.send(true);
    }
  } finally {
    receive.close();
    isolate.kill(priority: Isolate.immediate);
  }
}

Future<void> _indexWorker((String, SendPort) input) async {
  final ack = ReceivePort();
  final replies = StreamIterator(ack);
  input.$2.send(ack.sendPort);
  try {
    for (final cell in indexMapCells(input.$1)) {
      input.$2.send(cell);
      if (!await replies.moveNext()) break;
    }
    input.$2.send(null);
  } catch (e) {
    input.$2.send(e.toString());
  } finally {
    await replies.cancel();
    ack.close();
  }
}
