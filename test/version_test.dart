// The version mirror contract: `lib/version.dart` carries the human-facing
// app version as a constant that MUST match pubspec.yaml's `version:` entry.
// A release that bumps pubspec.yaml must bump the constant in the same
// change — this test reads pubspec.yaml directly (flutter test's cwd is the
// project root) and fails the release otherwise, so the about/onboarding
// page never drifts from the shipped version.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cycle_app/version.dart';

void main() {
  test('appVersion mirrors the pubspec.yaml version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match =
        RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec);
    expect(match, isNotNull,
        reason: 'pubspec.yaml must contain a version: entry');

    expect(appVersion, match!.group(1),
        reason: 'the about page shows appVersion from lib/version.dart — '
            'it must mirror pubspec.yaml exactly (bump both together)');
  });
}
