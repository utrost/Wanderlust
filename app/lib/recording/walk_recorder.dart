import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import 'walk_store.dart';
import '../transfer/walk_codec.dart';

enum RecorderError {
  locationServiceDisabled,
  permissionDenied,
  locationFailed,
  storageFailed,
}

enum RecorderState { idle, starting, recording, stopping }

abstract class LocationSource {
  Future<RecorderError?> authorize();
  Stream<Position> positions();
}

class DeviceLocationSource implements LocationSource {
  DeviceLocationSource({this.forRecording = true, this.detailedGps});
  final bool forRecording;
  final bool Function()? detailedGps;
  static const _notificationChannel = MethodChannel('wanderlust/walking');

  /// A user-started location service keeps this stream alive with the screen
  /// off. Cancellation releases both GPS and the service's partial wake lock.
  static LocationSettings settingsFor(
    TargetPlatform platform, {
    bool detailed = false,
  }) => platform == TargetPlatform.android
      ? AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: detailed ? 2 : 5,
          intervalDuration: Duration(seconds: detailed ? 2 : 5),
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: 'Walk in progress',
            notificationText: 'Recording your route. Tap to return and stop.',
            notificationChannelName: 'Walk recording',
            notificationIcon: AndroidResource(name: 'ic_walk_notification'),
            enableWakeLock: true,
            setOngoing: true,
          ),
        )
      : const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        );

  @override
  Future<RecorderError?> authorize() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return RecorderError.locationServiceDisabled;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return RecorderError.permissionDenied;
    }
    if (forRecording && defaultTargetPlatform == TargetPlatform.android) {
      // Notification denial does not revoke location permission. Android still
      // exposes the active foreground service in its active-apps controls.
      await _notificationChannel.invokeMethod<bool>('prepareRecording');
    }
    return null;
  }

  @override
  Stream<Position> positions() => Geolocator.getPositionStream(
    locationSettings: settingsFor(
      defaultTargetPlatform,
      detailed: detailedGps?.call() ?? false,
    ),
  );
}

class WalkRecorder extends ChangeNotifier {
  WalkRecorder({
    LocationSource? location,
    WalkStore? store,
    DateTime Function()? now,
  }) : _location = location ?? DeviceLocationSource(),
       _store = store ?? SqliteWalkStore(),
       _now = now ?? DateTime.now;
  final LocationSource _location;
  final WalkStore _store;
  final DateTime Function() _now;
  final List<Position> _points = [];
  List<SavedWalk> _savedWalks = [];
  List<SavedWalk> get savedWalks => List.unmodifiable(_savedWalks);
  StreamSubscription<Position>? _sub;
  Timer? _ticker;
  DateTime? _startedAt;
  DateTime? _endedAt;
  int? _walkId;
  double _distance = 0;
  bool _disposed = false;
  bool _foreground = true;
  bool _initialized = false;
  bool _pendingSave = false;
  bool get needsSaveRetry => _pendingSave;
  Future<void>? _initializing;
  Future<void> _writes = Future.value();
  Future<void>? _stopping;
  Future<bool>? _starting;
  Future<void>? _retrying;
  RecorderState state = RecorderState.idle;
  RecorderError? lastError;
  bool get isRecording => state == RecorderState.recording;
  bool get isBusy =>
      state == RecorderState.starting || state == RecorderState.stopping;
  int get pointCount => _points.length;
  Position? get latestPosition => _points.isEmpty ? null : _points.last;
  SavedWalk? get recordingSnapshot => _walkId == null || _startedAt == null
      ? null
      : SavedWalk(
          _walkId!,
          _startedAt!,
          null,
          'recording',
          List.unmodifiable(_points),
        );
  double get distanceMeters => _distance;
  Duration get elapsed => _startedAt == null
      ? Duration.zero
      : (_endedAt ?? _now()).difference(_startedAt!);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// GPS and journaling continue while hidden; the display clock need not wake
  /// Dart every second. Elapsed time is derived from timestamps on return.
  void setForeground(bool value) {
    _foreground = value;
    _updateTicker();
    if (value) _notify();
  }

  void _updateTicker() {
    _ticker?.cancel();
    _ticker = null;
    if (_foreground && isRecording && !_disposed) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _notify());
    }
  }

  Future<void> initialize() => _initializing ??= _initialize();
  Future<void> _initialize() async {
    try {
      _savedWalks = await _store.recoverAndList();
      _initialized = true;
    } catch (_) {
      lastError = RecorderError.storageFailed;
    }
    _notify();
  }

  Future<bool> start() {
    if (_disposed || state != RecorderState.idle || _pendingSave) {
      return Future.value(false);
    }
    return _starting = _start();
  }

  Future<bool> _start() async {
    state = RecorderState.starting;
    lastError = null;
    _notify();
    try {
      await initialize();
      if (!_initialized) {
        // Allow an explicit retry after a failed database open.
        _initializing = null;
        await initialize();
      }
      if (!_initialized) return false;
      lastError = await _location.authorize();
      if (lastError != null || _disposed || !_foreground) return false;
      final startedAt = _now();
      try {
        _walkId = await _store.begin(startedAt);
      } catch (_) {
        lastError = RecorderError.storageFailed;
        return false;
      }
      if (_disposed) return false;
      if (!_foreground) {
        await _store.finish(_walkId!, _now(), 'interrupted');
        _savedWalks = await _store.recoverAndList();
        return false;
      }
      _points.clear();
      _distance = 0;
      _startedAt = startedAt;
      _endedAt = null;
      _writes = Future.value();
      state = RecorderState.recording;
      _sub = _location.positions().listen(
        _onPoint,
        onError: (Object error, StackTrace stack) => _locationEnded(),
        onDone: _locationEnded,
      );
      _updateTicker();
      _notify();
      return true;
    } catch (_) {
      lastError = RecorderError.locationFailed;
      if (state == RecorderState.recording) await stop(interrupted: true);
      return false;
    } finally {
      if (state == RecorderState.starting) state = RecorderState.idle;
      _notify();
    }
  }

  void _onPoint(Position point) {
    if (!isRecording || _disposed) return;
    if (!point.latitude.isFinite ||
        !point.longitude.isFinite ||
        point.latitude.abs() > 90 ||
        point.longitude.abs() > 180 ||
        !point.accuracy.isFinite ||
        point.accuracy < 0) {
      return;
    }
    final sequence = _points.length;
    if (_points.isNotEmpty) {
      final previous = _points.last;
      _distance += Geolocator.distanceBetween(
        previous.latitude,
        previous.longitude,
        point.latitude,
        point.longitude,
      );
    }
    _points.add(point);
    final id = _walkId!;
    _writes = _writes
        .then((_) => _store.append(id, sequence, point))
        .catchError((Object error) {
          _pendingSave = true;
          lastError = RecorderError.storageFailed;
          unawaited(stop(interrupted: true));
        });
    _notify();
  }

  void _locationEnded() {
    if (!isRecording || _disposed) return;
    lastError = RecorderError.locationFailed;
    unawaited(stop(interrupted: true));
  }

  Future<void> stop({bool interrupted = false}) {
    if (_stopping != null) return _stopping!;
    if (!isRecording) return Future.value();
    state = RecorderState.stopping;
    _endedAt = _now();
    _ticker?.cancel();
    _ticker = null;
    _notify();
    final stopping = _finish(interrupted);
    _stopping = stopping;
    return stopping;
  }

  Future<void> _finish(bool interrupted) async {
    try {
      await _sub?.cancel();
      _sub = null;
      await _writes;
      await _store.finish(
        _walkId!,
        _endedAt!,
        interrupted || lastError != null ? 'interrupted' : 'completed',
      );
      _savedWalks = await _store.recoverAndList();
    } catch (_) {
      _pendingSave = true;
      lastError = RecorderError.storageFailed;
    } finally {
      state = RecorderState.idle;
      _stopping = null;
      _notify();
    }
  }

  /// Retry using the original walk and point keys. A partial earlier save is
  /// safe to replay, and the in-memory trace is kept until this succeeds.
  Future<void> retrySave() {
    if (!_pendingSave || state != RecorderState.idle || _disposed) {
      return Future.value();
    }
    return _retrying = _retrySave();
  }

  Future<void> _retrySave() async {
    state = RecorderState.stopping;
    _notify();
    try {
      for (var i = 0; i < _points.length; i++) {
        await _store.append(_walkId!, i, _points[i]);
      }
      await _store.finish(_walkId!, _endedAt!, 'interrupted');
      _savedWalks = await _store.recoverAndList();
      _pendingSave = false;
      lastError = null;
    } catch (_) {
      lastError = RecorderError.storageFailed;
    } finally {
      state = RecorderState.idle;
      _notify();
    }
  }

  /// Raw fixes retain timestamps and measured horizontal accuracy. Accuracy is
  /// a namespaced extension, not GPX hdop (which has different units).
  String toGpx() => pointsToGpx(_points);
  static String pointsToGpx(List<Position> points) => WalkCodec.exportGpx(
    SavedWalk(0, DateTime.utc(1970), null, 'completed', points),
  );

  Future<void> refreshSavedWalks() async {
    if (state != RecorderState.idle || _pendingSave) {
      throw StateError('Finish saving the current walk first.');
    }
    _savedWalks = await _store.recoverAndList();
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    // Leave the database session open for recovery as interrupted on relaunch.
    unawaited(_close());
    super.dispose();
  }

  Future<void> _close() async {
    try {
      await _sub?.cancel();
      await _starting;
      await _initializing;
      await _stopping;
      await _retrying;
      await _writes;
      await _store.close();
    } catch (_) {
      /* Recovery retains any committed points. */
    }
  }
}
