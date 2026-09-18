// Widget test of the bleeding control on the Tagebuch entry form: the
// selector must offer the full 5-level vocabulary (none/spotting/light/
// medium/heavy), and selecting a level must survive the save path — the
// level is read back from the database through the same database provider
// the form writes with.
//
// An in-memory drift database is injected (provider-override pattern from
// app_shell_test.dart), so the test stays file-free and platform-channel-free.
import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/main.dart';
import 'package:cycle_app/providers.dart';
import 'package:cycle_app/ui/diary.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ProviderScope _appScope(Locale locale) => ProviderScope(
      overrides: [
        // In-memory database: no files, no platform channels, no FFI paths.
        // ref.onDispose closes it together with the test's ProviderScope
        // (same closing semantics as the production provider; the
        // closeStreamsSynchronously remedy for stream-teardown timers is
        // documented in app_shell_test.dart).
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
        localeProvider.overrideWith((ref) => locale),
      ],
      child: const CycleApp(),
    );

void main() {
  testWidgets('bleeding selector offers all five levels and stores heavy',
      (WidgetTester tester) async {
    await tester.pumpWidget(_appScope(const Locale('de')));
    await tester.pumpAndSettle();

    // The Tagebuch screen is the shell's initial tab; the bleeding control
    // sits on its entry form. All five levels of the numeric scale must be
    // offered (German labels, per the pinned locale). NB "mittel" is also
    // the German label of one Muttermund position AND of the opening chip
    // "mittel" on the same form, so the strict one-match assertion does not
    // apply to that one word.
    const levels = ['keine', 'Schmierblutung', 'leicht', 'mittel', 'stark'];
    for (final level in levels) {
      expect(
        find.text(level),
        findsWidgets,
        reason: 'Bleeding option "$level" should be offered on the form',
      );
    }

    // Select the heaviest level and save the day.
    await tester.ensureVisible(find.text('stark'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('stark'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Speichern'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    // Read the saved day back through the database provider — the same
    // instance the form writes through, not a second connection.
    final context = tester.element(find.byType(TagebuchScreen));
    final container = ProviderScope.containerOf(context);
    final db = await container.read(databaseProvider.future);
    final date = container.read(selectedDateProvider);
    final row = await db.entriesDao.entryFor(date);
    expect(row, isNotNull, reason: 'The saved day must exist in the database');
    expect(
      row!.bleeding,
      Bleeding.heavy,
      reason: 'Selecting "stark" (heavy) and saving must persist level 4',
    );
  });
}
