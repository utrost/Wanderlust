import 'package:flutter/foundation.dart';

import '../settings/preferences_store.dart';
import '../settings/walk_preferences.dart';

/// Serializes reads/writes so a late startup read or slower earlier save cannot
/// overwrite a newer choice. Failed writes leave the last persisted value shown.
class PreferencesController extends ChangeNotifier {
  PreferencesController({required this.store, required this.onApplied});
  final PreferencesStore store;
  final Future<void> Function(WalkPreferences) onApplied;
  WalkPreferences _value = const WalkPreferences();
  WalkPreferences get value => _value;
  Future<void> _pending = Future.value();
  Future<void> get settled => _pending;
  bool _disposed = false;

  Future<void> _enqueue(Future<void> Function() action) {
    if (_disposed) return Future.error(StateError('Preferences are closed'));
    final operation = _pending.then((_) => action());
    // Observe errors for the queue; the caller still receives the failed future.
    _pending = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation;
  }

  Future<void> load() => _enqueue(() async {
    try {
      await _apply(await store.readPreferences());
    } catch (_) {
      // The last value (calm defaults at startup) remains usable offline.
    }
  });

  Future<void> save(WalkPreferences value) => _enqueue(() async {
    await store.savePreferences(value);
    await _apply(value);
  });

  Future<void> _apply(WalkPreferences value) async {
    if (_disposed) return;
    _value = value;
    notifyListeners();
    await onApplied(value);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
