// Einstellungen screen: language switcher (System/de/en), theme-mode
// switcher (System/light/dark), the PIN-lock stub (non-functional in M1 by
// design, ADR-0005), and JSON export/import.
//
// Export UX (no new dependencies, see lib/ui/file_transfer.dart): an
// always-available JSON text screen with a copy button on every platform,
// plus a file save/download where the platform supports it (web, desktop
// with a home directory). Import: paste-JSON dialog everywhere, plus a file
// picker on web. The drip CSV import (below the JSON card) reuses the same
// dialog shape: the mapper turns the CSV into an export document that goes
// through the existing importJsonToDatabase (merge policy for free).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/export_adapter.dart';
import '../domain/drip_import.dart';
import '../domain/export_import.dart';
import '../l10n/app_localizations.dart';
import '../providers.dart';
import 'file_transfer.dart';

/// Export file name used by the save/download path.
const String exportFileName = 'cycle_app_export.json';

class EinstellungenScreen extends ConsumerWidget {
  const EinstellungenScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(localeProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navSettings)),
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
                  Text(l10n.settingsLanguage,
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  // The provider stores null for "System"; the segment
                  // model uses a string key ('system'/'de'/'en') so all
                  // three states fit one SegmentedButton (ADR-0007).
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: 'system',
                        label: Text(l10n.languageSystem),
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
                    onSelectionChanged: (selection) => ref
                        .read(localeProvider.notifier)
                        .state = selection.first == 'system'
                        ? null
                        : Locale(selection.first),
                  ),
                  const SizedBox(height: 8),
                  // In-memory ONLY: reset to the system default after a web
                  // reload by design for this milestone (documented on
                  // localeProvider + docs/roadmap.md).
                  Text(l10n.settingsLanguageNote,
                      style: Theme.of(context).textTheme.bodySmall),
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
                  Text(l10n.settingsThemeMode,
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  // System follows the device brightness (the MaterialApp
                  // default); the explicit choices win over the platform.
                  // The "System" label is shared with the language switcher
                  // — same word, same meaning ("follow the device").
                  SegmentedButton<ThemeMode>(
                    segments: [
                      ButtonSegment(
                        value: ThemeMode.system,
                        label: Text(l10n.languageSystem),
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
                    onSelectionChanged: (selection) => ref
                        .read(themeModeProvider.notifier)
                        .state = selection.first,
                  ),
                  const SizedBox(height: 8),
                  // In-memory ONLY: resets to the system default after a
                  // web reload by design (documented on themeModeProvider +
                  // docs/roadmap.md; mirrors the language switcher).
                  Text(l10n.settingsThemeModeNote,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // --- PIN lock stub -------------------------------------------
          // Disabled ON PURPOSE: flipping it on would falsely signal that a
          // protection exists. The lock story (native SQLCipher later, web
          // PIN limitations) is set out in ADR-0005.
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
                  Text(l10n.settingsPinLockNote,
                      style: Theme.of(context).textTheme.bodySmall),
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
                  Text(l10n.settingsExport,
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(l10n.settingsExportNote,
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: () => _openExport(context, ref),
                    icon: const Icon(Icons.download_outlined),
                    label: Text(l10n.settingsExport),
                  ),
                  const SizedBox(height: 16),
                  Text(l10n.settingsImport,
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(l10n.settingsImportNote,
                      style: Theme.of(context).textTheme.bodySmall),
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
                  Text(l10n.dripImportTitle,
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(l10n.dripImportNote,
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: () => _openDripImportDialog(context, ref),
                    icon: const Icon(Icons.upload_outlined),
                    label: Text(l10n.dripImportButton),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openExport(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final db = await ref.read(databaseProvider.future);
    final json = await exportDatabaseToJson(db);
    // An export without any content is not useful as a file; communicate
    // instead of producing an empty document in the user's Downloads.
    final doc = parseExportJson(json);
    if (doc.profiles.isEmpty && doc.entries.isEmpty && doc.marks.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.exportNothing)));
      return;
    }
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _ExportPreviewPage(json: json),
      ),
    );
  }

  Future<void> _openImportDialog(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    // The Apply action must react to BOTH the pasted text and the running
    // import, so the dialog listens to controller + pending flag together
    // (a one-time build here would freeze the button — there is no widget
    // rebuild of the actions while the user types).
    final running = ValueNotifier<bool>(false);
    final listenable = Listenable.merge([controller, running]);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.importTitle),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (canPickFile) ...[
                  OutlinedButton.icon(
                    onPressed: () async {
                      final text = await pickFileText();
                      if (text != null) {
                        controller.text = text;
                      }
                    },
                    icon: const Icon(Icons.file_open_outlined),
                    label: Text(l10n.importPickFile),
                  ),
                  const SizedBox(height: 8),
                ],
                TextField(
                  controller: controller,
                  maxLines: 10,
                  decoration: InputDecoration(hintText: l10n.importHint),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                MaterialLocalizations.of(dialogContext).cancelButtonLabel,
              ),
            ),
            ListenableBuilder(
              listenable: listenable,
              builder: (context, _) {
                final busy = running.value;
                final hasText = controller.text.trim().isNotEmpty;
                return FilledButton(
                  onPressed: !hasText || busy
                      ? null
                      : () async {
                          final raw = controller.text;
                          running.value = true;
                          try {
                            await _applyImport(
                                dialogContext, context, ref, raw);
                          } finally {
                            running.value = false;
                          }
                        },
                  child: Text(l10n.importApply),
                );
              },
            ),
          ],
        );
      },
    );
    controller.dispose();
    running.dispose();
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
      Navigator.of(dialogContext).pop();
      if (!screenContext.mounted) return;
      ScaffoldMessenger.of(screenContext).showSnackBar(
        SnackBar(
          content: Text(
            summary.entriesWritten == 0 && summary.marksNew == 0
                ? l10n.importEmpty
                : l10n.importSummary(
                    summary.profilesToInsert,
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
      ScaffoldMessenger.of(dialogContext).showSnackBar(
        SnackBar(content: Text(l10n.importInvalid)),
      );
    } catch (_) {
      // The transaction rolled back (import is all-or-nothing): the stored
      // data is unchanged, so tell the user exactly that instead of
      // crashing (ImportFailedException and anything below it).
      if (!dialogContext.mounted) return;
      ScaffoldMessenger.of(dialogContext).showSnackBar(
        SnackBar(content: Text(l10n.importFailed)),
      );
    }
  }

  /// Drip CSV import dialog: same shape as [_openImportDialog] — a paste
  /// textarea everywhere, a file picker on web (accepting CSV), and a
  /// shared controller + busy-flag listener so Apply tracks both.
  Future<void> _openDripImportDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    final running = ValueNotifier<bool>(false);
    final listenable = Listenable.merge([controller, running]);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.dripImportTitle),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (canPickFile) ...[
                  OutlinedButton.icon(
                    onPressed: () async {
                      final text =
                          await pickFileText(accept: '.csv,text/csv');
                      if (text != null) {
                        controller.text = text;
                      }
                    },
                    icon: const Icon(Icons.file_open_outlined),
                    label: Text(l10n.importPickFile),
                  ),
                  const SizedBox(height: 8),
                ],
                TextField(
                  controller: controller,
                  maxLines: 10,
                  decoration: InputDecoration(hintText: l10n.dripImportHint),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                MaterialLocalizations.of(dialogContext).cancelButtonLabel,
              ),
            ),
            ListenableBuilder(
              listenable: listenable,
              builder: (context, _) {
                final busy = running.value;
                final hasText = controller.text.trim().isNotEmpty;
                return FilledButton(
                  onPressed: !hasText || busy
                      ? null
                      : () async {
                          final raw = controller.text;
                          running.value = true;
                          try {
                            await _applyDripImport(
                                dialogContext, context, ref, raw);
                          } finally {
                            running.value = false;
                          }
                        },
                  child: Text(l10n.dripImportApply),
                );
              },
            ),
          ],
        );
      },
    );
    controller.dispose();
    running.dispose();
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
      Navigator.of(dialogContext).pop();
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
      ScaffoldMessenger.of(dialogContext).showSnackBar(
        SnackBar(content: Text(l10n.dripImportInvalid)),
      );
    } catch (_) {
      // The transaction rolled back (import is all-or-nothing): the stored
      // data is unchanged, so tell the user exactly that instead of
      // crashing (ImportFailedException and anything below it).
      if (!dialogContext.mounted) return;
      ScaffoldMessenger.of(dialogContext).showSnackBar(
        SnackBar(content: Text(l10n.importFailed)),
      );
    }
  }
}

/// Full-screen JSON preview: the export text with a copy button for every
/// platform, and a file save/download where the platform supports it.
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
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.exportCopied)),
                    );
                  },
                  icon: const Icon(Icons.copy_outlined),
                  label: Text(l10n.exportCopy),
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
                else
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
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontFamily: 'monospace'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
