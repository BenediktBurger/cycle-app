// Native implementation: writes the export next to the user's home
// directory (HOME on desktop, USERPROFILE fallback on Windows), hands the
// export to the system share sheet via `share_plus` (staged in the
// platform temp directory via `path_provider` — on Android this is the
// only route to a real export file, since free-form paths and SAF save
// dialogs do not exist there; desktops get the share action on top of
// their save path), and opens a real file picker for imports via
// `file_selector` (SAF-backed on Android).
// The web implementation keeps its browser file input, the stub covers
// targets with neither dart:html nor dart:io.
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart' show getTemporaryDirectory;
import 'package:share_plus/share_plus.dart';

// The raw save stays a desktop-only affordance: on Android/iOS the visible
// file system is not user-browsable, so the share sheet (below) carries
// the file instead. The environment probe is deliberately part of the
// desktop branch — hermetic widget tests run as this io target.
bool get canSaveFile =>
    (Platform.isLinux || Platform.isMacOS || Platform.isWindows) &&
    _targetDir() != null;

// The share sheet is cross-platform via share_plus (Android/iOS and the
// desktops), so every native target the io file compiles for can offer
// it — no per-Platform switch here. share_plus stages the file through
// its own FileProvider, so no permission or manifest change is needed.
bool get canShareFile => true;

bool get canPickFile => true;

/// Test-only seam for the widget tests, which must not touch platform
/// channels: when set, `pickFileText` delegates here instead of opening the
/// real picker. Always null in production code.
Future<String?> Function(String accept)? pickFileTextOverride;

/// Test-only seam for the widget tests, which must not touch platform
/// channels: when set, the share action delegates here instead of staging
/// the file and opening the real system share sheet. Always null in
/// production code.
Future<bool> Function(String filename, String content)? shareFileOverride;

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

/// Stages [content] under [filename] in the platform's temporary directory
/// and opens the system share sheet with that file (the user then picks
/// the target: Files/Drive/mail on Android, whatever the desktop offers).
/// True when the hand-off to the share sheet happened; false on any
/// staging or platform error (the caller reports only via snackbar, so
/// failures surface as "not shared", never as a crash). The share sheet
/// being dismissed by the user is still a hand-off, not a failure.
Future<bool> shareFile(String filename, String content) async {
  final override = shareFileOverride;
  if (override != null) return override(filename, content);

  try {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}$filename');
    await file.writeAsString(content);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
    return true;
  } catch (_) {
    // The plugin's channel, the platform temp directory or the staging
    // write can each fail per platform; the snackbar contract means the
    // error lands in the UI, not in the crash log.
    return false;
  }
}

/// Opens the native file picker filtered by [accept] (the same HTML accept
/// list as the web implementation, e.g. `application/json,.json` or
/// `.csv,text/csv`) and reads the chosen file's text; null when the user
/// cancelled the dialog.
Future<String?> pickFileText({String accept = 'application/json,.json'}) async {
  final override = pickFileTextOverride;
  if (override != null) return override(accept);

  final file = await openFile(acceptedTypeGroups: [acceptTypeGroup(accept)]);
  if (file == null) return null;
  try {
    return await file.readAsString();
  } on Exception {
    // Unreadable pick result behaves like a cancel: nothing to import.
    return null;
  }
}

/// Translates an HTML-style accept list (`.csv,text/csv` — extensions
/// starting with a dot, everything else a MIME type) into the
/// [XTypeGroup] `file_selector` expects. The default (empty) accept matches
/// every file; a known type keeps a human-readable group label.
XTypeGroup acceptTypeGroup(String accept) {
  final tokens = accept
      .split(',')
      .map((token) => token.trim())
      .where((token) => token.isNotEmpty)
      .toList();
  final extensions = [
    for (final token in tokens)
      if (token.startsWith('.')) token.substring(1),
  ];
  final mimeTypes = [
    for (final token in tokens)
      if (!token.startsWith('.')) token,
  ];

  String label = 'ALL TYPES';
  if (extensions.contains('csv') || mimeTypes.contains('text/csv')) {
    label = 'CSV';
  } else if (extensions.contains('json') ||
      mimeTypes.contains('application/json')) {
    label = 'JSON';
  }
  return XTypeGroup(
    label: label,
    extensions: extensions.isEmpty ? null : extensions,
    mimeTypes: mimeTypes.isEmpty ? null : mimeTypes,
  );
}
