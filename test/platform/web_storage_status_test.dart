import 'package:cycle_app/platform/web_storage_status.dart';
import 'package:flutter_test/flutter_test.dart';

const _iphoneSafari =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 '
    'Mobile/15E148 Safari/604.1';
const _ipadSafari =
    'Mozilla/5.0 (iPad; CPU OS 17_5 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 '
    'Mobile/15E148 Safari/604.1';
const _iphoneChrome =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/126.0.6478.54 '
    'Mobile/15E148 Safari/604.1';
const _iphoneFirefox =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) FxiOS/127.0 '
    'Mobile/15E148 Safari/604.1';
const _iphoneEdge =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) EdgiOS/126.0.0.0 '
    'Mobile/15E148 Safari/604.1';
const _androidChrome =
    'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';
const _desktopSafari =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15';

WebStorageStatus _status({
  WebStorageBackend backend = WebStorageBackend.opfs,
  bool installedPwa = false,
  bool? persistent,
  int? usageBytes,
  int? quotaBytes,
  String userAgent = _iphoneSafari,
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

void main() {
  group('fromDriftImplementationName', () {
    test('maps every drift storage name to the neutral backend', () {
      const expected = {
        'opfsShared': WebStorageBackend.opfs,
        'opfsLocks': WebStorageBackend.opfs,
        'sharedIndexedDb': WebStorageBackend.sharedIndexedDb,
        'sharedIndexDb': WebStorageBackend.sharedIndexedDb,
        'unsafeIndexedDb': WebStorageBackend.unsafeIndexedDb,
        'indexDb': WebStorageBackend.unsafeIndexedDb,
        'inMemory': WebStorageBackend.inMemory,
        'memory': WebStorageBackend.inMemory,
      };
      for (final entry in expected.entries) {
        expect(
          WebStorageBackend.fromDriftImplementationName(entry.key),
          entry.value,
          reason: entry.key,
        );
      }
    });

    test('maps an unrecognized storage name to unknown', () {
      expect(
        WebStorageBackend.fromDriftImplementationName('someFutureBackend'),
        WebStorageBackend.unknown,
      );
    });
  });

  group('composeWebStorageStatus', () {
    test('carries the backend and every probe fact into the status', () {
      final status = composeWebStorageStatus(
        WebStorageBackend.sharedIndexedDb,
        WebStorageProbe(
          installedPwa: true,
          persistent: false,
          usageBytes: 4096,
          quotaBytes: 8192,
          userAgent: _ipadSafari,
          missingFeatures: const {'sharedWorkers', 'dedicatedWorkers'},
        ),
      );

      expect(status.backend, WebStorageBackend.sharedIndexedDb);
      expect(status.installedPwa, isTrue);
      expect(status.persistent, isFalse);
      expect(status.usageBytes, 4096);
      expect(status.quotaBytes, 8192);
      expect(status.userAgent, _ipadSafari);
      expect(status.missingFeatures, {'sharedWorkers', 'dedicatedWorkers'});
    });
  });

  group('backend classification', () {
    test('only the in-memory backend is classified as in-memory', () {
      for (final backend in WebStorageBackend.values) {
        expect(
          _status(backend: backend).isInMemory,
          backend == WebStorageBackend.inMemory,
          reason: backend.name,
        );
      }
    });

    test('only the unsafe IndexedDB backend needs the multi-tab warning', () {
      for (final backend in WebStorageBackend.values) {
        expect(
          _status(backend: backend).needsMultiTabWarning,
          backend == WebStorageBackend.unsafeIndexedDb,
          reason: backend.name,
        );
      }
    });
  });

  group('isIosSafari', () {
    test('recognizes iPhone and iPad Safari', () {
      expect(_status(userAgent: _iphoneSafari).isIosSafari, isTrue);
      expect(_status(userAgent: _ipadSafari).isIosSafari, isTrue);
    });

    test('excludes iOS browser shells that embed Safari', () {
      expect(_status(userAgent: _iphoneChrome).isIosSafari, isFalse);
      expect(_status(userAgent: _iphoneFirefox).isIosSafari, isFalse);
      expect(_status(userAgent: _iphoneEdge).isIosSafari, isFalse);
    });

    test('excludes non-iOS browsers', () {
      expect(_status(userAgent: _androidChrome).isIosSafari, isFalse);
      expect(_status(userAgent: _desktopSafari).isIosSafari, isFalse);
    });
  });

  group('showInstallHint', () {
    test('shows on iOS Safari only while not installed and not persistent', () {
      expect(_status(persistent: null).showInstallHint, isTrue);
      expect(_status(persistent: false).showInstallHint, isTrue);
      expect(_status(persistent: true).showInstallHint, isFalse);
    });

    test('is hidden once installed', () {
      expect(_status(installedPwa: true).showInstallHint, isFalse);
    });

    test('is hidden outside iOS Safari and in the in-memory fallback', () {
      expect(_status(userAgent: _androidChrome).showInstallHint, isFalse);
      expect(
        _status(backend: WebStorageBackend.inMemory).showInstallHint,
        isFalse,
      );
    });
  });

  group('backendLabelKey', () {
    test('selects a distinct localization key per backend', () {
      final keys = {
        for (final backend in WebStorageBackend.values)
          _status(backend: backend).backendLabelKey,
      };

      expect(keys, hasLength(WebStorageBackend.values.length));
      expect(
        _status(backend: WebStorageBackend.opfs).backendLabelKey,
        'webStorageBackendOpfs',
      );
      expect(
        _status(backend: WebStorageBackend.sharedIndexedDb).backendLabelKey,
        'webStorageBackendSharedIndexedDb',
      );
      expect(
        _status(backend: WebStorageBackend.unsafeIndexedDb).backendLabelKey,
        'webStorageBackendUnsafeIndexedDb',
      );
      expect(
        _status(backend: WebStorageBackend.inMemory).backendLabelKey,
        'webStorageBackendInMemory',
      );
      expect(
        _status(backend: WebStorageBackend.unknown).backendLabelKey,
        'webStorageBackendUnknown',
      );
    });
  });

  group('buildDiagnosticsText', () {
    test('reports every fact as a key-value line', () {
      final text = _status(
        backend: WebStorageBackend.opfs,
        installedPwa: true,
        persistent: false,
        usageBytes: 1234,
        quotaBytes: 5678,
        userAgent: _iphoneSafari,
        missingFeatures: const {'sharedWorkers', 'dedicatedWorkers'},
      ).buildDiagnosticsText();

      expect(text, contains('userAgent: $_iphoneSafari'));
      expect(text, contains('installedPwa: yes'));
      expect(text, contains('persistent: no'));
      expect(text, contains('backend: opfs'));
      expect(
        text,
        contains('missingFeatures: dedicatedWorkers, sharedWorkers'),
      );
      expect(text, contains('usageBytes: 1234'));
      expect(text, contains('quotaBytes: 5678'));
    });

    test('degrades unavailable facts to unknown', () {
      final text = _status(
        backend: WebStorageBackend.unknown,
        persistent: null,
        usageBytes: null,
        quotaBytes: null,
        userAgent: '',
      ).buildDiagnosticsText();

      expect(text, contains('userAgent: unknown'));
      expect(text, contains('persistent: unknown'));
      expect(text, contains('backend: unknown'));
      expect(text, contains('missingFeatures: none'));
      expect(text, contains('usageBytes: unknown'));
      expect(text, contains('quotaBytes: unknown'));
    });
  });
}
