// Pure-Dart tests for the DailyEntry domain model's measured-time rule:
// the time of day is metadata OF the temperature measurement, so a
// DailyEntry never carries a measuredAtMinutes without a bbtC — the
// constructor normalizes (drops) the time, and copyWith/equality inherit
// that. DB mappers, the export/import writers and any future writer all
// build DailyEntries, so they cannot store a stray time either.
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
}
