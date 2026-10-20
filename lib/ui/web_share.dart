// Browser file sharing, reached through a conditional export so native and VM
// builds never compile the JS interop.
export 'web_share_stub.dart' if (dart.library.js_interop) 'web_share_web.dart';
