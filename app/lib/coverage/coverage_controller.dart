import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../data/area_network.dart';
import '../geo/geo_core_ffi.dart';
import '../geo/matching_session.dart';
import '../geo/matching_worker.dart';
import '../recording/saved_walk.dart';
import '../transfer/walk_codec.dart';
import 'coverage_store.dart';
import 'unmatched_trails.dart';

// Bump when matching rules change: old saved traces are then reprocessed once.
const matchingRevision = 'sections-15m-v6';
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
    this.loadWalk,
    this.liveInterval = const Duration(seconds: 2),
  }) : _store = store,
       _loadNetwork = loadNetwork ?? (() async => null),
       _match = match;
  final Future<SavedWalk> Function(int)? loadWalk;
  final Duration liveInterval;
  final Future<List<String>> Function()? loadSavedNetworks;
  SavedWalk? _liveWalk;
  Set<int> _liveEdges = {};
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
  int _liveMatchedPoints = 0;
  int _liveEpoch = 0;
  String? liveError;
  Map<int, int>? _displayCounts;
  Map<int, int> get displayCounts => _displayCounts ??= Map.unmodifiable({
    ...counts,
    for (final id in _liveEdges) id: (counts[id] ?? 0) + 1,
  });

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
      _liveMatchedPoints = 0;
      _liveUnmatched = {};
      _liveTrailLines = const [];
    }
    _liveWalk = walk;
    _scheduleLive();
  }

  /// Hidden screens need no live rendering work. On return, match all fixes
  /// since the last successful preview, with overlap for consecutive evidence.
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
          // Usually an 80-fix overlap plus new points. After time in the pocket,
          // include ALL unprocessed fixes rather than dropping the hidden walk.
          final tailStart = _liveMatchedPoints > 80
              ? _liveMatchedPoints - 80
              : 0;
          final tail = walk.points.skip(tailStart).toList();
          final gpx = WalkCodec.exportGpx(
            SavedWalk(
              walk.id,
              walk.startedAt,
              null,
              'recording',
              tail,
              segmentStarts: [
                for (final i in walk.segmentStarts)
                  if (i > tailStart) i - tailStart,
              ],
              untimed: [
                for (final i in walk.untimed)
                  if (i >= tailStart) i - tailStart,
              ],
            ),
          );
          final edges = <int>{};
          final unmatchedByArea = <Set<int>>[];
          for (final area in networks) {
            final result = await _runMatch(area.geojson, [gpx]);
            if (result.length != 1 ||
                !area.edgeIds.containsAll(result.single.walked)) {
              throw StateError('Invalid live coverage result');
            }
            edges.addAll(result.single.walked);
            if (result.single.unmatched.any(
              (i) => i <= 0 || i >= tail.length,
            )) {
              throw StateError('Invalid live GPS trail result');
            }
            unmatchedByArea.add(
              result.single.unmatched.map((i) => i + tailStart).toSet(),
            );
          }
          if (!_disposed && epoch == _liveEpoch && _liveWalk?.id == walk.id) {
            _liveEdges = {..._liveEdges, ...edges};
            _liveUnmatched.removeWhere((i) => i > tailStart);
            _liveUnmatched.addAll(UnmatchedTrails.common(unmatchedByArea));
            _liveTrailLines = UnmatchedTrails.fromIndices(walk, _liveUnmatched);
            _liveMatchedPoints = walk.points.length;
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
    _savedTrailLines = const [];
    _liveUnmatched = {};
    _liveTrailLines = const [];
    _liveEpoch++;
    _liveMatchedPoints = 0;
    final visible = {for (final map in networks) ...map.edgeIds};
    _liveEdges = _liveEdges.intersection(visible);
    _scheduleLive();
  }

  List<AreaNetwork> networks = const [];
  final CoverageStore _store;
  final Future<String?> Function() _loadNetwork;
  final MatchBatch? _match;
  final MatchingWorker _worker = MatchingWorker();
  bool _fillSmallGaps = false;

  Future<List<MatchResult>> _runMatch(String network, List<String> walks) =>
      _match?.call(network, walks) ??
      _worker.match(network, walks, fillSmallGaps: _fillSmallGaps);

  /// Serialize policy changes with matching. Invalidate any in-flight preview,
  /// then rebuild saved memberships and the whole current walk under the policy.
  Future<void> setFillSmallGaps(bool enabled, List<SavedWalk> walks) {
    if (_disposed) return Future.value();
    _liveEpoch++;
    final snapshot = List<SavedWalk>.of(walks);
    _queue = _queue.then((_) async {
      if (_disposed || _fillSmallGaps == enabled) return;
      _fillSmallGaps = enabled;
      _trails.clear();
      _savedTrailLines = const [];
      _liveUnmatched = {};
      _liveTrailLines = const [];
      _liveEdges = {};
      _liveMatchedPoints = 0;
      await _synchronize(snapshot);
      _scheduleLive();
    });
    return _queue;
  }

  AreaNetwork? network;
  Map<int, int> counts = const {};
  bool busy = false;
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
      if (selected != null) selected.version: selected,
    };
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
  }

  Future<void> refreshMaps() async {
    _queue = _queue.then((_) async {
      if (_disposed) return;
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

  final _prepared = Expando<(String, String)>('prepared traces');
  (String, String) _prepare(SavedWalk walk) {
    return _prepared[walk] ??= (() {
      final gpx = WalkCodec.exportGpx(walk);
      return (gpx, sha256.convert(utf8.encode(gpx)).toString());
    })();
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
      if (error != null) return;
      for (final area in networks) {
        final pending = <(SavedWalk, String, String)>[];
        for (final walk in walks) {
          if (walk.status == 'recording') continue;
          final traceHash = walk.fingerprint ?? _prepare(walk).$2;
          final fingerprint =
              '$matchingRevision/${_fillSmallGaps ? 'fill-v1' : 'direct'}/$traceHash';
          if (await _store.matchFingerprint(walk.id, area.coverageVersion) !=
                  fingerprint ||
              !_trails.contains(walk.id, area.version)) {
            final full = walk.isSummary ? await loadWalk!(walk.id) : walk;
            pending.add((full, _prepare(full).$1, fingerprint));
          }
        }
        // Do not send empty GPX to a parser which correctly rejects empty tracks.
        final nonempty = pending.where((p) => p.$1.points.isNotEmpty).toList();
        final results = nonempty.isEmpty
            ? <MatchResult>[]
            : await _runMatch(area.geojson, nonempty.map((p) => p.$2).toList());
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
          _trails.put(nonempty[i].$1, area.version, results[i].unmatched);
        }
        for (final p in pending) {
          if (p.$1.points.isEmpty) _trails.put(p.$1, area.version, const []);
          await _store.replaceWalkMatch(
            p.$1.id,
            area.coverageVersion,
            p.$3,
            matched[p.$1.id] ?? {},
          );
        }
      }
      _trails.retain(walks.map((w) => w.id).toSet());
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
        _liveUnmatched = {};
        _liveTrailLines = const [];
        liveError = null;
        _liveTimer?.cancel();
        _liveScheduled = false;
      }
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
    _liveTimer?.cancel();
    _liveWalk = null;
    unawaited(settled.whenComplete(_worker.close));
    super.dispose();
  }
}
