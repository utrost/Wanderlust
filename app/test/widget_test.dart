import 'dart:async';
import 'package:wanderlust/widgets/area_map.dart';
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
  const geoChannel = MethodChannel('flutter.baseflow.com/geolocator');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          geoChannel,
          (call) async => call.method == 'isLocationServiceEnabled' ? false : 0,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(geoChannel, null);
  });

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
      await tester.tap(find.byTooltip('Offline maps'));
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
    await tester.tap(find.byTooltip('Offline maps'));
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
    expect(requests, 2);
    expect(find.byTooltip('Location ready · Location details'), findsOneWidget);
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
      await tester.tap(
        find.byTooltip('Location needs attention · Location details'),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Turn on location to find your position.'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Your location'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'startup and real resume center once; permission dialogs do not',
    (tester) async {
      var requests = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        geoChannel,
        (call) async {
          if (call.method == 'isLocationServiceEnabled') return true;
          if (call.method == 'checkPermission') return 2;
          if (call.method == 'getCurrentPosition') {
            requests++;
            return {
              ...fix(requests).toJson(),
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            };
          }
          fail(
            'Automatic centering must not request permission: ${call.method}',
          );
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MapScreen(store: BootStore(source: networkJson())),
        ),
      );
      await tester.pumpAndSettle();
      expect(requests, 1);
      AreaMap map() => tester.widget<AreaMap>(find.byType(AreaMap));
      final first = map().centerRequest;
      expect(first, greaterThan(0));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(requests, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(requests, 2);
      expect(map().centerRequest, first + 1);
      expect(find.text('Start walk'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('browsing during GPS acquisition keeps the chosen viewport', (
    tester,
  ) async {
    final pending = Completer<Position>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(geoChannel, (
      call,
    ) async {
      if (call.method == 'isLocationServiceEnabled') return true;
      if (call.method == 'checkPermission') return 2;
      fail(call.method);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: MapScreen(
          store: BootStore(source: networkJson()),
          locate: () => pending.future,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.drag(find.byType(InteractiveViewer), const Offset(50, 30));
    pending.complete(
      Position.fromMap({
        ...fix(1).toJson(),
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      }),
    );
    await tester.pumpAndSettle();
    final map = tester.widget<AreaMap>(find.byType(AreaMap));
    expect(map.position, isNotNull);
    expect(map.centerRequest, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('automatic centering never prompts for denied permission', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(geoChannel, (
      call,
    ) async {
      if (call.method == 'isLocationServiceEnabled') return true;
      if (call.method == 'checkPermission') return 0;
      fail('Unexpected automatic location call: ${call.method}');
    });
    await tester.pumpWidget(
      MaterialApp(
        home: MapScreen(store: BootStore(source: networkJson())),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<AreaMap>(find.byType(AreaMap)).position, isNull);
    expect(find.byTooltip('Center on me'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'compact map controls remain readable with large text on a small screen',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.8)),
            child: child!,
          ),
          home: MapScreen(store: BootStore(source: networkJson())),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Add memory'), findsOneWidget);
      expect(find.byTooltip('Memories'), findsOneWidget);
      expect(find.byTooltip('Saved walks (0)'), findsOneWidget);
      expect(find.textContaining('street sections explored'), findsNothing);
      expect(find.text('Start walk'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'return during a walk waits for fresh GPS and preserves recording',
    (tester) async {
      final location = FakeLocation();
      final store = BootStore(source: networkJson());
      await tester.pumpWidget(
        MaterialApp(
          home: MapScreen(store: store, location: location),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start walk'));
      await tester.pumpAndSettle();
      location.stream.add(fix(1)); // Deliberately stale.
      await tester.pump();
      final before = tester.widget<AreaMap>(find.byType(AreaMap)).centerRequest;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(
        tester.widget<AreaMap>(find.byType(AreaMap)).centerRequest,
        before,
      );
      location.stream.add(
        Position.fromMap({
          ...fix(2).toJson(),
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }),
      );
      await tester.pump();
      expect(
        tester.widget<AreaMap>(find.byType(AreaMap)).centerRequest,
        before + 1,
      );
      expect(store.recording, isTrue);
      expect(find.text('Stop'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await location.stream.close();
    },
  );
}
