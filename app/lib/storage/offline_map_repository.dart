import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import '../maps/map_cells.dart';

import 'package:sqflite/sqflite.dart';

import '../data/area_network.dart';
import '../maps/area_store.dart';
import 'app_database.dart';

class OfflineMapRepository implements SpatialAreaStore {
  OfflineMapRepository(this.connection);
  final AppDatabase connection;
  Future<Database> get _db => connection.database;
  @override
  Future<List<OfflineArea>> listAreas() async {
    final rows = await (await _db).rawQuery(
      'SELECT a.version,a.name,a.downloaded_at,a.bytes,a.bbox,COALESCE((SELECT SUM(length(CAST(c.geojson AS BLOB))) FROM map_cell c WHERE c.source=a.version),0) AS cache_bytes FROM offline_area a ORDER BY a.downloaded_at DESC',
    );
    return rows
        .map(
          (r) => OfflineArea(
            version: r['version'] as String,
            name: r['name'] as String,
            downloadedAt: DateTime.parse(r['downloaded_at'] as String),
            bytes: r['bytes'] as int,
            cacheBytes: r['cache_bytes'] as int,
            bounds: r['bbox'] == null
                ? null
                : geographicBounds(
                    (jsonDecode(r['bbox'] as String) as List)
                        .cast<num>()
                        .map((n) => n.toDouble())
                        .toList(),
                  ),
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
    final values = {
      'name': area.name,
      'geojson': geojson,
      'downloaded_at': DateTime.now().toUtc().toIso8601String(),
      'bytes': bytes,
      'bbox': jsonEncode(area.bbox),
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

  @override
  Future<String?> selectedVersion() async {
    final rows = await (await _db).query(
      'offline_selection',
      columns: ['version'],
      where: 'id = 1',
    );
    return rows.isEmpty ? null : rows.single['version'] as String?;
  }

  @override
  Future<bool> indexNext(Offset? focus) async {
    final db = await _db;
    final rows = (await db.query(
      'offline_area',
      columns: ['version', 'bbox'],
      where: 'indexed = 0',
    )).toList();
    if (rows.isEmpty) return false;
    double distance(Map<String, Object?> row) {
      if (focus == null || row['bbox'] == null) return double.infinity;
      final b = geographicBounds(
        (jsonDecode(row['bbox'] as String) as List)
            .cast<num>()
            .map((n) => n.toDouble())
            .toList(),
      );
      return b.contains(focus) ? 0 : (b.center - focus).distanceSquared;
    }

    rows.sort((a, b) => distance(a).compareTo(distance(b)));
    final version = rows.first['version'] as String;
    final source = await readArea(version);
    if (source == null) return true;
    // A partial index is invisible and safely replaced after interruption.
    await db.delete('map_cell', where: 'source = ?', whereArgs: [version]);
    await for (final chunk in streamMapCells(source)) {
      final exists = await db.query(
        'offline_area',
        columns: ['version'],
        where: 'version = ?',
        whereArgs: [version],
      );
      if (exists.isEmpty) return true;
      await db.insert(
        'map_cell',
        chunk,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    final bbox = await compute(_sourceBounds, source);
    await db.update(
      'offline_area',
      {'indexed': 1, 'bbox': bbox},
      where: 'version = ?',
      whereArgs: [version],
    );
    return true;
  }

  @override
  Future<List<CellSource>> listCells() async => [
    for (final r in await (await _db).rawQuery(
      'SELECT c.cell, c.source, c.bytes, c.sections, c.digest FROM map_cell c JOIN offline_area a ON a.version = c.source WHERE a.indexed = 1',
    ))
      CellSource(
        r['cell'] as String,
        r['source'] as String,
        r['bytes'] as int,
        r['sections'] as int,
        r['digest'] as String,
      ),
  ];
  @override
  Future<String?> readCell(String cell) async {
    final db = await _db;
    // Cell payloads can exceed CursorWindow on dense maps: chunk text reads.
    final rows = await db.rawQuery(
      'SELECT c.source,c.digest,c.encoding,length(c.geojson) AS n FROM map_cell c JOIN offline_area a ON a.version = c.source WHERE c.cell = ? AND a.indexed = 1 ORDER BY c.source',
      [cell],
    );
    final sources = <Object>[], versions = <String>[];
    for (final row in rows) {
      versions.add(row['source'] as String);
      final b = StringBuffer();
      final compressed = BytesBuilder(copy: false);
      for (
        var start = 1;
        start <= (row['n'] as int);
        start += _mapChunkCharacters
      ) {
        final part = await db.rawQuery(
          'SELECT substr(geojson,?,?) AS chunk FROM map_cell WHERE cell = ? AND source = ?',
          [start, _mapChunkCharacters, cell, row['source']],
        );
        if (row['encoding'] == 1) {
          compressed.add(part.single['chunk'] as Uint8List);
        } else {
          b.write(part.single['chunk']);
        }
      }
      sources.add(row['encoding'] == 1 ? compressed.takeBytes() : b.toString());
    }
    return sources.isEmpty
        ? null
        : compute(_mergeCell, (cell, sources, versions));
  }
}

String _mergeCell((String, List<Object>, List<String>) value) =>
    mergeCellSources(value.$1, [
      for (final source in value.$2)
        source is String
            ? source
            : utf8.decode(gzip.decode(source as Uint8List)),
    ], value.$3);

String _sourceBounds(String source) =>
    jsonEncode((jsonDecode(source) as Map)['bbox']);
