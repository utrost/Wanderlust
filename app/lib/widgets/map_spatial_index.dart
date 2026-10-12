import 'dart:ui';

/// Uniform grid with a bounded fallback for features spanning many cells.
/// Queries return each intersecting object once, including boundary crossings.
class MapSpatialIndex<T> {
  MapSpatialIndex({this.cellSize = 64});
  final double cellSize;
  final _cells = <(int, int), List<(T, Rect)>>{};
  final _large = <(T, Rect)>[];
  final _all = <(T, Rect)>[];
  void add(T value, Rect bounds) {
    final entry = (value, bounds);
    _all.add(entry);
    final left = (bounds.left / cellSize).floor();
    final right = (bounds.right / cellSize).floor();
    final top = (bounds.top / cellSize).floor();
    final bottom = (bounds.bottom / cellSize).floor();
    if ((right - left + 1) * (bottom - top + 1) > 256) {
      _large.add(entry);
      return;
    }
    for (var x = left; x <= right; x++) {
      for (var y = top; y <= bottom; y++) {
        (_cells[(x, y)] ??= []).add(entry);
      }
    }
  }

  Set<T> query(Rect bounds) {
    final result = <T>{};
    void visit(Iterable<(T, Rect)> entries) {
      for (final entry in entries) {
        if (entry.$2.overlaps(bounds)) result.add(entry.$1);
      }
    }

    final left = (bounds.left / cellSize).floor();
    final right = (bounds.right / cellSize).floor();
    final top = (bounds.top / cellSize).floor();
    final bottom = (bounds.bottom / cellSize).floor();
    if ((right - left + 1) * (bottom - top + 1) > 4096) {
      visit(_all);
    } else {
      visit(_large);
      for (var x = left; x <= right; x++) {
        for (var y = top; y <= bottom; y++) {
          visit(_cells[(x, y)] ?? const []);
        }
      }
    }
    return result;
  }
}
