// PDF export smoke script (NOT part of the shipped test suite): builds a
// small PDF export document from a fixed fixture, like the database/export
// smoke scripts do for the host VM (see tool/db_smoke.dart).
//
// The pdf package is pure Dart, so this runs anywhere:
//   dart run tool/pdf_smoke.dart
// Prints byte-level and structural facts; writes nothing to disk.

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/domain/mucus.dart';
import 'package:cycle_app/domain/pdf_export_model.dart';
import 'package:cycle_app/pdf/cycle_pdf.dart';
import 'package:cycle_app/pdf/pdf_layout.dart';

void check(bool condition, String label) {
  if (!condition) throw StateError('SMOKE FAIL: $label');
  print('ok   $label');
}

DateTime d(int month, int day) => DateTime.utc(2026, month, day);

/// Three mark-opened cycles in 2026 (starts Mar 1, Mar 29, Apr 26) — the
/// third one a pregnancy-style 120-day window opening at Apr 26, spanning
/// several pages under the default column budget. The entries do NOT
/// overflow a cycle's start (each tracked day belongs to exactly one
/// cycle): cycle 2 tracks its 28 days up to the next start.
///
/// The first (28-day) cycle carries the render-relevant material the
/// symbol/overlay rows draw: a mucus peak, a first higher measurement, a
/// user-placed SUZ morning mark and an ignoreTemperature day; one dense
/// day carries mucus with quality, sex, a measurement time and disturbance
/// flags. The document generation reads all of it through the (unmodified)
/// model derivation.
List<DailyEntry> fixtureEntries() => [
  for (var i = 0; i < 28; i++)
    DailyEntry(
      date: d(3, 1 + i),
      bbtC: 36.0 + (i % 10) / 10,
      measuredAtMinutes: i == 12 ? 8 * 60 + 33 : null,
      mucusSign: i == 12 ? MucusSign.s : null,
      mucusQuality: i == 12 ? MucusQuality.ew : null,
      sexTimings: i == 12 ? 3 : 0,
      tempDisturbances: i == 12
          ? TempDisturbance.sp.bit | TempDisturbance.alk.bit
          : 0,
      notes: i == 3 ? 'Schmierblutung im Büro ß' : 'Ж α ž',
    ),
  for (var i = 0; i < 28; i++) DailyEntry(date: d(3, 29 + i), bbtC: 36.2),
  for (var i = 0; i < 120; i++) DailyEntry(date: d(4, 26 + i), bbtC: 36.9),
];

List<CycleMark> fixtureMarks() => [
  // Cycle 1 (Mar 1–28).
  CycleMark(date: d(3, 1), type: CycleMarkTypes.cycleStart),
  CycleMark(date: d(3, 14), type: CycleMarkTypes.ignoreTemperature),
  CycleMark(date: d(3, 16), type: CycleMarkTypes.mucusPeakDay),
  CycleMark(date: d(3, 17), type: CycleMarkTypes.firstHigherMeasurement),
  CycleMark(date: d(3, 18), type: CycleMarkTypes.suzMorning),
  // Cycles 2 and 3: bare starts.
  CycleMark(date: d(3, 29), type: CycleMarkTypes.cycleStart),
  CycleMark(date: d(4, 26), type: CycleMarkTypes.cycleStart),
];

/// Counts the uncompressed page markers the same way the widget-side
/// generation tests do: with `compress: false` every page object
/// dictionary appears verbatim as `/Type/Page/` (the `/Pages` node does
/// not match — its "Page" is followed by an "s", not a "/").
int countPageMarkers(List<int> bytes) {
  final pattern = '/Type/Page/'.codeUnits;
  var count = 0;
  for (var i = 0; i + pattern.length <= bytes.length; i++) {
    var matched = true;
    for (var j = 0; j < pattern.length; j++) {
      if (bytes[i + j] != pattern[j]) {
        matched = false;
        break;
      }
    }
    if (matched) count++;
  }
  return count;
}

Future<void> main() async {
  final fontBytes = await File(
    'assets/fonts/NotoSans-Regular.ttf',
  ).readAsBytes();
  check(fontBytes.isNotEmpty, 'bundled Noto Sans TTF is present');

  final model = buildPdfExportModel(
    entries: fixtureEntries(),
    marks: fixtureMarks(),
    observedCyclesOutsideApp: 4,
    name: 'Maria Muster',
    birthDate: d(12, 24),
    // The span rule (a cycle runs to the next start mark / today) extends
    // the LAST cycle — here the pregnancy-style 120-day fixture (Apr 26 –
    // Aug 23, all tracked) out to the pinned today (Sep 21): 149 days, so
    // it takes 4 pages under the 40-column budget. Pinned for
    // determinism; production passes the wall clock (nowProvider).
    today: d(9, 21),
  );
  check(model.cycles.length == 3, 'three mark-opened cycles exported');
  check(model.observedCycleCount == 7, 'count includes 4 outside-app cycles');
  // The extension: the last cycle's day list gains the data-less days
  // from its last tracked day (Aug 23) out to the pinned today.
  check(
    model.cycles.last.cycle.days.length == 149,
    'the last cycle extends through the pinned today: Apr 26 - Sep 21 (149 '
    'days, 120 tracked + 29 data-less)',
  );

  final overlay = model.overlays[0];
  check(
    overlay.peakIndexes.contains(15),
    'the placed mucus-peak mark maps to cycle day 16\'s index',
  );
  check(
    overlay.ignoredIndexes.contains(13),
    'the ignoreTemperature mark indexes the marked day',
  );
  check(
    overlay.suzMarks.any((m) => m.morning && m.dayIndex == 17),
    'the user-placed SUZ morning mark is carried into the overlay',
  );
  check(
    overlay.circledIndexes.isNotEmpty || overlay.arrowIndexes.isNotEmpty,
    'the first-higher mark derives a candidate mark',
  );

  final plan = planCyclePages(
    model.cycles.map((e) => e.cycle.days.length).toList(),
  );
  check(
    plan.length == 6,
    'column budget 40: the two short cycles need 1 page each, the '
    '149-day extended last cycle 4 pages = 6',
  );
  check(
    plan.every((w) => w.dayCount <= defaultMaxDaysPerPage),
    'no page window exceeds the column budget',
  );
  check(
    plan.where((w) => w.cycleIndex == 2).length == 4,
    'the pregnancy-style cycle continues across four pages',
  );

  final bytes = await generatePdfBytes(
    model: model,
    fontBytes: fontBytes,
    options: PdfExportOptions(anonymized: true, exportDate: d(9, 21)),
    compress: false, // page markers stay countable (structural check only)
  );
  check(bytes.isNotEmpty, 'the generated document is non-empty');
  final signature = '%PDF-'.codeUnits;
  check(
    bytes.sublist(0, signature.length).toString() == signature.toString(),
    'the byte stream starts with the PDF signature',
  );
  check(
    countPageMarkers(bytes) == plan.length,
    'page-marker count equals the planned page count (${plan.length})',
  );
  print('     document bytes: ${bytes.length}, pages: ${plan.length}');

  print('\nAll PDF export smoke checks passed.');
}
