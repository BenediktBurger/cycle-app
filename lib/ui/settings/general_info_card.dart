import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../db/settings_store.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';

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

// --- general information -------------------------------------
// User data (name, birth date), optional; the entries serve the
// PDF export.
final class GeneralInfoCard extends ConsumerWidget {
  const GeneralInfoCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Card(
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
                ref.read(pdfExportNameProvider.notifier).state = trimmed.isEmpty
                    ? null
                    : trimmed;
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
              validator: (raw) =>
                  raw.isEmpty ? true : tryParseIsoDate(raw.trim()) != null,
              onChanged: (raw) {
                final parsed = raw.trim().isEmpty
                    ? null
                    : tryParseIsoDate(raw.trim());
                if (parsed != null || raw.trim().isEmpty) {
                  ref.read(pdfExportBirthDateProvider.notifier).state = parsed;
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
