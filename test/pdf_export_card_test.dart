// Widget tests of the PDF-export action card on the settings pane: the
// export pipeline (cycle selector -> anonymize toggle -> generate ->
// save) from the UI side. Generation input and the save seam are stubbed
// (the document-builder provider + the io-side saveFileBytes test seam),
// so the tests never touch platform channels or write real files — the
// same pattern as the JSON import dialog's pickFileTextOverride.
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/domain/pdf_export_model.dart';
import 'package:cycle_app/domain/temperature_range.dart';
import 'package:cycle_app/l10n/app_localizations.dart';
import 'package:cycle_app/pdf/cycle_pdf.dart'
    show PdfExportOptions, pdfExportFileName;
import 'package:cycle_app/providers.dart';
import 'package:cycle_app/ui/file_transfer_io.dart' show saveFileBytesOverride;
import 'package:cycle_app/ui/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime d(int month, int day) => DateTime.utc(2026, month, day);

const List<int> fakePdfBytes = [
  37, 80, 68, 70, 45, 102, 97, 107, 101, // "%PDF-fake"
];

/// Three mark-opened cycles with starts Mar 1, Mar 29, Apr 26 — enough for
/// the selector to have rows and the default (latest) selection to matter.
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
  }) {
    return ProviderScope(
      overrides: [
        dailyEntriesProvider.overrideWith((ref) => Stream.value(entries)),
        marksProvider.overrideWith((ref) => Stream.value(marks)),
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

  testWidgets(
    'card defaults: the selector shows the LATEST observed cycle (its '
    'shared ordinal + start date), the anonymize switch is OFF',
    (WidgetTester tester) async {
      await enlargeViewport(tester);
      await tester.pumpWidget(
        harness(entries: cardEntries(), marks: cardMarks()),
      );
      await tester.pumpAndSettle();

      final select = find.byKey(
        const ValueKey('pdfExportCycleSelect'),
        skipOffstage: true,
      );
      expect(select, findsOneWidget);
      final field = tester
          .widget<DropdownButtonFormField<int>>(select)
          .initialValue;
      // The default = the latest mark-opened cycle, numbered by the shared
      // ordinal rule (3 mark-opened cycles, no outside-app ones).
      expect(field, 3);
      // The observed cycles appear in the menu, numbered + dated "up to the
      // exported one" (first cycle to the chosen one). The LATEST row
      // ("Cycle 3") shows twice: the closed field carries the default AND
      // the menu carries the row.
      await tester.tap(select);
      await tester.pumpAndSettle();
      expect(find.text('Cycle 1, from 2026-03-01'), findsOneWidget);
      expect(find.text('Cycle 2, from 2026-03-29'), findsOneWidget);
      expect(find.text('Cycle 3, from 2026-04-26'), findsNWidgets(2));
      await tester.tapAt(const Offset(10, 10)); // close the menu
      await tester.pumpAndSettle();

      final anonymize = tester.widget<SwitchListTile>(
        find.byKey(const ValueKey('pdfExportAnonymizeSwitch')).first,
      );
      expect(anonymize.value, isFalse, reason: 'anonymize defaults to off');
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
      await tester.pumpWidget(
        harness(entries: cardEntries(), marks: cardMarks(), runSink: runs),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('pdfExportButton')));
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
      await tester.tap(find.byKey(const ValueKey('pdfExportAnonymizeSwitch')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pdfExportButton')));
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

    await tester.pumpWidget(
      harness(entries: cardEntries(), marks: cardMarks()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pdfExportButton')));
    await tester.pumpAndSettle();

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

    await tester.pumpWidget(
      harness(entries: cardEntries(), marks: cardMarks(), runSink: [run]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('pdfExportAnonymizeSwitch')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pdfExportButton')));
    await tester.pumpAndSettle();
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
      await tester.pumpWidget(
        harness(
          entries: cardEntries(),
          marks: cardMarks(),
          runSink: [run],
          temperatureRange: range,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('pdfExportAnonymizeSwitch')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pdfExportButton')));
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

  testWidgets('an empty database never generates a document: the empty-data '
      'message shows, the builder never runs', (WidgetTester tester) async {
    var runs = 0;
    await enlargeViewport(tester);
    await tester.pumpWidget(harness(onExport: () => runs++));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pdfExportButton')));
    await tester.pumpAndSettle();

    expect(
      find.text('Database is empty — nothing to export.'),
      findsWidgets,
      reason: 'the card shows the guard inside AND in the SnackBar',
    );
    expect(runs, 0, reason: 'no document for empty data');
  });
}
