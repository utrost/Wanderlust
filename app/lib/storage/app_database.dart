import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../memories/memory_store.dart';
import '../blocks/block_geometry.dart' show blockRevision;

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
          version: 2,
          onConfigure: (db) async {
            await db.execute('PRAGMA foreign_keys = ON');
            await db.execute('PRAGMA busy_timeout = 5000');
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
            await _createSpatial(db);
          },
          onOpen: (db) async {
            final identity = await db.rawQuery('PRAGMA application_id');
            if (identity.single.values.single != applicationId) {
              throw StateError(
                'This database belongs to an unsupported app lineage.',
              );
            }
            // Only derived caches are invalidated. Source maps and recordings
            // survive algorithm upgrades, including interrupted rebuilds.
            await db.transaction((tx) async {
              final revision = await tx.query(
                'analysis_stamp',
                where: 'cell = ?',
                whereArgs: ['__block_revision__'],
              );
              if (revision.isEmpty ||
                  revision.single['stamp'] != blockRevision) {
                await tx.delete('block_cache');
                await tx.delete('topology_cache');
                await tx.delete('analysis_stamp');
                await tx.insert('analysis_stamp', {
                  'cell': '__block_revision__',
                  'stamp': blockRevision,
                });
              }
            });
          },
          // The com.simiono identity starts a new schema lineage. No upgrade or
          // downgrade may silently open a database from another lineage.
          onUpgrade: (db, oldVersion, newVersion) async {
            final identity = await db.rawQuery('PRAGMA application_id');
            if (identity.single.values.single != applicationId) {
              throw StateError('Unsupported database lineage');
            }
            if (oldVersion == 1 && newVersion == 2) {
              await _createSpatial(db);
              return;
            }
            throw StateError('Unsupported database version: $oldVersion');
          },
        ),
      );
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  static Future<void> _createSpatial(DatabaseExecutor db) async {
    await db.execute(
      'CREATE TABLE topology_cache (key TEXT PRIMARY KEY, data TEXT NOT NULL, used INTEGER NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE analysis_stamp (cell TEXT PRIMARY KEY, stamp TEXT NOT NULL)',
    );
    await db.execute('ALTER TABLE offline_area ADD COLUMN bbox TEXT');
    await db.execute(
      'ALTER TABLE offline_area ADD COLUMN indexed INTEGER NOT NULL DEFAULT 0',
    );
    await db.execute(
      'CREATE TABLE map_cell (source TEXT NOT NULL REFERENCES offline_area(version) ON DELETE CASCADE, cell TEXT NOT NULL, geojson TEXT NOT NULL, bytes INTEGER NOT NULL, sections INTEGER NOT NULL, digest TEXT NOT NULL, PRIMARY KEY(source,cell))',
    );
    await db.execute('CREATE INDEX map_cell_lookup ON map_cell(cell)');
    await db.execute(
      'CREATE TABLE match_evidence (walk_id INTEGER NOT NULL REFERENCES recorded_walk(id) ON DELETE CASCADE, network TEXT NOT NULL, fingerprint TEXT NOT NULL, supported TEXT NOT NULL, estimated TEXT NOT NULL, unmatched TEXT NOT NULL, PRIMARY KEY(walk_id,network))',
    );
    await db.execute(
      'CREATE TABLE walk_bounds (walk_id INTEGER PRIMARY KEY REFERENCES recorded_walk(id) ON DELETE CASCADE, fingerprint TEXT NOT NULL, bbox TEXT)',
    );
    await db.execute(
      'CREATE TABLE block_cache (id TEXT PRIMARY KEY, owner TEXT NOT NULL, revision TEXT NOT NULL, geometry TEXT NOT NULL, complete INTEGER NOT NULL, history TEXT NOT NULL, dirty INTEGER NOT NULL DEFAULT 1, west REAL NOT NULL, south REAL NOT NULL, east REAL NOT NULL, north REAL NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE block_section (block TEXT NOT NULL REFERENCES block_cache(id) ON DELETE CASCADE, section INTEGER NOT NULL, PRIMARY KEY(block,section))',
    );
    await db.execute(
      'CREATE INDEX block_section_lookup ON block_section(section)',
    );
    await db.execute(
      'CREATE TABLE supported_section (walk_id INTEGER NOT NULL REFERENCES recorded_walk(id) ON DELETE CASCADE, network TEXT NOT NULL, section INTEGER NOT NULL, PRIMARY KEY(walk_id,network,section))',
    );
    await db.execute(
      'CREATE INDEX supported_section_lookup ON supported_section(section)',
    );
    await db.execute(
      'CREATE TABLE network_source (network TEXT NOT NULL, source TEXT NOT NULL REFERENCES offline_area(version) ON DELETE CASCADE, PRIMARY KEY(network,source))',
    );
    await db.execute(
      'CREATE TABLE block_source (block TEXT NOT NULL REFERENCES block_cache(id) ON DELETE CASCADE, source TEXT NOT NULL REFERENCES offline_area(version) ON DELETE CASCADE, PRIMARY KEY(block,source))',
    );
    for (final event in ['INSERT', 'DELETE']) {
      final row = event == 'INSERT' ? 'NEW' : 'OLD';
      await db.execute(
        'CREATE TRIGGER dirty_block_${event.toLowerCase()} AFTER $event ON supported_section BEGIN UPDATE block_cache SET dirty = 1 WHERE id IN (SELECT block FROM block_section WHERE section = $row.section); END',
      );
    }
    await db.execute(
      "CREATE TRIGGER changed_walk_evidence AFTER UPDATE OF fingerprint,trace_metadata ON recorded_walk WHEN (OLD.fingerprint IS NOT NULL AND OLD.fingerprint IS NOT NEW.fingerprint) OR json_extract(OLD.trace_metadata, '\$.confirmedSections') IS NOT json_extract(NEW.trace_metadata, '\$.confirmedSections') OR json_extract(OLD.trace_metadata, '\$.activity') IS NOT json_extract(NEW.trace_metadata, '\$.activity') BEGIN DELETE FROM supported_section WHERE walk_id = OLD.id; DELETE FROM match_evidence WHERE walk_id = OLD.id; END",
    );
    const invalidate =
        "DELETE FROM supported_section WHERE network IN (SELECT network FROM network_source WHERE source = OLD.version); DELETE FROM match_evidence WHERE network IN (SELECT network FROM network_source WHERE source = OLD.version); DELETE FROM walk_match WHERE network_version IN (SELECT network FROM network_source WHERE source = OLD.version); DELETE FROM coverage_edge WHERE network_version IN (SELECT network FROM network_source WHERE source = OLD.version); DELETE FROM coverage_network WHERE version IN (SELECT network FROM network_source WHERE source = OLD.version); DELETE FROM block_cache WHERE id IN (SELECT block FROM block_source WHERE source = OLD.version); DELETE FROM network_source WHERE source = OLD.version;";
    await db.execute(
      'CREATE TRIGGER remove_map_derived BEFORE DELETE ON offline_area BEGIN $invalidate END',
    );
    await db.execute(
      'CREATE TRIGGER refresh_map_derived BEFORE UPDATE OF geojson ON offline_area WHEN OLD.geojson != NEW.geojson BEGIN $invalidate DELETE FROM map_cell WHERE source = OLD.version; UPDATE offline_area SET indexed = 0 WHERE version = OLD.version; END',
    );
    await db.execute(
      "CREATE TRIGGER added_map_geometry AFTER INSERT ON offline_area WHEN NEW.bbox IS NOT NULL BEGIN DELETE FROM block_cache WHERE west <= json_extract(NEW.bbox, '\$[2]') AND east >= json_extract(NEW.bbox, '\$[0]') AND south <= json_extract(NEW.bbox, '\$[3]') AND north >= json_extract(NEW.bbox, '\$[1]'); END",
    );
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
