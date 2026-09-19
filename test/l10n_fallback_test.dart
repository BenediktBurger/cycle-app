// Localization fallback tests: a missing translation term for the active
// locale must fall back to *English* (not the German template text), and an
// active locale outside the supported de/en set must resolve to English as
// well (see docs/adr/0007-language-policy.md: multilingual app, English as
// the fallback language so non-Germans are never exposed to German).
//
// The per-term fallback itself is a *codegen-time* mechanism: gen-l10n bakes
// the template ARB's text into a locale class for any key missing from that
// locale's ARB. Which key is missing therefore cannot be simulated at
// runtime; what these tests pin is the two real levers:
//  - the template ARB is the English one (l10n.yaml `template-arb-file`),
//  - an unsupported active language falls back to English via resolution,
//    i.e. English is the first/last supported locale.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/database.dart';

ProviderScope _appScope(Locale locale) =>
    // An active language that exists in neither supported language — what
    // the app *resolves it to* is the fallback under test.
    appScope(locale: locale);

void main() {
  testWidgets('unsupported active language resolves to English, not German',
      (WidgetTester tester) async {
    await tester.pumpWidget(_appScope(const Locale('fr')));
    await tester.pumpAndSettle();

    expect(
      find.text('Diary'),
      findsWidgets,
      reason: 'An unsupported active locale must fall back to English',
    );
    expect(
      find.text('Tagebuch'),
      findsNothing,
      reason: 'German is never the fallback for an unknown locale',
    );
  });

  test('untranslated keys fall back to English: the template ARB is English',
      () {
    // gen-l10n fills missing terms with the template ARB's text; the fallback
    // language is therefore determined by which ARB is the template.
    final l10nYaml = File('l10n.yaml').readAsStringSync();
    expect(
      l10nYaml,
      contains('template-arb-file: app_en.arb'),
      reason:
          'Untranslated terms must fall back to English, i.e. app_en.arb must '
          'be the gen-l10n template',
    );
  });
}
