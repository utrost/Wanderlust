import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wanderlust/memories/memory.dart';
import 'package:wanderlust/transfer/backup_contents.dart';
import 'backup_fixture.dart';
import 'package:wanderlust/memories/memory_photos.dart';
import 'package:wanderlust/recording/walk_store.dart';
import 'package:wanderlust/screens/memories_screen.dart';
import 'package:wanderlust/transfer/walk_codec.dart';
import 'package:wanderlust/widgets/memory_markers.dart';
import 'memory_fakes.dart';
import 'recording_test.dart' show fix;
import 'transfer_test.dart' show segmentedGpx;

class CancelPhoto implements MemoryPhotos {
  CancelPhoto(this.check);
  final Future<void> Function() check;
  @override
  Future<Uint8List?> pick(bool camera) async {
    await check();
    return null;
  }
}

class LostPhotoPicker extends ImagePicker {
  LostPhotoPicker(this.bytes);
  final Uint8List bytes;
  @override
  Future<LostDataResponse> retrieveLostData() async => LostDataResponse(
    files: [XFile.fromData(bytes, name: 'photo.png')],
    type: RetrieveType.image,
  );
}

void main() {
  sqfliteFfiInit();
  test(
    'stale GPS never becomes a pin; fresh fixes are frozen in the entry',
    () {
      expect(WalkMemory.create(fix: fix(1)).hasLocation, isFalse);
      final p = positionAt(fix(1), DateTime.now().toUtc());
      final m = WalkMemory.create(fix: p);
      expect(m.latitude, p.latitude);
      expect(m.copyWith(note: 'A bird').latitude, p.latitude);
      expect(m.copyWith(removeLocation: true).hasLocation, isFalse);
    },
  );
  test(
    'large photos survive restart; drafts do not alter saved entries; delete removes chunks',
    () async {
      final dir = await Directory.systemTemp.createTemp('wanderlust-memories-');
      final file = '${dir.path}/walks.db';
      SqliteWalkStore open() =>
          SqliteWalkStore(factory: databaseFactoryFfi, databasePath: file);
      var store = open();
      final photo = Uint8List.fromList(
        List.generate(3 * 1024 * 1024 + 7, (i) => i % 251),
      );
      final m = WalkMemory.create().copyWith(
        note: 'Old oak',
        photo: photo,
        draft: false,
      );
      try {
        await store.memories.put(m);
        await store.close();
        store = open();
        expect((await store.memories.list()).single.photo, isNull);
        expect((await store.memories.read(m.id, false))!.photo, photo);
        await store.memories.put(
          m.copyWith(note: 'Edited', draft: true, removePhoto: true),
        );
        expect((await store.memories.read(m.id, false))!.note, 'Old oak');
        await store.memories.put(
          m.copyWith(note: 'Edited', draft: false, removePhoto: true),
        );
        expect(await store.memories.read(m.id, true), isNull);
        expect((await store.memories.read(m.id, false))!.hasPhoto, isFalse);
        await store.memories.delete(m.id);
        expect(await store.memories.list(), isEmpty);
        await store.close();
        final db = await databaseFactoryFfi.openDatabase(file);
        expect(await db.query('memory_photo'), isEmpty);
        await db.close();
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'memory backup restores photos and walk links atomically with stable identities',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'wanderlust-memory-backup-',
      );
      final source = SqliteWalkStore(
        factory: databaseFactoryFfi,
        databasePath: '${dir.path}/a.db',
      );
      final target = SqliteWalkStore(
        factory: databaseFactoryFfi,
        databasePath: '${dir.path}/b.db',
      );
      try {
        final walk = WalkCodec.importGpx(segmentedGpx);
        await source.mergeWalks([walk]);
        final m = WalkMemory.create(walkUid: walk.uid).copyWith(
          note: 'River',
          photo: Uint8List.fromList([1, 2, 3]),
          draft: false,
        );
        await source.memories.put(m);
        final bytes = await encodeBackup(
          BackupContents(await source.listSaved(), [m]),
        );
        final restored = await decodeBackup(bytes);
        // Force a different local row id in the destination.
        final dummy = await target.begin(DateTime.utc(2026));
        await target.finish(dummy, DateTime.utc(2026), 'completed');
        expect(
          await target.mergeWalks(restored.walks, memories: restored.memories),
          1,
        );
        expect((await target.memories.list(walkUid: walk.uid)).single.id, m.id);
        expect((await target.memories.read(m.id, false))!.photo, [1, 2, 3]);
        expect(
          await target.mergeWalks(restored.walks, memories: restored.memories),
          0,
        );
        expect(await target.memories.list(), hasLength(1));
        final corrupt = Uint8List.fromList(bytes)..[bytes.length ~/ 2] ^= 1;
        await expectLater(decodeBackup(corrupt), throwsFormatException);
        final invalid = m.copyWith(
          photo: Uint8List(WalkMemory.maxPhotoBytes + 1),
        );
        await expectLater(target.memories.put(invalid), throwsFormatException);
        expect((await target.memories.read(m.id, false))!.photo, [1, 2, 3]);
      } finally {
        await source.close();
        await target.close();
        await dir.delete(recursive: true);
      }
    },
  );
  testWidgets(
    'Android lost photo recovery attaches to the durable draft and survives repeated recovery',
    (tester) async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.green, BlendMode.src);
      final picture = recorder.endRecording();
      final image = (await tester.runAsync(() => picture.toImage(16, 16)))!;
      final photo = (await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.png),
      ))!.buffer.asUint8List();
      image.dispose();
      picture.dispose();
      final store = FakeMemoryStore();
      final m = WalkMemory.create().copyWith(
        note: 'Before camera',
        pendingPhoto: true,
      );
      await store.put(m);
      await tester.runAsync(
        () => DeviceMemoryPhotos(picker: LostPhotoPicker(photo)).recover(store),
      );
      final recovered = (await store.read(m.id, true))!;
      expect(recovered.note, m.note);
      expect(recovered.photo, photo);
      expect(recovered.pendingPhoto, isFalse);
      await tester.runAsync(
        () => DeviceMemoryPhotos(picker: LostPhotoPicker(photo)).recover(store),
      );
      expect(store.entries, hasLength(1));
    },
  );
  testWidgets('Back keeps a draft and deleting requires confirmation', (
    tester,
  ) async {
    final store = FakeMemoryStore(), m = WalkMemory.create();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    MemoryEditor(store: store, memory: m, isNew: true),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'A bench');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect((await store.read(m.id, true))!.note, 'A bench');
    await tester.pumpWidget(
      MaterialApp(
        home: MemoryEditor(store: store, memory: m),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete memory'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(store.entries, hasLength(1));
    await tester.tap(find.byTooltip('Delete memory'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(store.entries, isEmpty);
  });
  testWidgets(
    'camera cancellation keeps a durable draft; saving publishes the note',
    (tester) async {
      final store = FakeMemoryStore(), m = WalkMemory.create();
      var launched = false;
      await tester.pumpWidget(
        MaterialApp(
          home: MemoryEditor(
            store: store,
            memory: m,
            isNew: true,
            photos: CancelPhoto(() async {
              final draft = (await store.read(m.id, true))!;
              expect(draft.note, 'A quiet bench');
              expect(draft.pendingPhoto, isTrue);
              launched = true;
            }),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'A quiet bench');
      await tester.ensureVisible(find.text('Take photo'));
      await tester.tap(find.text('Take photo'));
      await tester.pumpAndSettle();
      expect(launched, isTrue);
      expect((await store.read(m.id, true))!.pendingPhoto, isFalse);
      await tester.tap(find.text('Save memory'));
      await tester.pumpAndSettle();
      expect((await store.read(m.id, false))!.note, 'A quiet bench');
      expect(await store.read(m.id, true), isNull);
    },
  );
  testWidgets('failed storage keeps the editor text and offers retry', (
    tester,
  ) async {
    final store = FakeMemoryStore()..fail = true;
    await tester.pumpWidget(
      MaterialApp(
        home: MemoryEditor(
          store: store,
          memory: WalkMemory.create(),
          isNew: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'A fox');
    await tester.tap(find.text('Save memory'));
    await tester.pumpAndSettle();
    expect(find.text('A fox'), findsOneWidget);
    expect(store.entries, isEmpty);
    expect(
      find.textContaining('Could not complete this action'),
      findsOneWidget,
    );
    store.fail = false;
    await tester.tap(find.text('Save memory'));
    await tester.pumpAndSettle();
    expect(store.entries.values.single.note, 'A fox');
  });
  testWidgets(
    'markers open a saved memory at projected coordinates; drafts and unlocated notes stay hidden',
    (tester) async {
      final p = positionAt(fix(1), DateTime.now().toUtc());
      final m = WalkMemory.create(fix: p).copyWith(note: 'Tree', draft: false);
      WalkMemory? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 400,
            height: 400,
            child: MemoryMarkers(
              memories: [
                m,
                m.copyWith(draft: true),
                WalkMemory.create().copyWith(note: 'No pin', draft: false),
              ],
              project: (_) => const Offset(100, 100),
              size: const Size(400, 400),
              open: (m) => opened = m,
            ),
          ),
        ),
      );
      expect(find.byType(IconButton), findsOneWidget);
      await tester.tap(find.byTooltip('Memory: Tree'));
      expect(opened!.id, m.id);
    },
  );
}
