import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'web_share_outcome.dart';

/// True when the browser accepts a JSON file in its share sheet. The probe
/// uses the real file shape because `canShare` rejects data it cannot
/// validate, and a bare `navigator.share` check would not tell file sharing
/// apart from text sharing.
bool get canShareJsonFiles {
  try {
    return web.window.navigator.canShare(
      web.ShareData(files: <web.File>[_jsonFile('probe.json', '{}')].toJS),
    );
  } catch (_) {
    return false;
  }
}

/// Hands [content] to the browser share sheet as a JSON file. The share call
/// runs synchronously from the caller's tap: an awaiting step before it would
/// spend the transient activation the browser requires for `share()`.
Future<WebShareOutcome> shareJsonFiles(String filename, String content) async {
  try {
    await web.window.navigator
        .share(
          web.ShareData(files: <web.File>[_jsonFile(filename, content)].toJS),
        )
        .toDart;
    return webShareOutcome(resolved: true);
  } catch (error) {
    return webShareOutcome(resolved: false, errorName: _errorName(error));
  }
}

web.File _jsonFile(String filename, String content) => web.File(
  <JSAny>[content.toJS].toJS,
  filename,
  web.FilePropertyBag(type: 'application/json'),
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
