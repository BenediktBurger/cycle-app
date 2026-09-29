import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers.dart';

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

// --- paper history: the cycles outside this app --------------
// The three facts a user observed OUTSIDE this app (cycle count,
// shortest cycle, earliest first higher) are one migration story
// and feed statistics and the PDF export.
final class PaperHistoryCard extends ConsumerWidget {
  const PaperHistoryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Card(
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
              errorKey: const ValueKey('observedCyclesOutsideAppFieldError'),
              errorText: l10n.settingsObservedCyclesOutsideAppError,
              initialValue: ref.watch(observedCyclesOutsideAppProvider),
              labelText: l10n.settingsObservedCyclesOutsideApp,
              onChanged: (value) => ref
                  .read(observedCyclesOutsideAppProvider.notifier)
                  .set(value!),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.settingsObservedCyclesOutsideAppHelper,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            _NonNegativeIntegerField(
              fieldKey: const ValueKey('paperShortestCycleLengthField'),
              errorKey: const ValueKey('paperShortestCycleLengthFieldError'),
              errorText: l10n.settingsPaperShortestCycleLengthError,
              initialValue: ref.watch(shortestCycleLengthOutsideAppProvider),
              labelText: l10n.settingsPaperShortestCycleLength,
              minValue: 1,
              allowEmpty: true,
              onChanged: (value) => ref
                  .read(shortestCycleLengthOutsideAppProvider.notifier)
                  .set(value),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.settingsPaperShortestCycleLengthHelper,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            _NonNegativeIntegerField(
              fieldKey: const ValueKey('paperEarliestFirstHigherCycleDayField'),
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
              onChanged: (value) => ref
                  .read(earliestFirstHigherCycleDayOutsideAppProvider.notifier)
                  .set(value),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.settingsPaperEarliestFirstHigherHelper,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
