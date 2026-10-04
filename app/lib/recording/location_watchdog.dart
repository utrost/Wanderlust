import 'dart:async';
import 'package:geolocator/geolocator.dart';

/// Keeps one location subscription alive, with bounded retries on stale/error
/// streams. Does not end the journal or manufacture GPS fixes.
class LocationWatchdog {
  LocationWatchdog({
    required this.open,
    required this.onPoint,
    required this.onStale,
    required this.now,
    this.onRestart,
  });
  final Stream<Position> Function() open;
  final void Function(Position) onPoint;
  final void Function(bool) onStale;
  final DateTime Function() now;
  final void Function()? onRestart;
  StreamSubscription<Position>? _subscription;
  Timer? _timer;
  DateTime? _lastFix, _lastAttempt;
  bool _closed = false, _restarting = false;
  int _generation = 0;
  Future<void>? _pending;

  void start() {
    _lastFix = now();
    _connect();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => check());
  }

  void _connect() {
    final generation = ++_generation;
    _lastAttempt = now();
    try {
      _subscription = open().listen(
        (p) {
          if (_closed || generation != _generation) return;
          // Cached or malformed fixes must not silence a stalled-stream warning.
          if (p.latitude.isFinite &&
              p.longitude.isFinite &&
              p.latitude.abs() <= 90 &&
              p.longitude.abs() <= 180 &&
              p.accuracy.isFinite &&
              p.accuracy >= 0 &&
              !p.timestamp.isAfter(now().add(const Duration(seconds: 5))) &&
              now().difference(p.timestamp) <= const Duration(seconds: 30)) {
            _lastFix = now();
            onStale(false);
          }
          onPoint(p);
        },
        onError: (Object _) {
          if (!_closed && generation == _generation) {
            _lastFix = null;
            onStale(true);
          }
        },
        onDone: () {
          if (!_closed && generation == _generation) {
            _lastFix = null;
            onStale(true);
          }
        },
      );
    } catch (_) {
      _lastFix = null;
      onStale(true);
    }
  }

  void check() {
    if (_closed) return;
    final stale =
        _lastFix == null ||
        now().difference(_lastFix!) >= const Duration(seconds: 45);
    onStale(stale);
    if (stale &&
        !_restarting &&
        now().difference(_lastAttempt!) >= const Duration(seconds: 60)) {
      _pending = _restart();
    }
  }

  Future<void> _restart() async {
    _restarting = true;
    onRestart?.call();
    _lastAttempt = now();
    ++_generation;
    try {
      await _subscription?.cancel();
      _subscription = null;
      if (!_closed) _connect();
    } catch (_) {
      if (!_closed) onStale(true);
    } finally {
      _restarting = false;
    }
  }

  Future<void> close() async {
    _closed = true;
    ++_generation;
    _timer?.cancel();
    await _pending;
    await _subscription?.cancel();
    _subscription = null;
  }
}
