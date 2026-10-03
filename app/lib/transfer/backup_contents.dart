import '../memories/memory.dart';
import '../recording/saved_walk.dart';
import '../settings/walk_preferences.dart';

/// Validated metadata for a streamed archive, or a single imported GPX walk.
class BackupContents {
  const BackupContents(
    this.walks,
    this.memories, {
    this.maps = const [],
    this.preferences,
    this.activeMap,
  });
  final List<SavedWalk> walks;
  final List<WalkMemory> memories;
  final List<String> maps;
  final WalkPreferences? preferences;
  final String? activeMap;
}
