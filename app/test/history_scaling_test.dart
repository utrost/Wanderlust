import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wanderlust/coverage/coverage_controller.dart';
import 'package:wanderlust/coverage/coverage_store.dart';
import 'package:wanderlust/geo/geo_core_ffi.dart';
import 'package:wanderlust/maps/active_maps.dart';
import 'package:wanderlust/recording/walk_store.dart';
import 'active_maps_test.dart' show nearby;
import 'coverage_test.dart' show networkJson;
import 'recording_test.dart' show fix;

class MeasuredStore extends SqliteWalkStore {
  MeasuredStore(String path)
    : super(factory: databaseFactoryFfi, databasePath: path);
  int singleReads = 0, batches = 0, candidates = 0, traceLoads = 0;
  Completer<void>? cellGate;
  void reset() {
    singleReads = batches = candidates = traceLoads = 0;
  }

  @override
  Future<StoredMatch?> readEvidence(int walk, String network) {
    singleReads++;
    return super.readEvidence(walk, network);
  }

  @override
  Future<Map<int, (StoredMatch, String?)>> readEvidenceBatch(
    String network, {
    List<int>? walks,
  }) {
    batches++;
    candidates += walks?.length ?? 0;
    return super.readEvidenceBatch(network, walks: walks);
  }

  @override
  Future<SavedWalk> loadWalk(int id) {
    traceLoads++;
    return super.loadWalk(id);
  }

  @override
  Future<String?> readCell(String cell) async {
    await cellGate?.future;
    return super.readCell(cell);
  }
}

// Cache/database workload on a dense 10 x 10 km grid. Matching is stubbed in
// this test; native correctness is covered separately by fixtures and replay.
String denseMap() {
  final map = jsonDecode(networkJson()) as Map<String, dynamic>;
  map['bbox'] = [8.7, 53.0, 8.85, 53.09];
  var id = 0;
  map['features'] = [
    for (var x = 0; x < 100; x++)
      for (var y = 0; y < 100; y++)
        for (final delta in [
          [.0015, 0.0],
          [0.0, .0009],
        ])
          {
            'type': 'Feature',
            'id': ++id,
            'properties': {'highway': 'residential'},
            'geometry': {
              'type': 'LineString',
              'coordinates': [
                [8.7 + x * .0015, 53.0 + y * .0009],
                [8.7 + x * .0015 + delta[0], 53.0 + y * .0009 + delta[1]],
              ],
            },
          },
  ];
  return jsonEncode(map);
}

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late MeasuredStore store;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('history-scaling-');
    store = MeasuredStore('${dir.path}/db');
  });
  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });

  for (final size in [100, 500]) {
    test(
      '$size walks: cached opening avoids traces and individual evidence queries; distant walks are skipped',
      () async {
        await store.mergeWalks([
          for (var i = 0; i < size; i++)
            SavedWalk(
              i,
              DateTime.utc(2026, 1, 1).add(Duration(days: i)),
              DateTime.utc(2026, 1, 1).add(Duration(days: i, hours: 1)),
              'completed',
              [fix(i * 2), fix(i * 2 + 1)],
              uid: i.toRadixString(16).padLeft(32, '0'),
            ),
        ]);
        final history = await store.listSummaries();
        // Half the library belongs to a distant city. No trace reads should be
        // necessary to reject those summaries before cache lookup/matching.
        for (var i = 0; i < size; i++) {
          await store.writeWalkBounds(
            history[i].id,
            history[i].fingerprint!,
            i.isEven ? [8.8, 53.07, 8.81, 53.08] : [13.4, 52.5, 13.41, 52.51],
          );
        }
        final source = size == 500 ? denseMap() : networkJson();
        var matched = 0, largestBatch = 0;
        CoverageController create() => CoverageController(
          store: store,
          loadNetwork: () async => source,
          loadWalk: store.loadWalk,
          match: (_, traces) async {
            matched += traces.length;
            if (traces.length > largestBatch) largestBatch = traces.length;
            return [
              for (final _ in traces)
                const MatchResult(
                  walked: [1],
                  unmatched: [],
                  gapsFilled: 0,
                  gapsRejected: 0,
                ),
            ];
          },
        );
        var controller = create();
        final watch = Stopwatch()..start();
        await controller.synchronize(history);
        final cold = watch.elapsedMilliseconds;
        expect(controller.error, isNull);
        expect(matched, size ~/ 2);
        expect(largestBatch, lessThanOrEqualTo(16));
        controller.dispose();
        await controller.settled;
        controller = create();
        store.reset();
        watch.reset();
        await controller.initialize();
        expect(controller.displayCounts, {
          1: size ~/ 2,
        }, reason: 'saved coverage appears before historical synchronization');
        final cachedOpen = watch.elapsedMilliseconds;
        store.reset();
        watch.reset();
        await Future.wait([
          for (var i = 0; i < 10; i++) controller.synchronize(history),
        ]);
        expect(controller.error, isNull);
        expect(store.singleReads, 0);
        expect(store.traceLoads, 0);
        expect(
          store.batches,
          1,
          reason: 'ten queued refresh requests coalesce',
        );
        expect(store.candidates, size ~/ 2);
        expect(
          matched,
          size ~/ 2,
          reason: 'unchanged history must not rematch',
        );
        // ignore: avoid_print
        print(
          'HISTORY $size: cold ${cold}ms, cached open ${cachedOpen}ms, warm sync ${watch.elapsedMilliseconds}ms; ${store.batches} evidence batch, ${store.traceLoads} trace reads',
        );
        controller.dispose();
        await controller.settled;
      },
    );
  }

  test(
    'map shell is ready while cell loading is blocked, then streets arrive',
    () async {
      await store.saveArea(nearby('local', const Offset(8.8, 53.1)));
      while (await store.indexNext(null)) {}
      store.cellGate = Completer<void>();
      final active = ActiveMaps(store);
      try {
        await active.initialize().timeout(const Duration(seconds: 2));
        expect(active.anchor, isNotNull);
        expect(active.networks, isEmpty);
        expect(active.loading, true);
        store.cellGate!.complete();
        await active.settled;
        expect(active.networks, isNotEmpty);
      } finally {
        if (!store.cellGate!.isCompleted) store.cellGate!.complete();
        await active.settled;
        active.dispose();
      }
    },
  );
}
