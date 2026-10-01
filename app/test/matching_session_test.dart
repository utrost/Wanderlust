import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wanderlust/coverage/coverage_controller.dart';
import 'package:wanderlust/geo/matching_session.dart';
import 'package:wanderlust/geo/matching_worker.dart';
import 'package:wanderlust/review/walk_review.dart';
import 'package:wanderlust/transfer/walk_codec.dart';

void main() {
  test(
    'review, worker and one-shot paths agree after matcher reuse and failure',
    () async {
      final network = await File(
        'assets/geo/bremen-center.streets.geojson',
      ).readAsString();
      final gpx = await File(
        '../data/bremen/evaluation/schlachte.synthetic.gpx',
      ).readAsString();
      final session = MatchingSession();
      final worker = MatchingWorker();
      try {
        expect(
          () => session.match('{}', [gpx], fillSmallGaps: true),
          throwsA(isA<MatchingFailure>()),
        );
        for (final fill in [false, true]) {
          final expected = session.match(network, [
            gpx,
          ], fillSmallGaps: fill).single;
          final repeated = session.match(network, [
            gpx,
          ], fillSmallGaps: fill).single;
          final background = (await worker.match(network, [
            gpx,
          ], fillSmallGaps: fill)).single;
          final once = (await matchBatchInBackground(network, [
            gpx,
          ], fillSmallGaps: fill)).single;
          final review = await matchWalkReview(
            [network],
            WalkCodec.importGpx(gpx),
            fill,
          );
          expect(repeated.walked, expected.walked);
          expect(background.walked, expected.walked);
          expect(background.inferred, expected.inferred);
          expect(once.walked, expected.walked);
          expect(review.direct.union(review.inferred), expected.walked.toSet());
          expect(review.inferred, expected.inferred.toSet());
        }
      } finally {
        session.dispose();
        session.dispose();
        await worker.close();
      }
      expect(
        () => session.match(network, [gpx], fillSmallGaps: false),
        throwsStateError,
      );
      await expectLater(
        worker.match(network, [gpx], fillSmallGaps: false),
        throwsStateError,
      );
    },
    skip: Platform.environment['WANDERLUST_NATIVE_TESTS'] != '1'
        ? 'Requires host Rust library; enabled in CI.'
        : false,
  );
}
