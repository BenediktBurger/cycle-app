// Standalone widget tests of the diary section header: title rendering,
// the optional info button (absent without info, tooltip topic
// substitution, sufficient tap target) and the guidance bottom sheet it
// opens. Plain MaterialApp scaffold — the German section strings live at
// the call sites, so English (any supported locale) pins the mechanics.
import 'package:cycle_app/l10n/app_localizations.dart';
import 'package:cycle_app/ui/section_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _title = 'Temperature';
const _info = 'Measure after waking, before getting up or any activity.';

Widget _host(Widget header) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: Scaffold(body: ListView(children: [header])),
);

void main() {
  testWidgets('renders the title once, left-aligned', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host(const SectionHeader(title: _title)));

    expect(find.text(_title), findsOneWidget);
    expect(
      tester.getTopLeft(find.text(_title)).dx,
      0,
      reason: 'the section title sits at the row start (left-aligned)',
    );
  });

  testWidgets('shows no info button without info', (WidgetTester tester) async {
    await tester.pumpWidget(_host(const SectionHeader(title: _title)));

    expect(find.byIcon(Icons.info_outline), findsNothing);
  });

  testWidgets('shows the info button with the title as tooltip topic', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(const SectionHeader(title: _title, info: _info)),
    );

    expect(find.byIcon(Icons.info_outline), findsOneWidget);
    expect(
      find.byTooltip('Information about $_title'),
      findsOneWidget,
      reason: 'the localized tooltip substitutes the section title as topic',
    );
  });

  testWidgets('tapping the info button opens the guidance bottom sheet', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(const SectionHeader(title: _title, info: _info)),
    );

    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();

    expect(find.text(_info), findsOneWidget);
    // The sheet repeats the section title above its body.
    expect(find.text(_title), findsNWidgets(2));
  });

  testWidgets('dismissing the sheet leaves no widget state behind', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(const SectionHeader(title: _title, info: _info)),
    );
    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();

    // Tap the barrier above the sheet to dismiss it.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.text(_info), findsNothing);
    expect(find.text(_title), findsOneWidget);
  });

  testWidgets('the info button tap target covers 48 dp', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(const SectionHeader(title: _title, info: _info)),
    );

    final button = find.ancestor(
      of: find.byIcon(Icons.info_outline),
      matching: find.byType(IconButton),
    );
    final size = tester.getSize(button);
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
  });
}
