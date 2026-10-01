import 'dart:convert';
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import 'memory.dart';
import 'memory_repository.dart';

class MemoryStore implements MemoryRepository {
  MemoryStore(this.database);
  final Future<Database> Function() database;
  static const chunkSize = 64 * 1024;
  static Future<void> create(DatabaseExecutor db) async {
    await db.execute(
      'CREATE TABLE memory (id TEXT NOT NULL, draft INTEGER NOT NULL, json TEXT NOT NULL, PRIMARY KEY(id, draft))',
    );
    await db.execute(
      'CREATE TABLE memory_photo (id TEXT NOT NULL, draft INTEGER NOT NULL, seq INTEGER NOT NULL, bytes BLOB NOT NULL, PRIMARY KEY(id, draft, seq), FOREIGN KEY(id, draft) REFERENCES memory(id, draft) ON DELETE CASCADE)',
    );
  }

  @override
  Future<List<WalkMemory>> list({String? walkUid}) async {
    final rows = await (await database()).query('memory');
    final items = rows
        .map(
          (r) => WalkMemory.fromJson(
            jsonDecode(r['json'] as String) as Map<String, dynamic>,
          ),
        )
        .where((m) => walkUid == null || m.walkUid == walkUid)
        .toList();
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  static Future<WalkMemory?> readFrom(
    DatabaseExecutor db,
    String id,
    bool draft,
  ) async {
    final rows = await db.query(
      'memory',
      where: 'id = ? AND draft = ?',
      whereArgs: [id, draft ? 1 : 0],
    );
    if (rows.isEmpty) return null;
    final data =
        jsonDecode(rows.single['json'] as String) as Map<String, dynamic>;
    final buffer = BytesBuilder(copy: false);
    for (var seq = 0; buffer.length < (data['photoLength'] as int); seq++) {
      final chunks = await db.query(
        'memory_photo',
        columns: ['bytes'],
        where: 'id = ? AND draft = ? AND seq = ?',
        whereArgs: [id, draft ? 1 : 0, seq],
      );
      if (chunks.isEmpty) throw StateError('Memory photo is incomplete');
      buffer.add(chunks.single['bytes'] as Uint8List);
    }
    data['photo'] = buffer.isEmpty ? null : base64Encode(buffer.takeBytes());
    return WalkMemory.fromJson(data, complete: true);
  }

  @override
  Future<WalkMemory?> read(String id, bool draft) async =>
      (await database()).transaction((tx) => readFrom(tx, id, draft));
  static Future<void> writeTo(DatabaseExecutor db, WalkMemory value) async {
    // Validate before replacing either the metadata or any photo chunks.
    WalkMemory.fromJson(value.toJson(), complete: true);
    final d = value.draft ? 1 : 0;
    await db.insert('memory', {
      'id': value.id,
      'draft': d,
      'json': jsonEncode(value.toJson(includePhoto: false)),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    final bytes = value.photo;
    if (bytes != null) {
      final batch = db.batch();
      for (var start = 0; start < bytes.length; start += chunkSize) {
        batch.insert('memory_photo', {
          'id': value.id,
          'draft': d,
          'seq': start ~/ chunkSize,
          'bytes': Uint8List.sublistView(
            bytes,
            start,
            (start + chunkSize).clamp(0, bytes.length),
          ),
        });
      }
      await batch.commit(noResult: true);
    }
  }

  @override
  Future<void> put(WalkMemory value) async => (await database()).transaction((
    tx,
  ) async {
    if (value.pendingPhoto) {
      // A platform result belongs to exactly one durable draft.
      final rows = await tx.query('memory', where: 'draft = 1');
      for (final row in rows) {
        final data = jsonDecode(row['json'] as String) as Map<String, dynamic>;
        if (data['pendingPhoto'] == true) {
          data['pendingPhoto'] = false;
          await tx.update(
            'memory',
            {'json': jsonEncode(data)},
            where: 'id = ? AND draft = 1',
            whereArgs: [row['id']],
          );
        }
      }
    }
    await writeTo(tx, value);
    if (!value.draft) {
      await tx.delete(
        'memory',
        where: 'id = ? AND draft = 1',
        whereArgs: [value.id],
      );
    }
  });
  @override
  Future<void> delete(String id, {bool draftOnly = false}) async =>
      (await database()).transaction((tx) async {
        await tx.delete(
          'memory',
          where: draftOnly ? 'id = ? AND draft = 1' : 'id = ?',
          whereArgs: [id],
        );
      });
  @override
  Future<List<WalkMemory>> exportAll() async => (await database()).transaction((
    tx,
  ) async {
    final rows = await tx.query('memory', columns: ['id', 'draft']);
    final result = <WalkMemory>[];
    var photoBytes = 0;
    for (final row in rows) {
      final m = (await readFrom(tx, row['id'] as String, row['draft'] == 1))!;
      photoBytes += m.photoLength;
      if (photoBytes > 80 * 1024 * 1024) {
        throw const FormatException(
          'Photos exceed the backup size limit. No backup was written.',
        );
      }
      result.add(m);
    }
    return result;
  });
}
