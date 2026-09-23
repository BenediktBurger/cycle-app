// Web implementation: browser file download for exports and a file input
// for importing a previously saved export.
//
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
//
// Justification for dart:html (the two superseded-analysis infos above are
// intentionally ignored HERE, nothing else): this file exists exactly once,
// inside a conditional export that only web (dart2js) targets compile; pub
// gains NO extra dependency in exchange (package:web would be one more dep
// purely for cosmetic import-shape parity with drift internals). Migrating
// to package:web + dart:js_interop is future work when dart2wasm promotion
// matters for these helpers — the stub covers that case already.
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

const bool canSaveFile = true;
// No system share sheet on web — the browser download above carries the
// export file, so the share button stays hidden here.
const bool canShareFile = false;
const bool canPickFile = true;

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

// Never called in production ([canShareFile] is false keeps the button
// hidden); it exists only so every implementation of the conditional
// export compiles with the same surface.
Future<bool> shareFile(String filename, String content) async => false;

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
