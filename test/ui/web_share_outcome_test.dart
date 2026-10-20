// The VM-testable core of the browser share glue: how a settled
// `navigator.share` maps onto the transfer layer's bool contract. Everything
// else in the web implementation is browser interop covered by the web build.
import 'package:cycle_app/ui/web_share_outcome.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('web share outcome', () {
    test('a resolved share is a success', () {
      expect(webShareOutcome(resolved: true), WebShareOutcome.success);
    });

    test('an AbortError is a cancellation', () {
      expect(
        webShareOutcome(resolved: false, errorName: 'AbortError'),
        WebShareOutcome.cancelled,
      );
    });

    test('an unavailable API or other error is unsupported', () {
      for (final name in [
        'NotAllowedError',
        'NotSupportedError',
        'TypeError',
      ]) {
        expect(
          webShareOutcome(resolved: false, errorName: name),
          WebShareOutcome.unsupported,
          reason: '$name must not be mistaken for a completed share',
        );
      }
    });

    test('an error without a name is unsupported', () {
      expect(webShareOutcome(resolved: false), WebShareOutcome.unsupported);
    });

    test('only a completed share is true for the export marking', () {
      expect(webShareCompleted(WebShareOutcome.success), isTrue);
      expect(webShareCompleted(WebShareOutcome.cancelled), isFalse);
      expect(webShareCompleted(WebShareOutcome.unsupported), isFalse);
    });
  });
}
