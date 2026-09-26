import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/area_network.dart';
import '../geo/geo_core_ffi.dart';
import '../transfer/walk_codec.dart';
import '../recording/walk_store.dart';
import 'coverage_store.dart';

// Bump when matching rules change: old saved traces are then reprocessed once.
const matchingRevision = 'consecutive-observations-osm-v3';
typedef MatchBatch = Future<List<MatchResult>> Function(String, List<String>);

class CoverageFailure implements Exception {
  const CoverageFailure(this.stage, this.detail);
  final String stage;
  final String detail;
  @override
  String toString() => '$stage: $detail';
}

Future<List<MatchResult>> _matchOnWorker((String, List<String>) input) async {
  late final WanderlustGeo geo;
  try {
    geo = WanderlustGeo.open();
  } catch (e) {
    throw CoverageFailure('Native library / ABI unavailable', e.toString());
  }
  late final Matcher matcher;
  try {
    matcher = geo.loadNetwork(input.$1);
  } catch (e) {
    throw CoverageFailure('Street network rejected', e.toString());
  }
  try {
    return [for (final gpx in input.$2) matcher.matchGpx(gpx)];
  } catch (e) {
    throw CoverageFailure('Walk matching failed', e.toString());
  } finally {
    matcher.dispose();
  }
}

Future<List<MatchResult>> matchBatchInBackground(
  String network,
  List<String> walks,
) => compute(_matchOnWorker, (network, walks));

/// Serializes matching and persistence; repeated refreshes never add counts.
/// Matching runs off the UI isolate. Raw walks remain untouched on any failure.
class CoverageController extends ChangeNotifier {
  CoverageController({
    required CoverageStore store,
    Future<String> Function()? loadNetwork,
    MatchBatch? match,
    this.loadSavedNetworks,
  }) : _store = store,
       _loadNetwork =
           loadNetwork ??
           (() => rootBundle.loadString(
             'assets/geo/bremen-center.streets.geojson',
           )),
       _match = match ?? matchBatchInBackground;
  final Future<List<String>> Function()? loadSavedNetworks;
  List<AreaNetwork> networks = const [];
  final CoverageStore _store;
  final Future<String> Function() _loadNetwork;
  final MatchBatch _match;
  AreaNetwork? network;
  Map<int, int> counts = const {};
  bool busy = false;
  CoverageFailure? error;
  int processedWalks = 0;
  bool _disposed = false;
  Future<void> _queue = Future.value();
  Future<void>? _initializing;
  Future<void> get settled async {
    await _initializing;
    await _queue;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() => _initializing ??= _initialize();
  Future<void> _initialize() async {
    try {
      network ??= AreaNetwork.parse(await _loadNetwork());
      await _store.registerNetwork(network!);
      await _loadMaps(network!);
      error = null;
    } catch (e) {
      error = CoverageFailure(
        network == null
            ? 'Area could not load'
            : 'Coverage storage unavailable',
        e.toString(),
      );
    }
    _notify();
  }

  Future<(List<AreaNetwork>, Map<int, int>)> _readMaps(
    AreaNetwork selected,
  ) async {
    final maps = <String, AreaNetwork>{selected.version: selected};
    for (final source in await loadSavedNetworks?.call() ?? <String>[]) {
      final map = AreaNetwork.parse(source);
      maps.putIfAbsent(map.version, () => map);
    }
    for (final map in maps.values) {
      await _store.registerNetwork(map);
    }
    return (
      List<AreaNetwork>.unmodifiable(maps.values),
      Map<int, int>.unmodifiable(
        await _store.readCombinedCounts(maps.keys.toList()),
      ),
    );
  }

  Future<void> _loadMaps(AreaNetwork selected) async {
    final loaded = await _readMaps(selected);
    networks = loaded.$1;
    counts = loaded.$2;
  }

  Future<void> refreshMaps() async {
    _queue = _queue.then((_) async {
      if (_disposed) return;
      try {
        await initialize();
        if (network != null) await _loadMaps(network!);
        error = null;
      } catch (e) {
        error = CoverageFailure('Could not load saved maps', e.toString());
      }
      _notify();
    });
    await _queue;
  }

  /// Queue area changes with matching: an in-flight result is always committed
  /// to its original network, never the newly selected map.
  Future<bool> useNetwork(
    String source, {
    Future<void> Function()? persistSelection,
  }) async {
    var success = false;
    _queue = _queue.then((_) async {
      if (_disposed) return;
      busy = true;
      _notify();
      try {
        await initialize();
        final area = AreaNetwork.parse(source);
        final loaded = await _readMaps(area);
        if (persistSelection != null) await persistSelection();
        networks = loaded.$1;
        counts = loaded.$2;
        network = area;
        error = null;
        _initializing = Future.value();
        success = true;
      } catch (e) {
        error = CoverageFailure('Could not open map', e.toString());
      } finally {
        busy = false;
        _notify();
      }
    });
    await _queue;
    return success;
  }

  Future<void> synchronize(List<SavedWalk> walks) {
    if (_disposed) return Future.value();
    final snapshot = List<SavedWalk>.of(walks);
    _queue = _queue.then((_) => _synchronize(snapshot));
    return _queue;
  }

  Future<void> _synchronize(List<SavedWalk> walks) async {
    if (_disposed) return;
    busy = true;
    _notify();
    try {
      await initialize();
      if (error != null) {
        // Storage/assets can become available on an explicit retry.
        _initializing = null;
        await initialize();
      }
      if (network == null || error != null) return;
      for (final area in networks) {
        final pending = <(SavedWalk, String, String)>[];
        for (final walk in walks) {
          if (walk.status == 'recording') continue;
          final gpx = WalkCodec.exportGpx(walk);
          final fingerprint = sha256
              .convert(utf8.encode('$matchingRevision\n$gpx'))
              .toString();
          if (await _store.matchFingerprint(walk.id, area.version) !=
              fingerprint) {
            pending.add((walk, gpx, fingerprint));
          }
        }
        // Do not send empty GPX to a parser which correctly rejects empty tracks.
        final nonempty = pending.where((p) => p.$1.points.isNotEmpty).toList();
        final results = nonempty.isEmpty
            ? <MatchResult>[]
            : await _match(area.geojson, nonempty.map((p) => p.$2).toList());
        if (results.length != nonempty.length) {
          throw StateError('Matcher returned an incomplete batch');
        }
        final matched = <int, Set<int>>{};
        for (var i = 0; i < nonempty.length; i++) {
          final edges = results[i].walked.toSet();
          if (!area.edgeIds.containsAll(edges)) {
            throw StateError('Matcher returned unknown street ids');
          }
          matched[nonempty[i].$1.id] = edges;
        }
        for (final p in pending) {
          await _store.replaceWalkMatch(
            p.$1.id,
            area.version,
            p.$3,
            matched[p.$1.id] ?? {},
          );
        }
      }
      counts = Map<int, int>.unmodifiable(
        await _store.readCombinedCounts(
          networks.map((map) => map.version).toList(),
        ),
      );
      processedWalks = walks.where((w) => w.status != 'recording').length;
      error = null;
    } catch (e) {
      error = e is CoverageFailure
          ? e
          : CoverageFailure('Could not update streets', e.toString());
    } finally {
      busy = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
