import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanderlust/memories/memory.dart';
import 'package:wanderlust/widgets/memory_markers.dart';
import 'package:wanderlust/theme/wanderlust_theme.dart';

void main() {
  testWidgets(
    'memory pins have Android-sized accessible targets and named actions',
    (tester) async {
      final handle = tester.ensureSemantics();
      final memory = WalkMemory.create().copyWith(
        note: 'Quiet bench',
        draft: false,
        pin: (latitude: 53, longitude: 8),
      );
      var opened = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: WanderlustTheme.light(),
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 300,
              child: MemoryMarkers(
                memories: [memory],
                size: const Size(300, 300),
                project: (_) => const Offset(150, 150),
                open: (_) => opened = true,
              ),
            ),
          ),
        ),
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      expect(find.byTooltip('Memory: Quiet bench'), findsOneWidget);
      await tester.tap(find.byTooltip('Memory: Quiet bench'));
      expect(opened, isTrue);
      handle.dispose();
    },
  );
}
