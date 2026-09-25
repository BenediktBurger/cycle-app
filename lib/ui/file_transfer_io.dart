// Native implementation: a real save-as dialog for the export via
// `file_picker` on every target this file compiles for (desktop file
// choosers, Android's SAF "document create" — the plugin's
// `FilePicker.saveFile` covers all of them, so there is no free-form
// path fallback anymore), the system share sheet as a second hand-off
// via `share_plus` (staged in the platform temp directory via
// `path_provider`), and a real file picker for imports via
// `FilePicker.pickFile` (SAF-backed on Android).
// The web implementation keeps its browser file input, the stub covers
// targets with neither dart:html nor dart:io.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart' show getTemporaryDirectory;
import 'package:share_plus/share_plus.dart';

// The save-as dialog is a cross-platform affordance via file_picker
// (desktop file choosers and Android SAF alike), so every native target
// this file compiles for can offer it — a single call, no per-Platform
// switch and no extra probing.
const bool canSaveFile = true;

// The share sheet is cross-platform via share_plus (Android/iOS and the
// desktops), so every native target the io file compiles for can offer
// it — no per-Platform switch here. share_plus stages the file through
// its own FileProvider, so no permission or manifest change is needed.
const bool canShareFile = true;

const bool canPickFile = true;

/// Test-only seam for the widget tests, which must not touch platform
/// channels: when set, `pickFileText` delegates here instead of opening the
/// real picker. Always null in production code.
Future<String?> Function(String accept)? pickFileTextOverride;

/// Test-only seam for the widget tests, which must not touch platform
/// channels: when set, the share action delegates here instead of staging
/// the file and opening the real system share sheet. Always null in
/// production code.
Future<bool> Function(String filename, String content)? shareFileOverride;

/// Test-only seam for the widget tests, which must not touch platform
/// channels: when set, the save action delegates here instead of opening
/// the real save-as dialog. Always null in production code.
Future<bool> Function(String filename, String content)? saveFileOverride;

/// Test-only seam mirroring [saveFileOverride] for the byte exports (the
/// PDF document): when set, `saveFileBytes` delegates here instead of
/// opening the real save-as dialog. Always null in production code.
Future<bool> Function(String filename, List<int> bytes)? saveFileBytesOverride;

/// Test-only seam mirroring [shareFileOverride] for the byte shares (the
/// PDF document): when set, `shareFileBytes` delegates here instead of
/// staging the file and opening the real system share sheet. Always null
/// in production code.
Future<bool> Function(String filename, List<int> bytes)? shareFileBytesOverride;

/// Opens the save-as dialog, pre-filled with [filename], and lets
/// `file_picker` write [content] as application/json to the chosen
/// destination. True when the save destination was chosen and written;
/// false when the user cancelled the dialog or the save failed.
///
/// The caller's bool contract cannot distinguish a cancelled dialog from
/// a failed write: both surface the same failure snackbar, and a cancel
/// therefore never triggers the success snackbar. That matches
/// [shareFile]'s stance — a dialog that goes away without handing over
/// anything is not a success, we just cannot tell the user more.
Future<bool> saveFile(String filename, String content) async {
  final override = saveFileOverride;
  if (override != null) return override(filename, content);

  try {
    final destination = await FilePicker.saveFile(
      fileName: filename,
      bytes: utf8.encode(content),
      mimeType: 'application/json',
    );
    return destination != null;
  } catch (_) {
    // The plugin's channel can fail per platform; the snackbar contract
    // means the error lands in the UI, not in the crash log.
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

/// The binary twin of [shareFile] for the PDF document: stages [bytes]
/// under [filename] in the platform's temporary directory and opens the
/// system share sheet with that file. The bool contract matches
/// [shareFile]'s — a dismissed share sheet is a hand-off (true), false on
/// any staging or platform error.
Future<bool> shareFileBytes(String filename, List<int> bytes) async {
  final override = shareFileBytesOverride;
  if (override != null) return override(filename, bytes);

  try {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}$filename');
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
    return true;
  } catch (_) {
    // The plugin's channel, the platform temp directory or the staging
    // write can each fail per platform; the snackbar contract means the
    // error lands in the UI, not in the crash log.
    return false;
  }
}

/// Opens the save-as dialog, pre-filled with [filename], and lets
/// `file_picker` write [bytes] as application/pdf to the chosen
/// destination (the PDF export route); true when the save destination was
/// chosen and written, false on cancel or failure. The bytes variant of
/// [saveFile] exists because the PDF is a binary document. The caller's
/// bool contract matches [saveFile]'s — see the note there.
Future<bool> saveFileBytes(String filename, List<int> bytes) async {
  final save = saveFileBytesOverride;
  if (save != null) return save(filename, bytes);

  try {
    final destination = await FilePicker.saveFile(
      fileName: filename,
      bytes: Uint8List.fromList(bytes),
      mimeType: 'application/pdf',
    );
    return destination != null;
  } catch (_) {
    // The plugin's channel can fail per platform; the snackbar contract
    // means the error lands in the UI, not in the crash log.
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

  final extensions = acceptExtensions(accept);
  final picked = await FilePicker.pickFile(
    // Without extension tokens there is no usable filter (file_picker's
    // FileType.custom only understands extensions — see
    // [acceptExtensions]), so the dialog stays unfiltered then.
    type: extensions == null ? FileType.any : FileType.custom,
    allowedExtensions: extensions,
  );
  if (picked == null) return null;
  try {
    return utf8.decode(await picked.readAsBytes());
  } catch (_) {
    // Unreadable pick result behaves like a cancel: nothing to import.
    return null;
  }
}

/// Translates an HTML-style accept list (`.csv,text/csv` — extensions
/// starting with a dot, everything else a MIME type) into the extension
/// tokens `file_picker`'s [FileType.custom] filters by (dot-less, e.g.
/// `['csv']`); null when there is no extension to filter by, meaning "any
/// file".
///
/// Limitation (accepted): file_picker's custom open dialog filters by
/// EXTENSION only — a MIME-only accept string like `text/csv` or
/// `application/json` degrades to an unfiltered dialog (extension-only
/// filtering is coarser than a MIME-aware one). Real callers
/// always pair their MIME types with a dot-extension (`.json`, `.csv`),
/// so the JSON/CSV pick dialogs stay filtered in practice; a picked file
/// with the wrong content is caught by the import dialog's validation.
List<String>? acceptExtensions(String accept) {
  final extensions = [
    for (final token in accept.split(',').map((token) => token.trim()))
      if (token.startsWith('.')) token.substring(1),
  ];
  return extensions.isEmpty ? null : extensions;
}
