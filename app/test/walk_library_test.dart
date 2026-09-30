import 'package:wanderlust/transfer/walk_codec.dart';
import 'package:wanderlust/memories/memory_backup.dart';
import 'coverage_test.dart' show networkJson;
import 'package:wanderlust/settings/walk_preferences.dart';
import 'package:wanderlust/maps/area_store.dart';
import 'package:wanderlust/memories/memory.dart';
import 'memory_fakes.dart';
import 'package:wanderlust/memories/memory_store.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanderlust/recording/walk_store.dart';
import 'package:wanderlust/screens/walk_library_screen.dart';
import 'package:wanderlust/transfer/walk_files.dart';
import 'transfer_test.dart' show segmentedGpx;

class LibraryStore extends SqliteWalkStore {
  final _memories = FakeMemoryStore();
  @override
  MemoryStore get memories => _memories;
  final walks = <SavedWalk>[];
  bool failFavourite = false;
  @override
  Future<void> setFavourite(String uid, bool value) async {
    if (failFavourite) throw StateError('Disk full');
    final i = walks.indexWhere((w) => w.uid == uid);
    walks[i] = walks[i].withFavourite(value);
  }

  int mergeCalls = 0;
  WalkPreferences? restoredPreferences;
  List<String> restoredMaps = [];
  @override
  Future<List<OfflineArea>> listAreas() async => [];
  @override
  Future<String?> readActiveArea() async => null;
  @override
  Future<WalkPreferences> readPreferences() async => const WalkPreferences();
  @override
  Future<List<SavedWalk>> listSaved() async => List.of(walks);
  @override
  Future<int> mergeWalks(
    List<SavedWalk> incoming, {
    bool deduplicateTrace = false,
    List<WalkMemory> memories = const [],
    List<String> maps = const [],
    WalkPreferences? preferences,
    String? activeMap,
  }) async {
    mergeCalls++;
    restoredPreferences = preferences;
    restoredMaps = maps;
    var count = 0;
    for (final walk in incoming) {
      if (walks.any((w) => w.uid == walk.uid)) continue;
      walks.add(walk);
      count++;
    }
    return count;
  }
}

class TestFiles implements WalkFiles {
  Uint8List? picked;
  bool cancelSave = false;
  bool failSave = false;
  String? name;
  Uint8List? saved;
  @override
  Future<Uint8List?> pick() async => picked;
  @override
  Future<bool> save(String name, String mimeType, Uint8List bytes) async {
    if (failSave) throw StateError('Disk full');
    if (cancelSave) return false;
    this.name = name;
    saved = bytes;
    return true;
  }
}

Future<void> perform(
  WidgetTester tester,
  Finder finder, {
  bool cancelRestore = false,
  bool replaceSettings = false,
}) async {
  await tester.runAsync(() async {
    await tester.tap(finder);
    // Yield real event-loop time to compute's isolate; fake-time pumpAndSettle
    // alone can exhaust its timeout before the worker gets scheduled.
    for (var i = 0; i < 500; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await tester.pump();
      if (find.text('Restore').evaluate().isNotEmpty) {
        if (replaceSettings) {
          await tester.tap(find.text('Replace my settings'));
          await tester.pump();
        }
        await tester.tap(find.text(cancelRestore ? 'Cancel' : 'Restore'));
        await tester.pump();
      }
      if (find.byType(LinearProgressIndicator).evaluate().isEmpty) return;
    }
    fail('Library operation did not complete');
  });
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'library imports, exports and restores through document actions',
    (tester) async {
      final store = LibraryStore();
      final files = TestFiles()
        ..picked = Uint8List.fromList(utf8.encode(segmentedGpx));
      var updates = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: WalkLibraryScreen(
            store: store,
            files: files,
            onChanged: () async {
              updates++;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> tap(Finder finder) => perform(tester, finder);
      await tap(find.text('Import GPX'));
      expect(find.textContaining('1 walk added'), findsOneWidget);
      expect(store.walks, hasLength(1));
      expect(updates, 1);
      await tap(find.byTooltip('Export GPX'));
      expect(files.name, endsWith('.gpx'));
      expect(utf8.decode(files.saved!), contains('</trkseg><trkseg>'));
      await tap(find.text('Create backup'));
      expect(files.name, 'wanderlust-backup.json.gz');
      files.picked = files.saved;
      await tap(find.text('Restore backup'));
      expect(
        find.textContaining('0 walks added; 1 already saved'),
        findsOneWidget,
      );
      expect(store.walks, hasLength(1));
      files.failSave = true;
      await tap(find.text('Create backup'));
      expect(find.textContaining('Could not complete'), findsOneWidget);
      expect(store.walks, hasLength(1));
    },
  );

  testWidgets('cancellation and malformed files leave library unchanged', (
    tester,
  ) async {
    final files = TestFiles();
    final store = LibraryStore();
    await tester.pumpWidget(
      MaterialApp(
        home: WalkLibraryScreen(
          store: store,
          files: files,
          onChanged: () async {
            fail('No change callback on cancellation or parse failure');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import GPX'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('transfer-message')), findsNothing);
    files.picked = Uint8List.fromList(utf8.encode('{"broken":true}'));
    await perform(tester, find.text('Restore backup'));
    expect(find.textContaining('File could not be read'), findsOneWidget);
    expect(store.walks, isEmpty);
    files.cancelSave = true;
    await perform(tester, find.text('Create backup'));
    expect(find.byKey(const Key('transfer-message')), findsNothing);
    expect(files.saved, isNull);
  });
  testWidgets(
    'restore preview cancels safely and replaces settings only when opted in',
    (tester) async {
      final store = LibraryStore();
      final files = TestFiles()
        ..picked = MemoryBackup.encode(
          MemoryBackup(
            [],
            [],
            maps: [networkJson()],
            activeMap: 'test-v1',
            preferences: const WalkPreferences(mapSizeKm: 12),
          ),
          compressed: true,
        );
      await tester.pumpWidget(
        MaterialApp(
          home: WalkLibraryScreen(
            store: store,
            files: files,
            onChanged: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await perform(tester, find.text('Restore backup'), cancelRestore: true);
      expect(store.mergeCalls, 0);
      await perform(tester, find.text('Restore backup'));
      expect(store.mergeCalls, 1);
      expect(store.restoredMaps, hasLength(1));
      expect(store.restoredPreferences, isNull);
      await perform(tester, find.text('Restore backup'), replaceSettings: true);
      expect(store.mergeCalls, 2);
      expect(store.restoredPreferences!.mapSizeKm, 12);
    },
  );
  testWidgets(
    'favourites filter hides everyday walks without exporting or removing them',
    (tester) async {
      final store = LibraryStore()
        ..walks.add(WalkCodec.importGpx(segmentedGpx));
      final files = TestFiles();
      await tester.pumpWidget(
        MaterialApp(
          home: WalkLibraryScreen(
            store: store,
            files: files,
            onChanged: () async =>
                fail('Starring must not trigger coverage recomputation'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Walk history'), findsOneWidget);
      await tester.tap(find.text('Favourites'));
      await tester.pumpAndSettle();
      expect(find.text('Star a walk to find it here.'), findsOneWidget);
      await tester.tap(find.text('All walks'));
      await tester.pumpAndSettle();
      store.failFavourite = true;
      await tester.tap(find.byTooltip('Add to favourites'));
      await tester.pumpAndSettle();
      expect(store.walks.single.favourite, isFalse);
      expect(find.textContaining('Could not complete'), findsOneWidget);
      store.failFavourite = false;
      await tester.tap(find.byTooltip('Add to favourites'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Favourites'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Remove from favourites'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove from favourites'));
      await tester.pumpAndSettle();
      expect(find.text('Star a walk to find it here.'), findsOneWidget);
      expect(store.walks, hasLength(1));
      expect(files.saved, isNull);
      // A backup still includes all walks while viewing an empty favourites list.
      await perform(tester, find.text('Create backup'));
      expect(MemoryBackup.decode(files.saved!).walks, hasLength(1));
    },
  );
  testWidgets(
    'history remains scrollable with enlarged text on a small screen',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = LibraryStore()
        ..walks.add(WalkCodec.importGpx(segmentedGpx));
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.8)),
            child: child!,
          ),
          home: WalkLibraryScreen(
            store: store,
            files: TestFiles(),
            onChanged: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byTooltip('Add to favourites'), 250);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add to favourites'));
      await tester.pumpAndSettle();
      expect(store.walks.single.favourite, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
