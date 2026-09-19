// Widget test of the Muttermund (cervix) observation on the Tagebuch entry
// form: the position (tief … unerreichbar) and the opening
// (geschlossen/mittel/offen) must be offered as chip pickers, and a selected
// combination must survive the save path into the database (read back
// through the same database provider the form writes with).
//
// Provider-override harness pattern from diary_pain_selector_test.dart;
// German labels are pinned per that file's convention (pinned locale de).
import 'package:cycle_app/domain/cervix.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/diary_harness.dart';

ProviderScope _appScope(Locale locale) => diarySelectorScope(locale);

void main() {
  testWidgets('Muttermund position and opening are offered and persist',
      (WidgetTester tester) async {
    await tester.pumpWidget(_appScope(const Locale('de')));
    await tester.pumpAndSettle();

    // The pickers are offered with the German vocabulary (pinned locale).
    // NB "mittel" (position AND opening BOTH say it) is NOT asserted here
    // because it is ambiguous against the bleeding chip "mittel" on the
    // same form.
    expect(find.text('tief'), findsOneWidget,
        reason: 'the position options must be selectable');
    expect(find.text('sehr hoch'), findsOneWidget);
    expect(find.text('unerreichbar'), findsOneWidget);
    expect(find.text('geschlossen'), findsOneWidget,
        reason: 'the opening options must be selectable');
    expect(find.text('offen'), findsOneWidget);

    // Select a disambiguating combination: position tief, opening offen.
    await tester.ensureVisible(find.text('tief'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('tief'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('offen'));
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
    expect(row!.cervixPosition, CervixPosition.low.name,
        reason: 'the selected position (tief) must persist');
    expect(row.cervixOpening, CervixOpening.open.name,
        reason: 'the selected opening (offen) must persist');
  });
}
