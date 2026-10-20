// Web implementation: browser downloads for exports, the share sheet for JSON
// exports, and a file input for importing a previously saved export.
//
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
//
// dart:html stays confined to this download/picker file; the share glue next
// to it (web_share_web.dart) uses package:web + dart:js_interop, and migrating
// these DOM calls is separate work.
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import 'web_share.dart';
import 'web_share_outcome.dart';

const bool canSaveFile = true;
// The PDF hand-off stays the browser download on web; only the JSON export
// uses the share sheet (see [canShareJsonFile]).
const bool canShareFile = false;
const bool canPickFile = true;

/// JSON exports go through the browser share sheet where it accepts a file;
/// the runtime probe keeps the share button hidden where it does not.
bool get canShareJsonFile => canShareJsonFiles;

/// Triggers a browser download of [content] as [filename] (anchor + Blob).
/// Returns true when the click was sent — browsers may still ask the user
/// where to save / block the download, but that is beyond our control.
Future<bool> saveFile(String filename, String content) async {
  final blob = html.Blob([utf8.encode(content)], 'application/json');
  return _triggerDownload(filename, blob);
}

/// Binary variant of [saveFile] for the PDF export document: same download
/// anchoring, PDF MIME type.
Future<bool> saveFileBytes(String filename, List<int> bytes) =>
    _triggerDownload(filename, html.Blob([bytes], 'application/pdf'));

Future<bool> _triggerDownload(String filename, html.Blob blob) async {
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = filename
    // Avoid navigating away on some browsers if the attribute is ignored.
    ..target = 'self';
  html.document.body!.children.add(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
  return true;
}

/// Hands the JSON export to the browser share sheet where it accepts a file.
/// True only for a completed share; a dismissed sheet or an unavailable
/// share API is false. The browser download stays the separate save action.
Future<bool> shareFile(String filename, String content) async {
  if (!canShareJsonFile) return false;
  return webShareCompleted(await shareJsonFiles(filename, content));
}

/// Binary share variant for the PDF export document: dead on web, where the
/// browser download is the PDF hand-off; kept only for the conditional
/// export's equal surface.
Future<bool> shareFileBytes(String filename, List<int> bytes) async => false;

/// Opens a file picker filtered by [accept] (an HTML accept list such as
/// `application/json,.json` or `.csv,text/csv`) and reads the chosen file's
/// text; null when the user cancelled or no file was chosen.
Future<String?> pickFileText({String accept = 'application/json,.json'}) {
  final input = html.InputElement(type: 'file')..accept = accept;
  final picked = Completer<String?>();

  input.onChange.listen((event) {
    final files = input.files;
    if (files == null || files.isEmpty) {
      picked.complete(null);
      return;
    }
    final reader = html.FileReader();
    reader.onLoadEnd.listen((_) => picked.complete(reader.result as String?));
    reader.onError.listen((_) => picked.complete(null));
    reader.readAsText(files[0]);
  });

  html.document.body!.children.add(input);
  input.click();
  input.remove();
  return picked.future;
}
