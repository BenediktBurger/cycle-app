/// Platform-neutral description of the storage the web database runs on.
///
/// Shared widgets consume this model only: the browser probe and the JS
/// interop live behind platform-specific files.
library;

/// Names reported in the `missingFeatures` set when a browser API is
/// unavailable or rejects its promise.
abstract final class WebStorageFeature {
  static const installedPwa = 'installedPwa';
  static const persistence = 'storagePersistence';
  static const estimate = 'storageEstimate';
  static const userAgent = 'userAgent';
}

/// The storage implementation drift selected for the web database.
enum WebStorageBackend {
  opfs,
  sharedIndexedDb,
  unsafeIndexedDb,
  inMemory,
  unknown;

  /// Maps drift's `WasmStorageImplementation.name` without importing drift
  /// (or its web types) into this shared model.
  static WebStorageBackend fromDriftImplementationName(String name) {
    return switch (name) {
      'opfsShared' || 'opfsLocks' => opfs,
      'sharedIndexedDb' || 'sharedIndexDb' => sharedIndexedDb,
      'unsafeIndexedDb' || 'indexDb' => unsafeIndexedDb,
      'inMemory' || 'memory' => inMemory,
      _ => unknown,
    };
  }
}

/// Facts reported by the browser probe, before they are merged with drift's
/// chosen backend. Nullable fields mean the browser API was unavailable.
final class WebStorageProbe {
  const WebStorageProbe({
    required this.installedPwa,
    required this.persistent,
    required this.usageBytes,
    required this.quotaBytes,
    required this.userAgent,
    required this.missingFeatures,
  });

  final bool installedPwa;
  final bool? persistent;
  final int? usageBytes;
  final int? quotaBytes;
  final String userAgent;
  final Set<String> missingFeatures;
}

/// One merged, UI-facing storage status.
final class WebStorageStatus {
  const WebStorageStatus({
    required this.backend,
    required this.installedPwa,
    required this.persistent,
    required this.usageBytes,
    required this.quotaBytes,
    required this.userAgent,
    required this.missingFeatures,
  });

  final WebStorageBackend backend;
  final bool installedPwa;
  final bool? persistent;
  final int? usageBytes;
  final int? quotaBytes;
  final String userAgent;
  final Set<String> missingFeatures;

  bool get isInMemory => backend == WebStorageBackend.inMemory;

  bool get needsMultiTabWarning => backend == WebStorageBackend.unsafeIndexedDb;

  /// The status after an explicit `persist()` answer, which replaces a stale
  /// probe value and clears the persistence-unavailable entry.
  WebStorageStatus withPersistentResult(bool persistent) => WebStorageStatus(
    backend: backend,
    installedPwa: installedPwa,
    persistent: persistent,
    usageBytes: usageBytes,
    quotaBytes: quotaBytes,
    userAgent: userAgent,
    missingFeatures: {
      for (final feature in missingFeatures)
        if (feature != WebStorageFeature.persistence) feature,
    },
  );

  bool get isIosSafari {
    final ios =
        userAgent.contains('iPhone') ||
        userAgent.contains('iPad') ||
        userAgent.contains('iPod');
    if (!ios) return false;
    // iOS browser shells all carry Safari's token; the vendor token names them.
    const otherShells = ['CriOS', 'FxiOS', 'EdgiOS', 'OPiOS', 'Mercury'];
    if (otherShells.any(userAgent.contains)) return false;
    return userAgent.contains('Safari');
  }

  // Null means the persistence API was unavailable, so durability is
  // unconfirmed and the install hint still applies.
  bool get showInstallHint =>
      isIosSafari && !installedPwa && persistent != true && !isInMemory;

  String get backendLabelKey => switch (backend) {
    WebStorageBackend.opfs => 'webStorageBackendOpfs',
    WebStorageBackend.sharedIndexedDb => 'webStorageBackendSharedIndexedDb',
    WebStorageBackend.unsafeIndexedDb => 'webStorageBackendUnsafeIndexedDb',
    WebStorageBackend.inMemory => 'webStorageBackendInMemory',
    WebStorageBackend.unknown => 'webStorageBackendUnknown',
  };

  /// Plain `key: value` lines for the diagnostics copy action; unavailable
  /// facts stay visible as `unknown` instead of being omitted.
  String buildDiagnosticsText() {
    final features = missingFeatures.isEmpty
        ? 'none'
        : (missingFeatures.toList()..sort()).join(', ');
    final persistentText = switch (persistent) {
      true => 'yes',
      false => 'no',
      null => 'unknown',
    };
    return [
      'userAgent: ${userAgent.isEmpty ? 'unknown' : userAgent}',
      'installedPwa: ${installedPwa ? 'yes' : 'no'}',
      'persistent: $persistentText',
      'backend: ${backend.name}',
      'missingFeatures: $features',
      'usageBytes: ${usageBytes ?? 'unknown'}',
      'quotaBytes: ${quotaBytes ?? 'unknown'}',
    ].join('\n');
  }
}

WebStorageStatus composeWebStorageStatus(
  WebStorageBackend backend,
  WebStorageProbe probe,
) => WebStorageStatus(
  backend: backend,
  installedPwa: probe.installedPwa,
  persistent: probe.persistent,
  usageBytes: probe.usageBytes,
  quotaBytes: probe.quotaBytes,
  userAgent: probe.userAgent,
  missingFeatures: probe.missingFeatures,
);
