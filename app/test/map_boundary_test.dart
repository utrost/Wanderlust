import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wanderlust/coverage/coverage_controller.dart';
import 'package:wanderlust/data/area_network.dart';
import 'package:wanderlust/geo/geo_core_ffi.dart';
import 'package:wanderlust/maps/map_extent.dart';
import 'package:wanderlust/widgets/area_map.dart';
import 'package:wanderlust/widgets/gps_hud.dart';
import 'package:wanderlust/recording/walk_store.dart';
import 'package:wanderlust/transfer/walk_codec.dart';
import 'coverage_test.dart' show networkJson;
import 'recording_test.dart' show fix;

AreaNetwork area(String version, List<double> bbox) {
  final json =
      jsonDecode(networkJson(version: version)) as Map<String, dynamic>;
  json['bbox'] = bbox;
  return AreaNetwork.parse(jsonEncode(json));
}

void main() {
  sqfliteFfiInit();
  final west = area('west', [8.7, 53, 8.76, 53.04]);
  final east = area('east', [8.75, 53, 8.81, 53.04]);

  test('overlap and touching seams are not exposed map boundaries', () {
    const p = Offset(8.759, 53.02);
    expect(MapExtent([west]).distanceToBoundary(p), lessThan(100));
    expect(MapExtent([west, east]).distanceToBoundary(p), greaterThan(2000));
    final touching = area('touching', [8.76, 53, 8.82, 53.04]);
    expect(
      MapExtent([west, touching]).distanceToBoundary(p),
      greaterThan(2000),
    );
    expect(MapExtent([west, east]).contains(const Offset(8.80, 53.02)), isTrue);
    expect(
      MapExtent([west, east]).contains(const Offset(8.82, 53.02)),
      isFalse,
    );
  });

  test('gaps, partial overlap and corners remain exposed', () {
    final northEast = area('ne', [8.75, 53.03, 8.81, 53.07]);
    final extent = MapExtent([west, northEast]);
    expect(extent.contains(const Offset(8.78, 53.02)), isFalse);
    expect(
      extent.distanceToBoundary(const Offset(8.759, 53.02)),
      lessThan(100),
    );
    expect(
      extent.distanceToBoundary(const Offset(8.759, 53.0301)),
      lessThan(100),
    );
    expect(extent.distanceToBoundary(const Offset(8.78, 53.02)), 0);
    expect(MapExtent([]).contains(const Offset(8.75, 53.02)), isFalse);
  });

  testWidgets('warning at outer edge only, hidden for stale fixes', (
    tester,
  ) async {
    Future<void> show(List<AreaNetwork> maps, int age) async {
      final p = Position.fromMap({
        ...fix(1).toJson(),
        'latitude': 53.02,
        'longitude': 8.759,
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GpsHud(
              position: p,
              now: p.timestamp.add(Duration(seconds: age)),
              recording: true,
              locating: false,
              networks: maps,
            ),
          ),
        ),
      );
    }

    await show([west], 0);
    expect(find.textContaining('Offline map edge'), findsOneWidget);
    await show([west, east], 0);
    expect(find.textContaining('Offline map edge'), findsNothing);
    await show([west], 45);
    expect(find.textContaining('Offline map edge'), findsNothing);
    await show([east], 0);
    expect(find.textContaining('Outside saved maps'), findsNothing);
  });

  testWidgets('adjacent layers keep the same camera when GPS crosses a seam', (
    tester,
  ) async {
    Future<void> show(double lon) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AreaMap(
              network: west,
              networks: [west, east],
              counts: const {},
              centerRequest: 1,
              position: Position.fromMap({
                ...fix(1).toJson(),
                'latitude': 53.02,
                'longitude': lon,
              }),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    AreaMapPainter painter() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter)
        .whereType<AreaMapPainter>()
        .single;
    await show(8.759);
    final before = painter().transform!.clone();
    await show(8.77);
    expect(painter().networks, [west, east]);
    expect(painter().transform, before);
    expect(tester.takeException(), isNull);
  });

  test(
    'streets beyond the focused map paint after panning into an adjacent map',
    () async {
      AreaNetwork part(String version, List<double> bbox, int id) {
        final json =
            jsonDecode(networkJson(version: version)) as Map<String, dynamic>;
        json['bbox'] = bbox;
        json['features'] = (json['features'] as List)
            .where((f) => f['id'] == id)
            .toList();
        return AreaNetwork.parse(jsonEncode(json));
      }

      final a = part('a', [8.799, 53.099, 8.801, 53.101], 1);
      final b = part('b', [8.801, 53.099, 8.804, 53.101], 3);
      const size = Size(400, 800);
      final target = mapPoint(a, const Offset(8.8025, 53.1), size);
      final transform = Matrix4.identity()
        ..setTranslationRaw(200 - target.dx, 400 - target.dy, 0);
      final recorder = ui.PictureRecorder();
      AreaMapPainter(
        network: a,
        networks: [a, b],
        counts: const {3: 1},
        transform: transform,
      ).paint(Canvas(recorder), size);
      final picture = recorder.endRecording();
      final image = await picture.toImage(400, 800);
      final bytes = (await image.toByteData())!;
      var painted = 0;
      for (var y = 397; y <= 402; y++) {
        for (var x = 190; x < 210; x++) {
          if (bytes.getUint8((y * 400 + x) * 4 + 3) > 0) painted++;
        }
      }
      expect(painted, greaterThan(10));
      image.dispose();
      picture.dispose();
    },
  );

  test(
    'real Rust matches a walk spanning two maps without counting overlap twice',
    () async {
      String part(String version, List<int> ids) {
        final json =
            jsonDecode(networkJson(version: version)) as Map<String, dynamic>;
        json['features'] = (json['features'] as List)
            .where((f) => ids.contains(f['id']))
            .toList();
        return jsonEncode(json);
      }

      final a = part('a', [1, 2]), b = part('b', [2, 3]);
      final dir = await Directory.systemTemp.createTemp(
        'wanderlust-native-seam-',
      );
      final store = SqliteWalkStore(
        factory: databaseFactoryFfi,
        databasePath: '${dir.path}/walks.db',
      );
      final controller = CoverageController(
        store: store,
        loadNetwork: () async => a,
        loadSavedNetworks: () async => [a, b],
      );
      try {
        final walk = WalkCodec.importGpx(
          '<gpx><trk>'
          '<trkseg><trkpt lat="53.1" lon="8.8002"/><trkpt lat="53.1" lon="8.8004"/></trkseg>'
          '<trkseg><trkpt lat="53.1" lon="8.8012"/><trkpt lat="53.1" lon="8.8014"/></trkseg>'
          '<trkseg><trkpt lat="53.1" lon="8.8022"/><trkpt lat="53.1" lon="8.8024"/></trkseg>'
          '</trk></gpx>',
        );
        await store.mergeWalks([walk]);
        await controller.synchronize(await store.listSaved());
        expect(controller.error, isNull);
        expect(await store.readCounts('a'), {1: 1, 2: 1});
        expect(await store.readCounts('b'), {2: 1, 3: 1});
        expect(controller.counts, {1: 1, 2: 1, 3: 1});
        await controller.synchronize(await store.listSaved());
        expect(controller.counts, {1: 1, 2: 1, 3: 1});
      } finally {
        controller.dispose();
        await store.close();
        await dir.delete(recursive: true);
      }
    },
    skip: Platform.environment['WANDERLUST_NATIVE_TESTS'] != '1',
  );

  test(
    'all maps rematch saved walks; overlap counts distinct walks and deletion removes layer',
    () async {
      final dir = await Directory.systemTemp.createTemp('wanderlust-atlas-');
      final store = SqliteWalkStore(
        factory: databaseFactoryFfi,
        databasePath: '${dir.path}/walks.db',
      );
      var sources = [west.geojson, east.geojson];
      var calls = 0;
      final controller = CoverageController(
        store: store,
        loadNetwork: () async => west.geojson,
        loadSavedNetworks: () async => sources,
        match: (_, walks) async {
          calls++;
          return [
            for (final _ in walks)
              const MatchResult(walked: [1], gapsFilled: 0, gapsRejected: 0),
          ];
        },
      );
      try {
        for (var i = 0; i < 2; i++) {
          final id = await store.begin(fix(i).timestamp);
          await store.append(id, 0, fix(i + 1));
          await store.finish(id, fix(i + 2).timestamp, 'completed');
        }
        final walks = await store.listSaved();
        await controller.synchronize(walks);
        expect(controller.error, isNull);
        expect(calls, 2);
        expect(controller.networks, hasLength(2));
        expect(controller.counts, {1: 2}); // Four matches, two actual walks.
        await controller.synchronize(walks);
        expect(calls, 2);
        // Different maps may confirm different walks on the same edge.
        await store.replaceWalkMatch(walks[0].id, west.version, 'a', {2});
        await store.replaceWalkMatch(walks[1].id, east.version, 'b', {2});
        expect(await store.readCombinedCounts([west.version, east.version]), {
          1: 2,
          2: 2,
        });
        sources = [west.geojson];
        await controller.refreshMaps();
        expect(controller.networks, hasLength(1));
        expect(controller.counts, {1: 1, 2: 1});
        expect(await store.listSaved(), hasLength(2));
        // A failed cache read cannot persist a different selected map.
        sources = ['invalid'];
        var persisted = false;
        expect(
          await controller.useNetwork(
            east.geojson,
            persistSelection: () async {
              persisted = true;
            },
          ),
          isFalse,
        );
        expect(persisted, isFalse);
        expect(controller.network!.version, west.version);
        expect(controller.networks, hasLength(1));
      } finally {
        controller.dispose();
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
