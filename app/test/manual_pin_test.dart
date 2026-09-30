import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanderlust/data/area_network.dart';
import 'package:wanderlust/memories/memory.dart';
import 'package:wanderlust/screens/memories_screen.dart';
import 'package:wanderlust/screens/memory_pin_screen.dart';
import 'package:wanderlust/widgets/area_map.dart';
import 'coverage_test.dart' show networkJson;
import 'memory_fakes.dart';

void main() {
  test('map projection round-trips geographic coordinates', () {
    final network = AreaNetwork.parse(networkJson());
    const size = Size(400, 600), coordinate = Offset(8.8123, 53.1234);
    final result = mapCoordinate(
      network,
      mapPoint(network, coordinate, size),
      size,
    );
    expect((result - coordinate).distance, lessThan(1e-9));
  });

  testWidgets(
    'manual placement survives pan and save without GPS; cancellation keeps the pin',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = FakeMemoryStore();
      final memory = WalkMemory.create().copyWith(note: 'Quiet bench');
      await tester.pumpWidget(
        MaterialApp(
          home: MemoryEditor(
            store: store,
            memory: memory,
            isNew: true,
            networks: [AreaNetwork.parse(networkJson())],
            locate: () async =>
                throw StateError('Manual pin must not request GPS'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Choose on map'));
      await tester.tap(find.text('Choose on map'));
      await tester.pumpAndSettle();
      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      viewer.transformationController!.value = Matrix4.diagonal3Values(2, 2, 1)
        ..setTranslationRaw(-100, -150, 0);
      await tester.pump();
      final mapRect = tester.getRect(find.byType(AreaMap));
      final point = mapRect.center;
      final network = AreaNetwork.parse(networkJson());
      final expected = mapCoordinate(
        network,
        viewer.transformationController!.toScene(point - mapRect.topLeft),
        mapRect.size,
      );
      await tester.tapAt(point);
      await tester.pump();
      await tester.tap(find.text('Use this spot'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Pin placed on map'), findsOneWidget);
      await tester.ensureVisible(find.text('Choose on map'));
      await tester.tap(find.text('Choose on map'));
      await tester.pumpAndSettle();
      expect(find.byType(MemoryPinScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save memory'));
      await tester.pumpAndSettle();
      final saved = (await store.read(memory.id, false))!;
      expect(saved.latitude, closeTo(expected.dy, 1e-8));
      expect(saved.longitude, closeTo(expected.dx, 1e-8));
      expect(saved.accuracy, isNull);
    },
  );

  testWidgets(
    'no downloaded maps explains manual placement without losing the note',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MemoryEditor(
            store: FakeMemoryStore(),
            memory: WalkMemory.create().copyWith(note: 'Remember this'),
            isNew: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Choose on map'));
      await tester.tap(find.text('Choose on map'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Download an offline map first'),
        findsOneWidget,
      );
      expect(find.text('Remember this'), findsOneWidget);
    },
  );
}
