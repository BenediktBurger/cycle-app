// The wheel widget itself is pinned by
// test/ui/temperature_wheel_field_test.dart; these tests reach it through
// the diary entry form.
import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/domain/date_only.dart';
import 'package:cycle_app/domain/decimal_display.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/domain/temperature_steps.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/diary_harness.dart';
import 'support/error_collector.dart';
import 'support/finders.dart';
import 'support/temperature_wheel.dart';
import 'support/viewport.dart';

final _now = DateTime(2026, 4, 10, 14, 35); // 14:35, today = 2026-04-10
final _previousDay = DateOnly.normalize(DateTime(2026, 4, 9));

final _harness = DiaryHarness(now: _now);

/// Seeds the day before the selected one with the value most tests propose
/// as the suggestion.
Future<void> _seedPreviousDay(CycleDatabase db) =>
    db.entriesDao.upsertDaily(DailyEntry(date: _previousDay, bbtC: 36.55));

/// One wheel item's pixel height, measured off the rendered labels like the
/// shared drag helper does — hardcoding it would drift with the layout.
double _wheelItemExtent(WidgetTester tester, double centered) {
  final wheel = diaryTemperatureWheel();
  String label(double value) => formatDecimal(
    value,
    locale: Localizations.localeOf(tester.element(wheel)).toString(),
    decimalDigits: 2,
  );
  final index = TemperatureSteps.nearestIndex(centered);
  final above = tester.getCenter(
    find.descendant(
      of: wheel,
      matching: find.text(label(TemperatureSteps.valueAt(index + 1))),
    ),
  );
  final below = tester.getCenter(
    find.descendant(
      of: wheel,
      matching: find.text(label(TemperatureSteps.valueAt(index - 1))),
    ),
  );
  return (below.dy - above.dy) / 2;
}

/// Drags the wheel's content one item down and back to the starting item,
/// releasing only at the end — the settle lands on the starting item. The
/// leading slop leg is the segment DragStartBehavior.start discards — the
/// shared drag helper documents that accounting.
Future<void> _netZeroDrag(WidgetTester tester) async {
  final centered = double.parse(
    diaryTemperatureCenteredValue(tester).replaceAll(',', '.'),
  );
  final extent = _wheelItemExtent(tester, centered);
  final gesture = await tester.startGesture(
    tester.getCenter(diaryTemperatureWheel()),
  );
  await gesture.moveBy(Offset(0, kDragSlopDefault));
  await tester.pump();
  await gesture.moveBy(Offset(0, extent));
  await tester.pump();
  await gesture.moveBy(Offset(0, -extent));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an empty day centers the previous day\'s value on the gray '
      'wheel and an untouched save stores no temperature', (tester) async {
    _harness.tallSurface(tester);
    await tester.pumpWidget(_harness.scope(seed: _seedPreviousDay));
    await tester.pumpAndSettle();

    expect(
      diaryTemperatureCenteredValue(tester),
      '36,55',
      reason:
          'the previous day\'s value is proposed (German separator, '
          'pinned locale)',
    );
    expect(
      diaryTemperatureWheelSolid(tester),
      isFalse,
      reason:
          'a suggestion is not the day\'s value — the whole wheel renders '
          'gray',
    );
    expect(
      diaryTemperatureClearButton(),
      findsNothing,
      reason: 'a suggestion is not a value — nothing to clear yet',
    );
    expect(
      measuredTimeField(),
      findsNothing,
      reason: 'no value, no measurement time to record',
    );

    await tester.tap(diarySaveButton());
    await tester.pumpAndSettle();

    final stored = (await _harness.db!.entriesDao.entryFor(
      _harness.selectedDay,
    ))!;
    expect(
      stored.bbtC,
      isNull,
      reason:
          'the suggestion is display only — saving without a scroll '
          'stores no temperature',
    );
  });

  testWidgets('scrolling the wheel commits a real value and stamps the time '
      'on today; the save persists both', (tester) async {
    _harness.tallSurface(tester);
    await tester.pumpWidget(_harness.scope(seed: _seedPreviousDay));
    await tester.pumpAndSettle();

    await scrollTemperatureWheel(tester, from: 36.55, to: 36.60);

    expect(
      diaryTemperatureCenteredValue(tester),
      '36,60',
      reason: 'the committed grid value replaces the suggestion',
    );
    expect(
      diaryTemperatureWheelSolid(tester),
      isTrue,
      reason: 'a committed value renders the wheel solid',
    );
    expect(
      diaryTemperatureClearButton(),
      findsOneWidget,
      reason: 'the clear affordance appears with the value',
    );
    expect(
      find.text('14:35'),
      findsOneWidget,
      reason:
          'committing a value on today stamps the pinned current time '
          '(the existing stamping rule)',
    );

    await tester.tap(diarySaveButton());
    await tester.pumpAndSettle();

    final stored = (await _harness.db!.entriesDao.entryFor(
      _harness.selectedDay,
    ))!;
    expect(stored.bbtC, 36.60);
    expect(
      stored.measuredAtMinutes,
      14 * 60 + 35,
      reason: 'the stamped time is stored together with the value',
    );
  });

  testWidgets('a stored value renders the wheel solid, not gray', (
    tester,
  ) async {
    _harness.tallSurface(tester);
    await tester.pumpWidget(
      _harness.scope(
        seed: (db) async {
          await _seedPreviousDay(db);
          await db.entriesDao.upsertDaily(
            DailyEntry(date: _harness.selectedDay, bbtC: 36.4),
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(
      diaryTemperatureCenteredValue(tester),
      '36,40',
      reason: 'the day\'s own value wins over the previous day\'s',
    );
    expect(
      diaryTemperatureWheelSolid(tester),
      isTrue,
      reason: 'the stored value is the day\'s own — full contrast',
    );
    expect(diaryTemperatureClearButton(), findsOneWidget);
  });

  testWidgets('the clear button removes the value and the time; the save '
      'stores nulls for both', (tester) async {
    _harness.tallSurface(tester);
    await tester.pumpWidget(
      _harness.scope(
        seed: (db) async {
          await _seedPreviousDay(db);
          await db.entriesDao.upsertDaily(
            DailyEntry(
              date: _harness.selectedDay,
              bbtC: 36.4,
              measuredAtMinutes: 407, // 06:47
            ),
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('06:47'), findsOneWidget);

    await tester.tap(diaryTemperatureClearButton());
    await tester.pumpAndSettle();

    expect(
      diaryTemperatureWheelSolid(tester),
      isFalse,
      reason: 'clearing leaves the wheel gray',
    );
    expect(diaryTemperatureClearButton(), findsNothing);
    expect(
      measuredTimeField(),
      findsNothing,
      reason:
          'the measured time is metadata of the temperature — it goes '
          'with it',
    );

    await tester.tap(diarySaveButton());
    await tester.pumpAndSettle();

    final stored = (await _harness.db!.entriesDao.entryFor(
      _harness.selectedDay,
    ))!;
    expect(stored.bbtC, isNull);
    expect(
      stored.measuredAtMinutes,
      isNull,
      reason: 'the stored time is dropped together with the temperature',
    );
  });

  testWidgets('the clear button restores the gray suggestion; the save '
      'still stores neither temperature nor time', (tester) async {
    _harness.tallSurface(tester);
    await tester.pumpWidget(_harness.scope(seed: _seedPreviousDay));
    await tester.pumpAndSettle();

    await scrollTemperatureWheel(tester, from: 36.55, to: 36.60);
    await tester.tap(diaryTemperatureClearButton());
    await tester.pumpAndSettle();

    expect(
      diaryTemperatureCenteredValue(tester),
      '36,55',
      reason:
          'clearing returns the wheel to the previous day\'s suggestion, '
          'not to the unset default',
    );
    expect(
      diaryTemperatureWheelSolid(tester),
      isFalse,
      reason: 'the restored suggestion renders gray',
    );
    expect(
      diaryTemperatureClearButton(),
      findsNothing,
      reason: 'a suggestion is not a value — nothing to clear yet',
    );
    expect(
      measuredTimeField(),
      findsNothing,
      reason:
          'the measured time is metadata of the temperature — it goes '
          'with it',
    );

    await tester.tap(diarySaveButton());
    await tester.pumpAndSettle();

    final stored = (await _harness.db!.entriesDao.entryFor(
      _harness.selectedDay,
    ))!;
    expect(
      stored.bbtC,
      isNull,
      reason:
          'the restored suggestion stays display only — the cleared day '
          'saves no temperature',
    );
    expect(
      stored.measuredAtMinutes,
      isNull,
      reason: 'the stamped time is dropped together with the cleared value',
    );
  });

  testWidgets('an off-grid stored value displays the nearest step but '
      'survives an untouched save', (tester) async {
    _harness.tallSurface(tester);
    await tester.pumpWidget(
      _harness.scope(
        seed: (db) async {
          await db.entriesDao.upsertDaily(
            DailyEntry(date: _harness.selectedDay, bbtC: 36.68),
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(
      diaryTemperatureCenteredValue(tester),
      '36,70',
      reason: 'the wheel can only show grid steps — the nearest one',
    );

    await tester.tap(diarySaveButton());
    await tester.pumpAndSettle();

    final stored = (await _harness.db!.entriesDao.entryFor(
      _harness.selectedDay,
    ))!;
    expect(
      stored.bbtC,
      36.68,
      reason:
          'the display rounding must not silently rewrite the stored '
          'value',
    );
  });

  testWidgets('one mouse-wheel notch over the gray suggestion steps exactly '
      'one 0.05 K step; the save persists value and stamped time', (
    tester,
  ) async {
    _harness.tallSurface(tester);
    await tester.pumpWidget(_harness.scope(seed: _seedPreviousDay));
    await tester.pumpAndSettle();

    final p = TestPointer(1, PointerDeviceKind.mouse)
      ..hover(tester.getCenter(diaryTemperatureWheel()));
    await tester.sendEventToBinding(p.scroll(const Offset(0, 100)));
    await tester.pumpAndSettle();

    expect(
      diaryTemperatureCenteredValue(tester),
      '36,50',
      reason:
          'one notch advances exactly one grid item — wheel-down selects '
          'the next LOWER step, like the wheel\'s drag direction',
    );
    expect(
      diaryTemperatureWheelSolid(tester),
      isTrue,
      reason: 'the notch commits the stepped value as a real value',
    );
    expect(
      find.text('14:35'),
      findsOneWidget,
      reason:
          'committing a value on today stamps the pinned current time '
          '(the existing stamping rule)',
    );

    await tester.tap(diarySaveButton());
    await tester.pumpAndSettle();

    final stored = (await _harness.db!.entriesDao.entryFor(
      _harness.selectedDay,
    ))!;
    expect(stored.bbtC, 36.50);
    expect(
      stored.measuredAtMinutes,
      14 * 60 + 35,
      reason: 'the stamped time is stored together with the value',
    );
  });

  testWidgets('a tap commits the centred suggestion; the save persists '
      'value and stamped time', (tester) async {
    _harness.tallSurface(tester);
    await tester.pumpWidget(_harness.scope(seed: _seedPreviousDay));
    await tester.pumpAndSettle();

    await tester.tap(diaryTemperatureWheel());
    await tester.pumpAndSettle();

    expect(
      diaryTemperatureCenteredValue(tester),
      '36,55',
      reason: 'the tap commits the centred suggestion',
    );
    expect(
      diaryTemperatureWheelSolid(tester),
      isTrue,
      reason: 'a committed value renders the wheel solid',
    );
    expect(
      find.text('14:35'),
      findsOneWidget,
      reason:
          'committing a value on today stamps the pinned current time '
          '(the existing stamping rule)',
    );

    await tester.tap(diarySaveButton());
    await tester.pumpAndSettle();

    final stored = (await _harness.db!.entriesDao.entryFor(
      _harness.selectedDay,
    ))!;
    expect(stored.bbtC, 36.55);
    expect(
      stored.measuredAtMinutes,
      14 * 60 + 35,
      reason: 'the stamped time is stored together with the value',
    );
  });

  testWidgets('a re-tap on the committed value is idempotent: value and '
      'stamped time stay, the day keeps a single row', (tester) async {
    _harness.tallSurface(tester);
    await tester.pumpWidget(_harness.scope(seed: _seedPreviousDay));
    await tester.pumpAndSettle();

    await tester.tap(diaryTemperatureWheel());
    await tester.pumpAndSettle();
    await tester.tap(diaryTemperatureWheel());
    await tester.pumpAndSettle();

    expect(
      diaryTemperatureCenteredValue(tester),
      '36,55',
      reason: 'the re-tap commits the same value',
    );
    expect(
      find.text('14:35'),
      findsOneWidget,
      reason: 'the stamping guard must not move the already-stamped time',
    );

    await tester.tap(diarySaveButton());
    await tester.pumpAndSettle();

    final rows = (await _harness.db!.entriesDao.allEntries())
        .where((entry) => entry.date == _harness.selectedDay)
        .toList();
    expect(
      rows,
      hasLength(1),
      reason: 'committing twice must not duplicate the day\'s row',
    );
    expect(rows.single.bbtC, 36.55);
    expect(
      rows.single.measuredAtMinutes,
      14 * 60 + 35,
      reason: 'the stamped time is unchanged by the re-tap',
    );
  });

  testWidgets('a net-zero drag commits the starting value; the save '
      'persists it with the stamped time', (tester) async {
    _harness.tallSurface(tester);
    await tester.pumpWidget(_harness.scope(seed: _seedPreviousDay));
    await tester.pumpAndSettle();

    await _netZeroDrag(tester);

    expect(
      diaryTemperatureCenteredValue(tester),
      '36,55',
      reason: 'the settle lands back on the starting item — and commits it',
    );
    expect(diaryTemperatureWheelSolid(tester), isTrue);
    expect(find.text('14:35'), findsOneWidget);

    await tester.tap(diarySaveButton());
    await tester.pumpAndSettle();

    final stored = (await _harness.db!.entriesDao.entryFor(
      _harness.selectedDay,
    ))!;
    expect(stored.bbtC, 36.55);
    expect(stored.measuredAtMinutes, 14 * 60 + 35);
  });

  testWidgets('the labeled method button sits below the wheel row and the '
      'time row centers on the wheel band, overflow-free at a narrow '
      'viewport', (tester) async {
    useNarrowPhoneViewport(tester);
    await tester.pumpWidget(_harness.scope(seed: _seedPreviousDay));
    await tester.pumpAndSettle();

    expect(
      tester.takeException(),
      isNull,
      reason:
          'the whole form — wheel, time row and method button included — '
          'pumps overflow-free at 320x800',
    );

    await expectNoFrameworkErrors(
      tester,
      () async {
        await scrollTemperatureWheel(tester, from: 36.55, to: 36.60);

        final wheel = tester.getRect(diaryTemperatureWheel());
        final method = tester.getRect(
          find.byKey(const ValueKey('diaryMethodButton')),
        );
        expect(
          method.top,
          greaterThanOrEqualTo(wheel.bottom),
          reason: 'the method button sits BELOW the wheel row',
        );
        expect(
          find.text('Messmethode'),
          findsOneWidget,
          reason:
              'the method control carries its label as visible text '
              '(the methodDialogTitle string), not an icon-only affordance',
        );
        expect(
          tester.getRect(measuredTimeField()).left,
          greaterThan(wheel.right),
          reason: 'the stamped time renders right of the wheel',
        );
        final inlineTimeClear = find.byKey(
          const ValueKey('measuredTimeClearButton'),
        );
        expect(
          inlineTimeClear,
          findsOneWidget,
          reason: 'the inline time × is present at narrow widths',
        );
        final clear = tester.getRect(inlineTimeClear);
        expect(
          (clear.center.dy - wheel.center.dy).abs(),
          lessThanOrEqualTo(2),
          reason:
              'the inline time × rides the time row, vertically aligned '
              'with the wheel band (the selected temperature)',
        );
        expect(
          find.text('14:35'),
          findsOneWidget,
          reason: 'the stamped time renders beside the wheel',
        );

        await tester.tap(find.byKey(const ValueKey('diaryMethodButton')));
        await tester.pumpAndSettle();
        expect(
          find.byType(AlertDialog),
          findsOneWidget,
          reason: 'the labeled method button opens the measurement dialog',
        );
      },
      reason:
          'the below-row method button and the inline time clear must not '
          'introduce a new RenderFlex overflow at narrow widths',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the widest time label ("nicht erfasst") renders overflow-free '
      'at a narrow viewport', (tester) async {
    useNarrowPhoneViewport(tester);
    await tester.pumpWidget(
      _harness.scope(
        selectedDay: _previousDay,
        seed: (db) => db.entriesDao.upsertDaily(
          DailyEntry(date: _previousDay, bbtC: 36.4),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.takeException(),
      isNull,
      reason:
          'a past day with a stored value and no time pumps overflow-free '
          'at 320x800',
    );
    expect(
      measuredTimeField(),
      findsOneWidget,
      reason: 'the time button renders while a value is present',
    );
    expect(
      find.text('nicht erfasst'),
      findsOneWidget,
      reason:
          'the widest localized time label — the width-budget worst case '
          'for the right-side controls column',
    );
  });
}
