import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wanderlust/diagnostics/map_diagnostics.dart';
import 'package:wanderlust/maps/map_download.dart';
import 'nearby_maps_test.dart' show smallOsm;

void main() {
  test(
    'original failure, safe code locations and context survive wrappers',
    () async {
      final attempt = MapAttempt('download');
      await attempt.run(() async {
        MapAttempt.current!.mark(MapStage.save, bytes: 4000);
        MapAttempt.current!.capture(
          PlatformException(
            code: 'sqlite_error',
            message: 'SQLITE_BUSY at 53.101, 8.778 Secret Road',
            details: {'sql': 'private'},
          ),
          StackTrace.fromString(
            '#0 save (package:wanderlust/storage/offline_map_repository.dart:99:2)\n/private/location/53.101',
          ),
        );
      });
      attempt.capture(StateError('wrapper'), StackTrace.current);
      final reports = MapDiagnostics(
        metadata: () async => {
          'build': 'test',
          'directory': null,
          'coordinates': 'private',
        },
      );
      await reports.finish(attempt);
      final report = await reports.report();
      expect(report, contains('databaseBusy'));
      expect(report, contains('offline_map_repository.dart:99:2'));
      for (final secret in [
        '53.101',
        '8.778',
        'Secret Road',
        'private',
        'coordinates',
        'wrapper',
      ]) {
        expect(report, isNot(contains(secret)));
      }
    },
  );

  test(
    'SQLite errors never stringify SQL arguments and preserve numeric codes',
    () {
      final attempt = MapAttempt('download')..mark(MapStage.save);
      attempt.capture(PrivateDatabaseError(), StackTrace.current);
      expect(attempt.error!['sqliteCode'], 13);
      expect(attempt.userMessage, contains('insufficient space'));
    },
  );

  test(
    'retention survives restart and unavailable storage falls back to memory',
    () async {
      final dir = await Directory.systemTemp.createTemp('map-diagnostics-test');
      addTearDown(() => dir.delete(recursive: true));
      final reports = MapDiagnostics(directory: dir, metadata: () async => {});
      for (var i = 0; i < 25; i++) {
        await reports.finish(
          MapAttempt('download')..mark(MapStage.validation, bytes: i),
        );
      }
      final restarted = MapDiagnostics(
        directory: dir,
        metadata: () async => {},
      );
      final loaded = jsonDecode(await restarted.report()) as List;
      expect(loaded.length, 20);
      expect(loaded.first['events'][0]['bytes'], 5);
      expect(
        await File('${dir.path}/map-reports.json').length(),
        lessThanOrEqualTo(MapDiagnostics.maxBytes),
      );
      final unusable = File('${dir.path}/not-a-directory')
        ..writeAsStringSync('file');
      final fallback = MapDiagnostics(
        directory: Directory(unusable.path),
        metadata: () async => throw StateError('unavailable'),
      );
      await fallback.finish(
        MapAttempt('refresh')
          ..capture(StateError('failure'), StackTrace.current),
      );
      expect(await fallback.report(), contains('failed'));
    },
  );

  test(
    'byte budget bounds persisted reports even with unusually long metadata',
    () async {
      final dir = await Directory.systemTemp.createTemp('map-report-budget');
      addTearDown(() => dir.delete(recursive: true));
      final logs = MapDiagnostics(
        directory: dir,
        metadata: () async => {'model': 'x' * 30000},
      );
      for (var i = 0; i < 20; i++) {
        await logs.finish(MapAttempt('download'));
      }
      expect(
        await File('${dir.path}/map-reports.json').length(),
        lessThanOrEqualTo(MapDiagnostics.maxBytes),
      );
      expect((jsonDecode(await logs.report()) as List).length, lessThan(20));
    },
  );

  test(
    'conversion and validation errors retain their stage without payloads',
    () async {
      for (final stage in [MapStage.conversion, MapStage.validation]) {
        final attempt = MapAttempt('download')..mark(stage);
        attempt.capture(
          const FormatException('invalid at Secret Road 53.1, 8.8'),
          StackTrace.current,
        );
        expect(attempt.error!['stage'], stage.name);
        expect(jsonEncode(attempt.error), isNot(contains('Secret')));
        expect(attempt.userMessage, contains('prepare'));
      }
    },
  );

  test('late callbacks cannot alter a completed report', () async {
    final logs = MapDiagnostics(metadata: () async => {});
    final attempt = MapAttempt('download')..mark(MapStage.activation);
    await logs.finish(attempt);
    final before = await logs.report();
    await attempt.run(() async {
      MapAttempt.current!.capture(
        StateError('late unrelated error'),
        StackTrace.current,
      );
      MapAttempt.current!.mark(MapStage.save);
    });
    expect(await logs.report(), before);
  });

  test('stage failures do not falsely claim disk full', () {
    for (final stage in MapStage.values) {
      final attempt = MapAttempt('download')..mark(stage);
      attempt.capture(StateError('unknown'), StackTrace.current);
      expect(attempt.error!['stage'], stage.name);
      expect(attempt.userMessage, isNot(contains('space')));
    }
    final access = MapAttempt('download')..mark(MapStage.save);
    access.capture(
      const FileSystemException(
        'Permission denied',
        '/secret',
        OSError('denied', 13),
      ),
      StackTrace.current,
    );
    expect(access.error!['message'], 'accessDenied');
    access.saved = true;
    access.mark(MapStage.activation);
    expect(access.userMessage, startsWith('Map saved'));
  });

  test(
    'HTTP status, bytes and conversion are recorded on real local download',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        await request.drain<void>();
        request.response.write(smallOsm);
        await request.response.close();
      });
      final attempt = MapAttempt('download');
      await attempt.run(
        () => MapDownload(
          endpoint: Uri.parse('http://127.0.0.1:${server.port}/'),
        ).fetch(NearbyArea.around(53.1, 8.8, sizeKm: 1)),
      );
      expect(
        attempt.events.map((e) => e['stage']),
        containsAllInOrder(['request', 'response', 'conversion', 'validation']),
      );
      expect(
        attempt.events.firstWhere(
          (e) => e['stage'] == 'response',
        )['httpStatus'],
        200,
      );
      expect(attempt.events.last['bytes'], greaterThan(0));
    },
  );

  test(
    'connection errors retain original exception before user-facing wrapper',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      await server.close(force: true);
      final attempt = MapAttempt('download');
      await expectLater(
        attempt.run(
          () => MapDownload(
            endpoint: Uri.parse('http://127.0.0.1:$port/'),
          ).fetch(NearbyArea.around(53.1, 8.8, sizeKm: 1)),
        ),
        throwsFormatException,
      );
      expect(attempt.error!['type'], contains('SocketException'));
    },
  );
}

class PrivateDatabaseError extends DatabaseException {
  PrivateDatabaseError() : super('database or disk is full');
  @override
  int? getResultCode() => 13;
  @override
  Object? get result => {'arguments': 'Secret map'};
  @override
  String toString() => throw StateError('Must not stringify SQL');
}
