// Language default semantics: with no explicit language chosen in the
// settings (the "System" option), the app follows the platform's language
// when it is one of the supported languages (de/en) and falls back to
// English otherwise — never German (ADR-0007). An explicit settings choice
// wins over the platform regardless of what language the device reports.
//
// The platform locale is simulated through the test binding's platform
// dispatcher; the app itself is unchanged: in-memory drift database
// override, no platform channels (same pattern as app_shell_test.dart).
import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/main.dart';
import 'package:cycle_app/providers.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// App scope for the language tests. A null [locale] means: leave the
/// provider at its real default (the "System" option); anything else is an
/// explicit settings choice.
ProviderScope _appScope({Locale? locale}) => ProviderScope(
      overrides: [
        databaseProvider.overrideWith(
          (ref) {
            final db = CycleDatabase(
              DatabaseConnection(
                NativeDatabase.memory(),
                closeStreamsSynchronously: true,
              ),
            );
            ref.onDispose(db.close);
            return db;
          },
        ),
        if (locale != null) localeProvider.overrideWith((ref) => locale),
      ],
      child: const CycleApp(),
    );

void main() {
  testWidgets(
      'system-default on a German device resolves to German UI',
      (WidgetTester tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('de')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    await tester.pumpWidget(_appScope());
    await tester.pumpAndSettle();

    expect(find.text('Tagebuch'), findsWidgets,
        reason: 'The system language German must be picked up for de devices');
    expect(find.text('Diary'), findsNothing,
        reason: 'The fallback must not kick in for a supported device locale');
  });

  testWidgets(
      'system-default on a French device resolves to English UI',
      (WidgetTester tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('fr')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    await tester.pumpWidget(_appScope());
    await tester.pumpAndSettle();

    expect(find.text('Diary'), findsWidgets,
        reason: 'An unsupported device locale must fall back to English');
    expect(find.text('Tagebuch'), findsNothing,
        reason: 'German is never the automatic fallback (ADR-0007)');
  });

  testWidgets(
      'explicit German choice wins over a French device locale',
      (WidgetTester tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('fr')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    await tester.pumpWidget(_appScope(locale: const Locale('de')));
    await tester.pumpAndSettle();

    expect(find.text('Tagebuch'), findsWidgets,
        reason: 'An explicit language choice must beat the device locale');
    expect(find.text('Diary'), findsNothing);
  });

  testWidgets(
      'explicit English choice wins over a German device locale',
      (WidgetTester tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('de')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    await tester.pumpWidget(_appScope(locale: const Locale('en')));
    await tester.pumpAndSettle();

    expect(find.text('Diary'), findsWidgets,
        reason: 'An explicit language choice must beat the device locale');
    expect(find.text('Tagebuch'), findsNothing);
  });

  testWidgets(
      'settings switcher renders System/Deutsch/English and switches between them',
      (WidgetTester tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('de')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    await tester.pumpWidget(_appScope());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Einstellungen').first);
    await tester.pumpAndSettle();

    // All three options are offered.
    for (final option in ['System', 'Deutsch', 'English']) {
      expect(find.text(option), findsOneWidget,
          reason: 'Language option "$option" must be offered');
    }
    final switcher =
        tester.widget<SegmentedButton<String>>(find.byType(SegmentedButton<String>));
    expect(switcher.selected, {'system'},
        reason: 'The default selection must be "System"');

    // Switching to an explicit language applies it immediately.
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('Diary'), findsOneWidget,
        reason: 'Selecting English must switch the UI to English');
    final switcher2 =
        tester.widget<SegmentedButton<String>>(find.byType(SegmentedButton<String>));
    expect(switcher2.selected, {'en'});

    // Back to the system default: the German device locale returns.
    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();
    expect(find.text('Tagebuch'), findsOneWidget,
        reason: 'Selecting System must follow the device locale again');
    final switcher3 =
        tester.widget<SegmentedButton<String>>(find.byType(SegmentedButton<String>));
    expect(switcher3.selected, {'system'});
  });
}
