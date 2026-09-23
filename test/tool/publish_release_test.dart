// Pure-logic tests for tool/publish_release.dart — helper number two of the
// two-script release flow: it consumes the build/gh-release/ staging tree
// that tool/download_and_sign.dart left behind (handoff manifest + signed
// APKs), computes the real checksums, assembles/refreshes the GitHub release
// (the create command authors the tag at the manifest's head SHA), opens the
// release-branch PR with soft-fail semantics, and prints the post-release
// info. This helper is the ONLY one with a --dry-run, and the rehearsal
// prints would-be gh commands WITH EXACT REAL CHECKSUMS — no placeholders.
//
// Pure seam as everywhere in test/tool/: fixture JSON/CLI output texts and
// temp-dir sandboxes only — no real gh/apksigner/aapt/git/sha256sum (the gh
// and sha256sum layers are injectable runners fed with fixture results).
// Relative import on purpose: tool/ scripts live outside lib/. The two
// release scripts share names for their local plumbing, so both are
// prefixed here; the shared module is imported plainly.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/publish_release.dart' as publish;
import '../../tool/release_names.dart';

/// The pinned release-certificate fingerprint, duplicated here from the
/// committed [pinFilePath] content so the notes-body tests pin the exact
/// trust anchor the release must carry.
const pinnedReleaseFingerprint =
    '0aa5749804b8ed9e3c207f851b5902775d762207d60c2485a26b5d75eff5355b';

/// A well-formed 40-char lowercase head SHA for the manifest fixtures.
const validHeadSha = '978dbc5b9ee19ff0aedfc03594a603013f0e034a';

/// The pinned fingerprint in apksigner's colon-separated uppercase shape —
/// the lenient normalizer must accept it.
const pinnedFingerprintColonUppercase =
    '0A:A5:74:98:04:B8:ED:9E:3C:20:7F:85:1B:59:02:77:5D:76:22:07:D6:0C:24:85'
    ':A2:6B:5D:75:EF:F5:35:5B';

void main() {
  group('argument parsing', () {
    test('accepts a well-formed tag plus --dry-run', () {
      final options = publish.parseArguments(['v1.2.3', '--dry-run']);
      expect(options.tag, 'v1.2.3');
      expect(options.dryRun, isTrue);
    });

    test('parses flags in any order', () {
      final options = publish.parseArguments(['--dry-run', 'v0.1.0']);
      expect(options.tag, 'v0.1.0');
      expect(options.dryRun, isTrue);
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
          () => publish.parseArguments([tag]),
          throwsA(isA<UsageException>()),
          reason: 'tag "$tag" must be rejected',
        );
      }
    });

    test('rejects unknown flags — including --run-id, which belongs to the '
        'download helper only (the head SHA comes from the manifest here)', () {
      expect(
        () => publish.parseArguments(['--unknown', 'v1.2.3']),
        throwsA(isA<UsageException>()),
      );
      expect(
        () => publish.parseArguments(['v1.2.3', '--run-id', '12345']),
        throwsA(
          isA<UsageException>().having(
            (error) => error.message,
            'message',
            contains('unknown flag: --run-id'),
          ),
        ),
      );
      expect(
        () => publish.parseArguments(['-f', 'v1.2.3']),
        throwsA(isA<UsageException>()),
      );
    });

    test('rejects missing and extra positional arguments', () {
      expect(
        () => publish.parseArguments(const []),
        throwsA(isA<UsageException>()),
      );
      expect(
        () => publish.parseArguments(['v1.2.3', 'v2.0.0']),
        throwsA(isA<UsageException>()),
      );
    });

    test('the usage line names publish_release and the dry-run flag', () {
      expect(publish.usage, contains('publish_release.dart'));
      expect(publish.usage, contains('--dry-run'));
    });
  });

  group('staged-dir consumption (temp-dir sandbox)', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('publish_consumption');
    });

    tearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    File manifestFile() => File('${root.path}/$handoffManifestPath');

    File stagedApk(String abi) => File(
      '${root.path}/'
      '${stagedPublishPath(versionName: '0.2.1', abi: abi)}',
    );

    void stageHappyTree() {
      manifestFile()
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          '{"tag":"v0.2.1","versionName":"0.2.1","versionCodeBase":3,'
          '"runId":1234567890,"headSha":"$validHeadSha"}\n',
        );
      for (final abi in releaseAbis) {
        stagedApk(abi).writeAsBytesSync([1, 2, 3]);
      }
    }

    test('a happy staging tree consumes into the manifest and requires the '
        'APKs', () {
      stageHappyTree();
      final manifest = publish.consumeStagedRelease(root: root, tag: 'v0.2.1');
      expect(manifest.tag, 'v0.2.1');
      expect(manifest.versionName, '0.2.1');
      expect(manifest.versionCodeBase, 3);
      expect(manifest.runId, 1234567890);
      expect(manifest.headSha, validHeadSha);
    });

    test('a missing manifest fails loudly, pointing at the sign helper', () {
      expect(
        () => publish.consumeStagedRelease(root: root, tag: 'v0.2.1'),
        throwsA(
          isA<ReleaseToolException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('$handoffManifestPath is missing'),
              contains('download_and_sign.dart'),
            ),
          ),
        ),
      );
    });

    test('an unparsable manifest fails loudly', () {
      manifestFile()
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('not json');
      expect(
        () => publish.consumeStagedRelease(root: root, tag: 'v0.2.1'),
        throwsA(
          isA<ReleaseToolException>().having(
            (error) => error.message,
            'message',
            contains('invalid'),
          ),
        ),
      );
    });

    test('a manifest describing another tag fails loudly (stale or copied '
        'staging dir)', () {
      stageHappyTree();
      expect(
        () => publish.consumeStagedRelease(root: root, tag: 'v0.2.0'),
        throwsA(
          isA<ReleaseToolException>().having(
            (error) => error.message,
            'message',
            allOf(contains('v0.2.0'), contains('v0.2.1')),
          ),
        ),
      );
    });

    test('missing or empty staged APKs fail loudly by name', () {
      manifestFile()
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          '{"tag":"v0.2.1","versionName":"0.2.1","versionCodeBase":3,'
          '"runId":1234567890,"headSha":"$validHeadSha"}\n',
        );
      stagedApk('armeabi-v7a').writeAsBytesSync([1, 2, 3]);
      stagedApk('x86_64').writeAsBytesSync([1, 2, 3]);
      // arm64-v8a never lands.
      expect(
        () => publish.consumeStagedRelease(root: root, tag: 'v0.2.1'),
        throwsA(
          isA<ReleaseToolException>().having(
            (error) => error.message,
            'message',
            contains('cycle-app-0.2.1-arm64-v8a.apk'),
          ),
        ),
      );
    });
  });

  group('checksum parsing (sha256sum output)', () {
    test('extracts the digest from standard sha256sum output', () {
      expect(
        publish.parseSha256sum(
          '$pinnedReleaseFingerprint  '
          'cycle-app-0.2.1-arm64-v8a.apk\n',
        ),
        pinnedReleaseFingerprint,
      );
      expect(publish.parseSha256sum('deadbeef /some/path.apk\n'), 'deadbeef');
    });

    test('malformed or empty output yields null', () {
      expect(publish.parseSha256sum(''), isNull);
      expect(publish.parseSha256sum('\n'), isNull);
    });
  });

  group('staged checksums (real, read-only — injectable runner)', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('publish_checksums');
    });

    tearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    Future<ProcessResult> fakeSha256Runner(List<String> arguments) async {
      final file = arguments.last;
      final digest = file.contains('armeabi-v7a')
          ? '11' * 32
          : file.contains('arm64-v8a')
          ? '22' * 32
          : '33' * 32;
      return ProcessResult(0, 0, '$digest  $file\n', '');
    }

    test('maps the staged paths onto the publish names in attach order, '
        'with the real digests', () async {
      final printed = <String>[];
      final shaByPublishName = await publish.stagedChecksums(
        root: root,
        versionName: '0.2.1',
        sha256Runner: fakeSha256Runner,
        printer: printed.add,
      );
      expect(shaByPublishName.keys.toList(), publishApkNames('0.2.1'));
      expect(
        printed,
        [
          for (final entry in shaByPublishName.entries)
            'APK SHA-256: ${entry.key} ${entry.value}',
        ],
        reason:
            'the checksum lines go through the injected printer, not '
            'past the collected list',
      );
      expect(shaByPublishName, {
        'cycle-app-0.2.1-armeabi-v7a.apk': '11' * 32,
        'cycle-app-0.2.1-arm64-v8a.apk': '22' * 32,
        'cycle-app-0.2.1-x86_64.apk': '33' * 32,
      });
    });

    test('a sha256sum failure fails loudly', () async {
      Future<ProcessResult> failing(List<String> arguments) async =>
          ProcessResult(0, 1, '', 'sha256sum: boom');
      expect(
        () => publish.stagedChecksums(
          root: root,
          versionName: '0.2.1',
          sha256Runner: failing,
        ),
        throwsA(isA<ReleaseToolException>()),
      );
    });
  });

  group('release-notes body assembly (create path)', () {
    test('lists the fingerprint once and one checksum line per APK in '
        'attach order', () {
      final body = publish.buildNotesBody(
        certificateFingerprint: pinnedReleaseFingerprint,
        apkSha256ByPublishName: {
          for (final name in publishApkNames('0.2.1')) name: '99' * 32,
        },
      );
      expect(
        'SHA-256 certificate fingerprint: '.allMatches(body).length,
        1,
        reason: 'all three APKs share one release key',
      );
      expect(
        body,
        contains('SHA-256 certificate fingerprint: $pinnedReleaseFingerprint'),
      );
      expect('APK SHA-256: '.allMatches(body).length, 3);
      // Attach order: armeabi-v7a → arm64-v8a → x86_64.
      final checksumLines = RegExp(
        r'^APK SHA-256: (\S+) ([0-9a-f]{64})$',
        multiLine: true,
      ).allMatches(body).toList();
      expect(
        checksumLines.map((match) => match.group(1)),
        publishApkNames('0.2.1'),
      );
    });
  });

  group('checksum splice (existing release, re-attach)', () {
    final oldArmeabiHash = 'aa' * 32;
    final oldArm64Hash = 'bb' * 32;
    final oldX86Hash = 'cc' * 32;
    final freshArmeabiHash = '11' * 32;
    final freshArm64Hash = '22' * 32;
    final freshX86Hash = '33' * 32;

    final oldBody =
        '## Cycle App 0.2.1\n'
        '\n'
        'Changelog: nits and a fix.\n'
        '\n'
        'SHA-256 certificate fingerprint: $pinnedReleaseFingerprint\n'
        'APK SHA-256: cycle-app-0.2.1-armeabi-v7a.apk $oldArmeabiHash\n'
        'APK SHA-256: cycle-app-0.2.1-arm64-v8a.apk $oldArm64Hash\n'
        'APK SHA-256: cycle-app-0.2.1-x86_64.apk $oldX86Hash\n'
        '\n'
        'Download the APK for your device below and install it over the '
        'previous release.\n';

    final fresh = {
      'cycle-app-0.2.1-armeabi-v7a.apk': freshArmeabiHash,
      'cycle-app-0.2.1-arm64-v8a.apk': freshArm64Hash,
      'cycle-app-0.2.1-x86_64.apk': freshX86Hash,
    };

    test(
      'replaces exactly the APK SHA-256 lines, byte-preserving the rest',
      () {
        final spliced = publish.spliceChecksumLines(oldBody, fresh);
        expect(
          spliced,
          '## Cycle App 0.2.1\n'
          '\n'
          'Changelog: nits and a fix.\n'
          '\n'
          'SHA-256 certificate fingerprint: $pinnedReleaseFingerprint\n'
          'APK SHA-256: cycle-app-0.2.1-armeabi-v7a.apk $freshArmeabiHash\n'
          'APK SHA-256: cycle-app-0.2.1-arm64-v8a.apk $freshArm64Hash\n'
          'APK SHA-256: cycle-app-0.2.1-x86_64.apk $freshX86Hash\n'
          '\n'
          'Download the APK for your device below and install it over the '
          'previous release.\n',
        );
        for (final stale in [oldArmeabiHash, oldArm64Hash, oldX86Hash]) {
          expect(spliced, isNot(contains(stale)));
        }
      },
    );

    test('the fingerprint line and prose survive untouched', () {
      final spliced = publish.spliceChecksumLines(oldBody, fresh);
      expect(
        spliced.contains(
          'SHA-256 certificate fingerprint: $pinnedReleaseFingerprint',
        ),
        isTrue,
      );
      expect(spliced, contains('## Cycle App 0.2.1'));
      expect(spliced, contains('Changelog: nits and a fix.'));
    });

    test('a checksum line for an unpublished (stale) name disappears', () {
      final withStale =
          'Intro text\n'
          'APK SHA-256: cycle-app-0.1.0-x86_64.apk $oldX86Hash\n'
          'APK SHA-256: cycle-app-0.2.1-arm64-v8a.apk $oldArm64Hash\n'
          'Outro text\n';
      final spliced = publish.spliceChecksumLines(withStale, {
        'cycle-app-0.2.1-arm64-v8a.apk': freshArm64Hash,
      });
      expect(spliced, isNot(contains('cycle-app-0.1.0-x86_64.apk')));
      expect(
        spliced,
        'Intro text\n'
        'APK SHA-256: cycle-app-0.2.1-arm64-v8a.apk $freshArm64Hash\n'
        'Outro text\n',
      );
    });

    test('a body without checksum lines gets the fresh block appended', () {
      const plainBody = '## Cycle App 0.2.1\n\nAuto-generated changelog.\n';
      final spliced = publish.spliceChecksumLines(plainBody, {
        'cycle-app-0.2.1-arm64-v8a.apk': freshArm64Hash,
        'cycle-app-0.2.1-x86_64.apk': freshX86Hash,
      });
      expect(spliced, startsWith(plainBody));
      expect(
        spliced,
        contains(
          'APK SHA-256: cycle-app-0.2.1-arm64-v8a.apk $freshArm64Hash\n',
        ),
      );
      expect(
        spliced,
        contains('APK SHA-256: cycle-app-0.2.1-x86_64.apk $freshX86Hash\n'),
      );
    });
  });

  group('release-existence probe (gh "not found" narrow route)', () {
    // Shaped like the stderr line gh prints when a release does not exist:
    // the API's 404 surfaces as "Not Found" in gh's own error text.
    const notFoundFixture =
        'release view v0.2.1: could not determine release: HTTP 404: '
        'Not Found (https://api.github.com/repos/BenediktBurger/cycle-app/'
        'releases/tags/v0.2.1)';

    test('gh\'s 404 wording is recognized as "release missing"', () {
      expect(publish.releaseMissing(notFoundFixture), isTrue);
      expect(publish.releaseMissing('gh: Not Found'), isTrue);
    });

    test(
      'transient or environmental gh failures are NOT "release missing"',
      () {
        const transientFixtures = [
          'gh: auth error: could not refresh token (expired)',
          'dial tcp: lookup api.github.com: no such host',
          'HTTP 502: Bad Gateway (https://api.github.com/graphql)',
          'HTTP 403: API rate limit exceeded',
          '',
        ];
        for (final stderrFixture in transientFixtures) {
          expect(
            publish.releaseMissing(stderrFixture),
            isFalse,
            reason: 'stderr "$stderrFixture" is not a release-missing probe',
          );
        }
      },
    );
  });

  group('dry-run release payloads', () {
    const tag = 'v0.2.1';
    final staged = stagedPublishPaths('0.2.1');
    final fresh = {
      'cycle-app-0.2.1-armeabi-v7a.apk': '11' * 32,
      'cycle-app-0.2.1-arm64-v8a.apk': '22' * 32,
      'cycle-app-0.2.1-x86_64.apk': '33' * 32,
    };
    final body = publish.buildNotesBody(
      certificateFingerprint: pinnedReleaseFingerprint,
      apkSha256ByPublishName: fresh,
    );

    test('missing release: prints the would-be gh release create payload '
        'with --target (the tag is authored at publish time) and the notes '
        'body with the checksum lines, attach order first', () {
      final payload = publish.formatDryRunGhCreateCommand(
        tag,
        staged,
        body,
        headSha: validHeadSha,
      );
      expect(payload, contains('gh release create v0.2.1'));
      expect(payload, contains('--generate-notes'));
      expect(payload, contains('--target $validHeadSha'));
      // Attach order: armeabi-v7a → arm64-v8a → x86_64.
      var lastIndex = -1;
      for (final path in staged) {
        final index = payload.indexOf(path);
        expect(index, greaterThan(lastIndex), reason: '$path out of order');
        lastIndex = index;
      }
      expect(payload, contains('SHA-256 certificate fingerprint:'));
      expect(
        payload,
        contains('APK SHA-256: cycle-app-0.2.1-arm64-v8a.apk ${'22' * 32}'),
      );
      expect(payload, contains(publish.notesFilePath(tag)));
    });

    test('existing release: prints the would-be upload + edit commands '
        '(the tag exists — no --target needed there)', () {
      final spliced = publish.spliceChecksumLines(body, fresh);
      final payload = publish.formatDryRunGhUpdateCommands(
        tag,
        staged,
        spliced,
      );
      expect(payload, contains('gh release upload v0.2.1'));
      expect(payload, contains('--clobber'));
      expect(payload, isNot(contains('--target')));
      // Attach order: armeabi-v7a → arm64-v8a → x86_64.
      var lastIndex = -1;
      for (final path in staged) {
        final index = payload.indexOf(path);
        expect(index, greaterThan(lastIndex), reason: '$path out of order');
        lastIndex = index;
      }
      expect(payload, contains('gh release edit v0.2.1'));
      expect(payload, contains('--notes-file'));
      // The would-be edit payload carries the spliced body: the checksum
      // lines exactly as spliced, byte-for-byte.
      expect(
        payload,
        contains(
          'APK SHA-256: cycle-app-0.2.1-armeabi-v7a.apk '
          '${'11' * 32}\n',
        ),
      );
      expect(payload, contains(publish.spliceChecksumLines(body, fresh)));
    });

    test('the dry-run PR plumbing payloads come before any mutating step', () {
      final payload = publish.formatDryRunPrCommands(
        branch: releaseBranchForTag(tag),
        tag: tag,
      );
      expect(
        payload,
        contains(
          'gh pr create --repo BenediktBurger/cycle-app --base development '
          '--head release/v0.2.1 --title "Release v0.2.1"',
        ),
      );
      expect(payload, contains('gh pr merge --merge --auto release/v0.2.1'));
      expect(payload, contains('releases/tag/v0.2.1'));
    });
  });

  group('post-release PR plumbing (gh argv + lenient rerun handling)', () {
    const branch = 'release/v0.2.1';
    const tag = 'v0.2.1';

    test('gh pr create argv: base development, head the release branch, '
        'release-URL body', () {
      expect(publish.prCreateArguments(branch: branch, tag: tag), [
        'pr',
        'create',
        '--repo',
        releaseRepo,
        '--base',
        'development',
        '--head',
        branch,
        '--title',
        'Release v0.2.1',
        '--body',
        publish.prCreateBody(tag),
      ]);
      expect(
        publish.prCreateBody(tag),
        contains(
          'https://github.com/BenediktBurger/cycle-app/releases/tag/v0.2.1',
        ),
      );
    });

    test('gh pr merge argv: merge-commit method, auto (never squash/rebase '
        '— the release commit must stay an ancestor of development)', () {
      expect(publish.prAutoMergeArguments(branch), [
        'pr',
        'merge',
        '--merge',
        '--auto',
        branch,
      ]);
    });

    test('prAlreadyExists is lenient and case-insensitive', () {
      expect(
        publish.prAlreadyExists(
          'pull request for branch "release/v0.2.1" already exists',
        ),
        isTrue,
      );
      expect(
        publish.prAlreadyExists(
          'A Pull Request for the release/v0.2.1 branch ALREADY EXISTS.',
        ),
        isTrue,
      );
      expect(
        publish.prAlreadyExists(
          'dial tcp: lookup api.github.com: no such host',
        ),
        isFalse,
      );
      expect(publish.prAlreadyExists(''), isFalse);
    });

    test('soft-fail design: gh failures print manual commands and the '
        'flow completes without throwing', () async {
      Future<ProcessResult> failing(List<String> arguments) async {
        if (arguments.first == 'pr' && arguments[1] == 'create') {
          return ProcessResult(0, 1, '', 'gh: boom (create rejected)');
        }
        if (arguments.first == 'pr' && arguments[1] == 'merge') {
          return ProcessResult(
            0,
            4,
            '',
            'gh: pull request auto merge is disabled for this repository',
          );
        }
        return ProcessResult(0, 1, '', 'unexpected gh invocation');
      }

      final lines = <String>[];
      await publish.openReleasePr(
        branch: branch,
        tag: tag,
        ghRunner: failing,
        printer: lines.add,
      );
      final output = lines.join('\n');
      expect(
        output,
        contains(
          'gh pr create --repo BenediktBurger/cycle-app --base development '
          '--head release/v0.2.1 --title "Release v0.2.1"',
        ),
        reason: 'the exact manual command must be printed on failure',
      );
      expect(output, contains('Allow auto-merge'));
      expect(output, contains('gh pr merge --merge --auto release/v0.2.1'));
    });

    test('an already-existing PR is detected leniently and goes straight '
        'to the auto-merge', () async {
      Future<ProcessResult> alreadyExists(List<String> arguments) async {
        if (arguments.first == 'pr' && arguments[1] == 'create') {
          return ProcessResult(
            0,
            1,
            '',
            'pull request for branch "release/v0.2.1" already exists',
          );
        }
        if (arguments.first == 'pr' && arguments[1] == 'merge') {
          return ProcessResult(0, 0, 'auto merge queued', '');
        }
        return ProcessResult(0, 1, '', 'unexpected gh invocation');
      }

      final lines = <String>[];
      await publish.openReleasePr(
        branch: branch,
        tag: tag,
        ghRunner: alreadyExists,
        printer: lines.add,
      );
      final output = lines.join('\n');
      expect(output, contains('already exists'));
      expect(output, contains('auto-merge queued'));
      expect(output, isNot(contains('manual command')));
    });

    test(
      'the happy path reports the opened PR and the queued auto-merge',
      () async {
        Future<ProcessResult> passing(List<String> arguments) async {
          if (arguments.first == 'pr' && arguments[1] == 'create') {
            return ProcessResult(
              0,
              0,
              'https://github.com/BenediktBurger/cycle-app/pull/26',
              '',
            );
          }
          return ProcessResult(0, 0, 'auto merge queued', '');
        }

        final lines = <String>[];
        await publish.openReleasePr(
          branch: branch,
          tag: tag,
          ghRunner: passing,
          printer: lines.add,
        );
        final output = lines.join('\n');
        expect(output, contains('pull/26'));
        expect(output, contains('auto-merge'));
      },
    );
  });

  group('end-to-end publish flow (sandbox + injectable gh/sha runners)', () {
    const tag = 'v0.2.1';

    late Directory root;
    final ghInvocations = <List<String>>[];

    setUp(() async {
      root = await Directory.systemTemp.createTemp('publish_flow');
      ghInvocations.clear();
    });

    tearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    void stageHappyTree() {
      File('${root.path}/$handoffManifestPath')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          '{"tag":"v0.2.1","versionName":"0.2.1","versionCodeBase":3,'
          '"runId":1234567890,"headSha":"$validHeadSha"}\n',
        );
      File('${root.path}/tool/release_fingerprint.txt')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('$pinnedReleaseFingerprint\n');
      for (final abi in releaseAbis) {
        File(
          '${root.path}/'
          '${stagedPublishPath(versionName: '0.2.1', abi: abi)}',
        ).writeAsBytesSync([0, 1, 2, 3]);
      }
    }

    Future<ProcessResult> fakeSha256Runner(List<String> arguments) async {
      final file = arguments.last;
      final digest = file.contains('armeabi-v7a')
          ? '44' * 32
          : file.contains('arm64-v8a')
          ? '55' * 32
          : '66' * 32;
      return ProcessResult(0, 0, '$digest  $file\n', '');
    }

    /// A gh runner whose release-view answer and mutator exits are chosen
    /// per test; everything unexpected fails loudly so a stray gh call
    /// cannot pass silently.
    Future<ProcessResult> Function(List<String>) ghFixture({
      required String releaseViewResult, // 'missing' | 'present'
      int createExit = 0,
      int uploadExit = 0,
      int editExit = 0,
      int mergeExit = 0,
      String existingBody = '',
    }) {
      Future<ProcessResult> run(List<String> arguments) async {
        ghInvocations.add(arguments);
        Future<ProcessResult> ok([String stdout = '', String stderr = '']) =>
            Future.value(ProcessResult(0, 0, stdout, stderr));
        if (arguments.first == 'auth') {
          return ok('Logged in to github.com', '');
        }
        if (arguments[0] == 'release' && arguments[1] == 'view') {
          return releaseViewResult == 'present'
              ? ok(existingBody)
              : Future.value(
                  ProcessResult(0, 1, '', 'HTTP 404: Not Found (release)'),
                );
        }
        if (arguments[0] == 'release' && arguments[1] == 'create') {
          return createExit == 0
              ? ok('released')
              : Future.value(
                  ProcessResult(0, createExit, '', 'create rejected'),
                );
        }
        if (arguments[0] == 'release' && arguments[1] == 'upload') {
          return uploadExit == 0
              ? ok('uploaded')
              : Future.value(
                  ProcessResult(0, uploadExit, '', 'upload rejected'),
                );
        }
        if (arguments[0] == 'release' && arguments[1] == 'edit') {
          return editExit == 0
              ? ok('edited')
              : Future.value(ProcessResult(0, editExit, '', 'edit rejected'));
        }
        if (arguments[0] == 'pr' && arguments[1] == 'create') {
          return ok('https://github.com/BenediktBurger/cycle-app/pull/27');
        }
        if (arguments[0] == 'pr' && arguments[1] == 'merge') {
          return mergeExit == 0
              ? ok('auto merge queued')
              : Future.value(
                  ProcessResult(
                    0,
                    mergeExit,
                    '',
                    'gh: pull request auto merge is disabled for this '
                        'repository',
                  ),
                );
        }
        fail('unexpected gh invocation in fixture: $arguments');
      }

      return run;
    }

    test('dry run on a missing release: prints the resolved manifest, the '
        'REAL checksums, the create payload with --target, and the PR '
        'payloads — and mutates nothing (placeholders are gone)', () async {
      stageHappyTree();
      final lines = <String>[];
      await publish.runPublishRelease(
        ['v0.2.1', '--dry-run'],
        root: root,
        ghRunner: ghFixture(releaseViewResult: 'missing'),
        sha256Runner: fakeSha256Runner,
        printer: lines.add,
      );
      final output = lines.join('\n');

      // Manifest fields as resolved.
      expect(output, contains('handoff manifest resolved:'));
      expect(output, contains('tag=v0.2.1'));
      expect(output, contains('versionName=0.2.1'));
      expect(output, contains('versionCodeBase=3'));
      expect(output, contains('runId=1234567890'));
      expect(output, contains('headSha=$validHeadSha'));

      // REAL checksums from the staged files (fixture digests), no
      // placeholder.
      expect(
        output,
        contains('APK SHA-256: cycle-app-0.2.1-armeabi-v7a.apk ${'44' * 32}'),
      );
      expect(
        output,
        contains('APK SHA-256: cycle-app-0.2.1-arm64-v8a.apk ${'55' * 32}'),
      );
      expect(
        output,
        contains('APK SHA-256: cycle-app-0.2.1-x86_64.apk ${'66' * 32}'),
      );
      expect(output, isNot(contains('<computed-on-the-real-run>')));

      // The create payload authors the tag at the manifest's head SHA.
      expect(output, contains('gh release create v0.2.1'));
      expect(output, contains('--target $validHeadSha'));
      expect(output, contains('--generate-notes'));
      // The fingerprint line + checksum lines in the would-be notes body.
      expect(
        output,
        contains('SHA-256 certificate fingerprint: $pinnedReleaseFingerprint'),
      );
      expect(
        output,
        contains('APK SHA-256: cycle-app-0.2.1-arm64-v8a.apk ${'55' * 32}'),
      );

      // PR payloads are printed, never run.
      expect(output, contains('gh pr create --repo'));
      expect(output, contains('gh pr merge --merge --auto release/v0.2.1'));
      expect(output, contains('dry run complete'));

      // Nothing mutating was handed to gh: only auth status and the
      // release view (read-only).
      for (final invocation in ghInvocations) {
        final isReadOnly =
            (invocation.first == 'auth') ||
            (invocation[0] == 'release' && invocation[1] == 'view');
        expect(isReadOnly, isTrue, reason: 'invocation: $invocation');
      }
    });

    test('dry run on an existing release: prints the --clobber payload and '
        'the spliced notes body with the fresh real checksums, and mutates '
        'nothing', () async {
      stageHappyTree();
      final oldBody =
          '## Cycle App 0.2.1\n'
          'APK SHA-256: cycle-app-0.2.1-arm64-v8a.apk ${'bb' * 32}\n';
      final lines = <String>[];
      await publish.runPublishRelease(
        ['v0.2.1', '--dry-run'],
        root: root,
        ghRunner: ghFixture(
          releaseViewResult: 'present',
          existingBody: oldBody,
        ),
        sha256Runner: fakeSha256Runner,
        printer: lines.add,
      );
      final output = lines.join('\n');

      expect(output, contains('gh release upload v0.2.1'));
      expect(output, contains('--clobber'));
      expect(output, contains('gh release edit v0.2.1'));
      // The stale checksum is spliced out, the fresh real digest spliced in.
      expect(output, isNot(contains('bb' * 32)));
      expect(
        output,
        contains('APK SHA-256: cycle-app-0.2.1-arm64-v8a.apk ${'55' * 32}'),
      );
      expect(output, contains('dry run complete'));
      for (final invocation in ghInvocations) {
        final isReadOnly =
            (invocation.first == 'auth') ||
            (invocation[0] == 'release' && invocation[1] == 'view');
        expect(isReadOnly, isTrue, reason: 'invocation: $invocation');
      }
    });

    test(
      'real run on a missing release: creates the release with --target '
      'at the manifest head SHA, writes the notes file, opens the PR',
      () async {
        stageHappyTree();
        final lines = <String>[];
        await publish.runPublishRelease(
          ['v0.2.1'],
          root: root,
          ghRunner: ghFixture(releaseViewResult: 'missing'),
          sha256Runner: fakeSha256Runner,
          printer: lines.add,
        );
        final output = lines.join('\n');

        final create = ghInvocations.firstWhere(
          (invocation) =>
              invocation[0] == 'release' && invocation[1] == 'create',
        );
        expect(create[2], 'v0.2.1');
        expect(create, contains('--target'));
        expect(create[create.indexOf('--target') + 1], validHeadSha);
        expect(create, contains('--generate-notes'));
        expect(create, contains('--notes-file'));
        // Attach order: armeabi-v7a → arm64-v8a → x86_64.
        final attached = create
            .where(
              (argument) =>
                  argument.startsWith('$ghReleaseStagingDir/') &&
                  argument.endsWith('.apk'),
            )
            .toList();
        expect(attached, stagedPublishPaths('0.2.1'));
        expect(
          ghInvocations.any((invocation) => invocation[0] == 'pr'),
          isTrue,
        );

        // The notes file was staged under the publish tree with the
        // fingerprint + checksum block.
        final notes = File('${root.path}/${publish.notesFilePath(tag)}');
        expect(notes.existsSync(), isTrue);
        final notesBody = notes.readAsStringSync();
        expect(
          notesBody,
          contains(
            'SHA-256 certificate fingerprint: $pinnedReleaseFingerprint',
          ),
        );
        expect(
          notesBody,
          contains('APK SHA-256: cycle-app-0.2.1-armeabi-v7a.apk ${'44' * 32}'),
        );
        expect(output, contains('created the release'));
      },
    );

    test('real run on an existing release: uploads --clobber, splices the '
        'checksums into the notes, and a rejected PR merge soft-fails with '
        'the manual command (exit stays 0)', () async {
      stageHappyTree();
      final oldBody =
          '## Cycle App 0.2.1\n'
          'APK SHA-256: cycle-app-0.2.1-arm64-v8a.apk ${'bb' * 32}\n';
      final lines = <String>[];
      await publish.runPublishRelease(
        ['v0.2.1'],
        root: root,
        ghRunner: ghFixture(
          releaseViewResult: 'present',
          existingBody: oldBody,
          editExit: 0,
          mergeExit: 4,
        ),
        sha256Runner: fakeSha256Runner,
        printer: lines.add,
      );
      final output = lines.join('\n');

      final upload = ghInvocations.firstWhere(
        (invocation) => invocation[0] == 'release' && invocation[1] == 'upload',
      );
      expect(upload, contains('--clobber'));
      final edit = ghInvocations.firstWhere(
        (invocation) => invocation[0] == 'release' && invocation[1] == 'edit',
      );
      expect(edit, contains('--notes-file'));
      // The updated notes were staged (stale hash gone, fresh one in).
      final notesBody = File(
        '${root.path}/${publish.notesFilePath(tag)}',
      ).readAsStringSync();
      expect(notesBody, isNot(contains('bb' * 32)));
      expect(
        notesBody,
        contains('APK SHA-256: cycle-app-0.2.1-arm64-v8a.apk ${'55' * 32}'),
      );
      expect(output, contains('uploaded the APKs'));
      expect(output, contains('release notes updated'));
      // Soft-fail: the merge rejection printed the manual fallback command
      // and the run completed normally (no throw above).
      expect(output, contains('gh pr merge --merge --auto release/v0.2.1'));
      expect(output, contains('Allow auto-merge'));
    });

    test('the notes fingerprint for a fresh create comes from the pin file '
        '(same trust anchor the signing gate enforces)', () {
      expect(
        publish.pinnedFingerprintForNotes(
          pinFileContent: '# grab\n$pinnedFingerprintColonUppercase\n',
        ),
        pinnedReleaseFingerprint,
      );
      expect(
        () => publish.pinnedFingerprintForNotes(pinFileContent: 'nope'),
        throwsA(isA<ReleaseToolException>()),
      );
    });
  });
}
