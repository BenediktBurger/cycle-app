// Widget tests of the Tagebuch screen's stream error surfaces: a failed
// marks stream or entries stream shows the shared retry surface in the
// cycle-list area (instead of rendering content from silently-empty data),
// the entry form above stays intact, and tapping the retry button
// re-subscribes the stream so the real content returns. The streams are
// attempt-counter factories: invoked once per provider (re-)subscription,
// the first attempt fails and the retry attempt delivers the data.
//
// Locale pinned to en so the localized failure assertions are literal.
import 'package:cycle_app/domain/date_only.dart';
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/l10n/app_localizations.dart';
import 'package:cycle_app/providers.dart';
import 'package:cycle_app/ui/diary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/viewport.dart';

// Two recorded days, no cycleStart marks — one leading cycle group whose
// tiles render from entries data alone.
final _diaryDay = DateOnly.normalize(DateTime(2026, 9, 5));

final _diaryEntries = [
  DailyEntry(date: _diaryDay, bbtC: 36.4, bleeding: Bleeding.heavy),
  DailyEntry(date: DateOnly.addDays(_diaryDay, 1), bbtC: 36.5),
];

const _diaryMarks = <CycleMark>[];

/// Pump shape of the chart-list tests (support/cycle_list_harness.dart),
/// pointed at the Tagebuch screen: the two stream providers overridden with
/// attempt-counter factories, en locale delegates, one Scaffold home.
Widget errorScope({
  required List<DailyEntry> entries,
  Stream<List<DailyEntry>> Function()? entriesStreamFactory,
  Stream<List<CycleMark>> Function()? marksStreamFactory,
}) => ProviderScope(
  overrides: [
    dailyEntriesProvider.overrideWith(
      (ref) => entriesStreamFactory?.call() ?? Stream.value(entries),
    ),
    marksProvider.overrideWith(
      (ref) => marksStreamFactory?.call() ?? Stream.value(_diaryMarks),
    ),
    selectedDateProvider.overrideWith((ref) => _diaryDay),
  ],
  child: MaterialApp(
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
    ),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: const Scaffold(body: TagebuchScreen()),
  ),
);

void main() {
  testWidgets('a marks stream error shows the retry surface in the '
      'cycle-list area while the entry form stays intact; retry renders '
      'the list', (tester) async {
    useTallSurface(tester);
    var attempt = 0;
    await tester.pumpWidget(
      errorScope(
        entries: _diaryEntries,
        marksStreamFactory: () {
          attempt++;
          return attempt == 1
              ? Stream<List<CycleMark>>.error(StateError('injected error'))
              : Stream.value(_diaryMarks);
        },
      ),
    );
    await tester.pumpAndSettle();

    // The form above stays usable (its writes do not depend on marks).
    expect(find.byKey(const ValueKey('diarySaveAction')), findsOneWidget);
    // NOT the cycle tiles computed from silently-empty marks.
    expect(find.byType(ExpansionTile), findsNothing);
    expect(
      find.byKey(const ValueKey('marksStreamRetryButton')),
      findsOneWidget,
    );
    expect(find.text('Loading failed'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('marksStreamRetryButton')));
    await tester.pumpAndSettle();

    expect(
      find.byType(ExpansionTile),
      findsOneWidget,
      reason:
          'the retry re-subscribed the marks provider and the list '
          'rendered again',
    );
    expect(attempt, 2, reason: 'the retry re-invoked the stream factory');
  });

  testWidgets('an entries stream error carries the retry affordance; retry '
      'renders the cycle list', (tester) async {
    useTallSurface(tester);
    var attempt = 0;
    await tester.pumpWidget(
      errorScope(
        entries: _diaryEntries,
        entriesStreamFactory: () {
          attempt++;
          return attempt == 1
              ? Stream<List<DailyEntry>>.error(StateError('injected error'))
              : Stream.value(_diaryEntries);
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ExpansionTile), findsNothing);
    expect(find.text('Loading failed'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('entriesStreamRetryButton')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('entriesStreamRetryButton')));
    await tester.pumpAndSettle();

    expect(find.byType(ExpansionTile), findsOneWidget);
    expect(attempt, 2);
  });
}
