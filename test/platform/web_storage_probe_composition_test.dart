import 'dart:async';

import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/platform/browser_storage.dart';
import 'package:cycle_app/platform/web_storage_status.dart';
import 'package:cycle_app/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/database.dart';

void main() {
  group('unavailable browser APIs', () {
    test(
      'degrade a missing persistence API to unknown, not an error',
      () async {
        final status = composeWebStorageStatus(
          WebStorageBackend.opfs,
          await probeBrowserStorage(),
        );

        expect(status.persistent, isNull);
        expect(status.missingFeatures, contains(WebStorageFeature.persistence));
      },
    );

    test('degrade an unavailable estimate to unknown bytes', () async {
      final status = composeWebStorageStatus(
        WebStorageBackend.opfs,
        await probeBrowserStorage(),
      );

      expect(status.usageBytes, isNull);
      expect(status.quotaBytes, isNull);
      expect(status.missingFeatures, contains(WebStorageFeature.estimate));
    });
  });

  group('explicit persistence request', () {
    test('merges a granted result into the status', () {
      final status = composeWebStorageStatus(
        WebStorageBackend.opfs,
        const WebStorageProbe(
          installedPwa: false,
          persistent: null,
          usageBytes: null,
          quotaBytes: null,
          userAgent: '',
          missingFeatures: {WebStorageFeature.persistence},
        ),
      );

      final merged = status.withPersistentResult(true);

      expect(merged.persistent, isTrue);
      expect(
        merged.missingFeatures,
        isNot(contains(WebStorageFeature.persistence)),
      );
    });

    test('a denied request answers false without throwing', () async {
      expect(await requestPersistentStorage(), isFalse);
    });
  });

  group('webStorageReportProvider', () {
    test('returns no status on a native build', () async {
      final container = ProviderContainer(overrides: [inMemoryDatabase()]);
      addTearDown(container.dispose);

      expect(await container.read(webStorageReportProvider.future), isNull);
    });

    test('produces no status before the database opens', () async {
      final gate = Completer<CycleDatabase>();
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWith((ref) async {
            final db = await gate.future;
            ref.onDispose(db.close);
            return db;
          }),
        ],
      );
      addTearDown(container.dispose);

      var completed = false;
      final report = container.read(webStorageReportProvider.future);
      unawaited(report.then((_) => completed = true));
      await Future<void>.delayed(Duration.zero);

      expect(completed, isFalse);

      gate.complete(inMemoryCycleDatabase());
      expect(await report, isNull);
    });
  });
}
