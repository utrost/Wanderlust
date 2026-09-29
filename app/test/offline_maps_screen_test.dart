import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanderlust/data/area_network.dart';
import 'package:wanderlust/maps/area_store.dart';
import 'package:wanderlust/screens/offline_maps_screen.dart';

import 'nearby_maps_test.dart' show smallNetwork;
import 'calm_live_scenery_test.dart' show decorated;
import 'recording_test.dart' show fix;

class MemoryAreas implements AreaStore {
  final maps = <String, String>{};
  String? selected;
  @override
  Future<List<OfflineArea>> listAreas() async => [
    for (final entry in maps.entries)
      OfflineArea(
        version: entry.key,
        name: AreaNetwork.parse(entry.value).name,
        downloadedAt: DateTime.utc(2026, 9, 26),
        bytes: entry.value.length,
      ),
  ];
  @override
  Future<String?> readArea(String version) async => maps[version];
  @override
  Future<String?> readActiveArea() async => maps[selected];
  @override
  Future<void> saveArea(String source) async {
    maps[AreaNetwork.parse(source).version] = source;
  }

  @override
  Future<void> selectArea(String? version) async {
    selected = version;
  }

  @override
  Future<void> deleteArea(String version) async {
    maps.remove(version);
  }
}

void main() {
  testWidgets(
    'download is saved then selected, and the library closes on success',
    (tester) async {
      final store = MemoryAreas();
      var selected = false;
      final result = Completer<String>();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => OfflineMapsScreen(
                      store: store,
                      position: fix(1),
                      activeVersion: null,
                      fetch: (_) => result.future,
                      onSelect: (source, version) async {
                        expect(await store.readArea(version!), source);
                        await store.selectArea(version);
                        selected = true;
                        return true;
                      },
                    ),
                  ),
                ),
                child: const Text('Open maps'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open maps'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download nearby map'));
      await tester.pump();
      expect(find.text('Downloading nearby streets…'), findsOneWidget);
      expect(find.text('Cancel download'), findsOneWidget);
      result.complete(smallNetwork());
      await tester.pumpAndSettle();
      expect(selected, isTrue);
      expect(store.maps, hasLength(1));
      expect(find.text('Open maps'), findsOneWidget);
    },
  );

  testWidgets(
    'failed and cancelled downloads preserve saved maps and selection',
    (tester) async {
      final store = MemoryAreas();
      await store.saveArea(smallNetwork());
      final before = store.maps.keys.single;
      await store.selectArea(before);
      var cancelCase = false;
      final pending = Completer<String>();
      await tester.pumpWidget(
        MaterialApp(
          home: OfflineMapsScreen(
            store: store,
            position: fix(1),
            activeVersion: before,
            fetch: (_) async {
              if (cancelCase) return pending.future;
              throw const FormatException('Service busy. Try later.');
            },
            onSelect: (_, _) async {
              fail('Must not switch on failure or cancellation');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download nearby map'));
      await tester.pumpAndSettle();
      expect(find.text('Service busy. Try later.'), findsOneWidget);
      expect(store.selected, before);
      cancelCase = true;
      await tester.tap(find.text('Download nearby map'));
      await tester.pump();
      await tester.tap(find.text('Cancel download'));
      await tester.pump();
      pending.complete(smallNetwork());
      await tester.pumpAndSettle();
      expect(store.maps, hasLength(1));
      expect(store.selected, before);
    },
  );

  testWidgets(
    'refresh uses the saved bounds without GPS and replaces the old map after selection',
    (tester) async {
      final store = MemoryAreas();
      await store.saveArea(smallNetwork());
      final old = store.maps.keys.single;
      await store.selectArea(old);
      final updated = decorated();
      await tester.pumpWidget(
        MaterialApp(
          home: OfflineMapsScreen(
            store: store,
            position: null,
            activeVersion: old,
            fetch: (area) async {
              expect(area.bbox, AreaNetwork.parse(smallNetwork()).bbox);
              return updated;
            },
            onSelect: (source, version) async {
              expect(store.maps.containsKey(old), isTrue);
              await store.selectArea(version);
              return true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byTooltip('Refresh map with parks and water'),
      );
      await tester.tap(find.byTooltip('Refresh map with parks and water'));
      await tester.pumpAndSettle();
      expect(store.maps, hasLength(1));
      expect(store.selected, AreaNetwork.parse(updated).version);
      expect(AreaNetwork.parse(store.maps.values.single).scenery, isNotEmpty);
    },
  );

  testWidgets('saved maps open offline and downloads require a location', (
    tester,
  ) async {
    final store = MemoryAreas();
    await store.saveArea(smallNetwork());
    var selected = false;
    await tester.pumpWidget(
      MaterialApp(
        home: OfflineMapsScreen(
          store: store,
          position: null,
          activeVersion: null,
          fetch: (_) async {
            fail('Must not use the network when opening a saved map');
          },
          onSelect: (_, version) async {
            selected = true;
            await store.selectArea(version);
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Download nearby map'),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Example area'));
    await tester.pumpAndSettle();
    expect(selected, isTrue);
    expect(store.selected, store.maps.keys.single);
  });
}
