import 'dart:ui';

import '../recording/saved_walk.dart';

typedef _Pair = (Offset, Offset);

/// Derived display data, never street credit. Keeps only unmatched geometry,
/// not whole saved recordings. Rebuilt after restart or map/policy changes.
class UnmatchedTrails {
  final _walks = <int, Map<String, Map<int, _Pair>>>{};

  bool contains(int walk, String area) =>
      _walks[walk]?.containsKey(area) ?? false;

  void put(SavedWalk walk, String area, List<int> unmatched) {
    if (unmatched.any((i) => i <= 0 || i >= walk.points.length)) {
      throw StateError('Matcher returned an invalid GPS trail index');
    }
    (_walks[walk.id] ??= {})[area] = _pairs(walk, unmatched.toSet());
  }

  void clear() => _walks.clear();
  void retain(Set<int> walks) =>
      _walks.removeWhere((id, _) => !walks.contains(id));

  List<List<Offset>> lines(List<String> areas) => [
    if (areas.isNotEmpty)
      for (final entry in _walks.values)
        ..._lines({
          for (final i in common(
            areas.map((a) => entry[a]?.keys.toSet() ?? {}),
          ))
            i: entry[areas.first]![i]!,
        }),
  ];

  /// A pair matched in any downloaded map must not also appear as fallback.
  static Set<int> common(Iterable<Set<int>> sets) {
    final iterator = sets.iterator;
    if (!iterator.moveNext()) return {};
    final result = Set<int>.of(iterator.current);
    while (iterator.moveNext()) {
      result.retainAll(iterator.current);
    }
    return result;
  }

  static List<List<Offset>> fromIndices(SavedWalk walk, Set<int> indices) =>
      _lines(_pairs(walk, indices));

  static Map<int, _Pair> _pairs(SavedWalk walk, Set<int> indices) {
    final breaks = walk.segmentStarts.toSet();
    Offset point(int n) =>
        Offset(walk.points[n].longitude, walk.points[n].latitude);
    return {
      for (final i in indices)
        if (i > 0 && i < walk.points.length && !breaks.contains(i))
          i: (point(i - 1), point(i)),
    };
  }

  static List<List<Offset>> _lines(Map<int, _Pair> pairs) {
    final result = <List<Offset>>[];
    var previous = -2;
    for (final i in pairs.keys.toList()..sort()) {
      final pair = pairs[i]!;
      if (i != previous + 1) result.add([pair.$1]);
      result.last.add(pair.$2);
      previous = i;
    }
    return result;
  }
}
