import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../data/area_network.dart';
import '../maps/area_store.dart';
import 'app_database.dart';

class OfflineMapCapacityException extends StateError {
  OfflineMapCapacityException()
    : super(
        'Eight maps are saved. Remove an unused map before downloading another.',
      );
}

class OfflineMapRepository implements AreaStore {
  OfflineMapRepository(this.connection);
  final AppDatabase connection;
  Future<Database> get _db => connection.database;
  @override
  Future<List<OfflineArea>> listAreas() async {
    final rows = await (await _db).query(
      'offline_area',
      columns: ['version', 'name', 'downloaded_at', 'bytes'],
      orderBy: 'downloaded_at DESC',
    );
    return rows
        .map(
          (r) => OfflineArea(
            version: r['version'] as String,
            name: r['name'] as String,
            downloadedAt: DateTime.parse(r['downloaded_at'] as String),
            bytes: r['bytes'] as int,
          ),
        )
        .toList();
  }

  // Android CursorWindow cannot return a multi-megabyte value in one row.
  // Keep each result below 512 KiB even for four-byte Unicode code points.
  static const _mapChunkCharacters = 128 * 1024;

  Future<String?> _readArea(DatabaseExecutor db, String version) async {
    final lengths = await db.rawQuery(
      'SELECT length(geojson) AS characters FROM offline_area WHERE version = ?',
      [version],
    );
    if (lengths.isEmpty) return null;
    final length = lengths.single['characters'] as int;
    final source = StringBuffer();
    for (var start = 1; start <= length; start += _mapChunkCharacters) {
      final rows = await db.rawQuery(
        'SELECT substr(geojson, ?, ?) AS chunk FROM offline_area WHERE version = ?',
        [start, _mapChunkCharacters, version],
      );
      source.write(rows.single['chunk'] as String);
    }
    return source.toString();
  }

  @override
  Future<String?> readArea(String version) async =>
      (await _db).transaction((txn) => _readArea(txn, version));

  @override
  Future<String?> readActiveArea() async =>
      (await _db).transaction((txn) async {
        final rows = await txn.query(
          'offline_selection',
          columns: ['version'],
          where: 'id = 1',
        );
        final version = rows.isEmpty ? null : rows.single['version'] as String?;
        return version == null ? null : _readArea(txn, version);
      });

  @override
  Future<void> saveArea(String geojson) async {
    await (await _db).transaction((tx) => writeTo(tx, geojson));
  }

  static Future<void> writeTo(
    DatabaseExecutor tx,
    String geojson, {
    bool keepExisting = false,
  }) async {
    final bytes = utf8.encode(geojson).length;
    if (bytes > 16 * 1024 * 1024) {
      throw const FormatException('Map exceeds the 16 MiB offline limit.');
    }
    final area = AreaNetwork.parse(geojson);
    final rows = await tx.query('offline_area', columns: ['version']);
    final exists = rows.any((row) => row['version'] == area.version);
    if (keepExisting && exists) return;
    if (!exists && rows.length >= 8) {
      throw OfflineMapCapacityException();
    }
    final values = {
      'name': area.name,
      'geojson': geojson,
      'downloaded_at': DateTime.now().toUtc().toIso8601String(),
      'bytes': bytes,
    };
    // UPDATE preserves the selection foreign key; REPLACE would clear it.
    if (exists) {
      await tx.update(
        'offline_area',
        values,
        where: 'version = ?',
        whereArgs: [area.version],
      );
    } else {
      await tx.insert('offline_area', {'version': area.version, ...values});
    }
  }

  @override
  Future<void> selectArea(String? version) async {
    await (await _db).update('offline_selection', {
      'version': version,
    }, where: 'id = 1');
  }

  @override
  Future<void> deleteArea(String version) async {
    await (await _db).delete(
      'offline_area',
      where: 'version = ?',
      whereArgs: [version],
    );
  }
}
