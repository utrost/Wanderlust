import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wanderlust/recording/walk_store.dart';

import 'recording_test.dart' show fix;

void main() {
  sqfliteFfiInit();
  for (final summaries in [false, true]) {
    test(
      '${summaries ? 'summary' : 'full'} recovery uses last durable sequence, including empty walks',
      () async {
        final store = SqliteWalkStore(
          factory: databaseFactoryFfi,
          databasePath: inMemoryDatabasePath,
        );
        addTearDown(store.close);
        final emptyId = await store.begin(fix(0).timestamp);
        final id = await store.begin(fix(1).timestamp);
        await store.append(id, 0, fix(10));
        // A timestamp reversal must not change which fix was last committed.
        await store.append(id, 1, fix(5));
        expect(
          (await store.listSummaries()).every((w) => w.status == 'recording'),
          isTrue,
        );
        final recovered = summaries
            ? await store.listSummaries(recover: true)
            : await store.recoverAndList();
        expect(recovered.every((w) => w.status == 'interrupted'), isTrue);
        expect(
          recovered.firstWhere((w) => w.id == id).endedAt,
          fix(5).timestamp,
        );
        expect(
          recovered.firstWhere((w) => w.id == emptyId).endedAt,
          fix(0).timestamp,
        );
        expect((await store.loadWalk(id)).points, [fix(10), fix(5)]);
        expect(
          (await store.recoverAndList()).firstWhere((w) => w.id == id).endedAt,
          fix(5).timestamp,
        );
      },
    );
  }
}
