import 'dart:ui';

class MapScenery {
  const MapScenery(this.id, this.kind, this.paths);
  final String id;
  final String kind;
  final List<List<Offset>> paths;
  factory MapScenery.parse(Map<String, dynamic> json) {
    final kind = json['kind'] as String;
    if (!{'park', 'water', 'waterway'}.contains(kind)) {
      throw const FormatException('Unknown scenery');
    }
    final paths = (json['paths'] as List)
        .map(
          (p) => (p as List).map((v) {
            final pair = v as List;
            final x = (pair[0] as num).toDouble(),
                y = (pair[1] as num).toDouble();
            if (!x.isFinite || !y.isFinite || x.abs() > 180 || y.abs() > 90) {
              throw const FormatException('Invalid scenery coordinates');
            }
            return Offset(x, y);
          }).toList(),
        )
        .toList();
    if (paths.isEmpty ||
        paths.any(
          (p) =>
              p.length < (kind == 'waterway' ? 2 : 4) ||
              (kind != 'waterway' && p.first != p.last),
        )) {
      throw const FormatException('Incomplete scenery');
    }
    return MapScenery(json['id'] as String, kind, paths);
  }
}
