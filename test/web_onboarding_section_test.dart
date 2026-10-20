// The web onboarding section: a compact explanation of the durable web path
// (install to the Home Screen, Safari's seven-day eviction of non-installed
// tabs, the JSON export as the only backup, no sync, unencrypted browser
// storage) shown on a web FIRST START only. `webOverride` is the test seam:
// `kIsWeb` is a compile-time constant, so a VM widget test cannot reach the
// web branch otherwise. Native and the post-onboarding about page never show
// the section, and it carries no dismiss/acknowledge control.
import 'package:cycle_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/database.dart';
import 'support/viewport.dart';

void main() {
  const sectionKey = ValueKey('webOnboardingSection');

  Finder section() => find.byKey(sectionKey);

  Finder fact(String text) =>
      find.descendant(of: section(), matching: find.text(text));

  Finder factContaining(String text) =>
      find.descendant(of: section(), matching: find.textContaining(text));

  void expectSectionFacts(AppLocalizations l10n, List<String> terms) {
    for (final text in <String>[
      l10n.aboutWebOnboardingTitle,
      l10n.aboutWebOnboardingInstall,
      l10n.aboutWebOnboardingSafari,
      l10n.aboutWebOnboardingExport,
      l10n.aboutWebOnboardingNoSync,
      l10n.aboutWebOnboardingUnencrypted,
    ]) {
      expect(
        fact(text),
        findsOneWidget,
        reason: 'the section renders its localized title and five fact lines',
      );
    }
    for (final term in terms) {
      expect(
        factContaining(term),
        findsOneWidget,
        reason: 'the section states the required fact "$term"',
      );
    }
  }

  testWidgets('a web first start states every durable-path rule before the '
      'license section', (WidgetTester tester) async {
    useTallSurface(tester);
    final l10n = lookupAppLocalizations(const Locale('de'));
    await tester.pumpWidget(aboutHarness(webOverride: true));
    await tester.pumpAndSettle();

    expect(
      section(),
      findsOneWidget,
      reason:
          'the web branch of the first-start page explains the durable '
          'web path before the user enters data',
    );

    expectSectionFacts(l10n, <String>[
      'Zum Home-Bildschirm',
      'Android',
      'sieben Tagen',
      'JSON-Export',
      'vierteljährlich',
      'keine Synchronisierung',
      'nicht verschlüsselt',
    ]);

    final warningTop = tester.getTopLeft(find.text(l10n.aboutWarningTitle)).dy;
    final sectionTop = tester.getTopLeft(section()).dy;
    final licenseTop = tester
        .getTopLeft(find.text(l10n.aboutLicenseHeading))
        .dy;
    expect(
      sectionTop,
      greaterThan(warningTop),
      reason: 'the web rules follow the method warning',
    );
    expect(
      sectionTop,
      lessThan(licenseTop),
      reason: 'the web rules precede the license section',
    );
  });

  testWidgets('the web section has no dismiss or acknowledge control', (
    WidgetTester tester,
  ) async {
    useTallSurface(tester);
    await tester.pumpWidget(aboutHarness(webOverride: true));
    await tester.pumpAndSettle();

    expect(section(), findsOneWidget);
    for (final control in <Finder>[
      find.byType(IconButton),
      find.byType(ButtonStyleButton),
      find.byType(Checkbox),
    ]) {
      expect(
        find.descendant(of: section(), matching: control),
        findsNothing,
        reason:
            'the section offers no dismiss/acknowledge action, so it '
            'cannot become a one-time notice with its own persisted flag',
      );
    }
  });

  testWidgets('a native first start shows no web section while the warning '
      'and continue button still render', (WidgetTester tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(aboutHarness(webOverride: false));
    await tester.pumpAndSettle();

    expect(
      section(),
      findsNothing,
      reason: 'the native first start never shows the web section',
    );
    expect(
      find.textContaining('getreue Beobachtung'),
      findsOneWidget,
      reason: 'the method warning remains the native first-start content',
    );
    expect(
      find.byKey(const ValueKey('aboutContinueButton')),
      findsOneWidget,
      reason: 'native onboarding keeps its continue action',
    );
  });

  testWidgets('without the override the VM takes the native branch', (
    WidgetTester tester,
  ) async {
    useTallSurface(tester);
    await tester.pumpWidget(aboutHarness());
    await tester.pumpAndSettle();

    expect(
      section(),
      findsNothing,
      reason:
          'on the VM `kIsWeb` is false, so the default gate renders the '
          'section only when the web seam explicitly says web',
    );
  });

  testWidgets('the post-onboarding about page never shows the web section', (
    WidgetTester tester,
  ) async {
    useTallSurface(tester);
    await tester.pumpWidget(aboutHarness(onboarding: false, webOverride: true));
    await tester.pumpAndSettle();

    expect(
      section(),
      findsNothing,
      reason:
          'existing users opening the about page from Settings must not '
          'receive the first-start web explanation',
    );
    expect(
      find.textContaining('getreue Beobachtung'),
      findsOneWidget,
      reason: 'the shared about content stays intact',
    );
  });

  testWidgets('the English web first start states the same facts via the EN '
      'keys', (WidgetTester tester) async {
    useTallSurface(tester);
    final l10n = lookupAppLocalizations(const Locale('en'));
    await tester.pumpWidget(
      aboutHarness(locale: const Locale('en'), webOverride: true),
    );
    await tester.pumpAndSettle();

    expectSectionFacts(l10n, <String>[
      'Add to Home Screen',
      'Android',
      'seven days',
      'JSON export',
      'quarterly',
      'no sync',
      'not encrypted',
    ]);
  });
}
