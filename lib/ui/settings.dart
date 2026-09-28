// Einstellungen screen: language and theme-mode switchers, the
// temperature range, paper history, the PIN-lock stub (ADR-0005), JSON
// export/import, PDF export and the drip CSV import.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/export_adapter.dart';
import '../db/settings_store.dart';
import '../domain/date_only.dart';
import '../domain/decimal_display.dart';
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

/// The integer field of the settings pane's integer cards: free-text entry
/// validated per keystroke against "whole number >= [minValue]" — a valid
/// entry writes through to the provider immediately, an invalid one shows
/// the keyed error line and leaves the stored value untouched.
///
/// [initialValue] null renders an empty field; only [allowEmpty] fields
/// (the optional paper-history values) accept an empty entry as the cleared
/// state, writing through null. Deliberately a manual validation instead of
/// a digits-only input formatter: the formatter would swallow characters
/// silently while the visible rejection states the rule. The field follows
/// its [initialValue] until the user types.
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

  /// The validation rejection line (localized at the call site).
  final String errorText;
  final String labelText;

  /// The provider's current value; null renders the empty field.
  final int? initialValue;

  /// The smallest acceptable entry (0 for the count, 1 for the paper
  /// history values).
  final int minValue;

  /// Whether an empty entry is the valid "cleared" state (writes null).
  final bool allowEmpty;

  /// Fires for a VALID entry per keystroke; rejected entries fire nothing.
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
/// integer field above: uncontrolled text field (hydration happens behind
/// the database gate before any screen is reachable), keystroke validation,
/// valid entries write through via [onChanged].
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
  /// current text.
  final String? errorText;
  final Key? errorKey;

  /// The empty-content hint (e.g. the ISO date shape).
  final String? hintText;

  /// Returns true when the entry is acceptable; null = everything is.
  final bool Function(String raw)? validator;

  /// Fires for a VALID entry per keystroke; rejected entries fire nothing.
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

/// The selectable half-degree steps of the temperature-range pickers, across
/// the allowed 34.0..42.0 °C window. Built from integer half-steps (k / 2)
/// so no float drift creeps into the 0.5 step grid.
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
      appBar: AppBar(
        title: Text(l10n.navSettings),
        actions: [
          // The about page plays the SAME content the first-start
          // onboarding shows (lib/ui/about.dart) — one content source,
          // opened on demand.
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
          // User data (name, birth date), optional; the entries serve the
          // PDF export.
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
                    // A strict parse shared with the settings store's
                    // decode: correct shape AND a real calendar day.
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
          // The three facts a user observed OUTSIDE this app (cycle count,
          // shortest cycle, earliest first higher) are one migration story
          // and feed statistics and the PDF export.
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
                    labelText: l10n.settingsObservedCyclesOutsideApp,
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
                    // A cycle-day number counts from 1.
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
                  // model uses a string key so all three states fit one
                  // SegmentedButton (ADR-0007).
                  SegmentedButton<String>(
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
                  // The explicit choices win over the platform; both
                  // switchers share the `termSystem` label.
                  SegmentedButton<ThemeMode>(
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
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // --- temperature range ---------------------------------------
          // The chart's y range: two half-degree pickers; min < max is
          // enforced BY CONSTRUCTION — each picker only offers the values
          // strictly on its side of the other bound (no error states).
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
                                      '${formatDecimal(step, locale: Localizations.localeOf(context).toString(), decimalDigits: 1)} °C',
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
                                      '${formatDecimal(step, locale: Localizations.localeOf(context).toString(), decimalDigits: 1)} °C',
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
          // lock exists (at-rest encryption is already always-on on
          // native, ADR-005; the user-facing lock story is open).
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
          // One-run pipeline: export model (selection intersected by
          // cycle-start identity) -> document builder provider -> hand-off
          // via saveFileBytes or shareFileBytes.
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
          // One transactional wipe of every diary entry and mark (settings
          // and onboarding flag survive); cancel is the DEFAULT action.
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

  /// The delete-data flow: opens the confirmation dialog, then — only on
  /// an explicit confirm — runs the transactional wipe. The dialog's
  /// counts are a pre-read; the actual counts come from the wipe itself.
  /// Any failure (open, pre-reads, wipe) surfaces the localized failure
  /// message on the screen context instead of leaking an async error.
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
              // The DEFAULT action: focus lands here, Enter cancels.
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
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.deleteDataFailed)));
    }
  }

  Future<void> _openExport(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    try {
      final db = await ref.read(databaseProvider.future);
      final json = await exportDatabaseToJson(db);
      // An empty export is not useful as a file — communicate instead.
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
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.exportFailed)));
    }
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
        accept: 'application/json,.json',
        apply: (applyContext, raw) =>
            _applyImport(applyContext, context, ref, raw),
      ),
    );
  }

  /// Closes the import dialog after a successful import — only while it is
  /// STILL the route on top. `mounted` alone cannot guard the follow-up
  /// pop (the dialog's elements stay connected until the route is
  /// finalized), and the pop would then fire on whatever route is now on
  /// top — collapsing the whole route stack.
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
      // The DOCUMENT is invalid — nothing was written; the dialog stays
      // open for correcting the text.
      if (!dialogContext.mounted) return;
      ScaffoldMessenger.of(
        dialogContext,
      ).showSnackBar(SnackBar(content: Text(l10n.importInvalid)));
    } catch (_) {
      // The transaction rolled back — the stored data is unchanged.
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
      // Parse first: a non-drip file fails here before anything is written.
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
      // The transaction rolled back — the stored data is unchanged.
      if (!dialogContext.mounted) return;
      ScaffoldMessenger.of(
        dialogContext,
      ).showSnackBar(SnackBar(content: Text(l10n.importFailed)));
    }
  }
}

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

/// Self-contained import dialog used by both the JSON and the drip CSV
/// import: a paste textarea everywhere plus a file picker where the
/// platform provides one ([canPickFile], accept list from the caller).
///
/// Owns all dialog state in its State (text controller, busy flag), so a
/// scrim dismissal while an import is running can never touch disposed
/// state afterwards. The content is small-screen safe: scrollable dialog,
/// textarea height capped at a fraction of the viewport.
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

  /// Runs the import with the dialog's own context: pops the dialog on
  /// success and reports problems itself.
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
    // Rebuild on every text change so the Apply button follows both the
    // text and the busy flag.
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
      // A scrim dismissal during the import disposes this State — the
      // reset must stay a silent no-op in that case.
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
            // Height-capped expanding textarea: on small viewports
            // (keyboard up) the field shrinks to the available space.
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
          // Cancel stays enabled while running — a scrim tap is equally
          // possible, so gating only this button would be a pretense.
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
