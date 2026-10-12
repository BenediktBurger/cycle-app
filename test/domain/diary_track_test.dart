// DiaryTrack: which diary entry items (mucus / cervix / sex) the user
// tracks — the settings card's value type and the diary form's visibility
// source. Plain Dart (no flutter_test bindings needed beyond the test
// framework), pinned here headless like the other domain values.
import 'package:cycle_app/domain/diary_track.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('defaults', () {
    test('mucus and sex tracked, cervix not', () {
      expect(DiaryTrack.defaults.mucus, isTrue);
      expect(DiaryTrack.defaults.cervix, isFalse);
      expect(DiaryTrack.defaults.sex, isTrue);
    });

    test('isTracked covers every item of the enum', () {
      expect(DiaryTrack.defaults.isTracked(DiaryItem.mucus), isTrue);
      expect(DiaryTrack.defaults.isTracked(DiaryItem.cervix), isFalse);
      expect(DiaryTrack.defaults.isTracked(DiaryItem.sex), isTrue);
    });

    test(
      'withTracked flips exactly one item (the settings switches\' write)',
      () {
        final tracked = DiaryTrack.defaults.withTracked(DiaryItem.cervix, true);
        expect(tracked, const DiaryTrack(cervix: true));
        expect(DiaryTrack.defaults, DiaryTrack.defaults);
        expect(
          tracked.withTracked(DiaryItem.cervix, false),
          DiaryTrack.defaults,
        );
      },
    );
  });

  group('JSON round-trip', () {
    test('toJson/fromJson preserve all three choices', () {
      const tracked = DiaryTrack(mucus: false, cervix: true, sex: false);
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

    test('mistyped items fall back item-by-item to their defaults', () {
      final mistyped = DiaryTrack.fromJson({
        'mucus': 'yes', // string, not boolean
        'cervix': 1, // number, not boolean
        'sex': [], // list, not boolean
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
        'pain': true, // a future item's key, unknown to this version
      });
      expect(
        restored,
        const DiaryTrack(mucus: true, cervix: true, sex: false),
        reason: 'unknown item keys never change the known items',
      );
    });

    test('equal values are equal and hash alike', () {
      expect(DiaryTrack.fromJson({}), DiaryTrack.fromJson({}));
      expect(
        DiaryTrack.fromJson({}).hashCode,
        DiaryTrack.fromJson({}).hashCode,
      );
      expect(DiaryTrack.defaults, isNot(const DiaryTrack(cervix: true)));
    });
  });
}
