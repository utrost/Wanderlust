import 'package:geolocator/geolocator.dart';

import 'activity_type.dart';
import 'saved_walk.dart';

abstract class WalkStore {
  Future<List<SavedWalk>> recoverAndList();
  Future<int> begin(
    DateTime startedAt, {
    WalkActivity activity = WalkActivity.walk,
  });
  Future<void> append(int id, int sequence, Position point);
  Future<void> finish(int id, DateTime endedAt, String status);
  Future<void> close();
}
