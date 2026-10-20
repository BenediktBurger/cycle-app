/// The backup-reminder presets offered in Settings: Off, Monthly, Quarterly
/// (the default) and Half-yearly.
///
/// The enum names double as the persisted tokens, so renaming a value would
/// orphan stored choices; the settings store decodes unknown tokens to the
/// default instead.
enum BackupReminderInterval { off, monthly, quarterly, halfYearly }

extension BackupReminderIntervalMonths on BackupReminderInterval {
  /// Calendar-month step per preset; `off` is never due.
  int get months => switch (this) {
    BackupReminderInterval.off => 0,
    BackupReminderInterval.monthly => 1,
    BackupReminderInterval.quarterly => 3,
    BackupReminderInterval.halfYearly => 6,
  };
}

/// True when tracked data exists and [now] has reached the end of the interval
/// anchored at [lastExportAt] (or, when never exported, at
/// [earliestTrackedDataAt]). A snooze hides the reminder only while [now] is
/// before [snoozedUntil]; it never moves the anchor.
bool isBackupReminderDue({
  required BackupReminderInterval interval,
  required DateTime? lastExportAt,
  required DateTime? earliestTrackedDataAt,
  required DateTime? snoozedUntil,
  required DateTime now,
}) {
  if (interval == BackupReminderInterval.off) return false;
  if (earliestTrackedDataAt == null) return false;
  final anchor = lastExportAt ?? earliestTrackedDataAt;
  final nowUtc = now.toUtc();
  final snoozeEnd = snoozedUntil?.toUtc();
  if (snoozeEnd != null && nowUtc.isBefore(snoozeEnd)) return false;
  return !nowUtc.isBefore(_addCalendarMonths(anchor.toUtc(), interval.months));
}

/// Adds calendar months in UTC, clamping the day to the target month's last
/// day (31 January + 1 month is 28/29 February).
DateTime _addCalendarMonths(DateTime instant, int months) {
  final targetMonth = instant.month - 1 + months;
  final year = instant.year + targetMonth ~/ 12;
  final month = targetMonth % 12 + 1;
  final lastDay = DateTime.utc(year, month + 1, 0).day;
  return DateTime.utc(
    year,
    month,
    instant.day > lastDay ? lastDay : instant.day,
    instant.hour,
    instant.minute,
    instant.second,
    instant.millisecond,
    instant.microsecond,
  );
}
