import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../transfer/walk_codec.dart';
import 'activity_type.dart';
import 'gps_diagnostics.dart';
import 'location_watchdog.dart';
import 'native_recording.dart';
import 'saved_walk.dart';
import 'walk_distance.dart';
import 'walk_journal.dart';

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

abstract interface class DiagnosticLocationSource {
  Future<Map<String, Object?>> diagnosticMetadata();
}

abstract interface class RecoverableLocationSource {
  Future<void> recover();
}

class DeviceLocationSource
    implements
        LocationSource,
        DiagnosticLocationSource,
        RecoverableLocationSource {
  DeviceLocationSource({this.forRecording = true, this.gpsIntervalSeconds});
  final bool forRecording;
  final int Function()? gpsIntervalSeconds;
  static const _notificationChannel = MethodChannel('wanderlust/walking');
  static const _androidLocationChannel = MethodChannel(
    'flutter.baseflow.com/geolocator_android',
  );

  @override
  Future<void> recover() async {
    await _androidLocationChannel.invokeMethod<void>(
      'restartRecordingLocation',
    );
  }

  /// A user-started location service keeps this stream alive with the screen
  /// off. Cancellation releases both GPS and the service's partial wake lock.
  static LocationSettings settingsFor(
    TargetPlatform platform, {
    int intervalSeconds = 5,
  }) => platform == TargetPlatform.android
      ? AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: intervalSeconds == 2 ? 2 : 5,
          intervalDuration: Duration(seconds: intervalSeconds),
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
  Future<Map<String, Object?>> diagnosticMetadata() async {
    final result = <String, Object?>{};
    try {
      result['permissionAccuracy'] =
          (await Geolocator.getLocationAccuracy()).name;
      if (defaultTargetPlatform == TargetPlatform.android) {
        result['lastReportedProvider'] = await _androidLocationChannel
            .invokeMethod<String>('getLastReportedProvider');
      }
    } catch (_) {
      /* Diagnostics must never prevent recording. */
    }
    return result;
  }

  @override
  Stream<Position> positions() => Geolocator.getPositionStream(
    locationSettings: settingsFor(
      defaultTargetPlatform,
      intervalSeconds: gpsIntervalSeconds?.call() ?? 5,
    ),
  );
}

class WalkRecorder extends ChangeNotifier {
  WalkRecorder({
    LocationSource? location,
    required WalkStore store,
    DateTime Function()? now,
    this.showElapsed,
    this.activityType,
    this.gpsInterval,
    this.automaticGps,
    this.loadHistory,
    this.nativeRecording,
  }) : _location = location ?? DeviceLocationSource(),
       _store = store,
       _now = now ?? DateTime.now;
  final NativeRecordingBackend? nativeRecording;
  Timer? _nativePoll;
  Future<void>? _nativeSync;
  bool _recoverable = false;
  bool get hasRecoverableWalk => _recoverable;
  double? _nativeMeters;
  Map<String, Object?> _nativeDiagnostics = const {};
  List<int> _nativeSegments = const [];
  bool _nativeHasFix = false;
  final Future<List<SavedWalk>> Function()? loadHistory;
  Future<List<SavedWalk>> _history() =>
      loadHistory?.call() ?? _store.recoverAndList();
  final bool Function()? showElapsed;
  final WalkActivity Function()? activityType;
  final int Function()? gpsInterval;
  final bool Function()? automaticGps;
  int requestedGpsInterval = 5;
  GpsDiagnostics? _diagnostics;
  bool get locating =>
      isRecording &&
      !(nativeRecording != null
          ? _nativeHasFix
          : (_diagnostics?.hasFreshFix ?? false));
  Map<String, Object?> get gpsDiagnostics => nativeRecording != null
      ? _nativeDiagnostics
      : (_diagnostics?.snapshot() ?? const {});
  WalkActivity _activity = WalkActivity.walk;
  final LocationSource _location;
  final WalkStore _store;
  final DateTime Function() _now;
  final List<Position> _points = [];
  List<SavedWalk> _savedWalks = [];
  List<SavedWalk> get savedWalks => List.unmodifiable(_savedWalks);
  LocationWatchdog? _watchdog;
  bool gpsStale = false;
  Timer? _ticker;
  DateTime? _startedAt;
  DateTime? _endedAt;
  int? _walkId;
  WalkDistance _distance = WalkDistance();
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
          activity: _activity,
          segmentStarts: _nativeSegments,
        );
  double get distanceMeters => _nativeMeters ?? _distance.meters;
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
    _updateNativePolling();
    if (value) {
      if (nativeRecording != null && _initialized) unawaited(_pollNative());
      _watchdog?.check();
      _notify();
    }
  }

  void refreshDisplayClock() => _updateTicker();

  void _updateTicker() {
    _ticker?.cancel();
    _ticker = null;
    if (_foreground &&
        isRecording &&
        !_disposed &&
        (showElapsed?.call() ?? true)) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _notify());
    }
  }

  Future<void> initialize() => _initializing ??= _initialize();
  Future<void> _initialize() async {
    try {
      if (nativeRecording != null) await _syncNative();
      _savedWalks = (await _history())
          .where((w) => w.status != 'recording')
          .toList();
      _initialized = true;
      _updateNativePolling();
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
      if (nativeRecording != null) {
        await _nativeSync;
        final resumeId = _recoverable ? _walkId : null;
        await nativeRecording!.start(
          resumeId != null
              ? _activity.name
              : (activityType?.call() ?? WalkActivity.walk).name,
          resumeId: resumeId,
          intervalSeconds: (automaticGps?.call() ?? true)
              ? null
              : gpsInterval?.call(),
        );
        if (resumeId == null) {
          _walkId = null;
          _points.clear();
        }
        await _syncNative();
        _updateNativePolling();
        return isRecording;
      }
      final startedAt = _now();
      try {
        _activity = activityType?.call() ?? WalkActivity.walk;
        requestedGpsInterval =
            gpsInterval?.call() ?? (_activity == WalkActivity.cycle ? 2 : 5);
        _diagnostics = GpsDiagnostics(
          requestedIntervalSeconds: requestedGpsInterval,
          startedAt: startedAt,
        );
        _walkId = await _store.begin(startedAt, activity: _activity);
      } catch (_) {
        lastError = RecorderError.storageFailed;
        return false;
      }
      if (_disposed) return false;
      if (!_foreground) {
        await _store.finish(_walkId!, _now(), 'interrupted');
        _savedWalks = await _history();
        return false;
      }
      _points.clear();
      _distance = WalkDistance(automatic: true);
      _startedAt = startedAt;
      _endedAt = null;
      _writes = Future.value();
      state = RecorderState.recording;
      gpsStale = false;
      _watchdog = LocationWatchdog(
        open: _location.positions,
        recover:
            defaultTargetPlatform == TargetPlatform.android &&
                _location is RecoverableLocationSource
            ? (_location as RecoverableLocationSource).recover
            : null,
        onRestart: () {
          _diagnostics?.restarts++;
        },
        onPoint: _onPoint,
        now: _now,
        onStale: (value) {
          if (gpsStale != value) {
            gpsStale = value;
            _notify();
          }
        },
      )..start();
      _updateTicker();
      _notify();
      return true;
    } catch (_) {
      lastError = RecorderError.locationFailed;
      if (nativeRecording != null) {
        // A timeout can occur after the service committed Start. Reattach instead
        // of creating a second walk or stopping a successfully running service.
        await _pollNative();
        _updateNativePolling();
      } else if (state == RecorderState.recording) {
        await stop(interrupted: true);
      }
      return false;
    } finally {
      if (state == RecorderState.starting) state = RecorderState.idle;
      _notify();
    }
  }

  void _onPoint(Position point) {
    if (!isRecording || _disposed) return;
    _diagnostics?.add(point, _now());
    if (!point.latitude.isFinite ||
        !point.longitude.isFinite ||
        point.latitude.abs() > 90 ||
        point.longitude.abs() > 180 ||
        !point.accuracy.isFinite ||
        point.accuracy < 0) {
      return;
    }
    final sequence = _points.length;
    _distance.add(point);
    _points.add(point);
    final id = _walkId!;
    _writes = _writes
        .then((_) => _store.append(id, sequence, point))
        .catchError((Object error) {
          _pendingSave = true;
          lastError = RecorderError.storageFailed;
          unawaited(stop(interrupted: true));
        });
    if (_points.length % 30 == 0) {
      _writes = _writes.then((_) => _persistDiagnostics());
    }
    _notify();
  }

  Future<void> _persistDiagnostics() async {
    final store = _store;
    if (store is! GpsDiagnosticsStore ||
        _walkId == null ||
        _diagnostics == null) {
      return;
    }
    final metrics = _diagnostics!.snapshot();
    try {
      if (_location is DiagnosticLocationSource) {
        metrics.addAll(
          await (_location as DiagnosticLocationSource)
              .diagnosticMetadata()
              .timeout(const Duration(seconds: 2)),
        );
      }
      await (store as GpsDiagnosticsStore).saveGpsDiagnostics(
        _walkId!,
        metrics,
      );
    } catch (_) {
      /* Optional metrics must never jeopardize the recording. */
    }
  }

  Future<void> stop({bool interrupted = false}) {
    if (_stopping != null) return _stopping!;
    if (!isRecording && !_recoverable) return Future.value();
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
      if (nativeRecording != null) {
        await _nativeSync;
        await nativeRecording!.stop(_walkId!);
        await _syncNative();
        if (isRecording || _recoverable) {
          throw StateError('Walk has not stopped');
        }
        _savedWalks = (await _history())
            .where((w) => w.status != 'recording')
            .toList();
        _pendingSave = false;
        lastError = null;
        return;
      }
      await _watchdog?.close();
      _watchdog = null;
      await _writes;
      await _persistDiagnostics();
      await _store.finish(
        _walkId!,
        _endedAt!,
        interrupted || lastError != null ? 'interrupted' : 'completed',
      );
      _savedWalks = await _history();
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
      if (nativeRecording != null) {
        await _syncNative();
        if (_walkId != null && (isRecording || _recoverable)) {
          await nativeRecording!.stop(_walkId!);
          await _syncNative();
        }
        _savedWalks = (await _history())
            .where((w) => w.status != 'recording')
            .toList();
        _pendingSave = false;
        lastError = null;
        return;
      }
      for (var i = 0; i < _points.length; i++) {
        await _store.append(_walkId!, i, _points[i]);
      }
      await _store.finish(_walkId!, _endedAt!, 'interrupted');
      _savedWalks = await _history();
      _pendingSave = false;
      lastError = null;
    } catch (_) {
      lastError = RecorderError.storageFailed;
    } finally {
      state = RecorderState.idle;
      _notify();
    }
  }

  void _updateNativePolling() {
    _nativePoll?.cancel();
    _nativePoll = null;
    if (nativeRecording != null &&
        _foreground &&
        !_disposed &&
        (isRecording || _recoverable || isBusy || lastError != null)) {
      _nativePoll = Timer.periodic(const Duration(seconds: 2), (_) {
        if (!isBusy) unawaited(_pollNative());
      });
    }
  }

  Future<void> _pollNative() async {
    try {
      await _syncNative();
    } catch (_) {
      /* Service continues recording. */
    }
  }

  Future<void> _syncNative() => _nativeSync ??= _readNative().whenComplete(() {
    _nativeSync = null;
  });

  Future<void> _readNative() async {
    try {
      Map<String, dynamic>? snapshot;
      do {
        snapshot = await nativeRecording!.snapshot(
          walkId: _walkId,
          after: _points.length - 1,
        );
        if (snapshot == null || _disposed) return;
        final id = (snapshot['walkId'] as num).toInt();
        if (snapshot['active'] != true && _walkId == null) return;
        if (id != _walkId) {
          _walkId = id;
          _points.clear();
        }
        final page = snapshot['points'] as List? ?? const [];
        if (page.isEmpty &&
            _points.length < (snapshot['pointCount'] as num).toInt()) {
          throw StateError('Native journal page is missing');
        }
        for (final value in page) {
          final row = Map<String, dynamic>.from(value as Map);
          final seq = (row['sequence'] as num).toInt();
          if (seq < _points.length) continue;
          if (seq != _points.length) {
            throw StateError('Incomplete native journal page');
          }
          _points.add(
            Position.fromMap(Map<String, dynamic>.from(row['position'] as Map)),
          );
        }
      } while (_points.length < (snapshot['pointCount'] as num).toInt());
      final wasRecording = isRecording;
      _startedAt = DateTime.parse(snapshot['startedAt'] as String);
      _endedAt = snapshot['endedAt'] == null
          ? null
          : DateTime.parse(snapshot['endedAt'] as String);
      _activity = WalkActivity.parse(snapshot['activity']);
      _nativeSegments = (snapshot['segments'] as List? ?? const []).cast<int>();
      _nativeMeters = (snapshot['meters'] as num).toDouble();
      _nativeDiagnostics = readGpsDiagnostics(snapshot['diagnostics']);
      _nativeHasFix = snapshot['hasFreshFix'] as bool? ?? _points.isNotEmpty;
      requestedGpsInterval = (snapshot['intervalSeconds'] as num? ?? 3).toInt();
      _recoverable = snapshot['active'] == true && snapshot['running'] != true;
      gpsStale = snapshot['stale'] == true;
      state = snapshot['active'] == true && snapshot['running'] == true
          ? RecorderState.recording
          : RecorderState.idle;
      if (wasRecording && !isRecording) {
        _savedWalks = (await _history())
            .where((w) => w.status != 'recording')
            .toList();
      }
      if (!_pendingSave &&
          (isRecording || lastError == RecorderError.storageFailed)) {
        lastError = null;
      }
      _updateTicker();
      _updateNativePolling();
      _notify();
    } catch (_) {
      // Capture continues in Android even if the interface temporarily cannot read.
      lastError = RecorderError.storageFailed;
      _notify();
      rethrow;
    }
  }

  /// Raw fixes retain timestamps and measured horizontal accuracy. Accuracy is
  /// a namespaced extension, not GPX hdop (which has different units).
  String toGpx() => nativeRecording != null && recordingSnapshot != null
      ? WalkCodec.exportGpx(recordingSnapshot!)
      : pointsToGpx(_points, activity: _activity);
  static String pointsToGpx(
    List<Position> points, {
    WalkActivity activity = WalkActivity.walk,
  }) => WalkCodec.exportGpx(
    SavedWalk(
      0,
      DateTime.utc(1970),
      null,
      'completed',
      points,
      activity: activity,
    ),
  );

  Future<void> refreshSavedWalks() async {
    if (state != RecorderState.idle || _pendingSave) {
      throw StateError('Finish saving the current walk first.');
    }
    _savedWalks = await _history();
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _nativePoll?.cancel();
    // Leave the database session open for recovery as interrupted on relaunch.
    unawaited(_close());
    super.dispose();
  }

  Future<void> _close() async {
    try {
      await _watchdog?.close();
      await _nativeSync;
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
