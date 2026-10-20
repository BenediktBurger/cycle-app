import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../platform/web_storage_status.dart';
import '../providers.dart';

/// The web-only storage warnings above the shell's body: the in-memory
/// test-mode dialog and banner, the unsafe-IndexedDB multi-tab banner, and the
/// dismissible iOS install hint.
final class WebStorageWarnings extends ConsumerStatefulWidget {
  const WebStorageWarnings({super.key, required this.status});

  /// Null (native, or before the report is ready) renders nothing.
  final WebStorageStatus? status;

  @override
  ConsumerState<WebStorageWarnings> createState() => _WebStorageWarningsState();
}

class _WebStorageWarningsState extends ConsumerState<WebStorageWarnings> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _showInMemoryDialogIfNeeded(),
    );
  }

  @override
  void didUpdateWidget(WebStorageWarnings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _showInMemoryDialogIfNeeded(),
      );
    }
  }

  /// Schedules the one-time dialog after the frame that first sees the
  /// in-memory status; the shown flag is set before showing so a rebuild
  /// cannot open a second copy.
  void _showInMemoryDialogIfNeeded() {
    if (!mounted || widget.status?.isInMemory != true) return;
    if (ref.read(inMemoryWarningShownProvider)) return;
    ref.read(inMemoryWarningShownProvider.notifier).set(true);
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext);
        return AlertDialog(
          key: const ValueKey('inMemoryWarningDialog'),
          title: Text(l10n.webStorageInMemoryDialogTitle),
          content: Text(l10n.webStorageInMemoryDialogBody),
          actions: [
            FilledButton(
              key: const ValueKey('inMemoryWarningDismiss'),
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.webStorageInMemoryDismiss),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    if (status == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final installHintDismissed = ref.watch(installHintDismissedProvider);
    final banners = <Widget>[
      if (status.isInMemory)
        _WarningBanner(
          key: const ValueKey('inMemoryWarningBanner'),
          icon: Icons.memory,
          text: l10n.webStorageInMemoryBanner,
          background: scheme.errorContainer,
          foreground: scheme.onErrorContainer,
        ),
      if (status.needsMultiTabWarning)
        _WarningBanner(
          key: const ValueKey('unsafeIndexedDbBanner'),
          icon: Icons.tab,
          text: l10n.webStorageMultiTabBanner,
          background: scheme.errorContainer,
          foreground: scheme.onErrorContainer,
        ),
      if (status.showInstallHint && !installHintDismissed)
        _WarningBanner(
          key: const ValueKey('installHintBanner'),
          icon: Icons.add_to_home_screen,
          text: l10n.webStorageInstallHint,
          background: scheme.secondaryContainer,
          foreground: scheme.onSecondaryContainer,
          dismissKey: const ValueKey('installHintDismiss'),
          dismissTooltip: l10n.webStorageInstallHintDismiss,
          onDismiss: () =>
              ref.read(installHintDismissedProvider.notifier).set(true),
        ),
    ];

    if (banners.isEmpty) return const SizedBox.shrink();
    return Column(mainAxisSize: MainAxisSize.min, children: banners);
  }
}

/// The live warnings for the current browser storage report; nothing off the
/// web and while the report is loading.
final class WebStorageWarningsHost extends ConsumerWidget {
  const WebStorageWarningsHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(webStorageReportProvider).value;
    if (status == null) return const SizedBox.shrink();
    return WebStorageWarnings(status: status);
  }
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({
    super.key,
    required this.icon,
    required this.text,
    required this.background,
    required this.foreground,
    this.onDismiss,
    this.dismissKey,
    this.dismissTooltip,
  });

  final IconData icon;
  final String text;
  final Color background;
  final Color foreground;
  final VoidCallback? onDismiss;
  final Key? dismissKey;
  final String? dismissTooltip;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      child: SafeArea(
        top: true,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(icon, size: 20, color: foreground),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: foreground),
                ),
              ),
              if (onDismiss != null)
                IconButton(
                  key: dismissKey,
                  icon: const Icon(Icons.close),
                  color: foreground,
                  tooltip: dismissTooltip,
                  onPressed: onDismiss,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
