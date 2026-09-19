// Pure-Dart tests for the DailyEntry domain model: the measured-time rule
// (time of day is metadata OF the temperature measurement, so a DailyEntry
// never carries a measuredAtMinutes without a bbtC — the constructor
// normalizes/drops the time, and copyWith/equality inherit that), the
// sex-time bitmask, the cervix firmness fields, and the
// temp_disturbances mask (the NER-aligned raw-data disturbance flags
// sp/a/alk/kr — an int mask 0..15; the ANALYSIS exclusion is no longer
// driven by entry flags but by the ignoreTemperature mark, see
// lib/domain/cycle_grouping.dart). DB mappers, the export/import writers
// and any future writer all build DailyEntries, so they cannot store a
// stray time or an out-of-range mask either.
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
      expect(entry.copyWith(painBreast: true).sexTimings, 2);
      expect(entry.copyWith(sexTimings: 7).sexTimings, 7);
      expect(
        DailyEntry(date: day).copyWith(sexTimings: 0).sexTimings,
        0,
        reason: 'explicit 0 is a valid value, not an "unset" request',
      );
    });
  });

  group('TempDisturbance bitmask', () {
    test('bits follow the numeric-flag pattern (1/2/4/8)', () {
      expect(TempDisturbance.sp.bit, 1);
      expect(TempDisturbance.a.bit, 2);
      expect(TempDisturbance.alk.bit, 4);
      expect(TempDisturbance.kr.bit, 8);
    });

    test('token set is exactly the four disturbance flags (Reise is gone)', () {
      expect(
        TempDisturbance.values.map((t) => t.token),
        unorderedEquals(const ['sp', 'a', 'alk', 'kr']),
      );
    });

    test('bits are pairwise disjoint (a mask can name each combination)', () {
      final bits = TempDisturbance.values.map((t) => t.bit).toSet();
      expect(bits.length, TempDisturbance.values.length);
      for (final a in TempDisturbance.values) {
        for (final b in TempDisturbance.values) {
          if (a == b) continue;
          expect(a.bit & b.bit, 0,
              reason: '${a.name} and ${b.name} must be independent flags');
        }
      }
    });
  });

  group('tryParseTempDisturbances (storage & export lanes)', () {
    test('int masks inside 0..15 pass through verbatim', () {
      expect(tryParseTempDisturbances(0), 0);
      expect(tryParseTempDisturbances(1), 1);
      expect(tryParseTempDisturbances(3), 3);
      expect(tryParseTempDisturbances(15), 15);
    });

    test('junk collapses to 0 — never a row killer', () {
      // Out-of-range, negative, and non-int values are not representable
      // disturbances: they collapse to the neutral mask 0, mirroring the
      // lenient collapse of the other coercible fields (mucus tokens,
      // sex_timings), so foreign/legacy data never invalidates a row.
      for (final junk in <Object?>[16, 999, -1, '2', true, 36.5, null]) {
        expect(tryParseTempDisturbances(junk), 0, reason: 'junk: $junk');
      }
    });
  });

  group('tempDisturbances field', () {
    test('defaults to 0 — no disturbance recorded', () {
      expect(DailyEntry(date: day).tempDisturbances, 0);
    });

    test('single and combined bits are stored verbatim (OR semantics)', () {
      expect(
          DailyEntry(date: day, tempDisturbances: TempDisturbance.sp.bit)
              .tempDisturbances,
          1);
      final twice = DailyEntry(
        date: day,
        tempDisturbances: TempDisturbance.alk.bit | TempDisturbance.kr.bit,
      );
      expect(twice.tempDisturbances, 12,
          reason: 'multiple bits = multiple disturbances on the same day');
    });

    test('every mask 0..15 is representable, and only those', () {
      for (var mask = 0; mask <= 15; mask++) {
        expect(DailyEntry(date: day, tempDisturbances: mask).tempDisturbances,
            mask);
      }
      expect(
        () => DailyEntry(date: day, tempDisturbances: 16),
        throwsA(isA<AssertionError>()),
        reason: '16 is outside the 4-bit vocabulary',
      );
      expect(
        () => DailyEntry(date: day, tempDisturbances: -1),
        throwsA(isA<AssertionError>()),
        reason: 'negative masks are outside the vocabulary',
      );
    });

    test('isInterrupted is mask != 0 (raw data, not analysis exclusion)', () {
      expect(DailyEntry(date: day).isInterrupted, isFalse);
      for (var mask = 1; mask <= 15; mask++) {
        expect(
            DailyEntry(date: day, tempDisturbances: mask).isInterrupted, isTrue,
            reason: 'mask $mask carries a disturbance flag');
      }
      // The mask is RAW data: it does not drive analysis exclusion (see
      // cycle_grouping/evaluation — the ignoreTemperature mark does).
    });

    test('copyWith keeps the mask unless given', () {
      final entry = DailyEntry(date: day, tempDisturbances: 5);
      expect(entry.copyWith().tempDisturbances, 5);
      expect(entry.copyWith(painBreast: true).tempDisturbances, 5);
      expect(entry.copyWith(tempDisturbances: 0).tempDisturbances, 0,
          reason: 'explicit 0 is a valid value, not an "unset" request');
      expect(
        DailyEntry(date: day).copyWith(tempDisturbances: 15).tempDisturbances,
        15,
      );
    });

    test('equality/hashCode include the mask', () {
      expect(
        DailyEntry(date: day, tempDisturbances: 3),
        DailyEntry(date: day, tempDisturbances: 3),
      );
      expect(
        DailyEntry(date: day, tempDisturbances: 3).hashCode,
        DailyEntry(date: day, tempDisturbances: 3).hashCode,
      );
      expect(
        DailyEntry(date: day, tempDisturbances: 1),
        isNot(DailyEntry(date: day, tempDisturbances: 2)),
      );
      expect(
        DailyEntry(date: day, tempDisturbances: 1),
        isNot(DailyEntry(date: day)),
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
      expect(entry.copyWith(painBreast: true).cervixFirmness,
          CervixFirmness.halfSoft);
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
