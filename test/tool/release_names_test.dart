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
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/release_names.dart';
import 'release_fixtures.dart'
    show
        changelogGateFixture,
        changelogGateRunner,
        badTagList,
        manifestJsonRaw,
        pinnedReleaseFingerprint,
        validHeadSha,
        validManifestJson;

void main() {
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
}
