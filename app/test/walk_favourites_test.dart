import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wanderlust/data/area_network.dart';
import 'package:wanderlust/transfer/backup_contents.dart';
import 'backup_fixture.dart';
import 'package:wanderlust/recording/walk_store.dart';
import 'package:wanderlust/transfer/walk_codec.dart';
import 'coverage_test.dart' show networkJson;
import 'transfer_test.dart' show segmentedGpx, envelope;

void main() {
  sqfliteFfiInit();
  test(
    'favourites survive restart and backup without changing raw walks or heatmap counts',
    () async {
      final dir = await Directory.systemTemp.createTemp('walk-favourites-');
      var store = SqliteWalkStore(
        factory: databaseFactoryFfi,
        databasePath: '${dir.path}/walks.db',
      );
      final target = SqliteWalkStore(
        factory: databaseFactoryFfi,
        databasePath: '${dir.path}/restore.db',
      );
      try {
        final first = WalkCodec.importGpx(segmentedGpx);
        final second = SavedWalk(
          0,
          first.startedAt,
          first.endedAt,
          first.status,
          first.points,
          uid: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          segmentStarts: first.segmentStarts,
          untimed: first.untimed,
        );
        await store.mergeWalks([first, second]);
        final area = AreaNetwork.parse(networkJson());
        await store.registerNetwork(area);
        final walks = await store.listSaved();
        for (final walk in walks) {
          await store.replaceWalkMatch(
            walk.id,
            area.version,
            'test-fingerprint',
            {1, 2},
          );
        }
        expect(await store.readCounts(area.version), {1: 2, 2: 2});
        final raw = first.toBackup(includeFavourite: false);
        await store.setFavourite(first.uid, true);
        expect(await store.readCounts(area.version), {1: 2, 2: 2});
        await store.close();
        store = SqliteWalkStore(
          factory: databaseFactoryFfi,
          databasePath: '${dir.path}/walks.db',
        );
        final saved = (await store.listSaved()).firstWhere(
          (w) => w.uid == first.uid,
        );
        expect(saved.favourite, isTrue);
        expect(saved.toBackup(includeFavourite: false), raw);
        expect(WalkCodec.exportGpx(saved), WalkCodec.exportGpx(first));
        final backup = await decodeBackup(
          await encodeBackup(BackupContents(await store.listSaved(), [])),
        );
        await target.mergeWalks(backup.walks);
        expect(
          (await target.listSaved())
              .firstWhere((w) => w.uid == first.uid)
              .favourite,
          isTrue,
        );
        // Restoring an older choice must neither conflict nor overwrite local edits.
        await store.setFavourite(first.uid, false);
        expect(await store.mergeWalks(backup.walks), 0);
        expect((await store.listSaved()).every((w) => !w.favourite), isTrue);
        expect(await store.readCounts(area.version), {1: 2, 2: 2});
        final before = await store.listSaved();
        await expectLater(
          store.setFavourite('missing', true),
          throwsStateError,
        );
        expect((await store.listSaved()).length, before.length);
      } finally {
        await store.close();
        await target.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'older backups default to ordinary history and malformed favourite flags are rejected',
    () {
      final walk = WalkCodec.importGpx(segmentedGpx).toBackup();
      walk.remove('favourite');
      expect(
        WalkCodec.importBackup(envelope([walk])).single.favourite,
        isFalse,
      );
      walk['favourite'] = 'yes';
      expect(
        () => WalkCodec.importBackup(envelope([walk])),
        throwsFormatException,
      );
    },
  );
}
