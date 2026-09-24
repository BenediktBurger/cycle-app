// Lifecycle regression matrix for the dialog and the tab shell: the Android
// field report for this cluster was a Flutter framework assertion
// (`_dependents.isEmpty` in InheritedElement unmount — an inherited widget
// element taken down while widgets still depend on it), most plausibly tied
// to a dismissal race around a dialog route or to the diary form reloading
// mid-flight. The import dialogs themselves had already been refactored into
// fully self-contained stateful widgets (screen-level controllers and manual
// disposal after `await showDialog` were the earlier structural suspect), so
// this matrix drives the *remaining* interaction surface through the real
// app shell with ALL tabs mounted in the IndexedStack:
//
//   a) JSON import dialog: type into the textarea, dismiss via the scrim.
//   b) drip CSV import dialog: picker content, Apply while the import runs,
//      fast scrim dismissal through the still-running apply.
//   c) diary form: pick a mucus sign + a quality, then change the selected
//      date OFFSTAGE (provider write while the diary is mounted but hidden
//      behind the cycle tab — the chart-tap path, exercised directly at the
//      provider) and check the mid-form reload through the listener.
//   d) drip import: apply, fast scrim dismissal, RE-OPEN immediately.
//
// Each subtest installs a `FlutterError.onError` collector for its scenario
// INCLUDING the explicit tree teardown (`tester.pumpWidget(SizedBox)`)
// inside the collected window (the reported assertion class fires during
// element unmount, so teardown is where it would surface) and ends asserting
// the collected error list is empty.
//
// RESULT OF THE INVESTIGATION (plain language):
// Subtests (b) and (d) reproduced a real dismissal defect. Fast scrim
// dismissal racing the running import popped the ENTIRE route stack out
// from under the app: right after the second tap the MaterialApp rendered
// an empty Navigator — no scaffold, no shell, no bottom navigation. Cause:
// the dialogs' apply closure runs on the settings screen and pops the DIALOG
// by the dialog's context once the import lands. After a fast dismissal the
// dialog route is already popped by the barrier tap, but its elements are
// not yet torn down — `dialogContext.mounted` is still true, so the old
// `mounted`-guarded pop went through, `Navigator.of(dialogContext)` still
// resolved to the root navigator (the context's ancestor chain is intact
// until finalization) and popped whatever was on top now: the HOME route.
// On a device, the same race tears the whole visible UI down with the
// dialog — the churn through the route's inherited-element teardown (the
// dialog route's MediaQuery/Localizations/riverpod scope dependents being
// disassembled while still registering dependents) is precisely the class
// of field-reported framework assertion this matrix was hunting.
// The fix: the success-path pop only fires while the dialog route is still
// the current route (`ModalRoute.of(...).isCurrent` in the settings screen's
// apply handlers); the import summary still appears as a snackbar from the
// screen context either way.
// Subtests (a) and (c) pass before and after the fix and stay as regression
// guards: (a) covers a plain typed-then-dismissed dialog, (c) covers the
// mid-form listener reload of the entry form (S + quality selected, then the
// selected date changed through the provider while the diary tab is hidden).
import 'package:cycle_app/domain/date_only.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/providers.dart';
import 'package:cycle_app/ui/diary.dart';
import 'package:cycle_app/ui/file_transfer_io.dart' show pickFileTextOverride;
import 'package:cycle_app/ui/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'support/database.dart';
import 'support/finders.dart';
import 'support/fixtures.dart';
import 'support/viewport.dart';

/// Runs [body] with a collector installed in place of [FlutterError.onError];
/// after [body] returns, the whole widget tree is torn down INSIDE the
/// collected window (element unmount is where an inherited-widget teardown
/// assertion would fire), so the caller can assert over everything the
/// framework reported during the whole scenario INCLUDING teardown.
Future<List<FlutterErrorDetails>> collectLifecycleErrors(
  WidgetTester tester,
  Future<void> Function() body,
) async {
  final errors = <FlutterErrorDetails>[];
  final original = FlutterError.onError;
  FlutterError.onError = (details) => errors.add(details);
  try {
    await body();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  } finally {
    FlutterError.onError = original;
  }
  return errors;
}

/// The German yMd day label exactly as the diary renders it (same formatter
/// and locale as the screen itself).
String germanDayLabel(DateTime day) =>
    DateFormat.yMd('de').format(DateOnly.normalize(day).toLocal());

/// Pumps the real app shell (in-memory database, German pin, every tab
/// mounted) and settles it, DISCHARGING the one-time pump-time layout
/// record: under widget-test font metrics the diary date row overflows
/// exactly once at the forced narrow initial layout (documented in the
/// narrow-width harness note of diary_entry_form_test.dart; on real device
/// fonts it does not) — that single record is not what these tests measure.
/// Everything after this call, on any interaction and at teardown, belongs
/// to the lifecycle scenarios and must stay silent. [seedDays] seeds one
/// plain temperature-only entry per UTC date so the diary's cycle list has
/// a group with day tiles.
Future<void> pumpShell(
  WidgetTester tester, {
  required Set<int> seedDays,
  int month = 9,
}) async {
  await tester.pumpWidget(
    appScope(
      locale: const Locale('de'),
      now: () => DateTime.utc(2026, month, 10),
      selectedDay: DateTime.utc(2026, month, 10),
      entriesStream: Stream.value([
        for (final day in seedDays)
          DailyEntry(date: DateTime.utc(2026, month, day), bbtC: 36.5),
      ]),
    ),
  );
  await tester.pumpAndSettle();
  tester.takeException();
}

/// Scrolls the settings list until the given import card button is visible
/// and taps it, opening the dialog.
Future<void> openImportDialog(
  WidgetTester tester, {
  required String buttonLabel,
}) async {
  await tester.tap(navLabel('Einstellungen'));
  await tester.pumpAndSettle();
  final cardButton = find.widgetWithText(FilledButton, buttonLabel);
  await tester.scrollUntilVisible(
    cardButton,
    200,
    scrollable: find
        .descendant(
          of: find.byType(EinstellungenScreen),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
  // The card button is the only match of its label while no dialog is open
  // (the dialog's apply button carries the drip label, so once it opens the
  // label matches twice — the card stays .first in tree order). .first must
  // not be evaluated while the finder is still empty (the list is lazy below
  // the cache extent), so the .first restriction happens only at tap time.
  await tester.tap(find.widgetWithText(FilledButton, buttonLabel).first);
  await tester.pumpAndSettle();
}

/// The dialog-scoped versions of the shared labels: the dialogs carry the
/// same button labels as the settings cards underneath, so everything stays
/// scoped to the open AlertDialog.
Finder dialogChild(Finder inner) =>
    find.descendant(of: find.byType(AlertDialog), matching: inner);

void main() {
  group('dialog and shell lifecycle', () {
    testWidgets(
      'JSON import dialog: typed text then barrier dismissal leaks nothing '
      'into the framework',
      (WidgetTester tester) async {
        useSmallAndroidViewport(tester);
        await pumpShell(tester, seedDays: {});
        final errors = await collectLifecycleErrors(tester, () async {
          await openImportDialog(tester, buttonLabel: 'JSON-Import');
          expect(
            find.byType(AlertDialog),
            findsOneWidget,
            reason: 'the JSON import dialog must be open before dismissal',
          );
          await tester.enterText(
            dialogChild(find.byType(TextField)),
            '{"entries": [], "marks": []}',
          );
          await tester.pump();
          // Barrier dismissal while no import runs: the dialog route
          // finalizes with a non-empty textarea.
          await tester.tapAt(const Offset(10, 10));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
        });

        expect(
          errors,
          isEmpty,
          reason:
              'dismissing the JSON import dialog must not surface the '
              'inherited-element teardown assertion or any dispose error',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'drip import dismissed via the scrim while the import runs leaks '
      'nothing into the framework',
      (WidgetTester tester) async {
        useSmallAndroidViewport(tester);
        pickFileTextOverride = (accept) async => sampleDripCsv;
        addTearDown(() => pickFileTextOverride = null);
        await pumpShell(tester, seedDays: {});
        final errors = await collectLifecycleErrors(tester, () async {
          await openImportDialog(tester, buttonLabel: 'CSV importieren');
          expect(find.byType(AlertDialog), findsOneWidget);
          // Pick the sample CSV through the hermetic override, then apply.
          await tester.tap(
            dialogChild(find.widgetWithText(OutlinedButton, 'Datei wählen')),
          );
          await tester.pumpAndSettle();
          // No pump between Apply and the barrier tap: the dismissal races
          // the running import, exactly the field scenario.
          await tester.tap(
            dialogChild(find.widgetWithText(FilledButton, 'CSV importieren')),
          );
          await tester.tapAt(const Offset(10, 10));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
          // The import summary snackbar floats above the bottom navigation
          // for its display duration (standard Material behavior); advance
          // the clock past it before tapping navigation destinations.
          await tester.pump(const Duration(seconds: 5));
          await tester.pumpAndSettle();
          // The shell must survive the raced dismissal: the home route with
          // the whole IndexedStack is still intact and navigable.
          await tester.tap(navLabel('Tagebuch'));
          await tester.pumpAndSettle();
          expect(
            find.byType(TagebuchScreen),
            findsOneWidget,
            reason: 'the raced dismissal must leave the home route intact',
          );
        });

        expect(
          errors,
          isEmpty,
          reason:
              'dismissing the import route while its apply future is '
              'still running must not produce a dispose or teardown error',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'diary form survives a date change taken offstage with selected '
      'sign/quality while its tab is hidden',
      (WidgetTester tester) async {
        useSmallAndroidViewport(tester);
        await pumpShell(tester, seedDays: {1, 5});
        await tester.tap(navLabel('Tagebuch'));
        await tester.pumpAndSettle();

        Finder inDiary(Finder inner) =>
            find.descendant(of: find.byType(TagebuchScreen), matching: inner);
        Finder diaryScrollable() => find
            .descendant(
              of: find.byType(TagebuchScreen),
              matching: find.byType(Scrollable),
            )
            .first;
        Finder dateButton(DateTime day) =>
            inDiary(find.widgetWithText(OutlinedButton, germanDayLabel(day)));

        final errors = await collectLifecycleErrors(tester, () async {
          // --- select sign S + a quality (unsaved form state) ------------
          final sChip = inDiary(diaryChip('mucusSign', 's'));
          await tester.scrollUntilVisible(
            sChip,
            150,
            scrollable: diaryScrollable(),
          );
          await tester.pumpAndSettle();
          await tester.tap(sChip.first);
          await tester.pumpAndSettle();
          expect(
            inDiary(find.byKey(const ValueKey('mucusQualityRow'))),
            findsOneWidget,
          );
          final ewChip = inDiary(diaryChip('mucusQuality', 'ew'));
          await tester.scrollUntilVisible(
            ewChip,
            150,
            scrollable: diaryScrollable(),
          );
          await tester.pumpAndSettle();
          await tester.tap(ewChip.first);
          await tester.pumpAndSettle();

          // --- offstage date change (the chart-tap provider path) --------
          // Switch to the cycle tab: the diary stays mounted but hidden in
          // the IndexedStack. Writing the selected date through the provider
          // directly is exactly what a chart tap does; the diary's provider
          // listener must reload the form there.
          await tester.tap(navLabel('Zyklus'));
          await tester.pumpAndSettle();
          expect(
            find.byType(TagebuchScreen, skipOffstage: false),
            findsOneWidget,
            reason:
                'the diary stays mounted in the stack behind the cycle '
                'tab',
          );
          final container = ProviderScope.containerOf(
            tester.element(find.byType(TagebuchScreen, skipOffstage: false)),
          );
          container.read(selectedDateProvider.notifier).state =
              DateOnly.normalize(DateTime.utc(2026, 9, 5));
          await tester.pump();
          await tester.tap(navLabel('Tagebuch'));
          await tester.pumpAndSettle();
          expect(
            dateButton(DateTime.utc(2026, 9, 5)),
            findsOneWidget,
            reason:
                'the offstage reload must have landed on the new day '
                'when the tab is shown again',
          );
          // The reload resets the unsaved S/EW selection: the quality row is
          // gone again.
          expect(
            inDiary(find.byKey(const ValueKey('mucusQualityRow'))),
            findsNothing,
          );
        });

        expect(
          errors,
          isEmpty,
          reason:
              'listener-triggered form reloads (on-screen and offstage) '
              'must not surface setState-during-build or teardown errors',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'drip import: apply, fast barrier dismissal and immediate re-open '
      'leak nothing into the framework',
      (WidgetTester tester) async {
        useSmallAndroidViewport(tester);
        pickFileTextOverride = (accept) async => sampleDripCsv;
        addTearDown(() => pickFileTextOverride = null);
        await pumpShell(tester, seedDays: {});
        final errors = await collectLifecycleErrors(tester, () async {
          await openImportDialog(tester, buttonLabel: 'CSV importieren');
          await tester.tap(
            dialogChild(find.widgetWithText(OutlinedButton, 'Datei wählen')),
          );
          await tester.pumpAndSettle();
          // Fast dismissal racing the apply, then re-open immediately: the
          // dialog must come back as a fresh, working stateful widget.
          await tester.tap(
            dialogChild(find.widgetWithText(FilledButton, 'CSV importieren')),
          );
          await tester.tapAt(const Offset(10, 10));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
          // The import summary snackbar floats above the bottom navigation
          // for its display duration (standard Material behavior); advance
          // the clock past it before tapping navigation destinations.
          await tester.pump(const Duration(seconds: 5));
          await tester.pumpAndSettle();
          await openImportDialog(tester, buttonLabel: 'CSV importieren');
          expect(
            find.byType(AlertDialog),
            findsOneWidget,
            reason:
                're-opening after the fast dismissal must show a fresh '
                'dialog',
          );
          await tester.enterText(dialogChild(find.byType(TextField)), 'x');
          await tester.tapAt(const Offset(10, 10));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
        });

        expect(
          errors,
          isEmpty,
          reason:
              'the apply/dismiss/re-open cycle must not leak framework '
              'errors from the dialog state or the routed screen callbacks',
        );
        expect(tester.takeException(), isNull);
      },
    );
  });
}
