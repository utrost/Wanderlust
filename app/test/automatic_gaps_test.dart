import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wanderlust/coverage/coverage_controller.dart';
import 'package:wanderlust/geo/geo_core_ffi.dart';
import 'package:wanderlust/recording/walk_store.dart';
import 'package:wanderlust/review/gap_routes.dart';
import 'package:wanderlust/settings/walk_preferences.dart';
import 'package:wanderlust/transfer/walk_codec.dart';
import 'gap_routes_test.dart' as fixture;
import 'coverage_test.dart' show networkJson;

void main() {
  sqfliteFfiInit();
  test(
    'automatic default migrates old settings, manual preference round-trips',
    () {
      expect(const WalkPreferences().autoFillGaps, isTrue);
      expect(
        WalkPreferences.fromJson({'fillSmallGaps': true}).autoFillGaps,
        isTrue,
      );
      final manual = const WalkPreferences().copyWith(autoFillGaps: false);
      expect(WalkPreferences.fromJson(manual.toJson()).autoFillGaps, isFalse);
    },
  );
  test('shortest route is automatic and explicit alternate wins', () async {
    final gpx = WalkCodec.exportGpx(fixture.walk());
    final map = fixture.routes(alternative: true);
    expect((await automaticGapSections(map, [gpx], [[]])).single, {1, 2});
    expect(
      (await automaticGapSections(
        map,
        [gpx],
        [
          [3, 4],
        ],
      )).single,
      isEmpty,
    );
  });
  test(
    'live and saved coverage fill by default, switching to manual reverses estimates',
    () async {
      final dir = await Directory.systemTemp.createTemp('auto-gaps-');
      final store = SqliteWalkStore(
        factory: databaseFactoryFfi,
        databasePath: '${dir.path}/db',
      );
      final data = jsonDecode(networkJson()) as Map<String, dynamic>;
      data['features'] = jsonDecode(fixture.routes())['features'];
      for (final f in data['features'] as List) {
        f['type'] = 'Feature';
        f['geometry']['type'] = 'LineString';
      }
      data['bbox'] = [-.01, -.01, .01, .01];
      final controller = CoverageController(
        store: store,
        loadNetwork: () async => jsonEncode(data),
        loadWalk: store.loadWalk,
        liveInterval: const Duration(milliseconds: 1),
        match: (_, walks) async => [
          for (final _ in walks)
            const MatchResult(walked: [], gapsFilled: 0, gapsRejected: 0),
        ],
      );
      try {
        final w = fixture.walk();
        final id = await store.begin(w.startedAt);
        for (var i = 0; i < w.points.length; i++) {
          await store.append(id, i, w.points[i]);
        }
        controller.updateLive(await store.loadWalk(id));
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await controller.settled;
        expect(controller.displayCounts.keys, containsAll([1, 2]));
        await store.finish(id, w.points.last.timestamp, 'completed');
        var saved = await store.listSummaries();
        await controller.synchronize(saved);
        expect(controller.counts, {1: 1, 2: 1});
        await controller.synchronize(saved);
        expect(controller.counts, {1: 1, 2: 1});
        await controller.setFillSmallGaps(false, saved, autoFillGaps: false);
        expect(controller.counts, isEmpty);
        await store.saveConfirmedSections(saved.single.uid, [1]);
        saved = await store.listSummaries();
        await controller.synchronize(saved);
        expect(controller.counts, {1: 1});
        await controller.setFillSmallGaps(false, saved, autoFillGaps: true);
        expect(controller.counts, {1: 1, 2: 1});
      } finally {
        controller.dispose();
        await controller.settled;
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
