// Tests for the measurement-method vocabulary and the snapshot semantics in
// lib/domain/measurement_method.dart. The enum NAMES are the stable storage
// tokens (database + export), so the token-set test below pins them — a
// rename is a data migration.
import 'package:cycle_app/domain/date_only.dart';
import 'package:cycle_app/domain/measurement_method.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MeasurementRoute vocabulary', () {
    test('token set is exactly the four routes', () {
      expect(
        MeasurementRoute.values.map((r) => r.name),
        unorderedEquals(const ['vaginal', 'rectal', 'oral', 'other']),
      );
    });

    test('tryParseMeasurementRoute round-trips every token', () {
      for (final route in MeasurementRoute.values) {
        expect(tryParseMeasurementRoute(route.name), route);
      }
    });

    test('tryParseMeasurementRoute rejects unknown and non-string input', () {
      expect(tryParseMeasurementRoute('anal'), isNull);
      expect(tryParseMeasurementRoute('Vaginal'), isNull);
      expect(tryParseMeasurementRoute(''), isNull);
      expect(tryParseMeasurementRoute(null), isNull);
      expect(tryParseMeasurementRoute(3), isNull);
      expect(tryParseMeasurementRoute(Object()), isNull);
    });
  });

  group('normalizeThermometerName (the shared trim rule)', () {
    test('null stays null', () {
      expect(normalizeThermometerName(null), isNull);
    });

    test('whitespace-only input is no name', () {
      expect(normalizeThermometerName(''), isNull);
      expect(normalizeThermometerName('   '), isNull);
      expect(normalizeThermometerName(' \t\n '), isNull);
    });

    test('edge padding is trimmed, inner text survives', () {
      expect(normalizeThermometerName(' ThermaPen  '), 'ThermaPen');
      expect(normalizeThermometerName('ThermaPen'), 'ThermaPen');
    });
  });

  group('MeasurementMethodSnapshot construction', () {
    test('the date is normalized to UTC midnight (DateOnly convention)', () {
      final snapshot = MeasurementMethodSnapshot(
        date: DateTime(2026, 3, 1, 14, 30),
        route: MeasurementRoute.vaginal,
      );
      expect(snapshot.date, DateOnly.normalize(DateTime(2026, 3, 1)));
      expect(snapshot.date.isUtc, isTrue);
    });

    test('the thermometer arrives trimmed (blank collapses to null)', () {
      final padded = MeasurementMethodSnapshot(
        date: DateTime(2026, 3, 1),
        route: MeasurementRoute.oral,
        thermometer: '  ',
      );
      expect(padded.thermometer, isNull);

      final named = MeasurementMethodSnapshot(
        date: DateTime(2026, 3, 1),
        route: MeasurementRoute.oral,
        thermometer: ' ThermaPen ',
      );
      expect(named.thermometer, 'ThermaPen');
    });

    test('two snapshots for the same state are equal', () {
      final a = MeasurementMethodSnapshot(
        date: DateTime(2026, 3, 1),
        route: MeasurementRoute.rectal,
        thermometer: 'x',
      );
      final b = MeasurementMethodSnapshot(
        date: DateTime(2026, 3, 1, 5),
        route: MeasurementRoute.rectal,
        thermometer: 'x',
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });
  });

  group('effectiveMeasurementMethod picks the latest snapshot at or before '
      'the day', () {
    final baseline = MeasurementMethodSnapshot(
      date: DateTime(2026, 3, 1),
      route: MeasurementRoute.vaginal,
    );
    final change = MeasurementMethodSnapshot(
      date: DateTime(2026, 5, 10),
      route: MeasurementRoute.oral,
    );

    test('empty input has no effective state', () {
      expect(
        effectiveMeasurementMethod(const [], DateTime(2026, 3, 5)),
        isNull,
      );
    });

    test('a day before every snapshot has no effective state', () {
      expect(
        effectiveMeasurementMethod([baseline], DateTime(2026, 2, 28)),
        isNull,
      );
    });

    test('the day itself picks that snapshot', () {
      expect(
        effectiveMeasurementMethod([baseline], DateTime(2026, 3, 1, 12)),
        baseline,
      );
    });

    test('between snapshots the earlier one still applies', () {
      expect(
        effectiveMeasurementMethod([baseline, change], DateTime(2026, 4, 20)),
        baseline,
      );
    });

    test('from the change day on the later snapshot applies', () {
      expect(
        effectiveMeasurementMethod([
          baseline,
          change,
        ], DateTime(2026, 5, 10, 23)),
        change,
      );
      expect(
        effectiveMeasurementMethod([baseline, change], DateTime(2026, 6, 30)),
        change,
      );
    });

    test('the result is independent of the list order', () {
      final reversed = [change, baseline];
      final sorted = [baseline, change];
      for (final day in [
        DateTime(2026, 3, 2),
        DateTime(2026, 5, 10),
        DateTime(2026, 8, 1),
      ]) {
        expect(
          effectiveMeasurementMethod(reversed, day),
          effectiveMeasurementMethod(sorted, day),
        );
      }
    });
  });
}
