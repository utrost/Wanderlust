import 'package:wanderlust/memories/memory.dart';
import 'package:wanderlust/memories/memory_repository.dart';

class FakeMemoryStore implements MemoryRepository {
  final Map<String, WalkMemory> entries = {};
  bool fail = false;
  String key(String id, bool draft) => '$id:$draft';
  @override
  Future<List<WalkMemory>> list({String? walkUid}) async => entries.values
      .where((m) => walkUid == null || m.walkUid == walkUid)
      .toList();
  @override
  Future<WalkMemory?> read(String id, bool draft) async =>
      entries[key(id, draft)];
  @override
  Future<void> put(WalkMemory m) async {
    if (fail) throw StateError('disk full');
    entries[key(m.id, m.draft)] = m;
    if (!m.draft) entries.remove(key(m.id, true));
  }

  @override
  Future<void> delete(String id, {bool draftOnly = false}) async {
    entries.remove(key(id, true));
    if (!draftOnly) entries.remove(key(id, false));
  }

  @override
  Future<List<WalkMemory>> exportAll() async => entries.values.toList();
}
