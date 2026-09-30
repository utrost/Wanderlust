import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanderlust/data/area_network.dart';
import 'package:wanderlust/theme/heat_ramp.dart';
import 'package:wanderlust/widgets/area_map.dart';
import 'package:wanderlust/widgets/map_labels.dart';
import 'gap_interpolation_test.dart' show gapNetwork;

void main() {
  testWidgets(
    'street labels sit beside horizontal, vertical and diagonal roads',
    (tester) async {
      final data = jsonDecode(gapNetwork()) as Map<String, dynamic>;
      for (final feature in data['features'] as List) {
        feature['properties']['name'] = 'Street';
      }
      final area = AreaNetwork.parse(jsonEncode(data));
      for (final direction in [
        const Offset(1, 0),
        const Offset(0, 1),
        const Offset(1, 1),
      ]) {
        Offset project(Offset p) =>
            const Offset(100, 100) + direction * p.dx * 300000;
        final labels = layoutMapLabels(
          [area],
          const Size(600, 600),
          project,
          streets: true,
        );
        expect(labels, hasLength(1));
        for (var i = 0; i < 1000; i++) {
          expect(
            labels.single.bounds.contains(project(Offset(i / 1000000, 0))),
            isFalse,
          );
        }
      }
    },
  );

  testWidgets('a place label cannot punch a hole in confirmed coverage', (
    tester,
  ) async {
    final data = jsonDecode(gapNetwork()) as Map<String, dynamic>;
    data['wanderlust_places'] = [
      {
        'name': 'Crossing label',
        'kind': 'suburb',
        'point': [0.00045, 0],
      },
    ];
    final area = AreaNetwork.parse(jsonEncode(data));
    const size = Size(600, 600);
    final recorder = ui.PictureRecorder();
    AreaMapPainter(
      network: area,
      counts: {1: 1, 2: 1, 3: 1},
      coverageScreenWidth: 4,
    ).paint(Canvas(recorder), size);
    final picture = recorder.endRecording();
    final image = await tester.runAsync(() => picture.toImage(600, 600));
    final bytes = (await tester.runAsync(
      () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
    ))!;
    final expected = HeatRamp.color(1, dark: false).toARGB32();
    for (var metres = 2; metres < 98; metres++) {
      final p = mapPoint(area, Offset(metres / 111195, 0), size);
      final offset = (p.dy.floor() * 600 + p.dx.floor()) * 4;
      expect(bytes.getUint8(offset), (expected >> 16) & 255);
      expect(bytes.getUint8(offset + 1), (expected >> 8) & 255);
      expect(bytes.getUint8(offset + 2), expected & 255);
    }
    image!.dispose();
    picture.dispose();
  });
}
