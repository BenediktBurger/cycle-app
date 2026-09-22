// Pure-Dart unit tests of the date helpers the cycle chart relies on —
// here specifically the weekend detection used for color-highlit weekend
// columns: derivation must come from the real calendar date
// (DateTime.weekday), never from a list index.
import 'package:cycle_app/domain/date_only.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DateOnly.isWeekend', () {
    // 2026-09-04 is a Friday; 05/06 fall on the weekend, 07 is a Monday.
    test('marks Saturday and Sunday, spans other weekdays correctly', () {
      expect(
        DateOnly.isWeekend(DateTime(2026, 9, 4)),
        isFalse,
        reason: 'Friday',
      );
      expect(
        DateOnly.isWeekend(DateTime(2026, 9, 5)),
        isTrue,
        reason: 'Saturday',
      );
      expect(
        DateOnly.isWeekend(DateTime(2026, 9, 6)),
        isTrue,
        reason: 'Sunday',
      );
      expect(
        DateOnly.isWeekend(DateTime(2026, 9, 7)),
        isFalse,
        reason: 'Monday',
      );
    });

    test('is calendar-date based: normalization cannot shift the weekday', () {
      // Midnight disagreements (local 23:00 vs UTC 00:00 of the same day)
      // must resolve to the same weekend verdict.
      final saturdayUtcMidnight = DateTime.utc(2026, 9, 5);
      final saturdayLocalLate = DateTime(
        2026,
        9,
        5,
        13,
        37,
      ); // September afternoon, same day
      expect(
        DateOnly.isWeekend(saturdayUtcMidnight),
        DateOnly.isWeekend(saturdayLocalLate),
      );
      expect(DateOnly.isWeekend(saturdayLocalLate), isTrue);
    });
  });
}
