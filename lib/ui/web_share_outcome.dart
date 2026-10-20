/// How a `navigator.share` promise settled, in the transfer layer's terms.
enum WebShareOutcome { success, cancelled, unsupported }

/// Classifies one share attempt. [resolved] is true when the browser handed
/// the file over; otherwise [errorName] is the rejection's `name`. Only
/// `AbortError` is the user dismissing the sheet — every other failure,
/// including a nameless error, must not look like a completed hand-off.
WebShareOutcome webShareOutcome({required bool resolved, String? errorName}) {
  if (resolved) return WebShareOutcome.success;
  return errorName == 'AbortError'
      ? WebShareOutcome.cancelled
      : WebShareOutcome.unsupported;
}

/// The JSON share's bool contract: true only for a completed hand-off. A
/// dismissed sheet and an unavailable share API both report failure.
bool webShareCompleted(WebShareOutcome outcome) =>
    outcome == WebShareOutcome.success;
