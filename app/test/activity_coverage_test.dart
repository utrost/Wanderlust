import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wanderlust/coverage/coverage_controller.dart';
import 'package:wanderlust/geo/geo_core_ffi.dart';
import 'package:wanderlust/recording/walk_recorder.dart';
import 'package:wanderlust/recording/activity_type.dart';
import 'package:wanderlust/recording/walk_store.dart';
import 'package:wanderlust/transfer/walk_codec.dart';
import 'recording_test.dart' show FakeLocation, fix;
import 'coverage_test.dart' show networkJson;

void main() {
  sqfliteFfiInit();
  test(
    'changing saved mode replaces heatmap membership and is idempotent',
    () async {
      final dir = await Directory.systemTemp.createTemp('activity-coverage-');
      final store = SqliteWalkStore(
        factory: databaseFactoryFfi,
        databasePath: '${dir.path}/db',
      );
      final c = CoverageController(
        store: store,
        loadWalk: store.loadWalk,
        loadNetwork: () async => networkJson(),
        match: (_, traces) async => [
          for (final gpx in traces)
            MatchResult(
              walked: WalkCodec.importGpx(gpx).activity == WalkActivity.cycle
                  ? [2]
                  : [1],
              gapsFilled: 0,
              gapsRejected: 0,
            ),
        ],
      );
      try {
        final id = await store.begin(fix(0).timestamp);
        await store.append(id, 0, fix(0));
        await store.append(id, 1, fix(5));
        await store.finish(id, fix(5).timestamp, 'completed');
        await c.synchronize(await store.listSummaries());
        expect(c.counts, {1: 1});
        await store.setActivity((await store.walkUid(id))!, WalkActivity.cycle);
        await c.synchronize(await store.listSummaries());
        expect(c.counts, {2: 1});
        await c.synchronize(await store.listSummaries());
        expect(c.counts, {2: 1});
        await store.setActivity((await store.walkUid(id))!, WalkActivity.walk);
        await c.synchronize(await store.listSummaries());
        expect(c.counts, {1: 1});
      } finally {
        c.dispose();
        await c.settled;
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'recorder freezes mode at start for live previews and durable journal',
    () async {
      final dir = await Directory.systemTemp.createTemp('activity-recording-');
      final store = SqliteWalkStore(
        factory: databaseFactoryFfi,
        databasePath: '${dir.path}/db',
      );
      final location = FakeLocation();
      var mode = WalkActivity.cycle;
      final r = WalkRecorder(
        store: store,
        location: location,
        activityType: () => mode,
      );
      try {
        expect(await r.start(), isTrue);
        mode = WalkActivity.walk;
        location.stream.add(fix(0));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(r.recordingSnapshot!.activity, WalkActivity.cycle);
        expect(WalkCodec.importGpx(r.toGpx()).activity, WalkActivity.cycle);
        await r.stop();
        expect((await store.listSaved()).single.activity, WalkActivity.cycle);
      } finally {
        r.dispose();
        await location.stream.close();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await dir.delete(recursive: true);
      }
    },
  );
}
