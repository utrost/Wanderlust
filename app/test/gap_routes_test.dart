import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wanderlust/recording/saved_walk.dart';
import 'package:wanderlust/review/gap_routes.dart';

String routes({bool alternative = false, bool disconnected = false}) =>
    jsonEncode({
      'features': [
        for (final e in <(int, int, int, List<List<double>>)>[
          (
            1,
            1,
            2,
            [
              [0, 0],
              [.001, 0],
            ],
          ),
          (
            2,
            disconnected ? 20 : 2,
            3,
            [
              [.001, 0],
              [.002, 0],
            ],
          ),
          if (alternative)
            (
              3,
              1,
              4,
              [
                [0, 0],
                [.001, .0005],
              ],
            ),
          if (alternative)
            (
              4,
              4,
              3,
              [
                [.001, .0005],
                [.002, 0],
              ],
            ),
        ])
          {
            'id': e.$1,
            'properties': {'from_node': e.$2, 'to_node': e.$3},
            'geometry': {'coordinates': e.$4},
          },
      ],
    });
Position point(double x, int sec, {double accuracy = 5}) => Position(
  longitude: x,
  latitude: 0,
  timestamp: DateTime.utc(2026, 1, 1).add(Duration(seconds: sec)),
  accuracy: accuracy,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);
SavedWalk walk({
  int seconds = 140,
  List<int> breaks = const [],
  List<int> untimed = const [],
}) => SavedWalk(
  1,
  DateTime.utc(2026),
  null,
  'completed',
  [point(0, 0), point(.001, 100, accuracy: 100), point(.002, seconds)],
  segmentStarts: breaks,
  untimed: untimed,
);
void main() {
  test(
    'outage skips poor fixes and offers network routes without changing the trace',
    () async {
      final w = walk();
      final gaps = await suggestGapRoutes([routes(alternative: true)], w);
      expect(gaps, hasLength(1));
      expect(gaps.single.routes, hasLength(2));
      expect(gaps.single.routes.first.edges, [1, 2]);
      expect(gaps.single.routes.first.meters, closeTo(222.64, 1));
      expect(w.confirmedSections, isEmpty);
      expect(w.points, hasLength(3));
    },
  );
  test(
    'never invent connections across disconnected topology or track breaks',
    () async {
      expect(
        (await suggestGapRoutes([
          routes(disconnected: true),
        ], walk())).single.routes,
        isEmpty,
      );
      expect(await suggestGapRoutes([routes()], walk(breaks: [1])), isEmpty);
      expect(await suggestGapRoutes([routes()], walk(untimed: [1])), isEmpty);
      expect(await suggestGapRoutes([routes()], walk(seconds: 301)), isEmpty);
    },
  );
  test('rejects routes impossible in elapsed time and missing maps', () async {
    final w = SavedWalk(1, DateTime.utc(2026), null, 'completed', [
      point(0, 0),
      point(.002, 31),
    ]);
    expect((await suggestGapRoutes([routes()], w)).single.routes, isEmpty);
    expect((await suggestGapRoutes([], walk())).single.routes, isEmpty);
  });
}
