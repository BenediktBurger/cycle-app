// Tests for
// tool/fdroid_changelog_links.dart — the F-Droid fastlane changelog-link
// generator (`dart run tool/fdroid_changelog_links.dart [<repo-root>]`).
//
// Pure seam as everywhere in test/tool/: a temp-dir sandbox stands in for
// the repository root (pubspec.yaml + fastlane/metadata/android/<locale>/
// changelogs/), and failures surface through the script's own loud-failure
// contract — ChangelogLinksException — instead of a real process exit.
// Relative import on purpose: tool/ scripts live outside lib/ and are not
// addressable through `package:cycle_app/`.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/fdroid_changelog_links.dart';

/// The pubspec fixture: versionName 0.2.5, base versionCode 7 → per-ABI
/// changelog names 71/72/73 (the versionCode shape of
/// android/app/build.gradle.kts).
const fixedPubspec = 'name: cycle_app\nversion: 0.2.5+7\n';

/// The link names each locale's changelog dir must carry for a released
/// 0.2.5+7: one per ABI versionCode plus the unlisted-build fallback.
const generatedNames = {'71.txt', '72.txt', '73.txt', 'default.txt'};

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
      }
    }

    /// Runs the script against the sandbox root, returning its printed
    /// lines.
    List<String> runLinks() => capturePrint(() => run([root.path]));

    test('a fresh tree gets the three per-ABI links plus default.txt as '
        'relative symlinks to the authoring file of each locale', () {
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
      expect(
        output,
        contains(
          'ok: $fdroidMetadataRoot/en-US/changelogs/default.txt -> '
          '$authoringName',
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
}
