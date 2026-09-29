import 'package:xml/xml.dart';

/// Decorative OSM geometry is separate from the pedestrian matching graph.
class OsmScenery {
  static List<Map<String, Object?>> extract(
    XmlElement root,
    Map<int, List<double>> nodes,
  ) {
    Map<String, String> tags(XmlElement e) => {
      for (final t in e.findElements('tag'))
        t.getAttribute('k') ?? '': t.getAttribute('v') ?? '',
    };
    String? kind(Map<String, String> t) {
      if (t['natural'] == 'water' ||
          t['landuse'] == 'reservoir' ||
          t['waterway'] == 'riverbank') {
        return 'water';
      }
      if ({'river', 'stream', 'canal', 'drain'}.contains(t['waterway'])) {
        return 'waterway';
      }
      if ({'park', 'garden', 'nature_reserve'}.contains(t['leisure']) ||
          {'forest', 'grass', 'recreation_ground'}.contains(t['landuse']) ||
          t['natural'] == 'wood') {
        return 'park';
      }
      return null;
    }

    final ways = <int, List<int>>{};
    final wayTags = <int, Map<String, String>>{};
    for (final way in root.findElements('way')) {
      final id = int.tryParse(way.getAttribute('id') ?? '');
      if (id == null) continue;
      final refs = [
        for (final n in way.findElements('nd'))
          int.tryParse(n.getAttribute('ref') ?? ''),
      ];
      if (refs.length < 2 ||
          refs.any((n) => n == null || !nodes.containsKey(n))) {
        continue;
      }
      ways[id] = refs.cast<int>();
      wayTags[id] = tags(way);
    }
    List<List<int>>? rings(List<List<int>> fragments) {
      final pending = fragments.map((f) => f.toList()).toList();
      final output = <List<int>>[];
      while (pending.isNotEmpty) {
        final ring = pending.removeLast();
        while (ring.first != ring.last) {
          final i = pending.indexWhere(
            (f) => f.first == ring.last || f.last == ring.last,
          );
          if (i < 0) {
            return null; // Never invent a closing edge across missing data.
          }
          final next = pending.removeAt(i);
          ring.addAll((next.first == ring.last ? next : next.reversed).skip(1));
        }
        if (ring.length < 4) return null;
        output.add(ring);
      }
      return output;
    }

    final result = <Map<String, Object?>>[];
    final represented = <int>{};
    void add(String id, String type, List<List<int>> paths) {
      if (result.length >= 10000) {
        throw const FormatException('Too much map scenery. Try another area.');
      }
      result.add({
        'id': id,
        'kind': type,
        'paths': [
          for (final p in paths) [for (final n in p) nodes[n]!],
        ],
      });
    }

    for (final relation in root.findElements('relation')) {
      final t = tags(relation), type = kind(tags(relation));
      if (t['type'] != 'multipolygon' || type == null || type == 'waterway') {
        continue;
      }
      final outer = <List<int>>[], inner = <List<int>>[];
      final used = <int>[];
      var complete = true;
      for (final m in relation.findElements('member')) {
        final role = m.getAttribute('role') ?? '';
        if (!{'', 'outer', 'inner'}.contains(role)) continue;
        final id = int.tryParse(m.getAttribute('ref') ?? '');
        if (m.getAttribute('type') != 'way' || !ways.containsKey(id)) {
          complete = false;
          break;
        }
        (role == 'inner' ? inner : outer).add(ways[id]!);
        used.add(id!);
      }
      if (!complete || outer.isEmpty) continue;
      final outs = rings(outer), ins = rings(inner);
      if (outs == null || ins == null) continue;
      add('relation:${relation.getAttribute('id')}', type, [...outs, ...ins]);
      represented.addAll(used);
    }
    for (final entry in ways.entries) {
      if (represented.contains(entry.key)) continue;
      final type = kind(wayTags[entry.key]!);
      if (type == null) continue;
      if (type != 'waterway' &&
          (entry.value.length < 4 || entry.value.first != entry.value.last)) {
        continue;
      }
      add('way:${entry.key}', type, [entry.value]);
    }
    result.sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
    return result;
  }
}
