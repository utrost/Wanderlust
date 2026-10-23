import 'dart:async';
import 'dart:convert';
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
  bool _closed = false, _running = false, _again = false;
  Future<void> _pending = Future.value();
  Future<void> get settled => _pending;
  String? error;
  int remaining = 0;
  void schedule() {
    if (_running) {
      _again = true;
      return;
    }
    if (_closed || _timer != null) return;
    _timer = Timer(const Duration(milliseconds: 600), () {
      _timer = null;
      if (_closed || !canRun() || active.loading || active.gesturing) return;
      _running = true;
      _pending = _run()
          .catchError((Object e) {
            error = 'Saved-area analysis will retry when the map is idle.';
          })
          .whenComplete(() {
            _running = false;
            if (_again) {
              _again = false;
              schedule();
            }
          });
    });
  }

  Future<void> _run() async {
    final grouped = <String, List<CellSource>>{};
    for (final row in await active.store.listCells()) {
      (grouped[row.cell] ??= []).add(row);
    }
    if (grouped.isEmpty) return;
    final stamps = await cache.analysisStamps();
    final history = List<SavedWalk>.of(walks());
    final prefs = preferences();
    final historyKey = sha256
        .convert(
          utf8.encode(
            jsonEncode([
              matchingRevision,
              blockRevision,
              prefs.fillSmallGaps,
              prefs.autoFillGaps,
              prefs.completeBlocks,
              for (final w in history)
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
    remaining = grouped.length;
    for (final entry in grouped.entries) {
      if (_closed || !canRun() || active.loading || active.gesturing) return;
      final sources = entry.value
        ..sort((a, b) => a.version.compareTo(b.version));
      final stamp =
          '$historyKey/${sources.map((s) => '${s.version}:${s.digest}:${s.bytes}:${s.sections}').join('|')}';
      if (stamps[entry.key] == stamp) {
        remaining--;
        continue;
      }
      final bytes = sources.fold<int>(0, (n, s) => n + s.bytes);
      final sections = sources.fold<int>(0, (n, s) => n + s.sections);
      if (!active.reserveProcessing(bytes, sections)) continue;
      try {
        final source = await active.store.readCell(entry.key);
        if (source == null) continue;
        final map = await compute(AreaNetwork.parse, source);
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
            final topology =
                await cache.readTopology(key) ??
                await compute<List<AreaNetwork>, BlockTopology>(
                  buildBlockTopology,
                  [map],
                );
            await cache.writeTopology(key, topology);
            final support = coverage.supportedSections;
            await cache.saveBlocks(topology.blocks, {
              for (final b in topology.blocks) b.id: blockProgress(b, support),
            }, map.sourceVersions);
          }
          await cache.reconcileBlocks();
          await cache.saveAnalysisStamp(entry.key, stamp);
          await onUpdated();
        } finally {
          coverage.dispose();
          await coverage.settled;
        }
      } finally {
        active.releaseProcessing();
      }
      remaining--;
      // Yield between cells. Never hold a worldwide graph or GPS collection.
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    error = null;
  }

  void dispose() {
    _closed = true;
    _timer?.cancel();
  }
}
