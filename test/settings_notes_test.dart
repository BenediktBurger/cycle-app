// Widget test of the settings pane's note texts: the three "saved in the
// app's local storage" notes under the language, theme-mode and
// temperature-range cards are gone (users expect settings to persist), and
// the temperature-range card keeps only the useful cycle-tab note.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/database.dart';
import 'support/finders.dart';
import 'support/viewport.dart';

ProviderScope _appScope() => appScope();

/// Opens the settings tab (tap scoped to the navigation bar — the screens
/// stay mounted in the IndexedStack, so the bare 'Settings' label would be
/// ambiguous).
Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(navLabel('Settings'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'the settings pane carries no "stored locally" note anymore, only '
    'the cycle-tab note on the temperature-range card',
    (tester) async {
      // The temperature card sits below the pane's top cards (lazy
      // ListView — enlarge the surface so the whole card list is built).
      useTallSurface(tester, width: 900);
      await tester.pumpWidget(_appScope());
      await tester.pumpAndSettle();
      await _openSettings(tester);

      // The persistence sentence is the same English string under three
      // cards (and its temperature variant continues into the default hint);
      // both substring probes cover all of them.
      expect(
        find.textContaining("the app's local storage"),
        findsNothing,
        reason:
            'the superfluous "settings are stored" note is gone — '
            'users expect settings to persist',
      );
      expect(
        find.textContaining('restored on the next app start'),
        findsNothing,
        reason: 'no card repeats the persistence sentence anymore',
      );

      // The temperature-range card keeps the useful note as its only one.
      expect(
        find.text(
          'Visible range of the temperature chart on the cycle tab. '
          'Default: 36–38 °C.',
        ),
        findsOneWidget,
        reason:
            'the cycle-tab note is the only note left '
            'on the temperature-range card',
      );
    },
  );
}
