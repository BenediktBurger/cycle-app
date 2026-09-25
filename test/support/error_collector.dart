// Shared framework-error collector for the narrow-viewport harnesses:
// tests install it around the interactions that belong to the tested
// surface; the shell pump's overflow-free state is asserted separately,
// and any error recorded inside the collector still fails the test.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
  final errors = <FlutterErrorDetails>[];
  final originalOnError = FlutterError.onError;
  FlutterError.onError = (details) => errors.add(details);
  try {
    await body();
  } finally {
    FlutterError.onError = originalOnError;
  }
  expect(errors, isEmpty, reason: reason);
}
