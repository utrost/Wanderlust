import 'package:flutter/foundation.dart';

import '../memories/memory.dart';
import '../memories/memory_photos.dart';
import '../memories/memory_store.dart';

/// Loads map pins and recovers drafts. Editing/navigation belongs to the screen.
class MapMemoriesController extends ChangeNotifier {
  MapMemoriesController(this.store);
  final MemoryStore store;
  List<WalkMemory> items = [];
  bool ready = false;
  String? error;
  bool _disposed = false;

  void clearError() {
    error = null;
  }

  void reportOpenFailure() {
    error = 'Could not open a memory. Please retry.';
    if (!_disposed) notifyListeners();
  }

  Future<void> load({bool recover = false}) async {
    try {
      if (recover) {
        try {
          await DeviceMemoryPhotos().recover(store);
        } catch (_) {
          error =
              'Photo recovery needs attention. Open Memories to continue your draft.';
        }
      }
      final loaded = await store.list();
      if (!_disposed) items = loaded;
    } catch (_) {
      error = 'Could not load memories. Tap Memories to retry.';
    } finally {
      ready = true;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
