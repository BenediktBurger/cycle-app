// Shared framework-error collector for the shell/dialog harnesses:
// scenarios install it around the interactions that belong to the tested
// surface; the shell pump's overflow-free state is asserted separately,
// and any error recorded inside the collector still fails the test.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs [body] with `FlutterError.onError` rerouted into a list, returned
/// once the handler is restored — the caller asserts over everything the
/// framework reported during the scenario.
///
/// With [teardownWhenDone], the widget tree is unmounted INSIDE the
/// collected window before the list is returned: element unmount is where
/// an inherited-widget teardown assertion (e.g. `_dependents.isEmpty`)
/// fires, so the lifecycle scenarios collect over pump + interactions +
/// teardown. Without it, the collected window ends when [body] returns —
/// errors from a later teardown stay outside the list (typically surfaced
/// through the tester's pending-exception mechanism instead).
Future<List<FlutterErrorDetails>> collectFrameworkErrors(
  WidgetTester tester,
  Future<void> Function() body, {
  bool teardownWhenDone = false,
}) async {
  final errors = <FlutterErrorDetails>[];
  final original = FlutterError.onError;
  FlutterError.onError = (details) => errors.add(details);
  try {
    await body();
    if (teardownWhenDone) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  } finally {
    FlutterError.onError = original;
  }
  return errors;
}

/// Runs [body] with `FlutterError.onError` rerouted into a collector and
/// fails afterwards when anything was recorded: the interactions inside
/// [body] must not raise a framework exception (RenderFlex overflow).
/// Records outside the collector's window — e.g. the shell pump before it —
/// stay the caller's business (typically
/// `expect(tester.takeException(), isNull)` next to the call).
Future<void> expectNoFrameworkErrors(
  WidgetTester tester,
  Future<void> Function() body, {
  String reason =
      'no framework exception (RenderFlex overflow) during the interactions '
      'under test',
}) async {
  final errors = await collectFrameworkErrors(tester, body);
  expect(errors, isEmpty, reason: reason);
}
