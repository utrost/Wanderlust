import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/foundation.dart';
import '../recording/saved_walk.dart';

const discoveryCellMetres = 32.0;
const discoveryRadiusMetres = 60.0;
Offset discoveryProject(double longitude, double latitude) {
  final lat = latitude.clamp(-85.0, 85.0) * math.pi / 180;
  return Offset(
    longitude * 111319.49079327358,
    6378137 * math.log(math.tan(math.pi / 4 + lat / 2)),
  );
}

Offset discoveryCoordinate(double x, double y) => Offset(
  x / 111319.49079327358,
  (2 * math.atan(math.exp(y / 6378137)) - math.pi / 2) * 180 / math.pi,
);

/// Only recorded fixes reveal terrain. No bridge across GPS gaps or segments,
/// no dependency on street matching, and no reveal from merely browsing a map.
Set<(int, int)> discoveryCells(SavedWalk walk) {
  final cells = <(int, int)>{};
  for (final p in walk.points) {
    if (!p.latitude.isFinite ||
        !p.longitude.isFinite ||
        p.latitude.abs() > 85 ||
        p.longitude.abs() > 180 ||
        !p.accuracy.isFinite ||
        p.accuracy < 0 ||
        p.accuracy > 50) {
      continue;
    }
    final point = discoveryProject(p.longitude, p.latitude);
    final radius = discoveryRadiusMetres / math.cos(p.latitude * math.pi / 180);
    final cx = (point.dx / discoveryCellMetres).floor();
    final cy = (point.dy / discoveryCellMetres).floor();
    final n = (radius / discoveryCellMetres).ceil();
    for (var x = cx - n; x <= cx + n; x++) {
      for (var y = cy - n; y <= cy + n; y++) {
        final middle = Offset(
          (x + .5) * discoveryCellMetres,
          (y + .5) * discoveryCellMetres,
        );
        if ((middle - point).distance <= radius) cells.add((x, y));
      }
    }
  }
  return cells;
}

/// Derived from the backup's existing GPS records; no separate fragile ledger.
/// Only one rebuild runs at once; changes while loading are coalesced and retried.
class ExplorationController extends ChangeNotifier {
  ExplorationController(this.loadWalk);
  final Future<SavedWalk> Function(int) loadWalk;
  final _saved = <String, Set<(int, int)>>{};
  Set<(int, int)> cells = const {};
  List<SavedWalk> _walks = const [];
  SavedWalk? _live;
  bool _enabled = false, _running = false, _again = false, _closed = false;
  String? error;
  String? _requestKey;
  String? _liveKey;
  int _liveCount = 0;
  final _liveCells = <(int, int)>{};
  Future<void> _pending = Future.value();
  Future<void> get settled => _pending;
  void update(bool enabled, List<SavedWalk> walks, SavedWalk? live) {
    final requestKey =
        '${walks.map(_key).join('|')}/${live == null ? '' : _key(live)}';
    final unchanged =
        _enabled == enabled && _requestKey == requestKey && error == null;
    _requestKey = requestKey;
    _enabled = enabled;
    _walks = walks;
    _live = live;
    if (!enabled || _closed || unchanged) return;
    if (_running) {
      _again = true;
      return;
    }
    _pending = _refresh();
  }

  String _liveIdentity(SavedWalk walk) =>
      '${walk.uid}/${walk.id}/${walk.startedAt}';

  String _key(SavedWalk walk) =>
      '${_liveIdentity(walk)}/${walk.pointCount}/'
      '${walk.fingerprint}/${walk.endedAt}/${walk.status}';
  Future<void> _refresh() async {
    _running = true;
    try {
      do {
        _again = false;
        final walks = List<SavedWalk>.of(_walks), live = _live;
        final keep = walks.map(_key).toSet();
        _saved.removeWhere((key, _) => !keep.contains(key));
        for (final summary in walks) {
          if (_closed || !_enabled) return;
          final key = _key(summary);
          if (!_saved.containsKey(key)) {
            final walk = summary.isSummary
                ? await loadWalk(summary.id)
                : summary;
            _saved[key] = await compute(discoveryCells, walk);
          }
        }
        final result = {for (final part in _saved.values) ...part};
        if (live == null ||
            _liveKey != _liveIdentity(live) ||
            live.points.length < _liveCount) {
          _liveCells.clear();
          _liveCount = 0;
          _liveKey = live == null ? null : _liveIdentity(live);
        }
        if (live != null) {
          if (live.points.length > _liveCount) {
            final additions = SavedWalk(
              live.id,
              live.startedAt,
              live.endedAt,
              live.status,
              live.points.sublist(_liveCount),
            );
            _liveCells.addAll(await compute(discoveryCells, additions));
            _liveCount = live.points.length;
          }
          result.addAll(_liveCells);
        }
        if (_closed || !_enabled) return;
        final hadError = error != null;
        error = null;
        if (hadError || !setEquals(result, cells)) {
          cells = Set.unmodifiable(result);
          notifyListeners();
        }
      } while (_again);
    } catch (_) {
      if (!_closed) {
        error =
            'Exploration could not be loaded. Turn fog of war off and on to retry.';
        notifyListeners();
      }
    } finally {
      _running = false;
    }
  }

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }
}
