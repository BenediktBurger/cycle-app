// The diary entry form's section headers, integrated: every section block
// opens with a SectionHeader (exactly one, at its top), the combined cervix
// header replaces the three full-size picker labels, and an untracked
// section disappears together with its header. The info buttons' bottom
// sheets carry the section title and the (German) guidance text; a narrow
// viewport and a large font scale pump the whole form overflow-free.
//
// The tests pump the real app through the diary harness (German locale,
// pinned clock); the German section titles are asserted verbatim.
import 'package:cycle_app/domain/diary_track.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/diary_harness.dart';
import 'support/viewport.dart';

final _now = DateTime(2026, 10, 5, 10, 0);
final _harness = DiaryHarness(now: _now);

// The section titles in form order (German, per the pinned locale).
const _temperatureHeader = 'Temperatur';
const _bleedingHeader = 'Blutung';
const _mucusHeader = 'Fruchtbarkeitszeichen (Zervixschleim)';
const _cervixHeader = 'Muttermund';
const _sexHeader = 'Geschlechtsverkehr (X)';
const _painHeader = 'Schmerzen';

Finder _formHeader(String title) =>
    find.descendant(of: find.byType(Form), matching: find.text(title));

Finder _infoButton(String headerTitle) =>
    find.byKey(ValueKey('diarySectionInfo-$headerTitle'));

void main() {
  group('every header renders exactly once at its block start', () {
    testWidgets('the default configuration shows temperature, bleeding, '
        'mucus, sex and pain headers', (tester) async {
      _harness.tallSurface(tester);
      await tester.pumpWidget(_harness.scope());
      await tester.pumpAndSettle();

      // Cervix is untracked by default: no combined header anywhere.
      expect(
        _formHeader(_cervixHeader),
        findsNothing,
        reason: 'cervix is not tracked by default',
      );
      for (final title in [
        _temperatureHeader,
        _bleedingHeader,
        _mucusHeader,
        _sexHeader,
        _painHeader,
      ]) {
        expect(
          _formHeader(title),
          findsOneWidget,
          reason: 'the $title header opens its form section once',
        );
      }

      // Order pin: the headers sit top-down in form order.
      double? previousDy;
      for (final title in [
        _temperatureHeader,
        _bleedingHeader,
        _mucusHeader,
        _sexHeader,
        _painHeader,
      ]) {
        final dy = tester.getTopLeft(_formHeader(title)).dy;
        if (previousDy != null) expect(dy, greaterThan(previousDy));
        previousDy = dy;
      }
    });

    testWidgets('the temperature header opens the section that had no label '
        'before', (tester) async {
      _harness.tallSurface(tester);
      await tester.pumpWidget(_harness.scope());
      await tester.pumpAndSettle();

      // Exact match here: the field's label text is 'Temperatur (°C)', so
      // the bare 'Temperatur' can only be the header.
      expect(_formHeader(_temperatureHeader), findsOneWidget);
      final headerDy = tester.getTopLeft(_formHeader(_temperatureHeader)).dy;
      final fieldDy = tester
          .getTopLeft(find.byKey(const ValueKey('diaryTemperatureField')))
          .dy;
      expect(
        headerDy < fieldDy,
        isTrue,
        reason: 'the header sits above the BBT field',
      );
    });
  });

  group('the combined cervix header', () {
    testWidgets('replaces the three full-size picker labels with one header '
        'and three small sub-labels', (tester) async {
      _harness.tallSurface(tester);
      await tester.pumpWidget(
        _harness.scope(diaryTrack: const DiaryTrack(cervix: true)),
      );
      await tester.pumpAndSettle();

      expect(_formHeader(_cervixHeader), findsOneWidget);
      expect(find.text('Muttermund-Position'), findsOneWidget);
      expect(find.text('Muttermund-Öffnung'), findsOneWidget);
      expect(find.text('Muttermund-Festigkeit'), findsOneWidget);
    });
  });

  group('info buttons', () {
    testWidgets('every visible section header carries exactly one info '
        'button', (tester) async {
      _harness.tallSurface(tester);
      await tester.pumpWidget(
        _harness.scope(diaryTrack: const DiaryTrack(cervix: true)),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(Form),
          matching: find.byIcon(Icons.info_outline),
        ),
        findsNWidgets(6),
      );
    });

    testWidgets('tapping a section info button opens the guidance sheet with '
        'title and info text', (tester) async {
      _harness.tallSurface(tester);
      await tester.pumpWidget(_harness.scope());
      await tester.pumpAndSettle();

      final button = _infoButton(_sexHeader);
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();

      // The sheet repeats the section title (header + sheet = two).
      expect(find.text(_sexHeader), findsNWidgets(2));
      expect(
        find.textContaining('Samenerguss'),
        findsOneWidget,
        reason: 'the sheet body shows the sex guidance text',
      );
    });
  });

  group('untracked sections hide with their headers', () {
    final cases = [
      (
        'temperature',
        const DiaryTrack(temperature: false),
        _temperatureHeader,
        const ValueKey('diaryTemperatureField'),
      ),
      (
        'mucus',
        const DiaryTrack(mucus: false),
        _mucusHeader,
        const ValueKey('mucusSignChip-unset'),
      ),
      (
        'sex',
        const DiaryTrack(sex: false),
        _sexHeader,
        const ValueKey('sexTimingChip-morning'),
      ),
      (
        'pain',
        const DiaryTrack(pain: false),
        _painHeader,
        const ValueKey('painChip-breast'),
      ),
    ];
    for (final (name, track, header, chip) in cases) {
      testWidgets('$name untracked hides the section and its info button', (
        tester,
      ) async {
        _harness.tallSurface(tester);
        await tester.pumpWidget(_harness.scope(diaryTrack: track));
        await tester.pumpAndSettle();

        expect(_formHeader(header), findsNothing);
        expect(_infoButton(header), findsNothing);
        expect(find.byKey(chip), findsNothing);
      });
    }
  });

  group('layout overflow pins', () {
    Future<void> pumpWholeForm(
      WidgetTester tester, {
      required bool largeFontScale,
    }) async {
      if (largeFontScale) {
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      }
      useNarrowPhoneViewport(tester);
      await tester.pumpWidget(
        _harness.scope(diaryTrack: const DiaryTrack(cervix: true)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the whole form pumps overflow-free at 320 dp', (tester) async {
      await pumpWholeForm(tester, largeFontScale: false);
      expect(
        tester.takeException(),
        isNull,
        reason:
            'all headers, chips and switches render overflow-free '
            'at a 320x800 narrow phone viewport',
      );
    });

    testWidgets('the whole form pumps overflow-free at 320 dp and a 2.0 '
        'font scale', (tester) async {
      await pumpWholeForm(tester, largeFontScale: true);
      expect(
        tester.takeException(),
        isNull,
        reason:
            'the date-row lesson generalized: the header rows stay '
            'overflow-free at a large font scale',
      );
    });
  });
}
