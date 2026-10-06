// Tests of the merged notes band's shared geometry
// (lib/domain/band_layout.dart): the per-day zone layout both renderers
// consume — the cycle tab's band Stack (lib/ui) and the PDF's merged band
// row (lib/pdf) must compute the same offsets. Every zone height and the
// slot mapping are pinned here so neither renderer can drift.
import 'package:cycle_app/domain/band_layout.dart';
import 'package:cycle_app/domain/cervix.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime d(int day) => DateTime.utc(2026, 9, day);

void main() {
  group('notesBandLayout (the per-day zone offsets)', () {
    test('an untracked day reserves nothing', () {
      final zones = notesBandLayout(null);
      expect(zones.hasCervix, isFalse, reason: 'no cervix observation');
      expect(zones.hasPain, isFalse, reason: 'no pain');
      expect(zones.slotIndex, isNull, reason: 'no glyph-zone ink');
      expect(zones.opening, isNull);
      expect(zones.noteTop, 0, reason: 'the note zone spans the full band');
    });

    test('a full stack day: circle in the position slot, pain row between '
        'the letter row and the note zone', () {
      final zones = notesBandLayout(
        DailyEntry(
          date: d(21),
          cervixPosition: CervixPosition.low,
          cervixOpening: CervixOpening.open,
          cervixFirmness: CervixFirmness.soft,
          painBreast: true,
        ),
      );
      expect(zones.hasCervix, isTrue);
      expect(zones.opening, CervixOpening.open);
      expect(zones.slotIndex, cervixSlotIndex(CervixPosition.low));
      expect(zones.hasPain, isTrue);
      // The reserved block: glyph zone + letter row, then the pain row.
      expect(zones.painRowTop, cervixGlyphZoneHeight + cervixLetterRowHeight);
      expect(zones.noteTop, zones.painRowTop + painRowHeight);
      expect(zones.noteTop, lessThan(notesBandHeight));
    });

    test('an opening value is the only glyph: the position without an '
        'opening reserves the zone but paints nothing', () {
      final zones = notesBandLayout(
        DailyEntry(date: d(21), cervixPosition: CervixPosition.veryHigh),
      );
      expect(zones.hasCervix, isTrue, reason: 'the zone block stays reserved');
      expect(zones.slotIndex, isNull);
      expect(zones.opening, isNull);
      expect(
        zones.noteTop,
        cervixGlyphZoneHeight + cervixLetterRowHeight,
        reason:
            'no pain row on the pain-free day — the note zone starts '
            'below the reserved cervix block',
      );
    });

    test('an opening-only day takes the medium slot', () {
      final zones = notesBandLayout(
        DailyEntry(date: d(21), cervixOpening: CervixOpening.closed),
      );
      expect(zones.opening, CervixOpening.closed);
      expect(zones.slotIndex, cervixSlotIndex(CervixPosition.medium));
    });

    test('a pain day reserves its row; pain-free days never do', () {
      final painDay = notesBandLayout(
        DailyEntry(date: d(21), painBreast: true),
      );
      expect(painDay.hasCervix, isFalse);
      expect(painDay.painRowTop, 0, reason: 'the pain row takes the band top');
      expect(painDay.noteTop, painRowHeight);

      final firmnessDay = notesBandLayout(
        DailyEntry(date: d(21), cervixFirmness: CervixFirmness.hard),
      );
      expect(firmnessDay.hasPain, isFalse);
      expect(
        firmnessDay.painRowTop,
        cervixGlyphZoneHeight + cervixLetterRowHeight,
        reason:
            'the firmness-only day reserves the whole cervix block — '
            'the pain row leaves no gap',
      );
      expect(firmnessDay.noteTop, firmnessDay.painRowTop);
    });
  });

  group('cervix slots (the glyph zone\'s even spacing)', () {
    test('the slot index counts top-down: unreachable past everything, low '
        'lowest', () {
      expect(cervixSlotIndex(CervixPosition.unreachable), 0);
      expect(cervixSlotIndex(CervixPosition.veryHigh), 1);
      expect(cervixSlotIndex(CervixPosition.high), 2);
      expect(cervixSlotIndex(CervixPosition.medium), 3);
      expect(cervixSlotIndex(CervixPosition.low), 4);
    });

    test('the slot centers span the zone evenly: the topmost slot at the '
        "top's edge room, low at the bottom's", () {
      const edge = cervixOpenCircleSize / 2 + cervixCircleStrokeWidth;
      expect(cervixSlotCenterY(0), closeTo(edge, 1e-9));
      expect(cervixSlotCenterY(4), closeTo(cervixGlyphZoneHeight - edge, 1e-9));
      // Evenly stepped: consecutive slots share one interval.
      expect(
        cervixSlotCenterY(2) - cervixSlotCenterY(1),
        closeTo(cervixSlotCenterY(1) - cervixSlotCenterY(0), 1e-9),
      );
    });
  });
}
