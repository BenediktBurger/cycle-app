// DiaryTrack: which diary entry items (temperature / mucus / cervix / sex /
// pain) the user tracks — the settings card's value type and the diary
// form's visibility source. Plain Dart (no flutter_test bindings needed
// beyond the test framework), pinned here headless like the other domain
// values.
import 'package:cycle_app/domain/diary_track.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('defaults', () {
    test('temperature, mucus, sex and pain tracked, cervix not', () {
      expect(DiaryTrack.defaults.temperature, isTrue);
      expect(DiaryTrack.defaults.mucus, isTrue);
      expect(DiaryTrack.defaults.cervix, isFalse);
      expect(DiaryTrack.defaults.sex, isTrue);
      expect(DiaryTrack.defaults.pain, isTrue);
    });

    test('temperature is the first item of the enum', () {
      expect(
        DiaryItem.values.first,
        DiaryItem.temperature,
        reason: 'the settings card lists the switches in enum order',
      );
      expect(DiaryItem.values, [
        DiaryItem.temperature,
        DiaryItem.mucus,
        DiaryItem.cervix,
        DiaryItem.sex,
        DiaryItem.pain,
      ]);
    });

    test('isTracked covers every item of the enum', () {
      expect(DiaryTrack.defaults.isTracked(DiaryItem.temperature), isTrue);
      expect(DiaryTrack.defaults.isTracked(DiaryItem.mucus), isTrue);
      expect(DiaryTrack.defaults.isTracked(DiaryItem.cervix), isFalse);
      expect(DiaryTrack.defaults.isTracked(DiaryItem.sex), isTrue);
      expect(DiaryTrack.defaults.isTracked(DiaryItem.pain), isTrue);
    });

    test(
      'withTracked flips exactly one item (the settings switches\' write)',
      () {
        final tracked = DiaryTrack.defaults.withTracked(DiaryItem.cervix, true);
        expect(tracked, const DiaryTrack(cervix: true));
        expect(
          tracked.withTracked(DiaryItem.cervix, false),
          DiaryTrack.defaults,
        );

        final painOff = DiaryTrack.defaults.withTracked(DiaryItem.pain, false);
        expect(painOff, const DiaryTrack(pain: false));
        expect(painOff.withTracked(DiaryItem.pain, true), DiaryTrack.defaults);

        final tempOff = DiaryTrack.defaults.withTracked(
          DiaryItem.temperature,
          false,
        );
        expect(tempOff, const DiaryTrack(temperature: false));
        expect(
          tempOff.withTracked(DiaryItem.temperature, true),
          DiaryTrack.defaults,
        );
      },
    );
  });

  group('JSON round-trip', () {
    test('toJson/fromJson preserve all five choices', () {
      const tracked = DiaryTrack(
        temperature: false,
        mucus: false,
        cervix: true,
        sex: false,
        pain: false,
      );
      final restored = DiaryTrack.fromJson(tracked.toJson());
      expect(restored, tracked);
    });

    test('the defaults round-trip as themselves', () {
      expect(
        DiaryTrack.fromJson(DiaryTrack.defaults.toJson()),
        DiaryTrack.defaults,
      );
    });
  });

  group('equality', () {
    test('equal values are equal and hash alike', () {
      expect(DiaryTrack.fromJson({}), DiaryTrack.fromJson({}));
      expect(
        DiaryTrack.fromJson({}).hashCode,
        DiaryTrack.fromJson({}).hashCode,
      );
      expect(DiaryTrack.defaults, isNot(const DiaryTrack(cervix: true)));
    });
  });

  group('fromJson fallbacks', () {
    test('missing items fall back item-by-item to their defaults', () {
      final partial = DiaryTrack.fromJson({'cervix': true});
      expect(
        partial.mucus,
        isTrue,
        reason: 'mucus absent from the map keeps its default (tracked)',
      );
      expect(partial.cervix, isTrue);
      expect(
        partial.sex,
        isTrue,
        reason: 'sex absent from the map keeps its default (tracked)',
      );
    });

    test('a pre-pain row without the pain key decodes pain tracked', () {
      final restored = DiaryTrack.fromJson({
        'mucus': false,
        'cervix': true,
        'sex': false,
      });
      expect(
        restored.pain,
        isTrue,
        reason: 'a stored map predating the pain item keeps pain visible',
      );
    });

    test(
      'a pre-temperature row without the temperature key decodes it tracked',
      () {
        final restored = DiaryTrack.fromJson({
          'mucus': false,
          'cervix': true,
          'sex': false,
          'pain': true,
        });
        expect(
          restored.temperature,
          isTrue,
          reason:
              'a stored map predating the temperature item keeps the '
              'section visible',
        );
      },
    );

    test('mistyped items fall back item-by-item to their defaults', () {
      final mistyped = DiaryTrack.fromJson({
        'mucus': 'yes', // string, not boolean
        'cervix': 1, // number, not boolean
        'sex': [], // list, not boolean
        'pain': 2, // number, not boolean
      });
      expect(
        mistyped,
        DiaryTrack.defaults,
        reason:
            'every non-boolean item degrades to its own default, never '
            'an error',
      );
    });

    test('unknown keys in a stored map are ignored (forward compat)', () {
      final restored = DiaryTrack.fromJson({
        'mucus': true,
        'cervix': true,
        'sex': false,
        'flow': true, // a future item's key, unknown to this version
      });
      expect(
        restored,
        const DiaryTrack(mucus: true, cervix: true, sex: false),
        reason: 'unknown item keys never change the known items',
      );
    });
  });
}
