import 'dart:ui';
import 'package:flutter/foundation.dart';
import '../blocks/block_geometry.dart';
import '../data/area_network.dart';
import 'map_spatial_index.dart';

class _BlockTile {
  final blocks = <String, Path>{};
  Picture? picture;
  Rect? bounds;
}

/// Cache small geographic batches of completed fills. Gesture frames only query
/// visible batches and draw their paths; they never scan all completed blocks.
class BlockLayer {
  List<StreetBlock>? _blocks;
  AreaNetwork? _network;
  Size? _size;
  var _index = MapSpatialIndex<_BlockTile>(cellSize: 32);
  final _paths = <String, Path>{};
  final _byBlock = <String, _BlockTile>{};
  Set<String> _filled = const {};
  void prepare(List<StreetBlock> blocks, AreaNetwork network, Size size) {
    if (identical(_blocks, blocks) && _network == network && _size == size) {
      return;
    }
    _blocks = blocks;
    _network = network;
    _size = size;
    for (final tile in _byBlock.values.toSet()) {
      tile.picture?.dispose();
    }
    _index = MapSpatialIndex(cellSize: 32);
    _paths.clear();
    _byBlock.clear();
    _filled = const {};
    final tiles = <(int, int), _BlockTile>{};
    for (final block in blocks) {
      final path = Path();
      for (var i = 0; i < block.points.length; i++) {
        final p = network.project(block.points[i], size);
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      path.close();
      _paths[block.id] = path;
      final bounds = path.getBounds(), center = bounds.center;
      final tile = tiles.putIfAbsent((
        (center.dx / 16).floor(),
        (center.dy / 16).floor(),
      ), () => _BlockTile());
      tile.blocks[block.id] = path;
      _byBlock[block.id] = tile;
      tile.bounds = tile.bounds?.expandToInclude(bounds) ?? bounds;
    }
    for (final tile in tiles.values) {
      _index.add(tile, tile.bounds!);
    }
  }

  void paint(
    Canvas canvas,
    Rect? visible,
    Set<String> completed,
    String? selected,
    double zoom,
    Set<String> fading,
    double alpha,
  ) {
    final fill = fading.isEmpty ? completed : completed.difference(fading);
    if (!identical(fill, _filled) && !setEquals(fill, _filled)) {
      final dirty = {
        for (final id in {
          ...fill.difference(_filled),
          ..._filled.difference(fill),
        })
          if (_byBlock[id] != null) _byBlock[id]!,
      };
      for (final tile in dirty) {
        final fillPath = Path();
        for (final entry in tile.blocks.entries) {
          if (fill.contains(entry.key)) {
            fillPath.addPath(entry.value, Offset.zero);
          }
        }
        final recorder = PictureRecorder();
        Canvas(recorder).drawPath(
          fillPath,
          Paint()..color = const Color(0xff6f9874).withValues(alpha: .27),
        );
        tile.picture?.dispose();
        tile.picture = recorder.endRecording();
      }
    }
    _filled = fill;
    final paint = Paint()
      ..color = const Color(0xff6f9874).withValues(alpha: .27);
    final candidates = visible == null
        ? _byBlock.values.toSet()
        : _index.query(visible);
    for (final tile in candidates) {
      if (tile.picture != null) canvas.drawPicture(tile.picture!);
    }
    if (fading.isNotEmpty) {
      paint.color = const Color(0xff6f9874).withValues(alpha: .27 * alpha);
      for (final id in fading) {
        final path = _paths[id];
        if (path != null &&
            completed.contains(id) &&
            (visible == null || visible.overlaps(path.getBounds()))) {
          canvas.drawPath(path, paint);
        }
      }
    }
    final selectedPath = _paths[selected];
    if (selectedPath != null) {
      canvas.drawPath(
        selectedPath,
        Paint()
          ..color = const Color(0xff5b7561)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 / zoom,
      );
    }
  }

  void dispose() {
    for (final tile in _byBlock.values.toSet()) {
      tile.picture?.dispose();
    }
    _byBlock.clear();
  }
}
