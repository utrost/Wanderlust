import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanderlust/review/gap_routes.dart';
import 'package:wanderlust/widgets/gap_review_panel.dart';
import 'gap_routes_test.dart' show walk;

void main() {
  testWidgets(
    'preview never saves; confirmation, retry and undo are explicit',
    (tester) async {
      const first = GapRoute([1, 2], [Offset(0, 0), Offset(.002, 0)], 200);
      const second = GapRoute([3, 4], [Offset(0, 0), Offset(.002, .001)], 250);
      GapRoute? preview;
      Set<int>? confirmed;
      var fail = true;
      final saves = <List<int>>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GapReviewPanel(
              walk: walk(),
              maps: const [],
              suggest: (_, _) async => [
                ReviewGap(
                  DateTime.utc(2026),
                  DateTime.utc(2026).add(const Duration(seconds: 140)),
                  [first, second],
                ),
              ],
              save: (edges) async {
                saves.add(edges);
                if (fail) throw StateError('disk');
              },
              onPreview: (r) => preview = r,
              onConfirmed: (v) => confirmed = v,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Review GPS gaps'));
      await tester.pumpAndSettle();
      expect(preview, first);
      expect(saves, isEmpty);
      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Route 2 · 250 m').last);
      await tester.pumpAndSettle();
      expect(preview, second);
      expect(saves, isEmpty);
      await tester.tap(find.text('I walked this'));
      await tester.pumpAndSettle();
      expect(confirmed, isNull);
      expect(find.text('Could not save. Please retry.'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('I walked this'));
      await tester.pumpAndSettle();
      expect(confirmed, {3, 4});
      expect(saves.last, [3, 4]);
      await tester.tap(find.byTooltip('Undo all confirmed gaps for this walk'));
      await tester.pumpAndSettle();
      expect(confirmed, isEmpty);
      expect(saves.last, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
