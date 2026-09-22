// The shared about/onboarding content page: ONE content source, shown
// full-page on the first start ([AboutPage.onboarding]) and from the
// settings pane's about entry afterwards. Carries the fertility-tracking
// warning (Mode-M posture: the app supports, it never decides), the
// license/copyright section, the privacy notice, the backup hint, and the
// feedback note.
//
// Flutter's showAboutDialog is deliberately NOT used: it hard-wires the
// license-chapter surface and can host neither the German-first warning
// content nor the first-start "continue" affordance.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../providers.dart';
import '../version.dart';

/// The displayed app version: the pubspec mirror ([appVersion]) WITHOUT its
/// build suffix — the `+n` part is a build-farm artifact, not user
/// information. lib/version.dart keeps the exact pubspec mirror (its sync
/// test pins the whole string); only the display strips the suffix here.
final String displayedAppVersion = appVersion.split('+').first;

/// The onboarding page's continue action: flips the (hydratable, persisted)
/// onboarding flag; the write-through listener and the [_HomeGate] rebuild
/// take care of the rest — no navigation dance needed.
void completeOnboarding(WidgetRef ref) {
  ref.read(onboardingCompletedProvider.notifier).state = true;
}

/// Tap target of the contact rows: opens the bound URL in the system
/// browser/app. Launch failures are swallowed BY DESIGN: an offline device
/// or a missing handler must never crash the about page — every target is
/// also visible as row text, so the pointer stays usable either way.
Future<void> _openContactUrl(String url) async {
  try {
    await launchUrl(Uri.parse(url));
  } catch (error) {
    // Swallowed on purpose (see the doc comment above).
  }
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
          Text('${l10n.appTitle} · ${l10n.aboutVersion(displayedAppVersion)}',
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
                  // The warning body carries the INER website — SELECTABLE
                  // so the URL stays copyable as plain text (no link
                  // plugin; the app's offline-only posture).
                  SelectableText(l10n.aboutWarningBody,
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
          // The license/copyright section: Apache-2.0 with its copyright
          // holder — the full license text lives in the repository's
          // LICENSE file, so the section points there instead of
          // reproducing it. SELECTABLE: the embedded repository URL is
          // copyable.
          Text(l10n.aboutLicenseHeading, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          SelectableText(l10n.aboutLicenseBody,
              style: theme.textTheme.bodyMedium),
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
          const SizedBox(height: 24),
          // The contact section: TAPPABLE, labeled rows to the INER
          // website and the per-intent pages (courses, consultation, guide/
          // books) plus the app's TECHNICAL contact row (the GitHub issue
          // tracker). Each row binds its target to the per-locale arb
          // string — the English rows never deep-link a German-only page
          // (the EN arb binds the general site instead; info parity keeps
          // all rows in both locales) — with ONE deliberate exception: the
          // issue-tracker URL is an app fact, not an INER fact, so it is
          // locale-independent. Plain rows with an external-link icon;
          // inline rich-text link spans are deliberately not used. This is
          // a pointers/contact section only — no endorsement wording (the
          // app is not INER-endorsed).
          Text(l10n.aboutContactHeading, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final (String label, String url) in <(String, String)>[
            (l10n.aboutContactWebsite, l10n.aboutContactWebsiteUrl),
            (l10n.aboutContactCourses, l10n.aboutContactCoursesUrl),
            (l10n.aboutContactConsultation, l10n.aboutContactConsultationUrl),
            (l10n.aboutContactBooks, l10n.aboutContactBooksUrl),
            (l10n.aboutContactIssues, l10n.aboutContactIssuesUrl),
          ]) ...[
            Card(
              child: ListTile(
                onTap: () => _openContactUrl(url),
                title: Text(label, style: theme.textTheme.titleSmall),
                // The target URL is also visible as row text: with only a
                // plain Text the copy gesture would fight the row's tap
                // gesture, so copyability is not offered here (the tappable
                // row is the primary affordance).
                subtitle: Text(url, style: theme.textTheme.bodySmall),
                trailing: const Icon(Icons.open_in_new),
              ),
            ),
            const SizedBox(height: 4),
          ],
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
          // the GitHub issue tracker (or mail). SELECTABLE: the embedded
          // issue-tracker URL is copyable text.
          SelectableText(l10n.aboutFeedbackNotice,
              style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
