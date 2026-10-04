/// User-confirmed route sections, independent of recorded GPS and matching.
abstract interface class GapReviewStore {
  Future<void> saveConfirmedSections(String uid, List<int> edges);
}
