import 'dart:ui';
import 'map_cells.dart';

class OfflineArea {
  const OfflineArea({
    required this.version,
    required this.name,
    required this.downloadedAt,
    required this.bytes,
    this.bounds,
    this.cacheBytes = 0,
  });
  final String version;
  final String name;
  final DateTime downloadedAt;
  final int bytes, cacheBytes;
  final Rect? bounds;
}

abstract class AreaStore {
  Future<List<OfflineArea>> listAreas();
  Future<String?> readArea(String version);
  Future<String?> readActiveArea();
  Future<void> saveArea(String geojson);
  Future<void> selectArea(String? version);
  Future<void> deleteArea(String version);
}

/// Optional spatial interface; small in-memory stores remain usable in tests.
abstract class SpatialAreaStore implements AreaStore {
  Future<String?> selectedVersion();
  Future<bool> indexNext(Offset? focus);
  Future<List<CellSource>> listCells();
  Future<String?> readCell(String cell);
}
