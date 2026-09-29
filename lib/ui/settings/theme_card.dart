import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers.dart';

// --- theme mode ----------------------------------------------
final class ThemeModeCard extends ConsumerWidget {
  const ThemeModeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Card(
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
                  ref.read(themeModeProvider.notifier).set(selection.first),
            ),
          ],
        ),
      ),
    );
  }
}
