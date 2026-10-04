import 'dart:async';
import 'package:geolocator/geolocator.dart';

/// A bounded foreground-only stream. No fixes are written into an activity.
class LocationWarmup {
  LocationWarmup({
    required this.open,
    required this.onFix,
    DateTime Function()? now,
    this.duration = const Duration(seconds: 20),
  }) : now = now ?? DateTime.now;
  final Stream<Position> Function() open;
  final void Function(Position) onFix;
  final DateTime Function() now;
  final Duration duration;
  StreamSubscription<Position>? _subscription;
  Timer? _timer;
  final _done = Completer<void>();
  bool _closed = false, _started = false;
  Future<void>? _closing;
  DateTime? _lastGood;
  Future<void> start() {
    if (_closed || _started) return _done.future;
    _started = true;
    _timer = Timer(duration, () {
      unawaited(close());
    });
    try {
      _subscription = open().listen(
        (p) {
          if (_closed ||
              !p.latitude.isFinite ||
              !p.longitude.isFinite ||
              p.latitude.abs() > 90 ||
              p.longitude.abs() > 180 ||
              !p.accuracy.isFinite ||
              p.accuracy < 0) {
            return;
          }
          final age = now().difference(p.timestamp);
          if (age > const Duration(seconds: 10) ||
              age < const Duration(seconds: -5)) {
            return;
          }
          onFix(p);
          if (p.accuracy <= 15) {
            final previous = _lastGood;
            _lastGood = p.timestamp;
            if (previous != null && p.timestamp.isAfter(previous)) {
              unawaited(close());
            }
          } else {
            _lastGood = null;
          }
        },
        onError: (Object e, StackTrace st) {
          if (!_done.isCompleted) _done.completeError(e, st);
          unawaited(close());
        },
        onDone: () {
          unawaited(close());
        },
      );
    } catch (e, st) {
      _done.completeError(e, st);
      unawaited(close());
    }
    return _done.future;
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    try {
      await _subscription?.cancel().timeout(const Duration(seconds: 2));
    } catch (_) {
      // Optional warm-up cleanup must not block the recording controls.
    } finally {
      if (!_done.isCompleted) _done.complete();
    }
  }
}
