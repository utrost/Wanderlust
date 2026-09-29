import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wanderlust/coverage/coverage_controller.dart';
import 'package:wanderlust/recording/walk_recorder.dart';
import 'package:wanderlust/recording/walk_store.dart';
import 'recording_test.dart' show FakeLocation;
import 'package:wanderlust/transfer/walk_codec.dart';

void main() {
  sqfliteFfiInit();
  test(
    'GPX import and backup restore rebuild identical real Bremen coverage',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'wanderlust-native-transfer-',
      );
      final source = SqliteWalkStore(
        factory: databaseFactoryFfi,
        databasePath: '${dir.path}/source.db',
      );
      final target = SqliteWalkStore(
        factory: databaseFactoryFfi,
        databasePath: '${dir.path}/target.db',
      );
      final network = await File(
        'assets/geo/bremen-center.streets.geojson',
      ).readAsString();
      final a = CoverageController(
        store: source,
        loadNetwork: () async => network,
      );
      final b = CoverageController(
        store: target,
        loadNetwork: () async => network,
      );
      try {
        final gpx = await File(
          '../data/bremen/evaluation/schlachte.synthetic.gpx',
        ).readAsString();
        final imported = WalkCodec.importGpx(gpx);
        expect(await source.mergeWalks([imported], deduplicateTrace: true), 1);
        await a.synchronize(await source.listSaved());
        expect(a.error, isNull);
        final expected =
            (jsonDecode(
                      await File(
                        '../data/bremen/evaluation/schlachte.expected.json',
                      ).readAsString(),
                    )
                    as List)
                .cast<int>()
                .toSet();
        expect(
          a.counts.length,
          greaterThanOrEqualTo((expected.length * 0.6).floor()),
        );
        expect(a.counts.keys.every(expected.contains), isTrue);
        expect(a.counts.values.every((count) => count == 1), isTrue);
        expect(
          await source.mergeWalks([
            WalkCodec.importGpx(gpx),
          ], deduplicateTrace: true),
          0,
        );
        final backup = WalkCodec.exportBackup(await source.listSaved());
        final restored = WalkCodec.importBackup(backup);
        expect(await target.mergeWalks(restored), 1);
        await b.synchronize(await target.listSaved());
        expect(b.error, isNull);
        expect(b.counts, a.counts);
        expect(await target.mergeWalks(restored), 0);
        await b.synchronize(await target.listSaved());
        expect(b.counts, a.counts);
        final fragmented = SavedWalk(
          0,
          imported.startedAt,
          imported.endedAt,
          imported.status,
          imported.points,
          segmentStarts: [for (var i = 1; i < imported.points.length; i++) i],
        );
        final fragmentResult = await matchBatchInBackground(network, [
          WalkCodec.exportGpx(fragmented),
        ]);
        expect(
          fragmentResult.single.walked,
          isEmpty,
          reason: 'Separate singleton GPX segments must never be connected',
        );
        final fresh = CoverageController(
          store: target,
          loadNetwork: () async => network,
        );
        await fresh.initialize();
        expect(fresh.counts, a.counts);
        fresh.dispose();
      } finally {
        a.dispose();
        b.dispose();
        await source.close();
        await target.close();
        await dir.delete(recursive: true);
      }
    },
    skip: Platform.environment['WANDERLUST_NATIVE_TESTS'] != '1'
        ? 'Requires host Rust library; enabled in CI.'
        : false,
  );

  test(
    'recorded Bremen walk passes real Rust FFI and persists idempotent counts',
    () async {
      final dir = await Directory.systemTemp.createTemp('wanderlust-native-');
      final path = '${dir.path}/walks.db';
      var store = SqliteWalkStore(
        factory: databaseFactoryFfi,
        databasePath: path,
      );
      final source = FakeLocation();
      final recorder = WalkRecorder(location: source, store: store);
      final network = await File(
        'assets/geo/bremen-center.streets.geojson',
      ).readAsString();
      var coverage = CoverageController(
        store: store,
        loadNetwork: () async => network,
      );
      final gpx = await File(
        '../data/bremen/evaluation/schlachte.synthetic.gpx',
      ).readAsString();
      final expected =
          (jsonDecode(
                    await File(
                      '../data/bremen/evaluation/schlachte.expected.json',
                    ).readAsString(),
                  )
                  as List)
              .cast<int>()
              .toSet();
      // This regex reads our fixed generated fixture, not user-supplied GPX.
      final points =
          RegExp(r'<trkpt lon="([^"]+)" lat="([^"]+)"><time>([^<]+)</time>')
              .allMatches(gpx)
              .map(
                (m) => Position(
                  longitude: double.parse(m[1]!),
                  latitude: double.parse(m[2]!),
                  timestamp: DateTime.parse(m[3]!),
                  accuracy: 3,
                  altitude: 0,
                  altitudeAccuracy: 0,
                  heading: 0,
                  headingAccuracy: 0,
                  speed: 1.3,
                  speedAccuracy: 0,
                ),
              )
              .toList();
      expect(points.length, greaterThan(100));
      await recorder.start();
      for (final point in points) {
        source.stream.add(point);
      }
      await Future<void>.delayed(Duration.zero);
      await recorder.stop();
      await coverage.synchronize(recorder.savedWalks);
      expect(coverage.error, isNull, reason: coverage.error.toString());
      final counts = Map<int, int>.of(coverage.counts);
      expect(
        counts.length,
        greaterThanOrEqualTo((expected.length * 0.6).floor()),
      );
      expect(
        counts.keys.every(expected.contains),
        isTrue,
        reason: 'No phantom streets on clean fixture',
      );
      expect(counts.values.every((count) => count == 1), isTrue);
      // Upgrading matching rules replaces earlier phantom coverage, preserving
      // the raw walk. A new algorithm must not leave v3 counts cached forever.
      final savedWalk = recorder.savedWalks.single;
      final oldFingerprint = sha256
          .convert(
            utf8.encode(
              'consecutive-observations-osm-v3\n${WalkCodec.exportGpx(savedWalk)}',
            ),
          )
          .toString();
      final phantom = coverage.network!.edgeIds.firstWhere(
        (id) => !expected.contains(id),
      );
      await store.replaceWalkMatch(
        savedWalk.id,
        coverage.network!.version,
        oldFingerprint,
        {...counts.keys, phantom},
      );
      expect(
        (await store.readCounts(
          coverage.network!.version,
        )).containsKey(phantom),
        isTrue,
      );
      await coverage.synchronize(recorder.savedWalks);
      expect(coverage.counts, counts);
      expect((await store.listSaved()).single.points.length, points.length);
      // A second distinct walk increments once; no per-GPS-fix counting.
      await recorder.start();
      for (final point in points) {
        source.stream.add(point);
      }
      await Future<void>.delayed(Duration.zero);
      await recorder.stop();
      await coverage.synchronize(recorder.savedWalks);
      expect(coverage.counts, {for (final id in counts.keys) id: 2});
      coverage.dispose();
      recorder.dispose();
      await source.stream.close();
      // Recorder's asynchronous close drains first; explicit close is idempotent.
      await store.close();
      store = SqliteWalkStore(factory: databaseFactoryFfi, databasePath: path);
      coverage = CoverageController(
        store: store,
        loadNetwork: () async => network,
      );
      await coverage.initialize();
      expect(coverage.counts, {for (final id in counts.keys) id: 2});
      await coverage.synchronize(await store.recoverAndList());
      expect(coverage.counts, {for (final id in counts.keys) id: 2});
      coverage.dispose();
      await store.close();
      await dir.delete(recursive: true);
    },
    skip: Platform.environment['WANDERLUST_NATIVE_TESTS'] != '1'
        ? 'Requires cargo build --release -p geo-ffi and LD_LIBRARY_PATH=../target/release; enabled in CI.'
        : false,
  );
}
