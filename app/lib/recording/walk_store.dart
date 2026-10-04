import 'package:geolocator/geolocator.dart';
import 'package:sqflite/sqflite.dart';

import '../coverage/coverage_store.dart';
import '../data/area_network.dart';
import '../maps/area_store.dart';
import '../memories/memory.dart';
import '../memories/memory_repository.dart';
import '../memories/memory_store.dart';
import '../review/gap_review_store.dart';
import '../settings/preferences_store.dart';
import '../settings/walk_preferences.dart';
import '../storage/app_database.dart';
import '../storage/backup_importer.dart';
import '../storage/coverage_repository.dart';
import '../storage/offline_map_repository.dart';
import '../storage/preferences_repository.dart';
import '../storage/walk_repository.dart';
import '../transfer/backup_data.dart';
import '../transfer/walk_importer.dart';
import 'activity_type.dart';
import 'gps_diagnostics.dart';
import 'saved_walk.dart';
import 'walk_history.dart';
import 'walk_journal.dart';

export 'saved_walk.dart';
export 'walk_journal.dart';

/// Compatibility facade for existing screens. SQL and policies live in focused
/// repositories sharing one connection; backup imports own one transaction.
class SqliteWalkStore
    implements
        WalkStore,
        GpsDiagnosticsStore,
        WalkHistory,
        GapReviewStore,
        CoverageStore,
        AreaStore,
        PreferencesStore,
        WalkImporter {
  SqliteWalkStore({DatabaseFactory? factory, String? databasePath})
    : database = AppDatabase(factory: factory, databasePath: databasePath);
  final AppDatabase database;
  late final walksRepository = WalkRepository(database);
  late final mapsRepository = OfflineMapRepository(database);
  late final coverageRepository = CoverageRepository(database);
  late final preferencesRepository = PreferencesRepository(database);
  late final importerRepository = BackupImporter(database);
  late final MemoryRepository memories = MemoryStore(() => database.database);
  @override
  Future<void> saveConfirmedSections(String uid, List<int> edges) =>
      walksRepository.saveConfirmedSections(uid, edges);
  BackupData get backupData =>
      BackupData(history: this, maps: this, settings: this, memories: memories);
  @override
  Future<String?> walkUid(int id) => walksRepository.walkUid(id);
  @override
  Future<List<SavedWalk>> listSaved() => walksRepository.listSaved();
  @override
  Future<SavedWalk> loadWalk(int id) => walksRepository.loadWalk(id);
  @override
  Future<List<SavedWalk>> listSummaries({bool recover = false}) =>
      walksRepository.listSummaries(recover: recover);
  @override
  Future<void> setActivity(String uid, WalkActivity activity) =>
      walksRepository.setActivity(uid, activity);
  @override
  Future<void> setFavourite(String uid, bool favourite) =>
      walksRepository.setFavourite(uid, favourite);
  @override
  Future<WalkPreferences> readPreferences() =>
      preferencesRepository.readPreferences();
  @override
  Future<void> savePreferences(WalkPreferences value) =>
      preferencesRepository.savePreferences(value);
  @override
  Future<List<SavedWalk>> recoverAndList() => walksRepository.recoverAndList();
  @override
  Future<int> begin(
    DateTime startedAt, {
    WalkActivity activity = WalkActivity.walk,
  }) => walksRepository.begin(startedAt, activity: activity);
  @override
  Future<void> saveGpsDiagnostics(int walkId, Map<String, Object?> metrics) =>
      walksRepository.saveGpsDiagnostics(walkId, metrics);
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
  @override
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
