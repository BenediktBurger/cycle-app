// Platform-adaptive helpers for exporting/importing the JSON document.
//
// The import side offers a file picker everywhere it can:
//   - web: a file <input type=file> (plus the anchored browser download for
//     exports);
//   - native io targets (Linux/mac/Windows desktops and Android/iOS via
//     SAF): `FilePicker.pickFile` from `file_picker`;
//   - anything else (no dart:html and no dart:io): the stub, paste-only,
//     with the JSON text copy path staying the always-available route.
// The export save side: a real save-as dialog on every native io target
// (`FilePicker.saveFile`, SAF-backed on Android) and the browser download
// on web; the system share sheet (`share_plus`) stays alongside the save
// route on the io targets.
//
// Dispatch via conditional exports — only the file matching the current
// compiler target code is actually compiled/imported.
export 'file_transfer_stub.dart'
    if (dart.library.html) 'file_transfer_web.dart'
    if (dart.library.io) 'file_transfer_io.dart';
