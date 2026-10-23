import 'block_store.dart';
import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import '../coverage/coverage_controller.dart';
import '../data/area_network.dart';
import '../widgets/map_spatial_index.dart';
import 'block_geometry.dart';
import 'block_progress.dart';

/// Derived, optional state: no recording/database writes and no UI-isolate topology.
class BlockController extends ChangeNotifier {
  BlockController(
    this.coverage, {
    Future<BlockTopology> Function(List<AreaNetwork>)? build,
    this.cache,
  }) : _build = build ?? ((maps) => compute(buildBlockTopology, maps)) {
    coverage.addListener(_changed);
    if (cache != null) {
      _persisting = cache!.completedCount().then((value) {
        if (!_closed) {
          _total = value;
          notifyListeners();
        }
      });
    }
  }
  final CoverageController coverage;
  final BlockCacheStore? cache;
  int? _total;
  Future<void> _persisting = Future.value();
  final Future<BlockTopology> Function(List<AreaNetwork>) _build;
  bool enabled = false, busy = false, needsRefresh = false;
  String? error;
  List<StreetBlock> blocks = const [];
  Map<String, BlockProgress> saved = const {}, live = const {};
  Set<int> _supported = {}, _liveSupported = {};
  Set<int> get previewSections => _liveSupported;
  List<AreaNetwork> _maps = const [];
  final _reverse = <int, Set<StreetBlock>>{};
  MapSpatialIndex<StreetBlock> _index = MapSpatialIndex(cellSize: .001);
  int _epoch = 0;
  bool _closed = false;
  Future<void> _pending = Future.value();
  Set<String>? _cachedSources;
  BlockTopology? _cachedTopology;
  Future<void> get settled async {
    await _pending;
    await _persisting;
  }

  Future<void> refreshTotal() async {
    if (cache == null || _closed) return;
    await cache!.reconcileBlocks();
    final count = await cache!.completedCount();
    if (!_closed && count != _total) {
      _total = count;
      notifyListeners();
    }
  }

  int get completed => _total ?? saved.values.where((p) => p.complete).length;
  Set<String> get completedIds => {
    for (final e in saved.entries)
      if (e.value.complete) e.key,
  };
  int topologyRevision = 0;

  void setEnabled(bool value) {
    if (enabled == value) return;
    enabled = value;
    if (value) {
      _changed();
    } else {
      _epoch++;
      busy = false;
      _maps = const [];
    }
    notifyListeners();
  }

  void retry() {
    _maps = const [];
    error = null;
    _changed();
  }

  bool _viewportBusy = false;
  void setViewportBusy(bool value) {
    _viewportBusy = value;
    if (!value) _changed();
  }

  void _changed() {
    if (_viewportBusy ||
        !enabled ||
        _closed ||
        coverage.busy ||
        coverage.error != null) {
      return;
    }
    final maps = coverage.networks;
    if (!listEquals(_maps, maps)) {
      _maps = List.of(maps);
      final epoch = ++_epoch;
      busy = true;
      error = null;
      // Hide stale geometry immediately after a map revision/removal.
      blocks = const [];
      saved = const {};
      live = const {};
      _index = MapSpatialIndex(cellSize: .001);
      notifyListeners();
      _pending = _rebuild(List.of(maps), epoch);
    } else if (!busy) {
      _updateProgress();
    }
  }

  Future<void> _rebuild(List<AreaNetwork> maps, int epoch) async {
    try {
      final sources = {for (final map in maps) map.version};
      final result =
          _cachedTopology != null && setEquals(sources, _cachedSources)
          ? _cachedTopology!
          : cache == null
          ? await _build(maps)
          : await cache!.readTopology(topologyCacheKey(maps)) ??
                await _build(maps);
      if (cache != null) {
        await cache!.writeTopology(topologyCacheKey(maps), result);
      }
      if (_closed || epoch != _epoch || !enabled) return;
      _cachedSources = sources;
      _cachedTopology = result;
      blocks = result.blocks;
      needsRefresh = result.needsRefresh;
      topologyRevision++;
      _reverse.clear();
      _index = MapSpatialIndex(cellSize: .001);
      for (final block in blocks) {
        _index.add(block, block.bounds);
        for (final id in block.boundary.expand((b) => b.evidence.keys)) {
          (_reverse[id] ??= {}).add(block);
        }
      }
      _supported = {};
      _liveSupported = {};
      saved = {};
      live = {};
      busy = false;
      _updateProgress(force: true);
    } catch (_) {
      if (_closed || epoch != _epoch) return;
      busy = false;
      error = 'Could not find blocks. Your recordings are safe.';
      notifyListeners();
    }
  }

  void _updateProgress({bool force = false}) {
    final supported = coverage.supportedSections;
    final savedChanged = force || !setEquals(supported, _supported);
    final preview = {...supported, ...coverage.liveSupportedSections};
    final changed = {
      ...supported.difference(_supported),
      ..._supported.difference(supported),
      ...preview.difference(_liveSupported),
      ..._liveSupported.difference(preview),
    };
    if (!force && changed.isEmpty) {
      if (cache != null) _persisting = _persisting.then((_) => refreshTotal());
      return;
    }
    final affected = force
        ? blocks.toSet()
        : {for (final id in changed) ...?_reverse[id]};
    final nextSaved = Map<String, BlockProgress>.of(saved),
        nextLive = Map<String, BlockProgress>.of(live);
    for (final block in affected) {
      nextSaved[block.id] = blockProgress(block, supported);
      nextLive[block.id] = blockProgress(block, preview);
    }
    _supported = supported;
    _liveSupported = preview;
    saved = Map.unmodifiable(nextSaved);
    if (cache != null && savedChanged) {
      final snapshot = blocks, progress = saved;
      final sources = {for (final m in _maps) ...m.sourceVersions}.toList();
      _persisting = _persisting
          .then((_) async {
            await cache!.saveBlocks(snapshot, progress, sources);
            await cache!.reconcileBlocks();
            final count = await cache!.completedCount();
            if (!_closed) {
              _total = count;
              notifyListeners();
            }
          })
          .catchError((Object e) {
            if (!_closed) {
              error = 'Could not update saved block progress.';
              notifyListeners();
            }
          });
    }
    live = Map.unmodifiable(nextLive);
    notifyListeners();
  }

  StreetBlock? hit(Offset p) {
    final candidates = _index.query(Rect.fromCircle(center: p, radius: 1e-10));
    for (final block in candidates) {
      var inside = false;
      final poly = block.points;
      for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
        final a = poly[i], b = poly[j];
        if ((a.dy > p.dy) != (b.dy > p.dy) &&
            p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
          inside = !inside;
        }
      }
      if (inside) return block;
    }
    return null;
  }

  @override
  void dispose() {
    _closed = true;
    _epoch++;
    coverage.removeListener(_changed);
    super.dispose();
  }
}
