// Widget test of the pain options on the Tagebuch entry form: the two
// letter-coded pain options — breast tenderness (B) and Mittelschmerz (M)
// — must be offered and selectable, and selecting one of them (with the
// other unset) must survive the save path: the options are separate
// per-day booleans, read back from the database through the same
// database provider the form writes with.
//
// An in-memory drift database is injected (provider-override pattern from
// diary_bleeding_selector_test.dart).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/diary_harness.dart';

ProviderScope _appScope(Locale locale) => diarySelectorScope(locale);

void main() {
  testWidgets('pain options B and M are offered and survive the save path',
      (WidgetTester tester) async {
    await tester.pumpWidget(_appScope(const Locale('de')));
    await tester.pumpAndSettle();

    // Both options offered on the entry form (German labels, per the
    // pinned locale), each carrying its letter code.
    expect(find.text('Brustschmerzen (B)'), findsOneWidget,
        reason: 'the breast-pain (B) option must be selectable');
    expect(find.text('Mittelschmerz (M)'), findsOneWidget,
        reason: 'the Mittelschmerz (M) option must be selectable');

    // Select breast and Mittelschmerz together, then breast only.
    await tester.ensureVisible(find.text('Brustschmerzen (B)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Brustschmerzen (B)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mittelschmerz (M)'));
    await tester.pumpAndSettle();
    // Tapping the selected breast chip again deselects it (chip toggle,
    // same semantics as the bleeding chips).
    await tester.tap(find.text('Brustschmerzen (B)'));
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
    expect(row!.painMittelschmerz, isTrue,
        reason: 'the selected M option must persist');
    expect(row.painBreast, isFalse,
        reason: 'deselecting B must clear it independently of M');
  });
}
