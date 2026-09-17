// Tests for the "Zeichen der Fruchtbarkeit" vocabulary (NER cheat sheet):
// signs t / Ø(nichts) / f / S / A(Ausfluss) plus the quality qualifiers that
// are only valid together with S. Enum NAMES are the stable storage keys
// (database + export), so the token-set tests below pin them — a rename is a
// data migration.

import 'package:cycle_app/domain/mucus.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MucusSign vocabulary', () {
    test('token set is exactly the cheat-sheet signs', () {
      expect(
        MucusSign.values.map((s) => s.name),
        unorderedEquals(const ['t', 'nothing', 'f', 's', 'a']),
      );
    });

    test('a (Ausfluss) carries no quality — quality stays S-only', () {
      // 'A' is a discharge observation, not the mucus sign S; like every
      // non-S sign it must never carry a quality qualifier.
      expect(
        sanitizeMucusPair(sign: MucusSign.a, quality: MucusQuality.ew),
        (sign: MucusSign.a, quality: null),
      );
      expect(
        () => DailyEntry(
          date: DateTime(2026, 6, 15),
          mucusSign: MucusSign.a,
          mucusQuality: MucusQuality.gl,
        ),
        throwsA(isA<AssertionError>()),
      );
      expect(
        mucusDisplay(sign: MucusSign.a, quality: MucusQuality.ew),
        (symbol: 'A', superscript: null),
      );
    });

    test('tryParseMucusSign round-trips every token', () {
      for (final sign in MucusSign.values) {
        expect(tryParseMucusSign(sign.name), sign);
      }
    });

    test('tryParseMucusSign rejects unknown and non-string input', () {
      expect(tryParseMucusSign('wet'), isNull);
      expect(tryParseMucusSign('S'), isNull, reason: 'tokens are lowercase');
      expect(tryParseMucusSign(''), isNull);
      expect(tryParseMucusSign(null), isNull);
      expect(tryParseMucusSign(3), isNull);
      expect(tryParseMucusSign(Object()), isNull);
    });
  });

  group('MucusQuality vocabulary', () {
    test('token set is exactly the cheat-sheet qualities', () {
      expect(
        MucusQuality.values.map((q) => q.name),
        unorderedEquals(const [
          'w',
          'mi',
          'cr',
          'kl',
          'glb',
          'g',
          'ew',
          'gl',
          'fl',
          'ns',
        ]),
      );
    });

    test('gl and glb are distinct quality values (prefix collision)', () {
      expect(MucusQuality.gl, isNot(MucusQuality.glb));
      expect(MucusQuality.gl.name, 'gl');
      expect(MucusQuality.glb.name, 'glb');
    });

    test('tryParseMucusQuality round-trips every token', () {
      for (final quality in MucusQuality.values) {
        expect(tryParseMucusQuality(quality.name), quality);
      }
    });

    test('tryParseMucusQuality distinguishes gl from glb tokens', () {
      expect(tryParseMucusQuality('gl'), MucusQuality.gl);
      expect(tryParseMucusQuality('glb'), MucusQuality.glb);
    });

    test('tryParseMucusQuality rejects unknown and non-string input', () {
      expect(tryParseMucusQuality('milky'), isNull);
      expect(tryParseMucusQuality('EW'), isNull,
          reason: 'tokens are lowercase');
      expect(tryParseMucusQuality(null), isNull);
      expect(tryParseMucusQuality(2), isNull);
      expect(tryParseMucusQuality(3.5), isNull);
    });
  });

  group('quality-requires-s guard', () {
    test('quality is kept only together with sign s', () {
      final kept = sanitizeMucusPair(
        sign: MucusSign.s,
        quality: MucusQuality.ew,
      );
      expect(kept.sign, MucusSign.s);
      expect(kept.quality, MucusQuality.ew);
    });

    test('bare s without quality is valid (both null-side and empty side)', () {
      final bare = sanitizeMucusPair(sign: MucusSign.s);
      expect(bare.sign, MucusSign.s);
      expect(bare.quality, isNull);
    });

    test('any sign other than s collapses the quality to null', () {
      for (final sign in MucusSign.values.where((s) => s != MucusSign.s)) {
        final sanitized = sanitizeMucusPair(
          sign: sign,
          quality: MucusQuality.gl,
        );
        expect(sanitized.sign, sign);
        expect(sanitized.quality, isNull, reason: 'sign is ${sign.name}');
      }
    });

    test('a null sign invalidates the quality as well', () {
      final sanitized = sanitizeMucusPair(quality: MucusQuality.ns);
      expect(sanitized.sign, isNull);
      expect(sanitized.quality, isNull);
    });
  });

  group('DailyEntry mucus fields', () {
    DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);

    test('S with a quality constructs fine', () {
      final entry = DailyEntry(
        date: day(DateTime(2026, 6, 15)),
        mucusSign: MucusSign.s,
        mucusQuality: MucusQuality.ew,
      );
      expect(entry.mucusSign, MucusSign.s);
      expect(entry.mucusQuality, MucusQuality.ew);
    });

    test('bare S without a quality constructs fine', () {
      final entry = DailyEntry(
        date: day(DateTime(2026, 6, 15)),
        mucusSign: MucusSign.s,
      );
      expect(entry.mucusSign, MucusSign.s);
      expect(entry.mucusQuality, isNull);
    });

    test('non-sign observations never carry a quality (assert)', () {
      for (final sign in MucusSign.values.where((s) => s != MucusSign.s)) {
        expect(
          () => DailyEntry(
            date: day(DateTime(2026, 6, 15)),
            mucusSign: sign,
            mucusQuality: MucusQuality.ew,
          ),
          throwsA(isA<AssertionError>()),
          reason: 'sign ${sign.name} cannot have a quality',
        );
      }
      expect(
        () => DailyEntry(
          date: day(DateTime(2026, 6, 15)),
          mucusQuality: MucusQuality.ew,
        ),
        throwsA(isA<AssertionError>()),
        reason: 'a missing sign cannot have a quality either',
      );
    });

    test('quality can be set and cleared via copyWith (sentinel semantics)',
        () {
      final bare = DailyEntry(date: day(DateTime(2026, 6, 15)));
      expect(bare.copyWith(mucusSign: MucusSign.s).mucusSign, MucusSign.s);
      final withQuality =
          bare.copyWith(mucusSign: MucusSign.s, mucusQuality: MucusQuality.gl);
      expect(withQuality.mucusQuality, MucusQuality.gl);
      expect(
        withQuality.copyWith(mucusQuality: null).mucusQuality,
        isNull,
        reason: 'explicit null clears the quality',
      );
      expect(
        withQuality.copyWith().mucusQuality,
        MucusQuality.gl,
        reason: 'absent argument keeps the quality',
      );
    });
  });

  group('display symbols', () {
    test('sign symbols follow the cheat-sheet glyphs', () {
      expect(mucusSignSymbol(MucusSign.t), 't');
      expect(mucusSignSymbol(MucusSign.nothing), 'Ø');
      expect(mucusSignSymbol(MucusSign.f), 'f');
      expect(mucusSignSymbol(MucusSign.s), 'S');
      expect(mucusSignSymbol(MucusSign.a), 'A');
    });

    test('quality display tokens are the cheat-sheet tokens', () {
      expect(mucusQualityToken(MucusQuality.ew), 'EW');
      expect(mucusQualityToken(MucusQuality.gl), 'gl');
      expect(mucusQualityToken(MucusQuality.glb), 'glb');
      for (final quality in MucusQuality.values) {
        expect(mucusQualityToken(quality), isNotEmpty);
      }
    });

    test('display helper pairs the base sign with the superscript quality', () {
      // S with quality: superscript token.
      expect(
        mucusDisplay(sign: MucusSign.s, quality: MucusQuality.ew),
        (symbol: 'S', superscript: 'EW'),
      );
      expect(
        mucusDisplay(sign: MucusSign.s, quality: MucusQuality.gl),
        (symbol: 'S', superscript: 'gl'),
      );
      // Bare S: no superscript.
      expect(
        mucusDisplay(sign: MucusSign.s),
        (symbol: 'S', superscript: null),
      );
      // Non-sign observations: no superscript either (not recordable there).
      expect(
        mucusDisplay(sign: MucusSign.t),
        (symbol: 't', superscript: null),
      );
      expect(
        mucusDisplay(sign: MucusSign.f),
        (symbol: 'f', superscript: null),
      );
      // Nothing recorded at all: empty cell.
      expect(mucusDisplay(), (symbol: null, superscript: null));
      // "Nothing seen/felt" has its own glyph.
      expect(
        mucusDisplay(sign: MucusSign.nothing),
        (symbol: 'Ø', superscript: null),
      );
    });

    test('display helper never renders a quality on a non-s sign', () {
      // Defense in depth: even a mismatched input pair is displayed sanely.
      final display = mucusDisplay(
        sign: MucusSign.t,
        quality: MucusQuality.ew,
      );
      expect(display, (symbol: 't', superscript: null));
    });
  });
}
