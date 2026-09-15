// DB-layer tests: schema, DAOs, constraints.
//
// Pure Dart against NativeDatabase.memory() — no platform channels, no web.
// NOTE (2026-09-15): this omac sandbox cannot execute `flutter test` (it
// denies bind() on 127.0.0.1, which flutter_tester needs). These tests are
// therefore compile-verified via `flutter analyze` here; execution happens
// on the user's machine / CI. On Linux CI hosts, package:sqlite3 needs the
// system sqlite library (see the apt step in .github/workflows/ci.yml).

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cycle_app/domain/date_only.dart';
import 'package:cycle_app/domain/export_import.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/db/export_adapter.dart';
import 'package:cycle_app/db/mappers.dart';
import 'package:cycle_app/db/tables.dart';

void main() {
  late final CycleDatabase db;

  setUp(() {
    db = CycleDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  group('schema & migration v1', () {
    test('seeds exactly one profile named main', () async {
      final profiles = await db.profilesDao.allProfiles();
      expect(profiles, hasLength(1));
      expect(profiles.single.name, 'main');
      expect(profiles.single.ordinal, 0);
      expect(profiles.single.id, 1);
    });

    test('profileId default references the seeded profile', () async {
      await db
          .into(db.cycleEntries)
          .insert(CycleEntriesCompanion.insert(date: DateTime(2026, 3, 1)));
      final row = await db.entriesDao.entryFor(1, DateTime(2026, 3, 1));
      expect(row, isNotNull);
      expect(row!.profileId, 1);
    });

    test('mucus_nfp outside 0..4 is rejected by its CHECK constraint',
        () async {
      await expectLater(
        db.customStatement(
          'INSERT INTO cycle_entries (profile_id, date, mucus_nfp) '
          'VALUES (1, 20000, 5)',
        ),
        throwsA(isA<Exception>()),
      );
      // Sanity: an in-range value goes through.
      await db.customStatement(
        'INSERT INTO cycle_entries (profile_id, date, mucus_nfp) '
        'VALUES (1, 20001, 4)',
      );
    });

    test('bleeding is stored and read as the drift enum vocabulary', () async {
      await db.customStatement(
        "INSERT INTO cycle_entries (profile_id, date, bleeding) "
        "VALUES (1, 20000, 'period')",
      );
      final row = await db.entriesDao.entryFor(1, DateTime(2024, 10, 14));
      expect(row!.bleeding, Bleeding.period);
    });

    test('cycle entries reference existing profiles (foreign keys on)',
        () async {
      await expectLater(
        db.into(db.cycleEntries).insert(
              CycleEntriesCompanion.insert(
                date: DateTime(2026, 3, 1),
                profileId: const Value(99),
              ),
            ),
        throwsA(isA<Exception>()),
      );
    });

    test('epoch-day storage normalizes any time-of-day into the calendar day',
        () async {
      await db.entriesDao.upsertDaily(DailyEntry(date: DateTime(2026, 3, 4)));
      // Same calendar day, other time-of-day: must hit the same row.
      final row =
          await db.entriesDao.entryFor(1, DateTime(2026, 3, 4, 17, 30).toUtc());
      expect(row, isNotNull);
      expect(row!.date.year, 2026);
      expect(row.date.month, 3);
      expect(row.date.day, 4);
    });
  });

  group('EntriesDao.upsertByDate', () {
    test('inserts one row on the first write of a day', () async {
      await db.entriesDao.upsertByDate(
        CycleEntriesCompanion.insert(date: DateTime(2026, 3, 1)).copyWith(
          bleeding: const Value(Bleeding.period),
        ),
      );
      final rows = await db.entriesDao.allEntries(1);
      expect(rows, hasLength(1));
      expect(rows.single.bleeding, Bleeding.period);
    });

    test(
        're-upsert keeps exactly one row, same id, replaces fields, keeps '
        'created_at and bumps updated_at', () async {
      final first = await db.entriesDao.upsertByDate(
        dailyEntryToCompanion(DailyEntry(
          date: DateTime(2026, 3, 1),
          bleeding: Bleeding.period,
          bbtC: 36.1,
        )),
      );
      await Future<void>.delayed(const Duration(milliseconds: 1100));

      final second = await db.entriesDao.upsertByDate(
        dailyEntryToCompanion(DailyEntry(
          date: DateTime(2026, 3, 1),
          bleeding: Bleeding.none,
          bbtC: 36.8,
          notes: 'changed',
        )),
      );

      final rows = await db.entriesDao.allEntries(1);
      expect(rows, hasLength(1)); // still exactly one row for the day

      expect(second.id, first.id); // stable identity
      expect(second.bbtC, 36.8); // replaced
      expect(second.bleeding, Bleeding.none); // replaced
      expect(second.notes, 'changed'); // replaced
      // created_at is kept (drift stores DateTimes with second precision,
      // so direct equality with "now" cannot be asserted reliably):
      expect(!second.createdAt.isBefore(first.createdAt), isTrue);
      expect(!second.updatedAt.isBefore(second.createdAt), isTrue);
    });

    test(
        'a duplicate (profile, date) insert that bypasses the upsert hits '
        'the unique index', () async {
      await db.entriesDao.upsertByDate(
        CycleEntriesCompanion.insert(date: DateTime(2026, 3, 1)),
      );
      await expectLater(
        db.into(db.cycleEntries).insert(
              CycleEntriesCompanion.insert(date: DateTime(2026, 3, 1)),
            ),
        throwsA(isA<Exception>()), // UNIQUE constraint failed
      );
      expect(await db.entriesDao.allEntries(1), hasLength(1));
    });

    test('same day across different profiles does not collide (partner mode)',
        () async {
      await db.profilesDao.addProfile('partner'); // id 2
      await db.entriesDao.upsertDaily(
        DailyEntry(date: DateTime(2026, 1, 10), bleeding: Bleeding.none),
      );
      await db.entriesDao.upsertDaily(
        DailyEntry(date: DateTime(2026, 1, 10), bbtC: 36.2, profileId: 2),
      );
      expect((await db.entriesDao.entryFor(1, DateTime(2026, 1, 10)))!.bbtC,
          isNull);
      expect(
          (await db.entriesDao.entryFor(2, DateTime(2026, 1, 10)))!.bbtC, 36.2);
    });
  });

  group('EntriesDao round trip (drift <-> domain)', () {
    test('upsertDaily stores every domain field and maps back identical',
        () async {
      final input = DailyEntry(
        date: DateTime(2026, 6, 15),
        profileId: 1,
        bbtC: 36.55,
        bleeding: Bleeding.spotting,
        excludeIllness: true,
        excludeAlcohol: true,
        excludeTravel: true,
        excludeOther: true,
        mucusFeeling: 'milky, creamy',
        mucusNfp: 2,
        cervix: 'closed, low',
        pain: true,
        mood: true,
        desire: true,
        sex: true,
        notes: 'Notiz am Rande.',
      );

      final stored = await db.entriesDao.upsertDaily(input);
      final mapped = dailyEntryFromDrift(stored);

      expect(mapped, input); // DailyEntry == compares all fields + same day
      expect(stored.date.year, 2026);
      expect(stored.date.month, 6);
      expect(stored.date.day, 15);
    });

    test('explicit nulls are written on full replace (no stale values left)',
        () async {
      await db.entriesDao.upsertDaily(DailyEntry(
        date: DateTime(2026, 6, 15),
        mucusNfp: 3,
        notes: 'old note',
      ));
      await db.entriesDao.upsertDaily(
        DailyEntry(date: DateTime(2026, 6, 15)),
      );

      final row = (await db.entriesDao.entryFor(1, DateTime(2026, 6, 15)))!;
      expect(row.mucusNfp, isNull);
      expect(row.notes, isNull);
    });
  });

  group('EntriesDao.range / watch / delete', () {
    test('range returns only inclusive-range rows, sorted ascending', () async {
      for (final day in [
        DateTime(2026, 1, 5),
        DateTime(2026, 1, 3),
        DateTime(2026, 1, 8),
        DateTime(2026, 1, 20),
      ]) {
        await db.entriesDao.upsertDaily(
          DailyEntry(date: day, bleeding: Bleeding.none),
        );
      }
      final rows = await db.entriesDao
          .range(1, DateTime(2026, 1, 3), DateTime(2026, 1, 8));
      expect(rows.map((r) => r.date.day).toList(), [3, 5, 8]);
    });

    test('watchRange emits rows as they are upserted', () async {
      final stream = db.entriesDao
          .watchRange(1, DateTime(2026, 1, 1), DateTime(2026, 1, 31));

      expectLater(
        stream,
        emitsInOrder([
          <Object>[], // initial snapshot: empty
          // one row after the upsert below
          predicate<List<CycleEntry>>((rows) =>
              rows.length == 1 && rows.single.bleeding == Bleeding.spotting),
        ]),
      );

      await db.entriesDao.upsertDaily(DailyEntry(
        date: DateTime(2026, 1, 10),
        bleeding: Bleeding.spotting,
      ));
    });
  });

  group('MarksDao', () {
    test('addMark persists with default author user and lists per day',
        () async {
      final mark = await db.marksDao.addMark(
        1,
        DateTime(2026, 3, 12),
        MarkTypes.mucusPeakDay,
      );
      expect(mark.author, 'user');
      expect(mark.markType, MarkTypes.mucusPeakDay);
      expect(mark.entryDate.day, 12);

      final dayMarks = await db.marksDao.marksForDay(1, DateTime(2026, 3, 12));
      expect(dayMarks, hasLength(1));
    });

    test('addMark is idempotent per (profile, date, type)', () async {
      final a = await db.marksDao
          .addMark(1, DateTime(2026, 3, 12), MarkTypes.baseline);
      final b = await db.marksDao
          .addMark(1, DateTime(2026, 3, 12), MarkTypes.baseline);
      expect(a.id, b.id);
      expect(
        await db.marksDao.marksForDay(1, DateTime(2026, 3, 12)),
        hasLength(1),
      );
    });

    test('same day + same type stay distinct across profiles', () async {
      await db.profilesDao.addProfile('partner'); // id 2
      await db.marksDao.addMark(1, DateTime(2026, 3, 12), MarkTypes.baseline);
      await db.marksDao.addMark(2, DateTime(2026, 3, 12), MarkTypes.baseline);
      final p1 = await db.marksDao
          .marksInRange(1, DateTime(2026, 1, 1), DateTime(2026, 12, 31));
      final p2 = await db.marksDao
          .marksInRange(2, DateTime(2026, 1, 1), DateTime(2026, 12, 31));
      expect(p1, hasLength(1));
      expect(p2, hasLength(1));
    });

    test('toggleMark adds then removes, reporting the new presence', () async {
      final date = DateTime(2026, 4, 9);
      expect(
        await db.marksDao.toggleMark(1, date, MarkTypes.fertileWindow),
        isTrue,
      );
      expect(
        await db.marksDao.marksForDay(1, date),
        hasLength(1),
      );
      expect(
        await db.marksDao.toggleMark(1, date, MarkTypes.fertileWindow),
        isFalse,
      );
      expect(
        await db.marksDao.marksForDay(1, date),
        isEmpty,
      );
    });

    test('deleteMark reports removed rows', () async {
      final date = DateTime(2026, 4, 10);
      await db.marksDao.addMark(1, date, MarkTypes.baseline);
      expect(await db.marksDao.deleteMark(1, date, MarkTypes.baseline), 1);
      expect(await db.marksDao.deleteMark(1, date, MarkTypes.baseline), 0);
    });

    test('custom open-vocabulary mark types are storable (future tools)',
        () async {
      final date = DateTime(2026, 4, 11);
      await db.marksDao.addMark(1, date, 'adhocFutureTool');
      final marks = await db.marksDao.marksForDay(1, date);
      expect(marks.single.markType, 'adhocFutureTool');
    });
  });

  group('ProfilesDao', () {
    test('profileNames lists ordinal-ordered names', () async {
      final p = await db.profilesDao.addProfile('zweit', ordinal: 1);
      expect(p.id, greaterThan(1));
      expect(await db.profilesDao.profileNames(), ['main', 'zweit']);
      expect((await db.profilesDao.byId(p.id))!.name, 'zweit');
      expect(await db.profilesDao.byId(404), isNull);
    });
  });

  group('export adapter: profile-id remap on import', () {
    // Document referencing profile id 4 (unknown on the device: 1 = main,
    // 2 = fixture profile). Re-creation assigns the next AUTO id (3), so
    // every write for that document id must use the ACTUAL id — remapping
    // the document id is the adapter's job during the import writes.
    ExportBlob remapDoc() => ExportBlob(
          exportedAt: DateTime.utc(2026, 4, 1),
          profiles: const [
            {'id': 1, 'name': 'main', 'ordinal': 0},
            {'id': 4, 'name': 'partner-doc', 'ordinal': 1},
          ],
          entries: [
            {'profile_id': 4, 'date': '2026-04-02', 'bleeding': 'period'},
            {
              'profile_id': 1,
              'date': '2026-04-10',
              'bleeding': 'period',
              'bbt_c': 36.4,
            },
          ],
          marks: [
            {
              'profile_id': 4,
              'entry_date': '2026-04-20',
              'mark_type': 'peak',
              'author': 'user',
            },
          ],
        );

    test('re-created profiles: document ids are remapped to the actual ids',
        () async {
      final resident = await db.profilesDao.addProfile('resident', ordinal: 1);
      expect(resident.id, 2, reason: 'fixture: device ids are 1 and 2');

      final summary =
          await importJsonToDatabase(db, buildExportJson(remapDoc()));
      expect(summary.entriesNew, 2);
      expect(summary.profilesToInsert, 1);
      expect(summary.marksNew, 1);

      final partner = (await db.profilesDao.allProfiles())
          .singleWhere((p) => p.name == 'partner-doc');
      expect(partner.id, isNot(4),
          reason: 're-created profiles carry their own AUTO id');

      final rows = await db.entriesDao.allEntriesForAllProfiles();
      expect(rows, hasLength(2));
      final fromDoc = rows
          .singleWhere((e) => DateOnly.sameDay(e.date, DateTime(2026, 4, 2)));
      expect(fromDoc.profileId, partner.id,
          reason: 'document profile id 4 is written under the actual id 3');
      final own = rows
          .singleWhere((e) => DateOnly.sameDay(e.date, DateTime(2026, 4, 10)));
      expect(own.profileId, 1,
          reason: 'ids known on the device keep addressing that profile');
      expect(own.bbtC, 36.4);

      final mark = (await db.marksDao.allMarksForAllProfiles()).single;
      expect(mark.profileId, partner.id,
          reason: 'marks are remapped the same way');
      expect(DateOnly.sameDay(mark.entryDate, DateTime(2026, 4, 20)), isTrue);
    });

    test('unexpected errors surface as ImportFailedException', () async {
      // Nothing half-imported survives a mid-transaction/prepare failure:
      // the wrapper turns any engine error into the typed failure the UI
      // can message instead of a raw crash. The engine fails here because
      // the database is closed.
      final broken = CycleDatabase(NativeDatabase.memory());
      await broken.close();
      await expectLater(
        importJsonToDatabase(broken, buildExportJson(remapDoc())),
        throwsA(isA<ImportFailedException>()),
      );
    });
  });
}
