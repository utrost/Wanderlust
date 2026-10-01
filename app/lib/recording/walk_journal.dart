import 'package:geolocator/geolocator.dart';

import 'saved_walk.dart';

abstract class WalkStore {
  Future<List<SavedWalk>> recoverAndList();
  Future<int> begin(DateTime startedAt);
  Future<void> append(int id, int sequence, Position point);
  Future<void> finish(int id, DateTime endedAt, String status);
  Future<void> close();
}
