import '../blocks/block_geometry.dart';
import 'block_layer.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'map_spatial_index.dart';
import 'exploration_fog.dart';
import 'package:geolocator/geolocator.dart';

import '../data/area_network.dart';
import '../data/map_scenery.dart';
import '../coverage/street_display.dart';
import '../theme/heat_ramp.dart';
import '../theme/wanderlust_theme.dart';
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

/// Inverse projection for explicit, user-selected memory pins.
Offset mapCoordinate(AreaNetwork network, Offset point, Size size) {
  final a = mapPoint(network, Offset(network.bbox[0], network.bbox[1]), size);
  final b = mapPoint(network, Offset(network.bbox[2], network.bbox[3]), size);
  return Offset(
    network.bbox[0] +
        (point.dx - a.dx) / (b.dx - a.dx) * (network.bbox[2] - network.bbox[0]),
    network.bbox[1] +
        (point.dy - a.dy) / (b.dy - a.dy) * (network.bbox[3] - network.bbox[1]),
  );
}

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
    this.blocks = const [],
    this.completedBlocks = const {},
    this.selectedBlock,
    this.missingBlockLines = const [],
    this.fogOfWar = false,
    this.exploredCells = const {},
    this.memories = const [],
    this.onMemory,
    this.coverageScreenWidth,
    this.position,
    this.stale = false,
    this.centerRequest = 0,
    this.areaRequest = 0,
    this.trace = const [],
    this.unmatchedTrails = const [],
    this.inferred = const {},
    this.fitCoordinates = const [],
    this.onInteractionStart,
    this.onMapTap,
  });
  final List<AreaNetwork> networks;
  final double walkedLineWidth;
  final bool showStreetNames;
  final List<StreetBlock> blocks;
  final Set<String> completedBlocks;
  final String? selectedBlock;
  final List<List<Offset>> missingBlockLines;
  final bool fogOfWar;
  final Set<(int, int)> exploredCells;
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
  final List<List<Offset>> unmatchedTrails;
  final Set<int> inferred;
  final List<Offset> fitCoordinates;
  final VoidCallback? onInteractionStart;
  final ValueChanged<Offset>? onMapTap;

  @override
  State<AreaMap> createState() => _AreaMapState();
}

class _AreaMapState extends State<AreaMap> with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: 1,
  );
  Set<String> _fading = {};
  final _transform = TransformationController();
  final _geometry = MapGeometryCache();
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
    _fading = identical(widget.blocks, oldWidget.blocks)
        ? widget.completedBlocks.difference(oldWidget.completedBlocks)
        : {};
    if (_fading.isNotEmpty && !MediaQuery.disableAnimationsOf(context)) {
      _fade.forward(from: 0);
    }
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
    _fade.dispose();
    _transform.dispose();
    _geometry.dispose();
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
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: widget.onMapTap == null
                ? null
                : (details) {
                    final coordinate = mapCoordinate(
                      widget.network,
                      _transform.toScene(details.localPosition),
                      _size!,
                    );
                    if (coordinate.dx.isFinite &&
                        coordinate.dy.isFinite &&
                        coordinate.dx.abs() <= 180 &&
                        coordinate.dy.abs() <= 90) {
                      widget.onMapTap!(coordinate);
                    }
                  },
            child: InteractiveViewer(
              transformationController: _transform,
              boundaryMargin: const EdgeInsets.all(double.infinity),
              minScale: 1,
              maxScale: 12 * mapZoomFactor(widget.network),
              onInteractionStart: (_) {
                _pendingCenter = false;
                widget.onInteractionStart?.call();
              },
              child: const SizedBox.expand(),
            ),
          ),
          IgnorePointer(
            child: AnimatedBuilder(
              animation: Listenable.merge([_transform, _fade]),
              builder: (context, _) => CustomPaint(
                painter: AreaMapPainter(
                  geometry: _geometry,
                  blocks: widget.blocks,
                  completedBlocks: widget.completedBlocks,
                  selectedBlock: widget.selectedBlock,
                  missingBlockLines: widget.missingBlockLines,
                  fadingBlocks: _fading,
                  blockAlpha: _fade.value,
                  network: widget.network,
                  networks: widget.networks,
                  counts: widget.counts,
                  walkedLineWidth: widget.walkedLineWidth,
                  showStreetNames: widget.showStreetNames,
                  fogOfWar: widget.fogOfWar,
                  exploredCells: widget.exploredCells,
                  coverageScreenWidth: widget.coverageScreenWidth,
                  transform: _transform.value.clone(),
                  trace: widget.trace,
                  unmatchedTrails: widget.unmatchedTrails,
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

/// Geometry depends on the map projection and viewport, not GPS or heat counts.
class MapGeometryCache {
  AreaNetwork? _network;
  Size? _size;
  List<AreaNetwork>? _networks;
  final _paths = <Object, Path>{};
  StreetDisplay? _streetDisplay;
  final labels = MapLabelCache();
  final fog = ExplorationFog();
  final blocks = BlockLayer();
  MapSpatialIndex<AreaEdge> edgeIndex = MapSpatialIndex();
  List<AreaEdge> edges = const [];
  final sceneryIndex = <AreaNetwork, MapSpatialIndex<MapScenery>>{};
  void dispose() => labels.dispose();
  StreetDisplay streets(Iterable<AreaEdge> edges) =>
      _streetDisplay ??= StreetDisplay(edges);
  void prepare(AreaNetwork network, Size size, List<AreaNetwork> networks) {
    if (_network != network ||
        _size != size ||
        !listEquals(_networks, networks)) {
      _network = network;
      _networks = networks;
      _size = size;
      _paths.clear();
      _streetDisplay = null;
      labels.dispose();
      final unique = <int, AreaEdge>{};
      for (final map in [network, ...networks]) {
        for (final edge in map.edges) {
          unique.putIfAbsent(edge.id, () => edge);
        }
      }
      edges = unique.values.toList(growable: false);
      edgeIndex = MapSpatialIndex();
      sceneryIndex.clear();
      for (final map in {network, ...networks}) {
        final index = MapSpatialIndex<MapScenery>();
        for (final feature in map.scenery) {
          Rect? bounds;
          for (final p in feature.paths.expand((ring) => ring)) {
            final point = network.project(p, size);
            final r = Rect.fromLTWH(point.dx, point.dy, 0, 0);
            bounds = bounds == null ? r : bounds.expandToInclude(r);
          }
          if (bounds != null) index.add(feature, bounds.inflate(1));
        }
        sceneryIndex[map] = index;
      }
      for (final edge in edges) {
        final points = edge.points.map((p) => network.project(p, size));
        Rect? bounds;
        for (final p in points) {
          final point = Rect.fromLTWH(p.dx, p.dy, 0, 0);
          bounds = bounds == null ? point : bounds.expandToInclude(point);
        }
        edgeIndex.add(edge, bounds!.inflate(1));
      }
    }
  }

  Path path(Object key, Path Function() build) =>
      _paths.putIfAbsent(key, build);
}

class AreaMapPainter extends CustomPainter {
  AreaMapPainter({
    this.geometry,
    required this.network,
    required this.counts,
    this.networks = const [],
    this.walkedLineWidth = 3,
    this.showStreetNames = true,
    this.blocks = const [],
    this.completedBlocks = const {},
    this.selectedBlock,
    this.missingBlockLines = const [],
    this.fogOfWar = false,
    this.exploredCells = const {},
    this.coverageScreenWidth,
    this.transform,
    this.trace = const [],
    this.unmatchedTrails = const [],
    this.inferred = const {},
    this.textScale = 1,
    this.fadingBlocks = const {},
    this.blockAlpha = 1,
  });
  final MapGeometryCache? geometry;
  final List<AreaNetwork> networks;
  final double walkedLineWidth;
  final bool showStreetNames;
  final List<StreetBlock> blocks;
  final Set<String> completedBlocks;
  final String? selectedBlock;
  final List<List<Offset>> missingBlockLines;
  final bool fogOfWar;
  final Set<(int, int)> exploredCells;
  final double? coverageScreenWidth;
  final Matrix4? transform;
  final AreaNetwork network;
  final Map<int, int> counts;
  final List<List<Offset>> trace;
  final List<List<Offset>> unmatchedTrails;
  final Set<int> inferred;
  final double textScale;
  final Set<String> fadingBlocks;
  final double blockAlpha;

  @override
  void paint(Canvas canvas, Size size) {
    // Leave space for map controls without shifting geographic coordinates.
    final mapSize = mapDrawingSize(size);
    final cache = geometry ?? MapGeometryCache();
    cache.prepare(network, mapSize, networks);
    final inverse = Matrix4.tryInvert(transform ?? Matrix4.identity());
    final visible = inverse == null
        ? null
        : MatrixUtils.transformRect(
            inverse,
            Offset.zero & size,
          ).shift(const Offset(-12, -80)).inflate(12);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    if (transform != null) canvas.transform(transform!.storage);
    canvas.translate(12, 80);
    final zoom = transform?.getMaxScaleOnAxis() ?? 1.0;
    final maps = {
      for (final map in [network, ...networks]) map.version: map,
    }.values;
    final visibleScenery = {
      for (final map in maps)
        map: visible == null
            ? map.scenery.toSet()
            : cache.sceneryIndex[map]!.query(visible),
    };
    for (final kind in ['park', 'water', 'waterway']) {
      for (final map in maps) {
        canvas.save();
        final a = network.project(Offset(map.bbox[0], map.bbox[3]), mapSize);
        final b = network.project(Offset(map.bbox[2], map.bbox[1]), mapSize);
        canvas.clipRect(Rect.fromPoints(a, b));
        for (final feature in visibleScenery[map]!.where(
          (s) => s.kind == kind,
        )) {
          final path = cache.path(feature, () {
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
            return path;
          });
          if (visible != null &&
              !visible.overlaps(path.getBounds().inflate(1))) {
            continue;
          }
          canvas.drawPath(
            path,
            Paint()
              ..color = kind == 'park'
                  ? WanderlustColors.mapPark
                  : WanderlustColors.mapWater
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
    if (blocks.isNotEmpty) {
      cache.blocks.prepare(blocks, network, mapSize);
      cache.blocks.paint(
        canvas,
        visible,
        completedBlocks,
        selectedBlock,
        zoom,
        fadingBlocks,
        blockAlpha,
      );
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
      final path = cache.path(edge, () => _edgePath(edge, network, mapSize));
      if (visible != null && !visible.overlaps(path.getBounds().inflate(1))) {
        return;
      }
      canvas.drawPath(path, stroke);
    }

    final visibleEdges = visible == null
        ? cache.edges.toSet()
        : cache.edgeIndex.query(visible.inflate(24 / zoom));
    for (final edge in visibleEdges) {
      // Avoid subpixel detail at city-wide zoom; explored streets stay visible.
      final bounds = cache
          .path(edge, () => _edgePath(edge, network, mapSize))
          .getBounds();
      if (math.max(bounds.width, bounds.height) * zoom < 1.5) continue;
      draw(edge, 0);
    }
    final painted =
        visibleEdges.where((edge) => (counts[edge.id] ?? 0) > 0).toList()
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
        visibleEdges: visibleEdges,
        cache: cache.labels,
      ),
      textScale,
      cache: cache.labels,
    );
    paintUnmatchedTrails(
      canvas,
      unmatchedTrails,
      project,
      width:
          coverageScreenWidth ??
          math.min(
            walkedLineWidth,
            HeatRamp.width(1) * math.sqrt(zoom) * walkedLineWidth / 4.5,
          ),
    );
    // Labels must never erase walked coverage, including other streets that
    // cross a label's background. Street labels are offset from their own road.
    canvas.save();
    if (transform != null) canvas.transform(transform!.storage);
    canvas.translate(12, 80);
    final consolidate = mapSpanKm(network) / zoom >= 0.6;
    final streets = consolidate ? cache.streets(cache.edges) : null;
    for (final edge in painted) {
      for (final display in streets?.geometry(edge) ?? [edge]) {
        draw(display, counts[edge.id]!);
      }
    }
    canvas.restore();
    paintWalkOverlay(canvas, maps.toList(), inferred, trace, project);
    for (final line in missingBlockLines) {
      final path = Path();
      for (var i = 0; i < line.length; i++) {
        final p = project(line[i]);
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xff946227)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round,
      );
    }
    if (fogOfWar && visible != null) {
      cache.fog.prepare(exploredCells, network, mapSize);
      canvas.save();
      if (transform != null) canvas.transform(transform!.storage);
      canvas.translate(12, 80);
      cache.fog.paint(canvas, visible);
      canvas.restore();
    }
    canvas.restore();
    if (geometry == null) cache.dispose();
  }

  @override
  bool shouldRepaint(AreaMapPainter oldDelegate) =>
      oldDelegate.blocks != blocks ||
      oldDelegate.completedBlocks != completedBlocks ||
      oldDelegate.selectedBlock != selectedBlock ||
      oldDelegate.missingBlockLines != missingBlockLines ||
      oldDelegate.blockAlpha != blockAlpha ||
      oldDelegate.network != network ||
      oldDelegate.counts != counts ||
      oldDelegate.networks != networks ||
      oldDelegate.walkedLineWidth != walkedLineWidth ||
      oldDelegate.showStreetNames != showStreetNames ||
      oldDelegate.fogOfWar != fogOfWar ||
      oldDelegate.exploredCells != exploredCells ||
      oldDelegate.coverageScreenWidth != coverageScreenWidth ||
      oldDelegate.trace != trace ||
      oldDelegate.unmatchedTrails != unmatchedTrails ||
      oldDelegate.inferred != inferred ||
      oldDelegate.textScale != textScale ||
      oldDelegate.transform != transform;
}

Path _edgePath(AreaEdge edge, AreaNetwork network, Size size) {
  final path = Path();
  for (var i = 0; i < edge.points.length; i++) {
    final p = network.project(edge.points[i], size);
    if (i == 0) {
      path.moveTo(p.dx, p.dy);
    } else {
      path.lineTo(p.dx, p.dy);
    }
  }
  return path;
}
