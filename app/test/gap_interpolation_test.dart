import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wanderlust/coverage/coverage_controller.dart';
import 'package:wanderlust/recording/walk_store.dart';
import 'package:wanderlust/transfer/walk_codec.dart';

String gapNetwork() => jsonEncode({
  'type': 'FeatureCollection',
  'bbox': [-0.001, -0.001, 0.002, 0.002],
  'wanderlust_network': {
    'version': 1,
    'area_id': 'gap',
    'name': 'Gap fixture',
    'network_version': 'gap-v1',
    'attribution': 'Synthetic',
  },
  'features': [
    for (final edge in [(1, 0, 30), (2, 30, 60), (3, 60, 100)])
      {
        'type': 'Feature',
        'id': edge.$1,
        'properties': {'from_node': edge.$1, 'to_node': edge.$1 + 1},
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            [edge.$2 / 111195, 0],
            [edge.$3 / 111195, 0],
          ],
        },
      },
  ],
});
String gapGpx() {
  final start = DateTime.utc(2026, 9, 29, 9);
  return '<gpx><trk><trkseg>${[
    for (final sample in [(5, 0), (15, 5), (25, 10), (45, 20), (65, 30), (75, 35), (85, 40)]) '<trkpt lon="${sample.$1 / 111195}" lat="0"><time>${start.add(Duration(seconds: sample.$2)).toIso8601String()}</time></trkpt>',
  ].join()}</trkseg></trk></gpx>';
}

void main() {
  sqfliteFfiInit();
  test(
    'native interpolation is reversible for saved and live coverage without changing raw walks',
    () async {
      final dir = await Directory.systemTemp.createTemp('wanderlust-gap-');
      final store = SqliteWalkStore(
        factory: databaseFactoryFfi,
        databasePath: '${dir.path}/walks.db',
      );
      final controller = CoverageController(
        store: store,
        loadNetwork: () async => gapNetwork(),
        liveInterval: Duration.zero,
      );
      Future<void> drain() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await controller.settled;
      }

      try {
        await store.mergeWalks([WalkCodec.importGpx(gapGpx())]);
        final walks = await store.listSaved();
        final raw = WalkCodec.exportBackup(walks);
        await controller.synchronize(walks);
        expect(controller.error, isNull);
        expect(controller.counts, {1: 1, 3: 1});
        await controller.setFillSmallGaps(true, walks);
        expect(controller.error, isNull);
        expect(controller.counts, {1: 1, 2: 1, 3: 1});
        await controller.synchronize(walks);
        expect(controller.counts, {1: 1, 2: 1, 3: 1});
        await controller.setFillSmallGaps(false, walks);
        expect(controller.counts, {1: 1, 3: 1});
        expect(WalkCodec.exportBackup(await store.listSaved()), raw);
        final saved = walks.single;
        controller.updateLive(
          SavedWalk(99, saved.startedAt, null, 'recording', saved.points),
        );
        await drain();
        expect(controller.displayCounts, {1: 2, 3: 2});
        await controller.setFillSmallGaps(true, walks);
        await drain();
        expect(controller.displayCounts, {1: 2, 2: 2, 3: 2});
        await controller.setFillSmallGaps(false, walks);
        await drain();
        expect(controller.displayCounts, {1: 2, 3: 2});
        expect(WalkCodec.exportBackup(await store.listSaved()), raw);
      } finally {
        controller.dispose();
        await controller.settled;
        await store.close();
        await dir.delete(recursive: true);
      }
    },
    skip: Platform.environment['WANDERLUST_NATIVE_TESTS'] != '1'
        ? 'Requires host Rust library.'
        : false,
  );
}
