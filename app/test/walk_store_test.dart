import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wanderlust/recording/walk_store.dart';
import 'recording_test.dart' show fix;

void main() {
  sqfliteFfiInit();
  test('reopen recovers durable fixes and preserves completed sessions',
      () async {
    final dir = await Directory.systemTemp.createTemp('wanderlust-test-');
    final file = '${dir.path}/walks.db';
    SqliteWalkStore open() =>
        SqliteWalkStore(factory: databaseFactoryFfi, databasePath: file);
    var store = open();
    final completed = await store.begin(DateTime.utc(2026, 7, 11, 9));
    await store.append(completed, 0, fix(1));
    await store.finish(completed, fix(5).timestamp, 'completed');
    final interrupted = await store.begin(DateTime.utc(2026, 7, 11, 9));
    await store.append(interrupted, 0, fix(2));
    await store.append(interrupted, 1, fix(3));
    await store.close();
    store = open();
    final walks = await store.recoverAndList();
    expect(walks, hasLength(2));
    expect(walks.first.status, 'interrupted');
    expect(walks.first.endedAt, fix(3).timestamp);
    expect(walks.first.points, hasLength(2));
    expect(walks.first.points.first.accuracy, 4);
    expect(walks.first.points.first.timestamp, fix(2).timestamp);
    expect(walks.last.status, 'completed');
    expect((await store.recoverAndList()).first.status, 'interrupted');
    await store.close();
    await dir.delete(recursive: true);
  });
}
