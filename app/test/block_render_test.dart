import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanderlust/blocks/block_geometry.dart';
import 'package:wanderlust/memories/memory.dart';
import 'package:wanderlust/widgets/area_map.dart';
import 'package:wanderlust/widgets/block_layer.dart';
import 'blocks_test.dart' show square, network, p;

void main() {
  testWidgets(
    'block fill appears only when completed and removal clears cache',
    (tester) async {
      final map = network(square(), bbox: [-.0001, -.0001, .001, .001]);
      final block = buildBlockTopology([network(square())]).blocks.single;
      final layer = BlockLayer();
      const size = Size(300, 300);
      layer.prepare([block], map, size);
      Future<int> green(Set<String> completed) async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
        layer.paint(canvas, Offset.zero & size, completed, null, 1, {}, 1);
        final pic = recorder.endRecording();
        final image = await tester.runAsync(() => pic.toImage(300, 300));
        final bytes = await tester.runAsync(() => image!.toByteData());
        final center = map.project(p(50, 50), size);
        final value = bytes!.getUint8(
          (center.dy.floor() * 300 + center.dx.floor()) * 4,
        );
        image!.dispose();
        pic.dispose();
        return value;
      }

      expect(await green({}), 255);
      expect(await green({block.id}), lessThan(255));
      expect(await green({}), 255);
    },
  );
  testWidgets(
    'memory markers take tap priority over blocks; reduced motion has no fade',
    (tester) async {
      final map = network(square(), bbox: [-.0001, -.0001, .001, .001]);
      final blocks = buildBlockTopology([network(square())]).blocks;
      final memory = WalkMemory.create().copyWith(
        note: 'Bench',
        draft: false,
        pin: (latitude: p(50, 50).dy, longitude: p(50, 50).dx),
      );
      var memories = 0, blockTaps = 0;
      Widget view(Set<String> completed) => MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: AreaMap(
              network: map,
              counts: const {},
              blocks: blocks,
              completedBlocks: completed,
              memories: [memory],
              onMemory: (_) => memories++,
              onMapTap: (_) => blockTaps++,
            ),
          ),
        ),
      );
      await tester.pumpWidget(view({}));
      await tester.tap(find.byTooltip('Memory: Bench'));
      expect(memories, 1);
      expect(blockTaps, 0);
      await tester.pumpAndSettle();
      await tester.pumpWidget(view({blocks.single.id}));
      expect(tester.binding.hasScheduledFrame, false);
      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<AreaMapPainter>()
          .single;
      expect(painter.blockAlpha, 1);
      await tester.tapAt(const Offset(100, 400));
      expect(blockTaps, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
