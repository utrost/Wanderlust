import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wanderlust/memories/memory.dart';
import 'package:wanderlust/settings/walk_preferences.dart';
import 'package:wanderlust/transfer/backup_archive.dart';
import 'package:wanderlust/transfer/walk_codec.dart';
import 'package:wanderlust/transfer/walk_transfer.dart';

import 'transfer_test.dart' show segmentedGpx;
import 'walk_library_test.dart' show LibraryStore, TestFiles;

class ArchiveDocuments extends TestFiles {
  ArchiveDocuments(this.root, this.bytes);
  final Directory root;
  final Uint8List bytes;
  bool cancelPick = false, failExport = false;
  File? pickedFile;
  @override
  Future<File?> pickArchive() async {
    if (cancelPick) return null;
    pickedFile = File('${root.path}/private-input-copy');
    return pickedFile!.writeAsBytes(bytes);
  }

  @override
  Future<bool> saveArchive(File file) async {
    if (failExport) throw StateError('Provider disconnected');
    saved = await file.readAsBytes();
    return !cancelSave;
  }

  @override
  Future<void> cancelArchive() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Uint8List archive;
  late ArchiveDocuments files;
  late LibraryStore store;
  late WalkTransfer transfer;
  late List<String> events;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('transfer-service-test-');
    final source = LibraryStore();
    source.walks.add(WalkCodec.importGpx(segmentedGpx));
    await source.memories.put(
      WalkMemory.create(walkUid: source.walks.single.uid).copyWith(
        note: 'Bench',
        photo: Uint8List.fromList([1, 2, 3]),
        draft: false,
      ),
    );
    final input = File('${dir.path}/source');
    await BackupArchive.write(input, source.backupData, BackupProgress());
    archive = await input.readAsBytes();
    await input.delete();
    files = ArchiveDocuments(dir, archive);
    store = LibraryStore();
    events = [];
    transfer = WalkTransfer(
      data: store.backupData,
      importer: store,
      files: files,
      temporaryRoot: dir,
      checkPhoto: (_) async {
        events.add('photo');
      },
    );
  });
  tearDown(() => dir.delete(recursive: true));

  test(
    'v4 validates photos, asks choices, then commits and cleans staging',
    () async {
      final result = await transfer.importFile(
        backup: true,
        progress: BackupProgress(),
        choose: (summary) async {
          events.add('choose');
          expect(summary.walks, 1);
          expect(summary.memories, 1);
          expect(summary.hasSettings, isTrue);
          return const RestoreOptions(maps: false, settings: true);
        },
        onCommit: () {
          events.add('commit');
        },
      );
      expect(events, ['photo', 'choose', 'commit']);
      expect(result!.added, 1);
      expect(result.preferences, isA<WalkPreferences>());
      expect(store.mergeCalls, 1);
      expect((await store.memories.list()).single.photo, [1, 2, 3]);
      expect(await dir.list().toList(), isEmpty);
    },
  );

  test('declining restore deletes private copies without committing', () async {
    final result = await transfer.importFile(
      backup: true,
      progress: BackupProgress(),
      choose: (_) async => null,
    );
    expect(result, isNull);
    expect(store.mergeCalls, 0);
    expect(await dir.list().toList(), isEmpty);
  });

  test(
    'cancelling during preview prevents commit and cleans staging',
    () async {
      final progress = BackupProgress();
      await expectLater(
        transfer.importFile(
          backup: true,
          progress: progress,
          choose: (_) async {
            progress.cancelled = true;
            return const RestoreOptions(maps: true);
          },
        ),
        throwsA(isA<BackupCancelled>()),
      );
      expect(store.mergeCalls, 0);
      expect(await dir.list().toList(), isEmpty);
    },
  );

  test(
    'invalid photo prevents preview and commit and cleans staging',
    () async {
      final invalid = WalkTransfer(
        data: store.backupData,
        importer: store,
        files: files,
        temporaryRoot: dir,
        checkPhoto: (_) async {
          throw const FormatException('Bad photo');
        },
      );
      await expectLater(
        invalid.importFile(
          backup: true,
          progress: BackupProgress(),
          choose: (_) async {
            fail('Invalid data must not reach restore confirmation');
          },
        ),
        throwsFormatException,
      );
      expect(store.mergeCalls, 0);
      expect(await dir.list().toList(), isEmpty);
    },
  );

  test('retired JSON and gzip backups are rejected without a commit', () async {
    for (final old in [
      Uint8List.fromList([123, 125]),
      Uint8List.fromList([31, 139, 8, 0]),
    ]) {
      final legacyFiles = ArchiveDocuments(dir, old);
      final service = WalkTransfer(
        data: store.backupData,
        importer: store,
        files: legacyFiles,
        temporaryRoot: dir,
      );
      await expectLater(
        service.importFile(
          backup: true,
          progress: BackupProgress(),
          choose: (_) async =>
              throw StateError('No preview for retired format'),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('no longer supported'),
          ),
        ),
      );
      expect(store.mergeCalls, 0);
      expect(await dir.list().toList(), isEmpty);
    }
  });

  test(
    'picker cancellation and failed export leave no temporary files',
    () async {
      files.cancelPick = true;
      expect(
        await transfer.importFile(
          backup: true,
          progress: BackupProgress(),
          choose: (_) async => null,
        ),
        isNull,
      );
      expect(await dir.list().toList(), isEmpty);
      files.failExport = true;
      await expectLater(transfer.backup(BackupProgress()), throwsStateError);
      expect(await dir.list().toList(), isEmpty);
    },
  );
}
