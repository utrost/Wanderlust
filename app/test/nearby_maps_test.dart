import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wanderlust/coverage/coverage_controller.dart';
import 'package:wanderlust/data/area_network.dart';
import 'package:wanderlust/geo/geo_core_ffi.dart';
import 'package:wanderlust/maps/map_download.dart';
import 'package:wanderlust/maps/osm_network.dart';
import 'package:wanderlust/recording/walk_store.dart';
import 'package:wanderlust/transfer/walk_codec.dart';

import 'coverage_test.dart' show networkJson;
import 'recording_test.dart' show fix;

const smallOsm = '''<osm><meta osm_base="2026-09-26T00:00:00Z"/>
<node id="1" lon="8.8000" lat="53.1000"/>
<node id="2" lon="8.8002" lat="53.1000"/>
<node id="3" lon="8.8004" lat="53.1000"/>
<node id="4" lon="8.8002" lat="53.1002"/>
<way id="10"><nd ref="1"/><nd ref="2"/><nd ref="3"/><tag k="highway" v="footway"/><tag k="name" v="Example path"/></way>
<way id="11"><nd ref="2"/><nd ref="4"/><tag k="highway" v="residential"/></way></osm>''';

String smallNetwork() => OsmNetwork.normalize(
  smallOsm,
  [8.79, 53.09, 8.81, 53.11],
  areaId: 'example',
  name: 'Example area',
);

void main() {
  sqfliteFfiInit();
  test(
    'mobile builder reproduces all bundled Bremen edge IDs and geometry',
    () {
      final xml = utf8.decode(
        gzip.decode(File('../data/bremen/source.osm.gz').readAsBytesSync()),
      );
      final bundled =
          jsonDecode(
                File(
                  'assets/geo/bremen-center.streets.geojson',
                ).readAsStringSync(),
              )
              as Map;
      final generated =
          jsonDecode(
                OsmNetwork.normalize(
                  xml,
                  (bundled['bbox'] as List).cast<double>(),
                  areaId: 'bremen-center',
                  name: 'Bremen center',
                ),
              )
              as Map;
      final expected = {
        for (final f in bundled['features'] as List) f['id']: f['geometry'],
      };
      final actual = {
        for (final f in generated['features'] as List) f['id']: f['geometry'],
      };
      expect(actual, expected);
      expect(actual.length, 7930);
    },
  );

  test(
    'junction segmentation and IDs are stable across direction and input order',
    () {
      final a = jsonDecode(smallNetwork()) as Map;
      final reverse = smallOsm.replaceFirst(
        '<nd ref="1"/><nd ref="2"/><nd ref="3"/>',
        '<nd ref="3"/><nd ref="2"/><nd ref="1"/>',
      );
      final b =
          jsonDecode(
                OsmNetwork.normalize(
                  reverse,
                  [8.79, 53.09, 8.81, 53.11],
                  areaId: 'example',
                  name: 'Example area',
                ),
              )
              as Map;
      expect(a['features'], b['features']);
      expect(
        a['wanderlust_network']['network_version'],
        b['wanderlust_network']['network_version'],
      );
      expect(a['features'], hasLength(3));
    },
  );

  test(
    'restricted access, barriers and incomplete responses never create streets',
    () {
      expect(OsmNetwork.excluded({'highway': 'motorway'}), isTrue);
      expect(
        OsmNetwork.excluded({'highway': 'path', 'access': 'private'}),
        isTrue,
      );
      expect(
        OsmNetwork.excluded({
          'highway': 'path',
          'access': 'private',
          'foot': 'yes',
        }),
        isFalse,
      );
      expect(OsmNetwork.excluded({'highway': 'cycleway'}), isTrue);
      expect(
        OsmNetwork.excluded({
          'highway': 'footway',
          'foot:conditional': 'yes @ sunny',
        }),
        isTrue,
      );
      expect(OsmNetwork.blockedNode({'barrier': 'wall'}), isTrue);
      for (final xml in [
        '<osm><remark>timeout</remark></osm>',
        smallOsm.replaceFirst('<node id="1" lon="8.8000" lat="53.1000"/>', ''),
        smallOsm.replaceFirst('lon="8.8000"', 'lon="NaN"'),
      ]) {
        expect(
          () => OsmNetwork.normalize(
            xml,
            [8.79, 53.09, 8.81, 53.11],
            areaId: 'test',
            name: 'Test',
          ),
          throwsFormatException,
        );
      }
      final blocked = smallOsm.replaceFirst(
        '<node id="2" lon="8.8002" lat="53.1000"/>',
        '<node id="2" lon="8.8002" lat="53.1000"><tag k="barrier" v="wall"/></node>',
      );
      expect(
        () => OsmNetwork.normalize(
          blocked,
          [8.79, 53.09, 8.81, 53.11],
          areaId: 'test',
          name: 'Test',
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'nearby request spans approximately four km and rejects unsupported coordinates',
    () {
      final area = NearbyArea.around(53.1, 8.8);
      final b = area.bbox;
      expect(OsmNetwork.metres([b[0], 53.1], [b[2], 53.1]), closeTo(4000, 30));
      expect(OsmNetwork.metres([8.8, b[1]], [8.8, b[3]]), closeTo(4000, 30));
      expect(area.query, contains('${b[1]},${b[0]},${b[3]},${b[2]}'));
      expect(area.query, contains('relation["natural"'));
      expect(area.query, contains('(._;>>;)'));
      expect(area.query, contains('waterway'));
      expect(() => NearbyArea.around(double.nan, 8.8), throwsFormatException);
      expect(() => NearbyArea.around(89, 8.8), throwsFormatException);
    },
  );

  test(
    'real HTTP download sends bounded OSM query and normalizes off the UI isolate',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final received = Completer<String>();
      server.listen((request) async {
        received.complete(await utf8.decoder.bind(request).join());
        request.response.headers.contentType = ContentType(
          'application',
          'xml',
        );
        request.response.write(smallOsm);
        await request.response.close();
      });
      final download = MapDownload(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}'),
      );
      try {
        final source = await download.fetch(NearbyArea.around(53.1, 8.8));
        expect(AreaNetwork.parse(source).edges, hasLength(3));
        expect(
          Uri.splitQueryString(await received.future)['data'],
          contains('[timeout:45]'),
        );
      } finally {
        download.cancel();
        await server.close(force: true);
      }
    },
  );

  test('busy server produces an actionable retry error', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.statusCode = 429;
      await request.response.close();
    });
    final download = MapDownload(
      endpoint: Uri.parse('http://127.0.0.1:${server.port}'),
    );
    try {
      await expectLater(
        download.fetch(NearbyArea.around(53.1, 8.8)),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('busy'),
          ),
        ),
      );
    } finally {
      download.cancel();
      await server.close(force: true);
    }
  });

  test(
    'offline maps and selection survive restart, replacing and deleting are safe',
    () async {
      final dir = await Directory.systemTemp.createTemp('wanderlust-maps-');
      SqliteWalkStore open() => SqliteWalkStore(
        factory: databaseFactoryFfi,
        databasePath: '${dir.path}/walks.db',
      );
      var store = open();
      try {
        final source = smallNetwork();
        final area = AreaNetwork.parse(source);
        await store.saveArea(source);
        await store.selectArea(area.version);
        await store.saveArea(source); // Must not clear selection via REPLACE.
        expect(await store.readActiveArea(), source);
        await expectLater(store.saveArea('{}'), throwsA(anything));
        expect(await store.readActiveArea(), source);
        await store.close();
        store = open();
        expect(await store.readActiveArea(), source);
        expect(await store.listAreas(), hasLength(1));
        await expectLater(
          store.selectArea('missing'),
          throwsA(isA<DatabaseException>()),
        );
        expect(await store.readActiveArea(), source);
        await store.deleteArea(area.version);
        expect(await store.readActiveArea(), isNull);
        expect(await store.listAreas(), isEmpty);
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'large downloaded map reads in chunks, survives restart and activates with Unicode intact',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'wanderlust-large-map-',
      );
      SqliteWalkStore open() => SqliteWalkStore(
        factory: databaseFactoryFfi,
        databasePath: '${dir.path}/walks.db',
      );
      var store = open();
      final data = jsonDecode(smallNetwork()) as Map<String, dynamic>;
      // Multi-byte characters straddle SQL substring boundaries. SQLite indexes
      // code points, whereas Dart String.length counts UTF-16 code units.
      data['test_padding'] = List.filled(400000, 'Straße🌍').join();
      final source = jsonEncode(data);
      expect(utf8.encode(source).length, greaterThan(4 * 1024 * 1024));
      final area = AreaNetwork.parse(source);
      CoverageController? controller;
      try {
        await store.saveArea(source);
        await store.selectArea(area.version);
        await store.close();
        store = open();
        expect(await store.readArea(area.version), source);
        expect(await store.readActiveArea(), source);
        expect(await store.readArea('missing'), isNull);
        controller = CoverageController(
          store: store,
          loadNetwork: () async => (await store.readActiveArea())!,
          loadSavedNetworks: () async => [
            for (final a in await store.listAreas())
              (await store.readArea(a.version))!,
          ],
        );
        await controller.initialize();
        expect(controller.error, isNull);
        expect(controller.network!.version, area.version);
        expect(controller.networks.single.geojson, source);
      } finally {
        controller?.dispose();
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'v3 walk database upgrades to offline-map storage without changing walks',
    () async {
      final dir = await Directory.systemTemp.createTemp('wanderlust-v3-');
      final path = '${dir.path}/walks.db';
      var store = SqliteWalkStore(
        factory: databaseFactoryFfi,
        databasePath: path,
      );
      try {
        final id = await store.begin(fix(0).timestamp);
        await store.append(id, 0, fix(1));
        await store.finish(id, fix(2).timestamp, 'completed');
        final before = (await store.listSaved()).single.toBackup();
        await store.close();
        final db = await databaseFactoryFfi.openDatabase(path);
        await db.execute('DROP TABLE walk_preferences');
        await db.execute('DROP TABLE offline_selection');
        await db.execute('DROP TABLE offline_area');
        await db.execute('PRAGMA user_version = 3');
        await db.close();
        store = SqliteWalkStore(
          factory: databaseFactoryFfi,
          databasePath: path,
        );
        expect((await store.listSaved()).single.toBackup(), before);
        expect(await store.listAreas(), isEmpty);
        await store.saveArea(smallNetwork());
        expect(await store.listAreas(), hasLength(1));
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'network switching waits for old matching and reprocesses saved walks',
    () async {
      final dir = await Directory.systemTemp.createTemp('wanderlust-switch-');
      final store = SqliteWalkStore(
        factory: databaseFactoryFfi,
        databasePath: '${dir.path}/walks.db',
      );
      final gate = Completer<void>();
      final entered = Completer<void>();
      var calls = 0;
      final controller = CoverageController(
        store: store,
        loadNetwork: () async => networkJson(),
        match: (_, walks) async {
          calls++;
          if (calls == 1) {
            entered.complete();
            await gate.future;
          }
          return [
            for (final _ in walks)
              MatchResult(
                walked: [calls == 1 ? 1 : 2],
                gapsFilled: 0,
                gapsRejected: 0,
              ),
          ];
        },
      );
      try {
        final id = await store.begin(fix(0).timestamp);
        await store.append(id, 0, fix(1));
        await store.finish(id, fix(2).timestamp, 'completed');
        final walks = await store.listSaved();
        final pending = controller.synchronize(walks);
        await entered.future;
        final switching = controller.useNetwork(networkJson(version: 'second'));
        expect(controller.network!.version, 'test-v1');
        gate.complete();
        await pending;
        expect(await switching, isTrue);
        expect(await store.readCounts('test-v1'), {1: 1});
        expect(controller.counts, isEmpty);
        await controller.synchronize(walks);
        expect(controller.counts, {2: 1});
        expect(await store.readCounts('test-v1'), {1: 1});
        expect(await controller.useNetwork('{}'), isFalse);
        expect(controller.network!.version, 'second');
        expect(controller.counts, {2: 1});
        expect(
          await controller.useNetwork(
            networkJson(version: 'third'),
            persistSelection: () async {
              throw StateError('disk full');
            },
          ),
          isFalse,
        );
        expect(controller.network!.version, 'second');
      } finally {
        controller.dispose();
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'saved walk paints a newly downloaded network through real Rust',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'wanderlust-native-area-',
      );
      final store = SqliteWalkStore(
        factory: databaseFactoryFfi,
        databasePath: '${dir.path}/walks.db',
      );
      final controller = CoverageController(
        store: store,
        loadNetwork: () async => networkJson(),
      );
      try {
        final walk = WalkCodec.importGpx(
          '<gpx><trk><trkseg><trkpt lat="53.1" lon="8.80005"><time>2026-09-26T12:00:00Z</time></trkpt><trkpt lat="53.1" lon="8.80006"><time>2026-09-26T12:00:05Z</time></trkpt></trkseg></trk></gpx>',
        );
        await store.mergeWalks([walk]);
        final source = smallNetwork();
        await store.saveArea(source);
        final area = AreaNetwork.parse(source);
        expect(
          await controller.useNetwork(
            source,
            persistSelection: () => store.selectArea(area.version),
          ),
          isTrue,
        );
        await controller.synchronize(await store.listSaved());
        expect(controller.error, isNull);
        expect(controller.counts, {
          OsmNetwork.edgeId(10, [1, 2]): 1,
        });
        await controller.synchronize(await store.listSaved());
        expect(controller.counts, {
          OsmNetwork.edgeId(10, [1, 2]): 1,
        });
        expect(await store.readActiveArea(), source);
      } finally {
        controller.dispose();
        await store.close();
        await dir.delete(recursive: true);
      }
    },
    skip: Platform.environment['WANDERLUST_NATIVE_TESTS'] != '1'
        ? 'Requires host Rust library; enabled in CI.'
        : false,
  );

  test(
    'live Bremen outskirts response passes mobile normalization and Rust loading',
    () async {
      final file = Platform.environment['WANDERLUST_LIVE_MAP_XML'];
      if (file == null) return;
      final source = OsmNetwork.normalize(
        await File(file).readAsString(),
        [8.58, 53.15, 8.64, 53.186],
        areaId: 'vegesack-evaluation',
        name: 'Bremen Vegesack',
      );
      final area = AreaNetwork.parse(source);
      expect(area.edges.length, greaterThan(100));
      final geo = WanderlustGeo.open();
      final matcher = geo.loadNetwork(source);
      try {
        final result = matcher.matchGpx(
          '<gpx><trk><trkseg><trkpt lat="53.168" lon="8.61"/><trkpt lat="53.168" lon="8.61"/></trkseg></trk></gpx>',
        );
        expect(result.walked.every(area.edgeIds.contains), isTrue);
        // ignore: avoid_print
        print(
          'Live Vegesack evaluation: ${area.edges.length} edges, ${utf8.encode(source).length} bytes, Rust network accepted.',
        );
      } finally {
        matcher.dispose();
      }
    },
    skip: Platform.environment['WANDERLUST_LIVE_MAP_XML'] == null
        ? 'Optional live endpoint evaluation.'
        : false,
  );
}
