import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../db/export_adapter.dart';
import '../../db/settings_store.dart' show formatIsoDate;
import '../../domain/backup_reminder.dart';
import '../../domain/export_import.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../json_export.dart';
import 'import_dialog.dart';

// --- JSON export / import ------------------------------------
final class ExportImportCard extends ConsumerWidget {
  const ExportImportCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final lastExportAt = ref.watch(lastExportAtProvider);
    final interval = ref.watch(backupReminderIntervalProvider);
    return Card(
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
            Text(
              l10n.settingsLastExport(
                lastExportAt == null
                    ? l10n.settingsNever
                    : formatIsoDate(lastExportAt.toLocal()),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text(l10n.settingsBackupReminder)),
                DropdownButton<BackupReminderInterval>(
                  key: const ValueKey('backupReminderIntervalDropdown'),
                  value: interval,
                  onChanged: (value) {
                    if (value != null) {
                      ref
                          .read(backupReminderIntervalProvider.notifier)
                          .set(value);
                    }
                  },
                  items: [
                    for (final preset in BackupReminderInterval.values)
                      DropdownMenuItem(
                        value: preset,
                        child: Text(_intervalLabel(l10n, preset)),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              key: const ValueKey('settingsExportButton'),
              onPressed: () => openJsonExport(context, ref),
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
    );
  }

  /// Opens the self-contained JSON import dialog (see [ImportDialog]).
  Future<void> _openImportDialog(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => ImportDialog(
        title: l10n.importTitle,
        hint: l10n.importHint,
        applyLabel: l10n.importApply,
        accept: 'application/json,.json',
        apply: (applyContext, raw) =>
            _applyImport(applyContext, context, ref, raw),
        plan: (raw) async =>
            planDatabaseImport(await ref.read(databaseProvider.future), raw),
      ),
    );
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
      applyImportedCustomCategories(ref, summary);
      if (!dialogContext.mounted) return;
      popDialogRouteWhileCurrent(dialogContext);
      if (!screenContext.mounted) return;
      ScaffoldMessenger.of(
        screenContext,
      ).showSnackBar(SnackBar(content: Text(_summaryMessage(l10n, summary))));
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
}

String _intervalLabel(AppLocalizations l10n, BackupReminderInterval interval) =>
    switch (interval) {
      BackupReminderInterval.off => l10n.settingsBackupReminderOff,
      BackupReminderInterval.monthly => l10n.settingsBackupReminderMonthly,
      BackupReminderInterval.quarterly => l10n.settingsBackupReminderQuarterly,
      BackupReminderInterval.halfYearly =>
        l10n.settingsBackupReminderHalfYearly,
    };

String _summaryMessage(AppLocalizations l10n, ImportSummary summary) {
  if (summary.entriesWritten > 0 ||
      summary.marksNew > 0 ||
      summary.methodsWritten > 0) {
    return l10n.importSummary(
      summary.entriesNew,
      summary.entriesOverwritten,
      summary.duplicateEntryRows,
      summary.entriesInvalid,
      summary.marksNew,
      summary.marksSkipped,
      summary.methodsNew,
      summary.methodsOverwritten,
    );
  }
  if (summary.customCategoriesChanged) {
    return l10n.importCategoriesMerged(summary.customCategoriesAdded);
  }
  return l10n.importEmpty;
}
