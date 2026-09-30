import 'memory_fakes.dart';
import 'package:wanderlust/memories/memory_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'recording_test.dart' show fix, FakeLocation;
import 'package:geolocator/geolocator.dart';
import 'package:wanderlust/screens/map_screen.dart';
import 'package:wanderlust/recording/walk_store.dart';
import 'package:wanderlust/data/area_network.dart';
import 'package:wanderlust/maps/area_store.dart';
import 'package:wanderlust/settings/walk_preferences.dart';
import 'coverage_test.dart' show networkJson;
import 'nearby_maps_test.dart' show smallNetwork;

class BootStore extends SqliteWalkStore {
  final _memories = FakeMemoryStore();
  @override
  MemoryStore get memories => _memories;
  BootStore({String? source}) {
    if (source != null) {
      maps[AreaNetwork.parse(source).version] = source;
      selected = maps.keys.first;
    }
  }
  final maps = <String, String>{};
  String? selected;
  WalkPreferences preferences = const WalkPreferences();
  bool recording = false;
  @override
  Future<int> begin(DateTime startedAt) async {
    recording = true;
    return 1;
  }

  @override
  Future<void> append(int id, int sequence, Position point) async {}
  @override
  Future<void> finish(int id, DateTime endedAt, String status) async {
    recording = false;
  }

  @override
  Future<List<SavedWalk>> recoverAndList() async => [];
  @override
  Future<List<SavedWalk>> listSaved() async => [];
  @override
  Future<void> close() async {}
  @override
  Future<String?> readActiveArea() async => maps[selected];
  @override
  Future<String?> readArea(String version) async => maps[version];
  @override
  Future<List<OfflineArea>> listAreas() async => [
    for (final entry in maps.entries)
      OfflineArea(
        version: entry.key,
        name: AreaNetwork.parse(entry.value).name,
        downloadedAt: DateTime.now(),
        bytes: entry.value.length,
      ),
  ];
  @override
  Future<void> registerNetwork(AreaNetwork network) async {}
  @override
  Future<Map<int, int>> readCombinedCounts(List<String> versions) async => {};
  @override
  Future<WalkPreferences> readPreferences() async => preferences;
  @override
  Future<void> savePreferences(WalkPreferences value) async {
    preferences = value;
  }

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
    if (selected == version) selected = null;
  }
}

void main() {
  testWidgets('fresh installation offers local map setup without Bremen', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: MapScreen(store: BootStore())));
    await tester.pumpAndSettle();
    expect(find.text('Set up my map'), findsOneWidget);
    expect(find.text('Bremen center'), findsNothing);
    expect(find.text('Start walk'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'first map setup selects local download and deleting it returns to welcome',
    (tester) async {
      final store = BootStore();
      var fixes = 0, downloads = 0;
      await tester.binding.setSurfaceSize(const Size(400, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: MapScreen(
            store: store,
            locate: () async {
              fixes++;
              return fix(1);
            },
            fetchMap: (area) async {
              downloads++;
              expect(area.bbox[0], lessThan(fix(1).longitude));
              expect(area.bbox[2], greaterThan(fix(1).longitude));
              return smallNetwork();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(fixes, 0);
      expect(downloads, 0);
      await tester.tap(find.text('Set up my map'));
      await tester.pumpAndSettle();
      expect(find.text('Bremen center'), findsNothing);
      await tester.tap(find.text('Find my location'));
      await tester.pumpAndSettle();
      expect(fixes, 1);
      expect(downloads, 0);
      await tester.tap(find.text('Download nearby map'));
      await tester.pumpAndSettle();
      expect(downloads, 1);
      expect(store.selected, store.maps.keys.single);
      expect(find.text('Example area'), findsOneWidget);
      expect(find.text('Start walk'), findsOneWidget);
      await tester.tap(find.text('Offline maps'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byTooltip('Remove downloaded map'),
        200,
      );
      await tester.tap(find.byTooltip('Remove downloaded map'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Set up my map'), findsOneWidget);
      expect(find.text('Bremen center'), findsNothing);
      expect(store.maps, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('removing the last map during recording keeps Stop available', (
    tester,
  ) async {
    final store = BootStore(source: networkJson());
    final location = FakeLocation();
    await tester.binding.setSurfaceSize(const Size(400, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MapScreen(store: store, location: location),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start walk'));
    await tester.pumpAndSettle();
    expect(store.recording, isTrue);
    await tester.tap(find.text('Offline maps'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byTooltip('Remove downloaded map'),
      200,
    );
    await tester.tap(find.byTooltip('Remove downloaded map'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Stop'), findsOneWidget);
    expect(store.recording, isTrue);
    await tester.tap(find.text('Stop'));
    // Stream cancellation crosses the widget tester's fake and real async zones.
    for (var i = 0; i < 5; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    await tester.pumpAndSettle();
    expect(store.recording, isFalse);
    expect(find.text('Set up my map'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await location.stream.close();
  });
  testWidgets(
    'existing downloaded maps bypass welcome even without a selected map',
    (tester) async {
      final store = BootStore(source: networkJson())..selected = null;
      await tester.pumpWidget(MaterialApp(home: MapScreen(store: store)));
      await tester.pumpAndSettle();
      expect(find.text('Set up my map'), findsNothing);
      expect(find.text('Test area'), findsOneWidget);
      expect(find.text('Bremen center'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Center on me requests a one-off fix without starting a walk', (
    tester,
  ) async {
    const channel = MethodChannel('flutter.baseflow.com/geolocator');
    var requests = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      switch (call.method) {
        case 'isLocationServiceEnabled':
          return true;
        case 'checkPermission':
          return 2;
        case 'getCurrentPosition':
          requests++;
          return {
            ...fix(1).toJson(),
            'latitude': 53.0759058,
            'longitude': 8.8073262,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          };
        default:
          throw StateError(call.method);
      }
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MapScreen(store: BootStore(source: networkJson())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Center on me'));
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(find.text('Location ready'), findsOneWidget);
    expect(find.text('53.07591, 8.80733'), findsNothing);
    expect(find.text('Start walk'), findsOneWidget);
    expect(find.text('Stop'), findsNothing);
    expect(find.byTooltip('Show map area'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Center on me reports disabled GPS without creating a fake position',
    (tester) async {
      const channel = MethodChannel('flutter.baseflow.com/geolocator');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'isLocationServiceEnabled') return false;
        fail('Must not request a fix when GPS is disabled');
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MapScreen(store: BootStore(source: networkJson())),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Center on me'));
      await tester.pumpAndSettle();
      expect(
        find.text('Turn on location to find your position.'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Your location'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
