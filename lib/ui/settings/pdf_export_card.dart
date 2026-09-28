import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../db/settings_store.dart';
import '../../domain/date_only.dart';
import '../../domain/marks.dart';
import '../../domain/models.dart';
import '../../domain/pdf_export_model.dart';
import '../../l10n/app_localizations.dart';
import '../../pdf/cycle_pdf.dart'
    show pdfExportFileName, pdfFontAsset, PdfExportOptions;
import '../../providers.dart';
import '../file_transfer.dart';

// --- PDF export action card ----------------------------------
// One-run pipeline: export model (selection intersected by
// cycle-start identity) -> document builder provider -> hand-off
// via saveFileBytes or shareFileBytes.

/// The PDF-export action card: a summary line plus a "select cycles"
/// button that opens the full-screen [_CycleSelectionPage], the per-export
/// anonymize toggle and the save/share hand-off row.
///
/// SELECTION FLOW: the selection lives in THIS card's state. The page is
/// seeded from the card's current selection, edits its own copy while
/// open, and on CONFIRM pops the final selection back; any other exit
/// leaves the card's state untouched. Null means "all exportable cycles"
/// (the default), an explicit set the chosen subset.
///
/// The selection and the anonymize flag are card-local state (per-run
/// view choices, never persisted): a new app start exports everything
/// again unless re-chosen, and flipping anonymize must never rewrite the
/// stored identifying values.
final class PdfExportCard extends ConsumerStatefulWidget {
  const PdfExportCard({super.key});

  @override
  ConsumerState<PdfExportCard> createState() => _PdfExportCardState();
}

final class _PdfExportCardState extends ConsumerState<PdfExportCard> {
  /// The selected cycles' normalized (DateOnly) start dates — the export's
  /// cycle identity, or null while nothing was chosen differently (null =
  /// "all exportable cycles"). Written back from the selection page on
  /// confirm; card-local like the anonymize toggle.
  Set<DateTime>? _selection;
  var _anonymized = false;
  var _running = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // A still-loading stream reads as "no data" (the card then only
    // explains why there would be nothing to export).
    final entries =
        ref.watch(dailyEntriesProvider).value ?? const <DailyEntry>[];
    final marks = ref.watch(marksProvider).value ?? const <CycleMark>[];
    final outside = ref.watch(observedCyclesOutsideAppProvider);
    final choices = exportableCycles(
      entries,
      marks,
      observedCyclesOutsideApp: outside,
      today: ref.read(nowProvider)(),
    );
    final selectedCount = _selection == null
        ? choices.length
        : _shownSelection(choices).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.settingsPdfExport,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            if (choices.isEmpty)
              Text(
                l10n.exportNothing,
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              Text(
                l10n.pdfExportCyclesSelectedSummary(
                  selectedCount,
                  choices.length,
                ),
                key: const ValueKey('pdfExportSelectedSummary'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            // Selecting cycles lives on a full-screen page, opened here.
            FilledButton.tonalIcon(
              key: const ValueKey('pdfExportSelectCyclesButton'),
              onPressed: choices.isEmpty
                  ? null
                  : () => _openCycleSelection(context, choices),
              icon: const Icon(Icons.checklist),
              label: Text(l10n.pdfExportSelectCycles),
            ),
            SwitchListTile.adaptive(
              key: const ValueKey('pdfExportAnonymizeSwitch'),
              value: _anonymized,
              onChanged: (value) => setState(() => _anonymized = value),
              title: Text(l10n.pdfExportAnonymize),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.pdfExportAnonymizeNote,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            // ONE generation run serves both hand-offs: the document goes
            // through the save-as dialog or the system share sheet (web
            // has no share sheet — its browser download stays the
            // hand-off).
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const ValueKey('pdfExportButton'),
                  onPressed: _running
                      ? null
                      : () => _runExport(context, share: false),
                  icon: const Icon(Icons.save_outlined),
                  label: Text(l10n.pdfExportSaveButton),
                ),
                if (canShareFile)
                  FilledButton.tonalIcon(
                    key: const ValueKey('pdfExportShareButton'),
                    onPressed: _running
                        ? null
                        : () => _runExport(context, share: true),
                    icon: const Icon(Icons.share_outlined),
                    label: Text(l10n.exportShare),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The current selected set seen through the LIVE choices: null means
  /// "everything", otherwise the explicit set intersected with the live
  /// choices' normalized start dates — a stale member drops out, so the
  /// summary, the seeded page and the model builder agree.
  Set<DateTime> _shownSelection(
    List<({int ordinal, DateTime startDate})> choices,
  ) {
    if (_selection == null) {
      return {
        for (final choice in choices) DateOnly.normalize(choice.startDate),
      };
    }
    return {
      for (final member in _selection!)
        if (choices.any(
          (choice) => DateOnly.normalize(choice.startDate) == member,
        ))
          member,
    };
  }

  /// Opens the full-screen cycle-selection page seeded with the card's
  /// current choice (null = all kept AS the all state). Outcome:
  /// `(confirmed: true, selected: …)` — `selected` null for the Alle
  /// state; any other exit pops no record and the card state stays
  /// untouched ("confirm applies, back cancels").
  Future<void> _openCycleSelection(
    BuildContext context,
    List<({int ordinal, DateTime startDate})> choices,
  ) async {
    final outcome = await Navigator.of(context)
        .push<({bool confirmed, Set<DateTime>? selected})>(
          MaterialPageRoute(
            builder: (_) => _CycleSelectionPage(
              choices: choices,
              startAll: _selection == null,
              startSelected: _shownSelection(choices),
            ),
          ),
        );
    if (outcome == null || !outcome.confirmed) return;
    if (!mounted) return;
    setState(() => _selection = outcome.selected);
  }

  /// The export pipeline for one run: build the model from the LIVE data,
  /// generate via the builder provider, then hand the bytes to the pressed
  /// hand-off ([share] chooses the system share sheet over the save-as
  /// dialog); each hand-off reports its own verb's snackbars.
  Future<void> _runExport(BuildContext context, {required bool share}) async {
    final l10n = AppLocalizations.of(context);
    final successMessage = share ? l10n.exportShared : l10n.exportSaved;
    final failureMessage = share
        ? l10n.exportShareFailed
        : l10n.exportSaveFailed;
    final entries =
        ref.read(dailyEntriesProvider).value ?? const <DailyEntry>[];
    final marks = ref.read(marksProvider).value ?? const <CycleMark>[];
    final outside = ref.read(observedCyclesOutsideAppProvider);
    final choices = exportableCycles(
      entries,
      marks,
      observedCyclesOutsideApp: outside,
      today: ref.read(nowProvider)(),
    );
    if (choices.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.exportNothing)));
      return;
    }
    // The chosen selection (null = the default, everything):
    final selected = _selection == null ? null : _shownSelection(choices);

    final model = buildPdfExportModel(
      entries: entries,
      marks: marks,
      observedCyclesOutsideApp: outside,
      // The paper-history constants: the paper figures were known facts
      // at the FIRST in-app cycle, so they fold into every exported
      // cycle's header stats.
      shortestCycleLengthOutsideApp: ref.read(
        shortestCycleLengthOutsideAppProvider,
      ),
      earliestFirstHigherCycleDayOutsideApp: ref.read(
        earliestFirstHigherCycleDayOutsideAppProvider,
      ),
      name: ref.read(pdfExportNameProvider),
      birthDate: ref.read(pdfExportBirthDateProvider),
      selectedStartDates: selected,
      // The settings range is the PDF curve block's fixed y scale.
      temperatureRange: ref.read(temperatureRangeProvider),
      today: ref.read(nowProvider)(),
    );
    if (model.cycles.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.exportNothing)));
      return;
    }

    setState(() => _running = true);
    try {
      final now = DateTime.now();
      final fontData = await rootBundle.load(pdfFontAsset);
      final builder = ref.read(pdfDocumentBuilderProvider);
      final bytes = await builder(
        model,
        PdfExportOptions(anonymized: _anonymized, exportDate: now),
        fontData.buffer.asUint8List(
          fontData.offsetInBytes,
          fontData.lengthInBytes,
        ),
      );
      final filename = pdfExportFileName(now);
      final ok = await (share
          ? shareFileBytes(filename, bytes)
          : saveFileBytes(filename, bytes));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? successMessage : failureMessage)),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failureMessage)));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }
}

/// Full-screen cycle-selection page for the PDF export — the surface the
/// card's "Zyklen auswählen…" button pushes.
///
/// Controls pinned at the top (Alle/Keine bulk buttons, confirm button,
/// live count), rows sorted MOST-RECENT-FIRST in a lazy
/// [ListView.builder]. Row keys stay stable (`pdfExportCycleCheckboxRow$i`)
/// but the index counts the VISIBLE order, so `Row0` is the newest cycle.
/// State is a page-local editing copy seeded by the card's caller;
/// Confirm is the only way toggling leaves the page.
final class _CycleSelectionPage extends StatefulWidget {
  const _CycleSelectionPage({
    required this.choices,
    required this.startAll,
    required this.startSelected,
  });

  /// The exportable cycles in observation order (oldest→newest, shared
  /// output of [exportableCycles]); the display reverses it.
  final List<({int ordinal, DateTime startDate})> choices;

  /// Whether the card's current choice is the null "all" state.
  final bool startAll;

  /// The card's materialized selected set (when [startAll] is false).
  final Set<DateTime> startSelected;

  @override
  State<_CycleSelectionPage> createState() => _CycleSelectionPageState();
}

final class _CycleSelectionPageState extends State<_CycleSelectionPage> {
  /// The page-local copy of the selection (null = "every cycle"), seeded
  /// in [State.initState] from the pushed-in card state.
  Set<DateTime>? _selection;

  /// The display rows, most-recent-first (built once — the choices are a
  /// pushed-in snapshot, not a stream).
  late final List<({int ordinal, DateTime startDate})> _rows = widget
      .choices
      .reversed
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _selection = widget.startAll ? null : {...widget.startSelected};
  }

  bool _isShownSelected(int displayIndex) =>
      // null = all → every row checked; otherwise membership by the row's
      // normalized start date (the shared DateOnly identity).
      _selection?.contains(DateOnly.normalize(_rows[displayIndex].startDate)) ??
      true;

  /// The materialized all-selected state (what a row toggle's FIRST press
  /// converts the implicit null into, before flipping the row).
  Set<DateTime> _allStarts() => {
    for (final choice in widget.choices) DateOnly.normalize(choice.startDate),
  };

  /// Toggles display row [i].
  void _toggle(int displayIndex, bool checked) {
    final current = _selection ?? _allStarts();
    final start = DateOnly.normalize(_rows[displayIndex].startDate);
    setState(() {
      final next = {...current};
      if (checked) {
        next.add(start);
      } else {
        next.remove(start);
      }
      _selection = next;
    });
  }

  void _confirm() =>
      Navigator.of(context).pop((confirmed: true, selected: _selection));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final shownCount = _selection == null
        ? _rows.length
        : _rows
              .where(
                (row) =>
                    _selection!.contains(DateOnly.normalize(row.startDate)),
              )
              .length;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.pdfExportSelectionTitle)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The PINNED control head, visible without scrolling.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton(
                  key: const ValueKey('pdfExportCycleSelectAll'),
                  onPressed: () => setState(() => _selection = null),
                  child: Text(l10n.pdfExportCyclesAll),
                ),
                TextButton(
                  key: const ValueKey('pdfExportCycleSelectNone'),
                  onPressed: () => setState(() => _selection = const {}),
                  child: Text(l10n.pdfExportCyclesNone),
                ),
                Text(
                  l10n.pdfExportCyclesSelectedSummary(shownCount, _rows.length),
                  key: const ValueKey('pdfExportSelectionSummary'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                FilledButton.icon(
                  key: const ValueKey('pdfExportSelectionConfirmButton'),
                  onPressed: _confirm,
                  icon: const Icon(Icons.check),
                  label: Text(l10n.pdfExportSelectionConfirm),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: _rows.length,
              itemBuilder: (context, index) => CheckboxListTile(
                key: ValueKey('pdfExportCycleCheckboxRow$index'),
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                value: _isShownSelected(index),
                title: Text(
                  l10n.pdfExportCycleOption(
                    _rows[index].ordinal,
                    formatIsoDate(_rows[index].startDate),
                  ),
                ),
                onChanged: (checked) => _toggle(index, checked ?? false),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
