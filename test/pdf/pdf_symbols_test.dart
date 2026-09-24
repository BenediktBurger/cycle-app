// Tests of the PDF layer's pure per-day symbol mappings
// (lib/pdf/pdf_symbols.dart): the display mapping of a recorded day's
// observations onto the paper form's cell contents — bleeding fill, mucus
// glyph + quality superscript, sex/cervix/pain/disturbance letters, and
// the measurement-time text. Every helper DELEGATES to the existing domain
// display helpers where they exist (mucusDisplay, the cervix symbols, the
// temperature-disturbance letter vocabulary) — nothing is reworded here.
import 'package:cycle_app/domain/cervix.dart';
import 'package:cycle_app/domain/disturbances.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/domain/mucus.dart';
import 'package:cycle_app/pdf/pdf_symbols.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime _d(int month, int day, {int year = 2026}) =>
    DateTime.utc(year, month, day);

void main() {
  group('bleeding fill (level → bottom-anchored fill of the row cell)', () {
    test('level none draws nothing', () {
      expect(
        bleedingFill(Bleeding.none),
        isNull,
        reason: 'the empty cell stays empty',
      );
      final day = DailyEntry(
        date: _d(3, 2, year: 2026),
        bleeding: Bleeding.none,
      );
      expect(bleedingFill(day.bleeding), isNull);
    });

    test('spotting is the dotted fill inside the bottom quarter band', () {
      final fill = bleedingFill(Bleeding.spotting)!;
      expect(fill.dotted, isTrue, reason: 'the dotted-spotting convention');
      expect(fill.heightFraction, closeTo(1 / 4, 1e-9));
    });

    test('light … maximum fill (level − 1)/4 of the cell height, solid — '
        'mirroring the shared bleeding symbol\'s fractions', () {
      expect(
        bleedingFill(Bleeding.light)!.heightFraction,
        closeTo(1 / 4, 1e-9),
      );
      expect(bleedingFill(Bleeding.light)!.dotted, isFalse);
      expect(
        bleedingFill(Bleeding.medium)!.heightFraction,
        closeTo(2 / 4, 1e-9),
      );
      expect(
        bleedingFill(Bleeding.heavy)!.heightFraction,
        closeTo(3 / 4, 1e-9),
      );
      expect(
        bleedingFill(Bleeding.maximum)!.heightFraction,
        closeTo(1.0, 1e-9),
      );
      expect(bleedingFill(Bleeding.maximum)!.dotted, isFalse);
    });
  });

  group('mucus text (symbol + quality superscript)', () {
    test('no sign recorded draws nothing', () {
      expect(mucusText(null).symbol, isNull);
      expect(mucusText(DailyEntry(date: _d(3, 2))).symbol, isNull);
    });

    test('quality rides the S sign only — f/S carries no quality', () {
      final symbol = mucusText(
        DailyEntry(date: _d(3, 2), mucusSign: MucusSign.fs),
      );
      expect(symbol.symbol, 'f/S');
      expect(
        symbol.superscript,
        isNull,
        reason: 'the quality qualifiers stay exclusive to S',
      );
    });

    test('the quality superscript rides beneath an S sign', () {
      final withQuality = mucusText(
        DailyEntry(
          date: _d(3, 2),
          mucusSign: MucusSign.s,
          mucusQuality: MucusQuality.ew,
        ),
      );
      expect(withQuality.symbol, 'S');
      expect(withQuality.superscript, 'EW');
    });
  });

  group('letter glyphs of the strip rows', () {
    test('sex draws a single X whenever any time was recorded', () {
      expect(sexGlyph(null), isNull);
      expect(sexGlyph(DailyEntry(date: _d(3, 2))), isNull);
      expect(sexGlyph(DailyEntry(date: _d(3, 2), sexTimings: 1)), 'X');
      // Multi-bit day (several time slots): still ONE X in the PDF column.
      expect(sexGlyph(DailyEntry(date: _d(3, 2), sexTimings: 2 | 4)), 'X');
    });

    test('cervix letters combine position and firmness symbols', () {
      expect(cervixLetters(null), isNull);
      expect(
        cervixLetters(
          DailyEntry(
            date: _d(3, 2),
            cervixPosition: CervixPosition.medium,
            cervixFirmness: CervixFirmness.soft,
          ),
        ),
        'm w',
      );
      expect(
        cervixLetters(
          DailyEntry(date: _d(3, 2), cervixPosition: CervixPosition.veryHigh),
        ),
        'sh',
        reason: 'the "sehr hoch" glyph keeps its two letters to stay distinct',
      );
      // The opening is deliberately not displayed (entry-form-only field).
      expect(
        cervixLetters(
          DailyEntry(date: _d(3, 2), cervixOpening: CervixOpening.open),
        ),
        isNull,
      );
    });

    test('pain letter B (breast) and Mittelschmerz letter M', () {
      expect(painLetter(null), isNull);
      expect(painLetter(DailyEntry(date: _d(3, 2), painBreast: true)), 'B');
      expect(
        painLetter(DailyEntry(date: _d(3, 2), painMittelschmerz: true)),
        isNull,
        reason: 'Mittelschmerz M has its own row beneath the mucus letters',
      );
      expect(mittelschmerzLetter(DailyEntry(date: _d(3, 2))), isNull);
      expect(
        mittelschmerzLetter(
          DailyEntry(date: _d(3, 2), painMittelschmerz: true),
        ),
        'M',
      );
    });

    test('disturbance codes reuse the shared letter vocabulary, one code per '
        'set flag', () {
      expect(disturbanceCodes(null), isEmpty);
      expect(
        disturbanceCodes(
          DailyEntry(
            date: _d(3, 2),
            tempDisturbances: 1, // sp
          ),
        ),
        ['sp'],
      );
      final multi = disturbanceCodes(
        DailyEntry(
          date: _d(3, 2),
          tempDisturbances:
              TempDisturbance.sp.bit |
              TempDisturbance.alk.bit |
              TempDisturbance.kr.bit,
        ),
      );
      expect(multi, ['sp', 'alk', 'kr']);
      // The shared function stays the ONE letter vocabulary — the PDF
      // imports it from the domain, the chart from the same home.
      expect(disturbanceCodes, same(disturbanceLetters));
    });
  });

  group('joined note text (multi-line diary notes → one rotated line)', () {
    test('embedded line breaks fold into one line', () {
      expect(joinedNoteText('schlaflos\nab 3:00'), 'schlaflos ab 3:00');
      expect(joinedNoteText('steigt\nlangsam\nan'), 'steigt langsam an');
    });

    test('runs of whitespace collapse to a single space', () {
      expect(joinedNoteText('a\n\n  b\t c'), 'a b c');
    });

    test('single-line notes pass through, edge whitespace drops off', () {
      expect(joinedNoteText('viel EE'), 'viel EE');
      expect(joinedNoteText('  Kopfschmerz \n'), 'Kopfschmerz');
    });
  });

  group('weekend positions (the weekend band columns of one page window)', () {
    test('judged by the CALENDAR DATE, never by the column index — a window '
        'starting mid-week puts the band on Sa/So wherever they fall', () {
      // Jul 1 2026 is a Wednesday: Sa/So = Jul 4/5, positions 3 and 4 —
      // not the grid positions a mod-7 column rule would pick up.
      final days = [for (var i = 0; i < 8; i++) DailyEntry(date: _d(7, 1 + i))];
      expect(weekendPositions(days), [3, 4]);
    });

    test('Sa and So are ADJACENT columns; both get their own band', () {
      final days = [for (var i = 0; i < 2; i++) DailyEntry(date: _d(7, 4 + i))];
      expect(weekendPositions(days), [0, 1]);
    });

    test('a weekend-free window (tracked days Mon–Fri only) stays white', () {
      final days = [
        // Jul 6–10 2026 is a full Mon–Fri run; Feb 23–27 too.
        for (var i = 0; i < 5; i++) DailyEntry(date: _d(7, 6 + i)),
      ];
      expect(weekendPositions(days), isEmpty);
    });

    test('following weekend bands fall out of the dates for free — a window '
        'crossing two weekends carries both pairs', () {
      final days = [
        // Jul 11 Sa..? window Jul 8..21: two weekends: Jul 11/12 and
        // Jul 18/19 → positions 3,4,10,11.
        for (var i = 0; i < 14; i++) DailyEntry(date: _d(7, 8 + i)),
      ];
      expect(weekendPositions(days), [3, 4, 10, 11]);
    });
  });

  group('measurement time (the temperature\'s recorded time of day)', () {
    test('formats as German HH:mm, bottom edge minutes included', () {
      expect(measuredAtText(0), '00:00');
      expect(measuredAtText(8 * 60 + 5), '08:05');
      expect(measuredAtText(23 * 60 + 59), '23:59');
    });

    test('a day without a recorded time renders the empty cell', () {
      expect(
        measuredAtText(null),
        null,
        reason:
            'measuredAtMinutes is metadata of the temperature; the row '
            'only exists for days with a temperature, so null means no '
            'cell content',
      );
    });

    test('out-of-range minute values render empty (defensive, '
        'the parser guarantees 0–1439)', () {
      expect(measuredAtText(-1), null);
      expect(measuredAtText(1440), null);
    });
  });
}
