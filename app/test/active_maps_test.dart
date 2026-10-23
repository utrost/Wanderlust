import 'package:wanderlust/geo/geo_core_ffi.dart';
import 'package:wanderlust/blocks/block_geometry.dart';
import 'package:wanderlust/transfer/backup_archive.dart';
import 'blocks_test.dart' as block_fixture;
import 'coverage_sections_test.dart' show longStreet;
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wanderlust/maps/active_maps.dart';
import 'package:wanderlust/maps/map_cells.dart';
import 'package:wanderlust/recording/walk_store.dart';
import 'package:wanderlust/data/area_network.dart';
import 'coverage_test.dart' show networkJson;

String nearby(String name, Offset center) {
  final j = jsonDecode(networkJson(version: name)) as Map<String, dynamic>;
  j['bbox'] = [
    center.dx - .005,
    center.dy - .005,
    center.dx + .005,
    center.dy + .005,
  ];
  for (final f in j['features'] as List) {
    for (final p in f['geometry']['coordinates'] as List) {
      p[0] = (p[0] as num) - 8.8 + center.dx;
      p[1] = (p[1] as num) - 53.1 + center.dy;
    }
  }
  return jsonEncode(j);
}

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late SqliteWalkStore store;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('active-maps-');
    store = SqliteWalkStore(
      factory: databaseFactoryFfi,
      databasePath: '${dir.path}/db',
    );
  });
  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });

  test(
    'saved library exceeds eight maps; windows keep distant recording data',
    () async {
      const home = Offset(8.8, 53.1), away = Offset(13.4, 52.5);
      for (var i = 0; i < 12; i++) {
        await store.saveArea(nearby('home-$i', home));
      }
      await store.saveArea(nearby('away', away));
      await store.selectArea('home-0');
      final active = ActiveMaps(store);
      await active.initialize();
      await active.settled;
      expect(active.error, isNull, reason: active.failure.toString());
      expect(active.library, hasLength(13));
      expect(active.networks, isNotEmpty);
      expect(active.networks.every((m) => m.bbox[0] < 10), isTrue);
      active.position(home);
      await active.select('away');
      expect(active.error, isNull, reason: active.failure.toString());
      expect(active.networks.any((m) => m.bbox[0] < 10), isTrue);
      expect(active.networks.any((m) => m.bbox[0] > 12), isTrue);
      active.position(null);
      await active.settled;
      expect(active.networks.every((m) => m.bbox[0] > 12), isTrue);
      await active.select('home-0');
      expect(active.networks.every((m) => m.bbox[0] < 10), isTrue);
      expect(await store.listAreas(), hasLength(13));
      active.dispose();
    },
  );

  test(
    'cell partition preserves section identities and deduplicates overlaps',
    () {
      final source = nearby('home', const Offset(8.8, 53.1));
      final expected = AreaNetwork.parse(source).edgeIds;
      final chunks = indexMapCells(source).toList();
      final actual = <int>{};
      for (final c in chunks) {
        final merged = AreaNetwork.parse(
          mergeCellSources(c['cell'] as String, [
            c['geojson'] as String,
            c['geojson'] as String,
          ]),
        );
        actual.addAll(merged.edgeIds);
        expect(merged.edges.length, merged.edgeIds.length);
      }
      expect(actual, expected);
    },
  );

  test('interrupted index remains invisible until rebuilt', () async {
    await store.saveArea(nearby('home', const Offset(8.8, 53.1)));
    final db = await store.database.database;
    final chunk = indexMapCells((await store.readArea('home'))!).first;
    await db.insert('map_cell', chunk);
    expect(await store.listCells(), isEmpty);
    await store.indexNext(const Offset(8.8, 53.1));
    expect(await store.listCells(), isNotEmpty);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });
  test(
    '100 saved locations stay bounded, constrained budgets defer streets safely',
    () async {
      for (var i = 0; i < 100; i++) {
        await store.saveArea(nearby('town-$i', Offset(8 + i * .04, 53)));
      }
      await store.selectArea('town-0');
      final active = ActiveMaps(store, cellBudget: 4);
      await active.refresh();
      expect(active.error, isNull, reason: active.failure.toString());
      expect(active.library, hasLength(100));
      final backup = File('${dir.path}/library.wanderlust');
      await BackupArchive.write(backup, store.backupData, BackupProgress());
      final staging = await Directory('${dir.path}/stage').create();
      final archive = await BackupArchive.read(
        backup,
        staging,
        BackupProgress(),
      );
      expect(archive.mapFiles, hasLength(100));
      expect(
        archive.metadata.maps,
        isEmpty,
        reason: 'Map documents are streamed, not retained together',
      );
      expect(await archive.maps().length, 100);

      expect(active.networks.length, lessThanOrEqualTo(4));
      expect(active.loadedBytes, lessThanOrEqualTo(ActiveMaps.maxBytes));
      expect(active.loadedSections, lessThanOrEqualTo(ActiveMaps.maxSections));
      final before = active.networks;
      active.gestureStarted();
      await active.refresh();
      expect(identical(before, active.networks), isTrue);
      active.dispose();
      final constrained = ActiveMaps(store, sectionBudget: 1);
      await constrained.refresh();
      expect(constrained.loadedSections, lessThanOrEqualTo(1));
      expect(constrained.limited, isTrue);
      expect(await store.listAreas(), hasLength(100));
      constrained.dispose();
    },
  );
  test('buffered cells preserve native matching across kilometre boundaries', () {
    final json = jsonDecode(longStreet()) as Map<String, dynamic>;
    json['bbox'] = [-.005, -.005, .035, .005];
    json['features'][0]['geometry']['coordinates'] = [
      [0.0, 0.0],
      [.03, 0.0],
    ];
    final map = AreaNetwork.parse(jsonEncode(json));
    final gpx =
        '<gpx><trk><trkseg>${[for (var i = 0; i <= 300; i++) '<trkpt lon="${i * .0001}" lat="0"><time>${DateTime.utc(2026, 1, 1).add(Duration(seconds: i * 8)).toIso8601String()}</time></trkpt>'].join()}</trkseg></trk></gpx>';
    final geo = WanderlustGeo.open();
    final whole = geo.loadNetwork(map.geojson);
    final expected = whole.matchGpx(gpx).walked.toSet();
    whole.dispose();
    final actual = <int>{};
    for (final cell in indexMapCells(map.geojson)) {
      final source = mergeCellSources(cell['cell'] as String, [
        cell['geojson'] as String,
      ]);
      if (AreaNetwork.parse(source).edges.isEmpty) continue;
      final matcher = geo.loadNetwork(source);
      actual.addAll(matcher.matchGpx(gpx).walked);
      matcher.dispose();
    }
    expect(expected, isNotEmpty);
    expect(actual, expected);
  }, skip: Platform.environment['WANDERLUST_NATIVE_TESTS'] != '1');

  test(
    'a block crossing a cell boundary has the same identity in overlapping windows',
    () {
      final features = block_fixture.square(size: 250);
      for (final f in features) {
        for (final point in ((f['geometry'] as Map)['coordinates'] as List)) {
          point[0] = (point[0] as num) + .0085;
        }
      }
      final map = block_fixture.network(
        features,
        bbox: [-.01, -.01, .025, .015],
      );
      final whole = buildBlockTopology([map]);
      final ids = <String>{};
      for (final c in indexMapCells(map.geojson)) {
        final parsed = AreaNetwork.parse(
          mergeCellSources(c['cell'] as String, [c['geojson'] as String]),
        );
        ids.addAll(buildBlockTopology([parsed]).blocks.map((b) => b.id));
      }
      expect(whole.blocks, hasLength(1));
      expect(ids, {whole.blocks.single.id});
    },
  );
}
