import '../memories/memory.dart';
import '../recording/saved_walk.dart';
import '../settings/walk_preferences.dart';

/// Commits a validated import atomically across all its selected data.
abstract interface class WalkImporter {
  Future<int> mergeWalks(
    List<SavedWalk> incoming, {
    bool deduplicateTrace = false,
    void Function(int completed, int total)? onWalkProgress,
    List<WalkMemory> memories = const [],
    Stream<WalkMemory>? memoryStream,
    Stream<SavedWalk>? walkStream,
    Stream<String>? mapStream,
    List<String> maps = const [],
    WalkPreferences? preferences,
    String? activeMap,
  });
}
