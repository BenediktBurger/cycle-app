// Pure-logic tests for tool/release_names.dart — the shared module of the
// two release helpers (tool/download_and_sign.dart stages the signed APKs
// plus the handoff manifest, tool/publish_release.dart consumes them). This
// module carries the pieces both halves need: publish names, staged paths,
// tag/branch helpers, the staged-APK validation, the adb / post-release info
// line builders, and the handoff-manifest codec for
// build/gh-release/source.json.
//
// Pure seam as everywhere in test/tool/: fixture strings and temp-dir
// sandboxes only — nothing here shells out to real gh/apksigner/aapt/git/
// sha256sum, and no release, upload, or signing ever happens in a test.
// Relative import on purpose: tool/ scripts live outside lib/ and are not
// addressable through `package:cycle_app/`.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/release_names.dart';

/// The pinned release-certificate fingerprint, duplicated here from the
/// committed [pinFilePath] content so the tests pin the exact trust anchor
/// the release pipeline must enforce.
const pinnedReleaseFingerprint =
    '0aa5749804b8ed9e3c207f851b5902775d762207d60c2485a26b5d75eff5355b';

/// A well-formed 40-char lowercase head SHA for the manifest fixtures.
const validHeadSha = '978dbc5b9ee19ff0aedfc03594a603013f0e034a';

/// Builds a handoff-manifest JSON fixture out of RAW JSON fragments, so
/// malformed variants (wrong types, missing keys) stay writable.
String manifestJsonRaw({
  String? tag,
  String? versionName,
  String? versionCodeBase,
  String? runId,
  String? headSha,
}) {
  final fields = <String>[
    if (tag != null) '"tag":$tag',
    if (versionName != null) '"versionName":$versionName',
    if (versionCodeBase != null) '"versionCodeBase":$versionCodeBase',
    if (runId != null) '"runId":$runId',
    if (headSha != null) '"headSha":$headSha',
  ];
  return '{${fields.join(',')}}';
}

/// A well-formed manifest fixture with the settled default values.
String validManifestJson() => manifestJsonRaw(
  tag: '"v0.2.1"',
  versionName: '"0.2.1"',
  versionCodeBase: '3',
  runId: '1234567890',
  headSha: '"$validHeadSha"',
);

void main() {
  group('publish names and staged paths', () {
    const version = '0.2.1';

    test('ABI codes map the three release ABIs to 1/2/3', () {
      expect(abiCodes, {'armeabi-v7a': 1, 'arm64-v8a': 2, 'x86_64': 3});
      expect(releaseAbis, ['armeabi-v7a', 'arm64-v8a', 'x86_64']);
    });

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

    test('multi-digit versions survive the derivation', () {
      expect(
        publishApkName(versionName: '10.11.12', abi: 'x86_64'),
        'cycle-app-10.11.12-x86_64.apk',
      );
      expect(publishApkNames('10.11.12').last, 'cycle-app-10.11.12-x86_64.apk');
    });

    test('staged publish paths live under build/gh-release (gitignored)', () {
      expect(stagedPublishPaths(version), [
        '$ghReleaseStagingDir/cycle-app-0.2.1-armeabi-v7a.apk',
        '$ghReleaseStagingDir/cycle-app-0.2.1-arm64-v8a.apk',
        '$ghReleaseStagingDir/cycle-app-0.2.1-x86_64.apk',
      ]);
    });

    test('staged paths compose the staging dir with the publish names', () {
      for (final abi in releaseAbis) {
        expect(
          stagedPublishPath(versionName: version, abi: abi),
          '$ghReleaseStagingDir/'
          '${publishApkName(versionName: version, abi: abi)}',
          reason: abi,
        );
      }
    });
  });

  group('tag and branch helpers', () {
    test('valid release tags pass the regex', () {
      for (final tag in ['v0.2.1', 'v1.2.3', 'v10.11.12']) {
        expect(isValidReleaseTag(tag), isTrue, reason: tag);
      }
    });

    test('malformed tags fail the regex', () {
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
    final manifest = const HandoffManifest(
      tag: 'v0.2.1',
      versionName: '0.2.1',
      versionCodeBase: 3,
      runId: 1234567890,
      headSha: validHeadSha,
    );

    test('encode produces the settled exact shape with the declared field '
        'order', () {
      expect(
        encodeHandoffManifest(manifest),
        '{"tag":"v0.2.1","versionName":"0.2.1","versionCodeBase":3,'
        '"runId":1234567890,"headSha":"$validHeadSha"}',
      );
    });

    test('encode → decode round trip preserves every field', () {
      expect(decodeHandoffManifest(encodeHandoffManifest(manifest)), manifest);
    });

    test('the manifest path is build/gh-release/source.json', () {
      expect(handoffManifestPath, 'build/gh-release/source.json');
      expect(handoffManifestPath.startsWith('$ghReleaseStagingDir/'), isTrue);
    });

    test('a well-formed manifest decodes to the same values', () {
      final decoded = decodeHandoffManifest(validManifestJson());
      expect(decoded.tag, 'v0.2.1');
      expect(decoded.versionName, '0.2.1');
      expect(decoded.versionCodeBase, 3);
      expect(decoded.runId, 1234567890);
      expect(decoded.headSha, validHeadSha);
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

    test('a missing field fails loudly (each of the five dropped once)', () {
      final variants = <String>[
        manifestJsonRaw(
          versionName: '"0.2.1"',
          versionCodeBase: '3',
          runId: '1',
          headSha: '"$validHeadSha"',
        ),
        manifestJsonRaw(
          tag: '"v0.2.1"',
          versionCodeBase: '3',
          runId: '1',
          headSha: '"$validHeadSha"',
        ),
        manifestJsonRaw(
          tag: '"v0.2.1"',
          versionName: '"0.2.1"',
          runId: '1',
          headSha: '"$validHeadSha"',
        ),
        manifestJsonRaw(
          tag: '"v0.2.1"',
          versionName: '"0.2.1"',
          versionCodeBase: '3',
          headSha: '"$validHeadSha"',
        ),
        manifestJsonRaw(
          tag: '"v0.2.1"',
          versionName: '"0.2.1"',
          versionCodeBase: '3',
          runId: '1',
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
        ),
        manifestJsonRaw(
          tag: '"v0.2.1"',
          versionName: 'null',
          versionCodeBase: '3',
          runId: '1',
          headSha: '"$validHeadSha"',
        ),
        manifestJsonRaw(
          tag: '"v0.2.1"',
          versionName: '"0.2.1"',
          versionCodeBase: '"3"',
          runId: '1',
          headSha: '"$validHeadSha"',
        ),
        manifestJsonRaw(
          tag: '"v0.2.1"',
          versionName: '"0.2.1"',
          versionCodeBase: '3',
          runId: '"42"',
          headSha: '"$validHeadSha"',
        ),
        manifestJsonRaw(
          tag: '"v0.2.1"',
          versionName: '"0.2.1"',
          versionCodeBase: '3',
          runId: '1',
          headSha: '999',
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
}
