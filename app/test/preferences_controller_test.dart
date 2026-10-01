import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wanderlust/application/preferences_controller.dart';
import 'package:wanderlust/settings/preferences_store.dart';
import 'package:wanderlust/settings/walk_preferences.dart';

class ControlledPreferences implements PreferencesStore {
  final read = Completer<WalkPreferences>();
  final writes = <(WalkPreferences, Completer<void>)>[];
  @override
  Future<WalkPreferences> readPreferences() => read.future;
  @override
  Future<void> savePreferences(WalkPreferences value) {
    final completion = Completer<void>();
    writes.add((value, completion));
    return completion.future;
  }
}

void main() {
  test('startup read and rapid saves stay ordered in storage and UI', () async {
    final store = ControlledPreferences();
    final applied = <int>[];
    final controller = PreferencesController(
      store: store,
      onApplied: (value) async {
        applied.add(value.mapSizeKm);
      },
    );
    addTearDown(controller.dispose);
    final load = controller.load();
    final first = controller.save(const WalkPreferences(mapSizeKm: 8));
    final second = controller.save(const WalkPreferences(mapSizeKm: 12));
    store.read.complete(const WalkPreferences(mapSizeKm: 6));
    await load;
    await Future<void>.delayed(Duration.zero);
    expect(store.writes, hasLength(1));
    expect(controller.value.mapSizeKm, 6);
    store.writes[0].$2.complete();
    await first;
    await Future<void>.delayed(Duration.zero);
    expect(store.writes.map((w) => w.$1.mapSizeKm), [8, 12]);
    store.writes[1].$2.complete();
    await second;
    expect(controller.value.mapSizeKm, 12);
    expect(applied, [6, 8, 12]);
  });

  test(
    'failed save preserves current value and does not poison the queue',
    () async {
      final store = ControlledPreferences();
      final applied = <int>[];
      final controller = PreferencesController(
        store: store,
        onApplied: (value) async {
          applied.add(value.mapSizeKm);
        },
      );
      addTearDown(controller.dispose);
      final failed = controller.save(const WalkPreferences(mapSizeKm: 8));
      final failure = expectLater(failed, throwsStateError);
      final next = controller.save(const WalkPreferences(mapSizeKm: 12));
      await Future<void>.delayed(Duration.zero);
      store.writes[0].$2.completeError(StateError('Disk full'));
      await failure;
      expect(controller.value.mapSizeKm, 4);
      await Future<void>.delayed(Duration.zero);
      store.writes[1].$2.complete();
      await next;
      expect(applied, [12]);
    },
  );

  test(
    'disposal settles accepted writes without notifying disposed owners',
    () async {
      final store = ControlledPreferences();
      var applied = 0;
      final controller = PreferencesController(
        store: store,
        onApplied: (_) async {
          applied++;
        },
      );
      final saved = controller.save(const WalkPreferences(mapSizeKm: 8));
      await Future<void>.delayed(Duration.zero);
      controller.dispose();
      var settled = false;
      final drain = controller.settled.then((_) => settled = true);
      await Future<void>.delayed(Duration.zero);
      expect(settled, isFalse);
      store.writes.single.$2.complete();
      await saved;
      await drain;
      expect(applied, 0);
      await expectLater(
        controller.save(const WalkPreferences()),
        throwsStateError,
      );
    },
  );
}
