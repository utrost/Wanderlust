import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanderlust/data/area_network.dart';
import 'package:wanderlust/widgets/area_map.dart';

void main() {
  testWidgets('real Bremen geometry renders persisted coverage',
      (tester) async {
    final network = AreaNetwork.parse(
        File('assets/geo/bremen-center.streets.geojson').readAsStringSync());
    final fontPath = Platform.environment['WANDERLUST_FONT_PATH'];
    if (fontPath != null) {
      final font = FontLoader('Roboto')
        ..addFont(Future.value(
            ByteData.sublistView(File(fontPath).readAsBytesSync())));
      await tester.runAsync(font.load);
    }
    final key = GlobalKey();
    final counts = {
      for (final e in network.edges.where((e) => e.name == 'Am Wall')) e.id: 3
    };
    expect(counts, isNotEmpty);
    await tester.binding.setSurfaceSize(const Size(440, 900));
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(fontFamily: 'Roboto'),
        home: Scaffold(
          backgroundColor: const Color(0xFFFBF8F2),
          body: RepaintBoundary(
              key: key,
              child: ColoredBox(
                  color: const Color(0xFFFBF8F2),
                  child: Stack(children: [
                    Positioned.fill(
                        child: AreaMap(network: network, counts: counts)),
                    const Positioned(
                        top: 30,
                        left: 16,
                        child: Text('Bremen · synthetic coverage preview')),
                    const Positioned(
                        bottom: 24,
                        left: 16,
                        child: Text('© OpenStreetMap contributors · ODbL')),
                  ]))),
        )));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    final screenshotDir = Platform.environment['WANDERLUST_VISUAL_DIR'];
    if (screenshotDir != null) {
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$screenshotDir/bremen-coverage.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });
}
