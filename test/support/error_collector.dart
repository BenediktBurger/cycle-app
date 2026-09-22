// Shared framework-error collector for the narrow-width overflow repros:
// tests that deliberately WAIVE the pump-time exception (the single initial
// layout pass can overflow UNRELATED rows at a forced width — the documented
// narrow-width defect of the date row — while the row under test must stay
// silent) install this around the interactions that DO belong to the tested
// surface, and any error recorded there still fails the test.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs [body] with `FlutterError.onError` rerouted into a collector and
/// fails afterwards when anything was recorded: the interactions inside
/// [body] must not raise a framework exception (RenderFlex overflow). The
/// pump-time record stays the caller's business (typically
/// `tester.takeException()` right before this call).
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
