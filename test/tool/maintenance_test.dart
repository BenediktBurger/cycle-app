// Pure-logic tests for the maintenance tools
// (tool/fdroid_changelog_links.dart, tool/sqlite3mc.dart): fixture texts and
// temp-dir sandboxes only.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/fdroid_changelog_links.dart';
import '../../tool/sqlite3mc.dart';

/// The pubspec fixture: versionName 0.2.5, base versionCode 7 → per-ABI
/// changelog names 71/72/73 (the versionCode shape of
/// android/app/build.gradle.kts).
const fixedPubspec = 'name: cycle_app\nversion: 0.2.5+7\n';

/// The link names each locale's changelog dir must carry as generated
/// symlinks for a released 0.2.5+7: one per ABI versionCode.
const generatedNames = {'71.txt', '72.txt', '73.txt'};

/// The hand-maintained default fallback text present in every locale, kept
/// out of the script's generated name space.
const defaultFallbackName = 'default.txt';

const baseLocales = ['de-DE', 'en-US'];

/// Captures the script's print lines through a custom zone, so assertions
/// can check what a run reported without touching the runner's stdout.
List<String> capturePrint(void Function() body) {
  final lines = <String>[];
  runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => lines.add(line),
    ),
  );
  return lines;
}

/// The on-disk shape of [dir]: entry name → link target for symlinks, null
/// for every other entry type — enough to detect any wrong-type or
/// wrong-target drift between two runs.
Map<String, String?> shapeOf(Directory dir) => {
  for (final entity in dir.listSync())
    entity.path.split('/').last: FileSystemEntity.isLinkSync(entity.path)
        ? Link(entity.path).targetSync()
        : null,
};

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

/// A 64-char filler string, standing in for a hex SHA-256 in the fixtures.
String fill64(String character) => character.padLeft(64, character);

void main() {
  group('pubspec version parse', () {
    test('a `version: X.Y.Z+N` root line splits into versionName and the '
        'base versionCode where it sits', () {
      final version = parsePubspecVersion(
        'name: cycle_app\nversion: 0.2.5+7\nenvironment:\n  sdk: ^3.5.0\n',
      );
      expect(version.versionName, '0.2.5');
      expect(version.versionCode, 7);
    });

    test('an absent or non-`X.Y.Z+N` version line fails loudly', () {
      const badSources = [
        'name: cycle_app\n',
        'version: 0.2.5\n',
        'version: 0.2\n',
        'version: 0.2.5-rc1+7\n',
        'version: 0.2.5+7 extra\n',
        '  version: 0.2.5+7\n',
      ];
      for (final source in badSources) {
        expect(
          () => parsePubspecVersion(source),
          throwsA(
            isA<ChangelogLinksException>().having(
              (error) => error.message,
              'message',
              contains('version: X.Y.Z+N'),
            ),
          ),
          reason: 'pubspec source "$source" carries no usable version line',
        );
      }
    });
  });

  group('run over a temp repo root (fastlane tree sandbox)', () {
    const authoringName = '0.2.5.txt';

    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('fdroid_changelog_links');
    });

    tearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    Directory changelogs(String locale) =>
        Directory('${root.path}/$fdroidMetadataRoot/$locale/changelogs');

    /// Stages pubspec.yaml, the fastlane metadata tree for [baseLocales]
    /// (plus a non-directory root entry), and the hand-written authoring
    /// file in every locale of [withAuthoring].
    void stageTree({List<String> withAuthoring = baseLocales}) {
      File('${root.path}/pubspec.yaml')
        ..createSync()
        ..writeAsStringSync(fixedPubspec);
      Directory('${root.path}/$fdroidMetadataRoot').createSync(recursive: true);
      File(
        '${root.path}/$fdroidMetadataRoot/README.md',
      ).writeAsStringSync('# metadata\n');
      for (final locale in baseLocales) {
        final dir = changelogs(locale);
        dir.createSync(recursive: true);
        if (withAuthoring.contains(locale)) {
          File(
            '${dir.path}/$authoringName',
          ).writeAsStringSync('notes for $locale\n');
        }
        File(
          '${dir.path}/$defaultFallbackName',
        ).writeAsStringSync('default fallback text for $locale\n');
      }
    }

    /// Runs the script against the sandbox root, returning its printed
    /// lines.
    List<String> runLinks() => capturePrint(() => run([root.path]));

    test('a fresh tree gets the three per-ABI links as relative symlinks to '
        'the authoring file of each locale and leaves the default fallback '
        'text alone', () {
      stageTree();
      final lines = runLinks();

      final output = lines.join('\n');
      expect(
        output,
        contains('changelog links for versionName 0.2.5 (versionCode base 7)'),
        reason: 'the run opens with the version it is publishing links for',
      );
      for (final locale in baseLocales) {
        final dir = changelogs(locale);
        for (final name in generatedNames) {
          final linkPath = '${dir.path}/$name';
          expect(
            FileSystemEntity.typeSync(linkPath, followLinks: false),
            FileSystemEntityType.link,
            reason: '$locale/$name must exist as a symlink after the run',
          );
          expect(
            Link(linkPath).targetSync(),
            authoringName,
            reason:
                '$locale/$name must point at the authoring name only — the '
                'relative form the store resolves inside that locale',
          );
        }
        expect(
          FileSystemEntity.typeSync(
            '${dir.path}/$defaultFallbackName',
            followLinks: false,
          ),
          FileSystemEntityType.file,
          reason:
              '$locale/$defaultFallbackName is the hand-maintained fallback '
              'text, not a generated name — the run must not touch it',
        );
        expect(
          File('${dir.path}/$defaultFallbackName').readAsStringSync(),
          'default fallback text for $locale\n',
          reason: 'the staged default text must survive the run byte-identical',
        );
        expect(output, isNot(contains(defaultFallbackName)), reason: output);
        expect(
          File('${dir.path}/71.txt').readAsStringSync(),
          'notes for $locale\n',
          reason:
              'the link must resolve to its own locale\'s authoring '
              'file, not another locale\'s',
        );
        expect(
          output,
          contains('created: $fdroidMetadataRoot/$locale/changelogs/71.txt'),
          reason: output,
        );
      }
    });

    test('a second run over the finished tree is a silent no-op: the tree '
        'shape is unchanged and every link passes as ok', () {
      stageTree();
      runLinks();
      final afterFirstRun = {
        for (final locale in baseLocales) locale: shapeOf(changelogs(locale)),
      };

      final secondRun = runLinks();

      for (final locale in baseLocales) {
        expect(
          shapeOf(changelogs(locale)),
          afterFirstRun[locale],
          reason:
              'the rerun must leave $locale exactly as the first run '
              'shaped it',
        );
      }
      final output = secondRun.join('\n');
      expect(
        output,
        isNot(contains('created:')),
        reason: 'nothing may be (re)created on an idempotent rerun',
      );
      expect(
        output,
        contains(
          'ok: $fdroidMetadataRoot/de-DE/changelogs/71.txt -> $authoringName',
        ),
      );
    });

    test('an authoring file present in only one locale fails loudly naming '
        'the locale it is missing from', () {
      stageTree(withAuthoring: const ['de-DE']);

      expect(
        () => runLinks(),
        throwsA(
          isA<ChangelogLinksException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('$fdroidMetadataRoot/en-US/changelogs/$authoringName'),
              contains('is missing'),
            ),
          ),
        ),
      );
    });

    test('an authoring file that is a symlink (e.g. mistakenly pointed at '
        'another locale) fails loudly naming the path', () {
      stageTree();
      final dir = changelogs('de-DE');
      File('${dir.path}/$authoringName').deleteSync();
      Link(
        '${dir.path}/$authoringName',
      ).createSync('../../en-US/changelogs/$authoringName');

      expect(
        () => runLinks(),
        throwsA(
          isA<ChangelogLinksException>().having(
            (error) => error.message,
            'message',
            contains('$fdroidMetadataRoot/de-DE/changelogs/$authoringName'),
          ),
        ),
      );
      expect(
        Link('${dir.path}/$authoringName').targetSync(),
        '../../en-US/changelogs/$authoringName',
        reason:
            'the mistaken link must survive the failed run — resolving it '
            'is the operator\'s call, never the script\'s',
      );
    });

    test('an existing symlink with a wrong target fails loudly by name and '
        'survives the failed run unrepaired', () {
      stageTree();
      final dir = changelogs('de-DE');
      File('${dir.path}/0.2.4.txt').writeAsStringSync('old notes\n');
      Link('${dir.path}/72.txt').createSync('0.2.4.txt');

      expect(
        () => runLinks(),
        throwsA(
          isA<ChangelogLinksException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('$fdroidMetadataRoot/de-DE/changelogs/72.txt'),
              contains('is a symlink to "0.2.4.txt"'),
            ),
          ),
        ),
      );
      expect(
        Link('${dir.path}/72.txt').targetSync(),
        '0.2.4.txt',
        reason:
            'the wrong-target link must still hold its original target '
            '— repairing it is a human decision, not the script\'s',
      );
    });

    test('a regular file on an expected per-ABI name fails loudly and its '
        'bytes survive untouched', () {
      stageTree();
      final dir = changelogs('en-US');
      File('${dir.path}/72.txt').writeAsStringSync('hand-staged bytes\n');

      expect(
        () => runLinks(),
        throwsA(
          isA<ChangelogLinksException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('$fdroidMetadataRoot/en-US/changelogs/72.txt'),
              contains('is not a symlink'),
            ),
          ),
        ),
      );
      expect(
        FileSystemEntity.typeSync('${dir.path}/72.txt', followLinks: false),
        FileSystemEntityType.file,
        reason:
            'the regular file must stay a regular file — the script '
            'never deletes or overwrites data',
      );
      expect(
        File('${dir.path}/72.txt').readAsStringSync(),
        'hand-staged bytes\n',
        reason: 'the staged bytes must survive the failed run byte for byte',
      );
    });

    test('a regular file on an unowned numeric name (no pending versionCode '
        'claims it) fails loudly naming the file', () {
      stageTree();
      final stale = File('${changelogs('de-DE').path}/55.txt')
        ..writeAsStringSync('stale leftover\n');

      expect(
        () => runLinks(),
        throwsA(
          isA<ChangelogLinksException>().having(
            (error) => error.message,
            'message',
            allOf(contains('unowned'), contains('55.txt')),
          ),
        ),
      );
      expect(
        stale.readAsStringSync(),
        'stale leftover\n',
        reason:
            'the stale file must survive the failed run for a hand '
            'resolution',
      );
    });

    test('a symlink on a non-generated numeric name (999.txt) is tolerated '
        'and left untouched — only regular files must vacate the foreign '
        'numeric names', () {
      stageTree();
      final dir = changelogs('en-US');
      Link('${dir.path}/999.txt').createSync(authoringName);

      final lines = runLinks();

      expect(
        Link('${dir.path}/999.txt').targetSync(),
        authoringName,
        reason: 'the foreign-name symlink must survive the run untouched',
      );
      final output = lines.join('\n');
      expect(output, isNot(contains('999.txt')));
      expect(
        output,
        contains(
          'created: $fdroidMetadataRoot/en-US/changelogs/71.txt '
          '-> $authoringName',
        ),
        reason:
            'the expected links are still made and verified alongside '
            'the tolerated stray',
      );
    });

    test('a repo root without pubspec.yaml fails loudly with the root it '
        'looked under', () {
      expect(
        () => runLinks(),
        throwsA(
          isA<ChangelogLinksException>().having(
            (error) => error.message,
            'message',
            allOf(contains('no pubspec.yaml'), contains(root.path)),
          ),
        ),
      );
    });

    test('pubspec present but the fastlane metadata tree gone fails loudly '
        'with the tree path', () {
      File('${root.path}/pubspec.yaml').writeAsStringSync(fixedPubspec);

      expect(
        () => runLinks(),
        throwsA(
          isA<ChangelogLinksException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('$fdroidMetadataRoot under'),
              contains('fastlane tree is missing'),
            ),
          ),
        ),
      );
    });

    test('a metadata tree without any locale directory fails loudly (the '
        'script refuses to run against nothing)', () {
      File('${root.path}/pubspec.yaml').writeAsStringSync(fixedPubspec);
      Directory('${root.path}/$fdroidMetadataRoot').createSync(recursive: true);

      expect(
        () => runLinks(),
        throwsA(
          isA<ChangelogLinksException>().having(
            (error) => error.message,
            'message',
            contains('no locale directory'),
          ),
        ),
      );
    });
  });

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
      expect(options.vendoredDir, 'native/sqlite3mc');
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
