import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import '../blocks/block_geometry.dart';
import '../blocks/block_progress.dart';
import '../blocks/block_store.dart';
import '../coverage/coverage_controller.dart';
import '../coverage/coverage_store.dart';
import '../data/area_network.dart';
import '../recording/saved_walk.dart';
import '../settings/walk_preferences.dart';
import 'active_maps.dart';
import 'map_cells.dart';

/// Incremental historical maintenance. At most one buffered cell is processed;
/// recording, gestures and active-window loading always take precedence.
class LibraryAnalysis {
  LibraryAnalysis({
    required this.active,
    required this.store,
    required this.cache,
    required this.loadWalk,
    required this.walks,
    required this.preferences,
    required this.canRun,
    required this.onUpdated,
  });
  final ActiveMaps active;
  final CoverageStore store;
  final BlockCacheStore cache;
  final Future<SavedWalk> Function(int) loadWalk;
  final List<SavedWalk> Function() walks;
  final WalkPreferences Function() preferences;
  final bool Function() canRun;
  final Future<void> Function() onUpdated;
  Timer? _timer;
  bool _waitingRetry = false;
  bool _closed = false, _running = false, _again = false;
  Future<void> _pending = Future.value();
  Future<void> get settled => _pending;
  String? error;
  int remaining = 0;
  Object? lastFailure;
  int _retrySeconds = 5;
  void _retryLater({bool backoff = true}) {
    if (_closed || _timer != null) return;
    _waitingRetry = true;
    _timer = Timer(Duration(seconds: _retrySeconds), () {
      _timer = null;
      _waitingRetry = false;
      schedule();
    });
    if (backoff) _retrySeconds = (_retrySeconds * 2).clamp(5, 60);
  }

  void schedule() {
    if (_running) {
      _again = true;
      return;
    }
    if (_closed || (_timer != null && !_waitingRetry)) return;
    _timer?.cancel();
    _waitingRetry = false;
    _timer = Timer(const Duration(milliseconds: 600), () {
      _timer = null;
      if (_closed) return;
      if (_again || !canRun() || active.loading || active.gesturing) {
        // A save can keep coverage busy beyond the debounce. Do not lose that
        // request just because no further GPS/UI event arrives afterwards.
        _retryLater(backoff: false);
        return;
      }
      _running = true;
      _pending = _run()
          .catchError((Object e) {
            lastFailure = e;
            error = 'Saved-area analysis will retry when the map is idle.';
          })
          .whenComplete(() {
            _running = false;
            if (_again) {
              _again = false;
              schedule();
            } else if (remaining > 0 || error != null) {
              _retryLater();
            }
          });
    });
  }

  Future<void> _run() async {
    final grouped = <String, List<CellSource>>{};
    for (final row in await active.store.listCells()) {
      (grouped[row.cell] ??= []).add(row);
    }
    remaining = grouped.length;
    error = null;
    lastFailure = null;
    await onUpdated();
    if (grouped.isEmpty) return;
    final stamps = await cache.analysisStamps();
    final history = List<SavedWalk>.of(walks());
    final prefs = preferences();
    final traces = {
      for (final w in history)
        if (w.fingerprint != null) w.id: w.fingerprint!,
    };
    final bounds = store is BatchCoverageStore
        ? await (store as BatchCoverageStore).readWalkBoundsBatch(traces)
        : <int, List<double>>{};
    // Backfill only missing metadata once, rather than once for every map cell.
    for (final w in history) {
      if (_closed || !canRun() || active.gesturing) return;
      if (bounds.containsKey(w.id) || w.status == 'recording') continue;
      if (store case final PersistentCoverageStore persistent) {
        final old = w.fingerprint == null
            ? null
            : await persistent.readWalkBounds(w.id, w.fingerprint!);
        if (old != null) {
          bounds[w.id] = old;
          continue;
        }
        final full = w.isSummary ? await loadWalk(w.id) : w;
        if (full.points.isEmpty) continue;
        var r = Rect.fromLTWH(
          full.points.first.longitude,
          full.points.first.latitude,
          0,
          0,
        );
        for (final p in full.points) {
          r = r.expandToInclude(Rect.fromLTWH(p.longitude, p.latitude, 0, 0));
        }
        bounds[w.id] = boundsList(r);
        if (w.fingerprint != null) {
          await persistent.writeWalkBounds(w.id, w.fingerprint!, bounds[w.id]!);
        }
      }
    }
    String historyKeyFor(String cell) {
      final window = MapCell.parse(cell).bounds.inflate(.001);
      return sha256
          .convert(
            utf8.encode(
              jsonEncode([
                matchingRevision,
                blockRevision,
                prefs.fillSmallGaps,
                prefs.autoFillGaps,
                prefs.completeBlocks,
                'local-history-v1',
                for (final w in history)
                  if (w.status != 'recording' &&
                      (bounds[w.id] == null ||
                          geographicBounds(bounds[w.id]!).overlaps(window)))
                    [
                      w.id,
                      w.fingerprint,
                      w.activity.name,
                      w.confirmedSections,
                      w.storedPointCount,
                    ],
              ]),
            ),
          )
          .toString();
    }

    remaining = grouped.length;
    for (final entry in grouped.entries) {
      if (_closed ||
          _again ||
          !canRun() ||
          active.loading ||
          active.gesturing) {
        return;
      }
      final sources = entry.value
        ..sort((a, b) => a.version.compareTo(b.version));
      final stamp =
          '$blockRevision/${prefs.completeBlocks}/${historyKeyFor(entry.key)}/${sources.map((s) => '${s.version}:${s.digest}:${s.bytes}:${s.sections}').join('|')}';
      if (stamps[entry.key] == stamp) {
        remaining--;
        continue;
      }
      final loaded = active.loadedCell(entry.key, sources);
      final bytes = loaded == null
          ? sources.fold<int>(0, (n, s) => n + s.bytes)
          : 0;
      final sections = loaded == null
          ? sources.fold<int>(0, (n, s) => n + s.sections)
          : 0;
      if (!active.reserveProcessing(bytes, sections)) continue;
      try {
        final AreaNetwork map;
        if (loaded != null) {
          map = loaded;
        } else {
          final source = await active.store.readCell(entry.key);
          if (source == null) continue;
          map = await compute(AreaNetwork.parse, source);
        }
        if (_closed || !canRun() || active.gesturing) return;
        final coverage = CoverageController(
          store: store,
          loadWalk: loadWalk,
          loadActiveNetworks: () async => [map],
        );
        try {
          await coverage.setFillSmallGaps(
            prefs.fillSmallGaps,
            history,
            autoFillGaps: prefs.autoFillGaps,
          );
          await coverage.synchronize(history);
          if (coverage.error != null) {
            throw StateError(coverage.error.toString());
          }
          if (_closed || !canRun() || active.gesturing) return;
          if (prefs.completeBlocks) {
            final key = topologyCacheKey([map]);
            final cached = await cache.readTopology(key);
            final topology =
                cached ??
                await compute<List<AreaNetwork>, BlockTopology>(
                  buildBlockTopology,
                  [map],
                );
            if (cached == null) await cache.writeTopology(key, topology);
            final support = coverage.supportedSections;
            final progress = await compute(blockProgressBatch, (
              topology.blocks,
              support,
            ));
            await cache.saveBlocks(
              topology.blocks,
              progress,
              map.sourceVersions,
            );
          }
          await cache.reconcileBlocks();
          await cache.saveAnalysisStamp(entry.key, stamp);
          remaining--;
          await onUpdated();
        } finally {
          coverage.dispose();
          await coverage.settled;
        }
      } catch (e) {
        // A failed cell has no completion stamp and remains eligible for retry.
        // Continue other cells so a transient lock cannot stall the library.
        lastFailure = e;
        error = 'Saved-area analysis will retry when the map is idle.';
      } finally {
        active.releaseProcessing();
      }
      // Yield between cells. Never hold a worldwide graph or GPS collection.
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (remaining == 0) {
      error = null;
      lastFailure = null;
      _retrySeconds = 5;
    }
    await onUpdated();
  }

  void dispose() {
    _closed = true;
    _timer?.cancel();
  }
}
