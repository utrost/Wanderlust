import 'package:flutter_test/flutter_test.dart';
import 'package:wanderlust/coverage/unmatched_trails.dart';
import 'package:wanderlust/recording/saved_walk.dart';
import 'recording_test.dart' show fix;

SavedWalk walk(int id, {List<int> breaks = const []}) => SavedWalk(
  id,
  fix(0).timestamp,
  fix(5).timestamp,
  'completed',
  [for (var i = 0; i < 5; i++) fix(i)],
  segmentStarts: breaks,
);

void main() {
  test(
    'fallback merges consecutive pairs but never separated walks or segments',
    () {
      final trails = UnmatchedTrails();
      trails.put(walk(1, breaks: [3]), 'a', [1, 2, 3, 4]);
      trails.put(walk(2), 'a', [1]);
      final lines = trails.lines(['a']);
      expect(lines.map((line) => line.length), [3, 2, 2]);
    },
  );
  test(
    'overlapping maps suppress pairs matched in either map and deduplicate',
    () {
      final trails = UnmatchedTrails();
      trails.put(walk(1), 'a', [1, 2, 4]);
      trails.put(walk(1), 'b', [1, 4]);
      expect(trails.lines(['a', 'b']).map((line) => line.length), [2, 2]);
      expect(trails.lines(['a', 'missing']), isEmpty);
      trails.put(walk(1), 'b', []);
      expect(trails.lines(['a', 'b']), isEmpty);
    },
  );
  test(
    'deletion and clearing remove derived trails; invalid indices reject',
    () {
      final trails = UnmatchedTrails();
      trails.put(walk(1), 'a', [1]);
      trails.put(walk(2), 'a', [1]);
      trails.retain({2});
      expect(trails.contains(1, 'a'), isFalse);
      expect(trails.lines(['a']), hasLength(1));
      expect(() => trails.put(walk(2), 'a', [5]), throwsStateError);
      trails.clear();
      expect(trails.lines(['a']), isEmpty);
    },
  );
}
