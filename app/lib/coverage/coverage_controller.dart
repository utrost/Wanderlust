import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../data/area_network.dart';
import '../maps/map_cells.dart';
import '../geo/coverage_resolution.dart';
import '../geo/geo_core_ffi.dart';
import '../geo/matching_session.dart';
import '../geo/matching_worker.dart';
import '../recording/saved_walk.dart';
import '../review/gap_routes.dart';
import '../transfer/walk_codec.dart';
import 'coverage_store.dart';
import 'coverage_evidence.dart';
import 'unmatched_trails.dart';

// Bump when matching rules change: old saved traces are then reprocessed once.
const matchingRevision = 'movement-candidates-v14';
typedef MatchBatch = Future<List<MatchResult>> Function(String, List<String>);

typedef CoverageFailure = MatchingFailure;

Future<List<MatchResult>> _matchOnWorker(
  (String, List<String>, bool) input,
) async {
  final session = MatchingSession();
  try {
    return session.match(input.$1, input.$2, fillSmallGaps: input.$3);
  } finally {
    session.dispose();
  }
}

Future<List<MatchResult>> matchBatchInBackground(
  String network,
  List<String> walks, {
  bool fillSmallGaps = false,
}) => compute(_matchOnWorker, (network, walks, fillSmallGaps));

/// Serializes matching and persistence; repeated refreshes never add counts.
/// Matching runs off the UI isolate. Raw walks remain untouched on any failure.
class CoverageController extends ChangeNotifier {
  CoverageController({
    required CoverageStore store,
    Future<String?> Function()? loadNetwork,
    MatchBatch? match,
    this.loadSavedNetworks,
    this.loadActiveNetworks,
    this.loadWalk,
    this.liveInterval = const Duration(seconds: 2),
  }) : _store = store,
       _loadNetwork = loadNetwork ?? (() async => null),
       _match = match;
  final Future<SavedWalk> Function(int)? loadWalk;
  final Duration liveInterval;
  final Future<List<String>> Function()? loadSavedNetworks;
  final Future<List<AreaNetwork>> Function()? loadActiveNetworks;
  SavedWalk? _liveWalk;
  Set<int> _liveEdges = {};
  Set<int> _liveEstimated = {};
  final _evidence = CoverageEvidence();
  final _trails = UnmatchedTrails();
  Set<int> _liveUnmatched = {};
  List<List<Offset>> _savedTrailLines = const [];
  List<List<Offset>> _liveTrailLines = const [];
  List<List<Offset>> get unmatchedTrails => [
    ..._savedTrailLines,
    ..._liveTrailLines,
  ];
  Timer? _liveTimer;
  bool _liveScheduled = false;
  bool _previewActive = true;
  int _liveEpoch = 0;
  String? liveError;
  Set<int> get supportedSections =>
      _evidence.supported(networks.map((n) => n.version));
  Set<int> get estimatedSections =>
      _evidence.estimated(networks.map((n) => n.version));
  Set<int> get liveSupportedSections => _liveEdges.difference(_liveEstimated);
  Map<int, int>? _displayCounts;
  Map<int, int> get displayCounts => _displayCounts ??= (() {
    final direct = _evidence.counts(networks.map((n) => n.version));
    return Map<int, int>.unmodifiable({
      ...direct,
      for (final id in {..._liveEdges, ..._liveEstimated})
        id: (direct[id] ?? 0) + 1,
    });
  })();

  /// Coalesce fixes; previews never write coverage or mark an unfinished walk saved.
  void updateLive(SavedWalk walk) {
    if (_disposed ||
        (_liveWalk?.id == walk.id &&
            _liveWalk?.points.length == walk.points.length)) {
      return;
    }
    if (_liveWalk?.id != walk.id) {
      _liveEpoch++;
      _liveEdges = {};
      _liveEstimated = {};
      _liveUnmatched = {};
      _liveTrailLines = const [];
    }
    _liveWalk = walk;
    _scheduleLive();
  }

  /// Hidden screens need no live rendering work. On return, match all fixes
  /// in the current sequence, including evidence collected while hidden.
  void setPreviewActive(bool active) {
    _previewActive = active;
    if (active) _scheduleLive();
  }

  void _scheduleLive() {
    if (_disposed || !_previewActive || _liveScheduled || _liveWalk == null) {
      return;
    }
    _liveScheduled = true;
    _liveTimer = Timer(liveInterval, () {
      _queue = _queue.then((_) async {
        final walk = _liveWalk;
        var epoch = _liveEpoch;
        try {
          if (_disposed ||
              !_previewActive ||
              walk == null ||
              walk.points.length < 2) {
            return;
          }
          await initialize();
          epoch = _liveEpoch;
          // Re-evaluate the sequence: later evidence can correct earlier choices.
          // Replace the preview rather than accumulating provisional mistakes.
          final gpx = WalkCodec.exportGpx(walk);
          final edges = <int>{};
          final estimated = <int>{};
          final unmatchedByArea = <Set<int>>[];
          final traceBounds = Rect.fromLTRB(
            walk.points.map((p) => p.longitude).reduce((a, b) => a < b ? a : b),
            walk.points.map((p) => p.latitude).reduce((a, b) => a < b ? a : b),
            walk.points.map((p) => p.longitude).reduce((a, b) => a > b ? a : b),
            walk.points.map((p) => p.latitude).reduce((a, b) => a > b ? a : b),
          ).inflate(.001);
          for (final area in networks) {
            if (!traceBounds.overlaps(geographicBounds(area.bbox))) continue;
            final result = await _runMatch(area.geojson, [gpx]);
            if (result.length != 1 ||
                !area.edgeIds.containsAll(result.single.walked)) {
              throw StateError('Invalid live coverage result');
            }
            edges.addAll(
              result.single.walked.toSet().difference(
                result.single.inferred.toSet(),
              ),
            );
            estimated.addAll(result.single.inferred);
            if (result.single.unmatched.any(
              (i) => i <= 0 || i >= walk.points.length,
            )) {
              throw StateError('Invalid live GPS trail result');
            }
            unmatchedByArea.add(result.single.unmatched.toSet());
          }
          if (!_disposed && epoch == _liveEpoch && _liveWalk?.id == walk.id) {
            _liveEdges = edges;
            _liveEstimated = estimated.difference(edges);
            _liveUnmatched.clear();
            _liveUnmatched.addAll(UnmatchedTrails.common(unmatchedByArea));
            _liveTrailLines = UnmatchedTrails.fromIndices(walk, _liveUnmatched);
            liveError = null;
            _notify();
          }
        } catch (_) {
          if (!_disposed && epoch == _liveEpoch) {
            liveError =
                'Live colour is unavailable for now. Your walk is still recording.';
            _notify();
          }
        } finally {
          _liveScheduled = false;
          if (_liveWalk != walk) _scheduleLive();
        }
      });
    });
  }

  void _resetLiveMaps() {
    _trails.clear();
    _evidence.clear();
    _savedTrailLines = const [];
    _liveUnmatched = {};
    _liveTrailLines = const [];
    _liveEpoch++;
    final visible = {for (final map in networks) ...map.edgeIds};
    _liveEdges = _liveEdges.intersection(visible);
    _liveEstimated = _liveEstimated.intersection(visible);
    _scheduleLive();
  }

  List<AreaNetwork> networks = const [];
  final CoverageStore _store;
  final Future<String?> Function() _loadNetwork;
  final MatchBatch? _match;
  final MatchingWorker _worker = MatchingWorker();
  bool _fillSmallGaps = false;
  bool _autoFillGaps = false;

  Future<List<MatchResult>> _runMatch(
    String network,
    List<String> walks, {
    List<List<int>>? confirmed,
  }) async {
    final results =
        await (_match?.call(network, walks) ??
            _worker.match(network, walks, fillSmallGaps: _fillSmallGaps));
    if (walks.isEmpty) return results;
    final estimates = _autoFillGaps
        ? await automaticGapSections(
            network,
            walks,
            confirmed ?? List.generate(walks.length, (_) => <int>[]),
          )
        : List.generate(walks.length, (_) => <int>{});
    final resolved = [
      for (var i = 0; i < results.length; i++)
        MatchResult(
          walked: {...results[i].walked, ...estimates[i]}.toList(),
          inferred: {
            ...results[i].inferred,
            ...estimates[i].difference(results[i].walked.toSet()),
          }.toList(),
          unmatched: results[i].unmatched,
          gapsFilled: results[i].gapsFilled,
          gapsRejected: results[i].gapsRejected,
        ),
    ];
    return resolveCoverageDisplay(
      network,
      walks,
      resolved,
      confirmed: confirmed,
    );
  }

  /// Serialize policy changes with matching. Invalidate any in-flight preview,
  /// then rebuild saved memberships and the whole current walk under the policy.
  Future<void> setFillSmallGaps(
    bool enabled,
    List<SavedWalk> walks, {
    bool? autoFillGaps,
  }) {
    if (_disposed) return Future.value();
    _liveEpoch++;
    final snapshot = List<SavedWalk>.of(walks);
    _queue = _queue.then((_) async {
      if (_disposed ||
          (_fillSmallGaps == enabled &&
              (autoFillGaps == null || _autoFillGaps == autoFillGaps))) {
        return;
      }
      _autoFillGaps = autoFillGaps ?? _autoFillGaps;
      _fillSmallGaps = enabled;
      _trails.clear();
      _savedTrailLines = const [];
      _liveUnmatched = {};
      _liveTrailLines = const [];
      _liveEdges = {};
      _liveEstimated = {};
      await _synchronize(snapshot);
      _scheduleLive();
    });
    return _queue;
  }

  AreaNetwork? network;
  Map<int, int> counts = const {};
  bool busy = false;
  bool rematching = false;
  int routeUpdateRevision = 0;
  bool initialized = false;
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
    _displayCounts = null;
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() => _initializing ??= _initialize();
  Future<void> _initialize() async {
    try {
      final source = await _loadNetwork();
      await _loadMaps(source == null ? null : AreaNetwork.parse(source));
      error = null;
    } catch (e) {
      error = CoverageFailure(
        network == null
            ? 'Area could not load'
            : 'Coverage storage unavailable',
        e.toString(),
      );
    }
    initialized = true;
    _notify();
  }

  Future<(List<AreaNetwork>, Map<int, int>)> _readMaps(
    AreaNetwork? selected,
  ) async {
    final maps = <String, AreaNetwork>{
      if (selected != null && selected.edges.isNotEmpty)
        selected.version: selected,
    };
    for (final map in await loadActiveNetworks?.call() ?? <AreaNetwork>[]) {
      if (map.edges.isNotEmpty) maps.putIfAbsent(map.version, () => map);
    }
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
        await _store.readCombinedCounts(
          maps.values.map((m) => m.coverageVersion).toList(),
        ),
      ),
    );
  }

  Future<void> _loadMaps(AreaNetwork? selected) async {
    final loaded = await _readMaps(selected);
    networks = loaded.$1;
    network = selected ?? networks.firstOrNull;
    counts = loaded.$2;
    _resetLiveMaps();
    await _restoreEvidence();
  }

  Future<void> _restoreEvidence() async {
    if (_store case final BatchCoverageStore cache) {
      for (final map in networks) {
        for (final e in (await cache.readEvidenceBatch(
          map.coverageVersion,
        )).entries) {
          _evidence.put(
            e.key,
            map.version,
            e.value.$1.supported,
            e.value.$1.estimated,
          );
        }
      }
    }
  }

  Future<void> refreshMaps() async {
    final request = ++_mapRequest;
    _queue = _queue.then((_) async {
      if (_disposed || request != _mapRequest) return;
      try {
        await initialize();
        final source = await _loadNetwork();
        await _loadMaps(source == null ? null : AreaNetwork.parse(source));
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
        _resetLiveMaps();
        await _restoreEvidence();
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
    final request = ++_syncRequest;
    _queue = _queue.then(
      (_) => request == _syncRequest
          ? _synchronize(snapshot, request)
          : Future<void>.value(),
    );
    return _queue;
  }

  int _syncRequest = 0, _mapRequest = 0;

  final _prepared = Expando<(String, String)>('prepared traces');
  (String, String) _prepare(SavedWalk walk) {
    return _prepared[walk] ??= (() {
      final gpx = WalkCodec.exportGpx(walk);
      return (gpx, sha256.convert(utf8.encode(gpx)).toString());
    })();
  }

  String _fingerprint(SavedWalk walk) {
    final traceHash = walk.fingerprint ?? _prepare(walk).$2;
    return '$matchingRevision/${walk.activity.name}/${_fillSmallGaps ? 'fill-v1' : 'direct'}/${_autoFillGaps ? 'auto-gaps-v1' : 'manual-gaps'}/$traceHash/${walk.confirmedSections.join(',')}';
  }

  Future<void> _synchronize(List<SavedWalk> walks, [int? request]) async {
    if (_disposed) return;
    var updatedRoutes = false;
    _notify();
    try {
      await initialize();
      if (error != null) {
        // Storage/assets can become available on an explicit retry.
        _initializing = null;
        await initialize();
      }
      if (error != null) return;
      busy = true;
      _notify();
      if (_store case final PersistentCoverageStore cache) {
        await cache.syncEvidenceFingerprints({
          for (final w in walks)
            if (w.status != 'recording') w.id: _fingerprint(w),
        });
      }
      final traces = {
        for (final w in walks)
          if (w.status != 'recording') w.id: w.fingerprint ?? _prepare(w).$2,
      };
      final boundsByWalk = _store is BatchCoverageStore
          ? await (_store as BatchCoverageStore).readWalkBoundsBatch(traces)
          : <int, List<double>>{};
      final loadedWalks = <int, SavedWalk>{};
      var loadedPoints = 0;
      Future<SavedWalk> fullWalk(SavedWalk summary) async {
        if (!summary.isSummary) return summary;
        final existing = loadedWalks.remove(summary.id);
        if (existing != null) {
          loadedWalks[summary.id] = existing;
          return existing;
        }
        final full = await loadWalk!(summary.id);
        // Bounded LRU shared by all cells in this synchronization.
        while (loadedWalks.isNotEmpty &&
            loadedPoints + full.points.length > 50000) {
          loadedPoints -= loadedWalks
              .remove(loadedWalks.keys.first)!
              .points
              .length;
        }
        if (full.points.length <= 50000) {
          loadedWalks[summary.id] = full;
          loadedPoints += full.points.length;
        }
        return full;
      }

      for (final area in networks) {
        if (_disposed || (request != null && request != _syncRequest)) return;
        final candidates = walks.where((w) {
          final bounds = boundsByWalk[w.id];
          return w.status != 'recording' &&
              (bounds == null ||
                  geographicBounds(
                    bounds,
                  ).inflate(.001).overlaps(geographicBounds(area.bbox)));
        }).toList();
        final candidateIds = candidates.map((w) => w.id).toSet();
        for (final w in walks.where((w) => !candidateIds.contains(w.id))) {
          _trails.exclude(w.id, area.version);
          _evidence.put(w.id, area.version, {}, {});
        }
        final cachedBatch = _store is BatchCoverageStore
            ? await (_store as BatchCoverageStore).readEvidenceBatch(
                area.coverageVersion,
                walks: candidates.map((w) => w.id).toList(),
              )
            : null;
        final pending = <(SavedWalk, String, String)>[];
        Future<void> flush() async {
          if (pending.isNotEmpty) {
            updatedRoutes = true;
            rematching = true;
            _notify();
          }
          // Do not send empty GPX to a parser which correctly rejects empty tracks.
          final nonempty = pending
              .where((p) => p.$1.points.isNotEmpty)
              .toList();
          final results = nonempty.isEmpty
              ? <MatchResult>[]
              : await _runMatch(
                  area.geojson,
                  nonempty.map((p) => p.$2).toList(),
                  confirmed: nonempty
                      .map((p) => p.$1.confirmedSections)
                      .toList(),
                );
          if (results.length != nonempty.length) {
            throw StateError('Matcher returned an incomplete batch');
          }
          final matched = <int, Set<int>>{};
          for (var i = 0; i < nonempty.length; i++) {
            final edges = results[i].walked.toSet();
            if (!area.edgeIds.containsAll(edges)) {
              throw StateError('Matcher returned unknown street ids');
            }
            edges.addAll(
              nonempty[i].$1.confirmedSections.where(area.edgeIds.contains),
            );
            matched[nonempty[i].$1.id] = edges;
            final supported = edges.difference(results[i].inferred.toSet())
              ..addAll(
                nonempty[i].$1.confirmedSections.where(area.edgeIds.contains),
              );
            _evidence.put(
              nonempty[i].$1.id,
              area.version,
              supported,
              results[i].inferred.toSet(),
            );
            _trails.put(nonempty[i].$1, area.version, results[i].unmatched);
            if (_store case final PersistentCoverageStore cache) {
              await cache.writeEvidence(
                nonempty[i].$1.id,
                area.coverageVersion,
                StoredMatch(
                  nonempty[i].$3,
                  supported,
                  results[i].inferred.toSet(),
                  results[i].unmatched,
                ),
              );
            }
          }
          for (final p in pending) {
            if (p.$1.points.isEmpty) {
              _trails.put(p.$1, area.version, const []);
              _evidence.put(p.$1.id, area.version, {}, {});
            }
            await _store.replaceWalkMatch(
              p.$1.id,
              area.coverageVersion,
              p.$3,
              matched[p.$1.id] ?? {},
            );
          }
          pending.clear();
        }

        for (final walk in candidates) {
          if (walk.status == 'recording') continue;
          final traceHash = walk.fingerprint ?? _prepare(walk).$2;
          final fingerprint = _fingerprint(walk);
          if (_store case final PersistentCoverageStore cache) {
            final cached = cachedBatch == null
                ? await cache.readEvidence(walk.id, area.coverageVersion)
                : cachedBatch[walk.id]?.$1;
            if (cached?.fingerprint == fingerprint) {
              final displayFingerprint = cachedBatch == null
                  ? await _store.matchFingerprint(walk.id, area.coverageVersion)
                  : cachedBatch[walk.id]?.$2;
              if (displayFingerprint != fingerprint) {
                await _store.replaceWalkMatch(
                  walk.id,
                  area.coverageVersion,
                  fingerprint,
                  {...cached!.supported, ...cached.estimated},
                );
              }
              _evidence.put(
                walk.id,
                area.version,
                cached!.supported,
                cached.estimated,
              );
              if (!_trails.contains(walk.id, area.version)) {
                final full = walk.isSummary && cached.unmatched.isNotEmpty
                    ? await fullWalk(walk)
                    : walk;
                _trails.put(full, area.version, cached.unmatched);
              }
              continue;
            }
            var bounds =
                boundsByWalk[walk.id] ??
                (_store is BatchCoverageStore
                    ? null
                    : await cache.readWalkBounds(walk.id, traceHash));
            if (bounds == null) {
              final full = await fullWalk(walk);
              if (full.points.isNotEmpty) {
                var r = Rect.fromLTWH(
                  full.points.first.longitude,
                  full.points.first.latitude,
                  0,
                  0,
                );
                for (final p in full.points) {
                  r = r.expandToInclude(
                    Rect.fromLTWH(p.longitude, p.latitude, 0, 0),
                  );
                }
                bounds = boundsList(r);
                boundsByWalk[walk.id] = bounds;
                await cache.writeWalkBounds(walk.id, traceHash, bounds);
              }
            }
            if (bounds != null &&
                !geographicBounds(
                  bounds,
                ).inflate(.001).overlaps(geographicBounds(area.bbox))) {
              _trails.exclude(walk.id, area.version);
              continue;
            }
          }
          if ((cachedBatch == null
                      ? await _store.matchFingerprint(
                          walk.id,
                          area.coverageVersion,
                        )
                      : cachedBatch[walk.id]?.$2) !=
                  fingerprint ||
              !_trails.contains(walk.id, area.version)) {
            final full = await fullWalk(walk);
            pending.add((full, _prepare(full).$1, fingerprint));
            if (pending.length >= 16) {
              await flush();
              if (_disposed || (request != null && request != _syncRequest)) {
                return;
              }
              await Future<void>.delayed(Duration.zero);
            }
          }
        }
        await flush();
      }
      _trails.retain(walks.map((w) => w.id).toSet());
      _evidence.retain(walks.map((w) => w.id).toSet());
      _savedTrailLines = _trails.lines(networks.map((n) => n.version).toList());
      counts = Map<int, int>.unmodifiable(
        await _store.readCombinedCounts(
          networks.map((map) => map.coverageVersion).toList(),
        ),
      );
      if (_liveWalk != null &&
          walks.any((w) => w.id == _liveWalk!.id && w.status != 'recording')) {
        _liveEpoch++;
        _liveWalk = null;
        _liveEdges = {};
        _liveEstimated = {};
        _liveUnmatched = {};
        _liveTrailLines = const [];
        liveError = null;
        _liveTimer?.cancel();
        _liveScheduled = false;
      }
      processedWalks = walks.where((w) => w.status != 'recording').length;
      error = null;
      if (updatedRoutes) routeUpdateRevision++;
    } catch (e) {
      error = e is CoverageFailure
          ? e
          : CoverageFailure('Could not update streets', e.toString());
    } finally {
      busy = false;
      rematching = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _liveTimer?.cancel();
    _liveWalk = null;
    unawaited(settled.whenComplete(_worker.close));
    super.dispose();
  }
}
