// Pure due-logic tests for the backup reminder: preset boundaries, calendar
// month clamping, UTC instants, the never-exported anchor and snooze.
import 'package:cycle_app/domain/backup_reminder.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime _utc(int year, int month, int day, [int hour = 0]) =>
    DateTime.utc(year, month, day, hour);

bool _due({
  BackupReminderInterval interval = BackupReminderInterval.quarterly,
  DateTime? lastExportAt,
  DateTime? earliestTrackedDataAt,
  DateTime? snoozedUntil,
  required DateTime now,
  bool trackedData = true,
}) => isBackupReminderDue(
  interval: interval,
  lastExportAt: lastExportAt,
  earliestTrackedDataAt: trackedData
      ? earliestTrackedDataAt ?? _utc(2020, 1, 1)
      : null,
  snoozedUntil: snoozedUntil,
  now: now,
);

void main() {
  test('off is never due, even with old data', () {
    expect(
      _due(
        interval: BackupReminderInterval.off,
        earliestTrackedDataAt: _utc(2020, 1, 1),
        now: _utc(2026, 10, 20),
      ),
      isFalse,
    );
  });

  test('no tracked data and no export is never due', () {
    expect(_due(trackedData: false, now: _utc(2026, 10, 20)), isFalse);
  });

  test('no tracked data is not due even after an old export', () {
    expect(
      _due(
        trackedData: false,
        lastExportAt: _utc(2020, 1, 1),
        now: _utc(2026, 10, 20),
      ),
      isFalse,
    );
  });

  test('a recent export is not due', () {
    expect(
      _due(
        lastExportAt: _utc(2026, 9, 1),
        earliestTrackedDataAt: _utc(2020, 1, 1),
        now: _utc(2026, 10, 20),
      ),
      isFalse,
    );
  });

  test('never exported anchors at the earliest tracked data', () {
    expect(
      _due(earliestTrackedDataAt: _utc(2026, 7, 21), now: _utc(2026, 10, 20)),
      isFalse,
    );
    expect(
      _due(earliestTrackedDataAt: _utc(2026, 7, 20), now: _utc(2026, 10, 20)),
      isTrue,
    );
  });

  group('preset boundaries are inclusive', () {
    for (final (interval, months) in [
      (BackupReminderInterval.monthly, 1),
      (BackupReminderInterval.quarterly, 3),
      (BackupReminderInterval.halfYearly, 6),
    ]) {
      test('${interval.name} is due at the end and not one second before', () {
        final anchor = _utc(2026, 1, 15, 10);
        expect(
          _due(
            interval: interval,
            lastExportAt: anchor,
            now: _utc(
              2026,
              1 + months,
              15,
              10,
            ).subtract(const Duration(seconds: 1)),
          ),
          isFalse,
          reason: '${interval.name} must not be due early',
        );
        expect(
          _due(
            interval: interval,
            lastExportAt: anchor,
            now: _utc(2026, 1 + months, 15, 10),
          ),
          isTrue,
          reason: 'the interval end is inclusive',
        );
      });
    }
  });

  test('compares instants in UTC regardless of the DateTime form', () {
    final anchor = _utc(2026, 1, 15, 10);
    final end = _utc(2026, 2, 15, 10);
    expect(
      _due(
        interval: BackupReminderInterval.monthly,
        lastExportAt: anchor,
        now: end.toLocal(),
      ),
      isTrue,
    );
  });

  group('calendar-month steps clamp to month end', () {
    test('31 January + 1 month is the last February day', () {
      expect(
        _due(
          interval: BackupReminderInterval.monthly,
          lastExportAt: _utc(2024, 1, 31, 12),
          now: _utc(2024, 2, 28, 12),
        ),
        isFalse,
        reason: '2024 is a leap year, so the clamp target is 29 February',
      );
      expect(
        _due(
          interval: BackupReminderInterval.monthly,
          lastExportAt: _utc(2024, 1, 31, 12),
          now: _utc(2024, 2, 29, 12),
        ),
        isTrue,
      );
      expect(
        _due(
          interval: BackupReminderInterval.monthly,
          lastExportAt: _utc(2026, 1, 31, 12),
          now: _utc(2026, 2, 28, 12),
        ),
        isTrue,
        reason: '2026 is not a leap year, so the clamp target is 28 February',
      );
    });

    test('31 March + 1 month is 30 April', () {
      expect(
        _due(
          interval: BackupReminderInterval.monthly,
          lastExportAt: _utc(2026, 3, 31, 12),
          now: _utc(2026, 4, 30, 12),
        ),
        isTrue,
      );
      expect(
        _due(
          interval: BackupReminderInterval.monthly,
          lastExportAt: _utc(2026, 3, 31, 12),
          now: _utc(2026, 5, 1, 12),
        ),
        isTrue,
      );
    });

    test('31 August + 6 months is the last February day', () {
      expect(
        _due(
          interval: BackupReminderInterval.halfYearly,
          lastExportAt: _utc(2026, 8, 31, 12),
          now: _utc(2027, 2, 28, 12),
        ),
        isTrue,
      );
      expect(
        _due(
          interval: BackupReminderInterval.halfYearly,
          lastExportAt: _utc(2026, 8, 31, 12),
          now: _utc(2027, 2, 27, 12),
        ),
        isFalse,
      );
    });
  });

  group('snooze', () {
    final anchor = _utc(2026, 1, 1);

    test('suppresses while now is before the snooze end', () {
      expect(
        _due(
          lastExportAt: anchor,
          snoozedUntil: _utc(2026, 10, 27),
          now: _utc(2026, 10, 20),
        ),
        isFalse,
      );
    });

    test('resumes at the snooze end', () {
      expect(
        _due(
          lastExportAt: anchor,
          snoozedUntil: _utc(2026, 10, 20),
          now: _utc(2026, 10, 20),
        ),
        isTrue,
      );
    });

    test('an expired snooze resumes the same anchor', () {
      // If the snooze restarted the interval, 5 April + 3 months would be
      // 5 July and this instant would still be hidden.
      expect(
        _due(
          lastExportAt: anchor,
          snoozedUntil: _utc(2026, 4, 5),
          now: _utc(2026, 4, 5),
        ),
        isTrue,
      );
    });
  });
}
