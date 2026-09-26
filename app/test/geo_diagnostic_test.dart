import 'package:flutter_test/flutter_test.dart';
import 'package:wanderlust/geo/geo_core_ffi.dart';
import 'package:wanderlust/geo/live_match.dart';

void main() {
  for (final failure in [...GeoStage.values, null]) {
    test('diagnostics classify $failure and free loaded matchers', () async {
      var disposed = false;
      void fail(GeoStage stage) {
        if (failure == stage) throw StateError('specific failure');
      }

      final result = await diagnoseSample(
        loadAsset: (_) async {
          fail(GeoStage.assets);
          return 'fixture';
        },
        open: () {
          fail(GeoStage.library);
          return Object();
        },
        loadNetwork: (_, __) {
          fail(GeoStage.network);
          return Object();
        },
        match: (_, __) {
          fail(GeoStage.matching);
          return const MatchResult(walked: [1], gapsFilled: 0, gapsRejected: 0);
        },
        dispose: (_) {
          disposed = true;
        },
      );
      expect(result.stage, failure);
      expect(disposed, failure == null || failure == GeoStage.matching);
      if (failure != null) {
        expect(result.detail, contains('specific failure'));
      } else {
        expect(result.result!.walked, [1]);
      }
    });
  }
}
