// The About page as reached from the settings pane ("Einstellungen › Über
// die App"): the shared content page (lib/ui/about.dart) must render its
// full content — the version line (mirrored from pubspec via
// lib/version.dart), the method warning (with the INER website as visible
// text), the privacy/DSGVO notice, the license/copyright section, and the
// feedback footer whose URLs are selectable text; popping the page returns
// to the settings pane.
//
// German and English device locales receive one case each; both mirror the
// app's German-first posture and the ADR-0007 English fallback.
import 'package:cycle_app/l10n/app_localizations.dart';
import 'package:cycle_app/version.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/database.dart';
import 'support/finders.dart';
import 'support/viewport.dart';

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
}
