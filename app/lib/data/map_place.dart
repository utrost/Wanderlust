import 'dart:ui';

class MapPlace {
  const MapPlace(this.name, this.point, this.kind);
  final String name;
  final Offset point;
  final String kind;
  static MapPlace? tryParse(dynamic value) {
    if (value is! Map) return null;
    final name = value['name'];
    final p = value['point'];
    if (name is! String ||
        name.trim().isEmpty ||
        name.length > 120 ||
        p is! List ||
        p.length != 2 ||
        p[0] is! num ||
        p[1] is! num) {
      return null;
    }
    final x = (p[0] as num).toDouble(), y = (p[1] as num).toDouble();
    if (!x.isFinite || !y.isFinite || x.abs() > 180 || y.abs() > 90) {
      return null;
    }
    return MapPlace(
      name.trim(),
      Offset(x, y),
      value['kind'] is String ? value['kind'] as String : 'place',
    );
  }
}
