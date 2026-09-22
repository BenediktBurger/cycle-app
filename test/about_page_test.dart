// The About page as reached from the settings pane ("Einstellungen › Über
// die App"): the shared content page (lib/ui/about.dart) must render its
// full content — the version line (mirrored from pubspec via
// lib/version.dart), the method warning (with the INER website as visible
// text), the privacy/DSGVO notice, the license/copyright section, the
// tappable INER contact rows, and the feedback footer whose URLs are
// selectable text; popping the page returns to the settings pane.
//
// German and English device locales receive one case each; both mirror the
// app's German-first posture and the ADR-0007 English fallback.
//
// The contact rows' URLs are deliberately LOCALE-DEPENDENT (unlike the
// earlier plain-text URLs): each per-intent row binds its target to the
// per-locale arb string, and the English site has no courses/consultation
// page, so those two intents fall back to the general iner.org URL from
// English instead of ever linking a German-only page from English text.
import 'package:cycle_app/l10n/app_localizations.dart';
import 'package:cycle_app/version.dart';
import 'package:flutter/material.dart';
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
  /// Opens the app on the settings pane (German device locale, seeded
  /// onboarding flag — same pattern as notices_test.dart) and pushes the
  /// about page via the settings entry.
  Future<void> openGermanAboutPage(WidgetTester tester) async {
    useDeviceLocales(tester, const [Locale('de')]);
    await tester.pumpWidget(appScope(locale: const Locale('de')));
    await tester.pumpAndSettle();

    await tester.tap(navLabel('Einstellungen'));
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(find.text('Über die App'),
        find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Über die App'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'German about page renders version, warning with INER site, '
      'privacy, license and the selectable feedback URLs',
      (WidgetTester tester) async {
    final l10n = lookupAppLocalizations(const Locale('de'));
    await openGermanAboutPage(tester);

    // The version line: the app title plus the mirrored pubspec version —
    // asserted as the whole composed line, pinned to the appVersion
    // constant (not a find-by-number of the version substring alone). The
    // BUILD SUFFIX is stripped for display (about.dart shows the version
    // without `+n`), so the expected line composes only the first part.
    expect(
        find.text('${l10n.appTitle} · '
            '${l10n.aboutVersion(appVersion.split('+').first)}'),
        findsOneWidget,
        reason: 'the about page shows the app version mirrored from '
            'pubspec.yaml (lib/version.dart corresponds to the version '
            'entry), without the internal build suffix');

    // The method warning carries the INER website as visible text.
    expect(find.textContaining('getreue Beobachtung'), findsOneWidget,
        reason: 'the fertility-tracking warning is the page\'s core '
            'content');
    expect(find.textContaining('iner.org'), findsOneWidget,
        reason: 'the warning points to INER — the website as visible, '
            'copyable text (no link plugin)');
    expect(find.textContaining('github.com/BenediktBurger/cycle-app'),
        findsOneWidget,
        reason: 'the project\'s factual repository URL belongs to the '
            'feedback path');

    // The privacy/DSGVO notice on the about page.
    expect(find.text('Datenschutz'), findsOneWidget);
    expect(find.textContaining('ausschließlich lokal'), findsOneWidget,
        reason: 'the local-only storage statement is the notice\'s core');

    // The license/copyright section.
    expect(find.text('Lizenz'), findsOneWidget,
        reason: 'the about page names the license in its own section');
    expect(find.textContaining('Apache-2.0'), findsOneWidget,
        reason: 'the chosen license (LICENSE, README) is named');
    expect(find.textContaining('© 2026'), findsOneWidget,
        reason: 'the copyright year (LICENSE: "Copyright 2026")');
    expect(find.textContaining('Benedikt Burger'), findsOneWidget,
        reason: 'the copyright holder (LICENSE line)');

    // The feedback footer: send-nothing stance plus the issue tracker,
    // rendered as SELECTABLE text so the URL can be copied. The
    // crash/Privacy-layers overlap (the privacy body carries the same
    // crash clause), so these assertions use footer-unique substrings —
    // after the footer has been dragged into the lazily built range.
    await tester.dragUntilVisible(find.textContaining('cycle-app/issues'),
        find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(find.textContaining('cycle-app/issues'), findsOneWidget,
        reason: 'the feedback footer with the issue-tracker URL sits at '
            'the end of the page');
    expect(find.textContaining('Melde Fehler'), findsOneWidget,
        reason: 'the footer tells the user where to report errors');

    // Back navigation: popping the pushed route returns to the settings
    // pane (the about content is gone afterwards). The Material AppBar's
    // BackButton is tapped directly (pageBack() is Cupertino-biased).
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.textContaining('ausschließlich lokal'), findsNothing,
        reason: 'popping must leave the pushed about page');
  });

  testWidgets(
      'English about page asserts the same sections via the '
      'English keys', (WidgetTester tester) async {
    final l10n = lookupAppLocalizations(const Locale('en'));
    useDeviceLocales(tester, const [Locale('en')]);
    await tester.pumpWidget(appScope(locale: const Locale('en')));
    await tester.pumpAndSettle();

    await tester.tap(navLabel('Settings'));
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(find.text('About the app'),
        find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('About the app'));
    await tester.pumpAndSettle();

    expect(
        find.text('${l10n.appTitle} · '
            '${l10n.aboutVersion(appVersion.split('+').first)}'),
        findsOneWidget,
        reason: 'the version line mirrors pubspec.yaml (build suffix '
            'stripped for display) in English too');

    expect(find.textContaining('faithful observation'), findsOneWidget,
        reason: 'the English warning is the translated'
            ' same content');
    expect(find.textContaining('iner.org'), findsOneWidget,
        reason: 'the INER website as visible text in English too');
    expect(find.textContaining('github.com/BenediktBurger/cycle-app'),
        findsOneWidget);

    expect(find.text('Privacy'), findsOneWidget);
    expect(find.textContaining('exclusively locally'), findsOneWidget,
        reason: 'the English notice carries the same local-only '
            'statement');

    expect(find.text('License'), findsOneWidget);
    expect(find.textContaining('Apache-2.0'), findsOneWidget);
    expect(find.textContaining('© 2026'), findsOneWidget);
    expect(find.textContaining('Benedikt Burger'), findsOneWidget);

    await tester.dragUntilVisible(find.textContaining('cycle-app/issues'),
        find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('Report problems or suggestions'), findsOneWidget,
        reason: 'the footer tells the user where to report errors');
    expect(find.textContaining('cycle-app/issues'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.textContaining('exclusively locally'), findsNothing,
        reason: 'popping must leave the pushed about page');
  });

  testWidgets('German contact rows launch the locale-specific INER URLs',
      (WidgetTester tester) async {
    final l10n = lookupAppLocalizations(const Locale('de'));
    final launcher = RecordingLauncher();
    final originalLauncher = UrlLauncherPlatform.instance;
    addTearDown(() => UrlLauncherPlatform.instance = originalLauncher);
    UrlLauncherPlatform.instance = launcher;

    await openGermanAboutPage(tester);

    // The contact section sits below the backup hint; bring the LAST row
    // into the built range so all four rows are visible at once.
    await tester.dragUntilVisible(find.text(l10n.aboutContactBooks),
        find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();

    // All four labeled rows render with their target URL as visible text —
    // German pages for the German locale, per-intent arb bindings.
    expect(find.text(l10n.aboutContactHeading), findsOneWidget);
    expect(find.text(l10n.aboutContactWebsite), findsOneWidget);
    expect(find.text(l10n.aboutContactCourses), findsOneWidget);
    expect(find.text(l10n.aboutContactConsultation), findsOneWidget);
    expect(find.text(l10n.aboutContactBooks), findsOneWidget);
    expect(find.text('https://iner.org/'), findsOneWidget,
        reason: 'the general INER website URL belongs to the website row');
    expect(find.text('https://iner.org/de/anwenden/kurse/kurse.html'),
        findsOneWidget);
    expect(
        find.text('https://iner.org/de/erlernen/beratungen/deutschland.html'),
        findsOneWidget);
    expect(
        find.text(
            'https://iner.org/de/anwenden/buecher-infos/buecher-literatur.html'),
        findsOneWidget);

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

    expect(
        launcher.launched,
        unorderedEquals(<String>[
          'https://iner.org/',
          'https://iner.org/de/anwenden/kurse/kurse.html',
          'https://iner.org/de/erlernen/beratungen/deutschland.html',
          'https://iner.org/de/anwenden/buecher-infos/buecher-literatur.html',
        ]));
  });

  testWidgets(
      'English contact rows use the EN books page and the iner.org '
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
    await tester.dragUntilVisible(find.text('About the app'),
        find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('About the app'));
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(find.text(l10n.aboutContactBooks),
        find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();

    // Info parity: all four intents render in English too.
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
            'https://iner.org/en/to-exercise/books-informations/books-literature.html'),
        findsOneWidget,
        reason: 'the books page exists in English and is the EN books '
            'row\'s target');
    expect(find.text('https://iner.org/'), findsNWidgets(3),
        reason: 'website, courses and consultation rows all show/hit the '
            'general INER URL from English — no German-only deep links '
            'from English text');

    await tester.tap(find.text(l10n.aboutContactWebsite));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.aboutContactCourses));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.aboutContactConsultation));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.aboutContactBooks));
    await tester.pumpAndSettle();

    expect(
        launcher.launched,
        unorderedEquals(<String>[
          'https://iner.org/',
          'https://iner.org/',
          'https://iner.org/',
          'https://iner.org/en/to-exercise/books-informations/books-literature.html',
        ]));
  });
}
