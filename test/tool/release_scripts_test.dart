// Pure-logic tests for the release helpers (tool/release_names.dart,
// tool/download_and_sign.dart, tool/publish_release.dart): fixture JSON/CLI
// texts and temp-dir sandboxes only.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/download_and_sign.dart' as sign;
import '../../tool/publish_release.dart' as publish;
import '../../tool/release_names.dart';
import 'release_fixtures.dart'
    show
        badTagList,
        changelogGateFixture,
        changelogGateRunner,
        manifestJsonRaw,
        pinnedReleaseFingerprint,
        validHeadSha,
        validManifestJson;

/// Builds a synthetic signed-APK-like byte buffer: [prefix] (the ZIP entry
/// area stand-in), a signing block carrying [blockPairs] (each an arbitrary
/// id/payload), and a suffix ending in a minimal EOCD whose
/// central-directory offset field points at the block end — the shape
/// apksigner signs (entries → block → central directory → EOCD).
List<int> syntheticApk({
  required List<int> prefix,
  required List<(int, List<int>)> blockPairs,
  required List<int> centralDirectory,
}) {
  var pairsLen = 0;
  final pairs = <int>[];
  for (final (id, value) in blockPairs) {
    final pairLen = 4 + value.length;
    final pair = <int>[..._u64(pairLen), ..._u32(id), ...value];
    pairsLen += pair.length;
    pairs.addAll(pair);
  }
  // Layout: [u64 leading size][pairs][u64 trailing size][magic]; both size
  // fields count everything except their own field.
  final blockSize = pairsLen + 8 + 16;
  final block = <int>[
    ..._u64(blockSize),
    ...pairs,
    ..._u64(blockSize),
    ...'APK Sig Block 42'.codeUnits,
  ];
  final blockEnd = prefix.length + block.length;
  final eocd = <int>[
    ...[0x50, 0x4B, 0x05, 0x06],
    ..._u16(0),
    ..._u16(0),
    ..._u16(1),
    ..._u16(1),
    ..._u32(centralDirectory.length),
    ..._u32(blockEnd),
    ..._u16(0),
  ];
  return [...prefix, ...block, ...centralDirectory, ...eocd];
}

List<int> _u32(int value) => [
  value & 0xFF,
  (value >> 8) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 24) & 0xFF,
];

List<int> _u16(int value) => [value & 0xFF, (value >> 8) & 0xFF];

List<int> _u64(int value) => [
  ..._u32(value),
  ..._u32((value ~/ 0x100000000) & 0xFFFFFFFF),
];

/// The pinned fingerprint in apksigner's colon-separated uppercase shape —
/// the lenient normalizer must accept it.
const pinnedFingerprintColonUppercase =
    '0A:A5:74:98:04:B8:ED:9E:3C:20:7F:85:1B:59:02:77:5D:76:22:07:D6:0C:24:85'
    ':A2:6B:5D:75:EF:F5:35:5B';

/// The changelog text the summary embeds (untrimmed on purpose — the embed
/// site must trim it).
const whatsNewRaw =
    '  New: the diary gained a summary view.\nFixed: a crash.  ';
const whatsNewTrimmed =
    'New: the diary gained a summary view.\nFixed: a crash.';

String summaryBlock(String content) =>
    '<!-- release-summary -->\n'
    "## What's new\n"
    '\n'
    '$content\n'
    '<!-- /release-summary -->';

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
      for (final tag in badTagList) {
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

    test('accepts --default-changelog-only (the minor-release gate scope) '
        'and defaults to off without it', () {
      final options = sign.parseArguments([
        'v0.3.0',
        '--default-changelog-only',
      ]);
      expect(options.defaultChangelogOnly, isTrue);
      expect(sign.parseArguments(['v0.3.0']).defaultChangelogOnly, isFalse);
    });

    test('--default-changelog-only composes with --run-id in any order', () {
      final options = sign.parseArguments([
        '--run-id',
        '7',
        '--default-changelog-only',
        'v0.3.0',
      ]);
      expect(options.tag, 'v0.3.0');
      expect(options.runId, 7);
      expect(options.defaultChangelogOnly, isTrue);
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
    test('extracts the SHA from the JSON envelope', () {
      expect(sign.parseHeadSha('{"headSha":"$validHeadSha"}'), validHeadSha);
      expect(
        sign.parseHeadSha(
          '{\n  "runNumber": 3,\n  "headSha": "$validHeadSha"\n}\n',
        ),
        validHeadSha,
      );
    });

    test('tolerates the raw `-q .headSha` form too', () {
      expect(sign.parseHeadSha('$validHeadSha\n'), validHeadSha);
      expect(sign.parseHeadSha(' $validHeadSha '), validHeadSha);
    });

    test('submits a lowercase 40-char SHA usable as --target', () {
      expect(
        sign.parseHeadSha('{"headSha":"${validHeadSha.toUpperCase()}"}'),
        validHeadSha,
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

  group('keystore password sources (env vars, gitignored key.properties)', () {
    test('parseKeyProperties reads the three known keys', () {
      final parsed = sign.parseKeyProperties(
        'storePassword=store\n'
        'keyPassword=key\n'
        'keyAlias=alias\n',
      );
      expect(parsed, isNotNull);
      expect(parsed!.storePassword, 'store');
      expect(parsed.keyPassword, 'key');
      expect(parsed.keyAlias, 'alias');
    });

    test('comments, blank lines and whitespace are tolerated', () {
      final parsed = sign.parseKeyProperties(
        '\n'
        '# keystore config\n'
        '  # indented comment\n'
        '! another comment\n'
        'storePassword = store-pw\n'
        '\tkeyPassword : key-pw\n'
        'unknownKey=ignored\n',
      );
      expect(parsed, isNotNull);
      expect(parsed!.storePassword, 'store-pw');
      expect(parsed.keyPassword, 'key-pw');
      expect(parsed.keyAlias, isNull);
    });

    test('the first separator splits the key; later separators stay in '
        'the value', () {
      final parsed = sign.parseKeyProperties(
        'storePassword=pw;with=equals:and:colons\n',
      );
      expect(parsed!.storePassword, 'pw;with=equals:and:colons');
    });

    test('values may carry structural characters that properties files '
        'do not escape here', () {
      final parsed = sign.parseKeyProperties(
        'storePassword=pw:p1=;#not-comment\n',
      );
      expect(parsed!.storePassword, 'pw:p1=;#not-comment');
    });

    test('trailing whitespace of a value is kept (java.util.Properties '
        'semantics, so Gradle and apksigner see the same bytes)', () {
      final parsed = sign.parseKeyProperties('storePassword=pw \n');
      expect(parsed!.storePassword, 'pw ');
    });

    test('empty or missing values count as absent, no keys → null', () {
      expect(sign.parseKeyProperties('storePassword=\n'), isNull);
      expect(sign.parseKeyProperties('no-separator-line\n# c\n'), isNull);
      expect(sign.parseKeyProperties(''), isNull);
      expect(
        sign.parseKeyProperties('keyPassword=k\n'),
        isNotNull,
        reason: 'keyPassword-only input still parses',
      );
    });
  });

  group('resolveKeystorePasswords (precedence + loud fallback)', () {
    test('the env var wins over key.properties', () {
      final resolved = sign.resolveKeystorePasswords(
        environmentStorePassword: 'env-pw',
        keyProperties: const sign.KeyPropertiesPasswords(
          storePassword: 'props-pw',
          keyPassword: 'props-key',
          keyAlias: 'alias',
        ),
      );
      expect(resolved.storePassword, 'env-pw');
      expect(
        resolved.keyPassword,
        isNull,
        reason: 'the env source carries no per-key password',
      );
      expect(resolved.source, contains(sign.keystorePasswordEnvVar));
    });

    test('an empty env var falls through to key.properties', () {
      final resolved = sign.resolveKeystorePasswords(
        environmentStorePassword: '',
        keyProperties: const sign.KeyPropertiesPasswords(
          storePassword: 'props-pw',
        ),
      );
      expect(resolved.storePassword, 'props-pw');
      expect(resolved.source, contains(sign.keyPropertiesPath));
    });

    test('key.properties supplies store + optional key password + alias', () {
      final resolved = sign.resolveKeystorePasswords(
        environmentStorePassword: null,
        keyProperties: const sign.KeyPropertiesPasswords(
          storePassword: 'store',
          keyPassword: 'key',
          keyAlias: 'something-else',
        ),
      );
      expect(resolved.storePassword, 'store');
      expect(resolved.keyPassword, 'key');
      expect(resolved.keyAlias, 'something-else');
    });

    test('neither source throws loudly, naming both remedies and the '
        'prompting impossibility', () {
      expect(
        () => sign.resolveKeystorePasswords(
          environmentStorePassword: null,
          keyProperties: null,
        ),
        throwsA(
          isA<ReleaseToolException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains(sign.keystorePasswordEnvVar),
              contains(sign.keyPropertiesPath),
              contains('cannot prompt interactively'),
            ),
          ),
        ),
      );
      expect(
        () => sign.resolveKeystorePasswords(
          environmentStorePassword: null,
          keyProperties: const sign.KeyPropertiesPasswords(
            keyPassword: 'only-key',
          ),
        ),
        throwsA(isA<ReleaseToolException>()),
        reason: 'a key password without a store password is not enough',
      );
    });
  });

  group(
    'apksigner determinism sanity (double sign, outside-block compare)',
    () {
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

      test('the failure message names the APK and the outside-block scope', () {
        final message = sign.determinismFailureMessage(
          publishName: 'cycle-app-0.2.1-arm64-v8a.apk',
        );
        expect(message, contains('cycle-app-0.2.1-arm64-v8a.apk'));
        expect(message, contains('sign'));
        expect(message, contains('OUTSIDE the signing block'));
      });

      test('the would-be apksigner sign command names keystore, alias, both '
          'password forms and paths', () {
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
            contains('env:${sign.keystorePasswordEnvVar}'),
            contains('env:${sign.keyPasswordEnvVar}'),
          ),
        );
      });
    },
  );

  group('APK signing block extent + the outside-block determinism compare', () {
    final prefix = List.generate(48, (i) => 0x20 + (i % 60));
    final centralDirectory = List.generate(40, (i) => i);
    final base = syntheticApk(
      prefix: prefix,
      blockPairs: [(0x7109871a, List.generate(30, (i) => i))],
      centralDirectory: centralDirectory,
    );

    test('a structurally consistent synthetic suit is located and matches '
        'itself', () {
      final extent = sign.signingBlockExtent(base);
      expect(extent, isNotNull);
      expect(
        extent!.$1,
        prefix.length,
        reason: 'the block starts right after the ZIP entry area',
      );
      expect(extent.$2, base.length - centralDirectory.length - 22);
      expect(sign.outputsMatchOutsideSigningBlocks(base, base), isTrue);
    });

    test('differences inside the block are tolerated (the ECDSA '
        'randomization the release key makes unavoidable)', () {
      final reSigned = syntheticApk(
        prefix: prefix,
        blockPairs: [(0x7109871a, List.generate(30, (i) => i))],
        centralDirectory: centralDirectory,
      );
      // Flip a byte inside the v2 pair payload AND change its length by one
      // byte — the DER leading-zero wobble of concrete ECDSA signatures. The
      // second file gets its own (shifted) central directory.
      final shifted = syntheticApk(
        prefix: prefix,
        blockPairs: [
          (0x7109871a, [...List.generate(30, (i) => i ^ 0xFF), 7]),
        ],
        centralDirectory: centralDirectory,
      );
      expect(sign.outputsMatchOutsideSigningBlocks(base, reSigned), isTrue);
      expect(
        sign.outputsMatchOutsideSigningBlocks(base, shifted),
        isTrue,
        reason: 'block-length shifts move only the EOCD CD-offset field',
      );
      // sanity: whole-file compare WOULD fail for the shifted length
      expect(shifted.length, isNot(base.length));
    });

    test('any difference in the ZIP entry area fails (the actual '
        'nondeterminism guard)', () {
      final tamperedPrefix = [...prefix];
      tamperedPrefix[7] ^= 1;
      final other = syntheticApk(
        prefix: tamperedPrefix,
        blockPairs: [(0x7109871a, List.generate(30, (i) => i))],
        centralDirectory: centralDirectory,
      );
      expect(sign.outputsMatchOutsideSigningBlocks(base, other), isFalse);
    });

    test('any difference in the central directory fails', () {
      final tamperedCd = [...centralDirectory];
      tamperedCd[3] ^= 0x10;
      final other = syntheticApk(
        prefix: prefix,
        blockPairs: [(0x7109871a, List.generate(30, (i) => i))],
        centralDirectory: tamperedCd,
      );
      expect(sign.outputsMatchOutsideSigningBlocks(base, other), isFalse);
    });

    test('a different entry-area length fails (different inputs)', () {
      final other = syntheticApk(
        prefix: [...prefix, 1],
        blockPairs: [(0x7109871a, List.generate(30, (i) => i))],
        centralDirectory: centralDirectory,
      );
      expect(sign.outputsMatchOutsideSigningBlocks(base, other), isFalse);
    });

    test('a missing or inconsistent block is reported as incomparable '
        '(null), not as a match', () {
      expect(sign.signingBlockExtent(prefix), isNull);
      final noBlock = [
        ...prefix,
        ...centralDirectory,
        ...base.sublist(base.length - 22),
      ];
      expect(sign.outputsMatchOutsideSigningBlocks(base, noBlock), isNull);
      // A block whose two size fields disagree is not a block.
      final corrupt = [...base];
      final blockStart = sign.signingBlockExtent(corrupt)!.$1;
      corrupt[blockStart] ^= 0xFF; // break the leading size field
      expect(sign.signingBlockExtent(corrupt), isNull);
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
        headSha: validHeadSha,
        defaultChangelogOnly: false,
      );
      sign.writeHandoffManifest(root: root, manifest: manifest);
      final file = File('${root.path}/$handoffManifestPath');
      expect(file.existsSync(), isTrue);
      expect(file.readAsStringSync(), '${encodeHandoffManifest(manifest)}\n');
      expect(
        file.readAsStringSync(),
        contains('"defaultChangelogOnly":false'),
        reason: 'the written file carries the gate-scope decision',
      );
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
        headSha: validHeadSha,
        defaultChangelogOnly: true,
      );
      expect(manifest.versionCodeBase, 3);
      expect(decodeHandoffManifest(encodeHandoffManifest(manifest)), manifest);
      expect(
        decodeHandoffManifest(encodeHandoffManifest(manifest)).tag,
        'v0.2.1',
      );
      expect(
        decodeHandoffManifest(
          encodeHandoffManifest(manifest),
        ).defaultChangelogOnly,
        isTrue,
        reason: 'the minor-release decision round-trips through the codec',
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
  });

  group('publish names and staged paths', () {
    const version = '0.2.1';

    test('publish names are the attached release asset names', () {
      expect(
        publishApkName(versionName: version, abi: 'arm64-v8a'),
        'cycle-app-0.2.1-arm64-v8a.apk',
      );
      expect(publishApkNames(version), [
        'cycle-app-0.2.1-armeabi-v7a.apk',
        'cycle-app-0.2.1-arm64-v8a.apk',
        'cycle-app-0.2.1-x86_64.apk',
      ]);
    });

    test('staged publish paths live under build/gh-release (gitignored)', () {
      expect(stagedPublishPaths(version), [
        '$ghReleaseStagingDir/cycle-app-0.2.1-armeabi-v7a.apk',
        '$ghReleaseStagingDir/cycle-app-0.2.1-arm64-v8a.apk',
        '$ghReleaseStagingDir/cycle-app-0.2.1-x86_64.apk',
      ]);
    });
  });

  group('tag and branch helpers', () {
    test('valid release tags pass the regex', () {
      for (final tag in ['v0.2.1', 'v1.2.3', 'v10.11.12']) {
        expect(isValidReleaseTag(tag), isTrue, reason: tag);
      }
    });

    test('malformed tags fail the regex', () {
      for (final tag in badTagList) {
        expect(isValidReleaseTag(tag), isFalse, reason: 'tag "$tag"');
      }
    });

    test('tagToVersion strips the v prefix (validated tags only)', () {
      expect(tagToVersion('v0.2.1'), '0.2.1');
      expect(tagToVersion('v10.11.12'), '10.11.12');
    });

    test('the release branch derivation follows the push convention', () {
      expect(releaseBranchForTag('v0.2.1'), 'release/v0.2.1');
      expect(releaseBranchForTag('v10.11.12'), 'release/v10.11.12');
    });
  });

  group('requireStagedApks (temp-dir sandbox)', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('release_names_staging');
    });

    tearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    File stagedFile(int index) =>
        File('${root.path}/${stagedPublishPaths('0.2.1')[index]}');

    test('staged files under publish names pass in attach order; the stale '
        'leftover bytes are what a rerun overwrote', () async {
      // A leftover from a previous run carries different bytes at index 0;
      // apksigner --out rewrites every staged path.
      await stagedFile(0).parent.create(recursive: true);
      await stagedFile(0).writeAsBytes([9, 9, 9, 9]);
      final signedBytes = [
        [1, 2, 3],
        [4, 5],
        [6],
      ];
      for (var i = 0; i < signedBytes.length; i++) {
        await stagedFile(i).writeAsBytes(signedBytes[i]);
      }

      final printed = <String>[];
      final names = requireStagedApks(
        root: root,
        versionName: '0.2.1',
        sink: printed.add,
      );
      expect(names, publishApkNames('0.2.1'));
      expect(printed, [
        for (final path in stagedPublishPaths('0.2.1')) 'staged APK: $path',
      ], reason: 'the staged lines go through the injected sink, not past it');
      for (var i = 0; i < signedBytes.length; i++) {
        expect(
          stagedFile(i).readAsBytesSync(),
          signedBytes[i],
          reason:
              '${stagedFile(i).path} must hold the fresh signed bytes '
              '(the stale leftover lost)',
        );
      }
    });

    test('a missing or empty staged APK fails loudly by name', () async {
      await stagedFile(0).create(recursive: true);
      await stagedFile(2).writeAsBytes([6]);
      expect(
        () => requireStagedApks(root: root, versionName: '0.2.1'),
        throwsA(
          isA<ReleaseToolException>().having(
            (error) => error.message,
            'message',
            contains('cycle-app-0.2.1-arm64-v8a.apk'),
          ),
        ),
      );

      await stagedFile(1).create(recursive: true);
      expect(
        () => requireStagedApks(root: root, versionName: '0.2.1'),
        throwsA(
          isA<ReleaseToolException>().having(
            (error) => error.message,
            'message',
            contains('exists but is empty'),
          ),
        ),
      );
    });
  });

  group('adb install next steps + device-test reminder', () {
    test('the exact adb install -r command per published ABI, in attach '
        'order', () {
      expect(adbInstallNextSteps('0.2.1'), [
        'adb install -r build/gh-release/cycle-app-0.2.1-armeabi-v7a.apk',
        'adb install -r build/gh-release/cycle-app-0.2.1-arm64-v8a.apk',
        'adb install -r build/gh-release/cycle-app-0.2.1-x86_64.apk',
      ]);
    });

    test('the device-default pair (armeabi-v7a, arm64-v8a) is listed first '
        'and present for any version', () {
      final lines = adbInstallNextSteps('10.11.12');
      expect(lines[0], contains('-armeabi-v7a.apk'));
      expect(lines[1], contains('-arm64-v8a.apk'));
      expect(
        adbInstallCommand(versionName: '10.11.12', abi: 'arm64-v8a'),
        'adb install -r build/gh-release/cycle-app-10.11.12-arm64-v8a.apk',
      );
    });

    test('the reminder puts the device work BEFORE the publish', () {
      expect(
        deviceTestBeforePublishReminder(),
        contains('BEFORE'),
        reason:
            'the device install + DB-migration test against the previously '
            'installed release precedes gh release create',
      );
    });
  });

  group('post-release info block', () {
    test('carries the release URL, one verification URL per versionCode, '
        'and the upgrade-test reminder', () {
      final lines = postReleaseInfoLines('v0.2.1', [31, 32, 33]);
      final text = lines.join('\n');
      expect(
        text,
        contains(
          'Release assets attached: '
          'https://github.com/BenediktBurger/cycle-app/releases/tag/v0.2.1',
        ),
      );
      expect(
        RegExp(
          r'https://verification\.f-droid\.org/'
          r'io\.github\.benediktburger\.cycleapp_\d+\.apk\.json',
        ).allMatches(text).length,
        3,
      );
      expect(text, contains('Upgrade test reminder'));
    });

    test('ends with the exact staged adb install lines, device pair first '
        'and x86_64 last', () {
      final lines = postReleaseInfoLines('v0.2.1', [31, 32, 33]);
      expect(lines.sublist(lines.length - 3), adbInstallNextSteps('0.2.1'));
    });
  });

  group('handoff-manifest codec (build/gh-release/source.json)', () {
    const manifest = HandoffManifest(
      tag: 'v0.2.1',
      versionName: '0.2.1',
      versionCodeBase: 3,
      runId: 1234567890,
      headSha: validHeadSha,
      defaultChangelogOnly: false,
    );

    test('encode produces the settled exact shape with the declared field '
        'order, defaultChangelogOnly last', () {
      expect(
        encodeHandoffManifest(manifest),
        '{"tag":"v0.2.1","versionName":"0.2.1","versionCodeBase":3,'
        '"runId":1234567890,"headSha":"$validHeadSha",'
        '"defaultChangelogOnly":false}',
      );
    });

    test('encode → decode round trip preserves every field, '
        'defaultChangelogOnly included', () {
      expect(decodeHandoffManifest(encodeHandoffManifest(manifest)), manifest);
      const skipManifest = HandoffManifest(
        tag: 'v0.2.1',
        versionName: '0.2.1',
        versionCodeBase: 3,
        runId: 1234567890,
        headSha: validHeadSha,
        defaultChangelogOnly: true,
      );
      expect(
        decodeHandoffManifest(encodeHandoffManifest(skipManifest)),
        skipManifest,
      );
    });

    test('a well-formed manifest decodes to the same values', () {
      final decoded = decodeHandoffManifest(validManifestJson());
      expect(decoded.tag, 'v0.2.1');
      expect(decoded.versionName, '0.2.1');
      expect(decoded.versionCodeBase, 3);
      expect(decoded.runId, 1234567890);
      expect(decoded.headSha, validHeadSha);
      expect(decoded.defaultChangelogOnly, isFalse);
    });

    test('non-JSON or non-object manifests fail loudly', () {
      for (final bad in ['', 'not json', '[]', '"v0.2.1"']) {
        expect(
          () => decodeHandoffManifest(bad),
          throwsA(isA<ReleaseToolException>()),
          reason: 'input "$bad" must not decode into a manifest',
        );
      }
    });

    test('a missing field fails loudly (each of the six dropped once)', () {
      final variants = <String>[
        manifestJsonRaw(
          versionName: '"0.2.1"',
          versionCodeBase: '3',
          runId: '1',
          headSha: '"$validHeadSha"',
          defaultChangelogOnly: 'false',
        ),
        manifestJsonRaw(
          tag: '"v0.2.1"',
          versionCodeBase: '3',
          runId: '1',
          headSha: '"$validHeadSha"',
          defaultChangelogOnly: 'false',
        ),
        manifestJsonRaw(
          tag: '"v0.2.1"',
          versionName: '"0.2.1"',
          runId: '1',
          headSha: '"$validHeadSha"',
          defaultChangelogOnly: 'false',
        ),
        manifestJsonRaw(
          tag: '"v0.2.1"',
          versionName: '"0.2.1"',
          versionCodeBase: '3',
          headSha: '"$validHeadSha"',
          defaultChangelogOnly: 'false',
        ),
        manifestJsonRaw(
          tag: '"v0.2.1"',
          versionName: '"0.2.1"',
          versionCodeBase: '3',
          runId: '1',
          defaultChangelogOnly: 'false',
        ),
        manifestJsonRaw(
          tag: '"v0.2.1"',
          versionName: '"0.2.1"',
          versionCodeBase: '3',
          runId: '1',
          headSha: '"$validHeadSha"',
        ),
      ];
      for (final variant in variants) {
        expect(
          () => decodeHandoffManifest(variant),
          throwsA(
            isA<ReleaseToolException>().having(
              (error) => error.message,
              'message',
              contains('missing'),
            ),
          ),
          reason: 'variant lacks a required field: $variant',
        );
      }
    });

    test('a wrong-typed field fails loudly', () {
      final variants = <String>[
        manifestJsonRaw(
          tag: '123',
          versionCodeBase: '3',
          runId: '1',
          headSha: '"$validHeadSha"',
          defaultChangelogOnly: 'false',
        ),
        manifestJsonRaw(
          tag: '"v0.2.1"',
          versionName: 'null',
          versionCodeBase: '3',
          runId: '1',
          headSha: '"$validHeadSha"',
          defaultChangelogOnly: 'false',
        ),
        manifestJsonRaw(
          tag: '"v0.2.1"',
          versionName: '"0.2.1"',
          versionCodeBase: '"3"',
          runId: '1',
          headSha: '"$validHeadSha"',
          defaultChangelogOnly: 'false',
        ),
        manifestJsonRaw(
          tag: '"v0.2.1"',
          versionName: '"0.2.1"',
          versionCodeBase: '3',
          runId: '"42"',
          headSha: '"$validHeadSha"',
          defaultChangelogOnly: 'false',
        ),
        manifestJsonRaw(
          tag: '"v0.2.1"',
          versionName: '"0.2.1"',
          versionCodeBase: '3',
          runId: '1',
          headSha: '999',
          defaultChangelogOnly: 'false',
        ),
        manifestJsonRaw(
          tag: '"v0.2.1"',
          versionName: '"0.2.1"',
          versionCodeBase: '3',
          runId: '1',
          headSha: '"$validHeadSha"',
          defaultChangelogOnly: '"false"',
        ),
      ];
      for (final variant in variants) {
        expect(
          () => decodeHandoffManifest(variant),
          throwsA(
            isA<ReleaseToolException>().having(
              (error) => error.message,
              'message',
              contains('must be'),
            ),
          ),
          reason: 'variant carries a mistyped field: $variant',
        );
      }
    });

    test('a tag violating the vX.Y.Z regex fails loudly', () {
      final variants = <String>[
        manifestJsonRaw(
          tag: '"0.2.1"',
          versionName: '"0.2.1"',
          versionCodeBase: '3',
          runId: '1',
          headSha: '"$validHeadSha"',
        ),
        manifestJsonRaw(
          tag: '"v0.2"',
          versionName: '"0.2"',
          versionCodeBase: '3',
          runId: '1',
          headSha: '"$validHeadSha"',
        ),
        manifestJsonRaw(
          tag: '"v1.2.3-rc1"',
          versionName: '"1.2.3"',
          versionCodeBase: '3',
          runId: '1',
          headSha: '"$validHeadSha"',
        ),
      ];
      for (final variant in variants) {
        expect(
          () => decodeHandoffManifest(variant),
          throwsA(isA<ReleaseToolException>()),
          reason: 'variant has a non-regex tag: $variant',
        );
      }
    });

    test('tag ↔ versionName disagreement fails loudly', () {
      expect(
        () => decodeHandoffManifest(
          manifestJsonRaw(
            tag: '"v0.2.1"',
            versionName: '"0.2.0"',
            versionCodeBase: '3',
            runId: '1',
            headSha: '"$validHeadSha"',
          ),
        ),
        throwsA(isA<ReleaseToolException>()),
      );
    });

    test('the headSha must be lowercase 40-hex', () {
      final variants = <String>[
        manifestJsonRaw(
          tag: '"v0.2.1"',
          versionName: '"0.2.1"',
          versionCodeBase: '3',
          runId: '1',
          headSha: '"${validHeadSha.toUpperCase()}"',
        ),
        manifestJsonRaw(
          tag: '"v0.2.1"',
          versionName: '"0.2.1"',
          versionCodeBase: '3',
          runId: '1',
          headSha: '"${validHeadSha.substring(0, 39)}"',
        ),
        manifestJsonRaw(
          tag: '"v0.2.1"',
          versionName: '"0.2.1"',
          versionCodeBase: '3',
          runId: '1',
          headSha: '"zzzzdbc5b9ee19ff0aedfc03594a603013f0e034a"',
        ),
      ];
      for (final variant in variants) {
        expect(
          () => decodeHandoffManifest(variant),
          throwsA(isA<ReleaseToolException>()),
          reason: 'variant headSha is not lowercase 40-hex: $variant',
        );
      }
    });

    test('versionCodeBase must be a positive int', () {
      for (final base in ['0', '-3']) {
        expect(
          () => decodeHandoffManifest(
            manifestJsonRaw(
              tag: '"v0.2.1"',
              versionName: '"0.2.1"',
              versionCodeBase: base,
              runId: '1',
              headSha: '"$validHeadSha"',
            ),
          ),
          throwsA(isA<ReleaseToolException>()),
          reason: 'versionCodeBase $base is not positive',
        );
      }
    });
  });

  group('pin-file reading (fingerprint line for both helpers)', () {
    test('the committed pin file parses to the pinned fingerprint', () {
      final pinFile = File(pinFilePath);
      expect(pinFile.existsSync(), isTrue);
      expect(
        parsePinFile(pinFile.readAsStringSync()),
        pinnedReleaseFingerprint,
      );
    });

    test('comments and blanks are skipped; normalization is lenient', () {
      const content =
          '# comment\n\n'
          '$pinnedReleaseFingerprint\n';
      expect(parsePinFile(content), pinnedReleaseFingerprint);
    });

    test('nothing plausible yields null', () {
      expect(parsePinFile('# only a comment\n'), isNull);
      expect(parsePinFile(''), isNull);
      expect(parsePinFile('tooshort\n'), isNull);
    });

    test('normalize strips colons, whitespace and case', () {
      expect(
        normalizeFingerprint(
          '0A:A5:74:98:04:B8:ED:9E:3C:20:7F:85:1B:59:02:77:5D:76:22:07:D6:0C:'
          '24:85:A2:6B:5D:75:EF:F5:35:5B',
        ),
        pinnedReleaseFingerprint,
      );
      expect(isFingerprintHex(pinnedReleaseFingerprint), isTrue);
      expect(isFingerprintHex('0aa57498'), isFalse);
    });
  });

  group('F-Droid changelog files gate (both helpers)', () {
    const authoringName = '0.2.5.txt';
    const linkNames = ['71.txt', '72.txt', '73.txt'];

    /// default.txt is committed as a regular-file blob (mode 100644), not a
    /// symlink: every complete fixture carries it next to the authoring
    /// file, outside the [linkNames] symlink space.
    const regularChangelogNames = {'default.txt'};

    /// All changelog names one complete locale carries in the fixtures:
    /// the per-ABI symlink names plus the regular default file.
    const allChangelogNames = [...linkNames, 'default.txt'];

    /// Feeds the gate tests from the shared Git-tree/blob fixture in
    /// release_fixtures.dart with this group's file set.
    ({String tree, Map<String, String> blobs}) fixture({
      required Map<String, Map<String, String>> targets,
      String authoringMode = '100644',
      Set<String> regularNames = const {},
      bool truncated = false,
      Map<String, Map<String, String>> regularFileContents = const {},
    }) => changelogGateFixture(
      targets: targets,
      authoringName: authoringName,
      linkNames: [...linkNames, ...regularChangelogNames, ...regularNames],
      authoringMode: authoringMode,
      regularNames: {...regularChangelogNames, ...regularNames},
      truncated: truncated,
      regularFileContents: regularFileContents,
    );

    /// Per-locale targets for a complete set: every name points at the
    /// authoring filename (the value is meaningless for regular-file blobs).
    Map<String, String> completeTargets() => {
      for (final name in allChangelogNames) name: authoringName,
    };

    GhApiRunner gateRunner(({String tree, Map<String, String> blobs}) data) =>
        changelogGateRunner(data);

    /// A tree stripped to the default-changelog-only expectation: per
    /// locale, ONLY a regular-file `default.txt` blob — the authoring file
    /// and the per-ABI names are absent, as a minor release skips them.
    ({String tree, Map<String, String> blobs}) skipFixture({
      Map<String, String> perLocale = const {'default.txt': 'fallback text'},
      Map<String, Map<String, String>> regularFileContents = const {},
    }) => changelogGateFixture(
      targets: {
        for (final locale in ['de-DE', 'en-US']) locale: perLocale,
      },
      authoringName: authoringName,
      linkNames: const ['default.txt'],
      includeAuthoringEntry: false,
      regularNames: const {'default.txt'},
      regularFileContents: regularFileContents,
    );

    test('expected file set (full release): authoring file, three per-ABI '
        'links, default', () {
      expect(
        expectedChangelogFiles(
          versionName: '0.2.5',
          versionCodeBase: 7,
          defaultChangelogOnly: false,
        ),
        ['0.2.5.txt', '71.txt', '72.txt', '73.txt', 'default.txt'],
      );
    });

    test('expected file set (default-changelog-only): exactly the fallback '
        'file, no authoring or per-ABI names', () {
      expect(
        expectedChangelogFiles(
          versionName: '0.2.5',
          versionCodeBase: 7,
          defaultChangelogOnly: true,
        ),
        ['default.txt'],
      );
    });

    test('recursive tree JSON decodes to path/mode/type/sha entries', () {
      final entries = decodeGhTree(
        '{"tree":['
        '{"path":"fastlane/metadata/android/de-DE","mode":"040000",'
        '"type":"tree","sha":"tree-de"},'
        '{"path":"fastlane/metadata/android/de-DE/changelogs/71.txt",'
        '"mode":"120000","type":"blob","sha":"blob-71"}'
        '],"truncated":false}',
      );
      expect(entries.map((entry) => entry.path), [
        'fastlane/metadata/android/de-DE',
        'fastlane/metadata/android/de-DE/changelogs/71.txt',
      ]);
      expect(entries.last.mode, '120000');
      expect(entries.first.type, 'tree');
      expect(entries.last.sha, 'blob-71');
    });

    test('tree decode is loud on a non-object answer, a missing tree array, '
        'mistyped fields, and a truncated answer', () {
      for (final badAnswer in [
        '[{"path":"p"}]',
        '{"truncated":false}',
        '{"tree":[{"path":4}]}',
        '{"tree":[{"path":"p","mode":"120000","type":"blob"}]}',
        '{"tree":[],"truncated":true}',
      ]) {
        expect(
          () => decodeGhTree(badAnswer),
          throwsA(isA<ReleaseToolException>()),
          reason: 'tree answer "$badAnswer" must abort the verify',
        );
      }
    });

    test('a blob answer decodes to the resolved symlink target — embedded '
        'base64 line wraps included', () {
      final encoded = base64Encode(utf8.encode(authoringName));
      final wrapped = '${encoded.substring(0, 3)}\\n${encoded.substring(3)}';
      expect(
        decodeGhBlobText('{"content":"$wrapped","encoding":"base64"}'),
        authoringName,
      );
    });

    test('a blob decode is loud on non-object answers and missing content', () {
      for (final badAnswer in ['[]', '{"encoding":"base64"}']) {
        expect(
          () => decodeGhBlobText(badAnswer),
          throwsA(isA<ReleaseToolException>()),
          reason: 'blob answer "$badAnswer" must abort the verify',
        );
      }
    });

    test('a complete set — per-ABI symlinks plus a regular default.txt '
        'blob — passes with an ok line per locale', () async {
      final lines = <String>[];
      await requireChangelogFiles(
        versionName: '0.2.5',
        versionCodeBase: 7,
        defaultChangelogOnly: false,
        headSha: validHeadSha,
        ghApiRunner: gateRunner(
          fixture(
            targets: {
              for (final locale in ['de-DE', 'en-US'])
                locale: completeTargets(),
            },
          ),
        ),
        sink: lines.add,
      );
      expect(lines.length, 2, reason: lines.join('\n'));
      expect(lines.join('\n'), contains('de-DE ok'));
      expect(lines.join('\n'), contains('en-US ok'));
    });

    test(
      'missing links fail loudly and name every gap plus the fix path',
      () async {
        Object? caught;
        try {
          await requireChangelogFiles(
            versionName: '0.2.5',
            versionCodeBase: 7,
            defaultChangelogOnly: false,
            headSha: validHeadSha,
            ghApiRunner: gateRunner(
              fixture(targets: {'de-DE': {}, 'en-US': {}}),
            ),
            sink: (_) {},
          );
        } on ReleaseToolException catch (error) {
          caught = error;
        }
        expect(caught, isNotNull);
        final message = '$caught';
        expect(
          message,
          contains('F-Droid changelog files for 0.2.5'),
          reason: message,
        );
        expect(
          message,
          contains('de-DE: missing 71.txt, 72.txt, 73.txt, default.txt'),
          reason: message,
        );
        expect(
          message,
          contains('en-US: missing 71.txt, 72.txt, 73.txt, default.txt'),
          reason: message,
        );
        expect(
          message,
          contains('fdroid_changelog_links.dart'),
          reason: message,
        );
        expect(message, contains('--run-id re-attach'), reason: message);
      },
    );

    test('a regular file in place of a per-ABI symlink fails loudly naming '
        'the locale and the name', () async {
      Object? caught;
      try {
        await requireChangelogFiles(
          versionName: '0.2.5',
          versionCodeBase: 7,
          defaultChangelogOnly: false,
          headSha: validHeadSha,
          ghApiRunner: gateRunner(
            fixture(
              targets: {
                for (final locale in ['de-DE', 'en-US'])
                  locale: completeTargets(),
              },
              regularNames: const {'72.txt'},
            ),
          ),
          sink: (_) {},
        );
      } on ReleaseToolException catch (error) {
        caught = error;
      }
      expect(caught, isNotNull, reason: 'a regular 72.txt must fail the gate');
      final message = '$caught';
      expect(
        message,
        contains('de-DE: 72.txt is a regular file'),
        reason: message,
      );
      expect(message, contains('remove or rename it by hand'), reason: message);
      expect(message, contains('fdroid_changelog_links.dart'), reason: message);
    });

    test('a symlink to a stale or diverged versionName fails loudly naming '
        'the actual target', () async {
      Object? caught;
      try {
        await requireChangelogFiles(
          versionName: '0.2.5',
          versionCodeBase: 7,
          defaultChangelogOnly: false,
          headSha: validHeadSha,
          ghApiRunner: gateRunner(
            fixture(
              targets: {
                for (final locale in ['de-DE', 'en-US'])
                  locale: {...completeTargets(), '71.txt': '0.2.4.txt'},
              },
            ),
          ),
          sink: (_) {},
        );
      } on ReleaseToolException catch (error) {
        caught = error;
      }
      expect(caught, isNotNull, reason: 'a stale target must fail the gate');
      final message = '$caught';
      expect(
        message,
        contains(
          'de-DE: 71.txt is a symlink to "0.2.4.txt" but must point '
          'at "0.2.5.txt"',
        ),
        reason: message,
      );
      expect(message, contains('fdroid_changelog_links.dart'), reason: message);
    });

    test('a non-regular authoring entry fails the gate loudly naming the '
        'locale and the actual mode', () async {
      Object? caught;
      try {
        await requireChangelogFiles(
          versionName: '0.2.5',
          versionCodeBase: 7,
          defaultChangelogOnly: false,
          headSha: validHeadSha,
          ghApiRunner: gateRunner(
            fixture(
              targets: {
                for (final locale in ['de-DE', 'en-US'])
                  locale: completeTargets(),
              },
              authoringMode: '120000',
            ),
          ),
          sink: (_) {},
        );
      } on ReleaseToolException catch (error) {
        caught = error;
      }
      expect(
        caught,
        isNotNull,
        reason: 'a symlinked authoring entry must fail the gate',
      );
      final message = '$caught';
      expect(message, contains('de-DE:'), reason: message);
      expect(message, contains(authoringName), reason: message);
      expect(message, contains('git mode 120000'), reason: message);
    });

    test('a default.txt symlink fails the gate loudly with the hand-fix '
        'path for the fallback text', () async {
      Object? caught;
      try {
        await requireChangelogFiles(
          versionName: '0.2.5',
          versionCodeBase: 7,
          defaultChangelogOnly: false,
          headSha: validHeadSha,
          ghApiRunner: gateRunner(
            changelogGateFixture(
              targets: {
                for (final locale in ['de-DE', 'en-US'])
                  locale: {
                    for (final name in allChangelogNames) name: authoringName,
                  },
              },
              authoringName: authoringName,
              linkNames: allChangelogNames,
            ),
          ),
          sink: (_) {},
        );
      } on ReleaseToolException catch (error) {
        caught = error;
      }
      expect(
        caught,
        isNotNull,
        reason: 'a symlinked default.txt must fail the gate',
      );
      final message = '$caught';
      expect(
        message,
        contains('de-DE: $fdroidMetadataPath/de-DE/changelogs/default.txt'),
        reason: message,
      );
      expect(message, contains('git mode 120000'), reason: message);
      expect(
        message,
        contains('hand-maintained'),
        reason:
            '$message — the fix path must name the fallback text as '
            'hand-maintained, not shapeable by the link generator',
      );
    });

    test('skip mode passes on a tree stripped to the regular default.txt '
        'blob — absent authoring and per-ABI names are not checked', () async {
      final lines = <String>[];
      await requireChangelogFiles(
        versionName: '0.2.5',
        versionCodeBase: 7,
        defaultChangelogOnly: true,
        headSha: validHeadSha,
        ghApiRunner: gateRunner(skipFixture()),
        sink: lines.add,
      );
      expect(lines.length, 2, reason: lines.join('\n'));
      expect(lines.join('\n'), contains('de-DE ok'));
      expect(lines.join('\n'), contains('en-US ok'));
    });

    test('skip mode fails loudly naming ONLY the default.txt when it is '
        'missing', () async {
      Object? caught;
      try {
        await requireChangelogFiles(
          versionName: '0.2.5',
          versionCodeBase: 7,
          defaultChangelogOnly: true,
          headSha: validHeadSha,
          ghApiRunner: gateRunner(skipFixture(perLocale: const {})),
          sink: (_) {},
        );
      } on ReleaseToolException catch (error) {
        caught = error;
      }
      expect(
        caught,
        isNotNull,
        reason: 'a default.txt-less tree must fail the skip-mode gate',
      );
      final message = '$caught';
      expect(message, contains('de-DE: missing default.txt'), reason: message);
      expect(message, contains('en-US: missing default.txt'), reason: message);
      expect(message, isNot(contains(authoringName)), reason: message);
      expect(message, isNot(contains('71.txt')), reason: message);
      expect(message, contains('--default-changelog-only'), reason: message);
    });

    test('skip mode keeps the default.txt mode check: a symlinked '
        'default.txt fails loudly', () async {
      Object? caught;
      try {
        await requireChangelogFiles(
          versionName: '0.2.5',
          versionCodeBase: 7,
          defaultChangelogOnly: true,
          headSha: validHeadSha,
          ghApiRunner: gateRunner(
            changelogGateFixture(
              targets: {
                for (final locale in ['de-DE', 'en-US'])
                  locale: {'default.txt': authoringName},
              },
              authoringName: authoringName,
              linkNames: const ['default.txt'],
              includeAuthoringEntry: false,
            ),
          ),
          sink: (_) {},
        );
      } on ReleaseToolException catch (error) {
        caught = error;
      }
      expect(
        caught,
        isNotNull,
        reason: 'a symlinked default.txt must fail the skip-mode gate too',
      );
      final message = '$caught';
      expect(message, contains('git mode 120000'), reason: message);
      expect(message, contains('hand-maintained'), reason: message);
    });

    test(
      'a failed tree call aborts instead of counting as "missing"',
      () async {
        Object? caught;
        try {
          await requireChangelogFiles(
            versionName: '0.2.5',
            versionCodeBase: 7,
            defaultChangelogOnly: false,
            headSha: validHeadSha,
            ghApiRunner: (arguments) async =>
                ProcessResult(0, 1, '', 'gh: HTTP 404'),
            sink: (_) {},
          );
        } on ReleaseToolException catch (error) {
          caught = error;
        }
        final message = '$caught';
        expect(message, contains('git-tree'), reason: message);
        expect(message, contains('gh'), reason: message);
        expect(message, isNot(contains('Fix path')), reason: message);
      },
    );

    test(
      'a locale-less metadata tree fails loudly in both gate modes',
      () async {
        for (final defaultChangelogOnly in [false, true]) {
          Object? caught;
          try {
            await requireChangelogFiles(
              versionName: '0.2.5',
              versionCodeBase: 7,
              defaultChangelogOnly: defaultChangelogOnly,
              headSha: validHeadSha,
              ghApiRunner: gateRunner((
                tree:
                    '{"tree":[{"path":"$fdroidMetadataPath/README.md",'
                    '"mode":"100644","type":"blob","sha":"sha-readme"}],'
                    '"truncated":false}',
                blobs: const {},
              )),
              sink: (_) {},
            );
          } on ReleaseToolException catch (error) {
            caught = error;
          }
          expect('$caught', contains('no locale directory'), reason: '$caught');
        }
      },
    );

    test('the full-release gate returns the en-US authoring changelog text '
        'fetched at the head commit', () async {
      final content = await requireChangelogFiles(
        versionName: '0.2.5',
        versionCodeBase: 7,
        defaultChangelogOnly: false,
        headSha: validHeadSha,
        ghApiRunner: gateRunner(
          fixture(
            targets: {
              for (final locale in ['de-DE', 'en-US'])
                locale: completeTargets(),
            },
            regularFileContents: {
              'de-DE': {authoringName: 'de authoring body'},
              'en-US': {authoringName: 'en-US authoring body'},
            },
          ),
        ),
        sink: (_) {},
      );
      expect(content, 'en-US authoring body');
    });

    test('the default-changelog-only gate returns the en-US default.txt '
        'content', () async {
      final content = await requireChangelogFiles(
        versionName: '0.2.5',
        versionCodeBase: 7,
        defaultChangelogOnly: true,
        headSha: validHeadSha,
        ghApiRunner: gateRunner(
          skipFixture(
            regularFileContents: {
              'en-US': {'default.txt': 'en-US fallback body'},
            },
          ),
        ),
        sink: (_) {},
      );
      expect(content, 'en-US fallback body');
    });

    test('a tree without an en-US locale directory fails loudly naming '
        'en-US', () async {
      Object? caught;
      try {
        await requireChangelogFiles(
          versionName: '0.2.5',
          versionCodeBase: 7,
          defaultChangelogOnly: false,
          headSha: validHeadSha,
          ghApiRunner: gateRunner(
            fixture(targets: {'de-DE': completeTargets()}),
          ),
          sink: (_) {},
        );
      } on ReleaseToolException catch (error) {
        caught = error;
      }
      expect(
        caught,
        isNotNull,
        reason: 'a tree without en-US must abort the gate',
      );
      expect('$caught', contains('en-US'), reason: '$caught');
    });

    test('a failed content-blob fetch fails loudly naming the git-blob '
        'fetch', () async {
      final data = fixture(
        targets: {
          for (final locale in ['de-DE', 'en-US']) locale: completeTargets(),
        },
      );
      final summaryBlobSha = 'sha-en-US-authoring';
      expect(data.blobs.containsKey(summaryBlobSha), isTrue);
      Object? caught;
      try {
        await requireChangelogFiles(
          versionName: '0.2.5',
          versionCodeBase: 7,
          defaultChangelogOnly: false,
          headSha: validHeadSha,
          ghApiRunner: gateRunner((
            tree: data.tree,
            blobs: {...data.blobs}..remove(summaryBlobSha),
          )),
          sink: (_) {},
        );
      } on ReleaseToolException catch (error) {
        caught = error;
      }
      expect(
        caught,
        isNotNull,
        reason: 'a failed content-blob fetch must abort the gate',
      );
      expect('$caught', contains('git-blob fetch'), reason: '$caught');
      expect('$caught', contains(summaryBlobSha), reason: '$caught');
    });
  });

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
      for (final tag in badTagList) {
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

    test('accepts --default-changelog-only (the minor-release agreement '
        'flag) and defaults to off without it', () {
      final options = publish.parseArguments([
        'v1.2.3',
        '--default-changelog-only',
      ]);
      expect(options.defaultChangelogOnly, isTrue);
      expect(publish.parseArguments(['v1.2.3']).defaultChangelogOnly, isFalse);
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
        ..writeAsStringSync('${validManifestJson()}\n');
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
        ..writeAsStringSync('${validManifestJson()}\n');
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
    test('layers the fingerprint line, the checksum lines in attach order, '
        'then a blank line and the what\'s-new block', () {
      final body = publish.buildNotesBody(
        certificateFingerprint: pinnedReleaseFingerprint,
        apkSha256ByPublishName: {
          for (final name in publishApkNames('0.2.1')) name: '99' * 32,
        },
        whatsNew: whatsNewRaw,
      );
      expect(
        body,
        'SHA-256 certificate fingerprint: $pinnedReleaseFingerprint\n'
        'APK SHA-256: cycle-app-0.2.1-armeabi-v7a.apk ${'99' * 32}\n'
        'APK SHA-256: cycle-app-0.2.1-arm64-v8a.apk ${'99' * 32}\n'
        'APK SHA-256: cycle-app-0.2.1-x86_64.apk ${'99' * 32}\n'
        '\n'
        '${summaryBlock(whatsNewTrimmed)}',
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

  group("summary block splice (what's new, re-attach)", () {
    final fingerprintLine =
        'SHA-256 certificate fingerprint: $pinnedReleaseFingerprint';

    test('a body that already carries the block gets it replaced whole, '
        'checksum lines and surrounding prose untouched', () {
      const oldContent = 'Stale old summary text.';
      final body =
          '$fingerprintLine\n'
          'APK SHA-256: cycle-app-0.2.1-armeabi-v7a.apk ${'aa' * 32}\n'
          '${summaryBlock(oldContent)}\n'
          '\n'
          "## What's Changed\n"
          '\n'
          '* generated entry\n';
      final spliced = publish.spliceSummaryBlock(body, whatsNewRaw);
      expect(
        spliced,
        '$fingerprintLine\n'
        'APK SHA-256: cycle-app-0.2.1-armeabi-v7a.apk ${'aa' * 32}\n'
        '${summaryBlock(whatsNewTrimmed)}\n'
        '\n'
        "## What's Changed\n"
        '\n'
        '* generated entry\n',
      );
      expect(spliced, isNot(contains(oldContent)));
    });

    test('a legacy body without the marker gets the block inserted after '
        'the last checksum line, before the generated changelog', () {
      final body =
          '$fingerprintLine\n'
          'APK SHA-256: cycle-app-0.2.1-armeabi-v7a.apk ${'aa' * 32}\n'
          'APK SHA-256: cycle-app-0.2.1-arm64-v8a.apk ${'bb' * 32}\n'
          '\n'
          "## What's Changed\n"
          '\n'
          '* generated entry\n';
      final spliced = publish.spliceSummaryBlock(body, whatsNewRaw);
      expect(
        spliced,
        '$fingerprintLine\n'
        'APK SHA-256: cycle-app-0.2.1-armeabi-v7a.apk ${'aa' * 32}\n'
        'APK SHA-256: cycle-app-0.2.1-arm64-v8a.apk ${'bb' * 32}\n'
        '\n'
        '${summaryBlock(whatsNewTrimmed)}\n'
        '\n'
        "## What's Changed\n"
        '\n'
        '* generated entry\n',
      );
    });

    test('a legacy body without checksum lines gets the block inserted '
        'after the fingerprint line', () {
      final body = '$fingerprintLine\n\n## What\'s Changed\n\n* entry\n';
      final spliced = publish.spliceSummaryBlock(body, whatsNewRaw);
      expect(
        spliced,
        '$fingerprintLine\n'
        '\n'
        '${summaryBlock(whatsNewTrimmed)}\n'
        '\n'
        "## What's Changed\n"
        '\n'
        '* entry\n',
      );
    });

    test('a body with neither checksum nor fingerprint lines gets the '
        'block appended at the end', () {
      const body = '## Cycle App 0.2.1\n\nGenerated changelog.\n';
      final spliced = publish.spliceSummaryBlock(body, whatsNewRaw);
      expect(
        spliced,
        '## Cycle App 0.2.1\n\nGenerated changelog.\n\n'
        '${summaryBlock(whatsNewTrimmed)}',
      );
    });

    test('splicing a body that already carries the current block yields '
        'the same body', () {
      final body =
          '$fingerprintLine\n'
          'APK SHA-256: cycle-app-0.2.1-x86_64.apk ${'cc' * 32}\n'
          '${summaryBlock(whatsNewTrimmed)}\n'
          '\n'
          'Prose.\n';
      expect(publish.spliceSummaryBlock(body, whatsNewRaw), body);
      final freshBody = publish.buildNotesBody(
        certificateFingerprint: pinnedReleaseFingerprint,
        apkSha256ByPublishName: {'cycle-app-0.2.1-x86_64.apk': 'cc' * 32},
        whatsNew: whatsNewRaw,
      );
      expect(publish.spliceSummaryBlock(freshBody, whatsNewRaw), freshBody);
    });

    test('a start marker without its closing marker fails loudly', () {
      const body = 'prose\n<!-- release-summary -->\ndangling content\n';
      expect(
        () => publish.spliceSummaryBlock(body, whatsNewRaw),
        throwsA(isA<ReleaseToolException>()),
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
      whatsNew: whatsNewRaw,
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
          'gh pr create --repo BenediktBurger/cycle-app --base main '
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

    test('gh pr create argv: base main, head the release branch, '
        'release-URL body', () {
      expect(publish.prCreateArguments(branch: branch, tag: tag), [
        'pr',
        'create',
        '--repo',
        releaseRepo,
        '--base',
        'main',
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
        '— the release commit must stay an ancestor of main)', () {
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
          'gh pr create --repo BenediktBurger/cycle-app --base main '
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
        ..writeAsStringSync('${validManifestJson()}\n');
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
      bool changelogOnlyGate = false,
      List<String> gateLocales = const ['de-DE', 'en-US'],
      String enUsChangelogContent = whatsNewRaw,
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
        if (arguments[0] == 'api') {
          // Git Trees + Git Blobs API (read-only): the changelog-files gate
          // walks the fastlane tree at the manifest's head commit and
          // resolves each changelog symlink's target blob.
          const authoringName = '0.2.1.txt';
          const linkNames = ['31.txt', '32.txt', '33.txt', 'default.txt'];
          if (changelogOnlyGate) {
            return changelogGateRunner(
              changelogGateFixture(
                targets: {
                  for (final locale in gateLocales)
                    locale: const {'default.txt': 'fallback text'},
                },
                authoringName: authoringName,
                linkNames: const ['default.txt'],
                includeAuthoringEntry: false,
                regularNames: const {'default.txt'},
                regularFileContents: {
                  'en-US': {'default.txt': enUsChangelogContent},
                },
              ),
            )(arguments);
          }
          return changelogGateRunner(
            changelogGateFixture(
              targets: {
                for (final locale in gateLocales)
                  locale: {for (final name in linkNames) name: authoringName},
              },
              authoringName: authoringName,
              linkNames: linkNames,
              regularNames: const {'default.txt'},
              regularFileContents: {
                'en-US': {authoringName: enUsChangelogContent},
              },
            ),
          )(arguments);
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

      // The summary text is the en-US changelog fetched at the manifest's
      // head commit.
      expect(output, contains(summaryBlock(whatsNewTrimmed)));
      expect(
        output,
        isNot(contains('fallback text')),
        reason:
            'the summary text is the en-US content blob, not the '
            'fallback the other fixture entries serve',
      );
      final checksumIndex = output.indexOf(
        'APK SHA-256: cycle-app-0.2.1-x86_64.apk ${'66' * 32}',
      );
      final summaryIndex = output.indexOf(publish.releaseSummaryStartMarker);
      expect(checksumIndex, greaterThan(-1));
      expect(summaryIndex, greaterThan(checksumIndex));

      // PR payloads are printed, never run.
      expect(output, contains('gh pr create --repo'));
      expect(output, contains('gh pr merge --merge --auto release/v0.2.1'));
      expect(output, contains('dry run complete'));

      // Nothing mutating was handed to gh: only auth status, the
      // contents-API listings, and the release view (read-only).
      for (final invocation in ghInvocations) {
        final isReadOnly =
            (invocation.first == 'auth') ||
            (invocation.first == 'api') ||
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
      expect(
        output,
        contains(
          'APK SHA-256: cycle-app-0.2.1-x86_64.apk ${'66' * 32}\n'
          '\n'
          '${summaryBlock(whatsNewTrimmed)}',
        ),
      );
      expect(
        publish.releaseSummaryStartMarker.allMatches(output).length,
        1,
        reason: 'exactly one summary block, no duplicate insertion',
      );
      expect(output, contains('dry run complete'));
      for (final invocation in ghInvocations) {
        final isReadOnly =
            (invocation.first == 'auth') ||
            (invocation.first == 'api') ||
            (invocation[0] == 'release' && invocation[1] == 'view');
        expect(isReadOnly, isTrue, reason: 'invocation: $invocation');
      }
    });

    test('dry run on an existing release whose body already carries a '
        'stale summary block: the block is replaced, not duplicated', () async {
      stageHappyTree();
      final oldBody =
          'SHA-256 certificate fingerprint: $pinnedReleaseFingerprint\n'
          'APK SHA-256: cycle-app-0.2.1-arm64-v8a.apk ${'bb' * 32}\n'
          '${summaryBlock('Stale old summary text.')}\n'
          '\n'
          "## What's Changed\n"
          '\n'
          '* generated entry\n';
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

      expect(output, contains(summaryBlock(whatsNewTrimmed)));
      expect(output, isNot(contains('Stale old summary text.')));
      expect(
        publish.releaseSummaryStartMarker.allMatches(output).length,
        1,
        reason: 'the stale block is replaced wholesale, not duplicated',
      );
      expect(
        output,
        contains(
          'APK SHA-256: cycle-app-0.2.1-x86_64.apk ${'66' * 32}\n'
          '${summaryBlock(whatsNewTrimmed)}',
        ),
      );
      expect(output, contains('dry run complete'));
      for (final invocation in ghInvocations) {
        final isReadOnly =
            (invocation.first == 'auth') ||
            (invocation.first == 'api') ||
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

        // The notes file was staged under the publish tree: fingerprint +
        // checksum block first, then the what's-new summary block.
        final notes = File('${root.path}/${publish.notesFilePath(tag)}');
        expect(notes.existsSync(), isTrue);
        expect(
          notes.readAsStringSync(),
          'SHA-256 certificate fingerprint: $pinnedReleaseFingerprint\n'
          'APK SHA-256: cycle-app-0.2.1-armeabi-v7a.apk ${'44' * 32}\n'
          'APK SHA-256: cycle-app-0.2.1-arm64-v8a.apk ${'55' * 32}\n'
          'APK SHA-256: cycle-app-0.2.1-x86_64.apk ${'66' * 32}\n'
          '\n'
          '${summaryBlock(whatsNewTrimmed)}',
        );
        expect(output, contains('created the release'));
      },
    );

    test('real run on an existing release: uploads --clobber, splices the '
        'checksums into the notes, and a rejected PR merge soft-fails with '
        'the manual command (exit stays 0)', () async {
      stageHappyTree();
      final oldBody =
          'SHA-256 certificate fingerprint: $pinnedReleaseFingerprint\n'
          'APK SHA-256: cycle-app-0.2.1-arm64-v8a.apk ${'bb' * 32}\n'
          '${summaryBlock('Stale old summary text.')}\n'
          '\n'
          "## What's Changed\n"
          '\n'
          '* generated entry\n';
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
      // The updated notes were staged: fresh checksums, and the stale
      // summary block replaced (never duplicated).
      final notesBody = File(
        '${root.path}/${publish.notesFilePath(tag)}',
      ).readAsStringSync();
      // fetchReleaseBody trims the fetched body, so the staged file ends
      // without a trailing newline.
      expect(
        notesBody,
        'SHA-256 certificate fingerprint: $pinnedReleaseFingerprint\n'
        'APK SHA-256: cycle-app-0.2.1-armeabi-v7a.apk ${'44' * 32}\n'
        'APK SHA-256: cycle-app-0.2.1-arm64-v8a.apk ${'55' * 32}\n'
        'APK SHA-256: cycle-app-0.2.1-x86_64.apk ${'66' * 32}\n'
        '${summaryBlock(whatsNewTrimmed)}\n'
        '\n'
        "## What's Changed\n"
        '\n'
        '* generated entry',
      );
      expect(notesBody, isNot(contains('bb' * 32)));
      expect(notesBody, isNot(contains('Stale old summary text.')));
      expect(output, contains('uploaded the APKs'));
      expect(output, contains('release notes updated'));
      // Soft-fail: the merge rejection printed the manual fallback command
      // and the run completed normally (no throw above).
      expect(output, contains('gh pr merge --merge --auto release/v0.2.1'));
      expect(output, contains('Allow auto-merge'));
    });

    test('a missing English changelog aborts the whole run before any '
        'release create, upload, or edit', () async {
      stageHappyTree();
      final lines = <String>[];
      await expectLater(
        publish.runPublishRelease(
          ['v0.2.1'],
          root: root,
          ghRunner: ghFixture(
            releaseViewResult: 'missing',
            gateLocales: const ['de-DE'],
          ),
          sha256Runner: fakeSha256Runner,
          printer: lines.add,
        ),
        throwsA(
          isA<ReleaseToolException>().having(
            (error) => error.message,
            'message',
            contains('en-US'),
          ),
        ),
      );
      final mutating = ghInvocations.where(
        (invocation) =>
            invocation[0] == 'release' &&
            const {'create', 'upload', 'edit'}.contains(invocation[1]),
      );
      expect(mutating, isEmpty, reason: 'invocations: $ghInvocations');
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

    group('default-changelog-only flow (the manifest is authoritative)', () {
      /// stageHappyTree() with the manifest rewritten to carry the given
      /// `defaultChangelogOnly` value.
      void stageTreeWithManifest({required bool defaultChangelogOnly}) {
        stageHappyTree();
        File('${root.path}/$handoffManifestPath').writeAsStringSync(
          '${manifestJsonRaw(tag: '"v0.2.1"', versionName: '"0.2.1"', versionCodeBase: '3', runId: '1234567890', headSha: '"$validHeadSha"', defaultChangelogOnly: '$defaultChangelogOnly')}\n',
        );
      }

      test(
        'CLI flag + manifest false is a loud exit BEFORE any gh call',
        () async {
          stageHappyTree();
          Object? caught;
          try {
            await publish.runPublishRelease(
              ['v0.2.1', '--default-changelog-only'],
              root: root,
              ghRunner: ghFixture(releaseViewResult: 'missing'),
              sha256Runner: fakeSha256Runner,
              printer: (_) {},
            );
          } on UsageException catch (error) {
            caught = error;
          }
          expect(caught, isNotNull, reason: 'the mismatch must abort loudly');
          expect(ghInvocations, isEmpty);
        },
      );

      test('manifest true without the CLI flag proceeds in skip mode with '
          'the info line', () async {
        stageTreeWithManifest(defaultChangelogOnly: true);
        final lines = <String>[];
        await publish.runPublishRelease(
          ['v0.2.1', '--dry-run'],
          root: root,
          ghRunner: ghFixture(
            releaseViewResult: 'missing',
            changelogOnlyGate: true,
          ),
          sha256Runner: fakeSha256Runner,
          printer: lines.add,
        );
        final output = lines.join('\n');
        expect(
          output,
          contains('default-changelog-only'),
          reason: 'the run says which gate scope the manifest drove',
        );
        expect(output, contains('handoff manifest resolved:'));
        expect(output, contains('dry run complete'));
      });

      test('CLI flag + manifest true: both agree, skip mode runs', () async {
        stageTreeWithManifest(defaultChangelogOnly: true);
        final lines = <String>[];
        await publish.runPublishRelease(
          ['v0.2.1', '--dry-run', '--default-changelog-only'],
          root: root,
          ghRunner: ghFixture(
            releaseViewResult: 'missing',
            changelogOnlyGate: true,
          ),
          sha256Runner: fakeSha256Runner,
          printer: lines.add,
        );
        final output = lines.join('\n');
        expect(output, contains('default-changelog-only'));
        expect(output, contains('dry run complete'));
      });
    });
  });
}
