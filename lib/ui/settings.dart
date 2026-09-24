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
// importJsonToDatabase (merge policy for free). The PDF export card
// (further below) mirrors the hand-off UX with its own one-run pipeline:
// save into a PDF file and share the generated document next to it.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/export_adapter.dart';
import '../db/settings_store.dart';
import '../domain/date_only.dart';
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

/// The integer field of the settings pane's integer cards (the outside-app
/// cycle count and the paper-history pair: shortest cycle length, earliest
/// first higher's cycle day): free-text entry validated per keystroke
/// against "whole number >= [minValue]" — a valid entry writes through to
/// the field's provider immediately (the same write-through wiring the
/// switcher cards use), an invalid one shows the keyed error line and
/// leaves the stored value untouched.
///
/// [initialValue] null means "no value given": the field renders empty and
/// only [allowEmpty] fields (the optional paper-history values) accept an
/// empty entry as the cleared state, writing through null. The count field
/// (>= 0, always given) keeps its old semantics.
///
/// Manual validation instead of a digits-only input formatter on purpose:
/// the formatter would silently swallow characters while the visible
/// rejection states the rule. The field follows its [initialValue] until
/// the user types: an external change to the initial value resyncs the
/// controller while the field is untouched, afterwards the visible text
/// belongs to the user and is not clobbered from outside mid-entry.
final class _NonNegativeIntegerField extends StatefulWidget {
  const _NonNegativeIntegerField({
    required this.fieldKey,
    required this.errorKey,
    required this.errorText,
    required this.labelText,
    required this.onChanged,
    this.initialValue = 0,
    this.minValue = 0,
    this.allowEmpty = false,
  });

  final Key fieldKey;
  final Key errorKey;

  /// The validation rejection line (localized at the call site, so the
  /// count field and the paper fields can carry their own >= 0 / >= 1
  /// wording).
  final String errorText;
  final String labelText;

  /// The provider's current value; null renders the empty field.
  final int? initialValue;

  /// The smallest acceptable entry (0 for the count, 1 for the paper
  /// history values — a "cycle" plausibly has at least one day).
  final int minValue;

  /// Whether an empty entry is the valid "cleared" state (writes null) —
  /// only the paper-history values are optional, so only they clear.
  final bool allowEmpty;

  /// Fires for a VALID entry per keystroke (empty text → null only when
  /// [allowEmpty]); rejected entries fire nothing.
  final ValueChanged<int?> onChanged;

  @override
  State<_NonNegativeIntegerField> createState() =>
      _NonNegativeIntegerFieldState();
}

final class _NonNegativeIntegerFieldState
    extends State<_NonNegativeIntegerField> {
  late final TextEditingController _controller;

  String _textOf(int? value) => value == null ? '' : '$value';

  bool _userEdited = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _textOf(widget.initialValue));
  }

  @override
  void didUpdateWidget(_NonNegativeIntegerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != oldWidget.initialValue && !_userEdited) {
      _controller.text = _textOf(widget.initialValue);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String raw) {
    _userEdited = true;
    final text = raw.trim();
    if (text.isEmpty) {
      setState(() {});
      if (widget.allowEmpty) widget.onChanged(null);
      return;
    }
    final value = int.tryParse(text);
    final valid = value != null && value >= widget.minValue;
    setState(() {});
    if (valid) widget.onChanged(value);
  }

  bool get _invalid {
    final text = _controller.text.trim();
    if (text.isEmpty) return !widget.allowEmpty;
    final value = int.tryParse(text);
    return value == null || value < widget.minValue;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: widget.fieldKey,
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
            widget.errorText,
            key: widget.errorKey,
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
          // --- general information -------------------------------------
          // Name and birth date moved here from the former PDF-titled
          // identifying card — a pure move: the same settings keys and
          // field wiring, only the card around them changed (the owner's
          // Q&A verdict: these are user data, not "PDF settings"). The
          // caption under the title says the entries are optional and what
          // they are used for; the anonymization note lives at the switch
          // that acts on these values (inside the export card below).
          Card(
            key: const ValueKey('generalInfoCard'),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.settingsGeneralInformation,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.settingsGeneralInformationNote,
                    style: Theme.of(context).textTheme.bodySmall,
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
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // --- paper history: the cycles outside this app --------------
          // The three facts a user observed OUTSIDE this app go together
          // in ONE card because they are the same migration story: the
          // count of foregoing cycles (the cycle page's "Zyklus N"
          // ordinals count up from it), the shortest of those cycles (a
          // length in days) and their earliest first higher measurement
          // (a cycle-day number counting from 1). All three are optional
          // paper-form values that feed statistics and the PDF export;
          // free-text integer entry with keystroke validation, write-
          // through like every card on this pane. Positioned right after
          // the general-information card: both gather user-recorded facts
          // about oneself/history, before the app-behaviour settings.
          Card(
            key: const ValueKey('paperHistoryCard'),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.settingsPaperHistory,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.settingsPaperHistoryHelper,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  _NonNegativeIntegerField(
                    fieldKey: const ValueKey('observedCyclesOutsideAppField'),
                    errorKey: const ValueKey(
                      'observedCyclesOutsideAppFieldError',
                    ),
                    errorText: l10n.settingsObservedCyclesOutsideAppError,
                    initialValue: ref.watch(observedCyclesOutsideAppProvider),
                    // A plain label: the field names the count with the
                    // existing setting wording.
                    labelText: l10n.settingsObservedCyclesOutsideApp,
                    // The count is never optional (allowEmpty stays false),
                    // so a valid entry is always a real int here.
                    onChanged: (value) =>
                        ref
                                .read(observedCyclesOutsideAppProvider.notifier)
                                .state =
                            value!,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.settingsObservedCyclesOutsideAppHelper,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  _NonNegativeIntegerField(
                    fieldKey: const ValueKey('paperShortestCycleLengthField'),
                    errorKey: const ValueKey(
                      'paperShortestCycleLengthFieldError',
                    ),
                    errorText: l10n.settingsPaperShortestCycleLengthError,
                    initialValue: ref.watch(
                      shortestCycleLengthOutsideAppProvider,
                    ),
                    labelText: l10n.settingsPaperShortestCycleLength,
                    // A paper "cycle" plausibly has at least one day, so
                    // the optional value validates >= 1 and empty clears.
                    minValue: 1,
                    allowEmpty: true,
                    onChanged: (value) =>
                        ref
                                .read(
                                  shortestCycleLengthOutsideAppProvider
                                      .notifier,
                                )
                                .state =
                            value,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.settingsPaperShortestCycleLengthHelper,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  _NonNegativeIntegerField(
                    fieldKey: const ValueKey(
                      'paperEarliestFirstHigherCycleDayField',
                    ),
                    errorKey: const ValueKey(
                      'paperEarliestFirstHigherCycleDayFieldError',
                    ),
                    errorText: l10n.settingsPaperEarliestFirstHigherError,
                    initialValue: ref.watch(
                      earliestFirstHigherCycleDayOutsideAppProvider,
                    ),
                    labelText: l10n.settingsPaperEarliestFirstHigher,
                    // A cycle-day number on the paper form counts from 1.
                    minValue: 1,
                    allowEmpty: true,
                    onChanged: (value) =>
                        ref
                                .read(
                                  earliestFirstHigherCycleDayOutsideAppProvider
                                      .notifier,
                                )
                                .state =
                            value,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.settingsPaperEarliestFirstHigherHelper,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
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
                    // Test seam: the switcher wrapper plus one key per
                    // segment so tests can pick a segment by its model
                    // token (system/de/en) instead of its label. The key
                    // rides on the segment's label Text — a ButtonSegment
                    // cannot carry a key, and the segment's rendered change
                    // button enters the tree unkeyed.
                    key: const ValueKey('languageSwitcher'),
                    segments: [
                      ButtonSegment(
                        value: 'system',
                        label: Text(
                          l10n.termSystem,
                          key: const ValueKey('languageSegment-system'),
                        ),
                      ),
                      ButtonSegment(
                        value: 'de',
                        label: Text(
                          l10n.languageGerman,
                          key: const ValueKey('languageSegment-de'),
                        ),
                      ),
                      ButtonSegment(
                        value: 'en',
                        label: Text(
                          l10n.languageEnglish,
                          key: const ValueKey('languageSegment-en'),
                        ),
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
                    // Test seam, mirroring the language switcher above:
                    // wrapper key plus per-segment keys on the label Text
                    // (ButtonSegment cannot carry a key).
                    key: const ValueKey('themeSwitcher'),
                    segments: [
                      ButtonSegment(
                        value: ThemeMode.system,
                        label: Text(
                          l10n.termSystem,
                          key: const ValueKey('themeSegment-system'),
                        ),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        label: Text(
                          l10n.themeLight,
                          key: const ValueKey('themeSegment-light'),
                        ),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        label: Text(
                          l10n.themeDark,
                          key: const ValueKey('themeSegment-dark'),
                        ),
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
                    key: const ValueKey('settingsExportButton'),
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
                    key: const ValueKey('settingsImportJsonButton'),
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
          // Generates the paper-form PDF for chosen exportable cycles: a
          // card with a summary line + a "select cycles" button that opens
          // the full-screen cycle-selection page at click time (the
          // formerly inline checkbox list grew unmanageable with many
          // cycles), the per-export anonymize toggle (card-local state,
          // never persisted) and a save/share action pair. The pipeline:
          // export model (the selection intersected by cycle-start
          // identity) -> document builder provider (stubbed in tests) ->
          // ONE generation run handing off either via saveFileBytes or via
          // shareFileBytes, reported through the same SnackBar pattern as
          // the JSON export card above (each hand-off reports its own
          // verb).
          const PdfExportCard(),
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
                    key: const ValueKey('settingsImportDripButton'),
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

/// The PDF-export action card: a summary line plus a "select cycles"
/// button that opens the full-screen [_CycleSelectionPage] (with the
/// Alle/Keine bulk buttons and per-cycle checkboxes — moved there because
/// the inline list grew unmanageable with many cycles), the anonymize
/// toggle and the Export button — see the call-site comment in the pane
/// for the pipeline.
///
/// SELECTION FLOW: the selection lives in THIS card's state. The page is
/// seeded from the card's current selection, holds its own editing copy
/// while open, and on CONFIRM the final selection is popped back and
/// applied via [State.setState]; any other way out (back button, back
/// gesture, no confirm) leaves the card's state untouched. The
/// `Set<DateOnly>`-materialized null-means-all logic stays exactly as
/// before: null = every exportable cycle (the default, matching the
/// card's former export-all behavior), the explicit set = the chosen
/// subset.
///
/// Card-local state (the cycle selection set and the anonymize flag) is a
/// deliberate choice OVER persisted settings: both are per-run view
/// choices (a new app start exports everything again unless re-chosen),
/// and the anonymize toggle is per-export by definition (flipping it must
/// never rewrite the stored identifying values — the tests pin that). The
/// settings store's `pdfExport.*` keys carry identifying source data; a
/// selection row would naturally extend there, but no existing consumer
/// needs the choice to survive a restart.
final class PdfExportCard extends ConsumerStatefulWidget {
  const PdfExportCard({super.key});

  @override
  ConsumerState<PdfExportCard> createState() => _PdfExportCardState();
}

final class _PdfExportCardState extends ConsumerState<PdfExportCard> {
  /// The selected cycles' normalized (DateOnly) start dates — the export's
  /// cycle identity passed into [buildPdfExportModel] — or null while
  /// NOTHING was chosen differently yet: null = "all exportable cycles" (the
  /// default, matching the card's former export-all behavior). Written
  /// back from the selection page on confirm (see the class doc).
  /// Card-local like the anonymize toggle (a per-run view choice, not a
  /// persisted setting; the settings store's pdfExport.* rows carry
  /// identifying source data, not a selection).
  Set<DateTime>? _selection;
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
      // The grouping's injected clock (see nowProvider — test seam): read
      // fresh (the same NON-reactive convention as every choice call site —
      // the data streams above already drive the rebuild).
      today: ref.read(nowProvider)(),
    );
    // The SELECTION is the export card's cycle choice, shown as the
    // summary line: the set of chosen cycles' start dates (DateOnly
    // identity), or null = "everything" (the pre-interaction default,
    // matching the card's former "up to the latest" all-export behavior
    // and today's users). The member state stays card-local like the
    // anonymize toggle — a per-run view choice, never persisted (see the
    // class doc).
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
            // The cycle choice moved OFF the card: the summary above +
            // this button is all the card shows; the button opens the
            // full-screen selection page AT CLICK TIME (the page's rows
            // are seeded from the card's current selection). Disabled in
            // the "no cycles" state — the guard message above explains.
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
            // The anonymization note sits AT the control it explains, not
            // at the data entry: the values it talks about live in the
            // general-information card above, but what this note adds is
            // what the toggle does — one switch row, one explanation.
            const SizedBox(height: 8),
            Text(
              l10n.pdfExportAnonymizeNote,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            // The hand-off row: ONE generation run serves both actions —
            // the generated document goes either through the save-as
            // dialog or, staged in the temp directory, through the system
            // share sheet (the JSON export page's wrap idiom; web has no
            // share sheet, so its browser download stays the hand-off).
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
  /// choices' normalized start dates — a stale member (a start no longer
  /// among the live choices) drops out, so the summary line and the export
  /// always count selected cycles the data still shows (the model builder
  /// intersects by the same start-day identity; pruning here keeps the
  /// summary, the seeded selection page and the model consistent).
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

  /// Opens the full-screen cycle-selection page (see [_CycleSelectionPage]
  /// for the surface): the page is seeded with the card's current choice
  /// — null = all kept AS the all state (the explicit materialization
  /// happens inside the page only per row) — and edits its own copy until
  /// Confirm pops the page with the final selection.
  ///
  /// Confirmed result: `(confirmed: true, selected: …)` where `selected`
  /// is null for the Alle state (matching [_selection]'s null-means-all
  /// semantics) or the explicit set. Any other exit pops WITHOUT a record
  /// (`null` here) — the card state stays untouched, exactly the
  /// owner-specified "confirm applies, back cancels" flow.
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
    // The settings pane can be gone by the time the page pops (the app
    // navigated away in between) — setState only while this State lives.
    if (!mounted) return;
    setState(() => _selection = outcome.selected);
  }

  /// The export pipeline for one run: build the model from the LIVE data
  /// (read fresh — watching streams made the card rebuild mid-run is not a
  /// concern here), generate via the builder provider, then hand the bytes
  /// to the pressed hand-off ([share] chooses the system share sheet over
  /// the save-as dialog). Both hand-offs consume the SAME generated bytes —
  /// they differ nowhere else, and each reports its OWN verb's snackbars
  /// (a generation failure reports the pressed verb's failure message:
  /// nothing was written or staged either way). The empty-data guard
  /// mirrors the JSON export's: an empty document is never generated, the
  /// message explains instead.
  Future<void> _runExport(BuildContext context, {required bool share}) async {
    final l10n = AppLocalizations.of(context);
    // Each hand-off reports only its own verb — a failed share must not
    // claim a failure to save, a successful one not a saved file.
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
      // The paper-history constants ride along: the paper figures were
      // known facts when the FIRST in-app cycle was printed, so they fold
      // into every exported cycle's header stats (see the builder).
      shortestCycleLengthOutsideApp: ref.read(
        shortestCycleLengthOutsideAppProvider,
      ),
      earliestFirstHigherCycleDayOutsideApp: ref.read(
        earliestFirstHigherCycleDayOutsideAppProvider,
      ),
      name: ref.read(pdfExportNameProvider),
      birthDate: ref.read(pdfExportBirthDateProvider),
      // The cycle selection is the model-level cycle filter (the
      // builder intersects by start-day identity — see its doc); the
      // former "up to the chosen cycle" seam is retired from this UI.
      selectedStartDates: selected,
      // The settings card's display range is the PDF curve block's fixed
      // y scale — the same echo the chart reads (never rescaled for data).
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
      // Generation problems (e.g. a broken font asset) land on the
      // pressed hand-off's failure surface — nothing was written or
      // staged either way.
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
/// card's "Zyklen auswählen…" button pushes (same Scaffold + AppBar
/// scaffolding shape as the JSON export's [_ExportPreviewPage]).
///
/// Requirements (the many-cycles reality, ~400 rows):
///
/// - CONTROLS PINNED AT THE TOP: the Alle/Keine bulk buttons and the
///   confirm button ("Auswahl bestätigen") sit in the non-scrolling head
///   next to a live count summary, together with the MOST-RECENT cycle
///   row visible without scrolling — only scrolling reveals older
///   cycles.
/// - ROWS SORTED MOST-RECENT-FIRST (the newest cycle at the top — the
///   common case is adjusting what is tracked now), rendered by a
///   [ListView.builder] so a long list never builds all tiles eagerly.
///   Row label builder: the same shared wording as before
///   ([AppLocalizations.pdfExportCycleOption]). ROW KEYS: the names stay
///   stable (`pdfExportCycleCheckboxRow$i`) but the index now counts the
///   page's VISIBLE order (newest-first), so `Row0` is the most recent
///   cycle — the former card listed them oldest-first.
/// - STATE: a page-local editing copy, seeded from the card's selection
///   (`null` = the all state, kept as null — nothing materializes until a
///   row toggles or Keine picks the empty set). Confirm pops with
///   `(confirmed: true, selected: the copy)`; the Alle button restores
///   null inside the copy so a confirmed Alle reverts the card to the
///   all state. The copy is applied by the CARD's caller (see the card
///   class doc); Confirm is the only way the toggling leaves the page —
///   the back button/gesture closes without effect.
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

  /// The card's materialized selection (only meaningful when
  /// [startAll] is false).
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
      // null = all → every row shows checked; otherwise row membership
      // against the row's normalized start date (the same DateOnly
      // identity the card and the model builder use).
      _selection?.contains(DateOnly.normalize(_rows[displayIndex].startDate)) ??
      true;

  /// The materialized all-selected state: every choice's normalized
  /// start date — what a row toggle's FIRST press converts the implicit
  /// null (= all) into, before flipping the row.
  Set<DateTime> _allStarts() => {
    for (final choice in widget.choices) DateOnly.normalize(choice.startDate),
  };

  /// Toggles display row [i]: the FIRST toggle materializes the implicit
  /// all-selected state into the explicit set, then flips the row (the
  /// same per-run semantics the card's old inline list had).
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
    // The pinned head's summary: the same shared wording the card shows
    // (counted against the page's own editing copy).
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
          // The PINNED control head: bulk buttons + confirm + a live
          // count, one row above the list — visible (with the newest
          // cycle row below it) without scrolling.
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
          // The lazy list: with ~400 cycles only the visible tiles build.
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
