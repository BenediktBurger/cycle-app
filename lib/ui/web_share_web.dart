import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'web_share_outcome.dart';

/// True when the browser accepts a file of [mimeType] in its share sheet. The
/// probe uses the real file shape because `canShare` rejects data it cannot
/// validate, and a bare `navigator.share` check would not tell file sharing
/// apart from text sharing.
bool canShareBrowserFiles(String mimeType) {
  try {
    return web.window.navigator.canShare(
      web.ShareData(
        files: <web.File>[
          _file('probe', const <int>[0], mimeType),
        ].toJS,
      ),
    );
  } catch (_) {
    return false;
  }
}

/// Hands [bytes] to the browser share sheet as [filename] of [mimeType]. The
/// share call runs synchronously from the caller's tap: an awaiting step
/// before it would spend the transient activation the browser requires for
/// `share()`.
Future<WebShareOutcome> shareBrowserFile(
  String filename,
  List<int> bytes, {
  required String mimeType,
}) async {
  try {
    await web.window.navigator
        .share(
          web.ShareData(
            files: <web.File>[_file(filename, bytes, mimeType)].toJS,
          ),
        )
        .toDart;
    return webShareOutcome(resolved: true);
  } catch (error) {
    return webShareOutcome(resolved: false, errorName: _errorName(error));
  }
}

web.File _file(String filename, List<int> bytes, String mimeType) => web.File(
  <JSAny>[Uint8List.fromList(bytes).toJS].toJS,
  filename,
  web.FilePropertyBag(type: mimeType),
);

/// The rejected error's `name`; a thrown non-object carries none.
String? _errorName(Object error) {
  try {
    if (!error.isA<JSObject>()) return null;
    return (error as JSObject).getProperty<JSString?>('name'.toJS)?.toDart;
  } catch (_) {
    return null;
  }
}
