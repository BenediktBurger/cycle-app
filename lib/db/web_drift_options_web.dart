import 'package:drift_flutter/drift_flutter.dart';

import '../platform/web_storage_status.dart';

DriftWebOptions webDriftOptions({
  required Uri sqlite3Wasm,
  required Uri driftWorker,
  required void Function(WebStorageBackend backend)? onResult,
}) {
  return DriftWebOptions(
    sqlite3Wasm: sqlite3Wasm,
    driftWorker: driftWorker,
    onResult: onResult == null
        ? null
        : (result) => onResult(
            WebStorageBackend.fromDriftImplementationName(
              result.chosenImplementation.name,
            ),
          ),
  );
}
