import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// The heading row of one diary entry-form section: the section title and —
/// only when an info text exists — a trailing button opening a scrollable
/// guidance bottom sheet (section title + info text).
class SectionHeader extends StatelessWidget {
  const SectionHeader({required this.title, this.info, super.key});

  final String title;
  final String? info;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        ),
        if (info != null)
          IconButton(
            // The explicit 48 dp minimum keeps the tap target at the
            // accessibility floor whatever the theme's visual density.
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            key: ValueKey('diarySectionInfo-$title'),
            icon: const Icon(Icons.info_outline),
            tooltip: l10n.sectionInfoTooltip(title),
            onPressed: () => _showInfo(context),
          ),
      ],
    );
  }

  void _showInfo(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleMedium;
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: titleStyle),
              const SizedBox(height: 8),
              Text(info!, style: Theme.of(sheetContext).textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}
