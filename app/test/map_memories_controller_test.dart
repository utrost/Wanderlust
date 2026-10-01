import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wanderlust/application/map_memories_controller.dart';
import 'package:wanderlust/memories/memory.dart';
import 'package:wanderlust/memories/memory_repository.dart';

class ControlledMemories implements MemoryRepository {
  final requests = <Completer<List<WalkMemory>>>[];
  @override
  Future<List<WalkMemory>> list({String? walkUid}) {
    final result = Completer<List<WalkMemory>>();
    requests.add(result);
    return result.future;
  }

  @override
  Future<WalkMemory?> read(String id, bool draft) => throw UnimplementedError();
  @override
  Future<void> put(WalkMemory memory) => throw UnimplementedError();
  @override
  Future<void> delete(String id, {bool draftOnly = false}) =>
      throw UnimplementedError();
  @override
  Future<List<WalkMemory>> exportAll() => throw UnimplementedError();
}

void main() {
  for (final failOld in [false, true]) {
    test(
      'late ${failOld ? 'failure' : 'list'} cannot replace newer pins',
      () async {
        final store = ControlledMemories();
        final controller = MapMemoriesController(store);
        addTearDown(controller.dispose);
        final old = controller.load();
        await Future<void>.delayed(Duration.zero);
        final latest = controller.load();
        await Future<void>.delayed(Duration.zero);
        final pin = WalkMemory.create().copyWith(note: 'new pin', draft: false);
        final list = [pin];
        store.requests[1].complete(list);
        await latest;
        list.clear();
        if (failOld) {
          store.requests[0].completeError(StateError('late failure'));
        } else {
          store.requests[0].complete([]);
        }
        await old;
        expect(controller.items.single.id, pin.id);
        expect(controller.error, isNull);
        expect(() => controller.items.clear(), throwsUnsupportedError);
      },
    );
  }
  test(
    'overlapping refresh waits for single photo recovery and retry clears read error',
    () async {
      final store = ControlledMemories();
      final recovery = Completer<void>();
      var calls = 0;
      final controller = MapMemoriesController(
        store,
        recoverPhotos: () {
          calls++;
          return recovery.future;
        },
      );
      addTearDown(controller.dispose);
      final first = controller.load(recover: true);
      final second = controller.load(recover: true);
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      expect(store.requests, isEmpty);
      recovery.complete();
      await Future<void>.delayed(Duration.zero);
      expect(store.requests, hasLength(1));
      store.requests.single.completeError(StateError('read failure'));
      await Future.wait([first, second]);
      expect(controller.error, isNotNull);
      final retry = controller.load();
      await Future<void>.delayed(Duration.zero);
      store.requests.last.complete([]);
      await retry;
      expect(controller.error, isNull);
    },
  );
  test(
    'failed recovery can be retried without retaining its warning',
    () async {
      final store = ControlledMemories();
      var calls = 0;
      final controller = MapMemoriesController(
        store,
        recoverPhotos: () async {
          if (++calls == 1) throw StateError('Photo unavailable');
        },
      );
      addTearDown(controller.dispose);
      final first = controller.load(recover: true);
      await Future<void>.delayed(Duration.zero);
      store.requests.single.complete([]);
      await first;
      expect(controller.error, contains('Photo recovery'));
      final retry = controller.load(recover: true);
      await Future<void>.delayed(Duration.zero);
      store.requests.last.complete([]);
      await retry;
      expect(calls, 2);
      expect(controller.error, isNull);
    },
  );
  test('disposing during a read prevents changes and notifications', () async {
    final store = ControlledMemories();
    final controller = MapMemoriesController(store);
    var notifications = 0;
    controller.addListener(() => notifications++);
    final pending = controller.load();
    await Future<void>.delayed(Duration.zero);
    controller.dispose();
    store.requests.single.complete([WalkMemory.create()]);
    await pending;
    expect(notifications, 0);
    expect(controller.items, isEmpty);
    expect(controller.ready, isFalse);
  });
}
