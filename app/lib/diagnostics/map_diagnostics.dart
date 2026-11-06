import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

/// Only fixed stage names and numeric measurements may enter a map report.
enum MapStage {
  request,
  response,
  conversion,
  validation,
  save,
  listing,
  activation,
}

class MapAttempt {
  MapAttempt(this.operation);
  final String operation;
  final started = DateTime.now().toUtc();
  final clock = Stopwatch()..start();
  final events = <Map<String, Object?>>[];
  Map<String, Object?>? error;
  MapStage stage = MapStage.request;
  bool saved = false;
  bool cancelled = false;
  bool _finished = false;
  static final _zoneKey = Object();
  static MapAttempt? get current => Zone.current[_zoneKey] as MapAttempt?;
  Future<T> run<T>(Future<T> Function() action) =>
      runZoned(action, zoneValues: {_zoneKey: this});

  void mark(MapStage value, {int? bytes, int? status}) {
    if (_finished) return;
    stage = value;
    if (events.isNotEmpty && events.last['stage'] == value.name) {
      events.removeLast();
    }
    if (events.length >= 32) return;
    events.add({
      'stage': value.name,
      'elapsedMs': clock.elapsedMilliseconds,
      if (bytes != null) 'bytes': bytes,
      if (status != null) 'httpStatus': status,
    });
  }

  /// Do not retain exception.toString(): SQLite errors can contain entire INSERT
  /// arguments, including GeoJSON. Classify in memory and discard the payload.
  void capture(Object exception, StackTrace stack) {
    if (_finished || error != null) return;
    try {
      _capture(exception, stack);
    } catch (_) {
      error = {
        'stage': stage.name,
        'message': 'unexpected',
        'type': 'unavailable',
      };
    }
  }

  void _capture(Object exception, StackTrace stack) {
    int? databaseCode;
    if (exception is DatabaseException) {
      try {
        databaseCode = exception.getResultCode();
      } catch (_) {}
    }
    // Use structured SQLite accessors; never format SQL or its arguments.
    final raw = exception is DatabaseException
        ? ''
        : exception is PlatformException
        ? exception.message ?? ''
        : exception.toString();
    final code = RegExp(
      r'\b(?:SQLITE_[A-Z_]+|ENOSPC|EACCES|EPERM|EROFS)\b',
    ).firstMatch(raw)?.group(0);
    final sqliteNumber = RegExp(
      r'\bcode\s+(\d{1,3})\b',
    ).firstMatch(raw)?.group(1);
    final osCode = exception is FileSystemException
        ? exception.osError?.errorCode
        : exception is SocketException
        ? exception.osError?.errorCode
        : null;
    final category =
        databaseCode != null && (databaseCode & 255) == 13 ||
            code == 'SQLITE_FULL' ||
            code == 'ENOSPC' ||
            osCode == 28
        ? 'diskFull'
        : databaseCode != null && [5, 6].contains(databaseCode & 255)
        ? 'databaseBusy'
        : exception is DatabaseException && exception.isNoSuchTableError()
        ? 'databaseTableMissing'
        : exception is DatabaseException && exception.isDatabaseClosedError()
        ? 'databaseClosed'
        : exception is DatabaseException && exception.isReadOnlyError()
        ? 'readOnly'
        : exception is DatabaseException && exception.isOpenFailedError()
        ? 'databaseOpenFailed'
        : databaseCode != null && [3, 23].contains(databaseCode & 255)
        ? 'accessDenied'
        : databaseCode != null && (databaseCode & 255) == 11
        ? 'databaseCorrupt'
        : RegExp(
            r'SQLITE_BUSY|SQLITE_LOCKED|database is locked',
            caseSensitive: false,
          ).hasMatch(raw)
        ? 'databaseBusy'
        : RegExp(
            r'EACCES|EPERM|permission denied|SecurityException',
            caseSensitive: false,
          ).hasMatch(raw)
        ? 'accessDenied'
        : RegExp(
            r'SQLITE_READONLY|EROFS|read.only database',
            caseSensitive: false,
          ).hasMatch(raw)
        ? 'readOnly'
        : RegExp(
            r'CursorWindow|SQLiteBlobTooBig|row too big',
            caseSensitive: false,
          ).hasMatch(raw)
        ? 'databaseRowTooLarge'
        : exception is TimeoutException
        ? 'timeout'
        : exception is IOException
        ? 'connectionOrIO'
        : exception is FormatException
        ? 'invalidOrUnsupportedData'
        : 'unexpected';
    final frames = RegExp(
      r'(?:package:wanderlust/|dart:)[A-Za-z0-9_./-]+\.dart:\d+(?::\d+)?',
    ).allMatches(stack.toString()).take(24).map((m) => m.group(0)!).toList();
    final type = exception.runtimeType.toString().replaceAll(
      RegExp(r'[^A-Za-z0-9_<>]'),
      '',
    );
    final platformCode =
        exception is PlatformException &&
            RegExp(r'^[a-zA-Z_]{1,48}$').hasMatch(exception.code)
        ? exception.code
        : null;
    error = {
      'stage': stage.name,
      'type': type.substring(0, type.length.clamp(0, 80)),
      'message': category,
      if (code != null) 'code': code,
      if (databaseCode != null || sqliteNumber != null)
        'sqliteCode': databaseCode ?? int.parse(sqliteNumber!),
      if (osCode != null) 'osCode': osCode,
      if (platformCode != null) 'platformCode': platformCode,
      'stack': frames,
    };
  }

  String get userMessage {
    if (error?['message'] == 'diskFull') {
      return 'The phone reported insufficient space. Free some storage and retry.';
    }
    if (saved) {
      return 'Map saved, but could not finish opening it. Reopen it from Saved maps. Details are available below.';
    }
    return switch (stage) {
      MapStage.request || MapStage.response =>
        'Could not download the map. Open Details for a diagnostic report.',
      MapStage.conversion || MapStage.validation =>
        'Could not prepare the downloaded map. Open Details for a diagnostic report.',
      MapStage.save =>
        'Could not save the map. Open Details for a diagnostic report.',
      MapStage.listing =>
        'Could not load saved maps. Open Details for a diagnostic report.',
      MapStage.activation =>
        'Could not open the saved map. Open Details for a diagnostic report.',
    };
  }
}

/// Independent of SQLite so a broken database can still be diagnosed.
class MapDiagnostics {
  MapDiagnostics({this.directory, this.metadata});
  static final instance = MapDiagnostics();
  final Directory? directory;
  final Future<Map<String, Object?>> Function()? metadata;
  static const maxBytes = 256 * 1024;
  static const maxAttempts = 20;
  final _reports = <Map<String, Object?>>[];
  Future<void>? _queue;
  bool _loaded = false;
  File? _file;

  Future<Map<String, Object?>> _environment() async {
    if (metadata == null && !Platform.isAndroid) return {};
    try {
      return await (metadata?.call() ??
              const MethodChannel('wanderlust/diagnostics')
                  .invokeMapMethod<String, Object?>('environment')
                  .then((v) => v ?? {}))
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      return {};
    }
  }

  Future<void> _load(Map<String, Object?> environment) async {
    if (_loaded) return;
    _loaded = true;
    try {
      final path = directory?.path ?? environment['directory'] as String?;
      if (path == null) return;
      _file = File('$path/map-reports.json');
      if (await _file!.exists() && await _file!.length() <= maxBytes) {
        final data = jsonDecode(await _file!.readAsString()) as List;
        _reports.addAll(
          data.cast<Map<String, dynamic>>().map(
            (r) => r.cast<String, Object?>(),
          ),
        );
        _trim();
      }
    } catch (_) {
      /* In-memory reporting still works. */
    }
  }

  void _trim() {
    while (_reports.length > maxAttempts ||
        utf8.encode(jsonEncode(_reports)).length > maxBytes) {
      _reports.removeAt(0);
    }
  }

  Future<void> finish(MapAttempt attempt) {
    attempt.clock.stop();
    attempt._finished = true;
    final pending = (_queue ?? Future<void>.value())
        .then((_) async {
          final environment = await _environment();
          await _load(environment);
          _reports.add({
            'schema': 1,
            'started': attempt.started.toIso8601String(),
            'operation': attempt.operation,
            'elapsedMs': attempt.clock.elapsedMilliseconds,
            'outcome': attempt.cancelled
                ? 'cancelled'
                : attempt.error == null
                ? 'success'
                : 'failed',
            'mapSaved': attempt.saved,
            'environment': {
              for (final key in [
                'build',
                'manufacturer',
                'model',
                'android',
                'sdk',
                'availableBytes',
              ])
                if (environment[key] case final value?) key: value,
            },
            'events': attempt.events,
            if (attempt.error != null) 'error': attempt.error,
          });
          _trim();
          try {
            if (_file != null) {
              await _file!.parent.create(recursive: true);
              final temporary = File('${_file!.path}.tmp');
              await temporary.writeAsString(jsonEncode(_reports), flush: true);
              await temporary.rename(_file!.path);
            }
          } catch (_) {
            /* Never replace the original map failure. */
          }
        })
        .catchError((Object _) {});
    _queue = pending;
    return pending.whenComplete(() {
      if (identical(_queue, pending)) _queue = null;
    });
  }

  Future<String> report() async {
    await _queue;
    await _load(await _environment());
    return const JsonEncoder.withIndent('  ').convert(_reports);
  }
}
