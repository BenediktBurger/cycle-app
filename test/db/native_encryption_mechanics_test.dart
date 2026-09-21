// Integration check for the native database encryption mechanics
// (ADR-005): the SQLite3MultipleCiphers build comes out of the sqlite3
// hook user-define in pubspec.yaml, and the `PRAGMA key` flow that
// lib/db/database_opener.dart applies in its native `setup` must actually
// encrypt the file — and a wrong key must not silently read plaintext.
//
// These tests run against the SAME sqlite3 binding the app's
// NativeDatabase uses, so they double as a host-side tripwire for the
// hook configuration. The setup steps under test are the production ones:
// the shared applyCipherAndKey helper from lib/db/cipher_setup.dart is
// exactly what the opener's native `setup` applies.
//
// Not covered here — deliberately: the platform key store (the
// production flutter_secure_storage store in lib/db/db_key.dart needs
// emulators/devices) and the web executor (stays unencrypted per
// ADR-005).
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart' show NativeDatabase;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:cycle_app/db/cipher_setup.dart';
import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/db/db_key.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync();
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('the raw binding behind NativeDatabase is a cipher build', () {
    final db = sqlite3.openInMemory();
    try {
      expect(db.select('PRAGMA cipher;'), isNotEmpty);
    } finally {
      db.close();
    }
  });

  test('an encrypted database file is ciphertext on disk, keyed reads work',
      () async {
    final key = generateDbKey();
    final file = File('${tempDir.path}/encrypted.sqlite');

    // Write through drift with the opener's setup applied.
    final writer = CycleDatabase(
      NativeDatabase(file, setup: (rawDb) => applyCipherAndKey(rawDb, key)),
    );
    try {
      await writer.entriesDao.upsertByDate(
        CycleEntriesCompanion.insert(
          date: DateTime(2026, 9, 21),
        ).copyWith(bbtC: const Value(36.6)),
      );
    } finally {
      await writer.close();
    }

    // The file on disk carries anything but the plaintext SQLite header.
    final header = file.readAsBytesSync().sublist(0, 15);
    expect(
      String.fromCharCodes(header),
      isNot('SQLite format 3'),
      reason: 'the database file must not be plaintext at rest',
    );

    // Reopen with the correct key: the data is there.
    final reader = CycleDatabase(
      NativeDatabase(file, setup: (rawDb) => applyCipherAndKey(rawDb, key)),
    );
    try {
      final rows = await reader.entriesDao.allEntries();
      final row = rows.single;
      // Calendar-day identity, not wall-clock instants (the converter
      // round-trips DateTime in UTC).
      expect(row.date.year, 2026);
      expect(row.date.month, 9);
      expect(row.date.day, 21);
      expect(row.bbtC, 36.6);
    } finally {
      await reader.close();
    }
  });

  test('a wrong key cannot read the database', () async {
    final key = generateDbKey();
    final file = File('${tempDir.path}/locked.sqlite');

    final writer = CycleDatabase(
      NativeDatabase(file, setup: (rawDb) => applyCipherAndKey(rawDb, key)),
    );
    try {
      await writer.entriesDao.upsertByDate(
        CycleEntriesCompanion.insert(date: DateTime(2026, 9, 21)),
      );
    } finally {
      await writer.close();
    }

    // The adversarial view: cipher build present, wrong key. Any read of
    // schema or data fails instead of yielding values.
    final intruder = sqlite3.open(file.path);
    try {
      intruder.execute("PRAGMA key = '${'0' * 64}'");
      expect(
        () => intruder.select('select count(*) from sqlite_master'),
        throwsA(isA<SqliteException>()),
      );
    } finally {
      intruder.close();
    }
  });

  test('unkeyed opens remain plaintext-capable', () {
    // Sanity anchor: the suite (migration tests, host smoke scripts) also
    // opens plaintext files — those must keep working without any key.
    final file = File('${tempDir.path}/plain.sqlite');
    final db = sqlite3.open(file.path);
    try {
      expect(db.select('select 42 as answer;').first['answer'], 42);
    } finally {
      db.close();
    }
  });
}
