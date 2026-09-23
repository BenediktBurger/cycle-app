// Release helper 1 of 2 (docs/release.md's local half, everything through
// signing): `dart run tool/download_and_sign.dart vX.Y.Z [--run-id <id>]`.
//
// It resolves the Release workflow run (a push of a release/** branch —
// convention release/v<semver> — or a workflow_dispatch starts the CI build;
// NO tag exists at build time and the artifact versions come from
// pubspec.yaml), captures the run's head SHA, cross-checks the run commit's
// own pubspec against the requested vX.Y.Z, downloads the three per-ABI
// unsigned artifacts, validates them (aapt), signs them locally with the
// release keystore, verifies the signature against the pinned release key,
// stages the signed APKs under build/gh-release/ under their publish names,
// writes the handoff manifest build/gh-release/source.json, and prints the
// adb install lines for the device test — where it ENDS.
//
// The other half lives in tool/publish_release.dart: it consumes
// build/gh-release/ (manifest + staged APKs), computes checksums, assembles
// the GitHub release (its create command authors the tag at the manifest's
// head SHA), opens the release-branch PR, and prints the post-release info.
// The device-test break between the two helpers is deliberate: script 1
// runs, the operator installs the signed APK and runs the DB-migration test,
// and only then does script 2 touch the release. There is no `--dry-run`
// here BY DESIGN: this helper mutates nothing outside gitignored
// directories (build/ci-artifacts/, build/gh-release/), so a rehearsal
// would only repeat itself — passing --dry-run is an unknown-flag
// UsageException (the publish script's --dry-run is the one rehearsal).
//
// Hard invariants, never bypassable, loud abort (exit 1) on violation:
// 1. the requested `vX.Y.Z` matches the `version: X.Y.Z+N` line of
//    pubspec.yaml AT THE CI RUN'S OWN COMMIT (fetched via the GitHub
//    contents API — the local checkout may sit on any branch, so the local
//    pubspec is deliberately NOT consulted). A half-committed bump or the
//    wrong run is how wrong-version APKs get published;
// 2. every signed APK's certificate fingerprint MUST equal the pinned value
//    in tool/release_fingerprint.txt (the F-Droid buildserver's signature
//    copying and the metadata `AllowedAPKSigningKeys` both rely on this) —
//    the lenient apksigner-output parser lives here with the gate;
// 3. apksigner comes from the newest build-tools directory ≤ 34: build-tools
//    ≥ 35 produces signatures the F-Droid buildserver's signature-copying
//    step cannot handle (fdroiddata#3299) — the affected build would not be
//    flagged but silently skipped, hence the hard cap.
//
// The signing key never touches CI: the CI artifacts carry the documented
// debug-signing fallback signature, and apksigner REPLACES those signature
// blocks during signing — they never reach the published assets. Keystore
// passwords are only ever entered interactively (apksigner's own prompt) or
// via the APKSIGNER_STORE_PASSWORD environment variable — never a committed
// file.
//
// Determinism: before staging is finalized, the first APK is signed a
// second time and compared byte-for-byte with the staged one (apksigner's
// v2/v3 signatures carry no timestamp by default); any difference aborts
// the run loudly.
//
// Linux-release-machine note: this tool targets the project's Linux release
// machine — it shells out to `gh` (authenticated) and the Android SDK
// build-tools binaries (apksigner, aapt; resolved under $ANDROID_HOME or
// $ANDROID_SDK_ROOT). The publish half needs none of that: it only wants an
// authenticated `gh` and `sha256sum`.
//
// The pieces shared with the publish half (naming, tag/branch helpers,
// staged-APK validation, adb/info lines, handoff-manifest codec, the shared
// loud-failure exception) live in tool/release_names.dart.

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'release_names.dart';

/// Release signing keystore, relative to `$HOME`, and the key alias inside
/// it — the operator's release key per docs/release.md.
const String keystoreTildePath = '~/keystores/cycleapp-release.jks';
const String keystoreAlias = 'cycleapp-release';

/// Environment variable for scripted runs: keystore store password, passed
/// to apksigner as `--ks-pass env:APKSIGNER_STORE_PASSWORD`. Never a
/// committed file; when absent, apksigner prompts interactively instead.
const String keystorePasswordEnvVar = 'APKSIGNER_STORE_PASSWORD';

/// The workflow name the release pipeline declares; matched against
/// `gh run list --workflow` output.
const String releaseWorkflowName = 'Release';

/// Gitignored download directory for the CI workflow artifacts (the run's
/// unsigned APKs land here before signing).
const String ciArtifactsDir = 'build/ci-artifacts';

/// Hard cap on the apksigner build-tools major version.
const int maxApksignerBuildToolsMajor = 34;

const String usage =
    'usage: dart run tool/download_and_sign.dart vX.Y.Z [--run-id <id>]';

/// Parsed command line.
class Options {
  const Options({required this.tag, required this.runId});

  /// The release tag, `vX.Y.Z`.
  final String tag;

  /// Explicit workflow-run id (`--run-id`): skips the `gh run list` lookup
  /// and downloads from exactly this run (e.g. a re-run whose artifact set
  /// is the intended one — the v0.2.1 re-attach path).
  final int? runId;
}

/// Validates and normalizes the command line. Pure — throws [UsageException]
/// on anything unexpected. NOTE: there is no `--dry-run` in this helper on
/// purpose (see the header) — the flag lands in the default branch and is
/// rejected as an unknown flag.
Options parseArguments(List<String> arguments) {
  String? tag;
  int? runId;

  for (var i = 0; i < arguments.length; i++) {
    final argument = arguments[i];
    switch (argument) {
      case '--run-id':
        if (i + 1 >= arguments.length) {
          throw UsageException(
            'missing value for --run-id (expected a numeric workflow run id)',
            usage: usage,
          );
        }
        final value = arguments[++i];
        final id = int.tryParse(value);
        if (id == null || id < 0) {
          throw UsageException(
            '--run-id must be a numeric workflow run id (got "$value")',
            usage: usage,
          );
        }
        if (runId != null) {
          throw UsageException('--run-id given twice', usage: usage);
        }
        runId = id;
      default:
        if (argument.startsWith('-')) {
          throw UsageException('unknown flag: $argument', usage: usage);
        }
        if (tag != null) {
          throw UsageException(
            'exactly one tag argument expected (got "$tag" and "$argument")',
            usage: usage,
          );
        }
        tag = argument;
    }
  }
  if (tag == null) {
    throw UsageException('missing version tag argument', usage: usage);
  }
  if (!isValidReleaseTag(tag)) {
    throw UsageException(
      'tag must have the form vX.Y.Z (got "$tag") — the tag name identifies '
      'the workflow run\'s artifacts and the GitHub release',
      usage: usage,
    );
  }
  return Options(tag: tag, runId: runId);
}

// --- CI artifact names (this helper only) --------------------------------------

/// The CI artifact name for one ABI split of [versionName]: the upload name
/// of the release workflow — `cycle-app-<version>-<abi>-unsigned`.
String artifactName({required String versionName, required String abi}) =>
    'cycle-app-$versionName-$abi-unsigned';

/// All three CI artifact names, in release asset order.
List<String> artifactNames(String versionName) => [
  for (final abi in releaseAbis)
    artifactName(versionName: versionName, abi: abi),
];

/// The ABI encoded in an artifact or publish name
/// (`cycle-app-<version>-<abi>[-unsigned].apk`); the version part is
/// digits/dots only, so everything between it and the known suffix is the
/// ABI; null when the remainder is no known ABI.
String? abiFromArtifactName(String name) {
  const prefix = 'cycle-app-';
  const unsignedSuffix = '-unsigned';
  var core = name;
  if (core.endsWith('.apk')) {
    core = core.substring(0, core.length - '.apk'.length);
  }
  if (!core.startsWith(prefix)) return null;
  core = core.substring(prefix.length);
  if (core.endsWith(unsignedSuffix)) {
    core = core.substring(0, core.length - unsignedSuffix.length);
  }
  final separator = core.indexOf('-');
  if (separator == -1) return null;
  final abi = core.substring(separator + 1);
  return abiCodes.containsKey(abi) ? abi : null;
}

// --- release-run selection ---------------------------------------------------

/// Selects the release-workflow run for [branch] from `gh run list --json`
/// output ([runListJson]).
///
/// gh emits runs newest-first, so the first entry matching the branch's
/// release-workflow run wins. An explicit `--run-id` (the [Options.runId]
/// override) never reaches this function: the caller resolves it beforehand
/// and skips the `gh run list` round-trip entirely — the override needs no
/// branch expectations at all.
int resolveRunId({required String? runListJson, required String branch}) {
  final dynamic decoded;
  try {
    decoded = jsonDecode(runListJson ?? '');
  } on FormatException catch (error) {
    throw ReleaseToolException(
      'could not parse `gh run list` output as JSON: ${error.message}',
    );
  }
  if (decoded is! List) {
    throw ReleaseToolException(
      'unexpected `gh run list` output — wanted a JSON array of runs.',
    );
  }
  for (final run in decoded) {
    if (run is! Map) continue;
    final workflowName = (run['workflowName'] ?? run['name']) as String?;
    final headBranch = run['headBranch'] as String?;
    final databaseId = run['databaseId'];
    if (workflowName == releaseWorkflowName &&
        headBranch == branch &&
        databaseId is int) {
      return databaseId;
    }
  }
  throw ReleaseToolException(
    'no release workflow run found for branch $branch — the CI build starts '
    'on a push of a release/** branch (naming convention release/v<semver>, '
    'e.g. release/v0.2.1 — is the version bumped on the branch named '
    '$branch?) or is re-run by workflow_dispatch. Check '
    '`gh run list --repo $releaseRepo --workflow $releaseWorkflowName`, '
    'rerun the workflow, or pass the run explicitly with --run-id <id>.',
  );
}

// --- head-SHA capture ----------------------------------------------------------

/// The run's head commit SHA from `gh run view <id> --json headSha` output:
/// extracted from the JSON envelope's `headSha` field (the `-q .headSha`
/// raw-string form is tolerated just as well). Normalized to lowercase
/// 40-char hex — the exact shape the handoff manifest's `headSha` needs (the
/// publish script feeds it to `gh release create --target`). Loud failure on
/// anything else: a wrong SHA would mis-point the published tag.
String parseHeadSha(String runViewOutput) {
  final text = runViewOutput.trim();
  if (text.isEmpty) {
    throw ReleaseToolException(
      'empty `gh run view` output — no head SHA to author the tag with.',
    );
  }
  String? sha;
  try {
    final decoded = jsonDecode(text);
    if (decoded is Map && decoded['headSha'] is String) {
      sha = decoded['headSha'] as String;
    }
  } on FormatException {
    // Not JSON — treat the whole output as the raw `-q .headSha` value.
  }
  final candidate = (sha ?? text).trim().toLowerCase();
  if (RegExp(r'^[0-9a-f]{40}$').hasMatch(candidate)) return candidate;
  throw ReleaseToolException(
    'could not read a 40-char head SHA from `gh run view` output '
    '(got "${(sha ?? text).trim()}") — inspect the run by hand before '
    'publishing; a wrong SHA would point the tag away from the commit '
    'CI built.',
  );
}

// --- pubspec at the run's commit -------------------------------------------------

/// Decodes the default JSON envelope of
/// `gh api repos/<repo>/contents/pubspec.yaml?ref=<headSha>` into the raw
/// pubspec.yaml text: jsonDecode → base64 `content` → utf8. GitHub pads the
/// base64 payload with line breaks; the decoder ignores those. Loud failure
/// on a non-JSON answer or a missing/invalid `content` field — a silent
/// fallback of any kind would validate the wrong commit's version.
String decodePubspecEnvelope(String apiOutput) {
  final text = apiOutput.trim();
  final dynamic decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException catch (error) {
    throw ReleaseToolException(
      'could not parse the pubspec.yaml contents-API answer as JSON: '
      '${error.message} (raw: "${text.length > 80 ? '${text.substring(0, 80)}…' : text}")',
    );
  }
  if (decoded is! Map || decoded['content'] is! String) {
    throw ReleaseToolException(
      'the pubspec.yaml contents-API answer carries no base64 `content` '
      'field (raw: "${text.isEmpty ? '<empty>' : text}") — is the ref valid '
      'and does pubspec.yaml exist at the run\'s commit?',
    );
  }
  final compacted = (decoded['content'] as String)
      .replaceAll('\n', '')
      .replaceAll('\r', '')
      .trim();
  try {
    return utf8.decode(base64Decode(compacted));
  } on FormatException {
    throw ReleaseToolException(
      'the pubspec.yaml contents-API answer carries an unparsable base64 '
      '`content` payload.',
    );
  }
}

/// The loud cross-check failure when the run commit's pubspec disagrees with
/// the requested release version (a wrong run or a half-committed version
/// bump); null when consistent.
String? runPubspecProblem({
  required String versionName,
  required PubspecVersion runPubspec,
}) {
  if (runPubspec.name == versionName) return null;
  return 'VERSION MISMATCH: the CI run\'s pubspec.yaml declares '
      '${runPubspec.name}+${runPubspec.build}, but the requested release '
      'version is $versionName — wrong run or a half-committed version '
      'bump; resolve it before signing or publishing (the local checkout\'s '
      'pubspec is deliberately not consulted — the release is validated '
      'against the commit CI actually built).';
}

// --- build-tools resolution ---------------------------------------------------

/// Applies the hard cap: picks the numerically newest build-tools directory
/// name whose first version component is at most [maxMajor]. Non-version
/// entries are ignored. Loud error when nothing qualifies — e.g. only
/// build-tools ≥ 35 installed — naming the cap and the remedy.
String selectBuildToolsVersion(
  Iterable<String> directoryNames, {
  int maxMajor = maxApksignerBuildToolsMajor,
}) {
  String? best;
  List<int>? bestKey;
  for (final name in directoryNames) {
    final key = _versionKey(name);
    if (key == null) continue;
    if (key.first > maxMajor) continue;
    if (bestKey == null || _compareVersionKeys(key, bestKey) > 0) {
      best = name;
      bestKey = key;
    }
  }
  if (best == null) {
    throw ReleaseToolException(
      'no build-tools directory with version ≤ 34 found — apksigner must '
      'come from build-tools ≤ 34, because a 35+ apksigner signature cannot '
      'be handled by the F-Droid buildserver\'s signature copying (the '
      'affected build would be silently skipped, not just flagged). Install '
      'a build-tools 34.x via the SDK manager and retry.',
    );
  }
  return best;
}

/// Numeric version components, or null for non-version names (negative and
/// non-numeric parts are rejected).
List<int>? _versionKey(String name) {
  final key = <int>[];
  for (final part in name.split('.')) {
    final value = int.tryParse(part);
    if (value == null) return null;
    key.add(value);
  }
  return key;
}

int _compareVersionKeys(List<int> a, List<int> b) {
  for (var i = 0; i < math.max(a.length, b.length); i++) {
    final left = i < a.length ? a[i] : 0;
    final right = i < b.length ? b[i] : 0;
    if (left != right) return left.compareTo(right);
  }
  return 0;
}

// --- fingerprint verification (the pin hard gate) -------------------------------

bool fingerprintsMatch(String pinned, String actual) =>
    normalizeFingerprint(pinned) == normalizeFingerprint(actual);

/// Extracts the SHA-256 certificate digest from `apksigner verify
/// --print-certs` output. The exact line format varies between apksigner
/// versions (spacing, colons, case) — the parser is deliberately lenient;
/// returns null when no plausible digest is found.
String? parseCertificateFingerprint(String apksignerOutput) {
  for (final rawLine in apksignerOutput.split('\n')) {
    final line = rawLine.trim();
    if (!line.contains('SHA-256') || !line.toLowerCase().contains('digest')) {
      continue;
    }
    final separator = line.indexOf(': ');
    if (separator == -1) continue;
    final value = normalizeFingerprint(line.substring(separator + 2));
    if (isFingerprintHex(value)) return value;
  }
  return null;
}

// --- aapt / pubspec version validation ----------------------------------------

/// Parsed `version: X.Y.Z+N` line from pubspec.yaml.
class PubspecVersion {
  const PubspecVersion(this.name, this.build);

  /// The versionName, `X.Y.Z`.
  final String name;

  /// The versionCode candidate (build number `+N`).
  final int build;
}

/// Extracts the `version: X.Y.Z+N` line from pubspec.yaml content; null when
/// absent or malformed.
PubspecVersion? parsePubspecVersion(String pubspecSource) {
  final match = RegExp(
    r'^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$',
    multiLine: true,
  ).firstMatch(pubspecSource);
  if (match == null) return null;
  return PubspecVersion(
    '${match.group(1)}.${match.group(2)}.${match.group(3)}',
    int.parse(match.group(4)!),
  );
}

/// versionName/versionCode embedded in the APK (via `aapt dump badging`).
class ApkVersionInfo {
  const ApkVersionInfo({required this.versionName, required this.versionCode});

  final String versionName;
  final int versionCode;
}

/// Extracts `versionName`/`versionCode` from `aapt dump badging` output
/// (first `package:` line). Lenient about attribute order; null when either
/// value is missing.
ApkVersionInfo? parseAaptBadging(String badgingOutput) {
  final versionCode = RegExp(
    r"versionCode='(\d+)'",
  ).firstMatch(badgingOutput)?.group(1);
  final versionName = RegExp(
    r"versionName='([^']*)'",
  ).firstMatch(badgingOutput)?.group(1);
  if (versionCode == null || versionName == null) return null;
  return ApkVersionInfo(
    versionName: versionName,
    versionCode: int.parse(versionCode),
  );
}

/// The expected split versionCode: pubspec build number N times 10 plus the
/// ABI offset, mirroring android/app/build.gradle.kts.
int expectedSplitVersionCode(int buildNumber, int abiCode) =>
    buildNumber * 10 + abiCode;

/// Whether the embedded version of a downloaded APK matches the expected
/// split scheme. Returns the loud failure message, or null when the APK is
/// fit to sign.
String? apkVersionProblem({
  required ApkVersionInfo info,
  required String versionName,
  required int expectedVersionCode,
}) {
  if (info.versionName != versionName) {
    return 'VERSION MISMATCH: the downloaded APK embeds versionName '
        '"${info.versionName}", expected "$versionName" (from the tag) — '
        'wrong run or artifact, never sign it.';
  }
  if (info.versionCode != expectedVersionCode) {
    return 'VERSIONCODE MISMATCH: the downloaded APK embeds versionCode '
        '${info.versionCode}, expected $expectedVersionCode (split scheme: '
        'pubspec build number N * 10 + abiCode — see '
        'android/app/build.gradle.kts) — wrong run or artifact, never sign '
        'it.';
  }
  return null;
}

// --- plumbing helpers -----------------------------------------------------------

/// Combined stdout/stderr text of a failed process run. (Its equivalents
/// also live, script-locally, in tool/publish_release.dart — the split
/// keeps both scripts import-independent.)
String processOutputText(ProcessResult result) =>
    '${result.stderr} ${result.stdout}'.trim();

/// Runs an external command and fails loudly on a non-zero exit, naming the
/// step that failed.
Future<ProcessResult> _run(
  String executable,
  List<String> arguments,
  String failurePrefix,
) async {
  final result = await Process.run(executable, arguments);
  if (result.exitCode != 0) {
    throw ReleaseToolException(
      '$failurePrefix (exit ${result.exitCode}):\n'
      '${processOutputText(result)}',
    );
  }
  return result;
}

/// The keystore path for the current environment: `~` in [keystoreTildePath]
/// expanded against the runtime `$HOME` (checked by the caller).
File keystoreFile({required String home}) =>
    File('$home/${keystoreTildePath.substring(1)}');

/// Runs a gh subcommand and fails loudly on a non-zero exit.
Future<ProcessResult> _gh(List<String> arguments) async {
  final result = await Process.run('gh', arguments);
  if (result.exitCode != 0) {
    throw ReleaseToolException(
      'gh ${arguments.join(' ')} failed (exit ${result.exitCode}):\n'
      '${processOutputText(result)}',
    );
  }
  return result;
}

Never _fail(String message) => throw ReleaseToolException(message);

// --- sign command display + determinism ------------------------------------------------

/// The would-be apksigner sign command line for one APK (displayed before
/// the password handling decides the `--ks-pass` form).
String formatSignCommand({
  required String apksigner,
  required String ksPath,
  required String outPath,
  required String inputPath,
}) {
  return '$apksigner sign --ks $ksPath --ks-key-alias $keystoreAlias '
      '[--ks-pass env:$keystorePasswordEnvVar] '
      '--out $outPath $inputPath';
}

/// Byte-for-byte comparison of two signed outputs (`cmp` semantics).
bool bytesIdentical(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The failure message when the double-sign determinism sanity disagrees.
String determinismFailureMessage({required String publishName}) =>
    'SIGN DETERMINISM FAILURE: signing the same input twice produced '
    'different bytes for $publishName — apksigner output must be '
    'reproducible before anything is attached. Check the build-tools '
    'version and apksigner inputs, then rerun.';

// --- the end-of-run pointer (script 1 ends at the device-test break) --------------

/// The end-of-run block after the handoff manifest: it names the publish
/// half and its optional rehearsal. Pure for tests; [runDownloadAndSign]
/// prints it.
List<String> publishNextStepLines({required String tag}) => [
  '',
  'Next step — publish (after the device test above passed):',
  '  dart run tool/publish_release.dart $tag',
  '  (optional rehearsal: dart run tool/publish_release.dart $tag '
      '--dry-run — it prints every would-be gh command with the REAL '
      'checksums from the staged files)',
];

// --- handoff-manifest write (the helper's final side effect) ------------------------

/// Pure write seam for stage 10's side effect (sandbox-tested): encodes
/// [manifest] with the shared codec and writes it under [root] at the
/// settled relative path. Only ever called after [requireStagedApks]
/// passed, so a present, valid manifest plus the non-empty staged set
/// together mean "a complete signing run happened for this tag".
void writeHandoffManifest({
  required Directory root,
  required HandoffManifest manifest,
}) {
  final file = File('${root.path}/$handoffManifestPath');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync('${encodeHandoffManifest(manifest)}\n');
}

void main(List<String> arguments) async {
  try {
    await runDownloadAndSign(arguments);
  } on ReleaseToolException catch (error) {
    stderr.writeln('ERROR: ${error.message}');
    exit(1);
  }
}

Future<void> runDownloadAndSign(List<String> arguments) async {
  final options = parseArguments(arguments);
  final tag = options.tag;
  final versionName = tagToVersion(tag);
  final artifactNameList = artifactNames(versionName);
  final stagedPaths = stagedPublishPaths(versionName);

  print(
    'Download-and-sign helper for $tag — download the unsigned CI release '
    'artifacts, validate, sign locally, stage them for publishing '
    '(docs/release.md; the publish half is tool/publish_release.dart).',
  );

  // --- stage 1: preconditions ---------------------------------------------
  print('preconditions …');
  final authStatus = await _gh(['auth', 'status']);
  print('gh auth: ${authStatus.stdout.isNotEmpty ? 'authenticated' : 'ok'}');
  final androidHome =
      Platform.environment['ANDROID_HOME'] ??
      Platform.environment['ANDROID_SDK_ROOT'];
  if (androidHome == null || androidHome.isEmpty) {
    _fail(
      'ANDROID_HOME is not set — cannot locate the Android SDK build-tools '
      '(apksigner/aapt).',
    );
  }
  final home = Platform.environment['HOME'];
  if (home == null || home.isEmpty) {
    _fail('HOME is not set — cannot locate the release keystore.');
  }
  final keystoreResolved = keystoreFile(home: home);
  if (!keystoreResolved.existsSync()) {
    _fail(
      'keystore ${keystoreResolved.path} not found (expected '
      '$keystoreTildePath) — the release signing key must sit at the '
      'runbook path (docs/release.md).',
    );
  }
  final pinFile = File(pinFilePath);
  if (!pinFile.existsSync()) {
    _fail(
      '$pinFilePath missing — the pinned release-certificate fingerprint is '
      'the signing hard gate (docs/release.md).',
    );
  }
  final pinnedFingerprint = parsePinFile(await pinFile.readAsString());
  if (pinnedFingerprint == null) {
    _fail(
      '$pinFilePath exists but contains no 64-hex fingerprint line — fix it '
      'by hand (bare hex, lowercase; `#` comments allowed).',
    );
  }
  print('pinned release-certificate fingerprint: $pinnedFingerprint');

  // --- stage 2: resolve the workflow run ------------------------------------
  final int runId;
  if (options.runId != null) {
    runId = options.runId!;
    print(
      '--run-id override: $runId (skips the release-branch match '
      'entirely — no branch expectations)',
    );
  } else {
    final branch = releaseBranchForTag(tag);
    final runList = await _gh([
      'run',
      'list',
      '--repo',
      releaseRepo,
      '--workflow',
      releaseWorkflowName,
      '--json',
      'databaseId,headBranch,workflowName,status',
    ]);
    runId = resolveRunId(
      runListJson: (runList.stdout as String).trim(),
      branch: branch,
    );
  }
  print('release workflow run for $tag: $runId');

  // --- stage 3: capture the run's head SHA -------------------------------------
  // The head SHA feeds the handoff manifest, whose headSha is the --target
  // the publish script tags with. This runs BEFORE the pubspec check — the
  // pubspec comes from this commit, not from the local checkout.
  final runView = await _gh([
    'run',
    'view',
    '$runId',
    '--repo',
    releaseRepo,
    '--json',
    'headSha',
  ]);
  final headSha = parseHeadSha((runView.stdout as String).trim());
  print('run head SHA: $headSha');

  // --- stage 4: pubspec sanity at the run's commit ----------------------------
  // The local checkout may sit on any branch, so the version is validated
  // against the run's OWN commit via the GitHub contents API. Pubspec check
  // after run/SHA resolution: its input IS the run's head SHA.
  final pubspecApi = await _gh([
    'api',
    'repos/$releaseRepo/contents/pubspec.yaml?ref=$headSha',
  ]);
  final runPubspecSource = decodePubspecEnvelope(
    (pubspecApi.stdout as String).trim(),
  );
  final runPubspec = parsePubspecVersion(runPubspecSource);
  if (runPubspec == null) {
    _fail(
      'pubspec.yaml at the run\'s commit (head SHA $headSha) has no '
      '`version: X.Y.Z+N` line — the versionCode scheme needs the build '
      'number; fix the pubspec and rerun the CI build.',
    );
  }
  print(
    'pubspec at the run\'s commit: ${runPubspec.name}+${runPubspec.build}; '
    'requested release version: $versionName (tag: $tag)',
  );
  final pubspecProblem = runPubspecProblem(
    versionName: versionName,
    runPubspec: runPubspec,
  );
  if (pubspecProblem != null) {
    _fail(pubspecProblem);
  }

  // --- stage 5: download the three unsigned artifacts ------------------------
  print('downloading artifacts into $ciArtifactsDir …');
  await Directory(ciArtifactsDir).create(recursive: true);
  final downloadedApkByArtifact = <String, String>{};
  for (final artifactNameOnce in artifactNameList) {
    final destination = '$ciArtifactsDir/$artifactNameOnce';
    final destinationDirectory = Directory(destination);
    if (destinationDirectory.existsSync()) {
      // gh refuses to overwrite existing files — a previous run's leftover
      // must not shadow the fresh download.
      await destinationDirectory.delete(recursive: true);
    }
    await destinationDirectory.create(recursive: true);
    final result = await Process.run('gh', [
      'run',
      'download',
      '$runId',
      '--repo',
      releaseRepo,
      '--name',
      artifactNameOnce,
      '--dir',
      destination,
    ]);
    if (result.exitCode != 0) {
      _fail(
        'could not download artifact "$artifactNameOnce" from run $runId — '
        'is it missing, or is $runId not a $releaseWorkflowName workflow '
        'run?\n'
        'gh output: ${processOutputText(result)}\n'
        'Remedies: rerun the workflow (a push of $tag\'s release branch or '
        'workflow_dispatch), or pick the right run with --run-id <id>.',
      );
    }
    final files = destinationDirectory
        .listSync(recursive: true)
        .whereType<File>()
        .toList();
    if (files.length != 1) {
      _fail(
        'expected exactly one APK file inside $destination for '
        '"$artifactNameOnce", found ${files.length} entries — unexpected '
        'artifact layout; inspect $destination by hand.',
      );
    }
    downloadedApkByArtifact[artifactNameOnce] = files.single.path;
    print('  $artifactNameOnce → ${files.single.path}');
  }

  // --- stage 6: build-tools resolution (hard cap ≤ 34) ------------------------
  final buildToolsRoot = Directory('$androidHome/build-tools');
  if (!buildToolsRoot.existsSync()) {
    _fail(
      'no build-tools under $androidHome — install the Android SDK '
      'build-tools (apksigner/aapt); check ANDROID_HOME.',
    );
  }
  final buildToolsVersion = selectBuildToolsVersion(
    buildToolsRoot.listSync().whereType<Directory>().map(
      (directory) =>
          directory.path.substring(directory.path.lastIndexOf('/') + 1),
    ),
  );
  final buildToolsBin = '${buildToolsRoot.path}/$buildToolsVersion';
  final apksignerPath = '$buildToolsBin/apksigner';
  if (!File(apksignerPath).existsSync()) {
    _fail('apksigner not found at $apksignerPath.');
  }
  final aaptPath = '$buildToolsBin/aapt';
  if (!File(aaptPath).existsSync()) {
    _fail(
      'aapt not found at $aaptPath — the downloaded APKs cannot be '
      'validated without it.',
    );
  }
  print(
    'build-tools: $buildToolsBin (apksigner hard-capped at ≤ 34: a '
    'build-tools ≥ 35 signature cannot be handled by the F-Droid '
    'buildserver\'s signature copying).',
  );

  // --- stage 7: aapt validation of the downloaded artifacts --------------------
  for (var i = 0; i < releaseAbis.length; i++) {
    final abi = releaseAbis[i];
    final apkPath = downloadedApkByArtifact[artifactNameList[i]]!;
    final badging = await _run(aaptPath, [
      'dump',
      'badging',
      apkPath,
    ], 'aapt dump badging failed for $apkPath');
    final info = parseAaptBadging(badging.stdout as String);
    if (info == null) {
      _fail(
        'could not parse versionName/versionCode from `aapt dump badging` '
        'output for $apkPath — wrong or corrupt artifact.',
      );
    }
    final expectedVersionCode = expectedSplitVersionCode(
      runPubspec.build,
      abiCodes[abi]!,
    );
    final problem = apkVersionProblem(
      info: info,
      versionName: versionName,
      expectedVersionCode: expectedVersionCode,
    );
    if (problem != null) {
      _fail(problem);
    }
    print(
      'validated ${artifactNameList[i]}: '
      'versionName=${info.versionName} versionCode=${info.versionCode}',
    );
  }

  // --- stage 8: sign each APK into build/gh-release under its publish name ----
  print('signing …');
  final stagingDirectory = Directory(ghReleaseStagingDir);
  await stagingDirectory.create(recursive: true);
  final storePassword = Platform.environment[keystorePasswordEnvVar];
  final signArguments = <String>[
    'sign',
    '--ks',
    keystoreResolved.path,
    '--ks-key-alias',
    keystoreAlias,
  ];
  if (storePassword != null) {
    signArguments
      ..add('--ks-pass')
      ..add('env:$keystorePasswordEnvVar');
  } else {
    print(
      'no $keystorePasswordEnvVar in the environment — apksigner will prompt '
      'for the keystore password interactively (set the variable to script '
      'this run).',
    );
  }
  for (var i = 0; i < releaseAbis.length; i++) {
    final result = await Process.run(apksignerPath, [
      ...signArguments,
      '--out',
      stagedPaths[i],
      downloadedApkByArtifact[artifactNameList[i]]!,
    ]);
    if (result.exitCode != 0) {
      _fail(
        'apksigner sign failed for ${artifactNameList[i]} '
        '(exit ${result.exitCode}):\n'
        '${processOutputText(result)}',
      );
    }
    print('  signed → ${stagedPaths[i]}');
  }

  // --- stage 9: fingerprint pin hard gate + determinism sanity -----------------
  for (final path in stagedPaths) {
    final verify = await _run(apksignerPath, [
      'verify',
      '--print-certs',
      path,
    ], 'apksigner verify failed for $path (corrupt APK or failed signature)');
    final digest = parseCertificateFingerprint(verify.stdout as String);
    if (digest == null) {
      _fail(
        'could not parse a SHA-256 certificate digest from apksigner verify '
        'output for $path — inspect by hand before attaching anything.',
      );
    }
    if (!fingerprintsMatch(pinnedFingerprint, digest)) {
      _fail(
        'SIGNATURE MISMATCH for $path: signed with $digest, pinned release '
        'key is $pinnedFingerprint. Wrong keystore/alias — never attach. '
        '(The CI build\'s debug-signing fallback is replaced entirely by '
        'apksigner sign, so a debug or foreign fingerprint here means a '
        'wrong keystore.)',
      );
    }
    print('verified $path against the pinned release key: $digest');
  }

  // Determinism sanity: sign the first APK a second time, compare bytes.
  final firstArtifactName = artifactNameList.first;
  final sanityInput =
      '$ciArtifactsDir/$firstArtifactName-determinism-input.apk';
  await File(downloadedApkByArtifact[firstArtifactName]!).copy(sanityInput);
  final sanityOutput =
      '$ciArtifactsDir/$firstArtifactName-determinism-output.apk';
  final reSign = await Process.run(apksignerPath, [
    ...signArguments,
    '--out',
    sanityOutput,
    sanityInput,
  ]);
  if (reSign.exitCode != 0) {
    _fail(
      'the determinism re-sign of $firstArtifactName failed '
      '(exit ${reSign.exitCode}):\n'
      '${processOutputText(reSign)}',
    );
  }
  final stagedBytes = await File(stagedPaths.first).readAsBytes();
  final reSignedBytes = await File(sanityOutput).readAsBytes();
  if (!bytesIdentical(stagedBytes, reSignedBytes)) {
    _fail(
      determinismFailureMessage(
        publishName: publishApkNames(versionName).first,
      ),
    );
  }
  print(
    'determinism sanity: signing the first APK twice produced '
    'byte-identical output.',
  );

  // --- stage 10: finalize the staging set + the handoff manifest ---------------
  requireStagedApks(root: Directory.current, versionName: versionName);
  writeHandoffManifest(
    root: Directory.current,
    manifest: HandoffManifest(
      tag: tag,
      versionName: versionName,
      versionCodeBase: runPubspec.build,
      runId: runId,
      headSha: headSha,
    ),
  );
  print('handoff manifest written: $handoffManifestPath');

  // The device-test break: the operator installs the SIGNED APK and runs the
  // DB-migration test NOW; the publish half (script 2) comes after. Device
  // targets first, emulator last — same ordering as the old pre-publish
  // reminder block.
  print('');
  print(deviceTestBeforePublishReminder());
  for (final line in adbInstallNextSteps(versionName)) {
    print('  $line');
  }
  for (final line in publishNextStepLines(tag: tag)) {
    print(line);
  }
}
