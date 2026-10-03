import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../memories/memory_store.dart';

/// Owns the connection and schema; repositories share this lifetime.
class AppDatabase {
  AppDatabase({DatabaseFactory? factory, String? databasePath})
    : _providedFactory = factory,
      _path = databasePath;
  final DatabaseFactory? _providedFactory;
  DatabaseFactory get _factory => _providedFactory ?? databaseFactory;
  final String? _path;
  Future<Database>? _opening;
  // Distinguishes this fresh schema lineage from earlier experimental databases.
  static const applicationId = 0x57414e44; // WAND

  Future<Database> get database => _opening ??= _open();
  Future<Database> _open() async {
    try {
      final file =
          _path ??
          path.join(await _factory.getDatabasesPath(), 'wanderlust.db');
      return await _factory.openDatabase(
        file,
        options: OpenDatabaseOptions(
          version: 1,
          onConfigure: (db) async {
            await db.execute('PRAGMA foreign_keys = ON');
          },
          onCreate: (db, version) async {
            await db.execute('PRAGMA application_id = $applicationId');
            await db.execute(
              "CREATE TABLE recorded_walk (id INTEGER PRIMARY KEY, started_at TEXT NOT NULL, ended_at TEXT, status TEXT NOT NULL CHECK(status IN ('recording','completed','interrupted')), uid TEXT, trace_metadata TEXT NOT NULL DEFAULT '{}', fingerprint TEXT)",
            );
            await db.execute(
              'CREATE TABLE recorded_point (walk_id INTEGER NOT NULL REFERENCES recorded_walk(id), seq INTEGER NOT NULL, position TEXT NOT NULL, timestamp TEXT NOT NULL, PRIMARY KEY(walk_id, seq))',
            );
            await _createCoverage(db);
            await _createTransfer(db);
            await _createAreas(db);
            await _createPreferences(db);
            await MemoryStore.create(db);
          },
          onOpen: (db) async {
            final identity = await db.rawQuery('PRAGMA application_id');
            if (identity.single.values.single != applicationId) {
              throw StateError(
                'This database belongs to an unsupported app lineage.',
              );
            }
          },
          // The com.simiono identity starts a new schema lineage. No upgrade or
          // downgrade may silently open a database from another lineage.
          onUpgrade: (db, oldVersion, newVersion) async {
            throw StateError('Unsupported database version: $oldVersion');
          },
        ),
      );
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  static Future<void> _createPreferences(DatabaseExecutor db) => db.execute(
    'CREATE TABLE walk_preferences (id INTEGER PRIMARY KEY CHECK(id = 1), json TEXT NOT NULL)',
  );

  static Future<void> _createAreas(DatabaseExecutor db) async {
    await db.execute(
      'CREATE TABLE offline_area (version TEXT PRIMARY KEY, name TEXT NOT NULL, geojson TEXT NOT NULL, downloaded_at TEXT NOT NULL, bytes INTEGER NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE offline_selection (id INTEGER PRIMARY KEY CHECK(id = 1), version TEXT REFERENCES offline_area(version) ON DELETE SET NULL)',
    );
    await db.insert('offline_selection', {'id': 1});
  }

  static Future<void> _createTransfer(DatabaseExecutor db) async {
    await db.execute('CREATE UNIQUE INDEX walk_uid ON recorded_walk(uid)');
    await db.execute(
      "CREATE TRIGGER assign_walk_uid AFTER INSERT ON recorded_walk WHEN NEW.uid IS NULL BEGIN UPDATE recorded_walk SET uid = lower(hex(randomblob(16))) WHERE id = NEW.id; END",
    );
  }

  static Future<void> _createCoverage(DatabaseExecutor db) async {
    await db.execute(
      'CREATE TABLE coverage_network (version TEXT PRIMARY KEY, area_id TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE coverage_edge (network_version TEXT NOT NULL REFERENCES coverage_network(version), edge_id INTEGER NOT NULL, PRIMARY KEY(network_version, edge_id))',
    );
    await db.execute(
      'CREATE TABLE walk_match (walk_id INTEGER NOT NULL REFERENCES recorded_walk(id), network_version TEXT NOT NULL REFERENCES coverage_network(version), fingerprint TEXT NOT NULL, PRIMARY KEY(walk_id, network_version))',
    );
    await db.execute(
      'CREATE TABLE walk_edge (walk_id INTEGER NOT NULL, network_version TEXT NOT NULL, edge_id INTEGER NOT NULL, PRIMARY KEY(walk_id, network_version, edge_id), FOREIGN KEY(walk_id, network_version) REFERENCES walk_match(walk_id, network_version) ON DELETE CASCADE, FOREIGN KEY(network_version, edge_id) REFERENCES coverage_edge(network_version, edge_id))',
    );
    await db.execute(
      'CREATE INDEX coverage_counts ON walk_edge(network_version, edge_id)',
    );
  }

  Future<void> close() async {
    if (_opening != null) await (await _opening!).close();
  }
}
