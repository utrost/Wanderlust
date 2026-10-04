import 'activity_type.dart';
import 'saved_walk.dart';

/// Read and organize history without controlling the recording journal.
abstract interface class WalkHistory {
  Future<String?> walkUid(int id);
  Future<List<SavedWalk>> listSaved();
  Future<List<SavedWalk>> listSummaries({bool recover = false});
  Future<SavedWalk> loadWalk(int id);
  Future<void> setActivity(String uid, WalkActivity activity);
  Future<void> setFavourite(String uid, bool favourite);
}
