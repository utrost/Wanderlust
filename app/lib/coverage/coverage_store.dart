import '../data/area_network.dart';

abstract class CoverageStore {
  Future<void> registerNetwork(AreaNetwork network);
  Future<String?> matchFingerprint(int walkId, String networkVersion);
  Future<void> replaceWalkMatch(
    int walkId,
    String networkVersion,
    String fingerprint,
    Set<int> edges,
  );
  Future<Map<int, int>> readCounts(String networkVersion);
}
