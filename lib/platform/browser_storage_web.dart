import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'web_storage_status.dart';

/// Reads the browser storage facts; an unavailable or rejecting API lands in
/// [WebStorageProbe.missingFeatures] instead of throwing.
Future<WebStorageProbe> probeBrowserStorage() async {
  final missing = <String>{};
  try {
    final navigator = web.window.navigator;
    final storage = navigator.storage;
    final estimate = await _readEstimate(storage, missing);
    return WebStorageProbe(
      installedPwa: _readInstalledPwa(navigator, missing),
      persistent: await _readPersisted(storage, missing),
      usageBytes: estimate.$1,
      quotaBytes: estimate.$2,
      userAgent: _readUserAgent(navigator, missing),
      missingFeatures: missing,
    );
  } catch (_) {
    return _unavailableProbe();
  }
}

/// Requests persistent storage for the current origin on explicit user action;
/// a missing API or a denial answers `false`.
Future<bool> requestPersistentStorage() async {
  try {
    return (await web.window.navigator.storage.persist().toDart).toDart;
  } catch (_) {
    return false;
  }
}

/// The probe for a host where even reaching the browser objects fails.
WebStorageProbe _unavailableProbe() => const WebStorageProbe(
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

Future<bool?> _readPersisted(
  web.StorageManager storage,
  Set<String> missing,
) async {
  try {
    return (await storage.persisted().toDart).toDart;
  } catch (_) {
    missing.add(WebStorageFeature.persistence);
    return null;
  }
}

Future<(int?, int?)> _readEstimate(
  web.StorageManager storage,
  Set<String> missing,
) async {
  try {
    final estimate = await storage.estimate().toDart;
    return (estimate.usage, estimate.quota);
  } catch (_) {
    missing.add(WebStorageFeature.estimate);
    return (null, null);
  }
}

bool _readInstalledPwa(web.Navigator navigator, Set<String> missing) {
  try {
    if (web.window.matchMedia('(display-mode: standalone)').matches) {
      return true;
    }
    // Safari before 16.4 exposes the installed state only as this non-standard
    // property; every other browser lacks it.
    final standalone = navigator.getProperty<JSBoolean?>('standalone'.toJS);
    return standalone?.toDart ?? false;
  } catch (_) {
    missing.add(WebStorageFeature.installedPwa);
    return false;
  }
}

String _readUserAgent(web.Navigator navigator, Set<String> missing) {
  try {
    return navigator.userAgent;
  } catch (_) {
    missing.add(WebStorageFeature.userAgent);
    return '';
  }
}
