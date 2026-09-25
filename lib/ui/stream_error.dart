// The shared inline retry surface for a failed live-stream watch
// (entries/marks): one look for every screen so the error treatments cannot
// drift. Styled after the startup database error screen (lib/main.dart)
// but leaner — an in-body surface next to real content, not a takeover.
//
// The keys stay stream-scoped: a screen can show both streams' surfaces in
// different slots (the diary), and the tests address each surface per
// stream, never per screen.
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// The retry surface of one failed stream: the load-failed text plus the
/// refresh button wired to [onRetry] (the caller invalidates the failed
/// provider). [scope] names the stream (`entries` / `marks`) and scopes the
/// widget's stable test keys: `ValueKey('${scope}StreamLoadError')` on the
/// surface, `ValueKey('${scope}StreamRetryButton')` on the button. The
/// stream failure of a data screen is a user corrective action, not a stack
/// trace to read, so only the corrective surface renders.
final class StreamLoadError extends StatelessWidget {
  const StreamLoadError({
    super.key,
    required this.scope,
    required this.onRetry,
  });

  final String scope;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      key: ValueKey('${scope}StreamLoadError'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(l10n.loadFailed, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              key: ValueKey('${scope}StreamRetryButton'),
              label: Text(l10n.retry),
            ),
          ],
        ),
      ),
    );
  }
}
