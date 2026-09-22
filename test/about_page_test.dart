// The About page as reached from the settings pane ("Einstellungen › Über
// die App"): the shared content page (lib/ui/about.dart) must render its
// full content — the version line (read from the installed binary via
// package_info_plus, mocked by the shared harness), the method warning (with
// the INER website as visible text), the privacy/DSGVO notice, the
// license/copyright section, the tappable INER contact rows, and the
// feedback footer whose URLs are selectable text; popping the page returns
// to the settings pane.
//
// German and English device locales receive one case each; both mirror the
// app's German-first posture and the ADR-0007 English fallback.
//
// The contact rows' URLs are deliberately LOCALE-DEPENDENT (unlike the
// earlier plain-text URLs): each per-intent row binds its target to the
// per-locale arb string, and the English site has no courses/consultation
// page, so those two intents fall back to the general iner.org URL from
// English instead of ever linking a German-only page from English text.
// The ONE exception is the GitHub issue-tracker row (the app's technical
// contact channel, next to the INER method-contact rows): its URL is an
// app-fact, not an INER fact, so it is identical in every locale.
import 'package:cycle_app/l10n/app_localizations.dart';
import 'package:cycle_app/main.dart';
import 'package:cycle_app/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'support/database.dart';
import 'support/finders.dart';
import 'support/viewport.dart';

/// Offline-safe recording fake for the launcher platform interface: every
/// launch is intercepted and only recorded, so no test ever touches a real
/// browser/channel. (The Link-widget delegate is irrelevant to this suite.)
class RecordingLauncher extends UrlLauncherPlatform {
  final List<String> launched = [];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }

  @override
  Future<bool> canLaunch(String url) async => true;
}

void main() {
  // MUST stay the FIRST test of this file — see the comment below — and it
  // deliberately bypasses the shared harness.
  testWidgets('the version line hides when the package-info lookup fails', (
    WidgetTester tester,
  ) async {
    // The harness (appScope) seeds PackageInfo mock values in ONE static
    // that nothing can clear again, and the mock must be answered for every
    // harness-pumping test. This failure path needs the plugin call to
    // ERROR like on a broken/unanswerable device install, so this case
    // pumps the app directly (no harness) — and since the harness's mock
    // cannot be undone, it must run before any other test of this file
    // touches the harness.
    useDeviceLocales(tester, const [Locale('de')]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inMemoryDatabase(),
          onboardingCompletedProvider.overrideWith((ref) => false),
        ],
        child: const CycleApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Sanity: the first-start page itself rendered — the missing package
    // info must not take the whole page down.
    expect(
      find.textContaining('getreue Beobachtung'),
      findsOneWidget,
      reason:
          'an unanswerable package-info plugin call stays contained: '
          'the rest of the about/onboarding content still renders',
    );
    expect(
      find.textContaining('0.1.0'),
      findsNothing,
      reason:
          'a failing package-info lookup HIDES the version line '
          'instead of showing a placeholder — no fallback may ever '
          'resurrect the deleted pubspec-mirror constant',
    );
  });

  /// Opens the app on the settings pane (German device locale, seeded
  /// onboarding flag — same pattern as notices_test.dart) and pushes the
  /// about page from the settings pane's app bar info action.
  Future<void> openGermanAboutPage(WidgetTester tester) async {
    useDeviceLocales(tester, const [Locale('de')]);
    await tester.pumpWidget(appScope(locale: const Locale('de')));
    await tester.pumpAndSettle();

    await tester.tap(navLabel('Einstellungen'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('aboutAction')));
    await tester.pumpAndSettle();
  }

  testWidgets('German about page renders version, warning with INER site, '
      'privacy, license and the selectable feedback URLs', (
    WidgetTester tester,
  ) async {
    final l10n = lookupAppLocalizations(const Locale('de'));
    await openGermanAboutPage(tester);

    // The version line: the app title plus the version the running binary
    // reports via package_info_plus (harness-mocked to '0.1.0' for a real
    // 0.1.0+1 install). Asserted as the whole composed line. The BUILD
    // SUFFIX is never part of the reported version (about.dart shows the
    // version without `+n` — it simply does not exist in PackageInfo).
    expect(
      find.text('${l10n.appTitle} · ${l10n.aboutVersion('0.1.0')}'),
      findsOneWidget,
      reason:
          'the about page shows the app version from the installed '
          'binary (the PackageInfo mock the harness seeds) — the '
          'constant mirror and its sync test are gone',
    );

    // The method warning carries the INER website as visible text.
    expect(
      find.textContaining('getreue Beobachtung'),
      findsOneWidget,
      reason:
          'the fertility-tracking warning is the page\'s core '
          'content',
    );
    expect(
      find.textContaining('iner.org'),
      findsOneWidget,
      reason:
          'the warning points to INER — the website as visible, '
          'copyable text (no link plugin)',
    );
    expect(
      find.textContaining('github.com/BenediktBurger/cycle-app'),
      findsOneWidget,
      reason:
          'the project\'s factual repository URL belongs to the '
          'feedback path',
    );

    // The privacy/DSGVO notice on the about page.
    expect(find.text('Datenschutz'), findsOneWidget);
    expect(
      find.textContaining('ausschließlich lokal'),
      findsOneWidget,
      reason: 'the local-only storage statement is the notice\'s core',
    );

    // The license/copyright section.
    expect(
      find.text('Lizenz'),
      findsOneWidget,
      reason: 'the about page names the license in its own section',
    );
    expect(
      find.textContaining('Apache-2.0'),
      findsOneWidget,
      reason: 'the chosen license (LICENSE, README) is named',
    );
    expect(
      find.textContaining('© 2026'),
      findsOneWidget,
      reason: 'the copyright year (LICENSE: "Copyright 2026")',
    );
    expect(
      find.textContaining('Benedikt Burger'),
      findsOneWidget,
      reason: 'the copyright holder (LICENSE line)',
    );

    // The feedback footer: send-nothing stance plus the issue tracker,
    // rendered as SELECTABLE text so the URL can be copied. The footer's
    // address now has a TAPPABLE sibling row showing the same URL as
    // plain row text, so the URL assertion uses the footer text's
    // parenthesized form (… cycle-app/issues) — the row's plain URL text
    // does not match it. The crash/Privacy-layers overlap (the privacy
    // body carries the same crash clause), so these assertions use
    // footer-unique substrings — after the footer has been dragged into
    // the lazily built range.
    await tester.dragUntilVisible(
      find.textContaining('Melde Fehler'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('cycle-app/issues)'),
      findsOneWidget,
      reason:
          'the feedback footer with the issue-tracker URL sits at '
          'the end of the page',
    );
    expect(
      find.textContaining('Melde Fehler'),
      findsOneWidget,
      reason: 'the footer tells the user where to report errors',
    );

    // Back navigation: popping the pushed route returns to the settings
    // pane (the about content is gone afterwards). The Material AppBar's
    // BackButton is tapped directly (pageBack() is Cupertino-biased).
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('ausschließlich lokal'),
      findsNothing,
      reason: 'popping must leave the pushed about page',
    );
  });

  testWidgets('English about page asserts the same sections via the '
      'English keys', (WidgetTester tester) async {
    final l10n = lookupAppLocalizations(const Locale('en'));
    useDeviceLocales(tester, const [Locale('en')]);
    await tester.pumpWidget(appScope(locale: const Locale('en')));
    await tester.pumpAndSettle();

    await tester.tap(navLabel('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('aboutAction')));
    await tester.pumpAndSettle();

    expect(
      find.text('${l10n.appTitle} · ${l10n.aboutVersion('0.1.0')}'),
      findsOneWidget,
      reason:
          'the version line comes from the installed binary '
          '(harness-mocked PackageInfo) in English too',
    );

    expect(
      find.textContaining('faithful observation'),
      findsOneWidget,
      reason:
          'the English warning is the translated'
          ' same content',
    );
    expect(
      find.textContaining('iner.org'),
      findsOneWidget,
      reason: 'the INER website as visible text in English too',
    );
    expect(
      find.textContaining('github.com/BenediktBurger/cycle-app'),
      findsOneWidget,
    );

    expect(find.text('Privacy'), findsOneWidget);
    expect(
      find.textContaining('exclusively locally'),
      findsOneWidget,
      reason:
          'the English notice carries the same local-only '
          'statement',
    );

    expect(find.text('License'), findsOneWidget);
    expect(find.textContaining('Apache-2.0'), findsOneWidget);
    expect(find.textContaining('© 2026'), findsOneWidget);
    expect(find.textContaining('Benedikt Burger'), findsOneWidget);

    // (Same duplication rule as the German case: the footer-unique
    // parenthesized URL substring, because the tappable issue row now
    // shows the same address as plain row text.)
    await tester.dragUntilVisible(
      find.textContaining('Report problems or suggestions'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Report problems or suggestions'),
      findsOneWidget,
      reason: 'the footer tells the user where to report errors',
    );
    expect(find.textContaining('cycle-app/issues)'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('exclusively locally'),
      findsNothing,
      reason: 'popping must leave the pushed about page',
    );
  });

  testWidgets('German contact rows launch the locale-specific INER URLs', (
    WidgetTester tester,
  ) async {
    final l10n = lookupAppLocalizations(const Locale('de'));
    final launcher = RecordingLauncher();
    final originalLauncher = UrlLauncherPlatform.instance;
    addTearDown(() => UrlLauncherPlatform.instance = originalLauncher);
    UrlLauncherPlatform.instance = launcher;

    await openGermanAboutPage(tester);

    // The contact section sits below the backup hint; bring the LAST row
    // into the built range so all five rows are visible at once.
    await tester.dragUntilVisible(
      find.text(l10n.aboutContactIssues),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();

    // All five labeled rows render with their target URL as visible text —
    // German pages for the German locale, per-intent arb bindings.
    expect(find.text(l10n.aboutContactHeading), findsOneWidget);
    expect(find.text(l10n.aboutContactWebsite), findsOneWidget);
    expect(find.text(l10n.aboutContactCourses), findsOneWidget);
    expect(find.text(l10n.aboutContactConsultation), findsOneWidget);
    expect(find.text(l10n.aboutContactBooks), findsOneWidget);
    expect(
      find.text('https://iner.org/'),
      findsOneWidget,
      reason: 'the general INER website URL belongs to the website row',
    );
    expect(
      find.text('https://iner.org/de/anwenden/kurse/kurse.html'),
      findsOneWidget,
    );
    expect(
      find.text('https://iner.org/de/erlernen/beratungen/deutschland.html'),
      findsOneWidget,
    );
    expect(
      find.text(
        'https://iner.org/de/anwenden/buecher-infos/buecher-literatur.html',
      ),
      findsOneWidget,
    );
    // The technical contact channel: the GitHub issue tracker, identical
    // in every locale (an app-fact URL, not a per-locale INER one).
    expect(
      find.text(l10n.aboutContactIssues),
      findsOneWidget,
      reason:
          'the issue-tracker row is the technical contact channel '
          'next to the INER method-contact rows',
    );
    expect(
      find.text('https://github.com/BenediktBurger/cycle-app/issues'),
      findsOneWidget,
      reason:
          'the German and English rows bind the SAME app-issues '
          'URL — deliberately locale-independent',
    );

    // Tapping a row launches its per-locale URL through the (recorded)
    // platform interface — never a real browser.
    await tester.tap(find.text(l10n.aboutContactWebsite));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.aboutContactCourses));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.aboutContactConsultation));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.aboutContactBooks));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.aboutContactIssues));
    await tester.pumpAndSettle();

    expect(
      launcher.launched,
      unorderedEquals(<String>[
        'https://iner.org/',
        'https://iner.org/de/anwenden/kurse/kurse.html',
        'https://iner.org/de/erlernen/beratungen/deutschland.html',
        'https://iner.org/de/anwenden/buecher-infos/buecher-literatur.html',
        'https://github.com/BenediktBurger/cycle-app/issues',
      ]),
    );
  });

  testWidgets('English contact rows use the EN books page and the iner.org '
      'fallback for the intents without an EN page', (tester) async {
    final l10n = lookupAppLocalizations(const Locale('en'));
    final launcher = RecordingLauncher();
    final originalLauncher = UrlLauncherPlatform.instance;
    addTearDown(() => UrlLauncherPlatform.instance = originalLauncher);
    UrlLauncherPlatform.instance = launcher;

    useDeviceLocales(tester, const [Locale('en')]);
    await tester.pumpWidget(appScope(locale: const Locale('en')));
    await tester.pumpAndSettle();
    await tester.tap(navLabel('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('aboutAction')));
    await tester.pumpAndSettle();

    // The contact section sits below the backup hint; bring the LAST row
    // into the built range so all five rows are visible at once.
    await tester.dragUntilVisible(
      find.text(l10n.aboutContactIssues),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();

    // Info parity: all five intents render in English too.
    expect(find.text(l10n.aboutContactHeading), findsOneWidget);
    expect(find.text(l10n.aboutContactWebsite), findsOneWidget);
    expect(find.text(l10n.aboutContactCourses), findsOneWidget);
    expect(find.text(l10n.aboutContactConsultation), findsOneWidget);
    expect(find.text(l10n.aboutContactBooks), findsOneWidget);
    // The books row carries the one real EN page; courses and consultation
    // FALL BACK to the general site (never a German-only page from
    // English): visible as three iner.org URL texts.
    expect(
      find.text(
        'https://iner.org/en/to-exercise/books-informations/books-literature.html',
      ),
      findsOneWidget,
      reason:
          'the books page exists in English and is the EN books '
          'row\'s target',
    );
    expect(
      find.text('https://iner.org/'),
      findsNWidgets(3),
      reason:
          'website, courses and consultation rows all show/hit the '
          'general INER URL from English — no German-only deep links '
          'from English text',
    );
    // The technical contact channel: the GitHub issue tracker, identical
    // in every locale (an app-fact URL, not a per-locale INER one).
    expect(
      find.text(l10n.aboutContactIssues),
      findsOneWidget,
      reason:
          'the issue-tracker row is the technical contact channel '
          'next to the INER method-contact rows',
    );
    expect(
      find.text('https://github.com/BenediktBurger/cycle-app/issues'),
      findsOneWidget,
      reason:
          'the same URL as the German row — deliberately '
          'locale-independent',
    );

    await tester.tap(find.text(l10n.aboutContactWebsite));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.aboutContactCourses));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.aboutContactConsultation));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.aboutContactBooks));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.aboutContactIssues));
    await tester.pumpAndSettle();

    expect(
      launcher.launched,
      unorderedEquals(<String>[
        'https://iner.org/',
        'https://iner.org/',
        'https://iner.org/',
        'https://iner.org/en/to-exercise/books-informations/books-literature.html',
        'https://github.com/BenediktBurger/cycle-app/issues',
      ]),
    );
  });
}
