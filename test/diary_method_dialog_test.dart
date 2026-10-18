// Widget tests of the measurement-method dialog on the Tagebuch screen:
// the always-visible thermometer icon at the temperature entry line opens
// the dialog for the SELECTED diary day — seeded with that day's effective
// state (the day's own snapshot first, else the latest earlier one), saving
// an upsert snapshot for that day and offering "Delete change" only while
// the day itself carries a snapshot. The date line shows the day that
// state is anchored to and navigates the diary to an earlier governing
// snapshot's day; apart from that, the diary's day navigation IS the date
// selection — no picker lives inside the dialog. German strings are pinned
// through the harness's de locale.

import 'package:cycle_app/domain/date_only.dart';
import 'package:cycle_app/domain/measurement_method.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'support/diary_harness.dart';
import 'support/error_collector.dart';
import 'support/faulty_db.dart';
import 'support/viewport.dart';

final _now = DateTime(2026, 4, 10, 7, 30);

// A day BEFORE the selected one: its snapshot governs the selected day's
// effective state (the "inheriting" scenarios).
final _earlierDay = DateOnly.normalize(DateTime(2026, 4, 1));

// The date-line text the dialog renders, in the same yMd('de') style.
final _earlierDayText = DateFormat.yMd('de').format(_earlierDay);
final _selectedDayText = DateFormat.yMd('de').format(DateTime(2026, 4, 10));

Finder _dateLineAffordance() => find.byKey(const ValueKey('methodDateLine'));

final _harness = DiaryHarness(now: _now);

const _dialogTitle = 'Messmethode';
const _notRecorded = 'Noch nicht erfasst';
const _deleteChange = 'Änderung löschen';
const _saveFailed =
    'Speichern fehlgeschlagen — die Daten wurden nicht geändert.';
const _deleteFailed =
    'Löschen fehlgeschlagen — die Daten wurden nicht geändert.';
const _loadFailed = 'Laden fehlgeschlagen';
const _changeNote =
    'Lege einen neuen Eintrag an, sobald sich an der Methode etwas ändert — '
    'auch wenn Messort oder Thermometermodell gleich bleiben, zum Beispiel '
    'nach dem Austausch des Thermometers gegen ein anderes desselben Modells. '
    'Den Grund für einen neuen Eintrag kannst du in den Notizen des Tages '
    'festhalten.';

Finder _methodIcon() => find.byKey(const ValueKey('diaryMethodButton'));

Finder _routeChip(String route) =>
    find.byKey(ValueKey('methodRouteChip-$route'));

Finder _thermometerField() =>
    find.byKey(const ValueKey('methodThermometerField'));

Finder _deleteButton() => find.byKey(const ValueKey('methodDeleteButton'));

/// Pumps the diary over a fault-injectable database and hands the instance
/// back (flags flip after the pump, so each test arms exactly its fault).
Future<FaultyCycleDatabase> _pumpFaultyDiary(WidgetTester tester) async {
  await tester.pumpWidget(_harness.scope(builder: FaultyCycleDatabase.new));
  await tester.pumpAndSettle();
  return _harness.db! as FaultyCycleDatabase;
}

Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(_methodIcon());
  await tester.pumpAndSettle();
}

void main() {
  group('thermometer icon', () {
    testWidgets(
      'is visible without an entry and opens the empty-state dialog',
      (tester) async {
        await tester.pumpWidget(_harness.scope());
        await tester.pumpAndSettle();

        expect(
          _methodIcon(),
          findsOneWidget,
          reason:
              'the thermometer icon sits at the temperature entry line even '
              'on a day without any stored entry',
        );

        await _openDialog(tester);
        expect(find.text(_dialogTitle), findsOneWidget);
        expect(
          find.text(_notRecorded),
          findsOneWidget,
          reason:
              'no snapshot exists at all — the dialog says so instead of '
              'inventing a method',
        );
        expect(_thermometerField(), findsOneWidget);
        expect(
          _deleteButton(),
          findsNothing,
          reason: 'this day carries no snapshot — there is nothing to delete',
        );
      },
    );

    testWidgets('stays visible on a day with a stored entry', (tester) async {
      await tester.pumpWidget(
        _harness.scope(
          seed: (db) async {
            await db.entriesDao.upsertDaily(
              DailyEntry(date: _harness.selectedDay, bbtC: 36.4),
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(
        _methodIcon(),
        findsOneWidget,
        reason: 'a recorded cycle day carries the icon too',
      );

      await _openDialog(tester);
      expect(
        find.text(_notRecorded),
        findsOneWidget,
        reason:
            'the entry stores no method of its own — the first save is '
            'the baseline',
      );
    });
  });

  group('dialog seeding', () {
    testWidgets('a day with its own snapshot pre-fills route and thermometer '
        'and offers the delete action', (tester) async {
      await tester.pumpWidget(
        _harness.scope(
          seed: (db) async {
            await db.measurementMethodsDao.upsertByDate(
              date: _harness.selectedDay,
              route: MeasurementRoute.oral,
              thermometer: 'ThermaPen',
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      await _openDialog(tester);
      expect(
        tester.widget<ChoiceChip>(_routeChip('oral')).selected,
        isTrue,
        reason: 'the stored route pre-selects its chip',
      );
      expect(
        tester.widget<ChoiceChip>(_routeChip('vaginal')).selected,
        isFalse,
      );
      expect(
        tester.widget<TextFormField>(_thermometerField()).controller!.text,
        'ThermaPen',
        reason: 'the stored thermometer name pre-fills the field',
      );
      expect(
        _deleteButton(),
        findsOneWidget,
        reason: 'the day carries its own snapshot — deleting it is offered',
      );
      expect(find.text(_notRecorded), findsNothing);
    });

    testWidgets(
      'a day inheriting an earlier snapshot shows the effective state '
      'with no delete action',
      (tester) async {
        await tester.pumpWidget(
          _harness.scope(
            seed: (db) async {
              await db.measurementMethodsDao.upsertByDate(
                date: _earlierDay,
                route: MeasurementRoute.vaginal,
                thermometer: 'Basalthermometer',
              );
            },
          ),
        );
        await tester.pumpAndSettle();

        await _openDialog(tester);
        expect(
          tester.widget<ChoiceChip>(_routeChip('vaginal')).selected,
          isTrue,
          reason:
              'the dialog shows the state as of the selected day — the '
              'earlier snapshot governs it',
        );
        expect(
          tester.widget<TextFormField>(_thermometerField()).controller!.text,
          'Basalthermometer',
        );
        expect(
          _deleteButton(),
          findsNothing,
          reason:
              'the selected day itself carries no snapshot — the change '
              'must not delete an earlier day\'s row',
        );
        expect(find.text(_notRecorded), findsNothing);
      },
    );
  });

  group('dialog date line', () {
    testWidgets(
      'an inheriting day shows the governing snapshot\'s day; tapping it '
      'navigates the diary there',
      (tester) async {
        await tester.pumpWidget(
          _harness.scope(
            seed: (db) async {
              await db.measurementMethodsDao.upsertByDate(
                date: _earlierDay,
                route: MeasurementRoute.vaginal,
                thermometer: 'Basalthermometer',
              );
            },
          ),
        );
        await tester.pumpAndSettle();

        await _openDialog(tester);
        expect(
          find.text(_earlierDayText),
          findsOneWidget,
          reason:
              'the selected day only inherits — the date line points at '
              'the day the snapshot starts, not at the selection',
        );
        expect(
          find.text(_selectedDayText),
          findsNothing,
          reason:
              'the selection was not recorded as a snapshot — it is '
              'not the state\'s anchor day',
        );

        await tester.tap(_dateLineAffordance());
        await tester.pumpAndSettle();

        expect(
          find.text(_dialogTitle),
          findsNothing,
          reason: 'the navigation closes the dialog',
        );

        // Re-opened, the dialog must seed from the navigated-to day: that
        // day carries the snapshot, so it can be deleted there and the
        // date line is plain again.
        await _openDialog(tester);
        expect(
          tester.widget<ChoiceChip>(_routeChip('vaginal')).selected,
          isTrue,
          reason: 'the diary selection is now the governing day',
        );
        expect(
          _deleteButton(),
          findsOneWidget,
          reason: 'the navigated day carries its own snapshot',
        );
        expect(find.text(_earlierDayText), findsOneWidget);
        expect(
          _dateLineAffordance(),
          findsNothing,
          reason:
              'the shown day carries the snapshot itself — no '
              'navigation affordance',
        );
      },
    );

    testWidgets(
      'a day carrying its own snapshot shows the selected day, not tappable',
      (tester) async {
        await tester.pumpWidget(
          _harness.scope(
            seed: (db) async {
              await db.measurementMethodsDao.upsertByDate(
                date: _harness.selectedDay,
                route: MeasurementRoute.oral,
              );
            },
          ),
        );
        await tester.pumpAndSettle();

        await _openDialog(tester);
        expect(find.text(_selectedDayText), findsOneWidget);

        await tester.tap(find.text(_selectedDayText));
        await tester.pumpAndSettle();

        expect(
          find.text(_dialogTitle),
          findsOneWidget,
          reason:
              'a plain date is inert — tapping it changes and closes nothing',
        );
        expect(_dateLineAffordance(), findsNothing);
      },
    );

    testWidgets('the empty state shows the selected day, not tappable', (
      tester,
    ) async {
      await tester.pumpWidget(_harness.scope());
      await tester.pumpAndSettle();

      await _openDialog(tester);
      expect(find.text(_notRecorded), findsOneWidget);
      expect(
        find.text(_selectedDayText),
        findsOneWidget,
        reason:
            'with nothing recorded yet the state\'s anchor is the '
            'selected day itself',
      );
      expect(_dateLineAffordance(), findsNothing);
    });
  });

  group('dialog save', () {
    testWidgets(
      'saves an upsert snapshot for the selected day, blank thermometer '
      'trimmed to null',
      (tester) async {
        await tester.pumpWidget(_harness.scope());
        await tester.pumpAndSettle();

        await _openDialog(tester);
        await tester.tap(_routeChip('vaginal'));
        await tester.pumpAndSettle();
        await tester.enterText(_thermometerField(), '   ');
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('methodSaveButton')));
        await tester.pumpAndSettle();

        expect(
          find.text(_dialogTitle),
          findsNothing,
          reason: 'saving closes the dialog',
        );

        final db = _harness.db!;
        final snapshot = await db.measurementMethodsDao.snapshotFor(
          _harness.selectedDay,
        );
        expect(
          snapshot,
          isNotNull,
          reason: 'the save upserts a row for the selected day',
        );
        expect(snapshot!.method, 'vaginal');
        expect(
          snapshot.thermometer,
          isNull,
          reason: 'a whitespace-only name is no name (the shared trim rule)',
        );
        expect(
          (await db.measurementMethodsDao.allSnapshots()).length,
          1,
          reason: 'exactly one row was written',
        );
      },
    );
  });

  group('dialog delete', () {
    testWidgets('deletes the day\'s own snapshot; re-opened, the dialog seeds '
        'from the earlier effective state', (tester) async {
      await tester.pumpWidget(
        _harness.scope(
          seed: (db) async {
            await db.measurementMethodsDao.upsertByDate(
              date: _earlierDay,
              route: MeasurementRoute.rectal,
            );
            await db.measurementMethodsDao.upsertByDate(
              date: _harness.selectedDay,
              route: MeasurementRoute.vaginal,
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      await _openDialog(tester);
      expect(find.text(_deleteChange), findsOneWidget);
      await tester.tap(_deleteButton());
      await tester.pumpAndSettle();

      final db = _harness.db!;
      expect(
        await db.measurementMethodsDao.snapshotFor(_harness.selectedDay),
        isNull,
        reason: 'the delete removes the selected day\'s own row',
      );
      expect(
        (await db.measurementMethodsDao.allSnapshots()).single.method,
        'rectal',
        reason: 'the earlier snapshot survives',
      );

      await _openDialog(tester);
      expect(
        tester.widget<ChoiceChip>(_routeChip('rectal')).selected,
        isTrue,
        reason:
            're-opened, the dialog seeds from the earlier effective '
            'state',
      );
      expect(
        _deleteButton(),
        findsNothing,
        reason: 'the day itself no longer carries a snapshot',
      );
    });
  });

  group('failure feedback', () {
    testWidgets('a failed save shows the saveFailed message and keeps the '
        'dialog open for another attempt', (tester) async {
      final db = await _pumpFaultyDiary(tester);
      await _openDialog(tester);
      await tester.tap(_routeChip('oral'));
      await tester.pumpAndSettle();

      db.failMethodSave = true;
      await tester.tap(find.byKey(const ValueKey('methodSaveButton')));
      await tester.pumpAndSettle();

      expect(find.text(_saveFailed), findsOneWidget);
      expect(
        find.text(_dialogTitle),
        findsOneWidget,
        reason: 'a failed save must not close the dialog — nothing was written',
      );
      expect(
        await db.measurementMethodsDao.snapshotFor(_now),
        isNull,
        reason: 'the failure left no snapshot behind',
      );

      // The dialog stays usable: disarming the fault lets the same press
      // succeed and close.
      db.failMethodSave = false;
      await tester.tap(find.byKey(const ValueKey('methodSaveButton')));
      await tester.pumpAndSettle();

      expect(find.text(_dialogTitle), findsNothing);
      expect(
        (await db.measurementMethodsDao.snapshotFor(_now))!.method,
        'oral',
      );
    });

    testWidgets('a failed delete shows the deleteDataFailed message and '
        'keeps the dialog open', (tester) async {
      final db = await _pumpFaultyDiary(tester);
      await db.measurementMethodsDao.upsertByDate(
        date: _now,
        route: MeasurementRoute.oral,
      );
      await _openDialog(tester);

      db.failMethodDelete = true;
      await tester.tap(_deleteButton());
      await tester.pumpAndSettle();

      expect(find.text(_deleteFailed), findsOneWidget);
      expect(
        find.text(_dialogTitle),
        findsOneWidget,
        reason:
            'a failed delete must not close the dialog — nothing was deleted',
      );
      expect(
        await db.measurementMethodsDao.snapshotFor(_now),
        isNotNull,
        reason: 'the snapshot survives the failed delete',
      );
    });

    testWidgets('a failed load shows the loadFailed message in the dialog '
        'body instead of spinning forever', (tester) async {
      final db = await _pumpFaultyDiary(tester);
      db.failMethodLoad = true;

      await _openDialog(tester);

      expect(find.text(_loadFailed), findsOneWidget);
      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
        reason: 'loading has ended — the failure is the outcome',
      );
      expect(find.text(_dialogTitle), findsOneWidget);
    });
  });

  group('dialog change note', () {
    testWidgets('the empty state shows the guidance note', (tester) async {
      await tester.pumpWidget(_harness.scope());
      await tester.pumpAndSettle();

      await _openDialog(tester);
      expect(
        find.text(_changeNote),
        findsOneWidget,
        reason:
            'the guidance applies generally — even the first entry is a '
            'method change',
      );
    });

    testWidgets('a day with its own snapshot shows the guidance note too', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness.scope(
          seed: (db) async {
            await db.measurementMethodsDao.upsertByDate(
              date: _harness.selectedDay,
              route: MeasurementRoute.oral,
              thermometer: 'ThermaPen',
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      await _openDialog(tester);
      expect(
        find.text(_changeNote),
        findsOneWidget,
        reason:
            'the note is shown in every dialog state — the guidance to '
            'create a new entry on any change is not state-specific',
      );
    });
  });

  group('narrow viewport', () {
    testWidgets('icon and dialog stay overflow-free on a small phone', (
      tester,
    ) async {
      useNarrowPhoneViewport(tester);
      await tester.pumpWidget(_harness.scope());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await expectNoFrameworkErrors(
        tester,
        () async {
          await _openDialog(tester);
          expect(find.text(_dialogTitle), findsOneWidget);
          await tester.tap(_routeChip('oral'));
          await tester.pumpAndSettle();
          await tester.enterText(_thermometerField(), 'ThermaPen');
          await tester.pumpAndSettle();
          expect(_deleteButton(), findsNothing);
        },
        reason:
            'the temperature line and the dialog must lay out '
            'overflow-free at 320x800',
      );
      expect(tester.takeException(), isNull);
    });
  });
}
