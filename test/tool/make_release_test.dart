// Pure-logic tests for tool/make_release.dart — the release-publishing script
// behind per-release checklist step 7 of docs/release.md (the script's header
// comment carries the full context).
//
// These tests deliberately stay on the pure seam: they exercise argument
// parsing/validation, tag-vs-version matching, apksigner/aapt output parsing,
// pin-file read/write normalization, release-notes assembly, and the pure
// dry-run/first-run gating decisions (pin staging, upgrade-test prompt)
// directly. Nothing here shells out to real git/gh/apksigner/aapt, and
// nothing touches the repository state (no tags are created,
// tool/release_fingerprint.txt is never written) — the process layer of the
// script stays outside this suite by design.
// Two documented exceptions spin up a Directory.systemTemp sandbox to
// exercise file writes without touching the repository itself: the "flutter
// pin staging + workflow sync orchestration" group (pin + workflow files)
// and the "publish-copy staging" group (the byte-identical publish copies
// the real run stages into the gitignored build/gh-release/ directory).
// Relative import on purpose: tool/ scripts live outside lib/ and are not
// addressable through `package:cycle_app/`.
import 'dart:io';

import '../../tool/make_release.dart';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('argument parsing', () {
    test('accepts a well-formed tag plus flags', () {
      final options = parseArguments(['v1.2.3', '--dry-run']);
      expect(options.tag, 'v1.2.3');
      expect(options.dryRun, isTrue);
      expect(options.acceptFingerprint, isFalse);
      expect(options.acceptFlutterVersion, isFalse);
      expect(options.tested, isFalse);
    });

    test('parses every flag independently', () {
      final options = parseArguments([
        '--tested',
        'v0.1.0',
        '--accept-fingerprint',
        '--accept-flutter-version',
        '--dry-run',
      ]);
      expect(options.tag, 'v0.1.0');
      expect(options.acceptFingerprint, isTrue);
      expect(options.acceptFlutterVersion, isTrue);
      expect(options.dryRun, isTrue);
      expect(options.tested, isTrue);
    });

    test('rejects malformed tags', () {
      const badTags = [
        'v1.2',
        '1.2.3',
        'v1.2.3.4',
        '',
        'vx.y.z',
        'v1.2.3-rc1',
        'V1.2.3',
        'v1.2.3+4',
      ];
      for (final tag in badTags) {
        expect(
          () => parseArguments([tag]),
          throwsA(isA<UsageException>()),
          reason: 'tag "$tag" must be rejected',
        );
      }
    });

    test('rejects unknown flags', () {
      expect(
        () => parseArguments(['--unknown', 'v1.2.3']),
        throwsA(isA<UsageException>()),
      );
      expect(
        () => parseArguments(['-f', 'v1.2.3']),
        throwsA(isA<UsageException>()),
      );
    });

    test('rejects missing and extra positional arguments', () {
      expect(() => parseArguments(const []), throwsA(isA<UsageException>()));
      expect(
        () => parseArguments(['v1.2.3', 'v2.0.0']),
        throwsA(isA<UsageException>()),
      );
    });
  });

  group('first-run pin staging (write pin, stop, rerun)', () {
    const accept = Options(
      tag: 'v0.1.0',
      acceptFingerprint: true,
      acceptFlutterVersion: false,
      dryRun: false,
      tested: false,
    );

    test(
      'a real run with --accept-fingerprint stops after writing the pin',
      () {
        expect(
          accept.stopsAfterWritingPin,
          isTrue,
          reason:
              'the fresh pin leaves the tree dirty — tag/push must not '
              'run with an uncommitted pin file',
        );
      },
    );

    test('a dry run only prints the pin and continues', () {
      const dryAccept = Options(
        tag: 'v0.1.0',
        acceptFingerprint: true,
        acceptFlutterVersion: false,
        dryRun: true,
        tested: false,
      );
      expect(dryAccept.stopsAfterWritingPin, isFalse);
    });

    test('runs without --accept-fingerprint never take the write-pin path', () {
      const plain = Options(
        tag: 'v0.1.0',
        acceptFingerprint: false,
        acceptFlutterVersion: false,
        dryRun: false,
        tested: false,
      );
      expect(
        plain.stopsAfterWritingPin,
        isFalse,
        reason:
            'missing pin without --accept-fingerprint aborts without '
            'writing anything',
      );
    });
  });

  group('flutter-pin first-run staging (write pin, stop, rerun)', () {
    const accept = Options(
      tag: 'v0.1.0',
      acceptFingerprint: false,
      acceptFlutterVersion: true,
      dryRun: false,
      tested: false,
    );

    test(
      'a real run with --accept-flutter-version stops after writing the pin',
      () {
        expect(
          accept.stopsAfterWritingFlutterPin,
          isTrue,
          reason:
              'the fresh pin leaves the tree dirty — tag/push must not '
              'run with an uncommitted pin file',
        );
      },
    );

    test('a dry run only prints the pin and continues', () {
      const dryAccept = Options(
        tag: 'v0.1.0',
        acceptFingerprint: false,
        acceptFlutterVersion: true,
        dryRun: true,
        tested: false,
      );
      expect(dryAccept.stopsAfterWritingFlutterPin, isFalse);
    });

    test(
      'runs without --accept-flutter-version never take the write-pin path',
      () {
        const plain = Options(
          tag: 'v0.1.0',
          acceptFingerprint: false,
          acceptFlutterVersion: false,
          dryRun: false,
          tested: false,
        );
        const dryOnly = Options(
          tag: 'v0.1.0',
          acceptFingerprint: false,
          acceptFlutterVersion: false,
          dryRun: true,
          tested: false,
        );
        expect(
          plain.stopsAfterWritingFlutterPin,
          isFalse,
          reason:
              'without the flag the run always fails loudly instead '
              'of staging a pin — the match check is never bypassable',
        );
        expect(dryOnly.stopsAfterWritingFlutterPin, isFalse);
      },
    );
  });

  group('flutter pin mismatch remediation messages', () {
    test('the no-flag mismatch failure lists every remediation element', () {
      final message = flutterPinMismatchMessage(
        installed: '3.48.1',
        pinned: '3.47.4',
      );
      expect(message, contains('FLUTTER VERSION MISMATCH'));
      expect(message, contains('3.48.1'));
      expect(message, contains('3.47.4'));
      expect(message, contains('tool/flutter-version'));
      expect(message, contains('--accept-flutter-version'));
      expect(message, contains('.github/workflows/ci.yml'));
      expect(message, contains('flutter-version:'));
      expect(message, contains('commit'));
      expect(message, contains('flutter build apk --release'));
      expect(message, contains('rerun'));
    });

    test('the no-flag mismatch failure offers both remediation directions', () {
      final message = flutterPinMismatchMessage(
        installed: '3.48.1',
        pinned: '3.47.4',
      );
      expect(message, contains('rewrites $flutterPinFilePath'));
    });

    test('the stop-after-rewrite message lists every follow-up step', () {
      final message = flutterPinWriteStopMessage('3.48.1');
      expect(message, contains('3.48.1'));
      expect(message, contains('tool/flutter-version'));
      expect(message, contains('git add'));
      expect(message, contains('commit'));
      expect(message, contains('.github/workflows/ci.yml'));
      expect(message, contains('flutter-version:'));
      expect(message, contains('flutter build apk --release'));
      expect(message, contains('rerun'));
    });

    test('both messages state that the script syncs the workflow inputs', () {
      final mismatch = flutterPinMismatchMessage(
        installed: '3.48.1',
        pinned: '3.47.4',
      );
      expect(
        mismatch,
        contains('updates the flutter-version: input'),
        reason: 'the re-pin run updates the workflow inputs itself',
      );
      final stop = flutterPinWriteStopMessage('3.48.1');
      expect(
        stop,
        contains('updated the flutter-version: input'),
        reason: 'the staging run updates the workflow inputs itself',
      );
      expect(
        stop,
        contains('git add $flutterPinFilePath .github/workflows/*'),
        reason: 'one commit collects the pin and the workflow files',
      );
      expect(
        mismatch,
        contains('commit all changed files'),
        reason: 'one commit collects the pin and the workflow files',
      );
    });

    test('neither message instructs a hand edit of the workflow input', () {
      final mismatch = flutterPinMismatchMessage(
        installed: '3.48.1',
        pinned: '3.47.4',
      );
      final stop = flutterPinWriteStopMessage('3.48.1');
      for (final message in [mismatch, stop]) {
        expect(message, isNot(contains('update the flutter-version')));
        expect(message, isNot(contains('Update the flutter-version')));
        expect(message, isNot(contains('and commit that too')));
        expect(message, isNot(contains('by hand')));
      }
    });
  });

  group('updateWorkflowFlutterVersion (workflow input sync transform)', () {
    // Minimal ci.yml-style fixture: a `uses:` block with an indented
    // flutter-version input, matching .github/workflows/ci.yml's shape.
    const original = '''
jobs:
  gate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version: 3.47.4
''';
    const updatedFor3481 = '''
jobs:
  gate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version: 3.48.1
''';

    test('rewrites the flutter-version: input and changes nothing else', () {
      expect(updateWorkflowFlutterVersion(original, '3.48.1'), updatedFor3481);
    });

    test('preserves the leading whitespace of the replaced line', () {
      expect(
        updateWorkflowFlutterVersion('  flutter-version: 3.47.4\n', '3.48.1'),
        '  flutter-version: 3.48.1\n',
      );
      expect(
        updateWorkflowFlutterVersion('\tflutter-version: 3.47.4\n', '3.48.1'),
        '\tflutter-version: 3.48.1\n',
      );
    });

    test('leaves commented flutter-version lines untouched', () {
      const commented =
          '  # flutter-version: 3.47.4\nflutter-version: 3.47.4\n';
      expect(
        updateWorkflowFlutterVersion(commented, '3.48.1'),
        '  # flutter-version: 3.47.4\nflutter-version: 3.48.1\n',
      );
    });

    test('replaces every matchable line at once', () {
      const doubled =
          'flutter-version: 3.47.4\nother: value\n  flutter-version: 3.47.4\n';
      expect(
        updateWorkflowFlutterVersion(doubled, '3.48.1'),
        'flutter-version: 3.48.1\nother: value\n  flutter-version: 3.48.1\n',
      );
    });

    test('returns null when no matchable line exists', () {
      expect(
        updateWorkflowFlutterVersion('channel: stable\n', '3.48.1'),
        isNull,
      );
      expect(
        updateWorkflowFlutterVersion('# flutter-version: 3.47.4\n', '3.48.1'),
        isNull,
        reason: 'a commented line must not count as a matchable input',
      );
    });

    test(
      'a value-less flutter-version: line is not rewritten across lines',
      () {
        // A multi-line match (via \s* after the colon) would swallow the
        // indented next line and the channel input with it.
        const valueless =
            '  with:\n    flutter-version:\n    channel: stable\n';
        expect(
          updateWorkflowFlutterVersion(valueless, '3.48.1'),
          anyOf(isNull, contains('channel: stable')),
          reason:
              'the rewrite must never span from the flutter-version: line '
              'into the following line',
        );
      },
    );

    test('is idempotent: re-applying the current version is a no-op', () {
      final once = updateWorkflowFlutterVersion(original, '3.48.1')!;
      expect(updateWorkflowFlutterVersion(once, '3.48.1'), once);
    });
  });

  group('flutter pin staging + workflow sync orchestration (temp-dir '
      'exception)', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('make_release_sync_test');
    });

    tearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    const workflowPinned = '''
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version: 3.47.4
''';
    const workflowSynced = '''
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version: 3.48.1
''';
    const malformedWorkflow = 'steps:\n  - run: make\n';

    File fileUnderRoot(String relativePath) =>
        File('${root.path}/$relativePath');
    File pinFile() => fileUnderRoot(flutterPinFilePath);

    Future<void> writeFile(String relativePath, String content) async {
      final file = File('${root.path}/$relativePath');
      await file.parent.create(recursive: true);
      await file.writeAsString(content);
    }

    test('flag + real run: pin file and both workflow files are updated, '
        'then the run stops', () async {
      await writeFile(ciWorkflowPath, workflowPinned);
      await writeFile(releaseWorkflowPath, workflowPinned);
      await expectLater(
        writeFlutterPinAndStop(root: root, version: '3.48.1'),
        throwsA(isA<ReleaseException>()),
      );
      expect(await pinFile().readAsString(), formatFlutterPinFile('3.48.1'));
      expect(
        await fileUnderRoot(ciWorkflowPath).readAsString(),
        workflowSynced,
      );
      expect(
        await fileUnderRoot(releaseWorkflowPath).readAsString(),
        workflowSynced,
      );
    });

    test('dry run: reports the would-be changes and writes nothing', () async {
      await writeFile(flutterPinFilePath, '# pin\n3.47.4\n');
      await writeFile(ciWorkflowPath, workflowPinned);
      await writeFile(releaseWorkflowPath, workflowPinned);
      await printFlutterPinSyncDryRunNote(root: root, version: '3.48.1');
      expect(
        await pinFile().readAsString(),
        '# pin\n3.47.4\n',
        reason: 'a dry run never stages the pin',
      );
      expect(
        await fileUnderRoot(ciWorkflowPath).readAsString(),
        workflowPinned,
      );
      expect(
        await fileUnderRoot(releaseWorkflowPath).readAsString(),
        workflowPinned,
      );
    });

    test(
      'missing release.yml: skipped, ci.yml still updated, run stops',
      () async {
        await writeFile(ciWorkflowPath, workflowPinned);
        await expectLater(
          writeFlutterPinAndStop(root: root, version: '3.48.1'),
          throwsA(isA<ReleaseException>()),
        );
        expect(await pinFile().readAsString(), formatFlutterPinFile('3.48.1'));
        expect(
          await fileUnderRoot(ciWorkflowPath).readAsString(),
          workflowSynced,
        );
        expect(fileUnderRoot(releaseWorkflowPath).existsSync(), isFalse);
      },
    );

    test('missing ci.yml: run aborts before anything is written', () async {
      await writeFile(releaseWorkflowPath, workflowPinned);
      await expectLater(
        writeFlutterPinAndStop(root: root, version: '3.48.1'),
        throwsA(isA<ReleaseException>()),
      );
      expect(
        pinFile().existsSync(),
        isFalse,
        reason:
            'ci.yml is the pin-cross-checking gate — its absence must '
            'hard-fail before any write',
      );
      expect(
        await fileUnderRoot(releaseWorkflowPath).readAsString(),
        workflowPinned,
      );
    });

    test('workflow without a matchable flutter-version line: run aborts '
        'naming the file, pin NOT written (validate before write)', () async {
      await writeFile(ciWorkflowPath, malformedWorkflow);
      await writeFile(releaseWorkflowPath, workflowPinned);
      await expectLater(
        writeFlutterPinAndStop(root: root, version: '3.48.1'),
        throwsA(
          isA<ReleaseException>().having(
            (error) => error.message,
            'message',
            allOf(contains(ciWorkflowPath), contains('flutter-version: X.Y.Z')),
          ),
        ),
      );
      expect(
        pinFile().existsSync(),
        isFalse,
        reason:
            'validation must happen before any write — no half-updated '
            'pin + workflow combination',
      );
      expect(
        await fileUnderRoot(ciWorkflowPath).readAsString(),
        malformedWorkflow,
      );
      expect(
        await fileUnderRoot(releaseWorkflowPath).readAsString(),
        workflowPinned,
      );
    });

    test('a second stop run rewrites nothing (only content changes are '
        'written)', () async {
      await writeFile(ciWorkflowPath, workflowPinned);
      await writeFile(releaseWorkflowPath, workflowPinned);
      await expectLater(
        writeFlutterPinAndStop(root: root, version: '3.48.1'),
        throwsA(isA<ReleaseException>()),
      );
      final ciAfterFirst = await fileUnderRoot(ciWorkflowPath).readAsString();
      final releaseAfterFirst = await fileUnderRoot(
        releaseWorkflowPath,
      ).readAsString();
      await expectLater(
        writeFlutterPinAndStop(root: root, version: '3.48.1'),
        throwsA(isA<ReleaseException>()),
      );
      expect(await fileUnderRoot(ciWorkflowPath).readAsString(), ciAfterFirst);
      expect(
        await fileUnderRoot(releaseWorkflowPath).readAsString(),
        releaseAfterFirst,
      );
    });
  });

  group('publish-copy staging (temp-dir exception)', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('make_release_staging_test');
    });

    tearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    Future<void> writeSource(String relativePath, List<int> bytes) async {
      final file = File('${root.path}/$relativePath');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
    }

    test('copies the build APKs under publish names into build/gh-release, '
        'byte-identical, originals intact', () async {
      final contents = [
        [1, 2, 3],
        [4, 5],
        [6],
      ];
      for (var i = 0; i < releaseApkPaths.length; i++) {
        await writeSource(releaseApkPaths[i], contents[i]);
      }
      final staged = await stagePublishCopies(root: root, versionName: '0.2.0');
      expect(staged, stagedPublishApkPaths('0.2.0'));
      for (var i = 0; i < releaseApkPaths.length; i++) {
        final copy = File('${root.path}/${staged[i]}');
        expect(copy.existsSync(), isTrue, reason: '${staged[i]} must exist');
        expect(
          copy.readAsBytesSync(),
          contents[i],
          reason:
              '${staged[i]} must be a byte-identical copy of '
              '${releaseApkPaths[i]}',
        );
        expect(
          File('${root.path}/${releaseApkPaths[i]}').existsSync(),
          isTrue,
          reason: 'staging must not remove the original build artifact',
        );
      }
      expect(
        Directory(
            '${root.path}/build/gh-release',
          ).listSync().map((entry) => entry.path.split('/').last).toList()
          ..sort(),
        [
          'cycle-app-0.2.0-arm64-v8a.apk',
          'cycle-app-0.2.0-armeabi-v7a.apk',
          'cycle-app-0.2.0-x86_64.apk',
        ],
        reason: 'only the publish names land in the staging directory',
      );
    });

    test(
      'overwrites leftovers from a previous run (name includes version)',
      () async {
        final contents = [
          [1, 2, 3],
          [4, 5],
          [6],
        ];
        for (var i = 0; i < releaseApkPaths.length; i++) {
          await writeSource(releaseApkPaths[i], contents[i]);
        }
        await writeSource('build/gh-release/cycle-app-0.2.0-armeabi-v7a.apk', [
          9,
          9,
          9,
          9,
        ]);
        final staged = await stagePublishCopies(
          root: root,
          versionName: '0.2.0',
        );
        expect(File('${root.path}/${staged.first}').readAsBytesSync(), [
          1,
          2,
          3,
        ], reason: 'a stale leftover copy must be replaced, not kept');
        for (var i = 0; i < releaseApkPaths.length; i++) {
          expect(
            File('${root.path}/${staged[i]}').readAsBytesSync(),
            contents[i],
            reason: '${staged[i]} must hold the fresh copy',
          );
        }
      },
    );
  });

  group('upgrade-test confirmation gating', () {
    test('a real run prompts unless --tested is given', () {
      const realRun = Options(
        tag: 'v0.1.0',
        acceptFingerprint: false,
        acceptFlutterVersion: false,
        dryRun: false,
        tested: false,
      );
      expect(realRun.promptsForUpgradeTest, isTrue);
      const scripted = Options(
        tag: 'v0.1.0',
        acceptFingerprint: false,
        acceptFlutterVersion: false,
        dryRun: false,
        tested: true,
      );
      expect(scripted.promptsForUpgradeTest, isFalse);
    });

    test('a dry run never prompts (checks only, nothing to gate)', () {
      const dry = Options(
        tag: 'v0.1.0',
        acceptFingerprint: true,
        acceptFlutterVersion: false,
        dryRun: true,
        tested: false,
      );
      expect(dry.promptsForUpgradeTest, isFalse);
      const dryTested = Options(
        tag: 'v0.1.0',
        acceptFingerprint: false,
        acceptFlutterVersion: false,
        dryRun: true,
        tested: true,
      );
      expect(dryTested.promptsForUpgradeTest, isFalse);
    });
  });

  group('flutter version pin helpers (tool/flutter-version)', () {
    const installedOutput = '''
Flutter 3.47.4 • channel stable • https://github.com/flutter/flutter.git
Framework • revision 9584c6713b (vor 11 Tagen) • 2026-09-10 15:25:10 -0700
Engine • hash 0e228ec8c8d2abc9fcf1d053e8a40665bb859ec7 (revision 06a2e2a110)
Tools • Dart 3.13.3 • DevTools 2.60.0
''';

    test('version validation is strict X.Y.Z', () {
      expect(isValidFlutterVersion('3.47.4'), isTrue);
      expect(isValidFlutterVersion('10.0.0'), isTrue);
      expect(isValidFlutterVersion('3.47'), isFalse);
      expect(isValidFlutterVersion('v3.47.4'), isFalse);
      expect(isValidFlutterVersion('3.47.4+1'), isFalse);
      expect(isValidFlutterVersion(''), isFalse);
      expect(isValidFlutterVersion('3.47.4 '), isFalse);
    });

    test('extracts the version from `flutter --version` output', () {
      expect(parseInstalledFlutterVersion(installedOutput), '3.47.4');
    });

    test('returns null for output without a version line', () {
      expect(parseInstalledFlutterVersion(''), isNull);
      expect(parseInstalledFlutterVersion('Tools • Dart 3.13.3\n'), isNull);
      expect(
        parseInstalledFlutterVersion(
          'Flutter not.a.version • channel stable\n',
        ),
        isNull,
      );
    });

    test(
      'round-trips a formatted pin file (header comment + version line)',
      () {
        final text = formatFlutterPinFile('3.47.4');
        expect(parseFlutterPinFile(text), '3.47.4');
      },
    );

    test('pin parser takes the last non-comment line (CI grep semantics)', () {
      expect(parseFlutterPinFile('# old note\n3.46.0\n3.47.4\n'), '3.47.4');
      // The CI check greps non-comment lines and takes the tail: a comment
      // appended after the value line does not hide the value.
      expect(
        parseFlutterPinFile('# pinned below\n3.47.4\n# lifted comment\n'),
        '3.47.4',
      );
      expect(parseFlutterPinFile('3.46.0\n3.47.4'), '3.47.4');
    });

    test('pin parser rejects comment-only, empty, and malformed files', () {
      expect(parseFlutterPinFile('# only a comment\n'), isNull);
      expect(parseFlutterPinFile(''), isNull);
      expect(parseFlutterPinFile('3.47\n'), isNull);
      expect(parseFlutterPinFile('v3.47.4\n'), isNull);
      expect(parseFlutterPinFile('not-a-version\n'), isNull);
    });

    test('pin parser tolerates whitespace padding', () {
      expect(parseFlutterPinFile('  3.47.4  \n'), '3.47.4');
    });
  });

  group('pubspec version line', () {
    const pubspecSource = '''
name: cycle_app
description: >-
  Example description spanning lines.
publish_to: none
version: 0.1.0+7

environment:
  sdk: ">=3.5.0 <4.0.0"
''';

    test('parses versionName and build number from the version line', () {
      final version = parsePubspecVersion(pubspecSource);
      expect(version, isNotNull);
      expect(version!.name, '0.1.0');
      expect(version.build, 7);
    });

    test('returns null when no version line is present', () {
      expect(parsePubspecVersion('name: cycle_app\ndependencies:\n'), isNull);
    });

    test('returns null for a version line without a build number', () {
      expect(parsePubspecVersion('version: 0.1.0\n'), isNull);
    });

    test('tag/version match and mismatch', () {
      expect(tagMatchesVersion('v0.1.0', '0.1.0'), isTrue);
      expect(tagMatchesVersion('v0.1.1', '0.1.0'), isFalse);
      expect(tagMatchesVersion('v1.0.0', '0.1.0'), isFalse);
    });
  });

  group('apksigner --print-certs parsing', () {
    // Real output shape of `apksigner verify --print-certs` (one signer).
    const output = '''
Signer #1 certificate DN: CN=Cycle App Release, O=Benedikt Burger, C=DE
Signer #1 certificate SHA-256 digest: 6a1f2c4d5e6f708192a3b4c5d6e7f8091a2b3c4d5e6f708192a3b4c5d6e7f809
Signer #1 certificate SHA-1 digest: 6a1f2c4d5e6f708192a3b4c5d6e7f8091a2b3c4d
Signer #1 certificate MD5 digest: 6a1f2c4d5e6f708192a3b4c5d6e7f809
Signer #1 certificate: [Retrieved from store as "PKCS7"]
''';

    test('extracts the SHA-256 digest (not SHA-1/MD5), normalized', () {
      expect(
        parseCertificateFingerprint(output),
        '6a1f2c4d5e6f708192a3b4c5d6e7f8091a2b3c4d5e6f708192a3b4c5d6e7f809',
      );
    });

    test('tolerates colon-separated uppercase digest bytes', () {
      const colonOutput =
          'Signer #1 certificate SHA-256 digest: '
          '6A:1F:2C:4D:5E:6F:70:81:92:A3:B4:C5:D6:E7:F8:09:'
          '1A:2B:3C:4D:5E:6F:70:81:92:A3:B4:C5:D6:E7:F8:09';
      expect(
        parseCertificateFingerprint(colonOutput),
        '6a1f2c4d5e6f708192a3b4c5d6e7f8091a2b3c4d5e6f708192a3b4c5d6e7f809',
      );
    });

    test('returns null when no SHA-256 digest line exists', () {
      expect(
        parseCertificateFingerprint(
          'Signer #1 certificate SHA-1 digest: deadbeef\n',
        ),
        isNull,
      );
      expect(parseCertificateFingerprint(''), isNull);
    });
  });

  group('aapt dump badging parsing', () {
    const badgingOutput = '''
package: name='io.github.benediktburger.cycleapp' versionCode='3' versionName='0.1.0' platformBuildVersionName='14'
sdkVersion:'21'
targetSdkVersion:'34'
uses-permission: name='android.permission.POST_NOTIFICATIONS'
application-label:'Cycle App'
application: label='Cycle App' icon='res/mipmap/ic_launcher.png'
launchable-activity: name='io.github.benediktburger.cycleapp.MainActivity'  label='Cycle App'
''';

    test('extracts versionName and versionCode', () {
      final info = parseAaptBadging(badgingOutput);
      expect(info, isNotNull);
      expect(info!.versionName, '0.1.0');
      expect(info.versionCode, 3);
    });

    test('returns null when the package line is missing', () {
      expect(parseAaptBadging("sdkVersion:'21'\n"), isNull);
    });
  });

  group('pin file read/write + normalization', () {
    const fingerprint =
        '6a1f2c4d5e6f708192a3b4c5d6e7f8091a2b3c4d5e6f708192a3b4c5d6e7f809';

    test('parses a formatted pin file (header comment + fingerprint)', () {
      final text = formatPinFile(fingerprint);
      expect(parsePinFile(text), fingerprint);
    });

    test('normalizes colons, case, and stray whitespace', () {
      // The pin file layout is "comment header + bare hex fingerprint"
      // (formatPinFile), but the reader tolerates a hand-edited variant:
      // colon-separated, uppercase, padded with whitespace.
      final colonized =
          '6A:1F:2C:4D:5E:6F:70:81:92:A3:B4:C5:D6:E7:F8:09:'
          '1A:2B:3C:4D:5E:6F:70:81:92:A3:B4:C5:D6:E7:F8:09\n';
      expect(parsePinFile(colonized), fingerprint);
      expect(parsePinFile('  ${fingerprint.toUpperCase()}  \n'), fingerprint);
    });

    test('ignores comment-only files and garbage lines', () {
      expect(parsePinFile('# only a comment\n'), isNull);
      expect(parsePinFile('# comment\nnot-a-fingerprint\n'), isNull);
      expect(parsePinFile(''), isNull);
    });

    test('fingerprint comparison is case/colon insensitive', () {
      expect(fingerprintsMatch('6A:1F:AA:BB', '6a1faabb'), isTrue);
      expect(fingerprintsMatch(fingerprint, fingerprint.toUpperCase()), isTrue);
      expect(
        fingerprintsMatch(fingerprint, 'ff${fingerprint.substring(2)}'),
        isFalse,
      );
    });
  });

  group('newest build-tools resolution (sort -V equivalent)', () {
    test('picks the numerically highest version directory', () {
      expect(
        newestBuildToolsDirectory(const ['33.0.2', '34.0.0', '35.0.1']),
        '35.0.1',
      );
      expect(newestBuildToolsDirectory(const ['9.0.0', '10.0.0']), '10.0.0');
      expect(newestBuildToolsDirectory(const ['35.0.1', '34.0.0']), '35.0.1');
    });

    test('ignores non-version entries and handles empty input', () {
      expect(
        newestBuildToolsDirectory(const ['source.properties', '34.0.0']),
        '34.0.0',
      );
      expect(newestBuildToolsDirectory(const []), isNull);
      expect(newestBuildToolsDirectory(const ['not-a-version']), isNull);
    });
  });

  group('split-APK artifact set and version-code scheme', () {
    test('the published set is exactly the three per-ABI split APKs', () {
      expect(releaseApkPaths, [
        'build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk',
        'build/app/outputs/flutter-apk/app-arm64-v8a-release.apk',
        'build/app/outputs/flutter-apk/app-x86_64-release.apk',
      ]);
    });

    test('the universal APK is not part of the published set', () {
      expect(
        releaseApkPaths,
        everyElement(isNot(contains('app-release.apk'))),
        reason:
            'releases attach the three split APKs only; the universal '
            'APK stays a local testing artifact',
      );
    });

    test('ABI codes are parsed from the well-known split file names', () {
      expect(abiCodeForApkPath(releaseApkPaths[0]), 1);
      expect(abiCodeForApkPath(releaseApkPaths[1]), 2);
      expect(abiCodeForApkPath(releaseApkPaths[2]), 3);
      expect(
        abiCodeForApkPath('build/app/outputs/flutter-apk/app-release.apk'),
        isNull,
        reason: 'a universal APK name carries no ABI',
      );
    });

    test('expected version codes follow the N*10 + abiCode scheme', () {
      final artifacts = buildReleaseArtifacts(2);
      expect(artifacts.map((artifact) => artifact.path), releaseApkPaths);
      expect(
        artifacts.map((artifact) => artifact.expectedVersionCode),
        [21, 22, 23],
        reason:
            'N = 2 (pubspec 0.2.0+2): armeabi-v7a 21, arm64-v8a 22, '
            'x86_64 23',
      );
      expect(
        buildReleaseArtifacts(
          7,
        ).map((artifact) => artifact.expectedVersionCode),
        [71, 72, 73],
      );
    });

    test(
      'a path without a known ABI keeps exactly the pubspec build number',
      () {
        expect(expectedVersionCode(5, 'x/app-release.apk'), 5);
      },
    );
  });

  group('publish-name derivation (cycle-app-<version>-<abi>.apk)', () {
    const version = '0.2.0';

    test('derives the publish name for each per-ABI split APK', () {
      expect(
        publishedApkFileName(
          apkPath: 'build/app/outputs/flutter-apk/app-arm64-v8a-release.apk',
          versionName: version,
        ),
        'cycle-app-0.2.0-arm64-v8a.apk',
      );
      expect(
        publishedApkFileName(
          apkPath: 'build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk',
          versionName: version,
        ),
        'cycle-app-0.2.0-armeabi-v7a.apk',
      );
      expect(
        publishedApkFileName(
          apkPath: 'build/app/outputs/flutter-apk/app-x86_64-release.apk',
          versionName: version,
        ),
        'cycle-app-0.2.0-x86_64.apk',
      );
    });

    test('round-trips: ABI parsed back from the publish name matches the '
        'canonical path ABI and keeps the versionCode scheme', () {
      const build = 7;
      for (final artifact in buildReleaseArtifacts(build)) {
        final publishName = publishedApkFileName(
          apkPath: artifact.path,
          versionName: version,
        );
        expect(publishName, startsWith('cycle-app-$version-'));
        expect(publishName, endsWith('.apk'));
        final abi = publishName.substring(
          'cycle-app-$version-'.length,
          publishName.length - '.apk'.length,
        );
        expect(
          abiCodes[abi],
          abiCodeForApkPath(artifact.path),
          reason: 'the publish name encodes the same ABI as the build path',
        );
        expect(
          build * 10 + abiCodes[abi]!,
          artifact.expectedVersionCode,
          reason: 'the round-tripped ABI keeps the split versionCode scheme',
        );
      }
    });

    test('multi-digit version components survive the derivation', () {
      expect(
        publishedApkFileName(
          apkPath: releaseApkPaths[1],
          versionName: '10.11.12',
        ),
        'cycle-app-10.11.12-arm64-v8a.apk',
      );
    });

    test('fails loudly for a name without a known ABI', () {
      for (final path in [
        'build/app/outputs/flutter-apk/app-release.apk',
        'some/unrelated.apk',
      ]) {
        expect(
          () => publishedApkFileName(apkPath: path, versionName: version),
          throwsA(isA<ReleaseException>()),
          reason: 'no publish name is derivable for "$path"',
        );
      }
    });
  });

  group('staged publish paths (dry-run / gh attach list)', () {
    test('lists one staged path per artifact, in attach order', () {
      expect(stagedPublishApkPaths('0.2.0'), [
        'build/gh-release/cycle-app-0.2.0-armeabi-v7a.apk',
        'build/gh-release/cycle-app-0.2.0-arm64-v8a.apk',
        'build/gh-release/cycle-app-0.2.0-x86_64.apk',
      ]);
    });
  });

  group('expanded release-notes body (one checksum line per APK)', () {
    const fingerprint =
        '6a1f2c4d5e6f708192a3b4c5d6e7f8091a2b3c4d5e6f708192a3b4c5d6e7f809';

    test(
      'lists the certificate fingerprint once and one line per artifact',
      () {
        final body = buildNotesBody(
          certificateFingerprint: fingerprint,
          apkSha256ByPath: {
            releaseApkPaths[0]: 'AA' * 32,
            releaseApkPaths[1]: 'BB' * 32,
            releaseApkPaths[2]: 'CC' * 32,
          },
        );
        expect(
          'SHA-256 certificate fingerprint: '.allMatches(body).length,
          1,
          reason: 'all three APKs share one release key',
        );
        expect(body, contains('SHA-256 certificate fingerprint: $fingerprint'));
        expect('APK SHA-256: '.allMatches(body).length, 3);
        for (final path in releaseApkPaths) {
          expect(body, contains('APK SHA-256: $path '));
        }
        expect(body, contains('aa' * 32));
        expect(body, contains('bb' * 32));
        expect(body, contains('cc' * 32));
      },
    );

    test('normalizes a colonized certificate fingerprint in the notes', () {
      final body = buildNotesBody(
        certificateFingerprint:
            '6A:1F:2C:4D:5E:6F:70:81:92:A3:B4:C5:D6:E7:'
            'F8:09:1A:2B:3C:4D:5E:6F:70:81:92:A3:B4:C5:D6:E7:F8:09',
        apkSha256ByPath: {releaseApkPaths.first: 'ff' * 32},
      );
      expect(body, contains('SHA-256 certificate fingerprint: $fingerprint'));
    });

    test('checksum lines reference the published APK filenames '
        '(one line per publish name, no canonical build name)', () {
      final body = buildNotesBody(
        certificateFingerprint: fingerprint,
        apkSha256ByPath: {
          for (final staged in stagedPublishApkPaths('0.2.0'))
            staged.split('/').last: 'aa' * 32,
        },
      );
      for (final name in [
        'cycle-app-0.2.0-armeabi-v7a.apk',
        'cycle-app-0.2.0-arm64-v8a.apk',
        'cycle-app-0.2.0-x86_64.apk',
      ]) {
        expect(body, contains('APK SHA-256: $name aa'));
      }
      expect(
        'APK SHA-256: '.allMatches(body).length,
        3,
        reason: 'one checksum line per published APK',
      );
    });
  });

  group('dry-run gh command format (all three split APKs attached)', () {
    test('attaches the staged publish paths in release order', () {
      final staged = stagedPublishApkPaths('0.2.0');
      final command = formatDryRunGhCommand(
        'v0.2.0',
        staged,
        'fingerprint line\nchecksum line\n',
      );
      expect(command, contains('gh release create v0.2.0 build/gh-release/'));
      expect(command, contains(' --generate-notes --notes "'));
      var lastIndex = -1;
      for (final path in staged) {
        final index = command.indexOf(path);
        expect(index, greaterThan(lastIndex), reason: '$path out of order');
        lastIndex = index;
      }
      expect(
        command,
        isNot(contains('app-arm')),
        reason:
            'the attach list uses the publish names, not the canonical build '
            'names',
      );
    });

    test('flattens the notes body newlines into the escaped form', () {
      final command = formatDryRunGhCommand(
        'v0.2.0',
        releaseApkPaths,
        'a\nb\n',
      );
      expect(command, contains('--notes "a\\nb"'));
    });
  });

  group('aapt versionCode warning (split scheme wording)', () {
    test('names the artifact, the embedded code, and the expectation', () {
      final warning = versionCodeMismatchWarning(
        apkPath: 'build/app/outputs/flutter-apk/app-arm64-v8a-release.apk',
        embeddedVersionCode: 5,
        expectedVersionCode: 22,
      );
      expect(warning, contains('app-arm64-v8a-release.apk'));
      expect(warning, contains('versionCode 5'));
      expect(warning, contains('expected 22'));
      expect(warning, contains('android/app/build.gradle.kts'));
    });

    test('carries no stale offset/universal wording', () {
      final warning = versionCodeMismatchWarning(
        apkPath: releaseApkPaths.first,
        embeddedVersionCode: 9,
        expectedVersionCode: 11,
      );
      expect(warning, isNot(contains('force-version-code-ignoring-abi')));
      expect(warning, isNot(contains('1000')));
      expect(warning, isNot(contains('ABI splits offset')));
      expect(warning, isNot(contains('universal')));
    });
  });

  group('release-notes body assembly', () {
    const fingerprint =
        '6a1f2c4d5e6f708192a3b4c5d6e7f8091a2b3c4d5e6f708192a3b4c5d6e7f809';

    test('contains the certificate fingerprint and APK checksum lines', () {
      final body = buildNotesBody(
        certificateFingerprint: fingerprint,
        apkSha256ByPath: {
          releaseApkPaths.first:
              'deadbeefcafebabe0123456789abcdefdeadbeefcafebabe0123456789abcdef',
        },
      );
      expect(body, contains('SHA-256 certificate fingerprint: $fingerprint'));
      expect(
        body,
        contains(
          'APK SHA-256: ${releaseApkPaths.first} '
          'deadbeefcafebabe0123456789abcdefdeadbeefcafebabe0123456789abcdef',
        ),
      );
    });

    test('normalizes a colonized certificate fingerprint in the notes', () {
      final body = buildNotesBody(
        certificateFingerprint:
            '6A:1F:2C:4D:5E:6F:70:81:92:A3:B4:C5:D6:E7:'
            'F8:09:1A:2B:3C:4D:5E:6F:70:81:92:A3:B4:C5:D6:E7:F8:09',
        apkSha256ByPath: {'x/app-release.apk': 'ff' * 32},
      );
      expect(body, contains('SHA-256 certificate fingerprint: $fingerprint'));
    });
  });
}
