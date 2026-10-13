// The MeasurementMethods table and its day-keyed DAO (which measurement
// route and thermometer apply FROM A DAY ON — each row is a state
// snapshot). Patterns match test/db/cervix_storage_test.dart: pure Dart
// against NativeDatabase.memory().
import 'package:cycle_app/domain/measurement_method.dart';
import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/db/mappers.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Not final: setUp assigns a fresh in-memory database before every test
  // (closed again by the per-test tearDown registered inside setUp).
  late CycleDatabase db;

  setUp(() {
    db = CycleDatabase(NativeDatabase.memory());
    addTearDown(db.close);
  });

  group('measurement_methods table shape', () {
    test('the columns are the day-keyed snapshot set', () async {
      final columns = await db
          .customSelect('PRAGMA table_info(measurement_methods)')
          .get();
      final byName = {
        for (final r in columns) r.data['name']! as String: r.data,
      };
      expect(
        byName.keys,
        unorderedEquals([
          'id',
          'date',
          'method',
          'thermometer',
          'created_at',
          'updated_at',
        ]),
      );
      final id = byName['id']!;
      final date = byName['date']!;
      final method = byName['method']!;
      final thermometer = byName['thermometer']!;
      expect(id['type'], 'INTEGER', reason: 'autoincrement primary key');
      expect(id['pk'], 1);
      expect(date['type'], 'INTEGER');
      expect(
        date['notnull'],
        1,
        reason: 'every snapshot is pinned to its calendar day',
      );
      expect(method['type'], 'TEXT');
      expect(
        method['notnull'],
        1,
        reason: 'a snapshot always carries its route',
      );
      expect(thermometer['type'], 'TEXT');
      expect(
        thermometer['notnull'],
        0,
        reason: 'the thermometer name is optional information',
      );
    });

    test('a duplicate same-day insert hits the unique index', () async {
      await db.measurementMethodsDao.upsertByDate(
        date: DateTime(2026, 3, 1),
        route: MeasurementRoute.vaginal,
      );
      expect(
        db.customStatement(
          "INSERT INTO measurement_methods (date, method) "
          "VALUES (20513, 'oral')",
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('the date unique index exists under its stable name', () async {
      final indexes = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'index' AND "
            "name = 'measurement_methods_date_unique'",
          )
          .get();
      expect(indexes, hasLength(1));
    });

    test('method is engine-rejected outside its vocabulary', () async {
      // A foreign route token (and anything non-vocabulary) must fail at
      // the engine — 'anal' is provably outside the four-token vocabulary.
      await expectLater(
        db.customStatement(
          "INSERT INTO measurement_methods (date, method) "
          "VALUES (21000, 'anal')",
        ),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        db.customStatement(
          "INSERT INTO measurement_methods (date, method) "
          "VALUES (21001, 'Vaginal')",
        ),
        throwsA(isA<Exception>()),
      );
      // Sanity: an in-vocabulary token goes through, thermometer nullable.
      await db.customStatement(
        "INSERT INTO measurement_methods (date, method) "
        "VALUES (21002, 'vaginal')",
      );
    });
  });

  group('MeasurementMethodsDao', () {
    test(
      'a snapshot can be written on a day with NO cycle_entries row',
      () async {
        final stored = await db.measurementMethodsDao.upsertByDate(
          date: DateTime(2026, 7, 5),
          route: MeasurementRoute.rectal,
          thermometer: 'ThermaPen',
        );
        expect(
          await db.entriesDao.entryFor(DateTime(2026, 7, 5)),
          isNull,
          reason: 'the day has no diary entry — methods are independent rows',
        );
        expect(stored.method, 'rectal');
        expect(stored.thermometer, 'ThermaPen');
        expect(stored.date, DateTime.utc(2026, 7, 5));
      },
    );

    test(
      'a time-of-day input collapses to the same calendar day key',
      () async {
        await db.measurementMethodsDao.upsertByDate(
          date: DateTime(2026, 7, 5, 14, 30),
          route: MeasurementRoute.oral,
        );
        expect(
          await db.measurementMethodsDao.snapshotFor(DateTime(2026, 7, 5)),
          isNotNull,
        );
        expect(await db.measurementMethodsDao.allSnapshots(), hasLength(1));
      },
    );

    test('re-upsert keeps exactly one row, same id, replaces fields, keeps '
        'created_at and bumps updated_at', () async {
      final first = await db.measurementMethodsDao.upsertByDate(
        date: DateTime(2026, 3, 1),
        route: MeasurementRoute.vaginal,
        thermometer: 'ThermaPen',
      );
      await Future<void>.delayed(const Duration(milliseconds: 1100));

      final second = await db.measurementMethodsDao.upsertByDate(
        date: DateTime(2026, 3, 1),
        route: MeasurementRoute.other,
      );

      final rows = await db.measurementMethodsDao.allSnapshots();
      expect(rows, hasLength(1)); // still exactly one row for the day
      expect(second.id, first.id); // stable identity
      expect(second.method, 'other'); // replaced
      // A full replacement write: the previously stored name is cleared.
      expect(second.thermometer, isNull);
      // created_at is kept (drift stores DateTimes with second precision,
      // so direct equality with "now" cannot be asserted reliably):
      expect(!second.createdAt.isBefore(first.createdAt), isTrue);
      expect(
        second.updatedAt.isAfter(first.updatedAt),
        isTrue,
        reason: 'the re-save bumps updated_at',
      );
    });

    test('reading the stored row maps back to the domain snapshot '
        '(route token through the shared parse helper)', () async {
      for (final route in MeasurementRoute.values) {
        final day = DateTime(2026, 8, 1 + route.index);
        await db.measurementMethodsDao.upsertByDate(
          date: day,
          route: route,
          thermometer: ' T ',
        );
        final driftRow = (await db.measurementMethodsDao.snapshotFor(day))!;
        expect(
          driftRow.method,
          route.name,
          reason: '${route.name} must be stored as its TEXT token',
        );
        final snapshot = measurementSnapshotFromDrift(driftRow);
        expect(snapshot.route, route);
        expect(
          snapshot.thermometer,
          'T',
          reason:
              'the mapper passes the stored name through verbatim; '
              'trimming happened at the snapshot constructor',
        );
        expect(snapshot.date, DateTime.utc(2026, 8, 1 + route.index));
      }
    });

    test('deleteByDate returns 1 for an existing row and 0 for an absent '
        'one', () async {
      await db.measurementMethodsDao.upsertByDate(
        date: DateTime(2026, 3, 1),
        route: MeasurementRoute.vaginal,
      );
      expect(
        await db.measurementMethodsDao.deleteByDate(DateTime(2026, 3, 1)),
        1,
      );
      expect(
        await db.measurementMethodsDao.deleteByDate(DateTime(2026, 3, 1)),
        0,
      );
      expect(
        await db.measurementMethodsDao.deleteByDate(DateTime(2026, 3, 2)),
        0,
      );
      expect(await db.measurementMethodsDao.allSnapshots(), isEmpty);
    });

    test('allSnapshots and watchAll are ordered ascending by date', () async {
      await db.measurementMethodsDao.upsertByDate(
        date: DateTime(2026, 5, 10),
        route: MeasurementRoute.oral,
      );
      await db.measurementMethodsDao.upsertByDate(
        date: DateTime(2026, 3, 1),
        route: MeasurementRoute.vaginal,
      );
      await db.measurementMethodsDao.upsertByDate(
        date: DateTime(2026, 7, 20),
        route: MeasurementRoute.rectal,
      );

      final dates = (await db.measurementMethodsDao.allSnapshots()).map(
        (r) => r.date,
      );
      expect(
        dates,
        orderedEquals([
          DateTime.utc(2026, 3, 1),
          DateTime.utc(2026, 5, 10),
          DateTime.utc(2026, 7, 20),
        ]),
      );

      final watched = await db.measurementMethodsDao.watchAll().first;
      expect(watched, hasLength(3));
      expect(
        watched.map((r) => r.date),
        orderedEquals([
          DateTime.utc(2026, 3, 1),
          DateTime.utc(2026, 5, 10),
          DateTime.utc(2026, 7, 20),
        ]),
      );
    });

    test('watchAll re-emits after a write', () async {
      final emissions = db.measurementMethodsDao.watchAll();
      expect(await emissions.first, isEmpty);
      await db.measurementMethodsDao.upsertByDate(
        date: DateTime(2026, 3, 1),
        route: MeasurementRoute.vaginal,
      );
      final second = await emissions.first;
      expect(second, hasLength(1));
    });

    test('deleteAll removes every snapshot row', () async {
      await db.measurementMethodsDao.upsertByDate(
        date: DateTime(2026, 3, 1),
        route: MeasurementRoute.vaginal,
      );
      await db.measurementMethodsDao.upsertByDate(
        date: DateTime(2026, 4, 1),
        route: MeasurementRoute.oral,
      );
      expect(await db.measurementMethodsDao.deleteAll(), 2);
      expect(await db.measurementMethodsDao.allSnapshots(), isEmpty);
    });
  });
}
