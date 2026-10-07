import 'package:flutter_test/flutter_test.dart';
import 'package:wanderlust/coverage/coverage_evidence.dart';

void main() {
  test('route visits include filled gaps once per activity across maps', () {
    final evidence = CoverageEvidence();
    evidence.put(1, 'a', {1}, {2, 3});
    evidence.put(1, 'b', {1, 2}, {3});
    evidence.put(2, 'a', {1}, {2, 4});
    expect(evidence.counts(['a', 'b']), {1: 2, 2: 2, 3: 1, 4: 1});
    evidence.put(1, 'b', {}, {1, 2, 3});
    expect(evidence.counts(['a', 'b']), {1: 2, 2: 2, 3: 1, 4: 1});
    evidence.retain({1});
    expect(evidence.counts(['a', 'b']), {1: 1, 2: 1, 3: 1});
    evidence.clear();
    expect(evidence.counts(['a', 'b']), isEmpty);
  });
}
