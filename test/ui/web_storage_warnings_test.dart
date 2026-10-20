// Widget tests of the web-only storage warnings: the one-time in-memory
// test-mode dialog plus its persistent banner, the unsafe-IndexedDB
// multi-tab banner, and the session-dismissible iOS install hint. The
// warning widget takes an injected status, so no browser API or kIsWeb is
// involved; the dismissal flags live in ProviderContainer-scoped providers.
import 'package:cycle_app/l10n/app_localizations.dart';
import 'package:cycle_app/platform/web_storage_status.dart';
import 'package:cycle_app/providers.dart';
import 'package:cycle_app/ui/web_storage_warnings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/database.dart';

const Locale _german = Locale('de');

const String _iosSafariUserAgent =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 '
    'Safari/604.1';

const String _androidUserAgent =
    'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36';

final Finder _inMemoryDialog = _key('inMemoryWarningDialog');
final Finder _inMemoryBanner = _key('inMemoryWarningBanner');
final Finder _unsafeIndexedDbBanner = _key('unsafeIndexedDbBanner');
final Finder _installHintBanner = _key('installHintBanner');
final Finder _installHintDismiss = _key('installHintDismiss');
final Finder _inMemoryDismiss = _key('inMemoryWarningDismiss');

Finder _key(String name) => find.byKey(ValueKey(name));

WebStorageStatus _status({
  WebStorageBackend backend = WebStorageBackend.opfs,
  bool installedPwa = true,
  bool? persistent = false,
  String userAgent = 'test-agent',
}) => WebStorageStatus(
  backend: backend,
  installedPwa: installedPwa,
  persistent: persistent,
  usageBytes: null,
  quotaBytes: null,
  userAgent: userAgent,
  missingFeatures: const {},
);

ProviderContainer _container() {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  return container;
}

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer container,
  WebStorageStatus? status,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: _german,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Column(
            children: [
              WebStorageWarnings(status: status),
              const Expanded(child: Text('entry form')),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('in-memory test mode', () {
    testWidgets('shows the dialog once per run and keeps the banner after '
        'dismissal', (tester) async {
      final container = _container();
      final inMemory = _status(backend: WebStorageBackend.inMemory);

      await _pump(tester, container, inMemory);

      expect(_inMemoryDialog, findsOneWidget);
      expect(
        _inMemoryBanner,
        findsOneWidget,
        reason: 'the persistent banner is independent of the one-time dialog',
      );
      expect(container.read(inMemoryWarningShownProvider), isTrue);

      await tester.tap(_inMemoryDismiss);
      await tester.pumpAndSettle();

      expect(_inMemoryDialog, findsNothing);
      expect(
        _inMemoryBanner,
        findsOneWidget,
        reason: 'dismissing the dialog must not hide the test-mode banner',
      );

      await _pump(tester, container, inMemory);
      expect(
        _inMemoryDialog,
        findsNothing,
        reason: 'the dialog is shown once per app run, not per rebuild',
      );
      expect(_inMemoryBanner, findsOneWidget);
    });

    testWidgets('a new app run shows the dialog again', (tester) async {
      final firstRun = _container();
      await _pump(
        tester,
        firstRun,
        _status(backend: WebStorageBackend.inMemory),
      );
      expect(_inMemoryDialog, findsOneWidget);
      await tester.tap(_inMemoryDismiss);
      await tester.pumpAndSettle();

      // Tear the tree down so the warning state cannot be reused.
      await tester.pumpWidget(const SizedBox());

      final secondRun = _container();
      await _pump(
        tester,
        secondRun,
        _status(backend: WebStorageBackend.inMemory),
      );

      expect(
        _inMemoryDialog,
        findsOneWidget,
        reason: 'the shown flag is per app run, not persisted',
      );
    });

    testWidgets('entry stays possible and no route blocks the app after '
        'dismissal', (tester) async {
      final container = _container();
      await _pump(
        tester,
        container,
        _status(backend: WebStorageBackend.inMemory),
      );

      expect(find.text('entry form'), findsOneWidget);

      await tester.tap(_inMemoryDismiss);
      await tester.pumpAndSettle();

      expect(find.text('entry form'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        Navigator.of(tester.element(find.text('entry form'))).canPop(),
        isFalse,
        reason: 'dismissal leaves no route blocking the app',
      );
      expect(_inMemoryDialog, findsNothing);
      expect(
        container.read(inMemoryWarningShownProvider),
        isTrue,
        reason: 'the dismissal is recorded without a navigation change',
      );
    });
  });

  group('unsafe IndexedDB', () {
    testWidgets('shows the multiple-tabs banner', (tester) async {
      final container = _container();
      await _pump(
        tester,
        container,
        _status(
          backend: WebStorageBackend.unsafeIndexedDb,
          userAgent: _androidUserAgent,
        ),
      );

      expect(_unsafeIndexedDbBanner, findsOneWidget);
      expect(find.textContaining('Tab'), findsOneWidget);
      expect(_inMemoryDialog, findsNothing);
      expect(_installHintBanner, findsNothing);
    });
  });

  group('iOS install hint', () {
    testWidgets('shows on iOS Safari without install or persistence', (
      tester,
    ) async {
      for (final persistent in [false, null]) {
        final container = _container();
        await _pump(
          tester,
          container,
          _status(
            installedPwa: false,
            persistent: persistent,
            userAgent: _iosSafariUserAgent,
          ),
        );

        expect(
          _installHintBanner,
          findsOneWidget,
          reason: 'persistent $persistent does not confirm durability',
        );
      }
    });

    testWidgets('hides on non-iOS, installed, persistent and in-memory', (
      tester,
    ) async {
      final hidden = [
        _status(installedPwa: false, userAgent: _androidUserAgent),
        _status(installedPwa: true, userAgent: _iosSafariUserAgent),
        _status(
          installedPwa: false,
          persistent: true,
          userAgent: _iosSafariUserAgent,
        ),
        _status(
          backend: WebStorageBackend.inMemory,
          installedPwa: false,
          userAgent: _iosSafariUserAgent,
        ),
      ];

      for (final status in hidden) {
        final container = _container();
        await _pump(tester, container, status);
        expect(
          _installHintBanner,
          findsNothing,
          reason:
              '${status.backend.name}, installed '
              '${status.installedPwa}, persistent ${status.persistent}',
        );
      }
    });

    testWidgets('dismissal survives rebuilds for the session only', (
      tester,
    ) async {
      final container = _container();
      final hint = _status(installedPwa: false, userAgent: _iosSafariUserAgent);

      await _pump(tester, container, hint);
      expect(_installHintBanner, findsOneWidget);

      await tester.tap(_installHintDismiss);
      await tester.pumpAndSettle();

      expect(_installHintBanner, findsNothing);
      expect(container.read(installHintDismissedProvider), isTrue);

      await _pump(tester, container, hint);
      expect(
        _installHintBanner,
        findsNothing,
        reason: 'the dismissal is in-memory state and survives rebuilds',
      );

      await tester.pumpWidget(const SizedBox());
      final nextRun = _container();
      await _pump(tester, nextRun, hint);
      expect(
        _installHintBanner,
        findsOneWidget,
        reason: 'a session dismissal is not a persisted setting',
      );
    });
  });

  group('no warning', () {
    testWidgets('null status renders nothing', (tester) async {
      final container = _container();
      await _pump(tester, container, null);

      expect(find.byType(AlertDialog), findsNothing);
      expect(_inMemoryBanner, findsNothing);
      expect(_unsafeIndexedDbBanner, findsNothing);
      expect(_installHintBanner, findsNothing);
      expect(
        find.text('entry form'),
        findsOneWidget,
        reason: 'a null report leaves the body untouched',
      );
    });

    testWidgets('a healthy OPFS status renders nothing', (tester) async {
      final container = _container();
      await _pump(tester, container, _status());

      expect(find.byType(AlertDialog), findsNothing);
      expect(_inMemoryBanner, findsNothing);
      expect(_unsafeIndexedDbBanner, findsNothing);
      expect(_installHintBanner, findsNothing);
    });

    testWidgets('the native shell renders none of the warnings', (
      tester,
    ) async {
      await tester.pumpWidget(appScope(locale: _german));
      await tester.pumpAndSettle();

      expect(_inMemoryDialog, findsNothing);
      expect(_inMemoryBanner, findsNothing);
      expect(_unsafeIndexedDbBanner, findsNothing);
      expect(_installHintBanner, findsNothing);
    });
  });

  group('host', () {
    testWidgets('renders the live report and nothing while it is null', (
      tester,
    ) async {
      Widget hostWith(WebStorageStatus? report) => ProviderScope(
        // Overrides only apply when the scope's container is created.
        key: UniqueKey(),
        overrides: [
          webStorageReportProvider.overrideWith((ref) async => report),
        ],
        child: MaterialApp(
          locale: _german,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: WebStorageWarningsHost()),
        ),
      );

      await tester.pumpWidget(hostWith(null));
      await tester.pumpAndSettle();
      expect(_unsafeIndexedDbBanner, findsNothing);

      await tester.pumpWidget(
        hostWith(
          _status(
            backend: WebStorageBackend.unsafeIndexedDb,
            userAgent: _androidUserAgent,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_unsafeIndexedDbBanner, findsOneWidget);
    });
  });
}
