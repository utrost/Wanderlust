import 'package:flutter/foundation.dart';

import '../memories/memory.dart';
import '../memories/memory_photos.dart';
import '../memories/memory_repository.dart';

/// Loads map pins and recovers drafts. Editing/navigation belongs to the screen.
class MapMemoriesController extends ChangeNotifier {
  MapMemoriesController(this.store, {Future<void> Function()? recoverPhotos})
    : _recoverPhotos =
          recoverPhotos ?? (() => DeviceMemoryPhotos().recover(store));
  final MemoryRepository store;
  final Future<void> Function() _recoverPhotos;
  List<WalkMemory> _items = const [];
  List<WalkMemory> get items => _items;
  bool _ready = false;
  bool get ready => _ready;
  String? _error;
  String? get error => _error;
  bool _disposed = false;
  int _generation = 0;
  Future<void>? _recovery;
  String? _recoveryError;

  void clearError() {
    if (_disposed) return;
    _error = null;
    _recoveryError = null;
    notifyListeners();
  }

  void reportOpenFailure() {
    if (_disposed) return;
    _error = 'Could not open a memory. Please retry.';
    notifyListeners();
  }

  Future<void> _recover() async {
    try {
      await _recoverPhotos();
      _recoveryError = null;
    } catch (_) {
      _recoveryError =
          'Photo recovery needs attention. Open Memories to continue your draft.';
    }
  }

  Future<void> load({bool recover = false}) async {
    if (_disposed) return;
    final generation = ++_generation;
    bool current() => !_disposed && generation == _generation;
    if (recover) {
      _recovery ??= _recover().whenComplete(() => _recovery = null);
    }
    try {
      // Concurrent refreshes must wait for recovery too, but only the newest
      // request may publish a list or an error.
      await _recovery;
      if (!current()) return;
      final loaded = await store.list();
      if (!current()) return;
      _items = List.unmodifiable(loaded);
      _error = _recoveryError;
    } catch (_) {
      if (current()) _error = 'Could not load memories. Tap Memories to retry.';
    } finally {
      if (current()) {
        _ready = true;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
