import 'dart:io';
import 'dart:typed_data';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wanderlust/recording/walk_store.dart';
import 'package:wanderlust/transfer/backup_archive.dart';
import 'package:wanderlust/transfer/backup_contents.dart';

Future<Uint8List> encodeBackup(BackupContents contents) async {
  sqfliteFfiInit();
  final dir = await Directory.systemTemp.createTemp('backup-fixture-');
  final store = SqliteWalkStore(
    factory: databaseFactoryFfi,
    databasePath: '${dir.path}/db',
  );
  try {
    await store.mergeWalks(
      contents.walks,
      memories: contents.memories,
      maps: contents.maps,
      preferences: contents.preferences,
      activeMap: contents.activeMap,
    );
    final file = File('${dir.path}/backup');
    await BackupArchive.write(file, store.backupData, BackupProgress());
    return await file.readAsBytes();
  } finally {
    await store.close();
    await dir.delete(recursive: true);
  }
}

Future<BackupContents> decodeBackup(Uint8List bytes) async {
  final dir = await Directory.systemTemp.createTemp('backup-fixture-');
  try {
    final file = await File('${dir.path}/backup').writeAsBytes(bytes);
    final staged = await BackupArchive.read(file, dir, BackupProgress());
    return BackupContents(
      await staged.walks().toList(),
      await staged.memories().toList(),
      maps: await staged.maps().toList(),
      preferences: staged.metadata.preferences,
      activeMap: staged.metadata.activeMap,
    );
  } finally {
    await dir.delete(recursive: true);
  }
}
