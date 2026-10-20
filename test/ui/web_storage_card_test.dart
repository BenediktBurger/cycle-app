// Widget tests of the Settings pane's browser-storage card: the presentational
// widget renders injected statuses, the two actions go through their injected
// seams, and native renders no card (kIsWeb is false on the VM).
import 'package:cycle_app/l10n/app_localizations.dart';
import 'package:cycle_app/platform/web_storage_status.dart';
import 'package:cycle_app/providers.dart';
import 'package:cycle_app/ui/settings/web_storage_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/database.dart';
import '../support/viewport.dart';

const Locale _german = Locale('de');
final Finder _card = _key('webStorageCard');
final Finder _makePersistentButton = _key('webStorageMakePersistentButton');
final Finder _copyDiagnosticsButton = _key('webStorageCopyDiagnosticsButton');

Finder _key(String name) => find.byKey(ValueKey(name));

WebStorageStatus status({
  WebStorageBackend backend = WebStorageBackend.opfs,
  bool installedPwa = true,
  bool? persistent = false,
  int? usageBytes = 2 * 1024 * 1024,
  int? quotaBytes = 10 * 1024 * 1024,
  String userAgent = 'test-agent',
  Set<String> missingFeatures = const {},
}) => WebStorageStatus(
  backend: backend,
  installedPwa: installedPwa,
  persistent: persistent,
  usageBytes: usageBytes,
  quotaBytes: quotaBytes,
  userAgent: userAgent,
  missingFeatures: missingFeatures,
);

Future<void> pumpCard(
  WidgetTester tester,
  WebStorageStatus status, {
  DateTime? lastExportAt,
  Future<bool> Function()? onMakePersistent,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: _german,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: WebStorageCard(
            status: status,
            lastExportAt: lastExportAt,
            onMakePersistent: onMakePersistent ?? () async => true,
          ),
        ),
      ),
    ),
  );
}

ButtonStyleButton persistenceButton(WidgetTester tester) =>
    tester.widget<ButtonStyleButton>(_makePersistentButton);

void main() {
  group('reported facts', () {
    testWidgets('renders the installed-PWA answer', (tester) async {
      await pumpCard(tester, status(installedPwa: true));
      expect(find.text('Als App installiert: ja'), findsOneWidget);

      await pumpCard(tester, status(installedPwa: false));
      expect(find.text('Als App installiert: nein'), findsOneWidget);
    });

    testWidgets('renders the persistence answer, including unknown', (
      tester,
    ) async {
      await pumpCard(tester, status(persistent: true));
      expect(find.text('Dauerhafter Speicher: ja'), findsOneWidget);

      await pumpCard(tester, status(persistent: false));
      expect(find.text('Dauerhafter Speicher: nein'), findsOneWidget);

      await pumpCard(
        tester,
        status(
          persistent: null,
          missingFeatures: const {WebStorageFeature.persistence},
        ),
      );
      expect(find.text('Dauerhafter Speicher: unbekannt'), findsOneWidget);
    });

    testWidgets('labels every backend', (tester) async {
      const labels = {
        WebStorageBackend.opfs: 'OPFS',
        WebStorageBackend.sharedIndexedDb: 'Geteilte IndexedDB',
        WebStorageBackend.unsafeIndexedDb: 'IndexedDB ohne Mehr-Tab-Schutz',
        WebStorageBackend.inMemory: 'Nur im Arbeitsspeicher',
        WebStorageBackend.unknown: 'Unbekannt',
      };
      for (final entry in labels.entries) {
        await pumpCard(tester, status(backend: entry.key));
        expect(
          find.text('Speicher-Backend: ${entry.value}'),
          findsOneWidget,
          reason: '${entry.key.name} has its own localized label',
        );
      }
    });

    testWidgets('renders the byte estimate and degrades to unknown', (
      tester,
    ) async {
      await pumpCard(
        tester,
        status(usageBytes: 1536 * 1024, quotaBytes: 10 * 1024 * 1024),
      );
      expect(
        find.text('Geschätzter Speicher: 1.5 MB von 10 MB'),
        findsOneWidget,
      );

      await pumpCard(tester, status(usageBytes: 1536 * 1024, quotaBytes: null));
      expect(find.text('Geschätzter Speicher: 1.5 MB'), findsOneWidget);

      await pumpCard(tester, status(usageBytes: null, quotaBytes: null));
      expect(find.text('Geschätzter Speicher: unbekannt'), findsOneWidget);
    });

    testWidgets('renders the last-export seam, defaulting to never', (
      tester,
    ) async {
      await pumpCard(tester, status());
      expect(find.text('Letzter Export: nie'), findsOneWidget);

      await pumpCard(tester, status(), lastExportAt: DateTime.utc(2026, 4, 26));
      expect(find.text('Letzter Export: 2026-04-26'), findsOneWidget);
    });
  });

  group('persistence action', () {
    testWidgets('is enabled only when the API answered false', (tester) async {
      await pumpCard(tester, status(persistent: false));
      expect(
        persistenceButton(tester).onPressed,
        isNotNull,
        reason: 'the browser confirmed the API is available and not granted',
      );

      await pumpCard(tester, status(persistent: true));
      expect(
        persistenceButton(tester).onPressed,
        isNull,
        reason: 'already persistent — nothing left to request',
      );

      await pumpCard(
        tester,
        status(
          persistent: null,
          missingFeatures: const {WebStorageFeature.persistence},
        ),
      );
      expect(
        persistenceButton(tester).onPressed,
        isNull,
        reason: 'without an API answer there is nothing to request',
      );
    });

    testWidgets('calls the injected action and confirms a grant', (
      tester,
    ) async {
      var calls = 0;
      await pumpCard(
        tester,
        status(persistent: false),
        onMakePersistent: () async {
          calls++;
          return true;
        },
      );

      await tester.tap(_makePersistentButton);
      await tester.pumpAndSettle();

      expect(calls, 1);
      expect(
        find.text('Dauerhafter Speicher ist jetzt aktiv.'),
        findsOneWidget,
      );
    });

    testWidgets('reports a denial', (tester) async {
      await pumpCard(
        tester,
        status(persistent: false),
        onMakePersistent: () async => false,
      );

      await tester.tap(_makePersistentButton);
      await tester.pumpAndSettle();

      expect(
        find.text('Der Browser hat dauerhaften Speicher nicht gewährt.'),
        findsOneWidget,
      );
    });
  });

  group('copy diagnostics', () {
    testWidgets('copies the full diagnostics text and confirms via snackbar', (
      tester,
    ) async {
      final clipboardCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') clipboardCalls.add(call);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );

      final reported = status(
        backend: WebStorageBackend.sharedIndexedDb,
        installedPwa: false,
        persistent: null,
        usageBytes: 123456,
        quotaBytes: null,
        userAgent: 'Mozilla/5.0 test',
        missingFeatures: const {WebStorageFeature.persistence},
      );
      await pumpCard(tester, reported);

      await tester.tap(_copyDiagnosticsButton);
      await tester.pumpAndSettle();

      expect(clipboardCalls, hasLength(1));
      expect(
        (clipboardCalls.single.arguments as Map)['text'],
        reported.buildDiagnosticsText(),
      );
      expect(
        find.text('Diagnose in die Zwischenablage kopiert.'),
        findsOneWidget,
      );
    });
  });

  group('host', () {
    testWidgets('renders the live report and hides while there is none', (
      tester,
    ) async {
      Widget hostWith(WebStorageStatus? report) => ProviderScope(
        // Overrides only apply when the scope's container is created.
        key: UniqueKey(),
        overrides: [
          webStorageReportProvider.overrideWith((ref) async => report),
        ],
        child: const MaterialApp(
          locale: _german,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: WebStorageCardHost()),
        ),
      );

      await tester.pumpWidget(hostWith(null));
      await tester.pumpAndSettle();
      expect(_card, findsNothing);

      final reported = status(backend: WebStorageBackend.sharedIndexedDb);
      await tester.pumpWidget(hostWith(reported));
      await tester.pumpAndSettle();
      expect(_card, findsOneWidget);
      expect(find.text('Speicher-Backend: Geteilte IndexedDB'), findsOneWidget);
    });
  });

  group('native surface', () {
    testWidgets('the settings pane renders no storage card on native', (
      tester,
    ) async {
      useTallSurface(tester, width: 900, height: 3200);
      await tester.pumpWidget(settingsHarness());
      await tester.pumpAndSettle();

      expect(
        _card,
        findsNothing,
        reason: 'the storage card is a web-only surface',
      );
      expect(
        find.byKey(const ValueKey('settingsExportButton')),
        findsOneWidget,
        reason: 'the list is built down to the export card it precedes',
      );
    });
  });
}
