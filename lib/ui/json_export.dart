// The one JSON export flow shared by Settings and the backup banner.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/export_adapter.dart';
import '../domain/export_import.dart';
import '../l10n/app_localizations.dart';
import '../providers.dart';
import 'export_preview_page.dart';
import 'file_transfer.dart';

/// Export file name used by every JSON hand-off (save, share, web download).
const String exportFileName = 'cycle_app_export.json';

/// Builds the JSON export, rejects a row-free document with the existing
/// snackbar, and opens the shared [ExportPreviewPage].
Future<void> openJsonExport(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  try {
    final db = await ref.read(databaseProvider.future);
    final json = await exportDatabaseToJson(db);
    // An empty export is not useful as a file — communicate instead.
    final doc = parseExportJson(json);
    if (doc.entries.isEmpty && doc.marks.isEmpty && doc.methods.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.exportNothing)));
      return;
    }
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ExportPreviewPage(json: json),
      ),
    );
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.exportFailed)));
  }
}

/// Hands [json] to the save-as dialog and marks the export only when the
/// dialog reports a completed save.
Future<bool> saveJsonExport(WidgetRef ref, String json) =>
    _handOffJson(ref, json, saveFile);

/// Hands [json] to the system share sheet and marks the export only when the
/// sheet reports a completed share (not a dismissal or an unavailable
/// result).
Future<bool> shareJsonExport(WidgetRef ref, String json) =>
    _handOffJson(ref, json, shareFile);

Future<bool> _handOffJson(
  WidgetRef ref,
  String json,
  Future<bool> Function(String filename, String content) handOff,
) async {
  final notifier = ref.read(lastExportAtProvider.notifier);
  // The reminder compares instants, so capture the clock in UTC before the
  // hand-off can outlive this widget's ref.
  final exportedAt = ref.read(nowProvider)().toUtc();
  final completed = await handOff(exportFileName, json);
  if (completed) notifier.set(exportedAt);
  return completed;
}
