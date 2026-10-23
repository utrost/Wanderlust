import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wanderlust/memories/memory.dart';
import 'package:wanderlust/recording/walk_store.dart';
import 'package:wanderlust/transfer/backup_archive.dart';
import 'package:wanderlust/transfer/walk_codec.dart';

import 'coverage_test.dart' show networkJson;
import 'transfer_test.dart' show segmentedGpx;

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late SqliteWalkStore store;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('archive-test-');
    store = SqliteWalkStore(
      factory: databaseFactoryFfi,
      databasePath: '${dir.path}/db',
    );
    await store.mergeWalks(
      [WalkCodec.importGpx(segmentedGpx)],
      maps: [networkJson()],
    );
  });
  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });
  test('v4 streams photos and restores atomically', () async {
    final walk = (await store.listSaved()).single;
    final m = WalkMemory.create(walkUid: walk.uid).copyWith(
      note: 'Bench',
      photo: Uint8List.fromList([1, 2, 3]),
      draft: false,
    );
    await store.memories.put(m);
    final file = File('${dir.path}/backup');
    await BackupArchive.write(file, store.backupData, BackupProgress());
    expect(await BackupArchive.recognizes(file), isTrue);
    final staged = await BackupArchive.read(file, dir, BackupProgress());
    expect(staged.metadata.walks.single.uid, walk.uid);
    expect(staged.metadata.memories.single.photo, isNull);
    expect((await staged.memories().single).photo, [1, 2, 3]);
    final target = SqliteWalkStore(
      factory: databaseFactoryFfi,
      databasePath: '${dir.path}/target',
    );
    try {
      await target.mergeWalks(
        staged.metadata.walks,
        memoryStream: staged.memories(),
        walkStream: staged.walks(),
        mapStream: staged.maps(),
      );
      expect((await target.memories.read(m.id, false))!.photo, [1, 2, 3]);
    } finally {
      await target.close();
    }
  });
  test(
    'v4 backups before optional map layers restore with both disabled',
    () async {
      final file = File('${dir.path}/legacy');
      await BackupArchive.write(file, store.backupData, BackupProgress());
      final bytes = await file.readAsBytes();
      const offset = BackupArchive.magic.length;
      final headerSize = ByteData.sublistView(
        bytes,
        offset,
        offset + 4,
      ).getUint32(0);
      final header =
          jsonDecode(
                utf8.decode(bytes.sublist(offset + 4, offset + 4 + headerSize)),
              )
              as Map<String, dynamic>;
      final start = offset + 4 + headerSize,
          end = start + (header['length'] as int);
      final settings =
          jsonDecode(utf8.decode(bytes.sublist(start, end)))
              as Map<String, dynamic>;
      (settings['preferences'] as Map)
        ..remove('completeBlocks')
        ..remove('fogOfWar');
      final payload = utf8.encode(jsonEncode(settings));
      header['length'] = payload.length;
      header['sha256'] = sha256.convert(payload).toString();
      final encoded = utf8.encode(jsonEncode(header));
      final length = ByteData(4)..setUint32(0, encoded.length);
      await file.writeAsBytes([
        ...bytes.take(offset),
        ...length.buffer.asUint8List(),
        ...encoded,
        ...payload,
        ...bytes.skip(end),
      ]);
      final restored = await BackupArchive.read(file, dir, BackupProgress());
      expect(restored.metadata.preferences!.completeBlocks, false);
      expect(restored.metadata.preferences!.fogOfWar, false);
      expect(await restored.walks().length, 1);
    },
  );
  test('corruption, truncation and trailing bytes are rejected', () async {
    final file = File('${dir.path}/backup');
    await BackupArchive.write(file, store.backupData, BackupProgress());
    final bytes = await file.readAsBytes();
    final corrupt = Uint8List.fromList(bytes);
    corrupt[bytes.length ~/ 2] ^= 1;
    for (final changed in [
      corrupt,
      bytes.sublist(0, bytes.length - 1),
      Uint8List.fromList([...bytes, 0]),
    ]) {
      await file.writeAsBytes(changed);
      await expectLater(
        BackupArchive.read(file, dir, BackupProgress()),
        throwsFormatException,
      );
    }
  });
  test('export refuses a memory whose walk is missing', () async {
    await store.memories.put(
      WalkMemory.create(
        walkUid: 'f' * 32,
      ).copyWith(note: 'Orphan', draft: false),
    );
    await expectLater(
      BackupArchive.write(
        File('${dir.path}/backup'),
        store.backupData,
        BackupProgress(),
      ),
      throwsFormatException,
    );
  });
  test('cancellation preserves data', () async {
    await expectLater(
      BackupArchive.write(
        File('${dir.path}/backup'),
        store.backupData,
        BackupProgress()..cancelled = true,
      ),
      throwsA(isA<BackupCancelled>()),
    );
    expect(await store.listSaved(), hasLength(1));
  });
  test('stream failure rolls back writes', () async {
    final target = SqliteWalkStore(
      factory: databaseFactoryFfi,
      databasePath: '${dir.path}/target',
    );
    Stream<WalkMemory> failing() async* {
      yield WalkMemory.create().copyWith(note: 'first', draft: false);
      throw const FormatException('broken photo');
    }

    try {
      await expectLater(
        target.mergeWalks(await store.listSaved(), memoryStream: failing()),
        throwsFormatException,
      );
      expect(await target.listSaved(), isEmpty);
      expect(await target.memories.list(), isEmpty);
    } finally {
      await target.close();
    }
  });
  test('88 MiB of photos export and read individually', () async {
    final photo = Uint8List(8 * 1024 * 1024)..[0] = 17;
    for (var i = 0; i < 11; i++) {
      await store.memories.put(
        WalkMemory.create().copyWith(
          note: 'Photo $i',
          photo: photo,
          draft: false,
        ),
      );
    }
    final file = File('${dir.path}/large');
    await BackupArchive.write(file, store.backupData, BackupProgress());
    expect(await file.length(), greaterThan(80 * 1024 * 1024));
    final staged = await BackupArchive.read(file, dir, BackupProgress());
    var bytes = 0;
    await for (final memory in staged.memories()) {
      bytes += memory.photo!.length;
    }
    expect(bytes, 88 * 1024 * 1024);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
