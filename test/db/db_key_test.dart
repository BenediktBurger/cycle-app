// Unit tests for the database encryption key (lib/db/db_key.dart).
//
// The load-or-create flow is exercised against an in-memory fake store —
// no platform channels involved, so these run everywhere the suite runs.
// The real store (flutter_secure_storage) is exercised only at runtime on a
// device; that on-device verification is still pending (no physical
// Android/iOS device has run this yet).
import 'dart:math';

import 'package:cycle_app/db/db_key.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [Random] replaying fixed bytes, so the generated key is deterministic.
final class _FixedRandom implements Random {
  _FixedRandom(this.values);

  final List<int> values;
  int _index = 0;

  int _next() => values[_index++ % values.length];

  @override
  bool nextBool() => _next().isOdd;

  @override
  double nextDouble() => _next() / 256;

  @override
  int nextInt(int max) => _next() % max;
}

/// An in-memory [DbKeyStore] that can be made to fail loudly.
final class _FakeStore implements DbKeyStore {
  final values = <String, String>{};
  Object? readError;
  Object? writeError;

  @override
  Future<String?> read() async {
    if (readError != null) throw readError!;
    return values[dbKeyStorageName];
  }

  @override
  Future<void> write(String value) async {
    if (writeError != null) throw writeError!;
    values[dbKeyStorageName] = value;
  }
}

void main() {
  group('generateDbKey', () {
    test('produces 64 lowercase hex characters (32 random bytes)', () {
      final key = generateDbKey();
      expect(key, hasLength(64));
      expect(key, matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('two generations differ (fresh randomness)', () {
      expect(generateDbKey(), isNot(generateDbKey()));
    });

    test('honors an injected Random for determinism', () {
      final key = generateDbKey(random: _FixedRandom([0x00, 0xff, 0x1a]));
      expect(key, startsWith('00ff1a'));
    });
  });

  group('loadOrCreateDbKey', () {
    test('creates, stores and returns a fresh key on first use', () async {
      final store = _FakeStore();
      final key = await loadOrCreateDbKey(store: store);
      expect(key, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(store.values, {dbKeyStorageName: key});
    });

    test('reuses the stored key on subsequent calls', () async {
      final store = _FakeStore();
      final first = await loadOrCreateDbKey(store: store);
      final second = await loadOrCreateDbKey(store: store);
      expect(second, first);
    });

    test('a failed read surfaces loudly — no fallback to a plaintext DB',
        () async {
      final store = _FakeStore()..readError = Exception('keystore locked');
      await expectLater(
        loadOrCreateDbKey(store: store),
        throwsA(isA<DbKeyException>()),
      );
    });

    test('a failed write surfaces loudly and stores nothing', () async {
      final store = _FakeStore()..writeError = Exception('disk full');
      await expectLater(
        loadOrCreateDbKey(store: store),
        throwsA(isA<DbKeyException>()),
      );
      expect(store.values, isEmpty, reason: 'no half-persisted key');
    });

    test('the exception names the failing phase and the cause', () async {
      final store = _FakeStore()..readError = Exception('keystore locked');
      try {
        await loadOrCreateDbKey(store: store);
        fail('expected DbKeyException');
      } on DbKeyException catch (e) {
        expect(e.message, contains('read'));
        expect(e.toString(), contains('keystore locked'));
      }
    });
  });
}
