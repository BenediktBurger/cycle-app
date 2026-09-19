// Widget test of the bleeding control on the Tagebuch entry form: the
// selector must offer the full 5-level vocabulary (none/spotting/light/
// medium/heavy), and selecting a level must survive the save path — the
// level is read back from the database through the same database provider
// the form writes with.
//
// An in-memory drift database is injected (provider-override pattern from
// app_shell_test.dart), so the test stays file-free and platform-channel-free.
import 'package:cycle_app/domain/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/diary_harness.dart';

ProviderScope _appScope(Locale locale) => diarySelectorScope(locale);

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
    final (:db, :date) = await savedDayOf(tester);
    final row = await db.entriesDao.entryFor(date);
    expect(row, isNotNull, reason: 'The saved day must exist in the database');
    expect(
      row!.bleeding,
      Bleeding.heavy,
      reason: 'Selecting "stark" (heavy) and saving must persist level 4',
    );
  });
}
