import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Why a walk couldn't start.
enum RecorderError { locationServiceDisabled, permissionDenied }

/// The minimal recording state (ROADMAP Phase 1): capture a walk as a GPS trace
/// while the app is open, exposing live duration / distance / point count. The
/// raw trace is what the geo-core matches into street counts once an area's
/// street network is loaded; here it records and can export the walk as GPX.
///
/// Foreground only for now — background recording (screen off) is the separate,
/// larger Phase-1 risk called out in the architecture docs.
class WalkRecorder extends ChangeNotifier {
  final List<Position> _points = [];
  StreamSubscription<Position>? _sub;
  Timer? _ticker;
  DateTime? _startedAt;

  /// Set when [start] fails, for the UI to explain why.
  RecorderError? lastError;

  bool get isRecording => _sub != null;
  int get pointCount => _points.length;

  Duration get elapsed =>
      _startedAt == null ? Duration.zero : DateTime.now().difference(_startedAt!);

  double get distanceMeters {
    var total = 0.0;
    for (var i = 1; i < _points.length; i++) {
      total += Geolocator.distanceBetween(
        _points[i - 1].latitude,
        _points[i - 1].longitude,
        _points[i].latitude,
        _points[i].longitude,
      );
    }
    return total;
  }

  /// Begin recording. Returns false (and sets [lastError]) if location is off or
  /// permission is refused.
  Future<bool> start() async {
    if (isRecording) return true;
    lastError = null;

    if (!await Geolocator.isLocationServiceEnabled()) {
      lastError = RecorderError.locationServiceDisabled;
      notifyListeners();
      return false;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      lastError = RecorderError.permissionDenied;
      notifyListeners();
      return false;
    }

    _points.clear();
    _startedAt = DateTime.now();
    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((p) {
      _points.add(p);
      notifyListeners();
    });
    // Tick so elapsed time updates even between location fixes.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => notifyListeners());
    notifyListeners();
    return true;
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _ticker?.cancel();
    _ticker = null;
    notifyListeners();
  }

  /// The recorded trace as GPX — feeds the geo-core matcher and export.
  String toGpx() {
    final b = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<gpx version="1.1" creator="wanderlust">')
      ..writeln('  <trk><trkseg>');
    for (final p in _points) {
      b.writeln('    <trkpt lat="${p.latitude}" lon="${p.longitude}"></trkpt>');
    }
    b
      ..writeln('  </trkseg></trk>')
      ..writeln('</gpx>');
    return b.toString();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }
}
