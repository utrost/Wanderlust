import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wanderlust/data/area_network.dart';
import 'package:wanderlust/maps/map_download.dart';
import 'package:wanderlust/maps/osm_network.dart';
import 'package:wanderlust/recording/walk_store.dart';
import 'package:wanderlust/screens/offline_maps_screen.dart';
import 'package:wanderlust/screens/settings_screen.dart';
import 'package:wanderlust/settings/walk_preferences.dart';
import 'package:wanderlust/widgets/area_map.dart';
import 'coverage_test.dart' show networkJson;
import 'offline_maps_screen_test.dart' show MemoryAreas;
import 'nearby_maps_test.dart' show smallNetwork;
import 'recording_test.dart' show fix;

void main() {
  sqfliteFfiInit();
  test('map sizes represent side length and validate extreme coordinates', () {
    for (final size in [1, 4, 10, 25]) {
      final area = NearbyArea.around(53.1, 8.8, sizeKm: size), b = area.bbox;
      expect(
        OsmNetwork.metres([b[0], 53.1], [b[2], 53.1]),
        closeTo(size * 1000, 60),
      );
      expect(
        OsmNetwork.metres([8.8, b[1]], [8.8, b[3]]),
        closeTo(size * 1000, 60),
      );
      expect(b[0], lessThan(8.8));
      expect(b[2], greaterThan(8.8));
      expect(area.query, contains('${b[1]},${b[0]},${b[3]},${b[2]}'));
      expect(area.name, contains('$size × $size km'));
    }
    expect(() => NearbyArea.around(53, 8, sizeKm: 0), throwsFormatException);
    expect(() => NearbyArea.around(53, 8, sizeKm: 26), throwsFormatException);
    expect(
      () => NearbyArea.around(79, 179.9, sizeKm: 25),
      throwsFormatException,
    );
    expect(() => NearbyArea.around(79, 179.9, sizeKm: 1), returnsNormally);
  });
  testWidgets(
    'large maps retain walking-scale centering and adequate pinch zoom',
    (tester) async {
      final json = jsonDecode(networkJson()) as Map<String, dynamic>;
      json['bbox'] = NearbyArea.around(53.1, 8.8, sizeKm: 25).bbox;
      final network = AreaNetwork.parse(jsonEncode(json));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AreaMap(
              network: network,
              counts: const {},
              position: fix(1),
              centerRequest: 1,
            ),
          ),
        ),
      );
      await tester.pump();
      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      final zoom = viewer.transformationController!.value.getMaxScaleOnAxis();
      expect(zoom, closeTo(25, 0.1));
      expect(viewer.maxScale, greaterThan(74));
      expect(zoom, lessThan(viewer.maxScale));
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'old settings use thinner defaults and new settings persist without resetting toggles',
    () async {
      final old = WalkPreferences.fromJson({'showTime': true});
      expect(old.showTime, isTrue);
      expect(old.walkedLineWidth, 3);
      expect(old.mapSizeKm, 4);
      expect(old.gpsIntervalSeconds, 5);
      expect(old.autoDownloadMaps, isTrue);
      expect(
        WalkPreferences.fromJson({
          'gpsIntervalSeconds': 10.0,
        }).gpsIntervalSeconds,
        10,
      );
      for (final interval in WalkPreferences.gpsIntervals) {
        final decoded = WalkPreferences.fromJson(
          WalkPreferences(
            gpsIntervalSeconds: interval,
            autoDownloadMaps: false,
          ).toJson(),
        );
        expect(decoded.gpsIntervalSeconds, interval);
        expect(decoded.autoDownloadMaps, isFalse);
      }
      expect(
        WalkPreferences.fromJson({'gpsIntervalSeconds': 7}).gpsIntervalSeconds,
        5,
      );
      expect(
        WalkPreferences.fromJson({'detailedGps': true}).gpsIntervalSeconds,
        2,
      );
      expect(old.fillSmallGaps, isFalse);
      final corrupt = WalkPreferences.fromJson({
        'walkedLineWidth': double.nan,
        'mapSizeKm': 25.5,
      });
      expect(corrupt.walkedLineWidth, 3);
      expect(corrupt.mapSizeKm, 4);
      final dir = await Directory.systemTemp.createTemp(
        'wanderlust-map-controls-',
      );
      SqliteWalkStore open() => SqliteWalkStore(
        factory: databaseFactoryFfi,
        databasePath: '${dir.path}/walks.db',
      );
      var store = open();
      try {
        await store.savePreferences(
          old.copyWith(
            walkedLineWidth: 1.5,
            mapSizeKm: 25,
            gpsIntervalSeconds: 2,
            fillSmallGaps: true,
          ),
        );
        await store.close();
        store = open();
        final saved = await store.readPreferences();
        expect(saved.showTime, isTrue);
        expect(saved.walkedLineWidth, 1.5);
        expect(saved.mapSizeKm, 25);
        expect(saved.gpsIntervalSeconds, 2);
        expect(saved.fillSmallGaps, isTrue);
        expect(saved.copyWith(showGps: true).fillSmallGaps, isTrue);
        expect(saved.copyWith(showGps: true).gpsIntervalSeconds, 2);
        expect(saved.copyWith(showGps: true).mapSizeKm, 25);
        expect(saved.copyWith(showSamples: true).walkedLineWidth, 1.5);
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  testWidgets(
    'GPS interval preserves other settings and rolls back failed writes',
    (tester) async {
      WalkPreferences? saved;
      var fail = false;
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            initial: const WalkPreferences(
              showTime: true,
              walkedLineWidth: 2,
              mapSizeKm: 6,
            ),
            diagnostic: const SizedBox(),
            save: (value) async {
              if (fail) throw StateError('storage unavailable');
              saved = value;
            },
          ),
        ),
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('gps-interval')),
        250,
      );
      await tester.drag(
        find.byKey(const Key('gps-interval')),
        const Offset(-500, 0),
      );
      await tester.pumpAndSettle();
      expect(saved!.gpsIntervalSeconds, 2);
      expect(saved!.showTime, isTrue);
      expect(saved!.walkedLineWidth, 2);
      expect(saved!.mapSizeKm, 6);
      fail = true;
      await tester.drag(
        find.byKey(const Key('gps-interval')),
        const Offset(500, 0),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<Slider>(find.byKey(const Key('gps-interval'))).value,
        0,
      );
    },
  );
  testWidgets(
    'Fill small gaps preserves other settings and rolls back failed writes',
    (tester) async {
      WalkPreferences? saved;
      var fail = false;
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            initial: const WalkPreferences(
              showTime: true,
              walkedLineWidth: 2,
              mapSizeKm: 6,
            ),
            diagnostic: const SizedBox(),
            save: (value) async {
              if (fail) throw StateError('storage unavailable');
              saved = value;
            },
          ),
        ),
      );
      await tester.scrollUntilVisible(find.text('Fill small gaps'), 250);
      await tester.tap(find.text('Fill small gaps'));
      await tester.pumpAndSettle();
      expect(saved!.fillSmallGaps, isTrue);
      expect(saved!.showTime, isTrue);
      expect(saved!.walkedLineWidth, 2);
      expect(saved!.mapSizeKm, 6);
      fail = true;
      await tester.tap(find.text('Fill small gaps'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, 'Fill small gaps'),
            )
            .value,
        isTrue,
      );
    },
  );
  testWidgets(
    'line slider persists, survives another toggle and rolls back on failure',
    (tester) async {
      var fail = false;
      WalkPreferences? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            initial: const WalkPreferences(mapSizeKm: 12),
            diagnostic: const SizedBox(),
            save: (v) async {
              if (fail) throw StateError('disk full');
              saved = v;
            },
          ),
        ),
      );
      Slider slider() =>
          tester.widget<Slider>(find.byKey(const Key('walked-line-width')));
      slider().onChanged!(2);
      slider().onChangeEnd!(2);
      await tester.pumpAndSettle();
      expect(saved!.walkedLineWidth, 2);
      expect(saved!.mapSizeKm, 12);
      await tester.tap(find.text('Show elapsed time'));
      await tester.pumpAndSettle();
      expect(saved!.showTime, isTrue);
      expect(saved!.walkedLineWidth, 2);
      fail = true;
      slider().onChanged!(6);
      slider().onChangeEnd!(6);
      await tester.pumpAndSettle();
      expect(slider().value, 2);
    },
  );
  testWidgets(
    '25 km selection reaches download; failed download retains the saved map',
    (tester) async {
      final store = MemoryAreas();
      await store.saveArea(smallNetwork());
      await store.selectArea(store.maps.keys.single);
      final before = store.selected;
      int? savedSize;
      NearbyArea? requested;
      await tester.pumpWidget(
        MaterialApp(
          home: OfflineMapsScreen(
            store: store,
            position: fix(1),
            activeVersion: before,
            onSizeChanged: (v) async => savedSize = v,
            fetch: (area) async {
              requested = area;
              throw const FormatException(
                'Map is too detailed. Choose a smaller size.',
              );
            },
            onSelect: (_, _) async {
              fail('Failed download must not change the active map');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final slider = tester.widget<Slider>(find.byKey(const Key('map-size')));
      slider.onChanged!(25);
      slider.onChangeEnd!(25);
      await tester.pumpAndSettle();
      expect(find.text('25 × 25 km · 625 km²'), findsOneWidget);
      expect(savedSize, 25);
      await tester.ensureVisible(find.text('Download nearby map'));
      await tester.tap(find.text('Download nearby map'));
      await tester.pumpAndSettle();
      expect(
        requested!.bbox,
        NearbyArea.around(fix(1).latitude, fix(1).longitude, sizeKm: 25).bbox,
      );
      expect(store.selected, before);
      expect(store.maps, hasLength(1));
      expect(find.textContaining('Choose a smaller size.'), findsOneWidget);
    },
  );
  testWidgets('failed size preference save restores the previous size', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OfflineMapsScreen(
          store: MemoryAreas(),
          position: fix(1),
          activeVersion: null,
          initialSizeKm: 8,
          onSizeChanged: (_) async {
            throw StateError('Could not save size');
          },
          onSelect: (_, _) async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final slider = tester.widget<Slider>(find.byKey(const Key('map-size')));
    slider.onChanged!(25);
    slider.onChangeEnd!(25);
    await tester.pumpAndSettle();
    expect(find.text('8 × 8 km · 64 km²'), findsOneWidget);
    expect(tester.widget<Slider>(find.byKey(const Key('map-size'))).value, 8);
  });
  test(
    'thickness control changes actual coverage pixels at high zoom',
    () async {
      final map = AreaNetwork.parse(networkJson());
      const size = Size(400, 800);
      final point = mapPoint(map, const Offset(8.8005, 53.1), size);
      final transform = Matrix4.diagonal3Values(12, 12, 1)
        ..setTranslationRaw(200 - point.dx * 12, 400 - point.dy * 12, 0);
      Future<int> pixels(double width) async {
        final recorder = ui.PictureRecorder();
        AreaMapPainter(
          network: map,
          counts: const {1: 1},
          transform: transform,
          walkedLineWidth: width,
        ).paint(Canvas(recorder), size);
        final picture = recorder.endRecording(),
            image = await picture.toImage(400, 800);
        final bytes = (await image.toByteData())!;
        var count = 0;
        for (var y = 390; y < 410; y++) {
          for (var x = 195; x < 205; x++) {
            count += bytes.getUint8((y * 400 + x) * 4 + 3);
          }
        }
        image.dispose();
        picture.dispose();
        return count;
      }

      final thin = await pixels(2),
          normal = await pixels(3),
          bold = await pixels(6);
      expect(thin, lessThan(normal));
      expect(normal, lessThan(bold));
      expect(
        AreaMapPainter(
          network: map,
          counts: const {},
          walkedLineWidth: 2,
        ).shouldRepaint(
          AreaMapPainter(network: map, counts: const {}, walkedLineWidth: 6),
        ),
        isTrue,
      );
    },
  );
}
