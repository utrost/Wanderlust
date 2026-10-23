import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wanderlust/coverage/coverage_controller.dart';
import 'package:wanderlust/data/area_network.dart';
import 'package:wanderlust/geo/geo_core_ffi.dart';
import 'package:wanderlust/recording/walk_store.dart';
import 'recording_test.dart' show fix;

String networkJson({String version = 'test-v1'}) => jsonEncode({
  'type': 'FeatureCollection',
  'bbox': [8.7, 53.0, 8.9, 53.2],
  'wanderlust_network': {
    'version': 1,
    'area_id': 'test',
    'name': 'Test area',
    'network_version': version,
    'attribution': 'Test',
  },
  'features': [
    for (final id in [1, 2, 3])
      {
        'type': 'Feature',
        'id': id,
        'properties': {'from_node': id, 'to_node': id + 1},
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            [8.8 + (id - 1) * 0.001, 53.1],
            [8.8 + id * 0.001, 53.1],
          ],
        },
      },
  ],
});

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late SqliteWalkStore store;
  late String file;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('wanderlust-coverage-');
    file = '${directory.path}/walks.db';
    store = SqliteWalkStore(factory: databaseFactoryFfi, databasePath: file);
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  Future<int> walk({bool empty = false}) async {
    final id = await store.begin(fix(0).timestamp);
    if (!empty) await store.append(id, 0, fix(1));
    await store.finish(id, fix(5).timestamp, 'completed');
    return id;
  }

  test(
    'GPS trails survive restart, avoid double street credit and disappear on removal',
    () async {
      final id = await store.begin(fix(0).timestamp);
      await store.append(id, 0, fix(1));
      await store.append(id, 1, fix(2));
      await store.finish(id, fix(3).timestamp, 'completed');
      var calls = 0;
      CoverageController create() => CoverageController(
        store: store,
        loadNetwork: () async => networkJson(),
        match: (_, traces) async {
          calls++;
          return [
            for (final _ in traces)
              const MatchResult(
                walked: [1],
                unmatched: [1],
                gapsFilled: 0,
                gapsRejected: 0,
              ),
          ];
        },
      );
      var controller = create();
      try {
        final walks = await store.listSaved();
        await controller.synchronize(walks);
        expect(controller.unmatchedTrails.single, hasLength(2));
        expect(controller.counts, {1: 1});
        await controller.synchronize(walks);
        expect(calls, 1);
        controller.dispose();
        await controller.settled;
        controller = create();
        await controller.synchronize(walks);
        expect(calls, 1);
        expect(controller.unmatchedTrails.single, hasLength(2));
        expect(controller.counts, {1: 1});
        await controller.synchronize([]);
        expect(controller.unmatchedTrails, isEmpty);
      } finally {
        controller.dispose();
        await controller.settled;
      }
    },
  );

  test(
    'counts are once per walk, replace atomically, and survive reopen',
    () async {
      final network = AreaNetwork.parse(networkJson());
      await store.registerNetwork(network);
      final a = await walk();
      final b = await walk();
      await store.replaceWalkMatch(a, network.version, 'a', {1, 2});
      await store.replaceWalkMatch(a, network.version, 'a', {1, 2});
      await store.replaceWalkMatch(b, network.version, 'b', {2, 3});
      expect(await store.readCounts(network.version), {1: 1, 2: 2, 3: 1});
      await store.replaceWalkMatch(a, network.version, 'changed', {3});
      expect(await store.readCounts(network.version), {2: 1, 3: 2});
      await expectLater(
        store.replaceWalkMatch(a, network.version, 'bad', {999}),
        throwsA(isA<DatabaseException>()),
      );
      expect(await store.readCounts(network.version), {2: 1, 3: 2});
      expect(await store.matchFingerprint(a, network.version), 'changed');
      await store.close();
      store = SqliteWalkStore(factory: databaseFactoryFfi, databasePath: file);
      expect(await store.readCounts(network.version), {2: 1, 3: 2});
    },
  );

  test('network versions cannot accidentally reuse counts', () async {
    final a = AreaNetwork.parse(networkJson());
    final b = AreaNetwork.parse(networkJson(version: 'test-v2'));
    await store.registerNetwork(a);
    await store.registerNetwork(b);
    final id = await walk();
    await store.replaceWalkMatch(id, a.version, 'one', {1});
    expect(await store.readCounts(b.version), isEmpty);
    await store.replaceWalkMatch(id, b.version, 'two', {2});
    expect(await store.readCounts(a.version), {1: 1});
    expect(await store.readCounts(b.version), {2: 1});
  });

  test('active walks cannot be counted', () async {
    final network = AreaNetwork.parse(networkJson());
    await store.registerNetwork(network);
    final id = await store.begin(fix(0).timestamp);
    await expectLater(
      store.replaceWalkMatch(id, network.version, 'active', {1}),
      throwsStateError,
    );
    expect(await store.readCounts(network.version), isEmpty);
  });

  test(
    'controller serializes refreshes and rematches only changed traces',
    () async {
      final id = await walk();
      var calls = 0;
      final controller = CoverageController(
        store: store,
        loadNetwork: () async => networkJson(),
        match: (network, gpx) async {
          calls++;
          return [
            for (final _ in gpx)
              MatchResult(
                walked: calls == 1 ? [1, 1, 2] : [3],
                gapsFilled: 0,
                gapsRejected: 0,
              ),
          ];
        },
      );
      final saved = await store.recoverAndList();
      await Future.wait([
        controller.synchronize(saved),
        controller.synchronize(saved),
      ]);
      expect(calls, 1);
      expect(controller.counts, {1: 1, 2: 1});
      await store.append(id, 0, fix(2)); // Changed data, same point count.
      await controller.synchronize(await store.recoverAndList());
      expect(calls, 2);
      expect(controller.counts, {3: 1});
      controller.dispose();
    },
  );

  test(
    'matching failure is retryable and never erases existing coverage',
    () async {
      await walk();
      var fail = true;
      final controller = CoverageController(
        store: store,
        loadNetwork: () async => networkJson(),
        match: (network, gpx) async {
          if (fail) {
            throw const CoverageFailure(
              'Native library / ABI unavailable',
              'test',
            );
          }
          return [
            for (final _ in gpx)
              const MatchResult(walked: [2], gapsFilled: 0, gapsRejected: 0),
          ];
        },
      );
      final saved = await store.recoverAndList();
      await controller.synchronize(saved);
      expect(controller.error!.stage, 'Native library / ABI unavailable');
      expect(controller.counts, isEmpty);
      fail = false;
      await controller.synchronize(saved);
      expect(controller.error, isNull);
      expect(controller.counts, {2: 1});
      controller.dispose();
    },
  );

  test(
    'empty and outside-area walks complete without invented streets',
    () async {
      await walk(empty: true);
      await walk();
      var calls = 0;
      final controller = CoverageController(
        store: store,
        loadNetwork: () async => networkJson(),
        match: (network, gpx) async {
          calls++;
          expect(gpx, hasLength(1));
          return [
            const MatchResult(walked: [], gapsFilled: 0, gapsRejected: 0),
          ];
        },
      );
      final saved = await store.recoverAndList();
      await controller.synchronize(saved);
      await controller.synchronize(saved);
      expect(calls, 1);
      expect(controller.counts, isEmpty);
      expect(controller.error, isNull);
      controller.dispose();
    },
  );

  test('projection preserves north-up and rejects duplicate edge ids', () {
    final area = AreaNetwork.parse(networkJson());
    const size = Size(400, 800);
    expect(
      area.project(const Offset(8.8, 53.2), size).dy,
      lessThan(area.project(const Offset(8.8, 53.0), size).dy),
    );
    final json = jsonDecode(networkJson()) as Map<String, dynamic>;
    (json['features'] as List).add((json['features'] as List).first);
    expect(() => AreaNetwork.parse(jsonEncode(json)), throwsFormatException);
  });
  test(
    'rematching reports real work and completion only after persistence',
    () async {
      await walk();
      final entered = Completer<void>();
      final finish = Completer<List<MatchResult>>();
      final controller = CoverageController(
        store: store,
        loadNetwork: () async => networkJson(),
        match: (_, _) {
          entered.complete();
          return finish.future;
        },
      );
      final saved = await store.listSaved();
      final update = controller.synchronize(saved);
      await entered.future;
      expect(controller.rematching, isTrue);
      expect(controller.routeUpdateRevision, 0);
      finish.complete([
        const MatchResult(walked: [1], gapsFilled: 0, gapsRejected: 0),
      ]);
      await update;
      expect(controller.rematching, isFalse);
      expect(controller.routeUpdateRevision, 1);
      await controller.synchronize(saved);
      expect(controller.routeUpdateRevision, 1);
      controller.dispose();
      await controller.settled;
      final failed = CoverageController(
        store: store,
        loadNetwork: () async => networkJson(version: 'changed'),
        match: (_, _) async => throw StateError('test failure'),
      );
      await failed.synchronize(saved);
      expect(failed.error, isNotNull);
      expect(failed.rematching, isFalse);
      expect(failed.routeUpdateRevision, 0);
      failed.dispose();
      await failed.settled;
    },
  );
}
