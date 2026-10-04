import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanderlust/geo/coverage_resolution.dart';
import 'package:wanderlust/geo/geo_core_ffi.dart';

String network({bool parallel = false, bool missing = false}) => jsonEncode({
  'features': [
    for (final edge in <(int, double, double, double)>[
      (1, 0, 100, 0),
      if (parallel) (2, 0, 100, 18),
      if (missing) (3, 45, 55, 0),
    ])
      {
        'id': edge.$1,
        'geometry': {
          'coordinates': [
            [edge.$2 / 111320, edge.$4 / 111320],
            [edge.$3 / 111320, edge.$4 / 111320],
          ],
        },
      },
  ],
});
String trace(List<(double, double)> points) =>
    '<gpx><trk><trkseg>${points.asMap().entries.map((e) => '<trkpt lon="${e.value.$1 / 111320}" lat="${e.value.$2 / 111320}"><time>2026-10-04T10:00:${(e.key * 5).toString().padLeft(2, '0')}Z</time></trkpt>').join()}</trkseg></trk></gpx>';
void main() {
  const result = MatchResult(
    walked: [1],
    unmatched: [1, 2],
    gapsFilled: 0,
    gapsRejected: 0,
  );
  test(
    'final painted route absorbs nearby GPS drift without changing credit',
    () async {
      final r = (await resolveCoverageDisplay(
        network(),
        [
          trace([(10, 18), (20, 20), (30, 18)]),
        ],
        [result],
      )).single;
      expect(r.unmatched, isEmpty);
      expect(r.walked, [1]);
    },
  );
  test('off-network and closer parallel street remain visible', () async {
    final raw = trace([(10, 18), (20, 20), (30, 18)]);
    expect(
      (await resolveCoverageDisplay(
        network(parallel: true),
        [raw],
        [result],
      )).single.unmatched,
      [1, 2],
    );
    expect(
      (await resolveCoverageDisplay(
        network(),
        [
          trace([(10, 40), (20, 40), (30, 40)]),
        ],
        [result],
      )).single.unmatched,
      [1, 2],
    );
  });
  test(
    'explicit confirmation participates in final fallback resolution',
    () async {
      const unmatched = MatchResult(
        walked: [],
        unmatched: [1, 2],
        gapsFilled: 0,
        gapsRejected: 0,
      );
      final r = (await resolveCoverageDisplay(
        network(),
        [
          trace([(10, 18), (20, 20), (30, 18)]),
        ],
        [unmatched],
        confirmed: [
          [1],
        ],
      )).single;
      expect(r.unmatched, isEmpty);
      expect(r.walked, isEmpty);
    },
  );
  test(
    'a short unpainted section between painted neighbours stays visible',
    () async {
      final source = jsonEncode({
        'features': [
          for (final e in [(1, 0, 45), (2, 45, 55), (3, 55, 100)])
            {
              'id': e.$1,
              'geometry': {
                'coordinates': [
                  [e.$2 / 111320, 0],
                  [e.$3 / 111320, 0],
                ],
              },
            },
        ],
      });
      const r = MatchResult(
        walked: [1, 3],
        unmatched: [1, 2],
        gapsFilled: 0,
        gapsRejected: 0,
      );
      expect(
        (await resolveCoverageDisplay(
          source,
          [
            trace([(40, 0), (50, 0), (60, 0)]),
          ],
          [r],
        )).single.unmatched,
        [1, 2],
      );
    },
  );
}
