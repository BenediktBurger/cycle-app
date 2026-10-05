import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/database.dart';

void main() {
  testWidgets('tooltips prefer above so a touch never covers them', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(appScope());
    await tester.pumpAndSettle();

    expect(
      TooltipTheme.of(tester.element(find.byType(Scaffold).first)).preferBelow,
      false,
    );
  });
}
