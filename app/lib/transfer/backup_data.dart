import '../maps/area_store.dart';
import '../memories/memory_repository.dart';
import '../recording/walk_history.dart';
import '../settings/preferences_store.dart';

/// Data dependencies for backup creation, independent of SQLite and widgets.
class BackupData {
  const BackupData({
    required this.history,
    required this.maps,
    required this.settings,
    required this.memories,
  });
  final WalkHistory history;
  final AreaStore maps;
  final PreferencesStore settings;
  final MemoryRepository memories;
}
