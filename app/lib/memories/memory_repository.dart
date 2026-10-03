import 'memory.dart';

/// Persistent notes, drafts and photos, without exposing database handles.
abstract interface class MemoryRepository {
  Future<List<WalkMemory>> list({String? walkUid});
  Future<WalkMemory?> read(String id, bool draft);
  Future<void> put(WalkMemory memory);
  Future<void> delete(String id, {bool draftOnly = false});
}
