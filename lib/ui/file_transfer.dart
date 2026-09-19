// Platform-adaptive helpers for exporting/importing the JSON document.
//
// The import side offers a file picker everywhere it can:
//   - web: a file <input type=file> (plus the anchored browser download for
//     exports);
//   - native io targets (Linux/mac/Windows desktops and Android/iOS via
//     SAF): `file_selector`'s `openFile`;
//   - anything else (no dart:html and no dart:io): the stub, paste-only,
//     with the JSON text copy path staying the always-available route.
//
// Dispatch via conditional exports — only the file matching the current
// compiler target code is actually compiled/imported.
export 'file_transfer_stub.dart'
    if (dart.library.html) 'file_transfer_web.dart'
    if (dart.library.io) 'file_transfer_io.dart';
