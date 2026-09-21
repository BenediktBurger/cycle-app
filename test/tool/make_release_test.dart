// Pure-logic tests for tool/make_release.dart — the release-publishing script
// behind per-release checklist step 7 of docs/release.md (the script's header
// comment carries the full context).
//
// These tests deliberately stay on the pure seam: they exercise argument
// parsing/validation, tag-vs-version matching, apksigner/aapt output parsing,
// pin-file read/write normalization, and release-notes assembly directly.
// Nothing here shells out to real git/gh/apksigner/aapt, and nothing touches
// the repository state (no tags are created) — the process layer of the
// script stays outside this suite by design.
// Relative import on purpose: tool/ scripts live outside lib/ and are not
// addressable through `package:cycle_app/`.
import '../../tool/make_release.dart';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('argument parsing', () {
    test('accepts a well-formed tag plus flags', () {
      final options = parseArguments(['v1.2.3', '--dry-run']);
      expect(options.tag, 'v1.2.3');
      expect(options.dryRun, isTrue);
      expect(options.acceptFingerprint, isFalse);
      expect(options.tested, isFalse);
    });

    test('parses every flag independently', () {
      final options = parseArguments(
          ['--tested', 'v0.1.0', '--accept-fingerprint', '--dry-run']);
      expect(options.tag, 'v0.1.0');
      expect(options.acceptFingerprint, isTrue);
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
      expect(() => parseArguments(['--unknown', 'v1.2.3']),
          throwsA(isA<UsageException>()));
      expect(() => parseArguments(['-f', 'v1.2.3']),
          throwsA(isA<UsageException>()));
    });

    test('rejects missing and extra positional arguments', () {
      expect(() => parseArguments(const []), throwsA(isA<UsageException>()));
      expect(() => parseArguments(['v1.2.3', 'v2.0.0']),
          throwsA(isA<UsageException>()));
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
      const colonOutput = 'Signer #1 certificate SHA-256 digest: '
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
            'Signer #1 certificate SHA-1 digest: deadbeef\n'),
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
      final colonized = '6A:1F:2C:4D:5E:6F:70:81:92:A3:B4:C5:D6:E7:F8:09:'
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
      expect(fingerprintsMatch(fingerprint, 'ff${fingerprint.substring(2)}'),
          isFalse);
    });
  });

  group('newest build-tools resolution (sort -V equivalent)', () {
    test('picks the numerically highest version directory', () {
      expect(newestBuildToolsDirectory(const ['33.0.2', '34.0.0', '35.0.1']),
          '35.0.1');
      expect(newestBuildToolsDirectory(const ['9.0.0', '10.0.0']), '10.0.0');
      expect(newestBuildToolsDirectory(const ['35.0.1', '34.0.0']), '35.0.1');
    });

    test('ignores non-version entries and handles empty input', () {
      expect(newestBuildToolsDirectory(const ['source.properties', '34.0.0']),
          '34.0.0');
      expect(newestBuildToolsDirectory(const []), isNull);
      expect(newestBuildToolsDirectory(const ['not-a-version']), isNull);
    });
  });

  group('release-notes body assembly', () {
    const fingerprint =
        '6a1f2c4d5e6f708192a3b4c5d6e7f8091a2b3c4d5e6f708192a3b4c5d6e7f809';

    test('contains the certificate fingerprint and APK checksum lines', () {
      final body = buildNotesBody(
        certificateFingerprint: fingerprint,
        apkSha256:
            'deadbeefcafebabe0123456789abcdefdeadbeefcafebabe0123456789abcdef',
      );
      expect(
        body,
        contains('SHA-256 certificate fingerprint: $fingerprint'),
      );
      expect(
        body,
        contains('APK SHA-256: '
            'deadbeefcafebabe0123456789abcdefdeadbeefcafebabe0123456789abcdef'),
      );
    });

    test('normalizes a colonized certificate fingerprint in the notes', () {
      final body = buildNotesBody(
        certificateFingerprint: '6A:1F:2C:4D:5E:6F:70:81:92:A3:B4:C5:D6:E7:'
            'F8:09:1A:2B:3C:4D:5E:6F:70:81:92:A3:B4:C5:D6:E7:F8:09',
        apkSha256: 'ff' * 32,
      );
      expect(body, contains('SHA-256 certificate fingerprint: $fingerprint'));
    });
  });
}
