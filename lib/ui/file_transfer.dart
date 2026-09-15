// Platform-adaptive helpers for exporting/importing the JSON document.
//
// No new dependency policy for this milestone: no file pickers, no share
// plugins. Therefore:
//   - web: browser file download (anchor + Blob) AND a file <input type=file>
//     for picking an export back in;
//   - native desktop (Linux/mac/Windows with HOME/USERPROFILE set): the JSON
//     is written next to the user's home directory;
//   - Android/iOS: neither is available without SAF/pickers, so the export
//     screen keeps a full-text copy button as the always-available path
//     (honest limitation, documented in CONTRIBUTING).
//
// Dispatch via conditional exports — only the file matching the current
// compiler target code is actually compiled/imported.
export 'file_transfer_stub.dart'
    if (dart.library.html) 'file_transfer_web.dart'
    if (dart.library.io) 'file_transfer_io.dart';
