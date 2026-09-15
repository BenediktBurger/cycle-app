// Native implementation WITHOUT new dependencies: writes the export next to
// the user's home directory (HOME on desktop, USERPROFILE fallback on
// Windows). Intentionally NOT a full Android/iOS path picker — Android
// storage access needs SAF (a plugin dependency), so there the JSON copy
// path stays the supported route for M1 (see the dispatcher's doc comment).
import 'dart:io';

bool get canSaveFile => _targetDir() != null;
const bool canPickFile = false;

String? _targetDir() {
  final dir =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  if (dir == null || dir.trim().isEmpty) return null;
  return dir;
}

/// Writes [content] to `<home>/<filename>`; true when the file landed.
Future<bool> saveFile(String filename, String content) async {
  final dir = _targetDir();
  if (dir == null) return false;
  try {
    final file = File('$dir${Platform.pathSeparator}$filename');
    await file.writeAsString(content);
    return true;
  } on FileSystemException {
    return false;
  }
}

/// No picker on native in M1 (no dev dependency for SAF/pickers); paste
/// into the import dialog is the route. Kept async-shaped for API parity.
Future<String?> pickJsonFileText() async => null;
