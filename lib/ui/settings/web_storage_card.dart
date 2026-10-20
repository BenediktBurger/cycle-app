import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../db/settings_store.dart' show formatIsoDate;
import '../../l10n/app_localizations.dart';
import '../../platform/web_storage_status.dart';
import '../../providers.dart';

/// The Settings pane's browser-storage report: every fact arrives through
/// [status], so the widget renders on the VM without browser APIs.
final class WebStorageCard extends StatelessWidget {
  const WebStorageCard({
    super.key,
    required this.status,
    required this.onMakePersistent,
    this.lastExportAt,
  });

  final WebStorageStatus status;

  /// Null means no export has been recorded yet.
  final DateTime? lastExportAt;

  /// The explicit persistence request; true means the browser granted it.
  final Future<bool> Function() onMakePersistent;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final canRequestPersistence = status.persistent == false;
    return Card(
      key: const ValueKey('webStorageCard'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.webStorageCard,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.webStorageInstalled(
                status.installedPwa ? l10n.webStorageYes : l10n.webStorageNo,
              ),
            ),
            Text(
              l10n.webStoragePersistent(switch (status.persistent) {
                true => l10n.webStorageYes,
                false => l10n.webStorageNo,
                null => l10n.webStorageUnknown,
              }),
            ),
            Text(
              l10n.webStorageBackend(
                _backendLabel(l10n, status.backendLabelKey),
              ),
            ),
            Text(_usageLine(l10n, status)),
            Text(
              l10n.webStorageLastExport(
                lastExportAt == null
                    ? l10n.webStorageNever
                    : formatIsoDate(lastExportAt!.toLocal()),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  key: const ValueKey('webStorageMakePersistentButton'),
                  onPressed: canRequestPersistence
                      ? () => _makePersistent(context)
                      : null,
                  icon: const Icon(Icons.lock_outline),
                  label: Text(l10n.webStorageMakePersistent),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('webStorageCopyDiagnosticsButton'),
                  onPressed: () => _copyDiagnostics(context),
                  icon: const Icon(Icons.copy_outlined),
                  label: Text(l10n.webStorageCopyDiagnostics),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _makePersistent(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final granted = await onMakePersistent();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          granted
              ? l10n.webStoragePersistGranted
              : l10n.webStoragePersistDenied,
        ),
      ),
    );
  }

  Future<void> _copyDiagnostics(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: status.buildDiagnosticsText()));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.webStorageDiagnosticsCopied)));
  }
}

/// The Settings pane's live storage report, absent until the database opened
/// on web (null off the web and while the report loads).
final class WebStorageCardHost extends ConsumerWidget {
  const WebStorageCardHost({super.key, this.lastExportAt});

  /// The export timestamp seam; null means no export recorded yet.
  final DateTime? lastExportAt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(webStorageReportProvider).value;
    if (status == null) return const SizedBox.shrink();
    return WebStorageCard(
      status: status,
      lastExportAt: lastExportAt,
      onMakePersistent: () => persistWebStorage(ref),
    );
  }
}

String _backendLabel(AppLocalizations l10n, String key) => switch (key) {
  'webStorageBackendOpfs' => l10n.webStorageBackendOpfs,
  'webStorageBackendSharedIndexedDb' => l10n.webStorageBackendSharedIndexedDb,
  'webStorageBackendUnsafeIndexedDb' => l10n.webStorageBackendUnsafeIndexedDb,
  'webStorageBackendInMemory' => l10n.webStorageBackendInMemory,
  _ => l10n.webStorageBackendUnknown,
};

String _usageLine(AppLocalizations l10n, WebStorageStatus status) {
  final used = status.usageBytes == null
      ? l10n.webStorageUnknown
      : _formatBytes(status.usageBytes!, l10n.localeName);
  final quota = status.quotaBytes;
  return quota == null
      ? l10n.webStorageUsageNoQuota(used)
      : l10n.webStorageUsage(used, _formatBytes(quota, l10n.localeName));
}

String _formatBytes(int bytes, String locale) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = unit == 0 || value >= 100 ? 0 : 1;
  final format = NumberFormat.decimalPattern(locale)
    ..minimumFractionDigits = 0
    ..maximumFractionDigits = digits;
  return '${format.format(value)} ${units[unit]}';
}
