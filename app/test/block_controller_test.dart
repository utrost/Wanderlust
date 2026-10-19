import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanderlust/blocks/block_controller.dart';
import 'package:wanderlust/blocks/block_geometry.dart';
import 'package:wanderlust/coverage/coverage_controller.dart';
import 'package:wanderlust/coverage/coverage_store.dart';
import 'package:wanderlust/data/area_network.dart';
import 'package:wanderlust/widgets/block_controls.dart';
import 'blocks_test.dart' show square, network, p;

class EmptyStore implements CoverageStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class BlockTestCoverage extends CoverageController {
  BlockTestCoverage() : super(store: EmptyStore());
  Set<int> supported = {}, preview = {};
  @override
  Set<int> get supportedSections => Set.of(supported);
  @override
  Set<int> get liveSupportedSections => Set.of(preview);
  void change({List<AreaNetwork>? maps, Set<int>? saved, Set<int>? live}) {
    if (maps != null) networks = maps;
    if (saved != null) supported = saved;
    if (live != null) preview = live;
    notifyListeners();
  }
}

void main() {
  test(
    'history, live preview, save, removal, map switching and rebuild',
    () async {
      final coverage = BlockTestCoverage();
      var builds = 0;
      final controller = BlockController(
        coverage,
        build: (maps) async {
          builds++;
          return buildBlockTopology(maps);
        },
      );
      final map = network(square());
      coverage.change(maps: [map], saved: {1, 2, 3, 4});
      expect(builds, 0);
      controller.setEnabled(true);
      await controller.settled;
      expect(controller.completed, 1);
      expect(controller.hit(p(50, 50)), isNotNull);
      expect(controller.hit(p(200, 200)), isNull);
      coverage.change(saved: {1, 2}, live: {3, 4});
      expect(controller.completed, 0);
      expect(controller.live.values.single.complete, true);
      coverage.change(saved: {1, 2, 3, 4}, live: {});
      expect(controller.completed, 1);
      coverage.network = map.withViewport([-.005, -.005, .005, .005]);
      coverage.change();
      await controller.settled;
      expect(builds, 1);
      coverage.change(saved: {});
      expect(controller.completed, 0);
      coverage.change(saved: {1, 2, 3, 4});
      expect(controller.completed, 1);
      coverage.change(maps: []);
      await controller.settled;
      expect(controller.completed, 0);
      coverage.change(maps: [map]);
      await controller.settled;
      expect(controller.completed, 1);
      controller.dispose();
      coverage.dispose();
    },
  );
  test(
    'stale worker results discarded after disable and map refresh',
    () async {
      final coverage = BlockTestCoverage()
        ..change(maps: [network(square())], saved: {1, 2, 3, 4});
      final pending = <Completer<BlockTopology>>[];
      final controller = BlockController(
        coverage,
        build: (maps) {
          final c = Completer<BlockTopology>();
          pending.add(c);
          return c.future;
        },
      );
      controller.setEnabled(true);
      controller.setEnabled(false);
      controller.setEnabled(true);
      pending[0].complete(buildBlockTopology(coverage.networks));
      await Future<void>.delayed(Duration.zero);
      expect(controller.blocks, isEmpty);
      pending[1].complete(buildBlockTopology(coverage.networks));
      await controller.settled;
      expect(controller.completed, 1);
      controller.dispose();
      coverage.dispose();
    },
  );
  test('failed worker is retryable without changing coverage', () async {
    final coverage = BlockTestCoverage()
      ..change(maps: [network(square())], saved: {1, 2, 3, 4});
    var fail = true;
    final controller = BlockController(
      coverage,
      build: (maps) async {
        if (fail) throw StateError('test');
        return buildBlockTopology(maps);
      },
    );
    controller.setEnabled(true);
    await controller.settled;
    expect(controller.error, isNotNull);
    fail = false;
    controller.retry();
    await controller.settled;
    expect(controller.completed, 1);
    expect(coverage.supported, {1, 2, 3, 4});
    controller.dispose();
    coverage.dispose();
  });
  testWidgets(
    'count and accessible details explain provisional progress and retry',
    (tester) async {
      final coverage = BlockTestCoverage()
        ..change(maps: [network(square())], saved: {1, 2}, live: {3, 4});
      final controller = BlockController(
        coverage,
        build: (maps) async => buildBlockTopology(maps),
      );
      controller.setEnabled(true);
      await controller.settled;
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              textScaler: TextScaler.linear(1.8),
              disableAnimations: true,
            ),
            child: Scaffold(
              body: Builder(
                builder: (context) => BlockCountChip(
                  controller: controller,
                  onPressed: () => showBlockDetails(
                    context,
                    controller,
                    block: controller.blocks.single,
                    recording: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('0 blocks completed'), findsOneWidget);
      await tester.tap(find.byType(ActionChip));
      await tester.pumpAndSettle();
      expect(find.textContaining('100% explored'), findsOneWidget);
      expect(find.textContaining('provisional until saved'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      coverage.dispose();
    },
  );
}
