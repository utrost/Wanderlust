import 'package:geolocator/geolocator.dart';

/// Bounded, coordinate-free acquisition metrics. Never changes recorded fixes.
class GpsDiagnostics {
  GpsDiagnostics({
    required this.requestedIntervalSeconds,
    required this.startedAt,
  });
  final int requestedIntervalSeconds;
  final DateTime startedAt;
  DateTime? _arrival, _fix;
  int fixes = 0, invalid = 0, stale = 0, future = 0, restarts = 0;
  double _accuracySum = 0, _accuracyMax = 0, _ageSum = 0, _ageMax = 0;
  double _deliverySum = 0, _deliveryMax = 0, _fixSum = 0, _fixMax = 0;
  int _deliveryCount = 0, _fixCount = 0;
  int? _firstFreshMs;
  bool get hasFreshFix => _firstFreshMs != null;

  void add(Position p, DateTime receivedAt) {
    if (!p.latitude.isFinite ||
        !p.longitude.isFinite ||
        p.latitude.abs() > 90 ||
        p.longitude.abs() > 180 ||
        !p.accuracy.isFinite ||
        p.accuracy < 0) {
      invalid++;
      return;
    }
    fixes++;
    _accuracySum += p.accuracy;
    if (p.accuracy > _accuracyMax) _accuracyMax = p.accuracy;
    final age = receivedAt.difference(p.timestamp).inMilliseconds;
    if (age > 30000) stale++;
    if (age < -5000) future++;
    if (age >= -5000 && age <= 30000) {
      _firstFreshMs ??= receivedAt
          .difference(startedAt)
          .inMilliseconds
          .clamp(0, 1 << 53);
    }
    final nonNegativeAge = age.clamp(0, 1 << 53).toDouble();
    _ageSum += nonNegativeAge;
    if (nonNegativeAge > _ageMax) _ageMax = nonNegativeAge;
    if (_arrival != null) {
      final ms = receivedAt.difference(_arrival!).inMilliseconds.toDouble();
      if (ms >= 0) {
        _deliveryCount++;
        _deliverySum += ms;
        if (ms > _deliveryMax) _deliveryMax = ms;
      }
    }
    if (_fix != null) {
      final ms = p.timestamp.difference(_fix!).inMilliseconds.toDouble();
      if (ms > 0) {
        _fixCount++;
        _fixSum += ms;
        if (ms > _fixMax) _fixMax = ms;
      }
    }
    _arrival = receivedAt;
    _fix = p.timestamp;
  }

  Map<String, Object?> snapshot() => {
    'version': 1,
    'requestedIntervalSeconds': requestedIntervalSeconds,
    'receivedFixes': fixes,
    'invalidFixes': invalid,
    'staleFixes': stale,
    'futureFixes': future,
    'streamRestarts': restarts,
    'firstFreshFixMs': _firstFreshMs,
    'meanAccuracyM': fixes == 0 ? null : _accuracySum / fixes,
    'maxAccuracyM': fixes == 0 ? null : _accuracyMax,
    'meanFixAgeMs': fixes == 0 ? null : _ageSum / fixes,
    'maxFixAgeMs': fixes == 0 ? null : _ageMax,
    'meanDeliveryIntervalMs': _deliveryCount == 0
        ? null
        : _deliverySum / _deliveryCount,
    'maxDeliveryIntervalMs': _deliveryCount == 0 ? null : _deliveryMax,
    'meanFixIntervalMs': _fixCount == 0 ? null : _fixSum / _fixCount,
    'maxFixIntervalMs': _fixCount == 0 ? null : _fixMax,
  };
}

abstract interface class GpsDiagnosticsStore {
  Future<void> saveGpsDiagnostics(int walkId, Map<String, Object?> metrics);
}

/// Ignore unknown fields and bound imported diagnostic metadata.
Map<String, Object?> readGpsDiagnostics(Object? value) {
  if (value is! Map) return const {};
  const numbers = {
    'version',
    'requestedIntervalSeconds',
    'receivedFixes',
    'invalidFixes',
    'staleFixes',
    'futureFixes',
    'streamRestarts',
    'firstFreshFixMs',
    'meanAccuracyM',
    'maxAccuracyM',
    'meanFixAgeMs',
    'maxFixAgeMs',
    'meanDeliveryIntervalMs',
    'maxDeliveryIntervalMs',
    'meanFixIntervalMs',
    'maxFixIntervalMs',
  };
  return Map.unmodifiable({
    for (final key in numbers)
      if (value[key] is num &&
          (value[key] as num).isFinite &&
          (value[key] as num) >= 0)
        key: value[key],
    for (final key in ['lastReportedProvider', 'permissionAccuracy'])
      if (value[key] is String && (value[key] as String).length <= 80)
        key: value[key],
  });
}
