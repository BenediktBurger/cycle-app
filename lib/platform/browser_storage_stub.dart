import 'web_storage_status.dart';

/// Native and VM builds have no browser storage API, so every probe fact is
/// unavailable instead of the call failing.
Future<WebStorageProbe> probeBrowserStorage() async => const WebStorageProbe(
  installedPwa: false,
  persistent: null,
  usageBytes: null,
  quotaBytes: null,
  userAgent: '',
  missingFeatures: {
    WebStorageFeature.installedPwa,
    WebStorageFeature.persistence,
    WebStorageFeature.estimate,
    WebStorageFeature.userAgent,
  },
);

/// There is nothing to persist outside a browser.
Future<bool> requestPersistentStorage() async => false;
