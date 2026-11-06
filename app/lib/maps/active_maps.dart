import '../diagnostics/map_diagnostics.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../data/area_network.dart';
import 'area_store.dart';
import 'map_cells.dart';

class ActiveMaps extends ChangeNotifier {
  ActiveMaps(
    this.store, {
    this.cellBudget = maxCells,
    this.byteBudget = maxBytes,
    this.sectionBudget = maxSections,
  }) : assert(cellBudget > 0 && cellBudget <= maxCells),
       assert(byteBudget > 0 && byteBudget <= maxBytes),
       assert(sectionBudget > 0 && sectionBudget <= maxSections);
  final int cellBudget, byteBudget, sectionBudget;

  final SpatialAreaStore store;
  static const maxCells = 100,
      maxBytes = 64 * 1024 * 1024,
      maxSections = 150000;
  List<OfflineArea> library = [];
  List<AreaNetwork> networks = [];
  String? anchor;
  Offset? recording;
  Rect? browsing;
  bool indexing = false, limited = false, gesturing = false;
  int get loadedBytes => _cache.values.fold(0, (n, e) => n + e.$3);
  int get loadedSections => {for (final m in networks) ...m.edgeIds}.length;
  void gestureStarted() {
    gesturing = true;
  }

  bool get loading => _running;
  int _reservedBytes = 0, _reservedSections = 0;

  /// Reuse only an exact source-set match, never an obsolete loaded revision.
  AreaNetwork? loadedCell(String cell, List<CellSource> sources) {
    final ordered = [...sources]
      ..sort((a, b) => a.version.compareTo(b.version));
    final key = ordered.map((e) => '${e.version}/${e.digest}').join('|');
    final entry = _cache[cell];
    return entry?.$1 == key ? entry!.$2 : null;
  }

  bool reserveProcessing(int bytes, int sections) {
    if (bytes == 0 && sections == 0) return true;
    if (bytes + loadedBytes > byteBudget ||
        sections + loadedSections > sectionBudget ||
        networks.length >= cellBudget) {
      return false;
    }
    _reservedBytes = bytes;
    _reservedSections = sections;
    return true;
  }

  void releaseProcessing() {
    _reservedBytes = 0;
    _reservedSections = 0;
  }

  String? error;
  Object? failure;
  bool _closed = false, _again = false, _running = false;
  Future<void> _pending = Future.value();
  Future<void> get settled => _pending;
  final _cache = <String, (String, AreaNetwork, int)>{};
  final _lastUsed = <String, int>{};
  int _clock = 0;
  String? _recordingCell;
  int revision = 0;
  final _ready = Completer<void>();
  Future<void> initialize() {
    if (!_running && !_ready.isCompleted) unawaited(refresh());
    return _ready.future;
  }

  void position(Offset? point) {
    final cell = point == null ? null : MapCell.at(point).id;
    if (cell == _recordingCell) return;
    _recordingCell = cell;
    recording = point;
    unawaited(refresh());
  }

  void view(Rect bounds) {
    final wasGesturing = gesturing;
    gesturing = false;
    if (!wasGesturing &&
        browsing != null &&
        MapCell.at(browsing!.center).id == MapCell.at(bounds.center).id &&
        (browsing!.width - bounds.width).abs() < MapCell.latitudeStep) {
      return;
    }
    browsing = bounds;
    unawaited(refresh());
  }

  Future<void> select(String version) async {
    await store.selectArea(version);
    library = await store.listAreas();
    final area = library.where((a) => a.version == version).firstOrNull;
    if (area?.bounds case final bounds?) {
      browsing = bounds;
      anchor = emptyMap(area!.name, boundsList(bounds), 'view/$version');
    }
    await refresh();
  }

  Future<void> refresh() {
    if (_closed) return Future.value();
    if (_running) {
      _again = true;
      return _pending;
    }
    _running = true;
    _pending = _run().whenComplete(() => _running = false);
    return _pending;
  }

  Future<void> _run() async {
    do {
      _again = false;
      try {
        library = await store.listAreas();
        if (library.isEmpty) {
          anchor = null;
          browsing = null;
        } else if (anchor != null &&
            !library.any(
              (a) =>
                  'view/${a.version}' ==
                  (jsonDecode(anchor!)
                      as Map)['wanderlust_network']['network_version'],
            )) {
          anchor = null;
          browsing = null;
        }
        if (browsing == null) {
          final selected = await store.selectedVersion();
          final area =
              library.where((a) => a.version == selected).firstOrNull ??
              library.firstOrNull;
          if (area != null) {
            var bounds = area.bounds;
            if (bounds == null) {
              final source = await store.readArea(area.version);
              if (source != null) {
                bounds = geographicBounds(AreaNetwork.parse(source).bbox);
              }
            }
            if (bounds != null) {
              browsing = bounds;
              anchor = emptyMap(
                area.name,
                boundsList(bounds),
                'view/${area.version}',
              );
            }
          }
        }
        if (_closed) return;
        if (!_ready.isCompleted) {
          _ready.complete();
          notifyListeners();
        }
        await _load();
        if (_closed) return;
        // One map at a time, yielding between transactions; recording is independent.
        indexing = true;
        notifyListeners();
        final changed = await store.indexNext(recording ?? browsing?.center);
        indexing = changed;
        if (changed) {
          revision++;
          _again = true;
        }
        error = null;
        failure = null;
      } catch (e, stack) {
        MapAttempt.current?.capture(e, stack);
        failure = e;
        error = 'Could not load nearby maps. Your recording is safe.';
        indexing = false;
        if (!_ready.isCompleted) _ready.complete();
      }
      if (!_closed) notifyListeners();
      if (_again) await Future<void>.delayed(Duration.zero);
    } while (_again && !_closed);
  }

  Future<void> _load() async {
    if (gesturing) return;
    final rows = await store.listCells();
    final grouped = <String, List<CellSource>>{};
    for (final row in rows) {
      (grouped[row.cell] ??= []).add(row);
    }
    final overview =
        browsing != null &&
        math.max(
                  browsing!.height,
                  browsing!.width *
                      math.cos(browsing!.center.dy * math.pi / 180),
                ) *
                111.32 >
            20;
    double score(String id) {
      final b = MapCell.parse(id).core;
      if (recording != null) {
        final delta = (b.center - recording!);
        final d =
            Offset(
              delta.dx * math.cos(recording!.dy * math.pi / 180),
              delta.dy,
            ).distance /
            MapCell.latitudeStep;
        if (d < 3) return d;
      }
      if (overview) return double.infinity;
      if (browsing != null && b.overlaps(browsing!)) {
        return 100 +
            (b.center - browsing!.center).distance / MapCell.latitudeStep;
      }
      if (browsing != null &&
          b.overlaps(browsing!.inflate(MapCell.latitudeStep))) {
        return 10000 +
            (b.center - browsing!.center).distance / MapCell.latitudeStep;
      }
      return double.infinity;
    }

    final ids = grouped.keys.where((id) => score(id).isFinite).toList()
      ..sort((a, b) {
        final sa = score(a), sb = score(b);
        if (sa >= 10000 && sb >= 10000) {
          final recent = (_lastUsed[b] ?? 0).compareTo(_lastUsed[a] ?? 0);
          if (recent != 0) return recent;
        }
        final c = sa.compareTo(sb);
        return c == 0 ? a.compareTo(b) : c;
      });
    final next = <String, (String, AreaNetwork, int)>{};
    final sections = <int>{};
    var bytes = 0;
    limited = false;
    for (final id in ids) {
      if (_closed || gesturing || _again) return;
      if (next.length >= cellBudget - (_reservedBytes > 0 ? 1 : 0)) {
        limited = true;
        break;
      }
      final sources = grouped[id]!
        ..sort((a, b) => a.version.compareTo(b.version));
      final key = sources.map((e) => '${e.version}/${e.digest}').join('|');
      // Reject oversized candidates before materialising text or parsed geometry.
      if (sources.any((e) => e.bytes > byteBudget) ||
          sources.any((e) => e.sections > sectionBudget)) {
        limited = true;
        continue;
      }
      var cached = _cache[id];
      if (cached == null || cached.$1 != key) {
        final source = await store.readCell(id);
        if (source == null) continue;
        final size = utf8.encode(source).length;
        if (size + bytes + _reservedBytes > byteBudget) {
          limited = true;
          continue;
        }
        final map = await compute(AreaNetwork.parse, source);
        if (_closed || gesturing || _again) return;
        cached = (key, map, size);
      }
      final added = cached.$2.edgeIds.difference(sections);
      if (bytes + cached.$3 + _reservedBytes > byteBudget ||
          sections.length + added.length + _reservedSections > sectionBudget) {
        limited = true;
        continue;
      }
      bytes += cached.$3;
      sections.addAll(added);
      next[id] = cached;
      // Publish a useful first cell without waiting for the whole window. Later
      // cells arrive together, preventing a matching/topology rebuild per cell.
      if (networks.isEmpty && next.length == 1 && !_again && !_closed) {
        _cache
          ..clear()
          ..addAll(next);
        networks = List.unmodifiable(next.values.map((e) => e.$2));
        notifyListeners();
        await Future<void>.delayed(Duration.zero);
      }
    }
    _cache
      ..clear()
      ..addAll(next);
    _clock++;
    _lastUsed.removeWhere((id, _) => !next.containsKey(id));
    for (final id in next.keys) {
      if (score(id) < 10000) _lastUsed[id] = _clock;
    }
    networks = List.unmodifiable(next.values.map((e) => e.$2));
  }

  @override
  void dispose() {
    _closed = true;
    _cache.clear();
    super.dispose();
  }
}
