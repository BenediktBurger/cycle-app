// Einstellungen screen: language switcher (System/de/en), theme-mode
// switcher (System/light/dark), the PIN-lock stub (non-functional in M1 by
// design, ADR-0005), and JSON export/import.
//
// Export UX: an always-available JSON text screen with a copy button on
// every platform, a file save-as dialog where the platform supports one
// (a real dialog on all native io targets via the file_picker plugin,
// SAF-backed on Android; browser download on web), and a system share
// sheet alongside on the native targets (share_plus). Import:
// paste-JSON dialog
// everywhere, plus a file picker on web and on the native targets (the
// file_picker plugin, SAF-backed on Android). The drip CSV import (below
// the JSON card) reuses the same dialog widget: the mapper turns the CSV
// into an export document that goes through the existing
// importJsonToDatabase (merge policy for free).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/export_adapter.dart';
import '../db/settings_store.dart';
import '../domain/drip_import.dart';
import '../domain/export_import.dart';
import '../domain/marks.dart';
import '../domain/models.dart';
import '../domain/pdf_export_model.dart';
import '../domain/temperature_range.dart';
import '../l10n/app_localizations.dart';
import '../pdf/cycle_pdf.dart'
    show pdfExportFileName, pdfFontAsset, PdfExportOptions;
import '../providers.dart';
import 'about.dart';
import 'file_transfer.dart';

/// Export file name used by the save/download path.
const String exportFileName = 'cycle_app_export.json';

/// The integer field of the "cycles observed outside this app" settings
/// card: free-text entry validated per keystroke against "whole number
/// >= 0" — a valid entry writes through to
/// [observedCyclesOutsideAppProvider] immediately (the same write-through
/// wiring the switcher cards use), an invalid one shows the keyed error
/// line and leaves the stored value untouched.
///
/// Manual validation instead of a digits-only input formatter on purpose:
/// the formatter would silently swallow characters while the visible
/// rejection states the rule. The field follows its [initialValue] until
/// the user types: an external change to the initial value resyncs the
/// controller while the field is untouched, afterwards the visible text
/// belongs to the user and is not clobbered from outside mid-entry.
final class _NonNegativeIntegerField extends StatefulWidget {
  const _NonNegativeIntegerField({
    required this.initialValue,
    required this.labelText,
    required this.onChanged,
  });

  final int initialValue;
  final String labelText;
  final ValueChanged<int> onChanged;

  @override
  State<_NonNegativeIntegerField> createState() =>
      _NonNegativeIntegerFieldState();
}

final class _NonNegativeIntegerFieldState
    extends State<_NonNegativeIntegerField> {
  late final TextEditingController _controller;
  bool _userEdited = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.initialValue}');
  }

  @override
  void didUpdateWidget(_NonNegativeIntegerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != oldWidget.initialValue && !_userEdited) {
      _controller.text = '${widget.initialValue}';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String raw) {
    _userEdited = true;
    final value = int.tryParse(raw.trim());
    final valid = value != null && value >= 0;
    setState(() {});
    if (valid) widget.onChanged(value);
  }

  bool get _invalid {
    final value = int.tryParse(_controller.text.trim());
    return value == null || value < 0;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: const ValueKey('observedCyclesOutsideAppField'),
          controller: _controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: widget.labelText,
            border: const OutlineInputBorder(),
          ),
          onChanged: _onChanged,
        ),
        if (_invalid)
          Text(
            // The rejection line, visible for every invalid intermediate
            // state (empty text included): the validation, not a formatter.
            l10n.settingsObservedCyclesOutsideAppError,
            key: const ValueKey('observedCyclesOutsideAppFieldError'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
      ],
    );
  }
}

/// The settings pane's plain text/date fields, same wiring shape as the
/// outside-app integer field below: an UNCONTROLLED text field (controller
/// initialized once, never re-synced from the provider on rebuilds —
/// hydration lands before any screen is reachable behind the database
/// gate), free-text entry validated per keystroke — a VALID entry writes
/// through immediately via [onChanged], an invalid one only shows the
/// keyed error line and leaves the stored value untouched. The PDF-export
/// name and birth-date fields share this shape.
final class _ValidatedSettingsField extends StatefulWidget {
  const _ValidatedSettingsField({
    required this.fieldKey,
    required this.initialValue,
    required this.labelText,
    this.errorText,
    this.errorKey,
    this.hintText,
    this.validator,
    this.onChanged,
  });

  final Key fieldKey;
  final String initialValue;
  final String labelText;

  /// The validation rejection line, shown while [validator] rejects the
  /// current text (the text stays local; nothing writes).
  final String? errorText;
  final Key? errorKey;

  /// The empty-content hint (e.g. the ISO date shape).
  final String? hintText;

  /// Returns true when the entry is acceptable; null = everything is.
  final bool Function(String raw)? validator;

  /// Fires for a VALID entry per keystroke (same write-through cadence as
  /// the outside-app integer field); rejected entries fire nothing.
  final ValueChanged<String>? onChanged;

  @override
  State<_ValidatedSettingsField> createState() =>
      _ValidatedSettingsFieldState();
}

final class _ValidatedSettingsFieldState
    extends State<_ValidatedSettingsField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _valid(String raw) => widget.validator == null || widget.validator!(raw);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: widget.fieldKey,
          controller: _controller,
          keyboardType: TextInputType.text,
          decoration: InputDecoration(
            labelText: widget.labelText,
            hintText: widget.hintText,
            border: const OutlineInputBorder(),
          ),
          onChanged: (raw) {
            // The rejection line, visible for every invalid intermediate
            // state — the validation, not a formatter.
            setState(() {});
            if (_valid(raw)) widget.onChanged?.call(raw);
          },
        ),
        if (widget.validator != null && !_valid(_controller.text))
          Text(
            widget.errorText ?? '',
            key: widget.errorKey,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
      ],
    );
  }
}

/// The selectable half-degree steps of the temperature-range pickers,
/// across the allowed 34.0..42.0 °C window (the temperature chart's y
/// bounds in °C). Built from integer half-steps (k / 2) so no float drift
/// creeps into the 0.5 step grid; the °C unit is the seam a later
/// Fahrenheit conversion would hook into (see the settings card comment).
final List<double> temperatureRangeSteps = List.unmodifiable(<double>[
  for (
    var k = (TemperatureRange.windowLower / 0.5).round(),
        upper = (TemperatureRange.windowUpper / 0.5).round();
    k <= upper;
    k++
  )
    k * 0.5,
]);

class EinstellungenScreen extends ConsumerWidget {
  const EinstellungenScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(localeProvider);

    return Scaffold(
      // The about entry lives in the app bar (like the cycle tab's glossary
      // info action) instead of a buried card, so it is reachable without
      // scrolling. It plays the SAME content page the first-start
      // onboarding shows (lib/ui/about.dart) — one content source, opened
      // here on demand; no setting is touched by opening it.
      appBar: AppBar(
        title: Text(l10n.navSettings),
        actions: [
          IconButton(
            key: const ValueKey('aboutAction'),
            icon: const Icon(Icons.info_outline),
            tooltip: l10n.aboutShow,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (context) => const AboutPage()),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // --- language ------------------------------------------------
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.settingsLanguage,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  // The provider stores null for "System"; the segment
                  // model uses a string key ('system'/'de'/'en') so all
                  // three states fit one SegmentedButton (ADR-0007).
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: 'system',
                        label: Text(l10n.termSystem),
                      ),
                      ButtonSegment(
                        value: 'de',
                        label: Text(l10n.languageGerman),
                      ),
                      ButtonSegment(
                        value: 'en',
                        label: Text(l10n.languageEnglish),
                      ),
                    ],
                    selected: {locale == null ? 'system' : locale.languageCode},
                    onSelectionChanged: (selection) =>
                        ref
                            .read(localeProvider.notifier)
                            .state = selection.first == 'system'
                        ? null
                        : Locale(selection.first),
                  ),
                  // Persisted: the choice applies immediately and is
                  // written through to the local drift database
                  // (app_settings) — restored on the next app start
                  // (hydration/write-through in main.CycleApp; see
                  // localeProvider). No action needed by the user, so the
                  // pane does not repeat it as a note.
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // --- theme mode ----------------------------------------------
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.settingsThemeMode,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  // System follows the device brightness (the MaterialApp
                  // default); the explicit choices win over the platform
                  // (its own switcher uses the shared `termSystem` label —
                  // one vocabulary across both switchers).
                  SegmentedButton<ThemeMode>(
                    segments: [
                      ButtonSegment(
                        value: ThemeMode.system,
                        label: Text(l10n.termSystem),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        label: Text(l10n.themeLight),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        label: Text(l10n.themeDark),
                      ),
                    ],
                    selected: {ref.watch(themeModeProvider)},
                    onSelectionChanged: (selection) =>
                        ref.read(themeModeProvider.notifier).state =
                            selection.first,
                  ),
                  // Persisted, mirroring the language switcher: the choice
                  // is written through to the local drift database
                  // (app_settings) and restored on the next app start
                  // (themeModeProvider). Its note is gone with the language
                  // card's: persistence is expected, the pane spares it.
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // --- temperature range ---------------------------------------
          // The cycle chart's y range ("Temperaturbereich"): two
          // half-degree pickers inside the allowed 34.0..42.0 °C window;
          // min < max is enforced BY CONSTRUCTION — each picker only
          // offers the values strictly on its side of the other bound (no
          // error states, the chart never sees an invalid range).
          // Persisted, mirroring the language/theme switcher: the range
          // is written through to the local drift database
          // (app_settings) and restored on the next app start
          // (temperatureRangeProvider). The 0.5 °C step unit is the seam a
          // later Fahrenheit conversion would hook into (out of scope; the
          // range math stays in °C domain units).
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.settingsTemperatureRange,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Builder(
                    builder: (context) {
                      final range = ref.watch(temperatureRangeProvider);
                      return Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<double>(
                              key: const ValueKey('temperatureRangeMin'),
                              initialValue: range.min,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: l10n.settingsRangeLower,
                                border: const OutlineInputBorder(),
                              ),
                              items: [
                                for (final step in temperatureRangeSteps.where(
                                  (step) => step < range.max,
                                ))
                                  DropdownMenuItem(
                                    value: step,
                                    child: Text(
                                      '${step.toStringAsFixed(1)} °C',
                                    ),
                                  ),
                              ],
                              onChanged: (value) {
                                if (value == null) return;
                                ref
                                    .read(temperatureRangeProvider.notifier)
                                    .state = TemperatureRange(
                                  min: value,
                                  max: range.max,
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<double>(
                              key: const ValueKey('temperatureRangeMax'),
                              initialValue: range.max,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: l10n.settingsRangeUpper,
                                border: const OutlineInputBorder(),
                              ),
                              items: [
                                for (final step in temperatureRangeSteps.where(
                                  (step) => step > range.min,
                                ))
                                  DropdownMenuItem(
                                    value: step,
                                    child: Text(
                                      '${step.toStringAsFixed(1)} °C',
                                    ),
                                  ),
                              ],
                              onChanged: (value) {
                                if (value == null) return;
                                ref
                                    .read(temperatureRangeProvider.notifier)
                                    .state = TemperatureRange(
                                  min: range.min,
                                  max: value,
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  // Persisted: the range is written through to the local
                  // drift database (app_settings) and restored on the next
                  // app start (temperatureRangeProvider). The short note
                  // below carries only the DEFAULT measurement (the
                  // half of the old note that actually informs the user
                  // — the persistence sentence is gone everywhere else).
                  Text(
                    l10n.settingsTemperatureRangeDefaultHint,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // --- cycles observed outside this app ------------------------
          // The groundwork the cycle page's "Zyklus N" ordinals count up
          // from: a user who tracked on paper (or in another tracker)
          // before entering her data here sets the number of those
          // foregoing cycles, and the cycle page's numbering — the chart's
          // boundary labels and the evaluation table's column headers
          // alike — starts after this count instead of at 1. Free-text
          // integer entry with keystroke validation (>= 0), write-through
          // like every card on this pane; the helper note explains what
          // the number moves.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.settingsObservedCyclesOutsideApp,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  _NonNegativeIntegerField(
                    initialValue: ref.watch(observedCyclesOutsideAppProvider),
                    // A plain label: the field names the count with the
                    // card title's wording.
                    labelText: l10n.settingsObservedCyclesOutsideApp,
                    onChanged: (value) =>
                        ref
                                .read(observedCyclesOutsideAppProvider.notifier)
                                .state =
                            value,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.settingsObservedCyclesOutsideAppHelper,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // --- PDF export: identifying values --------------------------
          // The "identifying source" values the generated PDF's paper-form
          // header carries: name and birth date (the birth date field is a
          // strict ISO date with validation — impossible days never
          // pass). Each export's "Anonymisieren" toggle decides PER EXPORT
          // whether the document shows these values or hides them (the
          // per-export toggle is intentionally NOT persisted — see the
          // export card below). The helper cross-references the
          // outside-app cycle count, which feeds the PDF's observed-cycle
          // header fact.
          Card(
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
                  _ValidatedSettingsField(
                    fieldKey: const ValueKey('pdfExportNameField'),
                    initialValue: ref.watch(pdfExportNameProvider) ?? '',
                    labelText: l10n.settingsPdfExportName,
                    onChanged: (raw) {
                      final trimmed = raw.trim();
                      ref.read(pdfExportNameProvider.notifier).state =
                          trimmed.isEmpty ? null : trimmed;
                    },
                  ),
                  const SizedBox(height: 8),
                  _ValidatedSettingsField(
                    fieldKey: const ValueKey('pdfExportBirthDateField'),
                    initialValue: ref.watch(pdfExportBirthDateProvider) == null
                        ? ''
                        : formatIsoDate(ref.watch(pdfExportBirthDateProvider)!),
                    labelText: l10n.settingsPdfExportBirthDate,
                    hintText: l10n.settingsPdfExportBirthDateFormat,
                    errorText: l10n.settingsPdfExportBirthDateError,
                    errorKey: const ValueKey('pdfExportBirthDateFieldError'),
                    // One strict parse shared with the settings store's
                    // decode (tryParseIsoDate): correct shape AND a real
                    // calendar day.
                    validator: (raw) => raw.isEmpty
                        ? true
                        : tryParseIsoDate(raw.trim()) != null,
                    onChanged: (raw) {
                      final parsed = raw.trim().isEmpty
                          ? null
                          : tryParseIsoDate(raw.trim());
                      if (parsed != null || raw.trim().isEmpty) {
                        ref.read(pdfExportBirthDateProvider.notifier).state =
                            parsed;
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.settingsPdfExportNote,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // --- PIN lock stub -------------------------------------------
          // Disabled ON PURPOSE: flipping it on would falsely signal that a
          // lock exists. At-rest encryption of the database is already
          // always-on on native (ADR-005, SQLite3MultipleCiphers + key in
          // secure storage); what remains open is the user-facing lock
          // story (PIN/biometric on native, PIN limitations on web).
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile.adaptive(
                    value: false,
                    onChanged: null,
                    title: Text(l10n.settingsPinLock),
                  ),
                  Text(
                    l10n.settingsPinLockNote,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // --- JSON export / import ------------------------------------
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.settingsExport,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.settingsExportNote,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: () => _openExport(context, ref),
                    icon: const Icon(Icons.download_outlined),
                    label: Text(l10n.settingsExport),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.settingsImport,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.settingsImportNote,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: () => _openImportDialog(context, ref),
                    icon: const Icon(Icons.upload_outlined),
                    label: Text(l10n.settingsImport),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // --- PDF export action card ----------------------------------
          // Generates the paper-form PDF from the tracked data "up to the
          // exported one": a cycle selector (defaults to the LATEST
          // mark-opened cycle), the per-export anonymize toggle (card-local
          // state, never persisted) and the Export action. The pipeline:
          // export model -> document builder provider (stubbed in tests)
          // -> saveFileBytes seam, reported through the same SnackBar
          // pattern as the JSON export card above.
          const PdfExportCard(),
          const SizedBox(height: 8),
          // --- privacy / GDPR notice -----------------------------------
          // The same string the about/onboarding page shows (one source,
          // lib/ui/about.dart): the app's data-control reality in plain
          // German-first prose — no servers, nothing ever sent, GDPR rights
          // exercisable directly via the export/delete/import actions.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.aboutPrivacyHeading,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.aboutPrivacyBody,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // --- drip CSV import ------------------------------------------
          // Drip (sibling project) exports calendar days as a CSV; the
          // mapper produces a normal export document, so the merge policy,
          // transaction and summary counting are the existing import ones.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.dripImportTitle,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.dripImportNote,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: () => _openDripImportDialog(context, ref),
                    icon: const Icon(Icons.upload_outlined),
                    label: Text(l10n.termCsvImport),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // --- delete data (danger) -------------------------------------
          // The tracked-data reset: every diary entry and every mark, in
          // one transactional wipe (settings + onboarding flag survive).
          // Danger-tinted everywhere, an explicit confirm with cancel as
          // the DEFAULT action, and an export-first recommendation — a
          // wipe without the export earlier is irrecoverable.
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.settingsDeleteData,
                    style: Theme.of(context).textTheme.titleSmall!.copyWith(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.settingsDeleteDataNote,
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    key: const ValueKey('settingsDeleteDataButton'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                      foregroundColor: Theme.of(context).colorScheme.onError,
                    ),
                    onPressed: () => _confirmDeleteData(context, ref),
                    icon: const Icon(Icons.delete_forever_outlined),
                    label: Text(l10n.settingsDeleteDataButton),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // --- feedback note -------------------------------------------
          // The pane's compact closing line (the about page carries the
          // same stance as its footer): the app does not send anything,
          // so errors/suggestions go to the GitHub issue tracker or mail.
          Text(
            l10n.settingsFeedbackNotice,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  /// The delete-data flow: opens the confirmation dialog (counts of what
  /// will go, cancel as the DEFAULT action), then — only on an explicit
  /// confirm — runs the transactional wipe and reports the removed counts.
  /// The dialog's counts are a pre-read; the actual counts come from the
  /// wipe itself (a write racing between the two is possible in theory).
  ///
  /// The WHOLE flow is guarded: opening the database, the dialog's
  /// pre-count reads, and the wipe itself can all fail, and any of them
  /// must surface the localized failure message instead of leaking an
  /// unhandled async error (the wipe is one all-or-nothing transaction, so
  /// a failure leaves the stored data untouched — say exactly that, like
  /// the import flows do).
  Future<void> _confirmDeleteData(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    try {
      final db = await ref.read(databaseProvider.future);
      final entries = await db.entriesDao.allEntries();
      final marks = await db.marksDao.allMarks();
      if (!context.mounted) return;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.deleteDataDialogTitle),
          content: Text(
            l10n.deleteDataDialogBody(entries.length, marks.length),
          ),
          actions: [
            TextButton(
              // The DEFAULT action: focus lands here, Enter cancels. The
              // risky path always needs an explicit extra tap on the button
              // that names the consequence ("Löschen").
              key: const ValueKey('deleteDataCancel'),
              autofocus: true,
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                MaterialLocalizations.of(dialogContext).cancelButtonLabel,
              ),
            ),
            FilledButton(
              key: const ValueKey('deleteDataConfirm'),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
                foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.deleteDataConfirm),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      final counts = await db.deleteAllTrackedData();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.deleteDataDone(counts.entries, counts.marks)),
        ),
      );
    } catch (_) {
      // Failure anywhere in the flow — even a pre-read before the wipe —
      // changes nothing (the wipe is all-or-nothing and, if it failed, was
      // never committed): report that instead of crashing, on the screen
      // context (the dialog is user-dismissable and may already be gone).
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.deleteDataFailed)));
    }
  }

  Future<void> _openExport(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final db = await ref.read(databaseProvider.future);
    final json = await exportDatabaseToJson(db);
    // An export without any content is not useful as a file; communicate
    // instead of producing an empty document in the user's Downloads.
    final doc = parseExportJson(json);
    if (doc.entries.isEmpty && doc.marks.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.exportNothing)));
      return;
    }
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _ExportPreviewPage(json: json),
      ),
    );
  }

  /// Opens the self-contained JSON import dialog (see [_ImportDialog]).
  Future<void> _openImportDialog(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => _ImportDialog(
        title: l10n.importTitle,
        hint: l10n.importHint,
        applyLabel: l10n.importApply,
        // Same accept list as the web implementation: exported JSON.
        accept: 'application/json,.json',
        apply: (applyContext, raw) =>
            _applyImport(applyContext, context, ref, raw),
      ),
    );
  }

  /// Closes the import dialog after a successful import — only while it is
  /// STILL the route on top. The actual race: the cancel button or a scrim
  /// tap pops the dialog route WHILE the import future is still in flight,
  /// before the success-path pop runs. `mounted` alone cannot guard the
  /// follow-up pop (the dialog's elements stay connected until the route is
  /// finalized, so the context's ancestor walk reaches the root navigator)
  /// and the pop would then fire on whatever route is now on top — the
  /// home — collapsing the whole route stack.
  void _popImportDialogWhileCurrent(BuildContext dialogContext) {
    final route = ModalRoute.of(dialogContext);
    if (route != null && route.isCurrent) {
      Navigator.of(dialogContext).pop();
    }
  }

  Future<void> _applyImport(
    BuildContext dialogContext,
    BuildContext screenContext,
    WidgetRef ref,
    String raw,
  ) async {
    final l10n = AppLocalizations.of(dialogContext);
    try {
      final db = await ref.read(databaseProvider.future);
      final summary = await importJsonToDatabase(db, raw);
      if (!dialogContext.mounted) return;
      _popImportDialogWhileCurrent(dialogContext);
      if (!screenContext.mounted) return;
      ScaffoldMessenger.of(screenContext).showSnackBar(
        SnackBar(
          content: Text(
            summary.entriesWritten == 0 && summary.marksNew == 0
                ? l10n.importEmpty
                : l10n.importSummary(
                    summary.entriesNew,
                    summary.entriesOverwritten,
                    summary.duplicateEntryRows,
                    summary.entriesInvalid,
                    summary.marksNew,
                    summary.marksSkipped,
                  ),
          ),
        ),
      );
    } on FormatException {
      // The DOCUMENT is invalid (not JSON, wrong schema) — nothing was
      // written; the import dialog stays open for correcting the text.
      if (!dialogContext.mounted) return;
      ScaffoldMessenger.of(
        dialogContext,
      ).showSnackBar(SnackBar(content: Text(l10n.importInvalid)));
    } catch (_) {
      // The transaction rolled back (import is all-or-nothing): the stored
      // data is unchanged, so tell the user exactly that instead of
      // crashing (ImportFailedException and anything below it).
      if (!dialogContext.mounted) return;
      ScaffoldMessenger.of(
        dialogContext,
      ).showSnackBar(SnackBar(content: Text(l10n.importFailed)));
    }
  }

  /// Opens the self-contained drip CSV import dialog — the same widget as
  /// the JSON import, parameterized with the drip title/hint/labels and the
  /// CSV accept list (see [_ImportDialog]).
  Future<void> _openDripImportDialog(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => _ImportDialog(
        title: l10n.dripImportTitle,
        hint: l10n.dripImportHint,
        applyLabel: l10n.termCsvImport,
        // CSV from the sibling project, both the extension and the MIME.
        accept: '.csv,text/csv',
        apply: (applyContext, raw) =>
            _applyDripImport(applyContext, context, ref, raw),
      ),
    );
  }

  /// Maps the pasted CSV into an export document and feeds it through the
  /// EXISTING write path ([importJsonToDatabase]) — merge policy, the
  /// all-or-nothing transaction and idempotence come from there.
  Future<void> _applyDripImport(
    BuildContext dialogContext,
    BuildContext screenContext,
    WidgetRef ref,
    String raw,
  ) async {
    final l10n = AppLocalizations.of(dialogContext);
    try {
      // Parse first: a non-drip file fails here before anything is written
      // (bad header = FormatException = "not a drip CSV" message, dialog
      // stays open for correction).
      final parsed = dripCsvToExportJson(raw);
      final db = await ref.read(databaseProvider.future);
      final summary = await importJsonToDatabase(db, parsed.json);
      if (!dialogContext.mounted) return;
      _popImportDialogWhileCurrent(dialogContext);
      if (!screenContext.mounted) return;
      ScaffoldMessenger.of(screenContext).showSnackBar(
        SnackBar(
          content: Text(
            parsed.stats.rowsImported == 0 &&
                    summary.entriesNew == 0 &&
                    summary.entriesOverwritten == 0
                ? l10n.importEmpty
                : l10n.dripImportSummary(
                    parsed.stats.rowsImported,
                    parsed.stats.rowsSkippedEmpty,
                    parsed.stats.rowsInvalid,
                    summary.entriesNew,
                    summary.entriesOverwritten,
                  ),
          ),
        ),
      );
    } on FormatException {
      // The text is not a drip CSV export (no "date" header column);
      // nothing was written, the dialog stays open.
      if (!dialogContext.mounted) return;
      ScaffoldMessenger.of(
        dialogContext,
      ).showSnackBar(SnackBar(content: Text(l10n.dripImportInvalid)));
    } catch (_) {
      // The transaction rolled back (import is all-or-nothing): the stored
      // data is unchanged, so tell the user exactly that instead of
      // crashing (ImportFailedException and anything below it).
      if (!dialogContext.mounted) return;
      ScaffoldMessenger.of(
        dialogContext,
      ).showSnackBar(SnackBar(content: Text(l10n.importFailed)));
    }
  }
}

/// The PDF-export action card: cycle selector, anonymize toggle, Export
/// button — see the call-site comment in the pane for the pipeline.
///
/// Card-local state (the chosen cycle ordinal and the anonymize flag) is a
/// deliberate choice OVER persisted settings: the selection is a per-run
/// view choice, and the anonymize toggle is per-export by definition
/// (flipping it must never rewrite the stored identifying values — the
/// tests pin that).
final class PdfExportCard extends ConsumerStatefulWidget {
  const PdfExportCard({super.key});

  @override
  ConsumerState<PdfExportCard> createState() => _PdfExportCardState();
}

final class _PdfExportCardState extends ConsumerState<PdfExportCard> {
  int? _selectedOrdinal;
  var _anonymized = false;
  var _running = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // The selector rows come from the live tracked data; a still-loading
    // stream reads as "no data" (the card then only explains why there
    // would be nothing to export).
    final entries =
        ref.watch(dailyEntriesProvider).value ?? const <DailyEntry>[];
    final marks = ref.watch(marksProvider).value ?? const <CycleMark>[];
    final outside = ref.watch(observedCyclesOutsideAppProvider);
    final choices = exportableCycles(
      entries,
      marks,
      observedCyclesOutsideApp: outside,
    );
    // The DEFAULT selection: the latest observed cycle ("up to the
    // exported one"), i.e. the last row — unless the user hand-picked one
    // that still exists.
    final effectiveOrdinal =
        _selectedOrdinal == null ||
            choices.every((c) => c.ordinal != _selectedOrdinal)
        ? (choices.isEmpty ? null : choices.last.ordinal)
        : _selectedOrdinal;

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
              DropdownButtonFormField<int>(
                key: const ValueKey('pdfExportCycleSelect'),
                initialValue: effectiveOrdinal,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.pdfExportCycleUpTo,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final choice in choices)
                    DropdownMenuItem(
                      value: choice.ordinal,
                      child: Text(
                        l10n.pdfExportCycleOption(
                          choice.ordinal,
                          formatIsoDate(choice.startDate),
                        ),
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => _selectedOrdinal = value),
              ),
            SwitchListTile.adaptive(
              key: const ValueKey('pdfExportAnonymizeSwitch'),
              value: _anonymized,
              onChanged: (value) => setState(() => _anonymized = value),
              title: Text(l10n.pdfExportAnonymize),
            ),
            FilledButton.icon(
              key: const ValueKey('pdfExportButton'),
              onPressed: _running ? null : () => _runExport(context),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: Text(l10n.pdfExportExportButton),
            ),
          ],
        ),
      ),
    );
  }

  /// The export pipeline for one run: build the model from the LIVE data
  /// (read fresh — watching streams made the card rebuild mid-run is not a
  /// concern here), generate via the builder provider, then save through
  /// the bytes seam. The empty-data guard mirrors the JSON export's: an
  /// empty document is never generated, the message explains instead.
  Future<void> _runExport(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final entries =
        ref.read(dailyEntriesProvider).value ?? const <DailyEntry>[];
    final marks = ref.read(marksProvider).value ?? const <CycleMark>[];
    final outside = ref.read(observedCyclesOutsideAppProvider);
    final choices = exportableCycles(
      entries,
      marks,
      observedCyclesOutsideApp: outside,
    );
    if (choices.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.exportNothing)));
      return;
    }
    // The just-chosen selection (the dropdown default when untouched):
    final ordinal =
        _selectedOrdinal == null ||
            choices.every((c) => c.ordinal != _selectedOrdinal)
        ? choices.last.ordinal
        : _selectedOrdinal!;
    final chosenStart = choices
        .firstWhere((c) => c.ordinal == ordinal)
        .startDate;

    final model = buildPdfExportModel(
      entries: entries,
      marks: marks,
      observedCyclesOutsideApp: outside,
      name: ref.read(pdfExportNameProvider),
      birthDate: ref.read(pdfExportBirthDateProvider),
      exportStartsUpTo: chosenStart,
      // The settings card's display range is the PDF curve block's fixed
      // y scale — the same echo the chart reads (never rescaled for data).
      temperatureRange: ref.read(temperatureRangeProvider),
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
      final ok = await saveFileBytes(pdfExportFileName(now), bytes);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? l10n.exportSaved : l10n.exportSaveFailed)),
      );
    } catch (_) {
      // Generation problems (e.g. a broken font asset) land on the same
      // failure surface as a failed save — nothing was written either way.
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.exportSaveFailed)));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }
}

/// Self-contained import dialog used by both the JSON and the drip CSV
/// import: a paste textarea everywhere plus a file picker where the
/// platform provides one ([canPickFile], accept list from the caller).
///
/// Owns all dialog state in its State (the text controller and the busy
/// flag): everything is disposed together with the widget tree, so a scrim
/// dismissal while an import is still running can never touch disposed
/// state afterwards — the busy-flag reset in the running future simply
/// becomes a no-op once [State.mounted] is gone. The content is
/// small-screen safe: the whole dialog is scrollable and the textarea's
/// height is capped at a fraction of the viewport, so it can never exceed
/// the screen with or without keyboard insets.
final class _ImportDialog extends StatefulWidget {
  const _ImportDialog({
    required this.title,
    required this.hint,
    required this.applyLabel,
    required this.accept,
    required this.apply,
  });

  final String title;
  final String hint;
  final String applyLabel;

  /// HTML-style accept list forwarded to the file picker (ignored on
  /// paste-only platforms).
  final String accept;

  /// Runs the import for the current textarea content with the dialog's own
  /// context: pops the dialog on success and reports problems itself (the
  /// dialog only manages the busy flag around it).
  final Future<void> Function(BuildContext dialogContext, String raw) apply;

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

final class _ImportDialogState extends State<_ImportDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _running = false;

  @override
  void initState() {
    super.initState();
    // The Apply action must react to BOTH the pasted text and the running
    // import — the stateful rebuild covers both (a one-time build here
    // would freeze the button while the user types).
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() => setState(() {});

  @override
  void dispose() {
    _controller
      ..removeListener(_onTextChanged)
      ..dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final text = await pickFileText(accept: widget.accept);
    if (text != null && mounted) {
      setState(() => _controller.text = text);
    }
  }

  Future<void> _apply() async {
    final raw = _controller.text;
    setState(() => _running = true);
    try {
      await widget.apply(context, raw);
    } finally {
      // A scrim dismissal during the import disposes this State while the
      // future is still running — resetting the flag afterwards must stay a
      // silent no-op in that case (and a build must not be requested).
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final applyEnabled = _controller.text.trim().isNotEmpty && !_running;
    return AlertDialog(
      scrollable: true,
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canPickFile) ...[
              OutlinedButton.icon(
                onPressed: _running ? null : _pickFile,
                icon: const Icon(Icons.file_open_outlined),
                label: Text(AppLocalizations.of(context).importPickFile),
              ),
              const SizedBox(height: 8),
            ],
            // Height-capped expanding textarea: on small viewports (keyboard
            // up) the field shrinks to the available space instead of
            // overflowing — the dialog itself scrolls when still too tall.
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.35,
              ),
              child: TextField(
                controller: _controller,
                minLines: 4,
                maxLines: null,
                decoration: InputDecoration(hintText: widget.hint),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          // Cancel stays enabled even while the import is running: a scrim
          // tap is equally possible, so gating only this button would be a
          // pretense — the busy handling is the dialog State's concern.
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: applyEnabled ? _apply : null,
          child: Text(widget.applyLabel),
        ),
      ],
    );
  }
}

/// Full-screen JSON preview: the export text with a copy button for every
/// platform, the system share sheet where [canShareFile] provides one,
/// and a file save/download where the platform supports it.
final class _ExportPreviewPage extends StatelessWidget {
  const _ExportPreviewPage({required this.json});

  final String json;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.exportTitle)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: json));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(l10n.exportCopied)));
                  },
                  icon: const Icon(Icons.copy_outlined),
                  label: Text(l10n.exportCopy),
                ),
                if (canShareFile)
                  FilledButton.tonalIcon(
                    // Same contract as the save button: the boolean result
                    // becomes a confirm/failure snackbar; the share sheet
                    // being dismissed is a hand-off (true), not a failure.
                    onPressed: () async {
                      final ok = await shareFile(exportFileName, json);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            ok ? l10n.exportShared : l10n.exportShareFailed,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.share_outlined),
                    label: Text(l10n.exportShare),
                  ),
                if (canSaveFile)
                  FilledButton.icon(
                    onPressed: () async {
                      final ok = await saveFile(exportFileName, json);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            ok ? l10n.exportSaved : l10n.exportSaveFailed,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.save_outlined),
                    label: Text(l10n.exportSaveFile),
                  )
                else if (!canShareFile)
                  Text(
                    // Targets with neither save nor share (paste-only
                    // stubs): the copy button above stays the route — the
                    // hint only says so, promising nothing further.
                    l10n.exportNativeHint,
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                json,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
