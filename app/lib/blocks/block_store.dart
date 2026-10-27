import 'block_geometry.dart';
import 'block_progress.dart';

abstract class BlockCacheStore {
  Future<int> completedCount();
  Future<bool> blocksPending();
  Future<BlockTopology?> readTopology(String key);
  Future<void> writeTopology(String key, BlockTopology topology);
  Future<Map<String, String>> analysisStamps();
  Future<void> saveAnalysisStamp(String cell, String stamp);
  Future<void> saveBlocks(
    List<StreetBlock> blocks,
    Map<String, BlockProgress> progress,
    List<String> sources,
  );
  Future<void> reconcileBlocks();
}
