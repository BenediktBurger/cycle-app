import 'package:drift_flutter/drift_flutter.dart';

import '../platform/web_storage_status.dart';

/// Native builds never enter the web branch; the shared signature keeps that
/// branch compiling.
DriftWebOptions webDriftOptions({
  required Uri sqlite3Wasm,
  required Uri driftWorker,
  required void Function(WebStorageBackend backend)? onResult,
}) {
  throw UnsupportedError('Web drift options are unavailable on native.');
}
