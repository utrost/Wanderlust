import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanderlust/data/area_network.dart';
import 'package:wanderlust/maps/automatic_maps.dart';
import 'package:wanderlust/maps/map_download.dart';
import 'coverage_test.dart' show networkJson;
import 'offline_maps_screen_test.dart' show MemoryAreas;
import 'recording_test.dart' show fix;

String area(String id, List<double> bbox) {
  final data = jsonDecode(networkJson(version: id)) as Map<String, dynamic>;
  data['bbox'] = bbox;
  return jsonEncode(data);
}

void main() {
  test(
    'downloads 2 km once near exposed boundary, keeps selection and adds coverage',
    () async {
      final store = MemoryAreas();
      final maps = [
        AreaNetwork.parse(area('old', [8.799, 53.06, 8.82, 53.08])),
      ];
      var now = fix(20).timestamp;
      var calls = 0;
      final gate = Completer<String>();
      final controller = AutomaticMaps(
        store: store,
        networks: () => maps,
        clock: () => now,
        fetch: (request) {
          calls++;
          expect(
            (request.bbox[3] - request.bbox[1]) * 111320,
            closeTo(2000, 25),
          );
          return gate.future;
        },
        onSaved: () async {
          maps.add(AreaNetwork.parse(store.maps.values.single));
        },
      );
      try {
        store.selected = 'old';
        final pending = controller.consider(fix(20));
        await Future<void>.delayed(Duration.zero);
        await controller.consider(fix(20));
        expect(calls, 1);
        gate.complete(
          area('new', NearbyArea.around(53.07, 8.8002, sizeKm: 2).bbox),
        );
        await pending;
        expect(store.selected, 'old');
        expect(maps, hasLength(2));
        now = fix(100).timestamp;
        await controller.consider(fix(100));
        expect(calls, 1);
      } finally {
        controller.dispose();
      }
    },
  );
  test(
    'disabled, stale fixes, covered interior and internal seams never fetch',
    () async {
      var calls = 0;
      final controller = AutomaticMaps(
        store: MemoryAreas(),
        clock: () => fix(20).timestamp,
        networks: () => [
          AreaNetwork.parse(area('a', [8.78, 53.05, 8.80, 53.09])),
          AreaNetwork.parse(area('b', [8.799, 53.05, 8.83, 53.09])),
        ],
        fetch: (_) async {
          calls++;
          throw StateError('unexpected');
        },
        onSaved: () async {},
      );
      await controller.consider(fix(20));
      controller.setEnabled(false);
      await controller.consider(fix(20));
      expect(calls, 0);
      controller.dispose();
    },
  );
  test('failure backs off and disabling in flight prevents saving', () async {
    var now = fix(20).timestamp, calls = 0;
    final store = MemoryAreas();
    final gate = Completer<String>();
    final controller = AutomaticMaps(
      store: store,
      clock: () => now,
      networks: () => [
        AreaNetwork.parse(area('old', [8.799, 53.06, 8.82, 53.08])),
      ],
      fetch: (_) {
        calls++;
        if (calls == 1) throw StateError('offline');
        return gate.future;
      },
      onSaved: () async {},
    );
    await controller.consider(fix(20));
    await controller.consider(fix(21));
    expect(calls, 1);
    now = fix(321).timestamp;
    final pending = controller.consider(fix(321));
    await Future<void>.delayed(Duration.zero);
    controller.setEnabled(false);
    gate.complete(area('new', NearbyArea.around(53.07, 8.8, sizeKm: 2).bbox));
    await pending;
    expect(calls, 2);
    expect(store.maps, isEmpty);
    controller.dispose();
  });
  test('eight maps pauses without evicting any user map', () async {
    final store = MemoryAreas();
    for (var i = 0; i < 8; i++) {
      store.maps['$i'] = area('$i', [8.799, 53.06, 8.82, 53.08]);
    }
    var calls = 0;
    final controller = AutomaticMaps(
      store: store,
      clock: () => fix(20).timestamp,
      networks: () => [AreaNetwork.parse(store.maps.values.first)],
      fetch: (_) async {
        calls++;
        throw StateError('unexpected');
      },
      onSaved: () async {},
    );
    await controller.consider(fix(20));
    expect(calls, 0);
    expect(store.maps, hasLength(8));
    expect(controller.message, contains('eight'));
    controller.dispose();
  });
}
