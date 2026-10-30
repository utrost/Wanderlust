import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wanderlust/geo/geo_core_ffi.dart';
import 'package:wanderlust/maps/map_cells.dart';
import 'package:wanderlust/recording/walk_store.dart';
import 'package:wanderlust/widgets/map_location_control.dart';
import 'recording_test.dart' show fix;

Map<String, dynamic> edge(
  int id,
  int from,
  int to,
  List<List<double>> points,
) => {
  'type': 'Feature',
  'id': id,
  'properties': {'from_node': from, 'to_node': to},
  'geometry': {'type': 'LineString', 'coordinates': points},
};
String source(String version, String date, List<Map<String, dynamic>> edges) =>
    jsonEncode({
      'type': 'FeatureCollection',
      'bbox': [8.79, 53.09, 8.82, 53.12],
      'features': edges,
      'wanderlust_network': {
        'version': 1,
        'network_version': version,
        'area_id': version,
        'name': version,
        'osm_base': date,
        'attribution': 'test',
      },
    });
void main() {
  sqfliteFfiInit();
  final old = source('old', '2026-01-01T00:00:00Z', [
    edge(1, 1, 2, [
      [8.8, 53.1],
      [8.801, 53.1],
    ]),
    edge(2, 2, 3, [
      [8.801, 53.1],
      [8.802, 53.1],
    ]),
    edge(3, 4, 5, [
      [8.801, 53.10001],
      [8.801, 53.101],
    ]),
  ]);
  final fresh = source('new', '2026-02-01T00:00:00Z', [
    edge(1, 1, 2, [
      [8.8, 53.1],
      [8.801, 53.10001],
    ]),
  ]);
  test(
    'newest nodes repair old-only neighbours without merging bridge identities',
    () {
      final a = mergeCellSources('cell', [old, fresh]);
      expect(a, mergeCellSources('cell', [fresh, old]));
      final f = (jsonDecode(a)['features'] as List);
      final retained = f.firstWhere((e) => e['id'] == 2);
      expect(retained['geometry']['coordinates'][0], [8.801, 53.10001]);
      expect(retained['properties']['from_node'], 2);
      expect(f.firstWhere((e) => e['id'] == 3)['properties']['from_node'], 4);
      if (Platform.environment['WANDERLUST_NATIVE_TESTS'] == '1') {
        final geo = WanderlustGeo.open();
        geo.loadNetwork(a).dispose();
        final bad = source('bad', '', [
          edge(1, 1, 2, [
            [8.8, 53.1],
            [8.801, 53.1],
          ]),
          edge(2, 2, 3, [
            [8.801, 53.10001],
            [8.802, 53.1],
          ]),
        ]);
        expect(
          () => geo.loadNetwork(bad),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'detail',
              contains('inconsistent coordinates'),
            ),
          ),
        );
      }
    },
  );
  test('newer refined parent replaces obsolete tail sections', () {
    final a = edge(11, 1, 2, [
      [8.8, 53.1],
      [8.801, 53.1],
    ]);
    final b = edge(12, 2, 3, [
      [8.801, 53.1],
      [8.802, 53.1],
    ]);
    (a['properties'] as Map)['coverage_parent'] = 100;
    (b['properties'] as Map)['coverage_parent'] = 100;
    final merged = jsonDecode(
      mergeCellSources('cell', [
        source('old', '2026-01-01', [a, b]),
        source('new', '2026-02-01', [a]),
      ]),
    );
    expect((merged['features'] as List).map((e) => e['id']), [11]);
  });
  test(
    'compressed cells retain geometry and decoded budgets across restart',
    () async {
      final dir = await Directory.systemTemp.createTemp('map-compression-');
      var store = SqliteWalkStore(
        factory: databaseFactoryFfi,
        databasePath: '${dir.path}/db',
      );
      try {
        await store.saveArea(old);
        while (await store.indexNext(null)) {}
        final cells = await store.listCells();
        final decoded = cells.fold<int>(0, (n, c) => n + c.bytes);
        expect((await store.listAreas()).single.cacheBytes, lessThan(decoded));
        final before = <String, String>{};
        for (final c in cells) {
          before[c.cell] = (await store.readCell(c.cell))!;
        }
        final db = await store.database.database;
        expect(
          (await db.rawQuery(
            'SELECT DISTINCT typeof(geojson) AS type, encoding FROM map_cell',
          )).single,
          {'type': 'blob', 'encoding': 1},
        );
        await store.close();
        store = SqliteWalkStore(
          factory: databaseFactoryFfi,
          databasePath: '${dir.path}/db',
        );
        for (final c in cells) {
          expect(await store.readCell(c.cell), before[c.cell]);
        }
        expect(await store.readArea('old'), old);
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'v2 cache migration preserves sources and GPS while clearing obsolete analysis',
    () async {
      final dir = await Directory.systemTemp.createTemp('map-v2-upgrade-');
      final path = '${dir.path}/db';
      var store = SqliteWalkStore(
        factory: databaseFactoryFfi,
        databasePath: path,
      );
      try {
        await store.saveArea(old);
        while (await store.indexNext(null)) {}
        final db = await store.database.database;
        await db.insert('recorded_walk', {
          'id': 1,
          'started_at': '2026-01-01T00:00:00Z',
          'status': 'completed',
        });
        await db.insert('recorded_point', {
          'walk_id': 1,
          'seq': 0,
          'position': jsonEncode(fix(1).toJson()),
          'timestamp': fix(1).timestamp.toIso8601String(),
        });
        await store.saveAnalysisStamp('obsolete-cell', 'old');
        // Reconstruct the previous cache schema; payloads need not survive the
        // migration, but source maps and journal rows must remain byte-for-byte.
        await db.execute('ALTER TABLE map_cell DROP COLUMN encoding');
        await db.setVersion(2);
        await store.close();
        store = SqliteWalkStore(
          factory: databaseFactoryFfi,
          databasePath: path,
        );
        expect(await store.readArea('old'), old);
        final upgraded = await store.database.database;
        expect(await upgraded.query('recorded_point'), hasLength(1));
        expect(await store.listCells(), isEmpty);
        expect((await store.analysisStamps())['obsolete-cell'], isNull);
        while (await store.indexNext(null)) {}
        expect(await store.listCells(), isNotEmpty);
        expect((await store.listAreas()).single.cacheBytes, greaterThan(0));
        await store.close();
        store = SqliteWalkStore(
          factory: databaseFactoryFfi,
          databasePath: path,
        );
        expect(await store.listCells(), isNotEmpty);
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  testWidgets(
    'saved footprints suppress window warnings and retain distant gaps',
    (tester) async {
      final p = fix(1);
      Future<void> show(List<Rect> boxes) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MapLocationControl(
                position: p,
                footprints: boxes,
                error: null,
                locating: false,
                showGps: false,
                onDetails: () {},
                onMaps: () {},
              ),
            ),
          ),
        );
      }

      final point = Offset(p.longitude, p.latitude);
      await show([Rect.fromCenter(center: point, width: .1, height: .1)]);
      expect(find.text('Map needed here'), findsNothing);
      expect(find.text('Map edge nearby'), findsNothing);
      await show([
        Rect.fromLTWH(point.dx - 1, point.dy - 1, .1, .1),
        Rect.fromLTWH(point.dx + 1, point.dy + 1, .1, .1),
      ]);
      expect(find.text('Map needed here'), findsOneWidget);
    },
  );
}
