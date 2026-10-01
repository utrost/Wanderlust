import 'package:geolocator/geolocator.dart';
import 'package:sqflite/sqflite.dart';

import '../coverage/coverage_store.dart';
import '../data/area_network.dart';
import '../maps/area_store.dart';
import '../memories/memory.dart';
import '../memories/memory_store.dart';
import '../settings/walk_preferences.dart';
import '../storage/app_database.dart';
import '../storage/backup_importer.dart';
import '../storage/coverage_repository.dart';
import '../storage/offline_map_repository.dart';
import '../storage/preferences_repository.dart';
import '../storage/walk_repository.dart';
import 'saved_walk.dart';

export 'saved_walk.dart';

abstract class WalkStore {
  Future<List<SavedWalk>> recoverAndList();
  Future<int> begin(DateTime startedAt);
  Future<void> append(int id, int sequence, Position point);
  Future<void> finish(int id, DateTime endedAt, String status);
  Future<void> close();
}

/// Compatibility facade for existing screens. SQL and policies live in focused
/// repositories sharing one connection; backup imports own one transaction.
class SqliteWalkStore implements WalkStore, CoverageStore, AreaStore {
  SqliteWalkStore({DatabaseFactory? factory, String? databasePath})
    : database = AppDatabase(factory: factory, databasePath: databasePath);
  final AppDatabase database;
  late final walksRepository = WalkRepository(database);
  late final mapsRepository = OfflineMapRepository(database);
  late final coverageRepository = CoverageRepository(database);
  late final preferencesRepository = PreferencesRepository(database);
  late final importerRepository = BackupImporter(database);
  late final memories = MemoryStore(() => database.database);
  Future<String?> walkUid(int id) => walksRepository.walkUid(id);
  Future<List<SavedWalk>> listSaved() => walksRepository.listSaved();
  Future<SavedWalk> loadWalk(int id) => walksRepository.loadWalk(id);
  Future<List<SavedWalk>> listSummaries({bool recover = false}) =>
      walksRepository.listSummaries(recover: recover);
  Future<void> setFavourite(String uid, bool favourite) =>
      walksRepository.setFavourite(uid, favourite);
  Future<WalkPreferences> readPreferences() =>
      preferencesRepository.readPreferences();
  Future<void> savePreferences(WalkPreferences value) =>
      preferencesRepository.savePreferences(value);
  @override
  Future<List<SavedWalk>> recoverAndList() => walksRepository.recoverAndList();
  @override
  Future<int> begin(DateTime startedAt) => walksRepository.begin(startedAt);
  @override
  Future<void> append(int id, int sequence, Position point) =>
      walksRepository.append(id, sequence, point);
  @override
  Future<void> finish(int id, DateTime endedAt, String status) =>
      walksRepository.finish(id, endedAt, status);
  @override
  Future<void> close() => database.close();
  @override
  Future<List<OfflineArea>> listAreas() => mapsRepository.listAreas();
  @override
  Future<String?> readArea(String version) => mapsRepository.readArea(version);
  @override
  Future<String?> readActiveArea() => mapsRepository.readActiveArea();
  @override
  Future<void> saveArea(String geojson) => mapsRepository.saveArea(geojson);
  @override
  Future<void> selectArea(String? version) =>
      mapsRepository.selectArea(version);
  @override
  Future<void> deleteArea(String version) => mapsRepository.deleteArea(version);
  @override
  Future<void> registerNetwork(AreaNetwork network) =>
      coverageRepository.registerNetwork(network);
  @override
  Future<String?> matchFingerprint(int walkId, String networkVersion) =>
      coverageRepository.matchFingerprint(walkId, networkVersion);
  @override
  Future<void> replaceWalkMatch(
    int walkId,
    String networkVersion,
    String fingerprint,
    Set<int> edges,
  ) => coverageRepository.replaceWalkMatch(
    walkId,
    networkVersion,
    fingerprint,
    edges,
  );
  @override
  Future<Map<int, int>> readCombinedCounts(List<String> versions) =>
      coverageRepository.readCombinedCounts(versions);
  @override
  Future<Map<int, int>> readCounts(String version) =>
      coverageRepository.readCounts(version);
  Future<int> mergeWalks(
    List<SavedWalk> incoming, {
    bool deduplicateTrace = false,
    List<WalkMemory> memories = const [],
    Stream<WalkMemory>? memoryStream,
    Stream<SavedWalk>? walkStream,
    List<String> maps = const [],
    WalkPreferences? preferences,
    String? activeMap,
  }) => importerRepository.mergeWalks(
    incoming,
    deduplicateTrace: deduplicateTrace,
    memories: memories,
    memoryStream: memoryStream,
    walkStream: walkStream,
    maps: maps,
    preferences: preferences,
    activeMap: activeMap,
  );
}
