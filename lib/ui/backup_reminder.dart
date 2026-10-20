import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../providers.dart';
import 'json_export.dart';

/// The backup reminder above the shell's body: a message plus "Export now"
/// (the shared JSON export flow) and "Later" (a seven-day snooze).
final class BackupReminderBanner extends StatelessWidget {
  const BackupReminderBanner({
    super.key,
    required this.onExportNow,
    required this.onLater,
  });

  final VoidCallback onExportNow;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final foreground = scheme.onTertiaryContainer;
    return Material(
      key: const ValueKey('backupReminderBanner'),
      color: scheme.tertiaryContainer,
      child: SafeArea(
        top: true,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.backup_outlined, size: 20, color: foreground),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.backupReminderMessage,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: foreground),
                    ),
                  ),
                ],
              ),
              OverflowBar(
                alignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    key: const ValueKey('backupReminderLater'),
                    onPressed: onLater,
                    child: Text(l10n.backupReminderLater),
                  ),
                  FilledButton(
                    key: const ValueKey('backupReminderExportNow'),
                    onPressed: onExportNow,
                    child: Text(l10n.backupReminderExportNow),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows the banner only while the due predicate says so; loading and
/// non-due states render nothing, leaving the shell layout untouched.
final class BackupReminderBannerHost extends ConsumerWidget {
  const BackupReminderBannerHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(backupReminderDueProvider)) return const SizedBox.shrink();
    return BackupReminderBanner(
      onExportNow: () => openJsonExport(context, ref),
      onLater: () {
        final now = ref.read(nowProvider)();
        ref
            .read(backupReminderSnoozedUntilProvider.notifier)
            .set(now.toUtc().add(const Duration(days: 7)));
      },
    );
  }
}
