import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wanderlust/coverage/coverage_controller.dart';
import 'package:wanderlust/data/area_network.dart';
import 'package:wanderlust/geo/geo_core_ffi.dart';
import 'package:wanderlust/maps/osm_network.dart';
import 'package:wanderlust/recording/walk_store.dart';
import 'package:wanderlust/screens/settings_screen.dart';
import 'package:wanderlust/settings/walk_preferences.dart';
import 'package:wanderlust/transfer/walk_codec.dart';
import 'package:wanderlust/widgets/area_map.dart';
import 'package:wanderlust/widgets/gps_hud.dart';
import 'coverage_test.dart' show networkJson;
import 'nearby_maps_test.dart' show smallOsm;
import 'recording_test.dart' show fix;

String sceneryXml() => smallOsm.replaceFirst(
  '</osm>',
  '''
<node id="101" lon="8.795" lat="53.095"/><node id="102" lon="8.805" lat="53.095"/>
<node id="103" lon="8.805" lat="53.105"/><node id="104" lon="8.795" lat="53.105"/>
<node id="111" lon="8.797" lat="53.097"/><node id="112" lon="8.803" lat="53.097"/>
<node id="113" lon="8.803" lat="53.103"/><node id="114" lon="8.797" lat="53.103"/>
<node id="121" lon="8.799" lat="53.099"/><node id="122" lon="8.801" lat="53.099"/>
<node id="123" lon="8.801" lat="53.101"/><node id="124" lon="8.799" lat="53.101"/>
<node id="131" lon="8.79" lat="53.107"/><node id="132" lon="8.81" lat="53.107"/>
<way id="100"><nd ref="101"/><nd ref="102"/><nd ref="103"/><nd ref="104"/><nd ref="101"/><tag k="leisure" v="park"/></way>
<way id="110"><nd ref="111"/><nd ref="112"/><nd ref="113"/></way>
<way id="111"><nd ref="111"/><nd ref="114"/><nd ref="113"/></way>
<way id="120"><nd ref="121"/><nd ref="122"/><nd ref="123"/><nd ref="124"/><nd ref="121"/></way>
<way id="130"><nd ref="131"/><nd ref="132"/><tag k="waterway" v="stream"/></way>
<relation id="200"><member type="way" ref="110" role="outer"/><member type="way" ref="111" role="outer"/><member type="way" ref="120" role="inner"/><tag k="type" v="multipolygon"/><tag k="natural" v="water"/></relation></osm>''',
);
String decorated() => OsmNetwork.normalize(
  sceneryXml(),
  [8.79, 53.09, 8.81, 53.11],
  areaId: 'test',
  name: 'Park and water',
);

void main() {
  sqfliteFfiInit();
  test(
    'returning from screen-off matches all unseen fixes, not just last 80',
    () async {
      final dir = await Directory.systemTemp.createTemp('wanderlust-pocket-');
      final store = SqliteWalkStore(
        factory: databaseFactoryFfi,
        databasePath: '${dir.path}/walks.db',
      );
      final batches = <int>[];
      final controller = CoverageController(
        store: store,
        loadNetwork: () async => networkJson(),
        liveInterval: Duration.zero,
        match: (_, traces) async {
          batches.add(WalkCodec.importGpx(traces.single).points.length);
          return [
            const MatchResult(walked: [1], gapsFilled: 0, gapsRejected: 0),
          ];
        },
      );
      SavedWalk snapshot(int length) => SavedWalk(
        1,
        fix(0).timestamp,
        null,
        'recording',
        [for (var i = 0; i < length; i++) fix(i)],
      );
      Future<void> drain() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await controller.settled;
      }

      try {
        controller.updateLive(snapshot(100));
        await drain();
        expect(batches, [100]);
        controller.setPreviewActive(false);
        controller.updateLive(snapshot(300));
        await drain();
        expect(batches, [100]);
        controller.setPreviewActive(true);
        await drain();
        expect(batches, [100, 280]);
        expect(controller.displayCounts, {1: 1});
        expect(controller.counts, isEmpty);
        controller.updateLive(snapshot(301));
        await drain();
        expect(batches.last, 81);
      } finally {
        controller.dispose();
        await controller.settled;
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'preferences default calm, migrate v4 and persist after reopening',
    () async {
      final dir = await Directory.systemTemp.createTemp('wanderlust-settings-');
      final path = '${dir.path}/walks.db';
      SqliteWalkStore open() =>
          SqliteWalkStore(factory: databaseFactoryFfi, databasePath: path);
      var store = open();
      try {
        expect((await store.readPreferences()).showTime, isFalse);
        await store.close();
        final db = await databaseFactoryFfi.openDatabase(path);
        await db.execute('DROP TABLE memory_photo');
        await db.execute('DROP TABLE memory');
        await db.execute('DROP TABLE walk_preferences');
        await db.execute('PRAGMA user_version = 4');
        await db.close();
        store = open();
        expect((await store.readPreferences()).showTime, isFalse);
        await store.savePreferences(
          const WalkPreferences(showTime: true, showSamples: true),
        );
        await store.close();
        store = open();
        expect((await store.readPreferences()).toJson(), {
          'showTime': true,
          'showSamples': true,
          'showGps': false,
          'showStreetNames': true,
          'showMemories': true,
          'detailedGps': false,
          'fillSmallGaps': false,
          'walkedLineWidth': 3.0,
          'mapSizeKm': 4,
        });
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  testWidgets(
    'details are optional and failed preference save leaves switch off',
    (tester) async {
      var failSave = true;
      WalkPreferences? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            initial: const WalkPreferences(),
            diagnostic: const SizedBox(),
            save: (v) async {
              if (failSave) throw StateError('disk full');
              saved = v;
            },
          ),
        ),
      );
      expect(
        tester
            .widgetList<SwitchListTile>(find.byType(SwitchListTile))
            .every((w) => !w.value),
        isTrue,
      );
      await tester.tap(find.text('Show elapsed time'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not save settings'), findsOneWidget);
      expect(saved, isNull);
      failSave = false;
      await tester.tap(find.text('Show elapsed time'));
      await tester.pumpAndSettle();
      expect(saved!.showTime, isTrue);
      await tester.pumpWidget(
        MaterialApp(
          home: GpsHud(
            position: fix(1),
            now: fix(1).timestamp,
            recording: true,
            locating: false,
            details: false,
          ),
        ),
      );
      expect(find.text('Location ready'), findsOneWidget);
      expect(find.textContaining('ago'), findsNothing);
      expect(find.textContaining('53.'), findsNothing);
    },
  );
  test(
    'live matching coalesces updates, deduplicates maps and commits once on save',
    () async {
      final dir = await Directory.systemTemp.createTemp('wanderlust-live-');
      final store = SqliteWalkStore(
        factory: databaseFactoryFfi,
        databasePath: '${dir.path}/walks.db',
      );
      final gate = Completer<void>(), entered = Completer<void>();
      var calls = 0;
      final controller = CoverageController(
        store: store,
        loadNetwork: () async => networkJson(),
        liveInterval: Duration.zero,
        match: (_, traces) async {
          calls++;
          if (calls == 1) {
            entered.complete();
            await gate.future;
          }
          return [
            for (final _ in traces)
              const MatchResult(walked: [1, 2], gapsFilled: 0, gapsRejected: 0),
          ];
        },
      );
      try {
        final id = await store.begin(fix(0).timestamp);
        for (var i = 1; i <= 4; i++) {
          await store.append(id, i - 1, fix(i));
        }
        controller.updateLive(
          SavedWalk(id, fix(0).timestamp, null, 'recording', [fix(1), fix(2)]),
        );
        await entered.future;
        controller.updateLive(
          SavedWalk(id, fix(0).timestamp, null, 'recording', [
            fix(1),
            fix(2),
            fix(3),
          ]),
        );
        controller.updateLive(
          SavedWalk(id, fix(0).timestamp, null, 'recording', [
            fix(1),
            fix(2),
            fix(3),
            fix(4),
          ]),
        );
        gate.complete();
        await controller.settled;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await controller.settled;
        expect(controller.displayCounts, {1: 1, 2: 1});
        expect(controller.counts, isEmpty);
        expect(await store.readCounts('test-v1'), isEmpty);
        expect(calls, 2);
        await store.finish(id, fix(5).timestamp, 'completed');
        await controller.synchronize(await store.listSaved());
        expect(controller.displayCounts, {1: 1, 2: 1});
        expect(controller.counts, {1: 1, 2: 1});
        await controller.synchronize(await store.listSaved());
        expect(controller.displayCounts, {1: 1, 2: 1});
      } finally {
        controller.dispose();
        await controller.settled;
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'late preview from a previous walk is discarded and failures leave saved counts intact',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'wanderlust-preview-race-',
      );
      final store = SqliteWalkStore(
        factory: databaseFactoryFfi,
        databasePath: '${dir.path}/walks.db',
      );
      final gate = Completer<void>(), entered = Completer<void>();
      var calls = 0;
      final controller = CoverageController(
        store: store,
        loadNetwork: () async => networkJson(),
        liveInterval: Duration.zero,
        match: (_, walks) async {
          calls++;
          if (calls == 1) {
            entered.complete();
            await gate.future;
            return [
              const MatchResult(walked: [1], gapsFilled: 0, gapsRejected: 0),
            ];
          }
          if (calls == 2) throw StateError('temporary matcher failure');
          return [
            const MatchResult(walked: [2], gapsFilled: 0, gapsRejected: 0),
          ];
        },
      );
      try {
        controller.updateLive(
          SavedWalk(1, fix(0).timestamp, null, 'recording', [fix(1), fix(2)]),
        );
        await entered.future;
        controller.updateLive(
          SavedWalk(2, fix(0).timestamp, null, 'recording', [fix(1), fix(2)]),
        );
        gate.complete();
        await controller.settled;
        expect(controller.displayCounts, isEmpty);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await controller.settled;
        expect(controller.liveError, isNotNull);
        expect(controller.counts, isEmpty);
        controller.updateLive(
          SavedWalk(2, fix(0).timestamp, null, 'recording', [
            fix(1),
            fix(2),
            fix(3),
          ]),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await controller.settled;
        expect(controller.liveError, isNull);
        expect(controller.displayCounts, {2: 1});
        controller.dispose();
        await controller.settled;
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'scenery preserves street identities, joins multipolygons and rejects incomplete rings',
    () {
      final source = jsonDecode(decorated()) as Map;
      final streets =
          jsonDecode(
                OsmNetwork.normalize(
                  smallOsm,
                  [8.79, 53.09, 8.81, 53.11],
                  areaId: 'test',
                  name: 'Park and water',
                ),
              )
              as Map;
      expect(source['features'], streets['features']);
      expect(
        source['wanderlust_network']['network_version'],
        streets['wanderlust_network']['network_version'],
      );
      final map = AreaNetwork.parse(decorated());
      expect(map.scenery.map((s) => s.kind).toSet(), {
        'park',
        'water',
        'waterway',
      });
      expect(
        map.scenery.singleWhere((s) => s.kind == 'water').paths,
        hasLength(2),
      );
      final broken = OsmNetwork.normalize(
        sceneryXml().replaceFirst(
          'ref="111" role="outer"',
          'ref="999" role="outer"',
        ),
        [8.79, 53.09, 8.81, 53.11],
        areaId: 'test',
        name: 'test',
      );
      expect(
        AreaNetwork.parse(broken).scenery.where((s) => s.kind == 'water'),
        isEmpty,
      );
    },
  );
  test('park, water and island holes paint below streets', () async {
    final network = AreaNetwork.parse(decorated());
    const size = Size(600, 800);
    final recorder = ui.PictureRecorder();
    AreaMapPainter(
      network: network,
      counts: const {},
    ).paint(Canvas(recorder), size);
    final picture = recorder.endRecording(),
        image = await picture.toImage(600, 800);
    final bytes = (await image.toByteData())!;
    List<int> pixel(Offset coordinate) {
      final p = mapPoint(network, coordinate, size),
          i = (p.dy.round() * 600 + p.dx.round()) * 4;
      return [for (var j = 0; j < 4; j++) bytes.getUint8(i + j)];
    }

    expect(pixel(const Offset(8.7955, 53.0955)), [220, 228, 210, 255]);
    expect(pixel(const Offset(8.798, 53.098)), [196, 218, 226, 255]);
    expect(pixel(const Offset(8.8, 53.1005)), [220, 228, 210, 255]);
    image.dispose();
    picture.dispose();
  });
  test(
    'public scenery response normalizes and loads in the native matcher',
    () async {
      final sourceFile = Platform.environment['WANDERLUST_SCENERY_XML'];
      if (sourceFile == null) return;
      final source = OsmNetwork.normalize(
        await File(sourceFile).readAsString(),
        [8.58, 53.15, 8.64, 53.186],
        areaId: 'vegesack-scenery',
        name: 'Vegesack parks and water',
      );
      final area = AreaNetwork.parse(source);
      expect(area.scenery.where((s) => s.kind == 'park'), isNotEmpty);
      expect(area.scenery.where((s) => s.kind == 'water'), isNotEmpty);
      expect(area.scenery.where((s) => s.kind == 'waterway'), isNotEmpty);
      final geo = WanderlustGeo.open();
      final matcher = geo.loadNetwork(source);
      matcher.dispose();
      final output = Platform.environment['WANDERLUST_SCENERY_OUTPUT'];
      if (output != null) await File(output).writeAsString(source);
      // ignore: avoid_print
      print(
        'Public Vegesack: ${area.edges.length} street sections, ${area.scenery.length} scenery features, ${utf8.encode(source).length} bytes.',
      );
    },
    skip: Platform.environment['WANDERLUST_SCENERY_XML'] == null,
  );

  test(
    'native live preview colours streets before saving, scenery does not enter matching',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'wanderlust-live-native-',
      );
      final store = SqliteWalkStore(
        factory: databaseFactoryFfi,
        databasePath: '${dir.path}/walks.db',
      );
      final controller = CoverageController(
        store: store,
        loadNetwork: () async => decorated(),
        liveInterval: Duration.zero,
      );
      try {
        final walk = WalkCodec.importGpx(
          '<gpx><trk><trkseg><trkpt lat="53.1" lon="8.80001"><time>2026-09-29T09:00:00Z</time></trkpt><trkpt lat="53.1" lon="8.80013"><time>2026-09-29T09:00:05Z</time></trkpt></trkseg></trk></gpx>',
        );
        controller.updateLive(walk);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await controller.settled;
        expect(controller.liveError, isNull);
        expect(controller.displayCounts, {
          OsmNetwork.edgeId(10, [1, 2]): 1,
        });
        expect(controller.counts, isEmpty);
      } finally {
        controller.dispose();
        await controller.settled;
        await store.close();
        await dir.delete(recursive: true);
      }
    },
    skip: Platform.environment['WANDERLUST_NATIVE_TESTS'] != '1',
  );
}
