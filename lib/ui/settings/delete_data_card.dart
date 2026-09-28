import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers.dart';

// --- delete data (danger) -------------------------------------
// One transactional wipe of every diary entry and mark (settings
// and onboarding flag survive); cancel is the DEFAULT action.
final class DeleteDataCard extends ConsumerWidget {
  const DeleteDataCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Card(
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
}
