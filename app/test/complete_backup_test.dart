import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wanderlust/memories/memory.dart';
import 'package:wanderlust/memories/memory_backup.dart';
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
    'compressed backup restores maps, settings, walks and pinned photos after restart',
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
        showStreetNames: false,
        fillSmallGaps: true,
      );
      final backup = MemoryBackup(
        [walk],
        [memory],
        maps: [networkJson()],
        activeMap: 'test-v1',
        preferences: preferences,
      );
      final raw = MemoryBackup.encode(backup);
      final zipped = MemoryBackup.encode(backup, compressed: true);
      expect(zipped.length, lessThan(raw.length));
      final restored = MemoryBackup.decode(zipped);
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

  test(
    'legacy v2 and walk-only backups remain readable; damaged gzip is rejected',
    () {
      final encoded = MemoryBackup.encode(const MemoryBackup([], []));
      final old = jsonDecode(utf8.decode(encoded)) as Map<String, dynamic>;
      old['version'] = 2;
      expect(
        MemoryBackup.decode(
          Uint8List.fromList(utf8.encode(jsonEncode(old))),
        ).maps,
        isEmpty,
      );
      expect(
        MemoryBackup.decode(
          Uint8List.fromList(utf8.encode(WalkCodec.exportBackup([]))),
        ).walks,
        isEmpty,
      );
      final zipped = MemoryBackup.encode(
        const MemoryBackup([], []),
        compressed: true,
      );
      zipped[zipped.length - 8] ^= 255;
      expect(() => MemoryBackup.decode(zipped), throwsFormatException);
    },
  );

  test(
    'invalid map and missing selection cannot be exported as restorable backups',
    () {
      expect(
        () => MemoryBackup.encode(const MemoryBackup([], [], maps: ['{}'])),
        throwsFormatException,
      );
      expect(
        () => MemoryBackup.encode(
          MemoryBackup([], [], maps: [networkJson()], activeMap: 'absent'),
        ),
        throwsFormatException,
      );
      expect(
        () => MemoryBackup.encode(
          MemoryBackup([], [], maps: [networkJson(), networkJson()]),
        ),
        throwsFormatException,
      );
    },
  );
  test('gzip expansion is bounded before parsing oversized input', () {
    late List<int> compressed;
    final encoder = gzip.encoder.startChunkedConversion(
      ByteConversionSink.withCallback((bytes) => compressed = bytes),
    );
    final block = Uint8List(1024 * 1024);
    for (var i = 0; i < 129; i++) {
      encoder.add(block);
    }
    encoder.close();
    expect(compressed.length, lessThan(1024 * 1024));
    expect(
      () => MemoryBackup.decode(Uint8List.fromList(compressed)),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Expanded backup'),
        ),
      ),
    );
  });
}
