// Shared test-view helpers for the widget tests — the viewport and
// platform-dispatcher state the scenarios kept copy-pasting between files.
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

/// Forces the test view to the given LOGICAL size (device pixel ratio 1), so
/// scenarios can size viewport-dependent layouts directly (e.g. the adaptive
/// shell's breakpoint); restored at test end.
void useViewportSize(WidgetTester tester, Size logicalSize) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = logicalSize;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Forces a 320x800 dp Android-class SMALL phone viewport — the minimum
/// usable width the date-row/narrow-width repros pump at; restored at test
/// end.
void useNarrowPhoneViewport(WidgetTester tester) {
  useViewportSize(tester, const Size(320, 800));
}

/// Enlarges the test surface over a WIDE, tall viewport (default 800x2400
/// dp): a lazy vertical list only builds the viewport's visible children, so
/// content below the default 800x600 test surface is not even BUILT and
/// finders miss it (the entry form's save button, the diary day tiles, the
/// cycle screen's day-options panel and evaluation table). The previous
/// surface is restored at test end.
void useTallSurface(WidgetTester tester,
    {double width = 800, double height = 2400}) {
  useViewportSize(tester, Size(width, height));
}

/// Pins the device locales the running app sees — the "system language"
/// path. Tests that assert a specific language through the SYSTEM (the
/// appScope harness's `locale:` pin bypasses the system-follow default)
/// call this and leave the locale provider at its default. Restored at
/// test end.
void useDeviceLocales(WidgetTester tester, List<Locale> locales) {
  tester.platformDispatcher.localesTestValue = locales;
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
}

/// Darkens the device's reported platform brightness — the "System"
/// theme-follow path. Restored (along with the dispatcher's other test
/// values) at test end.
void useDarkDeviceBrightness(WidgetTester tester) {
  tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
  addTearDown(tester.platformDispatcher.clearAllTestValues);
}
