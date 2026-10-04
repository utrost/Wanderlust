import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../geo/location_freshness.dart';
import '../geo/location_warmup.dart';
import '../recording/walk_recorder.dart';

/// Coordinates GPS and camera intent independently of navigation and widgets.
/// Browsing or hiding the app cancels pending camera moves, not acquired fixes.
class MapLocationController extends ChangeNotifier {
  MapLocationController({
    required this.recorder,
    this.locate,
    this.warmupPositions,
  });
  final WalkRecorder recorder;
  final Stream<Position> Function()? warmupPositions;
  int _warmupEpoch = 0;
  Future<void> prepareRecording() async {
    _warmupEpoch++;
    await _warmup?.close();
  }

  final Future<Position> Function()? locate;
  bool _disposed = false;
  LocationWarmup? _warmup;
  bool get visible => _visible;
  bool get locating => _locating;
  String? get error => _gpsError;
  int get centerRequest => _centerRequest;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _change(void Function() change) {
    if (_disposed) return;
    change();
    _notify();
  }

  void setVisible(bool value) {
    _visible = value;
    if (!value) {
      browseMap();
      unawaited(prepareRecording());
    }
  }

  void recordingStarted() => _change(() {
    _centerRequest++;
    _gpsError = null;
  });
  Position? _previewPosition;
  bool _locating = false;
  String? _gpsError;
  int _centerRequest = 0;
  bool _visible = true;
  bool _centerWhenFresh = false;
  int _cameraIntent = 0;

  void browseMap() {
    _cameraIntent++;
    _centerWhenFresh = false;
  }

  Position? get currentFix {
    final recorded = recorder.latestPosition;
    if (recorder.isRecording) return recorded;
    if (recorded == null) return _previewPosition;
    if (_previewPosition == null ||
        recorded.timestamp.isAfter(_previewPosition!.timestamp)) {
      return recorded;
    }
    return _previewPosition;
  }

  Future<void> centerOnMe({bool automatic = false}) async {
    if (_disposed || _locating) return;
    final intent = ++_cameraIntent;
    final warmupEpoch = _warmupEpoch;
    if (recorder.isRecording) {
      _change(() {
        _centerWhenFresh = true;
        _gpsError = null;
      });
      onRecordingChanged();
      return;
    }
    _change(() {
      _locating = true;
      _gpsError = null;
    });
    try {
      // Returning to the app must not open a permission dialog. The explicit
      // location button and first-map setup still request permission normally.
      if (automatic) {
        if (!await Geolocator.isLocationServiceEnabled()) return;
        final permission = await Geolocator.checkPermission();
        if (permission != LocationPermission.whileInUse &&
            permission != LocationPermission.always) {
          return;
        }
      }
      final error = automatic
          ? null
          : await DeviceLocationSource(forRecording: false).authorize();
      if (_disposed) return;
      if (error != null) {
        _change(
          () => _gpsError = error == RecorderError.locationServiceDisabled
              ? 'Turn on location to find your position.'
              : 'Allow location access in Android settings to show your position.',
        );
        return;
      }
      if (!_visible ||
          recorder.isBusy ||
          recorder.isRecording ||
          warmupEpoch != _warmupEpoch) {
        return;
      }
      Position? warmed;
      if (locate == null) {
        final warmup = LocationWarmup(
          open:
              warmupPositions ??
              () => Geolocator.getPositionStream(
                locationSettings:
                    defaultTargetPlatform == TargetPlatform.android
                    ? AndroidSettings(
                        accuracy: LocationAccuracy.high,
                        distanceFilter: 0,
                        intervalDuration: const Duration(seconds: 2),
                      )
                    : const LocationSettings(
                        accuracy: LocationAccuracy.high,
                        distanceFilter: 0,
                      ),
              ),
          onFix: (fix) {
            if (_disposed ||
                !_visible ||
                recorder.isBusy ||
                recorder.isRecording) {
              return;
            }
            warmed = fix;
            _change(() {
              _previewPosition = fix;
              if (intent == _cameraIntent) _centerRequest++;
            });
          },
        );
        _warmup = warmup;
        await warmup.start();
        if (identical(_warmup, warmup)) _warmup = null;
        if (_disposed ||
            !_visible ||
            recorder.isBusy ||
            recorder.isRecording ||
            warmupEpoch != _warmupEpoch) {
          return;
        }
      }
      final position = locate != null ? await locate!() : warmed;
      if (position == null) throw TimeoutException('Waiting for a current fix');
      if (!position.latitude.isFinite ||
          !position.longitude.isFinite ||
          position.latitude.abs() > 90 ||
          position.longitude.abs() > 180 ||
          !position.accuracy.isFinite ||
          position.accuracy < 0) {
        throw const FormatException('Invalid location fix');
      }
      if (isOldFix(position, DateTime.now())) {
        throw TimeoutException('Waiting for a current fix');
      }
      if (_disposed) return;
      _change(() {
        _previewPosition = position;
        if (_visible && intent == _cameraIntent) _centerRequest++;
      });
    } on TimeoutException {
      if (!_disposed) {
        _change(() => _gpsError = 'No GPS fix yet. Try again outdoors.');
      }
    } catch (_) {
      if (!_disposed) {
        _change(
          () => _gpsError = 'Location unavailable. Check GPS and permissions.',
        );
      }
    } finally {
      if (!_disposed) _change(() => _locating = false);
    }
  }

  void onRecordingChanged() {
    if (recorder.isBusy || recorder.isRecording) unawaited(_warmup?.close());
    final fix = recorder.latestPosition;
    if (_centerWhenFresh && fix != null && !isOldFix(fix, DateTime.now())) {
      _centerWhenFresh = false;
      _centerRequest++;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_warmup?.close());
    super.dispose();
  }
}
