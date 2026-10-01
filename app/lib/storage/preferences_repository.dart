import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../settings/preferences_store.dart';
import '../settings/walk_preferences.dart';
import 'app_database.dart';

class PreferencesRepository implements PreferencesStore {
  PreferencesRepository(this.connection);
  final AppDatabase connection;
  Future<Database> get _db => connection.database;
  @override
  Future<WalkPreferences> readPreferences() async {
    final rows = await (await _db).query('walk_preferences', where: 'id = 1');
    return rows.isEmpty
        ? const WalkPreferences()
        : WalkPreferences.fromJson(
            jsonDecode(rows.single['json'] as String) as Map<String, dynamic>,
          );
  }

  @override
  Future<void> savePreferences(WalkPreferences value) async {
    await writeTo(await _db, value);
  }

  static Future<void> writeTo(
    DatabaseExecutor db,
    WalkPreferences value,
  ) async {
    await db.insert('walk_preferences', {
      'id': 1,
      'json': jsonEncode(value.toJson()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
