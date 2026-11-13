import 'web_share_outcome.dart';

/// No browser share sheet exists on this target.
bool canShareBrowserFiles(String mimeType) => false;

/// No browser share sheet exists on this target; the caller keeps its file
/// save/download fallback.
Future<WebShareOutcome> shareBrowserFile(
  String filename,
  List<int> bytes, {
  required String mimeType,
}) async => WebShareOutcome.unsupported;
