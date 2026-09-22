// Inert fallback used only on targets with neither dart:html nor dart:io
// (e.g. a future dart2wasm main-target build). The JSON copy button in the
// export screen remains the always-available path on such targets.
bool get canSaveFile => false;
bool get canShareFile => false;
const bool canPickFile = false;

Future<bool> saveFile(String filename, String content) async => false;

// Never called in production (both capability getters are false keep every
// file button hidden); it exists only so all implementations of the
// conditional export compile with the same surface.
Future<bool> shareFile(String filename, String content) async => false;

Future<String?> pickFileText({
  String accept = 'application/json,.json',
}) async => null;
