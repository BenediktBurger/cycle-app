// The diary tab under the "What to track" settings: the Tagebuch entry
// form shows a tracked item's section and hides an untracked one's — all
// three cervix pickers (position/opening/firmness) together, behind one
// toggle. The key guarantee, tested explicitly: hiding is VIEW-ONLY — a
// stored day's values for a hidden section load and save back unchanged
// (no silent data wipe).
//
// The tests pump the Tagebuch screen through the diary harness (German
// locale, pinned clock); a non-default tracked-item configuration is forced
// through the diaryTrack pin (a "live choice" outside the settings card).
import 'package:cycle_app/db/mappers.dart';
import 'package:cycle_app/domain/cervix.dart';
import 'package:cycle_app/domain/date_only.dart';
import 'package:cycle_app/domain/diary_track.dart';
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/domain/mucus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/diary_harness.dart';
import 'support/finders.dart';
import 'support/viewport.dart';

final _now = DateTime(2026, 9, 21, 10, 30);
final _day = DateOnly.normalize(_now);
final _harness = DiaryHarness(now: _now);

/// The stored domain entry of the form's day.
Future<DailyEntry> storedDay(WidgetTester tester) async {
  final (:db, :date) = await savedDayOf(tester);
  final row = await db.entriesDao.entryFor(date);
  return dailyEntryFromDrift(row!);
}

void main() {
  group('default configuration renders the form', () {
    testWidgets('mucus, sex and pain chips show, the cervix pickers stay '
        'hidden', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(_harness.scope());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('mucusSignChip-unset')),
        findsOneWidget,
        reason: 'mucus is tracked by default — its chips show',
      );
      expect(
        find.byKey(const ValueKey('sexTimingChip-morning')),
        findsOneWidget,
        reason: 'sex is tracked by default — its chips show',
      );
      expect(
        find.byKey(const ValueKey('painChip-breast')),
        findsOneWidget,
        reason: 'pain is tracked by default — its chips show',
      );
      expect(find.text('Schmerzen'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('cervixPositionChip-low')),
        findsNothing,
        reason: 'cervix is NOT tracked by default — no position picker',
      );
      expect(
        find.byKey(const ValueKey('cervixOpeningChip-open')),
        findsNothing,
        reason: 'no opening picker at the default configuration',
      );
      expect(
        find.byKey(const ValueKey('cervixFirmnessChip-soft')),
        findsNothing,
        reason: 'no firmness picker at the default configuration',
      );
    });
  });

  group('cervix tracked', () {
    testWidgets('all three cervix pickers appear together, in their '
        'original order; mucus and sex are unaffected', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        _harness.scope(diaryTrack: const DiaryTrack(cervix: true)),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('cervixPositionChip-low')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('cervixOpeningChip-closed')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('cervixFirmnessChip-hard')),
        findsOneWidget,
      );

      // The cervix toggle is scoped to the cervix alone: with cervix on,
      // mucus and sex still show.
      expect(find.byKey(const ValueKey('mucusSignChip-unset')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('sexTimingChip-morning')),
        findsOneWidget,
      );

      // Original form order: position, then opening, then firmness.
      final positionTop = tester.getTopLeft(
        find.byKey(const ValueKey('cervixPositionChip-low')),
      );
      final openingTop = tester.getTopLeft(
        find.byKey(const ValueKey('cervixOpeningChip-closed')),
      );
      final firmnessTop = tester.getTopLeft(
        find.byKey(const ValueKey('cervixFirmnessChip-hard')),
      );
      expect(positionTop.dy < openingTop.dy, isTrue);
      expect(openingTop.dy < firmnessTop.dy, isTrue);
    });
  });

  group('pain untracked', () {
    testWidgets('the pain chips stay hidden; mucus and sex are unaffected', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        _harness.scope(diaryTrack: const DiaryTrack(pain: false)),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('painChip-breast')),
        findsNothing,
        reason: 'pain untracked — the section stays hidden',
      );
      expect(
        find.byKey(const ValueKey('painChip-mittelschmerz')),
        findsNothing,
      );
      expect(find.text('Schmerzen'), findsNothing);

      expect(find.byKey(const ValueKey('mucusSignChip-unset')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('sexTimingChip-morning')),
        findsOneWidget,
      );
    });
  });

  group('temperature untracked', () {
    testWidgets('the section stays hidden with its header, the BBT field, '
        'the method button and the exclude switch', (tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        _harness.scope(diaryTrack: const DiaryTrack(temperature: false)),
      );
      await tester.pumpAndSettle();

      // Exact match: the field label is 'Temperatur (°C)', so the bare
      // 'Temperatur' inside the Form can only be the section header.
      final formHeader = find.descendant(
        of: find.byType(Form),
        matching: find.text('Temperatur'),
      );
      expect(formHeader, findsNothing);
      expect(diaryTemperatureField(), findsNothing);
      expect(find.byKey(const ValueKey('diaryMethodButton')), findsNothing);
      expect(
        find.byKey(const ValueKey('diaryExcludeTemperatureSwitch')),
        findsNothing,
      );
    });
  });

  group('hidden sections do not wipe a stored day (view-only hiding)', () {
    testWidgets('a stored temperature measurement (with its disturbance '
        'bits and exclude mark) survives a save with the section hidden', (
      tester,
    ) async {
      useTallSurface(tester);
      final disturbances = TempDisturbance.sp.bit | TempDisturbance.kr.bit;
      await tester.pumpWidget(
        _harness.scope(
          diaryTrack: const DiaryTrack(temperature: false),
          seed: (db) async {
            await db.entriesDao.upsertDaily(
              DailyEntry(
                date: _day,
                bbtC: 36.5,
                measuredAtMinutes: 360,
                tempDisturbances: disturbances,
              ),
            );
            await db.marksDao.addMark(_day, CycleMarkTypes.ignoreTemperature);
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(diaryTemperatureField(), findsNothing);

      // A visible edit proves the save path ran outside the hidden
      // section.
      await tester.tap(diaryChip('bleeding', 'medium'));
      await tester.pumpAndSettle();
      await tester.tap(diarySaveButton());
      await tester.pumpAndSettle();

      final stored = await storedDay(tester);
      expect(
        stored.bbtC,
        36.5,
        reason:
            'hiding the temperature section must not drop the stored '
            'temperature on save',
      );
      expect(stored.measuredAtMinutes, 360);
      expect(stored.tempDisturbances, disturbances);
      expect(
        await _harness.storedMarkTypes(_day),
        contains(CycleMarkTypes.ignoreTemperature),
        reason: 'the exclude mark survives a save with the switch hidden',
      );
      expect(stored.bleeding, Bleeding.medium);
    });

    testWidgets('a stored cervix observation survives a save with the '
        'pickers hidden', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        _harness.scope(
          seed: (db) => db.entriesDao.upsertDaily(
            DailyEntry(
              date: _day,
              cervixPosition: CervixPosition.low,
              cervixOpening: CervixOpening.open,
              cervixFirmness: CervixFirmness.soft,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The form loads the stored day's cervix values under the hood and
      // writes them back unchanged on save — the load→save round-trip.
      await tester.tap(diarySaveButton());
      await tester.pumpAndSettle();

      final stored = await storedDay(tester);
      expect(
        stored.cervixPosition,
        CervixPosition.low,
        reason:
            'hiding the cervix section must not null the stored values '
            'on save',
      );
      expect(stored.cervixOpening, CervixOpening.open);
      expect(stored.cervixFirmness, CervixFirmness.soft);
    });

    testWidgets('a stored mucus observation survives a save with the section '
        'hidden, and the save still succeeds', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        _harness.scope(
          diaryTrack: const DiaryTrack(mucus: false),
          seed: (db) => db.entriesDao.upsertDaily(
            DailyEntry(
              date: _day,
              mucusSign: MucusSign.s,
              mucusQuality: MucusQuality.ew,
              cervixPosition: CervixPosition.low,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The section is hidden, and the save must still run — the form's
      // other inputs stay live.
      expect(find.byKey(const ValueKey('mucusSignChip-s')), findsNothing);

      // A visible edit that proves the save path ran outside the hidden
      // section.
      await tester.tap(diaryChip('bleeding', 'medium'));
      await tester.pumpAndSettle();
      await tester.tap(diarySaveButton());
      await tester.pumpAndSettle();

      final stored = await storedDay(tester);
      expect(
        stored.bleeding,
        Bleeding.medium,
        reason:
            'the save with a hidden section succeeds (a visible edit '
            'sticks)',
      );
      expect(stored.mucusSign, MucusSign.s);
      expect(stored.mucusQuality, MucusQuality.ew);
      expect(stored.cervixPosition, CervixPosition.low);
    });

    testWidgets('hidden mucus and sex sections keep the stored mucus/sex '
        'values on save', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        _harness.scope(
          diaryTrack: const DiaryTrack(mucus: false, cervix: false, sex: false),
          seed: (db) => db.entriesDao.upsertDaily(
            DailyEntry(
              date: _day,
              mucusSign: MucusSign.a,
              // Morning + evening (the middle slot unset).
              sexTimings: 1 | 4,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('sexTimingChip-morning')), findsNothing);
      await tester.tap(diarySaveButton());
      await tester.pumpAndSettle();

      final stored = await storedDay(tester);
      expect(stored.mucusSign, MucusSign.a);
      expect(
        stored.sexTimings,
        1 | 4,
        reason:
            'sex timings must not be zeroed by a save with the section '
            'hidden',
      );
    });

    testWidgets('a stored pain pair survives a save with the section hidden', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        _harness.scope(
          diaryTrack: const DiaryTrack(pain: false),
          seed: (db) => db.entriesDao.upsertDaily(
            DailyEntry(date: _day, painBreast: true, painMittelschmerz: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('painChip-breast')), findsNothing);
      await tester.tap(diarySaveButton());
      await tester.pumpAndSettle();

      final stored = await storedDay(tester);
      expect(
        stored.painBreast,
        isTrue,
        reason:
            'hiding the pain section must not null the stored flags on save',
      );
      expect(stored.painMittelschmerz, isTrue);
    });
  });
}
