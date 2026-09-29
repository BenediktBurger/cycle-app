import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers.dart';

// --- language ------------------------------------------------
final class LanguageCard extends ConsumerWidget {
  const LanguageCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(localeProvider);
    return Card(
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
              onSelectionChanged: (selection) => ref
                  .read(localeProvider.notifier)
                  .set(
                    selection.first == 'system'
                        ? null
                        : Locale(selection.first),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
