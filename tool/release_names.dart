// Shared module of the two release helpers: tool/download_and_sign.dart
// (resolves the CI run, downloads the unsigned artifacts, validates and
// signs them, stages the result under build/gh-release/ and ends at the
// handoff manifest) and tool/publish_release.dart (checksums → release
// assembly → PR → post info; the only one with a --dry-run). Both scripts
// import this module for the pieces both halves need: the naming constants
// and helpers, tag/branch helpers, the staged-APK validation, the adb /
// post-release info line builders, the handoff-manifest codec for
// build/gh-release/source.json, the fingerprint/pin normalizers both need
// against the same committed pin file, and ONE loud-failure exception type
// that both mains catch on their way to `stderr` + exit 1.
//
// Deliberately NOT here: anything Android-SDK- or build-tools-specific
// (downloader/signer domain), the pubspec/envelope parsing (downloader
// domain), and the release/notes/splice/PR payload logic (publish domain).
// tool/download_and_sign.dart's header describes where each half lives.
//
// Repo hygiene rules apply as everywhere (see AGENTS.md): no internal
// work-package or phase labels in code, comments, or messages.
//
// Linux release machine note: both consumers target the project's Linux
// release machine by design — they shell out to `gh`, the Android SDK
// build-tools, and `sha256sum`; the pieces gathered here only shape
// names/paths/JSON and validate files, so they stay platform-neutral.

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

/// The GitHub repository whose artifacts are downloaded, whose releases are
/// assembled, and whose PRs are opened.
const String releaseRepo = 'BenediktBurger/cycle-app';

/// Committed file pinning the release-certificate fingerprint (the trust
/// anchor; the F-Droid metadata cross-checks against the same value). The
/// downloader enforces it as the signature hard gate, the publisher stamps
/// it into fresh release notes.
const String pinFilePath = 'tool/release_fingerprint.txt';

/// Gitignored staging directory, relative to the repository root: script 1
/// writes the signed APKs and the handoff manifest here, script 2 consumes
/// exactly this tree.
const String ghReleaseStagingDir = 'build/gh-release';

/// ABI version-code offsets, mirroring the scheme in
/// android/app/build.gradle.kts: a split APK's versionCode is
/// `N * 10 + abiCode` (N = pubspec build number).
const Map<String, int> abiCodes = {
  'armeabi-v7a': 1,
  'arm64-v8a': 2,
  'x86_64': 3,
};

/// The three ABI splits in release asset order (armeabi-v7a first — the
/// attach order of the release).
const List<String> releaseAbis = ['armeabi-v7a', 'arm64-v8a', 'x86_64'];

/// Failure of a release-helper stage — always loud, always exit 1. Both
/// helper mains catch exactly this type (its [UsageException] subclass
/// included) and turn it into stderr + exit 1.
class ReleaseToolException implements Exception {
  ReleaseToolException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Bad command-line arguments — abort before any check runs. Each script
/// appends its own usage line.
class UsageException extends ReleaseToolException {
  UsageException(String message, {required String usage})
    : super('$message\n$usage');
}

/// The tag form every release invocation expects: `vX.Y.Z`.
bool isValidReleaseTag(String tag) => RegExp(r'^v\d+\.\d+\.\d+$').hasMatch(tag);

/// `vX.Y.Z` → `X.Y.Z` (call only on validated tags).
String tagToVersion(String tag) => tag.substring(1);

/// The release branch naming convention (push of a `release/**` branch is
/// what starts the CI build, so the CI run's head branch is `release/v<tag>`).
String releaseBranchForTag(String tag) => 'release/$tag';

// --- publish names / staged paths --------------------------------------------

/// The publish (asset) name for one ABI split of [versionName]:
/// `cycle-app-<version>-<abi>.apk`, e.g. `cycle-app-0.2.1-arm64-v8a.apk` —
/// exactly the F-Droid `binary:` URL basename.
String publishApkName({required String versionName, required String abi}) =>
    'cycle-app-$versionName-$abi.apk';

/// All three publish names, in release asset order.
List<String> publishApkNames(String versionName) => [
  for (final abi in releaseAbis)
    publishApkName(versionName: versionName, abi: abi),
];

/// The staged signed-APK path for one ABI: [ghReleaseStagingDir] plus the
/// publish name — the apksigner `--out` target in script 1 and the attach
/// path in script 2.
String stagedPublishPath({required String versionName, required String abi}) =>
    '$ghReleaseStagingDir/${publishApkName(versionName: versionName, abi: abi)}';

/// All three staged signed-APK paths, in release asset order.
List<String> stagedPublishPaths(String versionName) => [
  for (final abi in releaseAbis)
    stagedPublishPath(versionName: versionName, abi: abi),
];

/// Confirms that the staging step actually produced every staged signed APK
/// (exists and is non-empty) and returns the publish names in attach order.
/// A run whose signer silently skipped an APK — or a staging tree a
/// publisher is about to consume — must fail loudly here. The per-APK
/// `staged APK:` lines go through the injected [sink] (defaults to
/// [print]) so they land in the caller's collected output rather than
/// leaking past it — the publish half passes its sink down, the download
/// half keeps the default print.
List<String> requireStagedApks({
  required Directory root,
  required String versionName,
  void Function(String line)? sink,
}) {
  final out = sink ?? (line) => print(line);
  final stagedPaths = stagedPublishPaths(versionName);
  final failures = <String>[];
  for (final path in stagedPaths) {
    final file = File('${root.path}/$path');
    final exists = file.existsSync();
    if (exists && file.lengthSync() > 0) {
      out('staged APK: $path');
      continue;
    }
    failures.add(exists ? '$path exists but is empty' : '$path is missing');
  }
  if (failures.isNotEmpty) {
    throw ReleaseToolException(
      'the staging step did not produce every staged APK:\n'
      '${failures.join('\n')}\n'
      'Fix the signing stage (tool/download_and_sign.dart, build-tools '
      'hard cap ≤ 34) and rerun it before publishing.',
    );
  }
  return publishApkNames(versionName);
}

// --- handoff manifest (build/gh-release/source.json) ---------------------------

/// Provenance handoff between the two helpers, staged as
/// `$ghReleaseStagingDir/source.json` and gitignored alongside the APKs it
/// describes (so `flutter clean` ages manifest and APKs away together —
/// script 2 must re-run script 1 then, and already fails loudly on the
/// missing APKs). Script 1 writes it via [jsonEncode] at the END of a
/// successful staging run (only after [requireStagedApks] passed, so
/// manifest + non-empty staged set together mean "a complete signing run
/// happened for this tag"); script 2 decodes and validates it with
/// [decodeHandoffManifest] — the publish script re-resolves neither the run
/// nor the head SHA, so the publish tags the exact commit CI built even
/// when newer runs landed on the branch in the meantime.
class HandoffManifest {
  const HandoffManifest({
    required this.tag,
    required this.versionName,
    required this.versionCodeBase,
    required this.runId,
    required this.headSha,
  });

  /// The release tag the signing run was pointed at: `vX.Y.Z`.
  final String tag;

  /// The APK versionName: `X.Y.Z` — always [tag]'s `tagToVersion`.
  final String versionName;

  /// The pubspec build number `+N` at the run's commit; a split APK's
  /// versionCode is `N * 10 + abiCode`.
  final int versionCodeBase;

  /// The numeric id of the CI workflow run the artifacts came from
  /// (`--run-id` override or branch-resolved).
  final int runId;

  /// The run's head commit SHA, lowercase 40-hex — the exact shape
  /// `gh release create --target` needs.
  final String headSha;

  @override
  bool operator ==(Object other) =>
      other is HandoffManifest &&
      other.tag == tag &&
      other.versionName == versionName &&
      other.versionCodeBase == versionCodeBase &&
      other.runId == runId &&
      other.headSha == headSha;

  @override
  int get hashCode =>
      Object.hash(tag, versionName, versionCodeBase, runId, headSha);
}

/// The staged path of [HandoffManifest] relative to the repository root.
const String handoffManifestPath = '$ghReleaseStagingDir/source.json';

/// Encodes [manifest] as the settled JSON shape ([jsonEncode] of a map
/// literal — the declared field order is stable):
/// `{"tag","versionName","versionCodeBase","runId","headSha"}`.
String encodeHandoffManifest(HandoffManifest manifest) => jsonEncode({
  'tag': manifest.tag,
  'versionName': manifest.versionName,
  'versionCodeBase': manifest.versionCodeBase,
  'runId': manifest.runId,
  'headSha': manifest.headSha,
});

/// Decodes + validates a handoff manifest. Loud on anything unusable: a
/// non-JSON answer, a missing field, a wrong type, a tag violating
/// `^v\d+\.\d+\.\d+$`, a versionName disagreeing with the tag, a headSha
/// that is not lowercase 40-hex, or a non-positive versionCodeBase — a
/// publish run anti-dated to a wrong tag or commit would attach the wrong
/// assets at the wrong commit.
HandoffManifest decodeHandoffManifest(String source) {
  final dynamic decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException catch (error) {
    throw ReleaseToolException(
      'could not parse the handoff manifest as JSON: ${error.message}',
    );
  }
  if (decoded is! Map) {
    throw ReleaseToolException(
      'the handoff manifest must be a JSON object with the fields "tag", '
      '"versionName", "versionCodeBase", "runId", "headSha".',
    );
  }
  String stringField(String key) {
    if (!decoded.containsKey(key)) {
      throw ReleaseToolException(
        'handoff manifest field "$key" is missing — wanted '
        '{"tag","versionName","versionCodeBase","runId","headSha"}.',
      );
    }
    final value = decoded[key];
    if (value is! String) {
      throw ReleaseToolException(
        'handoff manifest field "$key" must be a string '
        '(got ${value.runtimeType} — wanted: tag, versionName, headSha).',
      );
    }
    return value;
  }

  int intField(String key) {
    if (!decoded.containsKey(key)) {
      throw ReleaseToolException(
        'handoff manifest field "$key" is missing — wanted '
        '{"tag","versionName","versionCodeBase","runId","headSha"}.',
      );
    }
    final value = decoded[key];
    if (value is! int) {
      throw ReleaseToolException(
        'handoff manifest field "$key" must be an int '
        '(got ${value.runtimeType} — wanted: versionCodeBase, runId).',
      );
    }
    return value;
  }

  final tag = stringField('tag');
  final versionName = stringField('versionName');
  final versionCodeBase = intField('versionCodeBase');
  final runId = intField('runId');
  final headSha = stringField('headSha');

  if (!isValidReleaseTag(tag)) {
    throw ReleaseToolException(
      'handoff manifest tag "$tag" must have the form vX.Y.Z.',
    );
  }
  if (versionName != tagToVersion(tag)) {
    throw ReleaseToolException(
      'handoff manifest inconsistency: versionName "$versionName" does not '
      'match the tag "$tag" (a stale or copied '
      '$ghReleaseStagingDir is the same wrong-asset risk as a version '
      'mismatch).',
    );
  }
  if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(headSha)) {
    throw ReleaseToolException(
      'handoff manifest headSha must be a lowercase 40-char hex SHA '
      '(got "$headSha") — it is the exact --target of the release create.',
    );
  }
  if (versionCodeBase <= 0) {
    throw ReleaseToolException(
      'handoff manifest versionCodeBase must be a positive int '
      '(got $versionCodeBase) — it feeds the N*10+abiCode verification URLs.',
    );
  }
  return HandoffManifest(
    tag: tag,
    versionName: versionName,
    versionCodeBase: versionCodeBase,
    runId: runId,
    headSha: headSha,
  );
}

// --- fingerprint / pin normalizers (shared trust anchor) ------------------------

/// Canonical form of a certificate fingerprint: no colons, no whitespace,
/// lowercase hex.
String normalizeFingerprint(String raw) =>
    raw.replaceAll(':', '').replaceAll(RegExp(r'\s'), '').toLowerCase();

bool isFingerprintHex(String value) =>
    RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

/// Reads the pin file content: skips comment (`#`) and blank lines, takes the
/// first remaining line as the fingerprint, normalized. Null when nothing
/// plausible remains. The downloader uses it as the signature hard gate; the
/// publisher uses it for the fresh release-notes fingerprint line.
String? parsePinFile(String pinFileContent) {
  for (final rawLine in pinFileContent.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final value = normalizeFingerprint(line);
    if (isFingerprintHex(value)) return value;
  }
  return null;
}

// --- adb install next steps + device-test reminder ------------------------------

/// The exact `adb install -r` command for one staged signed APK — the
/// operator's next-step guidance after signing (device install + the
/// DB-migration test against the previously installed release happen BEFORE
/// the release is published — the natural run order is script 1, device
/// work, script 2).
String adbInstallCommand({required String versionName, required String abi}) =>
    'adb install -r ${stagedPublishPath(versionName: versionName, abi: abi)}';

/// The adb install commands for all three published ABI splits, device
/// targets first: armeabi-v7a (the typical device default) and arm64-v8a
/// (modern devices) before the x86_64 emulator line.
List<String> adbInstallNextSteps(String versionName) => [
  for (final abi in releaseAbis)
    adbInstallCommand(versionName: versionName, abi: abi),
];

/// The ordering reminder printed with the adb commands: the device work is
/// a gate in front of the publish — with the two-script split it is the
/// literal break between the helpers.
String deviceTestBeforePublishReminder() =>
    'Device test BEFORE publishing: install the SIGNED APK on the test '
    'device and run the DB-migration check against the previously installed '
    'release — only then create the GitHub release (docs/release.md '
    'checklist is the authority; in the two-script flow this device work is '
    'the break between tool/download_and_sign.dart and '
    'tool/publish_release.dart).';

// --- post-release info -------------------------------------------------------------

/// The post-publish info block as a pure line list: the release URL, the
/// F-Droid verification URL per published versionCode, the upgrade-test
/// reminder, and the exact staged `adb install -r` commands (device pair —
/// armeabi-v7a/arm64-v8a — first, x86_64 last); the freshly signed APKs are
/// the new device-upgrade test.
List<String> postReleaseInfoLines(String tag, List<int> versionCodes) => [
  '',
  'Release assets attached: '
      'https://github.com/$releaseRepo/releases/tag/$tag',
  '',
  'F-Droid verification URLs (the authority for byte-reproducibility):',
  for (final versionCode in versionCodes)
    '  https://verification.f-droid.org/'
        'io.github.benediktburger.cycleapp_$versionCode.apk.json',
  '',
  'Upgrade test reminder: the freshly signed APKs count as a new '
      'device-upgrade test — install these exact files over the previous '
      'release before signing off (docs/release.md checklist is the '
      'authority).',
  ...adbInstallNextSteps(tagToVersion(tag)),
];

/// Prints the post-publish info block (see [postReleaseInfoLines]).
void printPostReleaseInfo(String tag, List<int> versionCodes) {
  for (final line in postReleaseInfoLines(tag, versionCodes)) {
    print(line);
  }
}
