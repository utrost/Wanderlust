import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wanderlust/recording/walk_store.dart';
import 'package:wanderlust/storage/app_database.dart';
import 'recording_test.dart' show fix;

void main() {
  sqfliteFfiInit();
  test(
    'new lineage creates the complete schema and retains it after reopening',
    () async {
      final dir = await Directory.systemTemp.createTemp('schema-baseline-');
      final path = '${dir.path}/db';
      var store = SqliteWalkStore(
        factory: databaseFactoryFfi,
        databasePath: path,
      );
      try {
        final id = await store.begin(fix(0).timestamp);
        await store.append(id, 0, fix(1));
        await store.finish(id, fix(2).timestamp, 'completed');
        final uid = await store.walkUid(id);
        final db = await store.database.database;
        expect(await db.getVersion(), 3);
        expect(
          (await db.rawQuery('PRAGMA application_id')).single.values.single,
          AppDatabase.applicationId,
        );
        expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
        expect(
          (await db.query(
            'sqlite_master',
            columns: ['name'],
            where: "type = 'table'",
          )).map((r) => r['name']),
          containsAll([
            'recorded_walk',
            'memory_photo',
            'walk_preferences',
            'offline_area',
            'walk_edge',
          ]),
        );
        await store.close();
        store = SqliteWalkStore(
          factory: databaseFactoryFfi,
          databasePath: path,
        );
        expect((await store.loadWalk(id)).points, [fix(1)]);
        expect(await store.walkUid(id), uid);
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'unrelated version-one database is rejected without modifying its data',
    () async {
      final dir = await Directory.systemTemp.createTemp('old-lineage-');
      final path = '${dir.path}/db';
      final old = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute('CREATE TABLE sentinel (value TEXT)');
            await db.insert('sentinel', {'value': 'preserve me'});
          },
        ),
      );
      await old.close();
      final database = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: path,
      );
      try {
        await expectLater(database.database, throwsStateError);
        final check = await databaseFactoryFfi.openDatabase(path);
        expect((await check.query('sentinel')).single['value'], 'preserve me');
        await check.close();
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}
