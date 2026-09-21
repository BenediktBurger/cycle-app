// Shared test-view helpers for the widget tests — the viewport state the
// small-device repro scenarios kept copy-pasting between files.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Shrinks the test view to a 360x640 dp Android-class device and restores
/// the view at test end. The teardown also resets the keyboard inset, so a
/// scenario that leaves a fake IME up cannot leak into the next test.
void useSmallAndroidViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 3.0;
  tester.view.physicalSize = const Size(1080, 1920);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
    tester.view.resetViewInsets();
  });
}
