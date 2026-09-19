// Widget test of dark-mode behaviour: the app's color-scheme mode resolves
// against the device brightness setting. This file covers the light OS
// surface only (today's light look, unchanged); the dark surface and the
// explicit light/dark choices live in theme_mode_setting_test.dart.
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
  testWidgets('light OS setting keeps the app light (today\'s look)',
      (WidgetTester tester) async {
    // There is no test value to set: the dispatcher defaults to light.
    await tester.pumpWidget(_appScope());
    await tester.pumpAndSettle();

    expect(materializedBrightness(tester), Brightness.light);
  });
}
