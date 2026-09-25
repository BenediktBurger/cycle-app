// Widget tests of the PDF-export action card on the settings pane: the
// export pipeline (cycle-selection page -> anonymize toggle -> generate ->
// save) from the UI side. Generation input and the save seam are stubbed
// (the document-builder provider + the io-side saveFileBytes test seam),
// so the tests never touch platform channels or write real files — the
// same pattern as the JSON import dialog's pickFileTextOverride.
//
// The cycle selection itself lives on a full-screen sub-page (pushed at
// click time from the card's "Select cycles…" button): the card keeps
// only the summary line, the anonymize switch and the export buttons.
// The sub-page's rows are ordered MOST-RECENT-FIRST, pinned controls
// (All/None/confirm) on top.
import 'dart:async';

import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/domain/pdf_export_model.dart';
import 'package:cycle_app/domain/temperature_range.dart';
import 'package:cycle_app/l10n/app_localizations.dart';
import 'package:cycle_app/pdf/cycle_pdf.dart'
    show PdfExportOptions, pdfExportFileName;
import 'package:cycle_app/providers.dart';
import 'package:cycle_app/ui/file_transfer_io.dart'
    show saveFileBytesOverride, shareFileBytesOverride;
import 'package:cycle_app/ui/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/finders.dart';

DateTime d(int month, int day) => DateTime.utc(2026, month, day);

const List<int> fakePdfBytes = [
  37, 80, 68, 70, 45, 102, 97, 107, 101, // "%PDF-fake"
];

/// Three mark-opened cycles with starts Mar 1, Mar 29, Apr 26 — enough for
/// the selection page to have rows and the default (all) selection to
/// matter.
List<DailyEntry> cardEntries() => [
  for (var i = 0; i < 28; i++) DailyEntry(date: d(3, 1 + i), bbtC: 36.5),
  for (var i = 0; i < 28; i++) DailyEntry(date: d(3, 29 + i), bbtC: 36.6),
  for (var i = 0; i < 5; i++) DailyEntry(date: d(4, 26 + i), bbtC: 36.7),
];

List<CycleMark> cardMarks() => [
  CycleMark(date: d(3, 1), type: CycleMarkTypes.cycleStart),
  CycleMark(date: d(3, 29), type: CycleMarkTypes.cycleStart),
  CycleMark(date: d(4, 26), type: CycleMarkTypes.cycleStart),
];

/// A many-cycle fixture: [n] mark-opened cycles 28 days apart, each with a
/// single tracked day on its opening mark (Jan 15 2026 + 28*i). Enough
/// rows that the oldest ones can never fit one screen — the lazy
/// ListView.builder must keep them unbuilt.
DateTime nthCycleStart(int i) =>
    DateTime.utc(2026, 1, 15).add(Duration(days: 28 * i));

List<DailyEntry> manyEntries(int n) => [
  for (var i = 0; i < n; i++) DailyEntry(date: nthCycleStart(i), bbtC: 36.5),
];

List<CycleMark> manyMarks(int n) => [
  for (var i = 0; i < n; i++)
    CycleMark(date: nthCycleStart(i), type: CycleMarkTypes.cycleStart),
];

/// What one stubbed generation run captured (model + options).
class CapturedRun {
  PdfExportModel? model;
  PdfExportOptions? options;
}

void main() {
  // The settings pane is one scroll list; the export card sits low, so the
  // tests render the full pane height in one viewport.
  Future<void> enlargeViewport(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  Widget harness({
    List<DailyEntry> entries = const [],
    List<CycleMark> marks = const [],
    List<CapturedRun>? runSink,
    VoidCallback? onExport,
    TemperatureRange? temperatureRange,
    DateTime? today,

    /// Holds one generation run open until completed: the disabled-state
    /// pin needs a frame where a run is IN FLIGHT (an immediate stub would
    /// finish the run inside the same pump).
    Completer<void>? generationGate,
    bool generationFails = false,
  }) {
    return ProviderScope(
      overrides: [
        dailyEntriesProvider.overrideWith((ref) => Stream.value(entries)),
        marksProvider.overrideWith((ref) => Stream.value(marks)),
        // The grouping's injected clock (see nowProvider — test seam):
        // pinned so fixtures far from the wall clock stay deterministic.
        if (today != null)
          nowProvider.overrideWith(
            (ref) =>
                () => today,
          ),
        pdfExportNameProvider.overrideWith((ref) => 'Maria Muster'),
        pdfExportBirthDateProvider.overrideWith(
          (ref) => DateTime.utc(1990, 1, 2),
        ),
        if (temperatureRange != null)
          temperatureRangeProvider.overrideWith((ref) => temperatureRange),
        pdfDocumentBuilderProvider.overrideWith(
          (ref) => (model, options, fontBytes) async {
            final run = (runSink == null || runSink.isEmpty)
                ? null
                : runSink.removeAt(0);
            run?.model = model;
            run?.options = options;
            onExport?.call();
            if (generationGate != null) await generationGate.future;
            if (generationFails) {
              throw StateError('stubbed document builder failure');
            }
            return fakePdfBytes;
          },
        ),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // The screen brings its own Scaffold + ListView — the enlarged
        // test surface from enlargeViewport covers its full height.
        home: EinstellungenScreen(),
      ),
    );
  }

  /// Opens the card's cycle-selection sub-page (pumped and settled), so
  /// the row/confirm helpers below address the page, not the card.
  Future<void> openSelectionPage(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('pdfExportSelectCyclesButton')));
    await tester.pumpAndSettle();
  }

  /// Pumps [widget] into the tester and then runs one settling cycle — the
  /// standard (pumpWidget, pumpAndSettle) pair every card test opens with.
  ///
  /// A test that needs extra intermediate frames (route transitions,
  /// snackbar dismissal) keeps its explicit pumps and calls this first, then
  /// pumps those frames itself.
  Future<void> pumpCard(WidgetTester tester, Widget widget) async {
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();
  }

  // The selection page's checkbox rows: keyed per row (the row index in
  // the page's visible order — MOST-RECENT-FIRST, so row 0 is the newest
  // cycle).
  Finder row(int i) =>
      find.byKey(ValueKey('pdfExportCycleCheckboxRow$i'), skipOffstage: false);

  CheckboxListTile rowWidget(WidgetTester tester, int i) {
    return tester.widget<CheckboxListTile>(row(i).first);
  }

  testWidgets(
    'card defaults: the inline checkbox list is GONE from the card — the '
    'card shows the summary line ("3 of 3 cycles selected", the null '
    'means-all default), the anonymize switch OFF and the selection '
    'button',
    (WidgetTester tester) async {
      await enlargeViewport(tester);
      await pumpCard(
        tester,
        harness(entries: cardEntries(), marks: cardMarks()),
      );

      // The checkbox rows do not render on the card anymore (they moved
      // onto the selection page).
      expect(
        find.byKey(const ValueKey('pdfExportCycleCheckboxRow0')),
        findsNothing,
      );
      // The selection button: opens the page at click time.
      expect(
        find.byKey(const ValueKey('pdfExportSelectCyclesButton')),
        findsOneWidget,
      );
      // The summary line counts the default all (semantics unchanged).
      expect(
        find.byKey(const ValueKey('pdfExportSelectedSummary')),
        findsOneWidget,
      );
      expect(find.text('3 of 3 cycles selected'), findsOneWidget);

      final anonymize = tester.widget<SwitchListTile>(
        pdfExportAnonymizeSwitch().first,
      );
      expect(anonymize.value, isFalse, reason: 'anonymize defaults to off');
    },
  );

  testWidgets('the selection page shows the pinned control row (All / None / '
      'confirm) and the MOST-RECENT cycle first, without scrolling', (
    WidgetTester tester,
  ) async {
    await enlargeViewport(tester);
    await pumpCard(tester, harness(entries: cardEntries(), marks: cardMarks()));
    await openSelectionPage(tester);

    // Pinned controls at the top of the page.
    expect(
      find.byKey(const ValueKey('pdfExportCycleSelectAll')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('pdfExportCycleSelectNone')),
      findsOneWidget,
    );
    expect(pdfExportSelectionConfirmButton(), findsOneWidget);
    // Rows newest-first: the page's row 0 is the newest cycle, the
    // ordinal-row labels keep the shared wording (reversed order).
    expect(
      rowWidget(tester, 0).title,
      isA<Text>().having((t) => t.data, 'data', 'Cycle 3, from 2026-04-26'),
      reason: 'row 0 = the most recent cycle',
    );
    expect(
      rowWidget(tester, 2).title,
      isA<Text>().having((t) => t.data, 'data', 'Cycle 1, from 2026-03-01'),
      reason: 'the oldest cycle sits last',
    );
    // The default (null = all) shows every row checked.
    expect(rowWidget(tester, 0).value, isTrue);
    expect(rowWidget(tester, 1).value, isTrue);
    expect(rowWidget(tester, 2).value, isTrue);
  });

  testWidgets('the selection list builds LAZILY (ListView.builder): with many '
      'cycles the oldest rows are not built before scrolling', (
    WidgetTester tester,
  ) async {
    // The card sits low in the settings scroll — the enlarged surface
    // (same helper as every other test) first brings the card up. The
    // page then fills the whole surface, and 80 * ~48 pt rows overflow
    // it by far, so the oldest rows cannot be onscreen, let alone
    // built (default viewport would hide the card itself instead).
    const cycles = 80;
    await enlargeViewport(tester);
    await pumpCard(
      tester,
      harness(
        entries: manyEntries(cycles),
        marks: manyMarks(cycles),
        today: DateTime.utc(2030, 1, 1),
      ),
    );
    await openSelectionPage(tester);

    // The newest cycle (row 0) is onscreen without scrolling.
    expect(
      find.byKey(const ValueKey('pdfExportCycleCheckboxRow0')),
      findsOneWidget,
    );
    // …and the oldest rows are NOT built (the lazy builder's promise —
    // with ~400 cycles a hand-rolled Column would have built all of
    // them eagerly).
    expect(
      find.byKey(const ValueKey('pdfExportCycleCheckboxRow${cycles - 1}')),
      findsNothing,
    );
  });

  testWidgets('toggling a row + confirm carries into the captured model: the '
      'unselected cycle stays out of the document', (
    WidgetTester tester,
  ) async {
    final run = CapturedRun();
    final saves = <(String, List<int>)>[];
    await enlargeViewport(tester);
    saveFileBytesOverride = (filename, bytes) async {
      saves.add((filename, bytes));
      return true;
    };
    addTearDown(() => saveFileBytesOverride = null);
    await pumpCard(
      tester,
      harness(entries: cardEntries(), marks: cardMarks(), runSink: [run]),
    );
    await openSelectionPage(tester);

    // Unselect cycle 2 (the newest-first page's row 1: the middle
    // cycle).
    await tester.tap(row(1), warnIfMissed: false);
    await tester.pumpAndSettle();
    // Both surfaces count against the same shared wording (the page's
    // pinned summary and the card's summary sit in different routes,
    // so the finder matches twice here).
    expect(find.text('2 of 3 cycles selected'), findsWidgets);

    await tester.tap(pdfExportSelectionConfirmButton());
    await tester.pumpAndSettle();

    // The applied selection lands on the card.
    expect(find.text('2 of 3 cycles selected'), findsOneWidget);
    // …and reaches the generation model (builder stub capture).
    await tester.tap(pdfExportButton());
    await tester.pumpAndSettle();
    expect(run.model, isNotNull);
    expect(run.model!.cycles.map((e) => e.cycle.startDate).toList(), [
      DateTime(2026, 3, 1),
      DateTime(2026, 4, 26),
    ], reason: 'the unselected middle cycle stays out of the document');
    expect(
      saves,
      hasLength(1),
      reason: 'the subset export still saves through the seam',
    );
  });

  testWidgets(
    'Keine on the page + confirm deselects all (the empty export stays '
    'behind the empty guard); Alle selects everything back',
    (WidgetTester tester) async {
      var runs = 0;
      await enlargeViewport(tester);
      saveFileBytesOverride = (filename, bytes) async => true;
      addTearDown(() => saveFileBytesOverride = null);
      await pumpCard(
        tester,
        harness(
          entries: cardEntries(),
          marks: cardMarks(),
          onExport: () => runs++,
        ),
      );

      await openSelectionPage(tester);
      await tester.tap(find.byKey(const ValueKey('pdfExportCycleSelectNone')));
      await tester.pumpAndSettle();
      // Every page row unchecked.
      for (var i = 0; i < 3; i++) {
        expect(rowWidget(tester, i).value, isFalse);
      }
      await tester.tap(pdfExportSelectionConfirmButton());
      await tester.pumpAndSettle();
      // The card's summary shows the empty selection.
      expect(find.text('0 of 3 cycles selected'), findsOneWidget);

      await tester.tap(pdfExportButton());
      await tester.pumpAndSettle();
      expect(
        runs,
        0,
        reason:
            'nothing selected → no document (the existing empty guard '
            'fires on the empty model)',
      );

      // Alle (back on the page) restores the default-all state.
      await openSelectionPage(tester);
      await tester.tap(find.byKey(const ValueKey('pdfExportCycleSelectAll')));
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        expect(rowWidget(tester, i).value, isTrue);
      }
      await tester.tap(pdfExportSelectionConfirmButton());
      await tester.pumpAndSettle();
      expect(find.text('3 of 3 cycles selected'), findsOneWidget);
    },
  );

  testWidgets(
    'the summary counts the selection against the LIVE choices: a chosen '
    'start that disappears from the data drops out of the count (never '
    '"3 of 2")',
    (WidgetTester tester) async {
      await enlargeViewport(tester);
      // The entry/mark streams stay CONTROLLABLE in this test: after the
      // selection is applied, the underlying data changes underneath the
      // card (the stale-selection case).
      final entriesCtrl = StreamController<List<DailyEntry>>();
      final marksCtrl = StreamController<List<CycleMark>>();
      addTearDown(() {
        entriesCtrl.close();
        marksCtrl.close();
      });
      entriesCtrl.add(cardEntries());
      marksCtrl.add(cardMarks());
      await pumpCard(
        tester,
        ProviderScope(
          overrides: [
            dailyEntriesProvider.overrideWith((ref) => entriesCtrl.stream),
            marksProvider.overrideWith((ref) => marksCtrl.stream),
            pdfExportNameProvider.overrideWith((ref) => 'Maria Muster'),
            pdfExportBirthDateProvider.overrideWith(
              (ref) => DateTime.utc(1990, 1, 2),
            ),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: EinstellungenScreen(),
          ),
        ),
      );

      // Toggle a row to materialize the selection (the first press
      // materializes the implicit all into an explicit set), then toggle
      // it back — the confirmed set then carries ALL THREE starts
      // explicitly, still reading "3 of 3".
      await openSelectionPage(tester);
      await tester.tap(row(0), warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.tap(row(0), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('3 of 3 cycles selected'), findsWidgets);
      await tester.tap(pdfExportSelectionConfirmButton());
      await tester.pumpAndSettle();
      expect(find.text('3 of 3 cycles selected'), findsOneWidget);

      // The data changes underneath: the newest cycle's start (Apr 26)
      // disappears from the tracked record (its entries + marks go).
      entriesCtrl.add([
        for (final e in cardEntries())
          if (e.date.isBefore(d(4, 26))) e,
      ]);
      marksCtrl.add([
        for (final mk in cardMarks())
          if (mk.date != d(4, 26)) mk,
      ]);
      await tester.pumpAndSettle();

      // The chosen-by-name set still holds 3 starts, but one of them is
      // not among the two LIVE choices any more: the summary shows the
      // reduced count ("2 of 2"), never the stale "3 of 2".
      expect(find.text('2 of 2 cycles selected'), findsOneWidget);
      expect(find.text('3 of 2 cycles selected'), findsNothing);
    },
  );

  testWidgets(
    'cancel (back without confirm) keeps the card\'s previous selection: '
    'the page-local toggling never leaks',
    (WidgetTester tester) async {
      final run = CapturedRun();
      await enlargeViewport(tester);
      saveFileBytesOverride = (filename, bytes) async => true;
      addTearDown(() => saveFileBytesOverride = null);
      await pumpCard(
        tester,
        harness(entries: cardEntries(), marks: cardMarks(), runSink: [run]),
      );
      await openSelectionPage(tester);

      // Toggle a row off, then leave the page WITHOUT confirming (the
      // back gesture — the same one the platform gives the user; the
      // AppBar's leading back button is it).
      await tester.tap(row(1), warnIfMissed: false);
      await tester.pumpAndSettle();
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();

      await tester.pumpAndSettle();
      // Page closed; the card still reads the untouched default all.
      expect(find.text('3 of 3 cycles selected'), findsOneWidget);
      await tester.tap(pdfExportButton());
      await tester.pumpAndSettle();
      expect(run.model!.cycles, hasLength(3));
    },
  );

  testWidgets(
    'the anonymize switch is card-local state and the export button runs '
    'the generation with the CURRENT input',
    (WidgetTester tester) async {
      final firstRun = CapturedRun();
      final secondRun = CapturedRun();
      final runs = [firstRun, secondRun];
      final saveNames = <String>[];
      await enlargeViewport(tester);
      // The save seam is stubbed too, so the whole pipeline runs inside the
      // test's fake-async zone (a real file write would not settle). The
      // stub CAPTURES the filename so the export's naming reaches the seam
      // tested, not just the payload.
      saveFileBytesOverride = (filename, bytes) async {
        saveNames.add(filename);
        return true;
      };
      addTearDown(() => saveFileBytesOverride = null);
      await pumpCard(
        tester,
        harness(entries: cardEntries(), marks: cardMarks(), runSink: runs),
      );

      await tester.tap(pdfExportButton());
      await tester.pumpAndSettle();
      expect(firstRun.model, isNotNull);
      expect(
        firstRun.options!.anonymized,
        isFalse,
        reason: 'default: no anonymization',
      );
      expect(
        firstRun.model!.name,
        'Maria Muster',
        reason:
            'the identifying value reaches the model verbatim; hiding '
            'it is the anonymize toggle\'s document-side decision',
      );
      expect(firstRun.model!.cycles, hasLength(3));
      // The save seam saw the PDF route's filename: the same ISO export
      // date the generation options were built with, suffixing the shared
      // "cycle_app_export" base (naming logic exercised through the seam,
      // mirroring the JSON route's assert).
      expect(
        saveNames.single,
        pdfExportFileName(firstRun.options!.exportDate!),
      );

      // Flip the switch, export again -> the generation input flips too.
      // The FIRST run's success SnackBar still covers the button (fake-async
      // time never expires it) — clear it the way a user's waited seconds
      // would.
      final messenger = tester.state<ScaffoldMessengerState>(
        find.byType(ScaffoldMessenger).first,
      );
      messenger.clearSnackBars();
      await tester.pump();
      await tester.pumpAndSettle();
      await tester.tap(pdfExportAnonymizeSwitch());
      await tester.pumpAndSettle();
      await tester.tap(pdfExportButton());
      await tester.pumpAndSettle();
      expect(
        secondRun.options!.anonymized,
        isTrue,
        reason: 'the per-export flip reaches the generation input',
      );
    },
  );

  testWidgets('a failed file save shows the existing no-save message '
      '(exportSaveFailed)', (WidgetTester tester) async {
    await enlargeViewport(tester);
    saveFileBytesOverride = (filename, bytes) async => false;
    addTearDown(() => saveFileBytesOverride = null);

    await pumpCard(tester, harness(entries: cardEntries(), marks: cardMarks()));
    await tester.tap(pdfExportButton());
    await tester.pumpAndSettle();

    // Status wording pin (retained text find): the exact SnackBar message
    // is what the failure path promises the user.
    expect(find.text('Saving the file failed.'), findsOneWidget);
  });

  testWidgets('a successful save shows the exportSaved message; the stored '
      'identifying values survive the anonymized run', (
    WidgetTester tester,
  ) async {
    final run = CapturedRun();
    final saveNames = <String>[];
    await enlargeViewport(tester);
    // The stub CAPTURES the filename: the anonymized export must still
    // reach the seam with the ISO export-date filename of ITS export run.
    saveFileBytesOverride = (filename, bytes) async {
      saveNames.add(filename);
      return true;
    };
    addTearDown(() => saveFileBytesOverride = null);

    await pumpCard(
      tester,
      harness(entries: cardEntries(), marks: cardMarks(), runSink: [run]),
    );

    await tester.tap(pdfExportAnonymizeSwitch());
    await tester.pumpAndSettle();
    await tester.tap(pdfExportButton());
    await tester.pumpAndSettle();
    // Status wording pin (retained text find): the exact SnackBar message
    // is what the success path promises the user.
    expect(find.text('File saved.'), findsOneWidget);
    expect(saveNames.single, pdfExportFileName(run.options!.exportDate!));

    // The stored identifying settings were not thrown away by the toggle:
    // the name field still carries the stored value (the anonymize switch
    // is card-local state; it never writes a provider or settings row).
    expect(find.text('Maria Muster'), findsOneWidget);
  });

  testWidgets(
    'the settings temperature range reaches the generation model and the '
    'anonymize switch still maps onto the per-export option',
    (WidgetTester tester) async {
      final run = CapturedRun();
      await enlargeViewport(tester);
      saveFileBytesOverride = (filename, bytes) async => true;
      addTearDown(() => saveFileBytesOverride = null);
      const range = TemperatureRange(min: 36.5, max: 37.5);
      await pumpCard(
        tester,
        harness(
          entries: cardEntries(),
          marks: cardMarks(),
          runSink: [run],
          temperatureRange: range,
        ),
      );

      await tester.tap(pdfExportAnonymizeSwitch());
      await tester.pumpAndSettle();
      await tester.tap(pdfExportButton());
      await tester.pumpAndSettle();

      expect(run.model, isNotNull);
      expect(
        run.model!.temperatureRange,
        range,
        reason:
            'the settings card\'s display range is the curve block\'s '
            'fixed y scale — echoed into the model verbatim',
      );
      expect(
        run.options!.anonymized,
        isTrue,
        reason:
            'the flipped switch still maps onto the per-export '
            'anonymize option (unchanged behavior, re-asserted)',
      );
    },
  );

  testWidgets(
    'the export card offers BOTH hand-offs in one wrap row: the renamed '
    'Save action renders left of the Share action (save keeps the key '
    'pdfExportButton and the primary styling — the mirror of the JSON '
    'export page\'s save+share row)',
    (WidgetTester tester) async {
      await enlargeViewport(tester);
      saveFileBytesOverride = (filename, bytes) async => true;
      addTearDown(() => saveFileBytesOverride = null);
      shareFileBytesOverride = (filename, bytes) async => true;
      addTearDown(() => shareFileBytesOverride = null);
      await pumpCard(
        tester,
        harness(entries: cardEntries(), marks: cardMarks()),
      );

      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      // Both sit in the SAME Wrap (the JSON page's hand-off-row idiom);
      // the innermost Wrap of the save button is that row.
      final row = find
          .ancestor(of: pdfExportButton(), matching: find.byType(Wrap))
          .first;
      expect(
        find.descendant(of: row, matching: pdfExportShareButton()),
        findsOneWidget,
      );
      expect(
        tester.getRect(pdfExportButton()).left,
        lessThan(tester.getRect(pdfExportShareButton()).left),
        reason: 'save is the primary hand-off and renders first (left)',
      );
    },
  );

  testWidgets(
    'the share press hands the generated document to the share seam alone: '
    'same bytes and export-date filename as the save route, save seam '
    'untouched (one press, one hand-off)',
    (WidgetTester tester) async {
      final run = CapturedRun();
      final shares = <(String, List<int>)>[];
      final saves = <(String, List<int>)>[];
      await enlargeViewport(tester);
      shareFileBytesOverride = (filename, bytes) async {
        shares.add((filename, bytes));
        return true;
      };
      addTearDown(() => shareFileBytesOverride = null);
      saveFileBytesOverride = (filename, bytes) async {
        saves.add((filename, bytes));
        return true;
      };
      addTearDown(() => saveFileBytesOverride = null);
      await pumpCard(
        tester,
        harness(entries: cardEntries(), marks: cardMarks(), runSink: [run]),
      );

      await tester.tap(pdfExportShareButton());
      await tester.pumpAndSettle();

      expect(
        shares.single.$1,
        pdfExportFileName(run.options!.exportDate!),
        reason:
            'the share route names the document like the save route '
            '(the ISO export date of the same run)',
      );
      expect(
        shares.single.$2,
        fakePdfBytes,
        reason: 'the SHARED payload is the generated document itself',
      );
      expect(saves, isEmpty, reason: 'sharing must not silently also save');
      expect(find.text('File shared.'), findsOneWidget);
      expect(find.text('File saved.'), findsNothing);
    },
  );

  testWidgets(
    'a failed share (the share seam reporting false) shows the share-failure '
    'message, never a success or save wording',
    (WidgetTester tester) async {
      final shares = <(String, List<int>)>[];
      await enlargeViewport(tester);
      shareFileBytesOverride = (filename, bytes) async {
        shares.add((filename, bytes));
        return false;
      };
      addTearDown(() => shareFileBytesOverride = null);
      saveFileBytesOverride = (filename, bytes) async => true;
      addTearDown(() => saveFileBytesOverride = null);
      await pumpCard(
        tester,
        harness(entries: cardEntries(), marks: cardMarks()),
      );

      await tester.tap(pdfExportShareButton());
      await tester.pumpAndSettle();

      expect(
        shares,
        hasLength(1),
        reason:
            'the press did reach the seam — '
            'the FALSE result is the failure, not a skipped hand-off',
      );
      expect(find.text('Sharing failed.'), findsOneWidget);
      expect(find.text('File shared.'), findsNothing);
      expect(find.text('Saving the file failed.'), findsNothing);
    },
  );

  testWidgets(
    'the anonymize switch flows into the SHARED generation like it does '
    'into the saved one; the stored identifying settings survive the '
    'anonymized share run',
    (WidgetTester tester) async {
      final run = CapturedRun();
      final shares = <(String, List<int>)>[];
      await enlargeViewport(tester);
      shareFileBytesOverride = (filename, bytes) async {
        shares.add((filename, bytes));
        return true;
      };
      addTearDown(() => shareFileBytesOverride = null);
      saveFileBytesOverride = (filename, bytes) async => true;
      addTearDown(() => saveFileBytesOverride = null);
      await pumpCard(
        tester,
        harness(entries: cardEntries(), marks: cardMarks(), runSink: [run]),
      );

      await tester.tap(pdfExportAnonymizeSwitch());
      await tester.pumpAndSettle();
      await tester.tap(pdfExportShareButton());
      await tester.pumpAndSettle();

      expect(run.options!.anonymized, isTrue);
      expect(shares, hasLength(1));
      expect(find.text('File shared.'), findsOneWidget);
      // Both hand-offs consume the SAME anonymize decision; it stays
      // card-local — the stored identifying field keeps its value.
      expect(find.text('Maria Muster'), findsOneWidget);
    },
  );

  testWidgets(
    'a generation failure during a SHARE press reports the share verb\'s '
    'failure message — and never reaches either seam',
    (WidgetTester tester) async {
      final shares = <(String, List<int>)>[];
      final saves = <(String, List<int>)>[];
      await enlargeViewport(tester);
      shareFileBytesOverride = (filename, bytes) async {
        shares.add((filename, bytes));
        return true;
      };
      addTearDown(() => shareFileBytesOverride = null);
      saveFileBytesOverride = (filename, bytes) async {
        saves.add((filename, bytes));
        return true;
      };
      addTearDown(() => saveFileBytesOverride = null);
      await pumpCard(
        tester,
        harness(
          entries: cardEntries(),
          marks: cardMarks(),
          generationFails: true,
        ),
      );

      await tester.tap(pdfExportShareButton());
      await tester.pumpAndSettle();

      expect(find.text('Sharing failed.'), findsOneWidget);
      expect(find.text('File shared.'), findsNothing);
      expect(shares, isEmpty);
      expect(saves, isEmpty);
    },
  );

  testWidgets(
    'both hand-off buttons disable while a run is in flight: the gate '
    'holds the generation open mid-press and the disabled states are '
    'pinned, then the gated run finishes normally',
    (WidgetTester tester) async {
      final gate = Completer<void>();
      await enlargeViewport(tester);
      shareFileBytesOverride = (filename, bytes) async => true;
      addTearDown(() => shareFileBytesOverride = null);
      saveFileBytesOverride = (filename, bytes) async => true;
      addTearDown(() => saveFileBytesOverride = null);
      await pumpCard(
        tester,
        harness(
          entries: cardEntries(),
          marks: cardMarks(),
          generationGate: gate,
        ),
      );

      await tester.tap(pdfExportButton());
      await tester.pump();
      expect(
        tester.widget<FilledButton>(pdfExportButton()).onPressed,
        isNull,
        reason: 'save is disabled mid-run — no second generation',
      );
      expect(
        tester.widget<FilledButton>(pdfExportShareButton()).onPressed,
        isNull,
        reason: 'share is disabled mid-run — one run serves one hand-off',
      );

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('File saved.'), findsOneWidget);
    },
  );

  testWidgets('an empty database never generates a document: the empty-data '
      'message shows, the builder never runs', (WidgetTester tester) async {
    var runs = 0;
    await enlargeViewport(tester);
    await pumpCard(tester, harness(onExport: () => runs++));
    await tester.tap(pdfExportButton());
    await tester.pumpAndSettle();

    expect(
      find.text('Database is empty — nothing to export.'),
      findsWidgets,
      reason: 'the card shows the guard inside AND in the SnackBar',
    );
    expect(runs, 0, reason: 'no document for empty data');
  });
}
