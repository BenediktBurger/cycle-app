// Pure-logic tests for tool/download_and_sign.dart — helper number one of
// the two-script release flow: it resolves the CI run, downloads the three
// unsigned artifacts, validates them against the run's own pubspec, signs
// them with the release keystore, stages them under build/gh-release/, and
// ends at the handoff manifest (build/gh-release/source.json). The publish
// half lives in tool/publish_release.dart; this helper has NO --dry-run (it
// mutates nothing outside gitignored dirs, and the flag is rejected loudly —
// tested here).
//
// Pure seam as everywhere in test/tool/: fixture JSON/CLI output texts and
// temp-dir sandboxes only — no real gh/apksigner/aapt/git/sha256sum. Relative
// import on purpose: tool/ scripts live outside lib/. The two release
// scripts share names for their local plumbing, so both are prefixed here;
// the shared module is imported plainly.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/download_and_sign.dart' as sign;
import '../../tool/release_names.dart';

/// The pinned release-certificate fingerprint, duplicated here from the
/// committed [pinFilePath] content so the parser tests pin the exact trust
/// anchor this helper must enforce.
const pinnedReleaseFingerprint =
    '0aa5749804b8ed9e3c207f851b5902775d762207d60c2485a26b5d75eff5355b';

void main() {
  group('argument parsing', () {
    test('accepts a well-formed tag plus --run-id', () {
      final options = sign.parseArguments(['v0.2.1', '--run-id', '12345']);
      expect(options.tag, 'v0.2.1');
      expect(options.runId, 12345);
    });

    test('parses flags in any order', () {
      final options = sign.parseArguments(['--run-id', '7', 'v0.1.0']);
      expect(options.tag, 'v0.1.0');
      expect(options.runId, 7);
    });

    test('rejects malformed tags (shared tag-key semantics)', () {
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
          () => sign.parseArguments([tag]),
          throwsA(isA<UsageException>()),
          reason: 'tag "$tag" must be rejected',
        );
      }
    });

    test('rejects unknown flags', () {
      expect(
        () => sign.parseArguments(['--unknown', 'v1.2.3']),
        throwsA(isA<UsageException>()),
      );
      expect(
        () => sign.parseArguments(['-f', 'v1.2.3']),
        throwsA(isA<UsageException>()),
      );
    });

    test('--dry-run is NOT accepted: unknown flag only (the split retired '
        'the global dry-run mode; publish_release.dart keeps the only '
        'rehearsal)', () {
      expect(
        () => sign.parseArguments(['v0.2.1', '--dry-run']),
        throwsA(
          isA<UsageException>().having(
            (error) => error.message,
            'message',
            contains('unknown flag: --dry-run'),
          ),
        ),
      );
    });

    test('rejects missing and extra positional arguments', () {
      expect(
        () => sign.parseArguments(const []),
        throwsA(isA<UsageException>()),
      );
      expect(
        () => sign.parseArguments(['v1.2.3', 'v2.0.0']),
        throwsA(isA<UsageException>()),
      );
    });

    test('rejects --run-id without a value or with a non-numeric value', () {
      expect(
        () => sign.parseArguments(['v1.2.3', '--run-id']),
        throwsA(isA<UsageException>()),
      );
      expect(
        () => sign.parseArguments(['v1.2.3', '--run-id', 'abc']),
        throwsA(isA<UsageException>()),
      );
      expect(
        () => sign.parseArguments(['v1.2.3', '--run-id', '-3']),
        throwsA(isA<UsageException>()),
        reason: 'a negative number is not a run id',
      );
    });

    test('the usage line names download_and_sign and carries no dry-run '
        'flag', () {
      expect(sign.usage, contains('download_and_sign.dart'));
      expect(sign.usage, isNot(contains('--dry-run')));
    });
  });

  group('CI artifact names (upload names, this helper only)', () {
    const version = '0.2.1';

    test('artifact names are the CI upload names (-unsigned suffix)', () {
      expect(
        sign.artifactName(versionName: version, abi: 'arm64-v8a'),
        'cycle-app-0.2.1-arm64-v8a-unsigned',
      );
      expect(sign.artifactNames(version), [
        'cycle-app-0.2.1-armeabi-v7a-unsigned',
        'cycle-app-0.2.1-arm64-v8a-unsigned',
        'cycle-app-0.2.1-x86_64-unsigned',
      ]);
    });

    test('artifact and publish names round-trip back to the ABI', () {
      for (final abi in abiCodes.keys) {
        final artifact = sign.artifactName(versionName: version, abi: abi);
        expect(sign.abiFromArtifactName(artifact), abi, reason: artifact);
        final publish = publishApkName(versionName: version, abi: abi);
        expect(sign.abiFromArtifactName(publish), abi, reason: publish);
      }
    });

    test('multi-digit versions survive the derivation', () {
      expect(
        sign.artifactName(versionName: '10.11.12', abi: 'x86_64'),
        'cycle-app-10.11.12-x86_64-unsigned',
      );
    });

    test('an unknown or unparseable name carries no ABI', () {
      expect(sign.abiFromArtifactName('some-unrelated-artifact'), isNull);
      expect(
        sign.abiFromArtifactName('cycle-app-0.2.1-gravitron-unsigned'),
        isNull,
      );
    });
  });

  group('release-run selection (branch-based, gh run list --json output)', () {
    // Shaped like `gh run list --repo BenediktBurger/cycle-app
    // --workflow Release --json databaseId,headBranch,workflowName,name`:
    // gh emits runs newest-first. No tag exists at build time — the CI build
    // is started by a push of the release/** branch or by workflow_dispatch,
    // so the head branch is the selector (the helper derives it from its
    // vX.Y.Z argument).
    const fixture = '''
[
  {
    "databaseId": 703211,
    "headBranch": "release/v0.2.1",
    "workflowName": "Release",
    "name": "Release",
    "status": "completed"
  },
  {
    "databaseId": 703209,
    "headBranch": "release/v0.2.1",
    "workflowName": "Release",
    "name": "Release",
    "status": "completed"
  },
  {
    "databaseId": 703205,
    "headBranch": "release/v0.2.0",
    "workflowName": "Release",
    "name": "Release"
  },
  {
    "databaseId": 703201,
    "headBranch": "main",
    "workflowName": "CI",
    "name": "CI"
  }
]
''';

    test('picks the release branch\'s workflow run, newest-first', () {
      expect(
        sign.resolveRunId(runListJson: fixture, branch: 'release/v0.2.1'),
        703211,
        reason:
            '703211 and 703209 both match release/v0.2.1; the first list '
            'entry is the newest',
      );
    });

    test('ignores runs of other branches and workflows', () {
      expect(
        sign.resolveRunId(runListJson: fixture, branch: 'release/v0.2.0'),
        703205,
      );
    });

    test('zero matches fails loudly, naming the branch convention and the '
        '--run-id remedy', () {
      try {
        sign.resolveRunId(runListJson: fixture, branch: 'release/v9.9.9');
        fail('a release branch without a workflow run must fail loudly');
      } on ReleaseToolException catch (error) {
        expect(error.message, contains('release/v9.9.9'));
        expect(error.message, contains('release/v'));
        expect(error.message, contains('--run-id'));
      }
    });

    test('the --run-id override flow carries its id and never consults the '
        'branch match', () {
      final options = sign.parseArguments(['v0.2.1', '--run-id', '42']);
      expect(options.runId, 42);
      expect(options.tag, 'v0.2.1');
      // The branch derivation itself stays pure and unused in that flow:
      // resolveRunId is only called without --run-id.
      expect(releaseBranchForTag(options.tag), 'release/v0.2.1');
    });

    test('malformed or empty output fails loudly', () {
      for (final broken in ['', 'not json', '{}']) {
        expect(
          () =>
              sign.resolveRunId(runListJson: broken, branch: 'release/v0.2.1'),
          throwsA(isA<ReleaseToolException>()),
          reason: 'input "$broken" must not select a run silently',
        );
      }
    });
  });

  group('head-SHA capture (gh run view --json headSha output)', () {
    const headSha = '978dbc5b9ee19ff0aedfc03594a603013f0e034a';

    test('extracts the SHA from the JSON envelope', () {
      expect(sign.parseHeadSha('{"headSha":"$headSha"}'), headSha);
      expect(
        sign.parseHeadSha('{\n  "runNumber": 3,\n  "headSha": "$headSha"\n}\n'),
        headSha,
      );
    });

    test('tolerates the raw `-q .headSha` form too', () {
      expect(sign.parseHeadSha('$headSha\n'), headSha);
      expect(sign.parseHeadSha(' $headSha '), headSha);
    });

    test('submits a lowercase 40-char SHA usable as --target', () {
      expect(
        sign.parseHeadSha('{"headSha":"${headSha.toUpperCase()}"}'),
        headSha,
        reason:
            'gh case-wraps or uppercases nothing, but the parser is '
            'lenient — the emitted SHA must be plain lowercase hex for '
            '`gh release create --target`',
      );
    });

    test('malformed or missing output fails loudly', () {
      const broken = '{"headSha":"too-short"}';
      for (final bad in [
        '',
        '   ',
        'not json',
        '{}',
        '{"headSha":null}',
        broken,
      ]) {
        expect(
          () => sign.parseHeadSha(bad),
          throwsA(isA<ReleaseToolException>()),
          reason: 'input "$bad" must not yield a placeholder SHA',
        );
      }
    });
  });

  group('pubspec at the run commit (gh api contents envelope)', () {
    const pubspecSource = 'name: cycle_app\nversion: 0.2.1+3\n';
    final encoded = base64Encode(utf8.encode(pubspecSource));

    String envelope(String base64Content) =>
        '{"name": "pubspec.yaml", "path": "pubspec.yaml",'
        ' "content": "$base64Content", "encoding": "base64"}';

    test('decodes the default JSON envelope into the pubspec source', () {
      expect(sign.decodePubspecEnvelope(envelope(encoded)), pubspecSource);
    });

    test('tolerates GitHub\'s \\n-padded base64 payload', () {
      // GitHub pads file-content payloads with LF line breaks — re-encode
      // the valid payload in 20-char lines. In the JSON envelope those
      // newlines arrive as the two-character \\n escape sequence INSIDE the
      // JSON string, which jsonDecode turns back into real newlines before
      // the base64 decoder sees them. The fixture mirrors that escaped
      // shape exactly.
      final lines = <String>[];
      for (var i = 0; i < encoded.length; i += 20) {
        lines.add(
          encoded.substring(
            i,
            i + 20 > encoded.length ? encoded.length : i + 20,
          ),
        );
      }
      final escapedPadding = lines.join(r'\n');
      expect(
        sign.decodePubspecEnvelope(
          '{"name": "pubspec.yaml", "path": "pubspec.yaml",'
          ' "content": "$escapedPadding", "encoding": "base64"}',
        ),
        pubspecSource,
        reason: 'the decoder must ignore the line padding GitHub uses',
      );
    });

    test('the decoded source feeds the existing parsePubspecVersion', () {
      final pubspec = sign.parsePubspecVersion(
        sign.decodePubspecEnvelope(envelope(encoded)),
      );
      expect(pubspec, isNotNull);
      expect(pubspec!.name, '0.2.1');
      expect(pubspec.build, 3);
      // The versionCode scheme stays grounded in this N:
      expect(sign.expectedSplitVersionCode(pubspec.build, 2), 32);
    });

    test('garbage or missing content fails loudly', () {
      for (final bad in [
        envelope('%not-base64%'),
        '{"name": "pubspec.yaml", "encoding": "base64"}',
      ]) {
        expect(
          () => sign.decodePubspecEnvelope(bad),
          throwsA(isA<ReleaseToolException>()),
          reason: 'envelope "$bad" must not yield a fallback pubspec',
        );
      }
    });

    test('non-JSON output fails loudly', () {
      for (final bad in ['', '   ', 'not json', '[]']) {
        expect(
          () => sign.decodePubspecEnvelope(bad),
          throwsA(isA<ReleaseToolException>()),
        );
      }
    });
  });

  group('run-pubspec ↔ requested-version cross-check', () {
    test('a consistent run pubspec passes', () {
      expect(
        sign.runPubspecProblem(
          versionName: '0.2.1',
          runPubspec: const sign.PubspecVersion('0.2.1', 3),
        ),
        isNull,
      );
    });

    test('a mismatched run pubspec is a loud problem naming both versions, '
        'and states that the local checkout is not the source', () {
      final problem = sign.runPubspecProblem(
        versionName: '0.2.1',
        runPubspec: const sign.PubspecVersion('0.2.0', 2),
      );
      expect(problem, isNotNull);
      expect(problem, contains('0.2.0'));
      expect(problem, contains('0.2.1'));
      expect(problem, contains("run's pubspec.yaml"));
      expect(
        problem,
        contains('not consulted'),
        reason:
            'the local checkout may be on any branch — the message must '
            'make clear the run\'s own commit is the validated source',
      );
    });
  });

  group('build-tools resolution (apksigner ≤ 34 rule)', () {
    test('picks the newest directory that is at most 34.x.y', () {
      expect(
        sign.selectBuildToolsVersion(const [
          '35.0.0',
          '34.0.0',
          '33.0.1',
          '29.0.2',
        ]),
        '34.0.0',
        reason:
            'apksigner from build-tools ≥ 35 produces signatures the '
            'F-Droid buildserver cannot copy — the hard cap is 34',
      );
      expect(
        sign.selectBuildToolsVersion(const ['34.0.0', '35.0.0']),
        '34.0.0',
        reason: '34.0.0 stays eligible even with 35.0.0 installed',
      );
      expect(
        sign.selectBuildToolsVersion(const ['33.0.2', '33.0.1']),
        '33.0.2',
        reason: 'patch versions compare numerically',
      );
    });

    test('ignores non-version entries and handles patch-only ordering', () {
      expect(
        sign.selectBuildToolsVersion(const ['source.properties', '33.0.1']),
        '33.0.1',
      );
      expect(
        sign.selectBuildToolsVersion(const ['34.0.1', '34.0.0']),
        '34.0.1',
      );
    });

    test('fails loudly when only build-tools ≥ 35 exist', () {
      for (final listing in const [
        ['35.0.0'],
        ['36.0.1', '35.0.0'],
        <String>[],
        ['not-a-version'],
      ]) {
        expect(
          () => sign.selectBuildToolsVersion(listing),
          throwsA(
            isA<ReleaseToolException>().having(
              (error) => error.message,
              'message',
              contains('34'),
            ),
          ),
          reason: 'listing $listing offers no eligible build-tools',
        );
      }
    });
  });

  group('apksigner --print-certs parsing (lenient digest parser)', () {
    test('extracts the SHA-256 digest, not SHA-1/MD5', () {
      const output =
          '''
Signer #1 certificate DN: CN=Cycle App Release, O=Benedikt Burger, C=DE
Signer #1 certificate SHA-256 digest: $pinnedReleaseFingerprint
Signer #1 certificate SHA-1 digest: 6a1f2c4d5e6f708192a3b4c5d6e7f8091a2b3c4d
Signer #1 certificate MD5 digest: 6a1f2c4d5e6f708192a3b4c5d6e7f809
Signer #1 certificate: [Retrieved from store as "PKCS7"]
''';
      expect(
        sign.parseCertificateFingerprint(output),
        pinnedReleaseFingerprint,
      );
    });

    test('parses apksigner\'s colon-separated uppercase digest format', () {
      // Real apksigner prints one colon-separated PAIR per BYTE (32 bytes →
      // `AB:CD:EF:…`), not per nibble — the fixture mirrors that exact shape.
      final pinnedBytes = List.generate(32, (i) {
        final byteHex = pinnedReleaseFingerprint.substring(i * 2, i * 2 + 2);
        return byteHex.toUpperCase();
      }).join(':');
      expect(
        pinnedBytes,
        '0A:A5:74:98:04:B8:ED:9E:3C:20:7F:85:1B:59:02:77:5D:76:22:07:D6:0C:24:'
        '85:A2:6B:5D:75:EF:F5:35:5B',
      );
      expect(
        sign.parseCertificateFingerprint(
          'Signer #1 certificate SHA-256 digest: $pinnedBytes',
        ),
        pinnedReleaseFingerprint,
      );
    });

    test('returns null when no SHA-256 digest line exists', () {
      expect(
        sign.parseCertificateFingerprint(
          'Signer #1 certificate SHA-1 digest: deadbeef\n',
        ),
        isNull,
      );
      expect(sign.parseCertificateFingerprint(''), isNull);
    });

    test('fingerprint comparison is case/colon insensitive', () {
      expect(
        sign.fingerprintsMatch(
          pinnedReleaseFingerprint,
          pinnedReleaseFingerprint.toUpperCase(),
        ),
        isTrue,
      );
      expect(
        sign.fingerprintsMatch(
          pinnedReleaseFingerprint,
          'ff${pinnedReleaseFingerprint.substring(2)}',
        ),
        isFalse,
        reason: 'a different digest must fail the verification hard gate',
      );
    });
  });

  group('aapt dump badging parsing and version validation', () {
    const badgingOutput = '''
package: name='io.github.benediktburger.cycleapp' versionCode='32' versionName='0.2.1' platformBuildVersionName='14'
sdkVersion:'21'
targetSdkVersion:'34'
uses-permission: name='android.permission.POST_NOTIFICATIONS'
application-label:'Cycle App'
launchable-activity: name='io.github.benediktburger.cycleapp.MainActivity'  label='Cycle App'
''';

    test('extracts versionName and versionCode (lenient about order)', () {
      final info = sign.parseAaptBadging(badgingOutput);
      expect(info, isNotNull);
      expect(info!.versionName, '0.2.1');
      expect(info.versionCode, 32);
      expect(sign.parseAaptBadging("sdkVersion:'21'\n"), isNull);
    });

    test('split expectation is N*10 + abiCode from pubspec\'s +N', () {
      final version = sign.parsePubspecVersion(
        'name: cycle_app\nversion: 0.2.1+3\n',
      );
      expect(version, isNotNull);
      final build = version!.build;
      for (final abi in abiCodes.keys) {
        expect(
          sign.expectedSplitVersionCode(build, abiCodes[abi]!),
          build * 10 + abiCodes[abi]!,
          reason: 'scheme in android/app/build.gradle.kts',
        );
      }
      // The current pin: 0.2.1+3 → versionCodes 31/32/33.
      expect(sign.expectedSplitVersionCode(3, 1), 31);
      expect(sign.expectedSplitVersionCode(3, 2), 32);
      expect(sign.expectedSplitVersionCode(3, 3), 33);
    });

    test('a matching embedded version validates with no problem', () {
      for (final abi in abiCodes.keys) {
        final expected = sign.expectedSplitVersionCode(3, abiCodes[abi]!);
        expect(
          sign.apkVersionProblem(
            info: sign.ApkVersionInfo(
              versionName: '0.2.1',
              versionCode: expected,
            ),
            versionName: '0.2.1',
            expectedVersionCode: expected,
          ),
          isNull,
          reason: abi,
        );
      }
    });

    test('a wrong versionName fails loudly', () {
      final problem = sign.apkVersionProblem(
        info: const sign.ApkVersionInfo(versionName: '0.2.0', versionCode: 32),
        versionName: '0.2.1',
        expectedVersionCode: 32,
      );
      expect(problem, isNotNull);
      expect(problem, contains('0.2.0'));
      expect(problem, contains('0.2.1'));
    });

    test('a wrong versionCode fails loudly', () {
      final problem = sign.apkVersionProblem(
        info: const sign.ApkVersionInfo(versionName: '0.2.1', versionCode: 22),
        versionName: '0.2.1',
        expectedVersionCode: 32,
      );
      expect(problem, isNotNull);
      expect(problem, contains('22'));
      expect(problem, contains('32'));
    });
  });

  group('apksigner determinism sanity (double sign, byte-compare)', () {
    test('byte comparison distinguishes identical and differing outputs', () {
      expect(sign.bytesIdentical(<int>[1, 2, 3], <int>[1, 2, 3]), isTrue);
      expect(sign.bytesIdentical(<int>[1, 2, 3], <int>[1, 2, 4]), isFalse);
      expect(
        sign.bytesIdentical(<int>[1, 2], <int>[1, 2, 3]),
        isFalse,
        reason: 'a length difference is a difference',
      );
      expect(sign.bytesIdentical(<int>[], <int>[]), isTrue);
    });

    test('the failure message names the APK and remedies by re-signing', () {
      final message = sign.determinismFailureMessage(
        publishName: 'cycle-app-0.2.1-arm64-v8a.apk',
      );
      expect(message, contains('cycle-app-0.2.1-arm64-v8a.apk'));
      expect(message, contains('sign'));
    });

    test('the would-be apksigner sign command names keystore, alias and '
        'paths', () {
      expect(
        sign.formatSignCommand(
          apksigner: '/opt/android-sdk/build-tools/34.0.0/apksigner',
          ksPath: '/home/benedikt/keystores/cycleapp-release.jks',
          outPath: 'build/gh-release/cycle-app-0.2.1-arm64-v8a.apk',
          inputPath:
              'build/ci-artifacts/cycle-app-0.2.1-arm64-v8a-unsigned'
              '/app-arm64-v8a-release.apk',
        ),
        allOf(
          contains('/opt/android-sdk/build-tools/34.0.0/apksigner sign'),
          contains('--ks /home/benedikt/keystores/cycleapp-release.jks'),
          contains('--ks-key-alias ${sign.keystoreAlias}'),
          contains('--out build/gh-release/cycle-app-0.2.1-arm64-v8a.apk'),
          contains(sign.keystorePasswordEnvVar),
        ),
      );
    });
  });

  group('handoff-manifest write (sandboxed stage-10 side effect)', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('download_sign_manifest');
    });

    tearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    test('the manifest is written as the settled exact JSON under '
        'build/gh-release/source.json', () {
      const manifest = HandoffManifest(
        tag: 'v0.2.1',
        versionName: '0.2.1',
        versionCodeBase: 3,
        runId: 1234567890,
        headSha: '978dbc5b9ee19ff0aedfc03594a603013f0e034a',
      );
      sign.writeHandoffManifest(root: root, manifest: manifest);
      final file = File('${root.path}/$handoffManifestPath');
      expect(file.existsSync(), isTrue);
      expect(file.readAsStringSync(), '${encodeHandoffManifest(manifest)}\n');
      // The written file decodes back into the same manifest.
      expect(decodeHandoffManifest(file.readAsStringSync()), manifest);
    });

    test('the staged manifest composes the run-pubspec N and the resolved '
        'run identity', () {
      // The composition the run actually performs: the run's pubspec build
      // number becomes versionCodeBase, the resolved run id and head SHA
      // round-trip through the codec the publish helper will validate.
      final runPubspec = sign.parsePubspecVersion(
        'name: cycle_app\nversion: 0.2.1+3\n',
      )!;
      final manifest = HandoffManifest(
        tag: 'v0.2.1',
        versionName: '0.2.1',
        versionCodeBase: runPubspec.build,
        runId: 1234567890,
        headSha: '978dbc5b9ee19ff0aedfc03594a603013f0e034a',
      );
      expect(manifest.versionCodeBase, 3);
      expect(decodeHandoffManifest(encodeHandoffManifest(manifest)), manifest);
      expect(
        decodeHandoffManifest(encodeHandoffManifest(manifest)).tag,
        'v0.2.1',
      );
    });
  });

  group('publish-pointer next steps (the helper ENDS at the device-test '
      'break)', () {
    test('points at the publish script with its tag argument and names the '
        'optional dry-run rehearsal', () {
      final lines = sign.publishNextStepLines(tag: 'v0.2.1');
      final text = lines.join('\n');
      expect(text, contains('dart run tool/publish_release.dart v0.2.1'));
      expect(
        text,
        contains('dart run tool/publish_release.dart v0.2.1 --dry-run'),
      );
    });

    test('the device-test reminder and the adb lines precede the pointer '
        '(device work gated in front of the publish)', () {
      expect(deviceTestBeforePublishReminder(), contains('BEFORE'));
      expect(
        adbInstallNextSteps('0.2.1').first,
        'adb install -r build/gh-release/cycle-app-0.2.1-armeabi-v7a.apk',
      );
    });
  });
}
