import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:xml/xml.dart';
import 'osm_scenery.dart';
import 'osm_places.dart';

/// Same pedestrian policy and node-chain identities as tools/build_network.py.
/// Raw OSM nodes remain graph junctions; proximity never joins bridges.
class OsmNetwork {
  static const policy = 'pedestrian-conservative-v2';
  static const safeInteger = 9007199254740991;
  static const highways = {
    'residential',
    'living_street',
    'footway',
    'path',
    'pedestrian',
    'steps',
    'service',
    'unclassified',
    'tertiary',
    'secondary',
    'primary',
    'tertiary_link',
    'secondary_link',
    'primary_link',
    'track',
  };
  static const footAllowed = {'yes', 'designated', 'permissive'};
  static const accessAllowed = {'yes', 'permissive'};

  static bool excluded(Map<String, String> t) {
    final h = t['highway'];
    if (!highways.contains(h) && h != 'cycleway' && h != 'bridleway') {
      return true;
    }
    if (t['area'] == 'yes' ||
        t['indoor'] == 'yes' ||
        t.containsKey('level') ||
        t.containsKey('foot:conditional') ||
        t.containsKey('access:conditional')) {
      return true;
    }
    if (t.containsKey('foot')) return !footAllowed.contains(t['foot']);
    if (h == 'cycleway' || h == 'bridleway') return true;
    return !accessAllowed.contains(t['access'] ?? 'yes');
  }

  static bool blockedNode(Map<String, String> t) {
    if (footAllowed.contains(t['foot'])) return false;
    if (t.containsKey('foot') && !footAllowed.contains(t['foot'])) return true;
    return !accessAllowed.contains(t['access'] ?? 'yes') ||
        t.containsKey('foot:conditional') ||
        t.containsKey('access:conditional') ||
        {'wall', 'fence', 'hedge', 'block'}.contains(t['barrier']);
  }

  static List<int> canonicalChain(List<int> chain) {
    for (var i = 0; i < chain.length; i++) {
      final compare = chain[i].compareTo(chain[chain.length - i - 1]);
      if (compare < 0) return chain;
      if (compare > 0) return chain.reversed.toList();
    }
    return chain;
  }

  static int edgeId(int way, List<int> chain) => int.parse(
    sha256
        .convert(
          utf8.encode('osm-edge-v2:$way:${canonicalChain(chain).join(',')}'),
        )
        .toString()
        .substring(0, 13),
    radix: 16,
  );

  static double metres(List<double> a, List<double> b) {
    final lon1 = a[0] * math.pi / 180, lat1 = a[1] * math.pi / 180;
    final lon2 = b[0] * math.pi / 180, lat2 = b[1] * math.pi / 180;
    final h =
        math.pow(math.sin((lat2 - lat1) / 2), 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.pow(math.sin((lon2 - lon1) / 2), 2);
    return 6371000 * 2 * math.asin(math.min(1, math.sqrt(h)));
  }

  static String normalize(
    String xml,
    List<double> bbox, {
    required String areaId,
    required String name,
  }) {
    if (utf8.encode(xml).length > 16 * 1024 * 1024) {
      throw const FormatException(
        'This area is too detailed to download. Choose a smaller map size.',
      );
    }
    if (bbox.length != 4 ||
        bbox.any((v) => !v.isFinite) ||
        bbox[0] < -180 ||
        bbox[2] > 180 ||
        bbox[1] < -90 ||
        bbox[3] > 90 ||
        bbox[0] >= bbox[2] ||
        bbox[1] >= bbox[3]) {
      throw const FormatException('Invalid map bounds.');
    }
    final doc = XmlDocument.parse(xml);
    final root = doc.rootElement;
    if (root.localName != 'osm' ||
        root.findAllElements('remark').isNotEmpty ||
        doc.children.any((n) => n is XmlDoctype)) {
      throw const FormatException(
        'Map server returned incomplete data. Choose a smaller size or retry later.',
      );
    }
    Map<String, String> tags(XmlElement e) => {
      for (final t in e.findElements('tag'))
        t.getAttribute('k') ?? '': t.getAttribute('v') ?? '',
    };
    int id(String? value) {
      final n = int.tryParse(value ?? '');
      if (n == null || n <= 0 || n > safeInteger) {
        throw const FormatException('Invalid OSM identifier.');
      }
      return n;
    }

    final nodes = <int, List<double>>{};
    final blocked = <int>{};
    for (final n in root.findElements('node')) {
      final nid = id(n.getAttribute('id'));
      final lon = double.tryParse(n.getAttribute('lon') ?? '');
      final lat = double.tryParse(n.getAttribute('lat') ?? '');
      if (lon == null ||
          lat == null ||
          !lon.isFinite ||
          !lat.isFinite ||
          lon.abs() > 180 ||
          lat.abs() > 90 ||
          nodes.containsKey(nid)) {
        throw const FormatException('Invalid OSM coordinates.');
      }
      nodes[nid] = [lon, lat];
      if (nodes.length > 150000) {
        throw const FormatException('Too many map points. Try a smaller area.');
      }
      if (blockedNode(tags(n))) blocked.add(nid);
    }
    bool inside(List<double> p) =>
        p[0] >= bbox[0] &&
        p[0] <= bbox[2] &&
        p[1] >= bbox[1] &&
        p[1] <= bbox[3];
    final ways = <(int, Map<String, String>, List<int>)>[];
    final seen = <int>{};
    final refsCount = <int, int>{};
    for (final way in root.findElements('way')) {
      final wid = id(way.getAttribute('id'));
      if (!seen.add(wid)) throw const FormatException('Duplicate OSM way.');
      final t = tags(way);
      if (excluded(t)) continue;
      final refs = canonicalChain(
        way.findElements('nd').map((n) => id(n.getAttribute('ref'))).toList(),
      );
      if (refs.length < 2 || refs.any((n) => !nodes.containsKey(n))) {
        throw const FormatException('Map has incomplete street geometry.');
      }
      ways.add((wid, t, refs));
      for (final ref in refs) {
        refsCount.update(ref, (v) => v + 1, ifAbsent: () => 1);
      }
    }
    final features = <int, Map<String, Object?>>{};
    for (final (wid, tags, refs) in ways) {
      final pieces = <List<int>>[];
      var piece = [refs.first];
      var length = 0.0;
      for (var i = 1; i < refs.length; i++) {
        final n = refs[i];
        length += metres(nodes[piece.last]!, nodes[n]!);
        piece.add(n);
        if (refsCount[n]! > 1 ||
            blocked.contains(n) ||
            length >= 60 ||
            i == refs.length - 1 ||
            inside(nodes[refs[i - 1]]!) != inside(nodes[n]!)) {
          pieces.add(piece);
          piece = [n];
          length = 0;
        }
      }
      for (final segment in pieces) {
        final chain = canonicalChain(segment);
        if (chain.any(blocked.contains) ||
            !chain.every((n) => inside(nodes[n]!))) {
          continue;
        }
        var length = 0.0;
        for (var i = 1; i < chain.length; i++) {
          length += metres(nodes[chain[i - 1]]!, nodes[chain[i]]!);
        }
        if (length < 0.01) continue;
        final eid = edgeId(wid, chain);
        final feature = <String, Object?>{
          'type': 'Feature',
          'id': eid,
          'properties': {
            'osm_way_id': wid,
            'from_node': chain.first,
            'to_node': chain.last,
            'highway': tags['highway'],
            'length_m': double.parse(length.toStringAsFixed(3)),
            for (final k in [
              'name',
              'bridge',
              'tunnel',
              'layer',
              'foot',
              'bicycle',
              'footway',
              'access',
            ])
              if (tags.containsKey(k)) k: tags[k],
          },
          'geometry': {
            'type': 'LineString',
            'coordinates': [for (final n in chain) nodes[n]!],
          },
        };
        if (features.containsKey(eid) &&
            jsonEncode(features[eid]) != jsonEncode(feature)) {
          throw const FormatException('Map edge identity collision.');
        }
        features[eid] = feature;
        if (features.length > 40000) {
          throw const FormatException('Too many streets. Try a smaller area.');
        }
      }
    }
    if (features.isEmpty) {
      throw const FormatException('No walkable streets found here.');
    }
    final ids = features.keys.toList()..sort();
    final ordered = [for (final id in ids) features[id]!];
    // Version identity deliberately namespaces the mobile serializer. Edge IDs
    // remain identical to the offline Python builder; counts are network-scoped.
    final version = sha256
        .convert(
          utf8.encode(
            jsonEncode({
              'builder': 'mobile-osm-v1',
              'area_id': areaId,
              'bbox': bbox,
              'policy': policy,
              'features': ordered,
            }),
          ),
        )
        .toString();
    final scenery = OsmScenery.extract(root, nodes);
    final places = OsmPlaces.extract(root, bbox, scenery);
    return jsonEncode({
      'type': 'FeatureCollection',
      'bbox': bbox,
      'wanderlust_network': {
        'version': 1,
        'area_id': areaId,
        'name': OsmPlaces.areaName(name, bbox, places, ordered),
        'network_version': version,
        'policy': policy,
        'edge_id_scheme': 'sha256-osm-way-node-chain-52bit-v2',
        'source_sha256': sha256.convert(utf8.encode(xml)).toString(),
        'attribution': '© OpenStreetMap contributors',
        'license': 'ODbL-1.0',
        'license_url': 'https://www.openstreetmap.org/copyright',
        'osm_base':
            root.findElements('meta').firstOrNull?.getAttribute('osm_base') ??
            '',
      },
      'features': ordered,
      'wanderlust_scenery': scenery,
      'wanderlust_places': places,
    });
  }
}
