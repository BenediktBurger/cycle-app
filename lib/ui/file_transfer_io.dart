// Native implementation: writes the export next to the user's home
// directory (HOME on desktop, USERPROFILE fallback on Windows) and opens a
// real file picker for imports via `file_selector` (SAF-backed on Android).
// The web implementation keeps its browser file input, the stub covers
// targets with neither dart:html nor dart:io.
import 'dart:io';

import 'package:file_selector/file_selector.dart';

bool get canSaveFile => _targetDir() != null;

bool get canPickFile => true;

/// Test-only seam for the widget tests, which must not touch platform
/// channels: when set, `pickFileText` delegates here instead of opening the
/// real picker. Always null in production code.
Future<String?> Function(String accept)? pickFileTextOverride;

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

/// Opens the native file picker filtered by [accept] (the same HTML accept
/// list as the web implementation, e.g. `application/json,.json` or
/// `.csv,text/csv`) and reads the chosen file's text; null when the user
/// cancelled the dialog.
Future<String?> pickFileText({String accept = 'application/json,.json'}) async {
  final override = pickFileTextOverride;
  if (override != null) return override(accept);

  final file = await openFile(acceptedTypeGroups: [
    acceptTypeGroup(accept),
  ]);
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
