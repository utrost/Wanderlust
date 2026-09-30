import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../recording/walk_recorder.dart';
import 'memory.dart';

class MemoryLocationError implements Exception {
  const MemoryLocationError(this.message);
  final String message;
}

/// Wait for a usable reading rather than rejecting the provider's first cached
/// fix. Own only our subscription: cancelling it must not stop a recorded walk.
Future<Position> locateMemory({
  Position? Function()? current,
  Future<RecorderError?> Function()? authorize,
  Stream<Position> Function()? positions,
  DateTime Function()? now,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final clock = now ?? DateTime.now;
  final latest = current?.call();
  if (latest != null && WalkMemory.usableFix(latest, clock())) return latest;
  try {
    final permission =
        await (authorize ??
            DeviceLocationSource(forRecording: false).authorize)();
    if (permission == RecorderError.locationServiceDisabled) {
      throw const MemoryLocationError(
        'Location is switched off. Turn on GPS in your phone settings, then retry.',
      );
    }
    if (permission == RecorderError.permissionDenied) {
      throw const MemoryLocationError(
        'Location permission was denied. Allow precise location for Wanderlust in Android settings, then retry.',
      );
    }
    if (permission != null) {
      throw const MemoryLocationError(
        'Could not access GPS. Check location settings and retry.',
      );
    }
    final source = positions ?? () => _independentPositions(timeout);
    final result = Completer<Position>();
    Position? rejected;
    final timer = Timer(timeout, () {
      if (result.isCompleted) return;
      final p = rejected;
      final detail = p != null && p.accuracy.isFinite && p.accuracy > 50
          ? 'GPS accuracy is ±${p.accuracy.round()} m; a pin needs 50 m or better.'
          : 'No recent GPS fix arrived.';
      result.completeError(
        MemoryLocationError(
          '$detail Try again outdoors. You can still save your note or photo without a pin.',
        ),
      );
    });
    StreamSubscription<Position>? subscription;
    try {
      subscription = source().listen(
        (p) {
          if (result.isCompleted) return;
          if (WalkMemory.usableFix(p, clock())) {
            result.complete(p);
          } else {
            rejected = p;
          }
        },
        onError: (Object e) {
          if (!result.isCompleted) result.completeError(e);
        },
        onDone: () {
          if (!result.isCompleted) {
            result.completeError(
              const MemoryLocationError(
                'GPS stopped before a usable fix arrived. Please retry.',
              ),
            );
          }
        },
      );
      return await result.future;
    } finally {
      timer.cancel();
      await subscription?.cancel();
    }
  } on MemoryLocationError {
    rethrow;
  } on LocationServiceDisabledException {
    throw const MemoryLocationError(
      'Location is switched off. Turn on GPS in your phone settings, then retry.',
    );
  } on PermissionDeniedException {
    throw const MemoryLocationError(
      'Location permission was denied. Allow precise location for Wanderlust in Android settings, then retry.',
    );
  } on TimeoutException {
    throw const MemoryLocationError(
      'GPS timed out. Try again outdoors; your note or photo can be saved without a pin.',
    );
  } catch (_) {
    throw const MemoryLocationError(
      'Could not read your location. Check GPS and precise-location permission, then retry.',
    );
  }
}

/// Geolocator shares getPositionStream across listeners, including its initial
/// distance filter. A stationary walker therefore needs a separate native
/// request. Each request has its own ID and timeout and cannot cancel recording.
Stream<Position> _independentPositions(Duration timeout) async* {
  final watch = Stopwatch()..start();
  while (watch.elapsed < timeout) {
    final remaining = timeout - watch.elapsed;
    yield await Geolocator.getCurrentPosition(
      locationSettings: defaultTargetPlatform == TargetPlatform.android
          ? AndroidSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 0,
              intervalDuration: const Duration(seconds: 2),
              forceLocationManager: true,
              timeLimit: remaining,
            )
          : LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 0,
              timeLimit: remaining,
            ),
    );
  }
}
