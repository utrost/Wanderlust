import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:wanderlust/data/area_network.dart';
import 'package:wanderlust/widgets/area_map.dart';
import 'package:wanderlust/widgets/exploration_fog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanderlust/exploration/exploration.dart';
import 'package:wanderlust/recording/saved_walk.dart';
import 'package:wanderlust/settings/walk_preferences.dart';
import 'package:wanderlust/widgets/map_spatial_index.dart';
import 'recording_test.dart' show fix;

void main() {
  testWidgets(
    'fog leaves discovered cells clear and shades unexplored terrain',
    (tester) async {
      final map = AreaNetwork.parse(
        File('assets/geo/bremen-center.streets.geojson').readAsStringSync(),
      ).withViewport([0, 0, .1, .1]);
      final fog = ExplorationFog();
      const size = Size(400, 400);
      fog.prepare({(100, 100)}, map, size);
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(Offset.zero & size, Paint()..color = Colors.blue);
      fog.paint(canvas, Offset.zero & size);
      final picture = recorder.endRecording();
      final image = await tester.runAsync(() => picture.toImage(400, 400));
      final bytes = (await tester.runAsync(() => image!.toByteData()))!;
      final center = map.project(
        discoveryCoordinate(
          100.5 * discoveryCellMetres,
          100.5 * discoveryCellMetres,
        ),
        size,
      );
      final offset = (center.dy.floor() * 400 + center.dx.floor()) * 4;
      expect(bytes.getUint8(offset), (Colors.blue.r * 255).round());
      expect(bytes.getUint8(0), greaterThan(Colors.blue.r * 255));
      image!.dispose();
      picture.dispose();
    },
  );

  testWidgets('exploration map renders at walking zoom', (tester) async {
    final map = AreaNetwork.parse(
      File('assets/geo/bremen-center.streets.geojson').readAsStringSync(),
    );
    final walk = SavedWalk(
      1,
      fix(0).timestamp,
      fix(500).timestamp,
      'completed',
      [for (var i = 0; i <= 500; i += 5) fix(i)],
    );
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    const size = Size(440, 850);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xfff4ede3),
    );
    final center = mapPoint(map, const Offset(8.8025, 53.07), size);
    final transform = Matrix4.diagonal3Values(4, 4, 1)
      ..setTranslationRaw(220 - center.dx * 4, 425 - center.dy * 4, 0);
    AreaMapPainter(
      network: map,
      counts: const {},
      fogOfWar: true,
      exploredCells: discoveryCells(walk),
      transform: transform,
    ).paint(canvas, size);
    final picture = recorder.endRecording();
    final image = await tester.runAsync(() => picture.toImage(440, 850));
    final directory = Platform.environment['WANDERLUST_VISUAL_DIR'];
    if (directory != null) {
      final bytes = await tester.runAsync(
        () => image!.toByteData(format: ImageByteFormat.png),
      );
      File(
        '$directory/exploration-fog.png',
      ).writeAsBytesSync(bytes!.buffer.asUint8List());
    }
    image!.dispose();
    picture.dispose();
  });

  test(
    'spatial query matches brute force including large crossing features',
    () {
      final index = MapSpatialIndex<int>();
      final boxes = <int, Rect>{};
      for (var i = 0; i < 10000; i++) {
        final rect = Rect.fromLTWH((i % 100) * 10, (i ~/ 100) * 10, 12, 12);
        boxes[i] = rect;
        index.add(i, rect);
      }
      boxes[10000] = const Rect.fromLTWH(-1000, -1000, 3000, 3000);
      index.add(10000, boxes[10000]!);
      for (final viewport in [
        const Rect.fromLTWH(100, 100, 80, 90),
        const Rect.fromLTWH(-300, -300, 50, 50),
        const Rect.fromLTWH(-10000, -10000, 20000, 20000),
      ]) {
        expect(index.query(viewport), {
          for (final e in boxes.entries)
            if (e.value.overlaps(viewport)) e.key,
        });
      }
      expect(
        index.query(const Rect.fromLTWH(100, 100, 80, 90)).length,
        lessThan(120),
      );
    },
  );
  test('fog is opt-in and survives preference serialization', () {
    expect(WalkPreferences.fromJson({}).fogOfWar, isFalse);
    final saved = const WalkPreferences().copyWith(fogOfWar: true).toJson();
    expect(WalkPreferences.fromJson(saved).fogOfWar, isTrue);
  });
  test('raw fixes reveal terrain without bridging a missing kilometre', () {
    final walk = SavedWalk(
      1,
      fix(0).timestamp,
      fix(1000).timestamp,
      'completed',
      [fix(0), fix(1000)],
      segmentStarts: const [1],
    );
    final cells = discoveryCells(walk);
    (int, int) cell(int t) {
      final p = discoveryProject(fix(t).longitude, fix(t).latitude);
      return (
        (p.dx / discoveryCellMetres).floor(),
        (p.dy / discoveryCellMetres).floor(),
      );
    }

    expect(cells, contains(cell(0)));
    expect(cells, contains(cell(1000)));
    expect(cells, isNot(contains(cell(500))));
  });
  test(
    'restored journeys rebuild discovery, deletion removes unique cells',
    () async {
      final a = SavedWalk(1, fix(0).timestamp, fix(1).timestamp, 'completed', [
        fix(0),
      ]);
      final b = SavedWalk(
        2,
        fix(1000).timestamp,
        fix(1001).timestamp,
        'completed',
        [fix(1000)],
      );
      final controller = ExplorationController((id) async => id == 1 ? a : b);
      controller.update(true, [a, b], null);
      await controller.settled;
      final both = controller.cells.length;
      expect(both, greaterThan(discoveryCells(a).length));
      controller.update(true, [a], null);
      await controller.settled;
      expect(controller.cells, discoveryCells(a));
      controller.update(false, [a], null);
      await controller.settled;
      controller.update(true, [], b);
      await controller.settled;
      expect(controller.cells, discoveryCells(b));
      controller.dispose();
    },
  );
}
