// Widget test of dark-mode behaviour: the app follows the device brightness
// setting. A dark OS surface must materialize a dark color scheme; a light
// OS surface must keep today's light look (default light theme, unchanged).
//
// The platform brightness is set via the test platform dispatcher, which is
// what ThemeMode.system (MaterialApp default) resolves against. An in-memory
// drift database is injected so the widget shell materializes like in the
// app shell smoke test.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/finders.dart';

import 'support/database.dart';

ProviderScope _appScope() => appScope();

void main() {
  testWidgets('dark OS setting renders the app with a dark scheme',
      (WidgetTester tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearAllTestValues);

    await tester.pumpWidget(_appScope());
    await tester.pumpAndSettle();

    expect(
      materializedBrightness(tester),
      Brightness.dark,
      reason:
          'The app must follow the device dark setting, not stay light-only',
    );
  });

  testWidgets('light OS setting keeps the app light (today\'s look)',
      (WidgetTester tester) async {
    // There is no test value to set: the dispatcher defaults to light.
    await tester.pumpWidget(_appScope());
    await tester.pumpAndSettle();

    expect(materializedBrightness(tester), Brightness.light);
  });
}
