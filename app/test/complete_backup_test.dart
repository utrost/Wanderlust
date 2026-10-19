import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wanderlust/memories/memory.dart';
import 'package:wanderlust/transfer/backup_contents.dart';
import 'backup_fixture.dart';
import 'package:wanderlust/recording/walk_store.dart';
import 'package:wanderlust/settings/walk_preferences.dart';
import 'package:wanderlust/transfer/walk_codec.dart';
import 'coverage_test.dart' show networkJson;
import 'transfer_test.dart' show segmentedGpx;

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late SqliteWalkStore store;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('complete-backup-');
    store = SqliteWalkStore(
      factory: databaseFactoryFfi,
      databasePath: '${dir.path}/walks.db',
    );
  });
  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });

  test(
    'streamed backup restores maps, settings, walks and pinned photos after restart',
    () async {
      final walk = WalkCodec.importGpx(segmentedGpx);
      final memory = WalkMemory.create(walkUid: walk.uid).copyWith(
        note: 'A bench',
        photo: Uint8List.fromList([1, 2, 3]),
        draft: false,
        pin: (latitude: 53.1, longitude: 8.8),
      );
      const preferences = WalkPreferences(
        mapSizeKm: 12,
        fogOfWar: true,
        completeBlocks: true,
        showStreetNames: false,
        fillSmallGaps: true,
      );
      final backup = BackupContents(
        [walk],
        [memory],
        maps: [networkJson()],
        activeMap: 'test-v1',
        preferences: preferences,
      );
      final restored = await decodeBackup(await encodeBackup(backup));
      expect(restored.preferences!.completeBlocks, true);
      await store.mergeWalks(
        restored.walks,
        memories: restored.memories,
        maps: restored.maps,
        preferences: restored.preferences,
        activeMap: restored.activeMap,
      );
      await store.close();
      store = SqliteWalkStore(
        factory: databaseFactoryFfi,
        databasePath: '${dir.path}/walks.db',
      );
      expect((await store.listSaved()).single.uid, walk.uid);
      expect(await store.readActiveArea(), networkJson());
      expect((await store.readPreferences()).toJson(), preferences.toJson());
      final saved = (await store.memories.read(memory.id, false))!;
      expect(saved.photo, [1, 2, 3]);
      expect(saved.latitude, 53.1);
      expect(saved.accuracy, isNull);
      expect(
        await store.mergeWalks(
          restored.walks,
          memories: restored.memories,
          maps: restored.maps,
        ),
        0,
      );
      expect(await store.listAreas(), hasLength(1));
    },
  );

  test(
    'map capacity failure rolls back walks, memories and settings together',
    () async {
      await store.saveArea(networkJson(version: 'local'));
      await store.selectArea('local');
      final walk = WalkCodec.importGpx(segmentedGpx);
      final memory = WalkMemory.create(
        walkUid: walk.uid,
      ).copyWith(note: 'Keep me', draft: false);
      await expectLater(
        store.mergeWalks(
          [walk],
          memories: [memory],
          maps: [for (var i = 0; i < 8; i++) networkJson(version: 'import-$i')],
          preferences: const WalkPreferences(mapSizeKm: 25),
        ),
        throwsFormatException,
      );
      expect(await store.listSaved(), isEmpty);
      expect(await store.memories.list(), isEmpty);
      expect(await store.listAreas(), hasLength(1));
      expect(await store.readActiveArea(), networkJson(version: 'local'));
      expect((await store.readPreferences()).mapSizeKm, 4);
    },
  );

  test(
    'merge preserves current selection and settings unless settings explicitly supplied',
    () async {
      await store.saveArea(networkJson(version: 'local'));
      await store.selectArea('local');
      await store.savePreferences(const WalkPreferences(mapSizeKm: 9));
      await store.mergeWalks([], maps: [networkJson()], activeMap: 'test-v1');
      expect(await store.readActiveArea(), networkJson(version: 'local'));
      expect((await store.readPreferences()).mapSizeKm, 9);
      await store.mergeWalks(
        [],
        preferences: const WalkPreferences(mapSizeKm: 7),
      );
      expect((await store.readPreferences()).mapSizeKm, 7);
    },
  );
}
