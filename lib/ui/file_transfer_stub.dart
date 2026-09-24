// Inert fallback used only on targets with neither dart:html nor dart:io
// (e.g. a future dart2wasm main-target build). The JSON copy button in the
// export screen remains the always-available path on such targets.
const bool canSaveFile = false;
const bool canShareFile = false;
const bool canPickFile = false;

Future<bool> saveFile(String filename, String content) async => false;

// Never called in production (both capability flags are false so every
// file button stays hidden); it exists only so all implementations of the
// conditional export compile with the same surface.
Future<bool> shareFile(String filename, String content) async => false;

/// Byte-export variant (the PDF document): the stub has no target either.
Future<bool> saveFileBytes(String filename, List<int> bytes) async => false;

/// Byte-share variant (the PDF document): dead too — no hand-off exists on
/// this target at all.
Future<bool> shareFileBytes(String filename, List<int> bytes) async => false;

Future<String?> pickFileText({
  String accept = 'application/json,.json',
}) async => null;
