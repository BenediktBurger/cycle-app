// The shared about/onboarding content page: ONE content source, shown
// full-page on the first start ([AboutPage.onboarding]) and from the
// settings pane's about entry afterwards. Carries the fertility-tracking
// warning (Mode-M posture: the app supports, it never decides), the privacy
// notice, the backup hint, and the feedback note.
//
// Flutter's showAboutDialog is deliberately NOT used: it hard-wires the
// license-chapter surface and can host neither the German-first warning
// content nor the first-start "continue" affordance.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../providers.dart';

/// Human-facing app version. Adapted per release; version-bump discipline
/// stays a release-notes concern (pubspec.yaml carries the same number).
const aboutAppVersion = '0.1.0';

/// The onboarding page's continue action: flips the (hydratable, persisted)
/// onboarding flag; the write-through listener and the [_HomeGate] rebuild
/// take care of the rest — no navigation dance needed.
void completeOnboarding(WidgetRef ref) {
  ref.read(onboardingCompletedProvider.notifier).state = true;
}

class AboutPage extends ConsumerWidget {
  const AboutPage({super.key, this.onboarding = false});

  /// Full-page variant on the first start: AppBar without a back affordance
  /// (the only way forward is "Continue") plus the continue button itself.
  final bool onboarding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.aboutTitle),
        // No way back into the shell before continuing (there IS no shell
        // behind this page on the first start).
        automaticallyImplyLeading: !onboarding,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('${l10n.appTitle} · ${l10n.aboutVersion(aboutAppVersion)}',
              style: theme.textTheme.titleSmall),
          const SizedBox(height: 16),
          // The method warning first: it is the reason this page exists at
          // all. A tinted card sets it apart from the rest of the prose.
          Card(
            color: theme.colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: theme.colorScheme.onSecondaryContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(l10n.aboutWarningTitle,
                            style: theme.textTheme.titleSmall!.copyWith(
                                color: theme.colorScheme.onSecondaryContainer)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(l10n.aboutWarningBody,
                      style: theme.textTheme.bodyMedium!.copyWith(
                          color: theme.colorScheme.onSecondaryContainer)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // The reading of the observations stays with the user/couple —
          // the Mode-M posture, here stated in the same breath as the
          // warning it tempers.
          Text(l10n.aboutPosture, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 24),
          // The privacy/DSGVO notice — the same string the settings pane's
          // "Datenschutz" card shows (shared string source, no drift).
          Text(l10n.aboutPrivacyHeading, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(l10n.aboutPrivacyBody, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          // Backup hint: one sentence pointing to the settings export card's
          // backup role (settingsExportNote) — export/import only, never
          // copying the encrypted device-bound database file.
          Text(l10n.aboutBackupHint, style: theme.textTheme.bodyMedium),
          if (onboarding) ...[
            const SizedBox(height: 24),
            // The one way forward on the first start: confirm the reading
            // and enter the shell. Persisted via the flag's write-through.
            FilledButton(
              key: const ValueKey('aboutContinueButton'),
              onPressed: () => completeOnboarding(ref),
              child: Text(l10n.aboutContinue),
            ),
          ],
          const SizedBox(height: 32),
          // The feedback footer — the last thing on the page: nothing is
          // sent by the app itself, so problems and suggestions belong to
          // the GitHub issue tracker (or mail).
          Text(l10n.aboutFeedbackNotice, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
