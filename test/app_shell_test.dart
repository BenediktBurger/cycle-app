// Phase-1 widget test: pure widget smoke test of the app shell.
// Requires no database, no platform channels, no FFI, no files.
//
// `flutter test` runs the l10n codegen from l10n.yaml automatically, so the
// import of the generated AppLocalizations (via `package:cycle_app/main.dart`)
// resolves on first run.
import 'package:cycle_app/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app shell shows the four navigation destinations (German)', (
    WidgetTester tester,
  ) async {
    // The app hard-codes Locale('de') in Phase 1, so the expected labels are
    // the German strings from the template ARB.
    await tester.pumpWidget(const ProviderScope(child: CycleApp()));

    const labels = ['Tagebuch', 'Zyklus', 'Statistik', 'Einstellungen'];
    for (final label in labels) {
      expect(
        find.text(label),
        findsWidgets,
        reason: 'Navigation destination "$label" should be present',
      );
    }

    // Switching tabs shows the corresponding placeholder screen.
    const switchTargets = ['Zyklus', 'Statistik', 'Einstellungen', 'Tagebuch'];
    for (final label in switchTargets) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(
        find.text(label),
        findsWidgets,
        reason: 'After tapping "$label" its screen should be shown',
      );
    }
  });
}
