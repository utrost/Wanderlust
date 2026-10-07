import 'package:flutter_test/flutter_test.dart';
import 'package:wanderlust/coverage/coverage_evidence.dart';

void main() {
  test('estimates never inflate visits; direct evidence wins across maps', () {
    final evidence = CoverageEvidence();
    evidence.put(1, 'a', {1}, {2, 3});
    evidence.put(1, 'b', {1, 2}, {3});
    evidence.put(2, 'a', {1}, {2, 4});
    expect(evidence.counts(['a', 'b']), {1: 2, 2: 1});
    expect(evidence.estimates(['a', 'b']), {3, 4});
    evidence.put(1, 'b', {}, {1, 2, 3});
    expect(evidence.counts(['a', 'b']), {1: 2});
    expect(evidence.estimates(['a', 'b']), {2, 3, 4});
    evidence.retain({1});
    expect(evidence.counts(['a', 'b']), {1: 1});
    expect(evidence.estimates(['a', 'b']), {2, 3});
    evidence.clear();
    expect(evidence.estimates(['a', 'b']), isEmpty);
    expect(evidence.counts(['a', 'b']), isEmpty);
  });
}
