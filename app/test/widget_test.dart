import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanderlust/main.dart';

void main() {
  testWidgets('boots to the map screen with the area chrome', (tester) async {
    await tester.pumpWidget(const WanderlustApp());

    // The calm map chrome renders regardless of whether the native geo-core is
    // present (the FFI status resolves asynchronously and degrades gracefully).
    expect(find.text('Kreuzberg'), findsOneWidget);
    expect(find.text('Start walk'), findsOneWidget);
  });
}
