// Pure-logic tests for tool/sqlite3mc.dart — the maintenance tool keeping
// the vendored sqlite3mc amalgamation identical to the upstream pin (the
// script's header comment carries the full context).
//
// These tests deliberately stay on the pure seam: argument parsing,
// pubspec.lock version extraction, the upstream-URL parsing of
// tool/download_sqlite.dart, the recorded-provenance parsing/rewriting of
// native/sqlite3mc/README.md, and the cache-key derivation. Nothing here
// touches the network, the file system, or the repository state — the
// process layer (fetch/cache/zip/compare/update) runs in the CI step and
// was exercised for real against the vendoring it ships with.
// Relative import on purpose: tool/ scripts live outside lib/ and are not
// addressable through `package:cycle_app/`.
import '../../tool/sqlite3mc.dart';

import 'package:flutter_test/flutter_test.dart';

/// Lock-file fragment in the real pubspec.lock layout, with surrounding
/// packages to make sure the extraction keys off the right block.
const lockFixture = '''
  fake_pkg_before:
    dependency: transitive
    description:
      name: fake_pkg_before
      url: "https://pub.dev"
    source: hosted
    version: "1.0.0"
  sqlite3:
    dependency: "direct main"
    description:
      name: sqlite3
      sha256: "4c7fe79840389aaeaf05fd093f795b631b5a98e2bd28d54e555c100f4a9c7a1c"
      url: "https://pub.dev"
    source: hosted
    version: "3.5.2"
''';

/// The upstream download-script fragment as shipped at tag
/// `sqlite3-3.5.2` (verbatim constant layout, abbreviated inert parts).
const downloadScriptFixture = '''
import 'dart:io';

const sqlitePath = 'sqlite-amalgamation-3530400';
const sqliteSource = 'https://sqlite.org/2026/sqlite-amalgamation-3530400.zip';
const sqliteMultipleCiphersSource =
    'https://github.com/utelle/SQLite3MultipleCiphers/releases/download/v2.5.0/sqlite3mc-2.5.0-sqlite-3.53.4-amalgamation.zip';
''';

/// The provenance block layout as committed in native/sqlite3mc/README.md.
const readmeFixture = '''
# Vendored SQLite3MultipleCiphers amalgamation

The `sqlite3` build hook compiles this.

## Provenance

- Source archive:
  https://github.com/utelle/SQLite3MultipleCiphers/releases/download/v2.5.0/sqlite3mc-2.5.0-sqlite-3.53.4-amalgamation.zip
  (from the tooling the `sqlite3` package itself pins in
  `tool/download_sqlite.dart` at tag `sqlite3-3.5.2`)
- Content: SQLite3MultipleCiphers 2.5.0 built on SQLite 3.53.4.
  Only `sqlite3mc_amalgamation.c` and `sqlite3mc_amalgamation.h` from the
  archive are vendored here (the same two files the `sqlite3` project's
  download script copies).
- Vendored on 2026-09-22 by `dart run tool/sqlite3mc.dart update`.
- SHA-256:
  - `sqlite3mc_amalgamation.c`
    aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  - `sqlite3mc_amalgamation.h`
    bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

## Licensing
''';

void main() {
  group('argument parsing', () {
    test('accepts check with its flags', () {
      final options = parseArguments([
        'check',
        '--offline',
        '--vendored-dir',
        'tmp/my-vendoring',
      ]);
      expect(options.check, isTrue);
      expect(options.offline, isTrue);
      expect(options.dryRun, isFalse);
      expect(options.vendoredDir, 'tmp/my-vendoring');
    });

    test('defaults to the committed vendoring location', () {
      final options = parseArguments(['check']);
      expect(options.vendoredDir, defaultVendoredDir);
      expect(options.offline, isFalse);
    });

    test('accepts update with --dry-run', () {
      final options = parseArguments(['update', '--dry-run']);
      expect(options.check, isFalse);
      expect(options.dryRun, isTrue);
    });

    test('flags can come before the subcommand', () {
      final options = parseArguments(['--dry-run', 'update']);
      expect(options.dryRun, isTrue);
    });

    test('rejects an empty command line', () {
      expect(() => parseArguments(const []), throwsA(isA<UsageException>()));
    });

    test('rejects unknown arguments', () {
      for (final bad in [
        const ['--offline'],
        const ['--dry-run'],
        const ['check', 'check'],
        const ['check', 'update'],
        const ['check', 'extra'],
        const ['check', '--dry-run'],
        const ['update', '--offline'],
        const ['release', '--dry-run'],
        const ['check', '--vendored-dir'],
      ]) {
        expect(
          () => parseArguments(bad),
          throwsA(isA<UsageException>()),
          reason: 'arguments $bad must be rejected',
        );
      }
    });
  });

  group('pubspec.lock version extraction', () {
    test('reads the hosted sqlite3 version', () {
      expect(hostedSqlite3Version(lockFixture), '3.5.2');
    });

    test('rejects a lockfile without the package', () {
      expect(
        () => hostedSqlite3Version('packages:'),
        throwsA(isA<ToolException>()),
      );
    });

    test('rejects a non-hosted sqlite3 dependency', () {
      const gitSource = '''  sqlite3:
    dependency: "direct main"
    description:
      path: "."
      url: "https://github.com/simolus3/sqlite3.dart"
    source: git
    version: "3.5.2"
''';
      expect(
        () => hostedSqlite3Version(gitSource),
        throwsA(isA<ToolException>()),
      );
    });

    test('rejects a block without a version line', () {
      const broken = '''
  sqlite3:
    dependency: "direct main"
    description:
      name: sqlite3
      url: "https://pub.dev"
    source: hosted
''';
      expect(() => hostedSqlite3Version(broken), throwsA(isA<ToolException>()));
    });
  });

  group('upstream pin parsing', () {
    test('extracts pin URL and versions from the 3.5.2 script', () {
      final pin = parseAmalgamationPin(
        downloadScriptFixture,
        vendoredDir: defaultVendoredDir,
      );
      expect(
        pin.url.toString(),
        'https://github.com/utelle/SQLite3MultipleCiphers/releases/'
        'download/v2.5.0/sqlite3mc-2.5.0-sqlite-3.53.4-amalgamation.zip',
      );
      expect(pin.smmcVersion, '2.5.0');
      expect(pin.engineSqliteVersion, '3.53.4');
      expect(
        pin.versionDescription,
        'SQLite3MultipleCiphers 2.5.0 built on SQLite 3.53.4',
      );
    });

    test('rejects a script without an amalgamation URL', () {
      expect(
        () => parseAmalgamationPin(
          'const x = 1;',
          vendoredDir: defaultVendoredDir,
        ),
        throwsA(isA<ToolException>()),
      );
    });

    test('rejects ambiguous URLs instead of guessing', () {
      const twoUrls = '''
const a =
    'https://github.com/utelle/SQLite3MultipleCiphers/releases/download/v2.5.0/sqlite3mc-2.5.0-sqlite-3.53.4-amalgamation.zip';
const b =
    'https://github.com/utelle/SQLite3MultipleCiphers/releases/download/v2.6.0/sqlite3mc-2.6.0-sqlite-3.53.4-amalgamation.zip';
''';
      expect(
        () => parseAmalgamationPin(twoUrls, vendoredDir: defaultVendoredDir),
        throwsA(isA<ToolException>()),
      );
    });

    test('tolerates an unparsable version for the content-only parts', () {
      final pin = parseAmalgamationPin(
        "const u = 'https://github.com/utelle/SQLite3MultipleCiphers/releases/download/v9.9.9/amalgamation.zip';",
        vendoredDir: defaultVendoredDir,
      );
      expect(pin.url.path, endsWith('amalgamation.zip'));
      expect(pin.smmcVersion, isNull);
      expect(pin.engineSqliteVersion, isNull);
      expect(pin.versionDescription, contains('not derivable'));
    });
  });

  group('vendored README provenance', () {
    test('records both hashes', () {
      final records = recordedHashes(
        readmeFixture,
        vendoredDir: defaultVendoredDir,
      );
      expect(records['sqlite3mc_amalgamation.c'], fill64('a'));
      expect(records['sqlite3mc_amalgamation.h'], fill64('b'));
    });

    test('rejects a README without the hash records', () {
      expect(
        () => recordedHashes(
          '# No records here',
          vendoredDir: defaultVendoredDir,
        ),
        throwsA(isA<ToolException>()),
      );
    });

    test('records the source URL', () {
      final url = recordedSourceUrl(readmeFixture);
      expect(url!.path, contains('SQLite3MultipleCiphers'));
    });

    test('a README without a URL record is not an error', () {
      expect(recordedSourceUrl('# hashes only\n'), isNull);
    });
  });

  group('provenance rewriting', () {
    test('round-trips to the identical block for unchanged facts', () {
      final rewritten = withRewrittenProvenance(
        readmeFixture,
        provenanceBlock(
          sourceUrl:
              'https://github.com/utelle/SQLite3MultipleCiphers/releases/download/v2.5.0/sqlite3mc-2.5.0-sqlite-3.53.4-amalgamation.zip',
          versionFacts: 'SQLite3MultipleCiphers 2.5.0 built on SQLite 3.53.4',
          pubVersion: '3.5.2',
          vendoredOn: '2026-09-22',
          hashes: {
            'sqlite3mc_amalgamation.c': fill64('a'),
            'sqlite3mc_amalgamation.h': fill64('b'),
          },
        ),
        vendoredDir: defaultVendoredDir,
      );
      expect(rewritten, readmeFixture);
    });

    test('replaces stale values in place, headings intact', () {
      final rewritten = withRewrittenProvenance(
        readmeFixture,
        provenanceBlock(
          sourceUrl: 'https://example.com/new_amalgamation.zip',
          versionFacts: 'SQLite3MultipleCiphers 2.6 built on SQLite 3.54',
          pubVersion: '4.0.0',
          vendoredOn: '2026-10-10',
          hashes: {
            'sqlite3mc_amalgamation.c': fill64('c'),
            'sqlite3mc_amalgamation.h': fill64('d'),
          },
        ),
        vendoredDir: defaultVendoredDir,
      );
      expect(
        rewritten.startsWith('# Vendored SQLite3MultipleCiphers'),
        isTrue,
        reason: 'everything before the block survives',
      );
      expect(
        rewritten,
        contains('## Licensing'),
        reason: 'everything after the block survives',
      );
      expect(rewritten, contains('new_amalgamation.zip'));
      expect(rewritten, contains('sqlite3-4.0.0'));
      expect(rewritten, contains('2026-10-10'));
      expect(rewritten, contains(fill64('c')));
      expect(rewritten, contains(fill64('d')));
      expect(rewritten, isNot(contains(fill64('a'))));
    });

    test('rejects a README without the heading structure', () {
      expect(
        () => withRewrittenProvenance(
          '# no headings',
          'x',
          vendoredDir: defaultVendoredDir,
        ),
        throwsA(isA<ToolException>()),
      );
    });
  });

  group('cache keys', () {
    test('are deterministic and URL-keyed', () {
      const url = 'https://example.com/sqlite3mc-amalgamation.zip';
      final path = cachePathFor(url, extension: '.zip');
      expect(
        path,
        cachePathFor(url, extension: '.zip'),
        reason: 'same URL, same cache slot',
      );
      expect(path, allOf(startsWith(cacheRootDir), endsWith('.zip')));
      expect(
        cachePathFor('$url ', extension: '.zip'),
        isNot(path),
        reason: 'a different URL must read a different slot',
      );
    });
  });
}

/// A 64-char filler string, standing in for a hex SHA-256 in the fixtures.
String fill64(String character) => character.padLeft(64, character);
