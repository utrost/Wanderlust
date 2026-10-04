import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wanderlust/recording/walk_store.dart';
import 'package:wanderlust/transfer/walk_codec.dart';
import 'recording_test.dart' show fix;
import 'coverage_test.dart' show networkJson;
import 'package:wanderlust/data/area_network.dart';

const segmentedGpx =
    '''<g:gpx xmlns:g="http://www.topografix.com/GPX/1/1" xmlns:wl="https://wanderlust.local/gpx/1">
<g:trk><g:trkseg><g:trkpt lat="53.1" lon="8.8"><g:ele>12.5</g:ele><g:time>2026-09-26T12:00:00.123456+02:00</g:time><g:extensions><wl:accuracy>4.5</wl:accuracy></g:extensions></g:trkpt></g:trkseg>
<g:trkseg><g:trkpt lat="53.1001" lon="8.8001"/></g:trkseg></g:trk>
<g:trk><g:trkseg><g:trkpt lat="53.1002" lon="8.8002"><g:time>2026-09-26T10:00:10Z</g:time></g:trkpt></g:trkseg></g:trk></g:gpx>''';

String envelope(List<Map<String, Object?>> walks) {
  final payload = jsonEncode({'walks': walks});
  return jsonEncode({
    'format': 'wanderlust-backup',
    'version': 1,
    'sha256': sha256.convert(utf8.encode(payload)).toString(),
    'payload': payload,
  });
}

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late SqliteWalkStore store;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('wanderlust-transfer-');
    store = SqliteWalkStore(
      factory: databaseFactoryFfi,
      databasePath: '${dir.path}/walks.db',
    );
  });
  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });

  test(
    'restore into a populated library remaps IDs and retains coverage',
    () async {
      final id = await store.begin(fix(0).timestamp);
      await store.append(id, 0, fix(1));
      await store.finish(id, fix(2).timestamp, 'completed');
      final network = AreaNetwork.parse(networkJson());
      await store.registerNetwork(network);
      await store.replaceWalkMatch(id, network.version, 'existing', {1});
      final backup = WalkCodec.exportBackup([
        WalkCodec.importGpx(segmentedGpx),
      ]);
      expect(await store.mergeWalks(WalkCodec.importBackup(backup)), 1);
      expect(await store.listSaved(), hasLength(2));
      expect(await store.readCounts(network.version), {1: 1});
      expect((await store.listSaved()).map((w) => w.id).toSet(), hasLength(2));
    },
  );

  test('oversize documents fail before parsing', () {
    final bytes = List<int>.filled(WalkCodec.maxBytes + 1, 32);
    expect(() => WalkCodec.decodeBytes(bytes), throwsFormatException);
    expect(
      () => WalkCodec.importGpx(' ' * (WalkCodec.maxBytes + 1)),
      throwsFormatException,
    );
  });

  test(
    'GPX round-trip preserves namespace, segments, missing times and precision',
    () {
      final walk = WalkCodec.importGpx(segmentedGpx);
      expect(walk.points.length, 3);
      expect(walk.segmentStarts, [1, 2]);
      expect(walk.untimed, [1]);
      expect(
        walk.points.first.timestamp,
        DateTime.parse('2026-09-26T10:00:00.123456Z'),
      );
      expect(walk.points.first.accuracy, 4.5);
      expect(walk.points.first.altitude, 12.5);
      final gpx = WalkCodec.exportGpx(walk);
      expect('<trkseg>'.allMatches(gpx).length, 3);
      expect('<time>'.allMatches(gpx).length, 2);
      final copy = WalkCodec.importGpx(gpx);
      expect(copy.traceKey, walk.traceKey);
      expect(copy.points.map((p) => p.hasAccuracy), [true, false, false]);
    },
  );

  test('GPX retains explicit zero and positive device accuracy', () {
    final zero = WalkCodec.importGpx(segmentedGpx.replaceAll('4.5', '0.0'));
    final copy = WalkCodec.importGpx(WalkCodec.exportGpx(zero));
    expect(copy.points.first.hasAccuracy, isTrue);
    expect(copy.points.first.accuracy, 0);
    final point = fix(0);
    expect(point.accuracy, greaterThan(0));
    final recorded = SavedWalk(
      1,
      point.timestamp,
      point.timestamp,
      'completed',
      [point],
    );
    expect(
      WalkCodec.importGpx(WalkCodec.exportGpx(recorded)).points.first.accuracy,
      point.accuracy,
    );
  });

  test('invalid GPX is rejected without silently dropping bad fixes', () {
    for (final gpx in [
      '<gpx>',
      '<html/>',
      '<gpx><rte><rtept lat="0" lon="0"/></rte></gpx>',
      '<gpx><trk><trkseg/></trk></gpx>',
      '<!DOCTYPE gpx><gpx/>',
      for (final lat in ['NaN', '91', 'Infinity', 'bad'])
        '<gpx><trk><trkseg><trkpt lat="$lat" lon="0"/></trkseg></trk></gpx>',
      for (final time in [
        '2026-02-30T12:00:00Z',
        '2026-09-26T12:00:00',
        '2026-09-26T24:00:00Z',
      ])
        '<gpx><trk><trkseg><trkpt lat="0" lon="0"><time>$time</time></trkpt></trkseg></trk></gpx>',
    ]) {
      expect(() => WalkCodec.importGpx(gpx), throwsA(anything), reason: gpx);
    }
    expect(() => WalkCodec.decodeBytes([0xff]), throwsFormatException);
  });

  test(
    'time gaps and reversals are retained for conservative native matching',
    () {
      final gpx =
          '<gpx><trk><trkseg>${[20, 10, 60].map((s) => '<trkpt lat="53" lon="8"><time>2026-09-26T10:${s == 60 ? '01:00' : '00:$s'}Z</time></trkpt>').join()}</trkseg></trk></gpx>';
      final walk = WalkCodec.importGpx(gpx);
      expect(walk.points.map((p) => p.timestamp.minute), [0, 0, 1]);
      expect(
        walk.points[0].timestamp.isAfter(walk.points[1].timestamp),
        isTrue,
      );
    },
  );

  test(
    'reimport skips renamed/reformatted and untimed tracks, even after reopen',
    () async {
      final walk = WalkCodec.importGpx(segmentedGpx);
      expect(await store.mergeWalks([walk], deduplicateTrace: true), 1);
      await store.close();
      store = SqliteWalkStore(
        factory: databaseFactoryFfi,
        databasePath: '${dir.path}/walks.db',
      );
      final saved = (await store.listSaved()).single;
      expect(saved.traceKey, walk.traceKey);
      expect(saved.toBackup(), walk.toBackup());
      expect(
        await store.mergeWalks([
          WalkCodec.importGpx(WalkCodec.exportGpx(saved)),
        ], deduplicateTrace: true),
        0,
      );
      const untimed =
          '<gpx><trk><trkseg><trkpt lat="0" lon="0"/></trkseg></trk></gpx>';
      final a = WalkCodec.importGpx(untimed, importedAt: DateTime.utc(2026));
      final b = WalkCodec.importGpx(untimed, importedAt: DateTime.utc(2027));
      expect(await store.mergeWalks([a], deduplicateTrace: true), 1);
      expect(await store.mergeWalks([b], deduplicateTrace: true), 0);
    },
  );

  test('exported recording reimport does not double-count it', () async {
    final id = await store.begin(fix(0).timestamp);
    await store.append(id, 0, fix(1));
    await store.finish(id, fix(2).timestamp, 'completed');
    final gpx = WalkCodec.exportGpx((await store.listSaved()).single);
    expect(
      await store.mergeWalks([
        WalkCodec.importGpx(gpx),
      ], deduplicateTrace: true),
      0,
    );
    expect(await store.listSaved(), hasLength(1));
  });

  test(
    'backup restores all measurements, empty/interrupted walks, and stable identities',
    () async {
      await store.mergeWalks([WalkCodec.importGpx(segmentedGpx)]);
      for (final status in ['completed', 'interrupted']) {
        final id = await store.begin(fix(0).timestamp);
        if (status == 'completed') await store.append(id, 0, fix(1));
        await store.finish(id, fix(3).timestamp, status);
      }
      final before = await store.listSaved();
      final backup = WalkCodec.exportBackup(before);
      final restored = WalkCodec.importBackup(backup);
      expect(
        restored.map((w) => w.toBackup()),
        before.map((w) => w.toBackup()),
      );
      final target = SqliteWalkStore(
        factory: databaseFactoryFfi,
        databasePath: '${dir.path}/target.db',
      );
      try {
        expect(await target.mergeWalks(restored), 3);
        expect(await target.mergeWalks(restored), 0);
        final actual = {
          for (final w in await target.listSaved()) w.uid: w.toBackup(),
        };
        expect(actual, {for (final w in before) w.uid: w.toBackup()});
      } finally {
        await target.close();
      }
    },
  );

  test(
    'distinct recording identities with identical traces survive a backup',
    () async {
      for (var i = 0; i < 2; i++) {
        final id = await store.begin(fix(0).timestamp);
        await store.append(id, 0, fix(1));
        await store.finish(id, fix(2).timestamp, 'completed');
      }
      final restored = WalkCodec.importBackup(
        WalkCodec.exportBackup(await store.listSaved()),
      );
      expect(restored.map((w) => w.uid).toSet(), hasLength(2));
      expect(restored.map((w) => w.traceKey).toSet(), hasLength(1));
      expect(await store.mergeWalks(restored), 0);
    },
  );

  test(
    'conflicting identity rolls back the entire restore and retains existing data',
    () async {
      final first = WalkCodec.importGpx(segmentedGpx);
      await store.mergeWalks([first]);
      final other = SavedWalk(0, first.startedAt, first.endedAt, first.status, [
        fix(1),
      ], uid: 'a' * 32);
      final conflict = SavedWalk(
        0,
        first.startedAt,
        first.endedAt,
        'interrupted',
        first.points,
        uid: first.uid,
      );
      await expectLater(
        store.mergeWalks([other, conflict]),
        throwsFormatException,
      );
      expect((await store.listSaved()).map((w) => w.toBackup()), [
        first.toBackup(),
      ]);
    },
  );

  test(
    'corrupted, future-version and semantically invalid backups are rejected',
    () {
      final row = WalkCodec.importGpx(segmentedGpx).toBackup();
      final good = envelope([row]);
      expect(
        () => WalkCodec.importBackup(
          good.replaceFirst('completed', 'interrupted'),
        ),
        throwsFormatException,
      );
      expect(
        () => WalkCodec.importBackup(
          good.replaceFirst('"version":1', '"version":2'),
        ),
        throwsFormatException,
      );
      for (final bad in [
        {...row, 'uid': 'bad'},
        {...row, 'status': 'recording'},
        {
          ...row,
          'segmentStarts': [99],
        },
        {
          ...row,
          'untimed': [0],
        },
        {...row, 'endedAt': null},
        {
          ...row,
          'points': [
            {'latitude': 1},
          ],
        },
      ]) {
        expect(
          () => WalkCodec.importBackup(envelope([bad])),
          throwsFormatException,
        );
      }
      expect(
        () => WalkCodec.importBackup(envelope([row, row])),
        throwsFormatException,
      );
    },
  );

  test(
    'library reads and failed imports never interrupt an active recording',
    () async {
      await store.begin(fix(0).timestamp);
      expect((await store.listSaved()).single.status, 'recording');
      await expectLater(
        store.mergeWalks([WalkCodec.importGpx(segmentedGpx)]),
        throwsStateError,
      );
      expect(() => WalkCodec.exportBackup([]), returnsNormally);
      expect(
        () async => WalkCodec.exportBackup(await store.listSaved()),
        throwsStateError,
      );
      expect((await store.listSaved()).single.status, 'recording');
    },
  );
}
