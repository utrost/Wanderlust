import 'journey_motion.dart';
import 'package:geolocator/geolocator.dart';

/// Conservative display distance. Raw fixes are journalled independently.
/// Uncertain readings and outages break continuity instead of inventing travel.
class WalkDistance {
  WalkDistance({this.maxSpeed = 3, this.automatic = false});
  final bool automatic;
  Position? _prior, _previous;
  final double maxSpeed;
  Position? _anchor;
  DateTime? _latest;
  double meters = 0;

  void add(Position point) {
    if (_latest != null && !point.timestamp.isAfter(_latest!)) return;
    _latest = point.timestamp;
    if (!point.accuracy.isFinite || point.accuracy < 0 || point.accuracy > 25) {
      _anchor = null;
      return;
    }
    final limit = automatic && _previous != null
        ? journeySpeedLimit(_prior, _previous!, point)
        : maxSpeed;
    _prior = _previous;
    _previous = point;
    final previous = _anchor;
    if (previous == null) {
      _anchor = point;
      return;
    }
    final seconds =
        point.timestamp.difference(previous.timestamp).inMilliseconds / 1000;
    if (seconds > 30) {
      _anchor = point;
      return;
    }
    final distance = Geolocator.distanceBetween(
      previous.latitude,
      previous.longitude,
      point.latitude,
      point.longitude,
    );
    // Leave the good anchor in place after a spike, so its return is not counted.
    if (distance / seconds > limit) return;
    // Accumulate real progress from the last anchor without adding sub-metre jitter.
    if (distance < 2) return;
    meters += distance;
    _anchor = point;
  }
}
