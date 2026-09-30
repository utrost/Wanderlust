import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../data/area_network.dart';
import '../theme/heat_ramp.dart';
import 'map_labels.dart';
import '../memories/memory.dart';
import 'memory_markers.dart';
import 'walk_overlay.dart';

/// Offline street geometry, with exactly the ids and coordinates used by Rust.
/// This is a street coverage view; the richer PMTiles basemap is still pending.
Size mapDrawingSize(Size size) =>
    Size(math.max(1, size.width - 24), math.max(1, size.height - 180));

Offset mapPoint(AreaNetwork network, Offset coordinate, Size size) =>
    network.project(coordinate, mapDrawingSize(size)) + const Offset(12, 80);

// Preserve walking-scale zoom as downloaded footprints grow beyond 4 km.
double mapSpanKm(AreaNetwork network) {
  final b = network.bbox;
  final width =
      (b[2] - b[0]) * math.cos((b[1] + b[3]) / 2 * math.pi / 180) * 111320;
  final height = (b[3] - b[1]) * 111320;
  return math.max(width, height) / 1000;
}

double mapZoomFactor(AreaNetwork network) =>
    math.max(1, mapSpanKm(network) / 4);

class AreaMap extends StatefulWidget {
  const AreaMap({
    super.key,
    required this.network,
    required this.counts,
    this.networks = const [],
    this.walkedLineWidth = 3,
    this.showStreetNames = true,
    this.memories = const [],
    this.onMemory,
    this.coverageScreenWidth,
    this.position,
    this.stale = false,
    this.centerRequest = 0,
    this.areaRequest = 0,
    this.trace = const [],
    this.inferred = const {},
    this.fitCoordinates = const [],
  });
  final List<AreaNetwork> networks;
  final double walkedLineWidth;
  final bool showStreetNames;
  final List<WalkMemory> memories;
  final void Function(WalkMemory)? onMemory;
  final double? coverageScreenWidth;
  final AreaNetwork network;
  final Map<int, int> counts;
  final Position? position;
  final bool stale;
  final int centerRequest;
  final int areaRequest;
  final List<List<Offset>> trace;
  final Set<int> inferred;
  final List<Offset> fitCoordinates;

  @override
  State<AreaMap> createState() => _AreaMapState();
}

class _AreaMapState extends State<AreaMap> {
  final _transform = TransformationController();
  Size? _size;
  bool _pendingCenter = false;
  bool _pendingFit = true;

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
      _pendingFit = true;
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
    final scale = math.max(
      4.0 * mapZoomFactor(widget.network),
      _transform.value.getMaxScaleOnAxis(),
    );
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
      if (_pendingFit && widget.fitCoordinates.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_pendingFit) return;
          final points = widget.fitCoordinates
              .map((p) => mapPoint(widget.network, p, _size!))
              .toList();
          final xs = points.map((p) => p.dx).toList()..sort();
          final ys = points.map((p) => p.dy).toList()..sort();
          final rect = Rect.fromLTRB(xs.first, ys.first, xs.last, ys.last);
          final scale = math
              .min(
                (_size!.width - 48) / math.max(rect.width, 1),
                (_size!.height - 48) / math.max(rect.height, 1),
              )
              .clamp(1.0, 12 * mapZoomFactor(widget.network));
          _transform.value = Matrix4.diagonal3Values(scale, scale, 1)
            ..setTranslationRaw(
              _size!.width / 2 - rect.center.dx * scale,
              _size!.height / 2 - rect.center.dy * scale,
              0,
            );
          _pendingFit = false;
        });
      }
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
            maxScale: 12 * mapZoomFactor(widget.network),
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
                  walkedLineWidth: widget.walkedLineWidth,
                  showStreetNames: widget.showStreetNames,
                  coverageScreenWidth: widget.coverageScreenWidth,
                  transform: _transform.value.clone(),
                  trace: widget.trace,
                  inferred: widget.inferred,
                  textScale: MediaQuery.textScalerOf(context).scale(12) / 12,
                ),
              ),
            ),
          ),
          if (widget.onMemory != null && widget.memories.isNotEmpty)
            AnimatedBuilder(
              animation: _transform,
              builder: (context, _) => MemoryMarkers(
                memories: widget.memories,
                size: _size!,
                open: widget.onMemory!,
                project: (p) => MatrixUtils.transformPoint(
                  _transform.value,
                  mapPoint(widget.network, p, _size!),
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
    this.walkedLineWidth = 3,
    this.showStreetNames = true,
    this.coverageScreenWidth,
    this.transform,
    this.trace = const [],
    this.inferred = const {},
    this.textScale = 1,
  });
  final List<AreaNetwork> networks;
  final double walkedLineWidth;
  final bool showStreetNames;
  final double? coverageScreenWidth;
  final Matrix4? transform;
  final AreaNetwork network;
  final Map<int, int> counts;
  final List<List<Offset>> trace;
  final Set<int> inferred;
  final double textScale;

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
                : coverageScreenWidth ??
                      math.min(
                        walkedLineWidth,
                        HeatRamp.width(count) *
                            math.sqrt(zoom) *
                            walkedLineWidth /
                            4.5,
                      )) /
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
    canvas.restore();
    Offset project(Offset p) => MatrixUtils.transformPoint(
      transform ?? Matrix4.identity(),
      mapPoint(network, p, size),
    );
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    paintMapLabels(
      canvas,
      layoutMapLabels(
        maps.toList(),
        size,
        project,
        streets: showStreetNames && mapSpanKm(network) / zoom <= 2,
        textScale: textScale,
      ),
      textScale,
    );
    // Labels must never erase walked coverage, including other streets that
    // cross a label's background. Street labels are offset from their own road.
    canvas.save();
    if (transform != null) canvas.transform(transform!.storage);
    canvas.translate(12, 80);
    for (final edge in painted) {
      draw(edge, counts[edge.id]!);
    }
    canvas.restore();
    paintWalkOverlay(canvas, maps.toList(), inferred, trace, project);
    canvas.restore();
  }

  @override
  bool shouldRepaint(AreaMapPainter oldDelegate) =>
      oldDelegate.network != network ||
      oldDelegate.counts != counts ||
      oldDelegate.networks != networks ||
      oldDelegate.walkedLineWidth != walkedLineWidth ||
      oldDelegate.showStreetNames != showStreetNames ||
      oldDelegate.coverageScreenWidth != coverageScreenWidth ||
      oldDelegate.trace != trace ||
      oldDelegate.inferred != inferred ||
      oldDelegate.textScale != textScale ||
      oldDelegate.transform != transform;
}
