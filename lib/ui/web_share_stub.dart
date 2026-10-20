import 'web_share_outcome.dart';

/// No browser share sheet exists on this target.
bool get canShareJsonFiles => false;

/// No browser share sheet exists on this target; the caller keeps its file
/// save/download fallback.
Future<WebShareOutcome> shareJsonFiles(String filename, String content) async =>
    WebShareOutcome.unsupported;
