import 'dart:ui';
import '../data/area_network.dart';
import '../exploration/exploration.dart';
import '../theme/wanderlust_theme.dart';
import 'map_spatial_index.dart';

/// Merge adjacent revealed cells into strips once, not on every drag frame.
class ExplorationFog {
  Set<(int, int)>? _cells;
  AreaNetwork? _network;
  Size? _size;
  var _index = MapSpatialIndex<Rect>();
  void prepare(Set<(int, int)> cells, AreaNetwork network, Size size) {
    if (identical(_cells, cells) && _network == network && _size == size) {
      return;
    }
    _cells = cells;
    _network = network;
    _size = size;
    _index = MapSpatialIndex();
    final rows = <int, List<int>>{};
    for (final cell in cells) {
      (rows[cell.$2] ??= []).add(cell.$1);
    }
    for (final row in rows.entries) {
      final xs = row.value..sort();
      var start = xs.first, end = start;
      void add() {
        final a = network.project(
          discoveryCoordinate(
            start * discoveryCellMetres,
            row.key * discoveryCellMetres,
          ),
          size,
        );
        final b = network.project(
          discoveryCoordinate(
            (end + 1) * discoveryCellMetres,
            (row.key + 1) * discoveryCellMetres,
          ),
          size,
        );
        final rect = Rect.fromPoints(a, b);
        _index.add(rect, rect);
      }

      for (final x in xs.skip(1)) {
        if (x > end + 1) {
          add();
          start = x;
        }
        end = x;
      }
      add();
    }
  }

  void paint(Canvas canvas, Rect visible) {
    // Adjacent, non-overlapping holes avoid even-odd overlap artefacts.
    final veil = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(visible);
    for (final rect in _index.query(visible)) {
      veil.addRect(rect.intersect(visible));
    }
    canvas.drawPath(
      veil,
      Paint()..color = WanderlustColors.paperBg.withValues(alpha: .78),
    );
  }
}
