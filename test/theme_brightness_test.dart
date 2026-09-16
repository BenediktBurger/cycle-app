// Widget test of dark-mode behaviour: the app follows the device brightness
// setting. A dark OS surface must materialize a dark color scheme; a light
// OS surface must keep today's light look (default light theme, unchanged).
//
// The platform brightness is set via the test platform dispatcher, which is
// what ThemeMode.system (MaterialApp default) resolves against. An in-memory
// drift database is injected so the widget shell materializes like in the
// app shell smoke test.
import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/main.dart';
import 'package:cycle_app/providers.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ProviderScope _appScope() => ProviderScope(
      overrides: [
        databaseProvider.overrideWith((ref) {
          final db = CycleDatabase(
            DatabaseConnection(
              NativeDatabase.memory(),
              closeStreamsSynchronously: true,
            ),
          );
          ref.onDispose(db.close);
          return db;
        }),
      ],
      child: const CycleApp(),
    );

/// The color-scheme brightness actually materialized by the running app,
/// taken from the shell's Scaffold (below the MaterialApp theme wiring).
Brightness _materializedBrightness(WidgetTester tester) {
  final scaffoldContext = tester.element(find.byType(Scaffold).first);
  return Theme.of(scaffoldContext).colorScheme.brightness;
}

void main() {
  testWidgets('dark OS setting renders the app with a dark scheme',
      (WidgetTester tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearAllTestValues);

    await tester.pumpWidget(_appScope());
    await tester.pumpAndSettle();

    expect(
      _materializedBrightness(tester),
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

    expect(_materializedBrightness(tester), Brightness.light);
  });
}
