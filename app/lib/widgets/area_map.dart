import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../data/area_network.dart';
import '../theme/heat_ramp.dart';

/// Offline street geometry, with exactly the ids and coordinates used by Rust.
/// This is a street coverage view; the richer PMTiles basemap is still pending.
Size mapDrawingSize(Size size) =>
    Size(math.max(1, size.width - 24), math.max(1, size.height - 180));

Offset mapPoint(AreaNetwork network, Offset coordinate, Size size) =>
    network.project(coordinate, mapDrawingSize(size)) + const Offset(12, 80);

class AreaMap extends StatefulWidget {
  const AreaMap({
    super.key,
    required this.network,
    required this.counts,
    this.networks = const [],
    this.position,
    this.stale = false,
    this.centerRequest = 0,
    this.areaRequest = 0,
  });
  final List<AreaNetwork> networks;
  final AreaNetwork network;
  final Map<int, int> counts;
  final Position? position;
  final bool stale;
  final int centerRequest;
  final int areaRequest;

  @override
  State<AreaMap> createState() => _AreaMapState();
}

class _AreaMapState extends State<AreaMap> {
  final _transform = TransformationController();
  Size? _size;
  bool _pendingCenter = false;

  @override
  void initState() {
    super.initState();
    _pendingCenter = widget.centerRequest > 0;
  }

  @override
  void didUpdateWidget(AreaMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.areaRequest != oldWidget.areaRequest ||
        widget.network.version != oldWidget.network.version) {
      _pendingCenter = false;
      _transform.value = Matrix4.identity();
    } else if (widget.centerRequest != oldWidget.centerRequest) {
      _pendingCenter = true;
    }
  }

  void _centerIfReady() {
    if (!mounted ||
        !_pendingCenter ||
        _size == null ||
        widget.position == null) {
      return;
    }
    final p = widget.position!;
    final point = mapPoint(
      widget.network,
      Offset(p.longitude, p.latitude),
      _size!,
    );
    final scale = math.max(4.0, _transform.value.getMaxScaleOnAxis());
    _transform.value = Matrix4.diagonal3Values(scale, scale, 1)
      ..setTranslationRaw(
        _size!.width / 2 - point.dx * scale,
        _size!.height / 2 - point.dy * scale,
        0,
      );
    _pendingCenter = false;
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      _size = bounds.biggest;
      if (_pendingCenter) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _centerIfReady());
      }
      return Stack(
        fit: StackFit.expand,
        children: [
          InteractiveViewer(
            transformationController: _transform,
            boundaryMargin: const EdgeInsets.all(double.infinity),
            minScale: 1,
            maxScale: 12,
            onInteractionStart: (_) => _pendingCenter = false,
            child: const SizedBox.expand(),
          ),
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _transform,
              builder: (context, _) => CustomPaint(
                painter: AreaMapPainter(
                  network: widget.network,
                  networks: widget.networks,
                  counts: widget.counts,
                  transform: _transform.value.clone(),
                ),
              ),
            ),
          ),
          if (widget.position case final position?)
            IgnorePointer(
              child: Semantics(
                label: widget.stale ? 'Last known location' : 'Your location',
                child: AnimatedBuilder(
                  animation: _transform,
                  builder: (context, _) => CustomPaint(
                    painter: LocationMarkerPainter(
                      network: widget.network,
                      position: position,
                      transform: _transform.value.clone(),
                      stale: widget.stale,
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

/// Painted in screen coordinates so the dot stays legible at every zoom level.
class LocationMarkerPainter extends CustomPainter {
  LocationMarkerPainter({
    required this.network,
    required this.position,
    required this.transform,
    required this.stale,
  });
  final AreaNetwork network;
  final Position position;
  final Matrix4 transform;
  final bool stale;

  Offset center(Size size) => MatrixUtils.transformPoint(
    transform,
    mapPoint(network, Offset(position.longitude, position.latitude), size),
  );

  @override
  void paint(Canvas canvas, Size size) {
    final point = center(size);
    final offset = mapPoint(
      network,
      Offset(
        position.longitude,
        position.latitude + position.accuracy / 111320,
      ),
      size,
    );
    final radius =
        (MatrixUtils.transformPoint(transform, offset) - point).distance;
    final color = stale ? Colors.grey.shade600 : const Color(0xFF1976D2);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawCircle(
      point,
      radius,
      Paint()..color = color.withValues(alpha: 0.13),
    );
    canvas.drawCircle(
      point,
      radius,
      Paint()
        ..color = color.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.drawCircle(point, 9, Paint()..color = Colors.white);
    canvas.drawCircle(point, 6, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(LocationMarkerPainter oldDelegate) =>
      oldDelegate.network != network ||
      oldDelegate.position != position ||
      oldDelegate.transform != transform ||
      oldDelegate.stale != stale;
}

class AreaMapPainter extends CustomPainter {
  AreaMapPainter({
    required this.network,
    required this.counts,
    this.networks = const [],
    this.transform,
  });
  final List<AreaNetwork> networks;
  final Matrix4? transform;
  final AreaNetwork network;
  final Map<int, int> counts;

  @override
  void paint(Canvas canvas, Size size) {
    // Leave space for map controls without shifting geographic coordinates.
    final mapSize = mapDrawingSize(size);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    if (transform != null) canvas.transform(transform!.storage);
    canvas.translate(12, 80);
    final zoom = transform?.getMaxScaleOnAxis() ?? 1.0;
    final maps = {
      for (final map in [network, ...networks]) map.version: map,
    }.values;
    for (final kind in ['park', 'water', 'waterway']) {
      for (final map in maps) {
        canvas.save();
        final a = network.project(Offset(map.bbox[0], map.bbox[3]), mapSize);
        final b = network.project(Offset(map.bbox[2], map.bbox[1]), mapSize);
        canvas.clipRect(Rect.fromPoints(a, b));
        for (final feature in map.scenery.where((s) => s.kind == kind)) {
          final path = Path()..fillType = PathFillType.evenOdd;
          for (final ring in feature.paths) {
            for (var i = 0; i < ring.length; i++) {
              final p = network.project(ring[i], mapSize);
              if (i == 0) {
                path.moveTo(p.dx, p.dy);
              } else {
                path.lineTo(p.dx, p.dy);
              }
            }
            if (kind != 'waterway') path.close();
          }
          canvas.drawPath(
            path,
            Paint()
              ..color = kind == 'park'
                  ? const Color(0xFFDCE4D2)
                  : const Color(0xFFC4DAE2)
              ..style = kind == 'waterway'
                  ? PaintingStyle.stroke
                  : PaintingStyle.fill
              ..strokeWidth = 2.0 / zoom
              ..strokeCap = StrokeCap.round,
          );
        }
        canvas.restore();
      }
    }
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    void draw(AreaEdge edge, int count) {
      stroke
        ..color = HeatRamp.color(count, dark: false)
        ..strokeWidth =
            (count == 0
                ? math.min(1.5, 0.65 * math.sqrt(zoom))
                : math.min(4.5, HeatRamp.width(count) * math.sqrt(zoom))) /
            zoom;
      final path = Path();
      for (var i = 0; i < edge.points.length; i++) {
        final p = network.project(edge.points[i], mapSize);
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(path, stroke);
    }

    final edges = <int, AreaEdge>{};
    for (final map in [network, ...networks]) {
      for (final edge in map.edges) {
        edges.putIfAbsent(edge.id, () => edge);
      }
    }
    for (final edge in edges.values) {
      draw(edge, 0);
    }
    final painted =
        edges.values.where((edge) => (counts[edge.id] ?? 0) > 0).toList()
          ..sort((a, b) => counts[a.id]!.compareTo(counts[b.id]!));
    for (final edge in painted) {
      draw(edge, counts[edge.id]!);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(AreaMapPainter oldDelegate) =>
      oldDelegate.network != network ||
      oldDelegate.counts != counts ||
      oldDelegate.networks != networks ||
      oldDelegate.transform != transform;
}
