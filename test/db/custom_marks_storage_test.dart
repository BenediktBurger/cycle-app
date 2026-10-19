// Storage tests for the custom_marks column: the lenient JSON decode of
// user-defined category picks, the NULL-on-empty write rule, and the
// DailyEntry field's value equality / copyWith behavior. On-disk migration
// choreography lives in test/db/migration_test.dart.
//
// Pure Dart against NativeDatabase.memory() — no platform channels. Same
// Linux system-sqlite note as test/db/cycle_database_test.dart.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/db/mappers.dart';
import 'package:cycle_app/domain/models.dart';

void main() {
  // Not final: setUp assigns a fresh in-memory database before every test
  // (closed again by the per-test tearDown registered inside setUp).
  late CycleDatabase db;

  setUp(() {
    db = CycleDatabase(NativeDatabase.memory());
    addTearDown(db.close);
  });

  group('custom_marks column', () {
    test('a marked day round-trips through the mapper', () async {
      const marks = {
        'Sport': ['Joggen', 'Kraft'],
        'Medikamente': ['Ibuprofen'],
      };
      await db.entriesDao.upsertDaily(
        DailyEntry(date: DateTime(2026, 6, 15), customMarks: marks),
      );

      final raw = await db
          .customSelect('SELECT custom_marks FROM cycle_entries')
          .getSingle();
      expect(
        raw.data['custom_marks'],
        '{"Sport":["Joggen","Kraft"],"Medikamente":["Ibuprofen"]}',
        reason: 'the picks are stored as one label-keyed JSON object',
      );

      final mapped = dailyEntryFromDrift(
        (await db.entriesDao.entryFor(DateTime(2026, 6, 15)))!,
      );
      expect(mapped.customMarks, marks);
    });

    test('an empty map stores NULL, not an empty JSON object', () async {
      await db.entriesDao.upsertDaily(
        DailyEntry(date: DateTime(2026, 6, 15), customMarks: const {}),
      );

      final raw = await db
          .customSelect('SELECT custom_marks FROM cycle_entries')
          .getSingle();
      expect(
        raw.data['custom_marks'],
        isNull,
        reason:
            'a day without custom marks is indistinguishable '
            'from a pre-v14 row',
      );
      final mapped = dailyEntryFromDrift(
        (await db.entriesDao.entryFor(DateTime(2026, 6, 15)))!,
      );
      expect(mapped.customMarks, isEmpty);
    });

    test(
      're-saving without marks clears a stored map (full replace)',
      () async {
        await db.entriesDao.upsertDaily(
          DailyEntry(
            date: DateTime(2026, 6, 15),
            customMarks: const {
              'Sport': ['Joggen'],
            },
          ),
        );
        await db.entriesDao.upsertDaily(
          DailyEntry(date: DateTime(2026, 6, 15)),
        );

        final raw = await db
            .customSelect('SELECT custom_marks FROM cycle_entries')
            .getSingle();
        expect(raw.data['custom_marks'], isNull);
      },
    );
  });

  group('tryParseCustomMarks (lenient decode)', () {
    test(
      'every malformed stored value decodes to {} without throwing',
      () async {
        const malformed = <String?>[
          null,
          '',
          'kein JSON',
          '[1, 2, 3]',
          '42',
          '"ein String"',
          '{"Sport": "Joggen"}',
          '{"Sport": 42}',
          '{"Sport": [1, 2]}',
          '{"Sport": [null]}',
          '{"Sport": ["Joggen"], "Störung": [true]}',
          '{42: ["Joggen"]}',
        ];
        for (final raw in malformed) {
          expect(
            tryParseCustomMarks(raw),
            isEmpty,
            reason: "malformed input '$raw' renders nothing, never throws",
          );
        }
      },
    );

    test('the stored JSON shape decodes verbatim, empty lists included', () {
      expect(tryParseCustomMarks('{"Sport":["Joggen","Kraft"]}'), {
        'Sport': ['Joggen', 'Kraft'],
      });
      expect(tryParseCustomMarks('{"Sport":[]}'), {
        'Sport': <String>[],
      }, reason: 'a bare-category tick (no entries) survives the decode');
    });
  });

  group('DailyEntry.customMarks', () {
    final day = DateTime(2026, 6, 15);

    test('equality compares the map by value', () {
      final marked = DailyEntry(
        date: day,
        customMarks: const {
          'Sport': ['Joggen', 'Kraft'],
        },
      );
      expect(
        DailyEntry(
          date: day,
          customMarks: const {
            'Sport': ['Joggen', 'Kraft'],
          },
        ),
        marked,
      );
      expect(
        DailyEntry(
          date: day,
          customMarks: const {
            'Kraft': ['Joggen', 'Sport'],
          },
        ),
        isNot(marked),
      );
      expect(
        DailyEntry(
          date: day,
          customMarks: const {
            'Sport': ['Kraft', 'Joggen'],
          },
        ),
        isNot(marked),
        reason: 'the item order within a category is significant',
      );
      expect(DailyEntry(date: day), isNot(marked));
      // Key order is not significant (map semantics).
      final a = DailyEntry(date: day, customMarks: const {'A': [], 'B': []});
      expect(DailyEntry(date: day, customMarks: const {'B': [], 'A': []}), a);
      expect(
        DailyEntry(date: day, customMarks: const {'B': [], 'A': []}).hashCode,
        a.hashCode,
      );
    });

    test('copyWith preserves the map and can replace it', () {
      final marked = DailyEntry(
        date: day,
        customMarks: const {
          'Sport': ['Joggen'],
        },
      );
      expect(marked.copyWith(notes: 'Notiz').customMarks, {
        'Sport': ['Joggen'],
      });
      expect(
        marked
            .copyWith(
              customMarks: const {
                'Medikamente': ['Eisen'],
              },
            )
            .customMarks,
        {
          'Medikamente': ['Eisen'],
        },
      );
    });
  });
}
