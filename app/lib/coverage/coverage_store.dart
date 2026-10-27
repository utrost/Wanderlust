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
  Future<Map<int, int>> readCombinedCounts(List<String> versions);
  Future<Map<int, int>> readCounts(String networkVersion);
}

class StoredMatch {
  const StoredMatch(
    this.fingerprint,
    this.supported,
    this.estimated,
    this.unmatched,
  );
  final String fingerprint;
  final Set<int> supported, estimated;
  final List<int> unmatched;
}

abstract class PersistentCoverageStore {
  Future<void> syncEvidenceFingerprints(Map<int, String> expected);
  Future<StoredMatch?> readEvidence(int walk, String network);
  Future<void> writeEvidence(int walk, String network, StoredMatch result);
  Future<List<double>?> readWalkBounds(int walk, String fingerprint);
  Future<void> writeWalkBounds(
    int walk,
    String fingerprint,
    List<double> bounds,
  );
}

/// Bulk access keeps cached startup independent of walk-by-cell SQL round trips.
abstract class BatchCoverageStore {
  Future<Map<int, List<double>>> readWalkBoundsBatch(Map<int, String> traces);
  Future<Map<int, (StoredMatch, String?)>> readEvidenceBatch(
    String network, {
    List<int>? walks,
  });
}
