import 'package:flutter/services.dart';

/// The service owns capture and persistence; Flutter only reads its journal.
abstract interface class NativeRecordingStore {
  Future<String> get recordingDatabasePath;
}

abstract interface class NativeRecordingBackend {
  Future<void> start(String activity, {int? resumeId, int? intervalSeconds});
  Future<Map<String, dynamic>?> snapshot({int? walkId, int after = -1});
  Future<void> stop(int walkId);
}

class AndroidRecordingBackend implements NativeRecordingBackend {
  AndroidRecordingBackend(this.store);
  final NativeRecordingStore store;
  static const _channel = MethodChannel('wanderlust/recorder');

  Future<T?> _call<T>(String method, Map<String, Object?> arguments) async =>
      _channel.invokeMethod<T>(method, {
        'database': await store.recordingDatabasePath,
        ...arguments,
      });

  @override
  Future<void> start(
    String activity, {
    int? resumeId,
    int? intervalSeconds,
  }) async {
    await _call<Object?>('start', {
      'activity': activity,
      if (intervalSeconds != null) 'intervalSeconds': intervalSeconds,
      if (resumeId != null) 'resumeId': resumeId,
    });
  }

  @override
  Future<Map<String, dynamic>?> snapshot({int? walkId, int after = -1}) async {
    final value = await _call<Map<Object?, Object?>>('snapshot', {
      'walkId': walkId,
      'after': after,
    });
    return value == null ? null : Map<String, dynamic>.from(value);
  }

  @override
  Future<void> stop(int walkId) async {
    await _call<Object?>('stop', {'walkId': walkId});
  }
}
