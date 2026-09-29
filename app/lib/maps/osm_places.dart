import 'package:xml/xml.dart';
import 'osm_network.dart';

/// Optional labels never alter the street graph or its stable identities.
class OsmPlaces {
  static List<Map<String, Object>> extract(
    XmlElement root,
    List<double> bbox,
    List<Map<String, Object?>> scenery,
  ) {
    final result = <Map<String, Object>>[];
    final names = <String, String>{};
    for (final element in root.childElements) {
      final tags = {
        for (final t in element.findElements('tag'))
          t.getAttribute('k'): t.getAttribute('v'),
      };
      final name = tags['name']?.trim();
      if (name == null || name.isEmpty || name.length > 120) continue;
      names['${element.localName}:${element.getAttribute('id')}'] = name;
      if (element.localName != 'node' ||
          !{
            'city',
            'town',
            'village',
            'hamlet',
            'suburb',
            'quarter',
            'neighbourhood',
          }.contains(tags['place'])) {
        continue;
      }
      final x = double.tryParse(element.getAttribute('lon') ?? ''),
          y = double.tryParse(element.getAttribute('lat') ?? '');
      if (x == null ||
          y == null ||
          !x.isFinite ||
          !y.isFinite ||
          x < bbox[0] ||
          x > bbox[2] ||
          y < bbox[1] ||
          y > bbox[3]) {
        continue;
      }
      result.add({
        'name': name,
        'kind': 'place',
        'point': [x, y],
      });
    }
    for (final feature in scenery) {
      final name = names[feature['id']];
      if (name == null) continue;
      final paths = feature['paths'] as List;
      final points = (paths.first as List).cast<List<double>>();
      // Label anchor is decorative; no inferred geometry or graph nodes.
      final xs = points.map((p) => p[0]).toList()..sort();
      final ys = points.map((p) => p[1]).toList()..sort();
      final x = (xs.first + xs.last) / 2, y = (ys.first + ys.last) / 2;
      if (x < bbox[0] || x > bbox[2] || y < bbox[1] || y > bbox[3]) continue;
      result.add({
        'name': name,
        'kind': feature['kind'] as String,
        'point': [x, y],
      });
    }
    return result.take(3000).toList();
  }

  static String areaName(
    String fallback,
    List<double> bbox,
    List<Map<String, Object>> places,
    List<Map<String, Object?>> streets,
  ) {
    if (!fallback.startsWith('Near ')) return fallback;
    final center = [(bbox[0] + bbox[2]) / 2, (bbox[1] + bbox[3]) / 2];
    final candidates = places.where((p) => p['kind'] == 'place').toList()
      ..sort(
        (a, b) => OsmNetwork.metres(center, (a['point'] as List).cast<double>())
            .compareTo(
              OsmNetwork.metres(center, (b['point'] as List).cast<double>()),
            ),
      );
    String? title = candidates.isEmpty
        ? null
        : 'Around ${candidates.first['name']}';
    if (title == null) {
      double best = double.infinity;
      for (final street in streets) {
        final name = (street['properties'] as Map)['name'];
        if (name is! String || name.trim().isEmpty || name.length > 120) {
          continue;
        }
        final coordinates = ((street['geometry'] as Map)['coordinates'] as List)
            .cast<List<double>>();
        for (final point in coordinates) {
          final distance = OsmNetwork.metres(center, point);
          if (distance < best) {
            best = distance;
            title = 'Around $name';
          }
        }
      }
    }
    if (title == null) return fallback;
    final size = fallback.contains(' · ')
        ? ' · ${fallback.split(' · ').last}'
        : '';
    return '$title$size';
  }
}
