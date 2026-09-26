class OfflineArea {
  const OfflineArea({
    required this.version,
    required this.name,
    required this.downloadedAt,
    required this.bytes,
  });
  final String version;
  final String name;
  final DateTime downloadedAt;
  final int bytes;
}

abstract class AreaStore {
  Future<List<OfflineArea>> listAreas();
  Future<String?> readArea(String version);
  Future<String?> readActiveArea();
  Future<void> saveArea(String geojson);
  Future<void> selectArea(String? version);
  Future<void> deleteArea(String version);
}
