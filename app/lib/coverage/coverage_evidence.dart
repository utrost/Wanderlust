/// Derived evidence is rebuilt with matching; raw recordings and backups stay
/// unchanged. A visit counts once across overlapping maps, even if another map
/// calls the same section an estimate.
class CoverageEvidence {
  final _walks = <int, Map<String, (Set<int>, Set<int>)>>{};

  void put(int walk, String area, Set<int> supported, Set<int> estimated) {
    (_walks[walk] ??= {})[area] = (
      Set.of(supported),
      estimated.difference(supported),
    );
  }

  void clear() => _walks.clear();
  void retain(Set<int> walks) =>
      _walks.removeWhere((id, _) => !walks.contains(id));

  Set<int> supported(Iterable<String> areas) => {
    for (final maps in _walks.values)
      for (final area in areas) ...?maps[area]?.$1,
  };

  Set<int> estimated(Iterable<String> areas) => {
    for (final maps in _walks.values)
      for (final area in areas) ...?maps[area]?.$2,
  }.difference(supported(areas));

  Map<int, int> counts(Iterable<String> areas) {
    final result = <int, int>{};
    for (final maps in _walks.values) {
      final supported = {
        for (final area in areas) ...?maps[area]?.$1,
        for (final area in areas) ...?maps[area]?.$2,
      };
      for (final edge in supported) {
        result.update(edge, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    return result;
  }
}
