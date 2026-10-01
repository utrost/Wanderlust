import 'dart:isolate';

import 'geo_core_ffi.dart';
import 'matching_session.dart';

/// A bounded, long-lived native matcher cache, owned by one coverage controller.
class MatchingWorker {
  Future<SendPort>? _starting;
  Isolate? _isolate;
  bool _closed = false;

  Future<SendPort> _start() async {
    final ready = ReceivePort();
    try {
      _isolate = await Isolate.spawn(_serve, ready.sendPort);
      return await ready.first as SendPort;
    } finally {
      ready.close();
    }
  }

  Future<List<MatchResult>> match(
    String source,
    List<String> walks, {
    required bool fillSmallGaps,
  }) async {
    if (_closed) throw StateError('Matching worker is closed');
    final port = await (_starting ??= _start());
    final response = ReceivePort();
    try {
      port.send((response.sendPort, source, walks, fillSmallGaps));
      final result = await response.first;
      if (result is String) throw StateError(result);
      return result as List<MatchResult>;
    } finally {
      response.close();
    }
  }

  /// Call after queued matching has settled, so no replies are abandoned.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (_starting == null) return;
    final port = await _starting!;
    final response = ReceivePort();
    try {
      port.send(response.sendPort);
      await response.first;
    } finally {
      response.close();
      _isolate?.kill();
    }
  }
}

void _serve(SendPort ready) {
  final commands = ReceivePort();
  final session = MatchingSession();
  ready.send(commands.sendPort);
  commands.listen((dynamic message) {
    if (message is SendPort) {
      session.dispose();
      commands.close();
      message.send(true);
      return;
    }
    final request = message as (SendPort, String, List<String>, bool);
    try {
      request.$1.send(
        session.match(request.$2, request.$3, fillSmallGaps: request.$4),
      );
    } catch (error) {
      request.$1.send('Walk matching failed: $error');
    }
  });
}
