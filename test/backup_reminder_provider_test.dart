// Provider tests for the backup reminder over the in-memory drift database:
// the earliest tracked-data anchor and the due flag's interval, snooze,
// empty-database and in-memory-report behavior. The clock is pinned through
// nowProvider, so nothing sleeps.
import 'dart:async';

import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/domain/backup_reminder.dart';
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/platform/web_storage_status.dart';
import 'package:cycle_app/providers.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/database.dart';
import 'support/provider_fixtures.dart';

final fixedNow = DateTime.utc(2026, 10, 20, 10);

WebStorageStatus _inMemoryStatus() => const WebStorageStatus(
  backend: WebStorageBackend.inMemory,
  installedPwa: false,
  persistent: false,
  usageBytes: null,
  quotaBytes: null,
  userAgent: 'test-agent',
  missingFeatures: <String>{},
);

Future<void> _insertEntry(CycleDatabase db, {required DateTime createdAt}) => db
    .into(db.cycleEntries)
    .insert(
      CycleEntriesCompanion.insert(
        date: createdAt,
        createdAt: Value(createdAt),
        updatedAt: Value(createdAt),
      ),
    );

Future<void> _insertMethodSnapshot(
  CycleDatabase db, {
  required DateTime createdAt,
}) => db
    .into(db.measurementMethods)
    .insert(
      MeasurementMethodsCompanion.insert(
        date: createdAt,
        method: 'oral',
        createdAt: Value(createdAt),
        updatedAt: Value(createdAt),
      ),
    );

ProviderContainer _container({
  Future<void> Function(CycleDatabase db)? seed,
  DateTime? lastExportAt,
  BackupReminderInterval? interval,
  DateTime? snoozedUntil,
  DateTime Function()? now,
  Duration? refreshInterval,
  Future<WebStorageStatus?> Function()? report,
}) {
  final container = ProviderContainer(
    overrides: [
      inMemoryDatabase(seed: seed),
      webStorageReportProvider.overrideWith(
        (ref) => report?.call() ?? Future<WebStorageStatus?>.value(null),
      ),
      nowProvider.overrideWith((ref) => now ?? (() => fixedNow)),
      if (refreshInterval != null)
        backupReminderRefreshIntervalProvider.overrideWith(
          (ref) => refreshInterval,
        ),
      if (lastExportAt != null) lastExportAtPin(lastExportAt),
      if (interval != null) backupReminderIntervalPin(interval),
      if (snoozedUntil != null) backupReminderSnoozedUntilPin(snoozedUntil),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<bool> _isDue(
  ProviderContainer container, {
  bool awaitReport = true,
}) async {
  await container.read(earliestTrackedDataAtProvider.future);
  if (awaitReport) await container.read(webStorageReportProvider.future);
  return container.read(backupReminderDueProvider);
}

void main() {
  group('earliest tracked data anchor', () {
    test('is null for an empty database', () async {
      final container = _container();
      expect(
        await container.read(earliestTrackedDataAtProvider.future),
        isNull,
      );
    });

    test(
      'takes the minimum entry createdAt, not the earliest entry date',
      () async {
        final container = _container(
          seed: (db) async {
            await _insertEntry(db, createdAt: DateTime.utc(2026, 9, 1));
            await _insertEntry(db, createdAt: DateTime.utc(2026, 5, 1));
          },
        );
        expect(
          await container.read(earliestTrackedDataAtProvider.future),
          DateTime.utc(2026, 5, 1),
        );
      },
    );

    test('includes method snapshots', () async {
      final container = _container(
        seed: (db) async {
          await _insertEntry(db, createdAt: DateTime.utc(2026, 9, 1));
          await _insertMethodSnapshot(db, createdAt: DateTime.utc(2026, 6, 1));
        },
      );
      expect(
        await container.read(earliestTrackedDataAtProvider.future),
        DateTime.utc(2026, 6, 1),
      );
    });

    test('a marks-only database anchors at the earliest mark day', () async {
      final container = _container(
        seed: (db) => db.marksDao.addMark(
          DateTime.utc(2026, 4, 1),
          CycleMarkTypes.cycleStart,
        ),
      );
      expect(
        await container.read(earliestTrackedDataAtProvider.future),
        DateTime.utc(2026, 4, 1),
      );
    });
  });

  group('due flag', () {
    test('an old export with tracked data is due', () async {
      final container = _container(
        lastExportAt: DateTime.utc(2026, 6, 1),
        seed: (db) => _insertEntry(db, createdAt: DateTime.utc(2026, 9, 1)),
      );
      expect(await _isDue(container), isTrue);
    });

    test('a recent export is not due', () async {
      final container = _container(
        lastExportAt: DateTime.utc(2026, 9, 1),
        seed: (db) => _insertEntry(db, createdAt: DateTime.utc(2026, 9, 1)),
      );
      expect(await _isDue(container), isFalse);
    });

    test('never exported anchors at the earliest entry createdAt', () async {
      final container = _container(
        seed: (db) => _insertEntry(db, createdAt: DateTime.utc(2026, 5, 1)),
      );
      expect(await _isDue(container), isTrue);
    });

    test('a never-exported recent entry is not due', () async {
      final container = _container(
        seed: (db) => _insertEntry(db, createdAt: DateTime.utc(2026, 10, 1)),
      );
      expect(await _isDue(container), isFalse);
    });

    test(
      'a marks-only database becomes due from the earliest mark day',
      () async {
        final container = _container(
          seed: (db) => db.marksDao.addMark(
            DateTime.utc(2026, 4, 1),
            CycleMarkTypes.cycleStart,
          ),
        );
        expect(await _isDue(container), isTrue);
      },
    );

    test('an empty database is not due', () async {
      final container = _container(lastExportAt: DateTime.utc(2020, 1, 1));
      expect(await _isDue(container), isFalse);
    });

    test('off is not due even with old data and an old export', () async {
      final container = _container(
        interval: BackupReminderInterval.off,
        lastExportAt: DateTime.utc(2020, 1, 1),
        seed: (db) => _insertEntry(db, createdAt: DateTime.utc(2026, 9, 1)),
      );
      expect(await _isDue(container), isFalse);
    });

    test('a snooze hides the reminder', () async {
      final container = _container(
        lastExportAt: DateTime.utc(2026, 6, 1),
        snoozedUntil: DateTime.utc(2026, 10, 27),
        seed: (db) => _insertEntry(db, createdAt: DateTime.utc(2026, 9, 1)),
      );
      expect(await _isDue(container), isFalse);
    });

    test('an expired snooze resumes the same anchor', () async {
      final container = _container(
        lastExportAt: DateTime.utc(2026, 6, 1),
        snoozedUntil: DateTime.utc(2026, 10, 20, 10),
        seed: (db) => _insertEntry(db, createdAt: DateTime.utc(2026, 9, 1)),
      );
      expect(await _isDue(container), isTrue);
    });

    test('an in-memory storage report suppresses the reminder', () async {
      final container = _container(
        lastExportAt: DateTime.utc(2026, 6, 1),
        report: () async => _inMemoryStatus(),
        seed: (db) => _insertEntry(db, createdAt: DateTime.utc(2026, 9, 1)),
      );
      expect(await _isDue(container), isFalse);
    });

    test('a loading storage report is not due yet', () async {
      final container = _container(
        lastExportAt: DateTime.utc(2026, 6, 1),
        report: () => Completer<WebStorageStatus?>().future,
        seed: (db) => _insertEntry(db, createdAt: DateTime.utc(2026, 9, 1)),
      );
      expect(await _isDue(container, awaitReport: false), isFalse);
    });

    test('a refreshing storage report keeps the previous answer', () async {
      var loads = 0;
      final refresh = Completer<WebStorageStatus?>();
      final container = _container(
        lastExportAt: DateTime.utc(2026, 6, 1),
        report: () => ++loads == 1
            ? Future<WebStorageStatus?>.value(null)
            : refresh.future,
        seed: (db) => _insertEntry(db, createdAt: DateTime.utc(2026, 9, 1)),
      );
      expect(await _isDue(container), isTrue);

      container.invalidate(webStorageReportProvider);
      expect(
        container.read(backupReminderDueProvider),
        isTrue,
        reason: 'a refresh must not hide the banner behind a loading state',
      );
      refresh.complete(null);
      await container.read(webStorageReportProvider.future);
    });

    test('a refreshing anchor keeps the previous answer', () async {
      final container = _container(
        lastExportAt: DateTime.utc(2026, 6, 1),
        seed: (db) => _insertEntry(db, createdAt: DateTime.utc(2026, 9, 1)),
      );
      expect(await _isDue(container), isTrue);

      container.invalidate(earliestTrackedDataAtProvider);
      expect(
        container.read(backupReminderDueProvider),
        isTrue,
        reason: 'a refresh must not hide the banner behind a loading state',
      );
      await container.read(earliestTrackedDataAtProvider.future);
    });

    test('re-evaluates on the refresh tick while the app stays open', () async {
      var now = fixedNow;
      final container = _container(
        interval: BackupReminderInterval.monthly,
        lastExportAt: fixedNow,
        refreshInterval: const Duration(milliseconds: 5),
        now: () => now,
        seed: (db) => _insertEntry(db, createdAt: DateTime.utc(2026, 9, 1)),
      );
      expect(await _isDue(container), isFalse);

      final due = Completer<void>();
      final subscription = container.listen(backupReminderDueProvider, (
        _,
        next,
      ) {
        if (next && !due.isCompleted) due.complete();
      });
      addTearDown(subscription.close);

      now = DateTime.utc(2026, 11, 21);
      await due.future.timeout(const Duration(seconds: 5));
      expect(container.read(backupReminderDueProvider), isTrue);
    });
  });
}
