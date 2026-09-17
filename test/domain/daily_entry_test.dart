// Pure-Dart tests for the DailyEntry domain model: the measured-time rule
// (time of day is metadata OF the temperature measurement, so a DailyEntry
// never carries a measuredAtMinutes without a bbtC — the constructor
// normalizes/drops the time, and copyWith/equality inherit that) plus the
// sex-time bitmask and cervix firmness fields. DB mappers, the
// export/import writers and any future writer all build DailyEntries, so
// they cannot store a stray time or an out-of-range mask either.
import 'package:cycle_app/domain/cervix.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final day = DateTime(2026, 6, 15);

  group('DailyEntry keeps the measured time only with a temperature', () {
    test('temperature + time both survive the constructor', () {
      final entry = DailyEntry(
        date: day,
        bbtC: 36.5,
        measuredAtMinutes: 407, // 06:47
      );
      expect(entry.bbtC, 36.5);
      expect(entry.measuredAtMinutes, 407);
    });

    test('a time without a temperature is dropped by the constructor', () {
      final entry = DailyEntry(date: day, measuredAtMinutes: 407);
      expect(entry.bbtC, isNull);
      expect(entry.measuredAtMinutes, isNull,
          reason: 'the time belongs to the temperature; nothing is stored '
              'for mucus-only etc. days');
    });

    // The constructor stays `const` (the normalization is a plain ternary
    // in the initializer list); there is no const DateTime to instantiate
    // one with, so const-ness is verified by `flutter analyze` instead.
  });

  group('copyWith inherits the normalization', () {
    final measured = DailyEntry(
      date: day,
      bbtC: 36.5,
      measuredAtMinutes: 407,
    );

    test('an untouched copy keeps temperature and time', () {
      final copy = measured.copyWith();
      expect(copy.bbtC, 36.5);
      expect(copy.measuredAtMinutes, 407);
    });

    test('changing the temperature keeps the time', () {
      final copy = measured.copyWith(bbtC: 36.7);
      expect(copy.bbtC, 36.7);
      expect(copy.measuredAtMinutes, 407);
    });

    test('clearing the temperature drops the time', () {
      final copy = measured.copyWith(bbtC: null);
      expect(copy.bbtC, isNull);
      expect(copy.measuredAtMinutes, isNull,
          reason: 'a temperature-less save must not keep the old time');
    });

    test('setting a time on a temperature-less day stays null', () {
      final withoutTemp =
          DailyEntry(date: day).copyWith(measuredAtMinutes: 420);
      expect(withoutTemp.measuredAtMinutes, isNull);

      final explicit = measured.copyWith(
        bbtC: null,
        measuredAtMinutes: 420,
      );
      expect(explicit.bbtC, isNull);
      expect(explicit.measuredAtMinutes, isNull,
          reason: 'no copyWith call can construct the invalid state');
    });

    test('clearing the time with a temperature present stays cleared', () {
      final copy = measured.copyWith(measuredAtMinutes: null);
      expect(copy.bbtC, 36.5);
      expect(copy.measuredAtMinutes, isNull);
    });
  });

  group('equality/hashCode see the normalized values', () {
    test('a time without a temperature equals the same day without one', () {
      final withStrayTime = DailyEntry(date: day, measuredAtMinutes: 407);
      final plain = DailyEntry(date: day);
      expect(withStrayTime, equals(plain));
      expect(withStrayTime.hashCode, plain.hashCode);
    });

    test('different times on the same measured day differ', () {
      final a = DailyEntry(date: day, bbtC: 36.5, measuredAtMinutes: 407);
      final b = DailyEntry(date: day, bbtC: 36.5, measuredAtMinutes: 408);
      expect(a, isNot(equals(b)));
    });
  });

  group('SexTiming bitmask', () {
    test('bits follow the numeric-flag pattern (1/2/4)', () {
      expect(SexTiming.start.bit, 1);
      expect(SexTiming.middle.bit, 2);
      expect(SexTiming.end.bit, 4);
    });

    test('bits are pairwise disjoint (a mask can name each combination)', () {
      final bits = SexTiming.values.map((t) => t.bit).toSet();
      expect(bits.length, SexTiming.values.length);
      for (final a in SexTiming.values) {
        for (final b in SexTiming.values) {
          if (a == b) continue;
          expect(a.bit & b.bit, 0,
              reason: '${a.name} and ${b.name} must be independent flags');
        }
      }
    });
  });

  group('sexTimings field', () {
    test('defaults to 0 — no sex recorded', () {
      expect(DailyEntry(date: day).sexTimings, 0);
    });

    test('single and combined bits are stored verbatim', () {
      for (final timing in SexTiming.values) {
        expect(DailyEntry(date: day, sexTimings: timing.bit).sexTimings,
            timing.bit,
            reason: '${timing.name} alone is a valid mask');
      }
      final twice = DailyEntry(
        date: day,
        sexTimings: SexTiming.start.bit | SexTiming.end.bit,
      );
      expect(twice.sexTimings, 5,
          reason: 'multiple bits = multiple times on the same day');
    });

    test('every mask 0..7 is representable, and only those', () {
      for (var mask = 0; mask <= 7; mask++) {
        expect(DailyEntry(date: day, sexTimings: mask).sexTimings, mask);
      }
      expect(
        () => DailyEntry(date: day, sexTimings: 8),
        throwsA(isA<AssertionError>()),
        reason: '8 is outside the 3-bit vocabulary',
      );
      expect(
        () => DailyEntry(date: day, sexTimings: -1),
        throwsA(isA<AssertionError>()),
        reason: 'negative masks are outside the vocabulary',
      );
    });

    test('copyWith keeps the mask unless given', () {
      final entry = DailyEntry(date: day, sexTimings: SexTiming.middle.bit);
      expect(entry.copyWith().sexTimings, 2);
      expect(entry.copyWith(desire: true).sexTimings, 2);
      expect(entry.copyWith(sexTimings: 7).sexTimings, 7);
      expect(
        DailyEntry(date: day).copyWith(sexTimings: 0).sexTimings,
        0,
        reason: 'explicit 0 is a valid value, not an "unset" request',
      );
    });
  });

  group('cervixFirmness field', () {
    test('defaults to null — not observed', () {
      expect(DailyEntry(date: day).cervixFirmness, isNull);
    });

    test('constructs with every vocabulary value', () {
      for (final firmness in CervixFirmness.values) {
        expect(
          DailyEntry(date: day, cervixFirmness: firmness).cervixFirmness,
          firmness,
        );
      }
    });

    test('copyWith sentinel semantics: absent keeps, explicit null clears', () {
      final entry = DailyEntry(
        date: day,
        cervixFirmness: CervixFirmness.halfSoft,
      );
      expect(entry.copyWith().cervixFirmness, CervixFirmness.halfSoft,
          reason: 'an absent argument keeps the observation');
      expect(
          entry.copyWith(desire: true).cervixFirmness, CervixFirmness.halfSoft);
      expect(entry.copyWith(cervixFirmness: CervixFirmness.soft).cervixFirmness,
          CervixFirmness.soft);
      expect(entry.copyWith(cervixFirmness: null).cervixFirmness, isNull,
          reason: 'explicit null clears the observation');
      expect(
        DailyEntry(date: day).copyWith(cervixFirmness: null).cervixFirmness,
        isNull,
      );
    });

    test('independent of position and opening', () {
      final entry = DailyEntry(
        date: day,
        cervixPosition: CervixPosition.high,
        cervixOpening: CervixOpening.open,
        cervixFirmness: CervixFirmness.soft,
      );
      expect(entry.copyWith(cervixFirmness: null).cervixPosition,
          CervixPosition.high);
      expect(entry.copyWith(cervixFirmness: null).cervixOpening,
          CervixOpening.open);
      expect(
        entry.copyWith(cervixPosition: null).cervixFirmness,
        CervixFirmness.soft,
        reason: 'firmness is a third independent observation',
      );
    });
  });

  group('equality/hashCode include the new fields', () {
    test('entries differing only in sexTimings differ', () {
      final a = DailyEntry(date: day, sexTimings: SexTiming.start.bit);
      final b = DailyEntry(date: day, sexTimings: SexTiming.end.bit);
      final c = DailyEntry(date: day);
      expect(a, isNot(equals(b)));
      expect(a, isNot(equals(c)));
      expect(a, equals(DailyEntry(date: day, sexTimings: 1)));
      expect(a.hashCode, DailyEntry(date: day, sexTimings: 1).hashCode);
    });

    test('entries differing only in cervixFirmness differ', () {
      final a = DailyEntry(date: day, cervixFirmness: CervixFirmness.hard);
      final b = DailyEntry(date: day, cervixFirmness: CervixFirmness.soft);
      final c = DailyEntry(date: day);
      expect(a, isNot(equals(b)));
      expect(a, isNot(equals(c)));
      expect(a.hashCode, isNot(equals(c.hashCode)));
      expect(
        a,
        equals(DailyEntry(date: day, cervixFirmness: CervixFirmness.hard)),
      );
      expect(
        a.hashCode,
        DailyEntry(date: day, cervixFirmness: CervixFirmness.hard).hashCode,
      );
    });

    test('a copyWith-modified new field participates in equality', () {
      final base = DailyEntry(
        date: day,
        cervixFirmness: CervixFirmness.halfSoft,
        sexTimings: 3,
      );
      final rebuilt = base.copyWith(
        cervixFirmness: CervixFirmness.halfSoft,
        sexTimings: 3,
      );
      expect(rebuilt, equals(base));
      expect(rebuilt.hashCode, base.hashCode);
    });
  });
}
