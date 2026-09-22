// Publish script: per-release checklist step 7 of docs/release.md, as a
// command — `dart run tool/make_release.dart vX.Y.Z`.
//
// It performs checklist step 7 mechanically (tag + push + GitHub Release) and
// the sanity parts of the earlier steps (version/tag match, clean tree,
// release-signed APK, embedded version, checksum). It deliberately does NOT
// build (step 4), interactively eyeball the signature (step 5), or replace
// the device upgrade test (step 6) — those stay manual checklist work.
//
// Two hard invariants it enforces, never bypassable, loud abort (exit 1) on
// violation:
// 1. the `vX.Y.Z` tag matches the `version: X.Y.Z+N` line in pubspec.yaml —
//    a half-committed version bump is exactly how wrong-version APKs get
//    published;
// 2. the APK is signed with the pinned release certificate (SHA-256
//    fingerprint in tool/release_fingerprint.txt) — Gradle silently falls
//    back to debug signing when `android/key.properties` is missing, and a
//    debug-signed APK must never be attached to a public release.
//
// The installed Flutter SDK version is checked against tool/flutter-version
// the same way: that file is what the F-Droid build recipe parses from each
// tag, so the pin and the locally used SDK must not drift. A mismatch
// ALWAYS fails the run — there is no bypass. --accept-flutter-version is
// only the re-pin mechanism (also used for first-run staging): it rewrites
// the pin file from the installed SDK AND updates the flutter-version:
// inputs in .github/workflows/ci.yml (and .github/workflows/release.yml when
// present) to the same version, then stops; one commit collects the changed
// files, then rebuild the release APK and rerun. CI cross-checks the
// workflow input against the same pin.
//
// Linux-release-machine note: by design this tool targets the project's
// Linux release machine — it shells out to `sha256sum`, `git`, `gh`, and the
// Android SDK build-tools binaries (`apksigner`, `aapt`; resolved under
// $ANDROID_HOME or $ANDROID_SDK_ROOT), and reads stdin for the upgrade-test
// confirmation prompt.

// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math' as math;

/// Committed file pinning the release-certificate fingerprint (the trust
/// anchor; F-Droid metadata later cross-checks against the same value).
const String pinFilePath = 'tool/release_fingerprint.txt';

/// Committed file pinning the Flutter SDK version used for a release.
/// The F-Droid build recipe parses this file from the tagged commit, so
/// the release SDK is pinned exactly here.
const String flutterPinFilePath = 'tool/flutter-version';

/// Workflow files whose `flutter-version:` input must follow the pin:
/// [ciWorkflowPath] is the CI gate that cross-checks the pin (must exist),
/// [releaseWorkflowPath] is the parked release pipeline (skipped when
/// absent). Both are written by the script's pin-staging paths; their
/// committed content is otherwise untouched.
const String ciWorkflowPath = '.github/workflows/ci.yml';
const String releaseWorkflowPath = '.github/workflows/release.yml';

/// Release artifact built by checklist step 4 (`flutter build apk --release`).
const String defaultApkPath = 'build/app/outputs/flutter-apk/app-release.apk';

const String usage = 'usage: dart run tool/make_release.dart vX.Y.Z '
    '[--accept-fingerprint] [--accept-flutter-version] [--dry-run] '
    '[--tested]';

/// Failure of a script stage — always loud, always exit 1.
class ReleaseException implements Exception {
  ReleaseException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Bad command-line arguments — abort before any check runs.
class UsageException extends ReleaseException {
  UsageException(String message) : super('$message\n$usage');
}

/// Parsed command line.
class Options {
  const Options({
    required this.tag,
    required this.acceptFingerprint,
    required this.acceptFlutterVersion,
    required this.dryRun,
    required this.tested,
  });

  /// The release tag, `vX.Y.Z`.
  final String tag;

  /// First-run behavior: pin the APK's actual certificate fingerprint into
  /// [pinFilePath] and stop the run there — the freshly written pin leaves
  /// the working tree dirty, so the operator commits it and reruns (the
  /// rerun matches the APK against the pin and proceeds).
  final bool acceptFingerprint;

  /// First-run and re-pin behavior for the Flutter SDK version: stage the
  /// pin file ([flutterPinFilePath]) with the installed SDK's version and
  /// sync the `flutter-version:` inputs in the CI workflows
  /// ([ciWorkflowPath], and [releaseWorkflowPath] when present) to the same
  /// version, then stop the run — the operator commits the changed files
  /// (the pin and the workflows) and reruns (the F-Droid recipe parses the
  /// pin file from the tagged commit). This covers both the first-ever pin
  /// (file missing) and a re-pin when the installed SDK has drifted from
  /// the committed pin — a mismatch NEVER lets a run continue, with or
  /// without this flag. A dry run only prints the would-be pin and the
  /// would-be workflow updates and continues.
  final bool acceptFlutterVersion;

  /// Check-only mode: no tag, no push, no release, no prompts.
  final bool dryRun;

  /// Scripted use: assume the device upgrade test (checklist step 6) was
  /// done and skip the interactive confirmation.
  final bool tested;

  /// Consulted when the pin file is missing: the run on which
  /// `--accept-fingerprint` is honored writes the pin and then stops — the
  /// fresh pin leaves the tree dirty, and tag/push must only happen on a
  /// clean tree. A dry run only prints the would-be pin and continues.
  bool get stopsAfterWritingPin => acceptFingerprint && !dryRun;

  /// Consulted both for first-run staging (pin file missing) and for a
  /// re-pin (installed SDK drifted from the committed pin): the run on
  /// which `--accept-flutter-version` is honored rewrites the pin file with
  /// the installed SDK's version, syncs the workflow `flutter-version:`
  /// inputs to it, and then stops — the changed files leave the tree dirty,
  /// and tag/push must only happen on a clean tree. A dry run only prints
  /// the would-be changes and continues. Without the flag a mismatch (or a
  /// missing pin) always fails — there is no bypass.
  bool get stopsAfterWritingFlutterPin => acceptFlutterVersion && !dryRun;

  /// Whether the script interactively asks for the upgrade-test
  /// confirmation (checklist step 6). A dry run performs checks only and
  /// has no publishing side effects to gate, so it never prompts — a short
  /// note is printed instead.
  bool get promptsForUpgradeTest => !dryRun && !tested;
}

/// Parsed `version: X.Y.Z+N` line from pubspec.yaml.
class PubspecVersion {
  const PubspecVersion(this.name, this.build);

  /// The versionName, `X.Y.Z`.
  final String name;

  /// The versionCode candidate (build number `+N`).
  final int build;
}

/// versionName/versionCode embedded in the APK (via `aapt dump badging`).
class ApkVersionInfo {
  const ApkVersionInfo({required this.versionName, required this.versionCode});

  final String versionName;
  final int versionCode;
}

/// Validates and normalizes the command line. Pure — throws [UsageException]
/// on anything unexpected.
Options parseArguments(List<String> arguments) {
  String? tag;
  var acceptFingerprint = false;
  var acceptFlutterVersion = false;
  var dryRun = false;
  var tested = false;

  for (final argument in arguments) {
    switch (argument) {
      case '--accept-fingerprint':
        acceptFingerprint = true;
      case '--accept-flutter-version':
        acceptFlutterVersion = true;
      case '--dry-run':
        dryRun = true;
      case '--tested':
        tested = true;
      default:
        if (argument.startsWith('-')) {
          throw UsageException('unknown flag: $argument');
        }
        if (tag != null) {
          throw UsageException('exactly one tag argument expected '
              '(got "$tag" and "$argument")');
        }
        tag = argument;
    }
  }
  if (tag == null) {
    throw UsageException('missing version tag argument');
  }
  if (!isValidReleaseTag(tag)) {
    throw UsageException(
        'tag must have the form vX.Y.Z (got "$tag") — the tag name is the '
        'release identity the script pins to pubspec.yaml');
  }
  return Options(
    tag: tag,
    acceptFingerprint: acceptFingerprint,
    acceptFlutterVersion: acceptFlutterVersion,
    dryRun: dryRun,
    tested: tested,
  );
}

bool isValidReleaseTag(String tag) => RegExp(r'^v\d+\.\d+\.\d+$').hasMatch(tag);

/// `vX.Y.Z` → `X.Y.Z` (call only on validated tags).
String tagToVersion(String tag) => tag.substring(1);

/// The central invariant: tag name == pubspec versionName.
bool tagMatchesVersion(String tag, String versionName) =>
    tagToVersion(tag) == versionName;

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

/// Canonical form of a certificate fingerprint: no colons, no whitespace,
/// lowercase hex.
String normalizeFingerprint(String raw) =>
    raw.replaceAll(':', '').replaceAll(RegExp(r'\s'), '').toLowerCase();

bool isFingerprintHex(String value) =>
    RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

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

/// Extracts `versionName`/`versionCode` from `aapt dump badging` output
/// (first `package:` line). Lenient about attribute order; null when either
/// value is missing.
ApkVersionInfo? parseAaptBadging(String badgingOutput) {
  final versionCode =
      RegExp(r"versionCode='(\d+)'").firstMatch(badgingOutput)?.group(1);
  final versionName =
      RegExp(r"versionName='([^']*)'").firstMatch(badgingOutput)?.group(1);
  if (versionCode == null || versionName == null) return null;
  return ApkVersionInfo(
    versionName: versionName,
    versionCode: int.parse(versionCode),
  );
}

/// Reads the pin file content: skips comment (`#`) and blank lines, takes the
/// first remaining line as the fingerprint, normalized. Null when nothing
/// plausible remains.
String? parsePinFile(String pinFileContent) {
  for (final rawLine in pinFileContent.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final value = normalizeFingerprint(line);
    if (isFingerprintHex(value)) return value;
  }
  return null;
}

/// Formats the committed pin file: a documented comment header plus the bare
/// normalized fingerprint.
String formatPinFile(String fingerprint) {
  final hex = normalizeFingerprint(fingerprint);
  return '# Pinned SHA-256 certificate fingerprint of the release signing '
      'key\n'
      '# (trust anchor for the release notes; F-Droid metadata cross-checks '
      'against\n'
      '# the same value — see docs/release.md). Written by\n'
      '# `dart run tool/make_release.dart --accept-fingerprint`.\n'
      '$hex\n';
}

/// Whether `value` is a bare `X.Y.Z` version string (`^\d+\.\d+\.\d+$`).
bool isValidFlutterVersion(String value) =>
    RegExp(r'^\d+\.\d+\.\d+$').hasMatch(value);

/// Extracts the installed SDK version from `flutter --version` output
/// (`Flutter X.Y.Z • channel …`). Null when no version is found or the
/// found value is not a valid `X.Y.Z` string.
String? parseInstalledFlutterVersion(String flutterVersionOutput) {
  final version = RegExp(r'Flutter (\d+\.\d+\.\d+)')
      .firstMatch(flutterVersionOutput)
      ?.group(1);
  if (version == null) return null;
  return isValidFlutterVersion(version) ? version : null;
}

/// Reads the pinned Flutter version ([flutterPinFilePath] content): skips
/// comment (`#`) and blank lines and takes the LAST remaining line — the
/// same semantics as the CI check's `grep -v '^#' … | tail -n 1`. Validated
/// against [isValidFlutterVersion]; null when nothing valid remains.
String? parseFlutterPinFile(String pinFileContent) {
  String? last;
  for (final rawLine in pinFileContent.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    last = line;
  }
  if (last == null) return null;
  return isValidFlutterVersion(last) ? last : null;
}

/// Formats the committed Flutter pin file: a documented comment header plus
/// the bare version line. Same shape as [formatPinFile].
String formatFlutterPinFile(String version) {
  return '# Pinned Flutter SDK version for the local release path '
      '(ADR-0009) and CI —\n'
      '# must match the installed `flutter --version` (enforced by CI and '
      'by\n'
      '# tool/make_release.dart). On a bump, no fdroiddata edit is needed: '
      'the\n'
      '# F-Droid recipe parses this file from the tagged commit\n'
      '# (metadata/io.github.benediktburger.cycleapp.yml).\n'
      '$version\n';
}

/// Replaces every `flutter-version: …` line in [workflowSource] with
/// `[indent]flutter-version: [version]` (leading whitespace preserved) and
/// returns the rewritten source; null when no such line matches. Comment
/// lines (`# flutter-version: …`) never match — the `#` prefix keeps them
/// out of the anchored pattern. Write-only-when-changed on top of this
/// transform gives idempotency for free.
String? updateWorkflowFlutterVersion(String workflowSource, String version) {
  // [ \t]* (not \s*) after the colon keeps the match on one line: \s* could
  // span a newline when a value-less `flutter-version:` line is followed by
  // an indented line, and the rewrite would swallow that line.
  final pattern =
      RegExp(r'^([ \t]*)flutter-version:[ \t]*.*$', multiLine: true);
  if (!pattern.hasMatch(workflowSource)) return null;
  return workflowSource.replaceAllMapped(
      pattern, (match) => '${match.group(1)}flutter-version: $version');
}

/// One workflow file's validated sync plan: [originalSource] as read from
/// disk, [updatedSource] as [updateWorkflowFlutterVersion] rewrote it.
class WorkflowFileUpdate {
  const WorkflowFileUpdate({
    required this.path,
    required this.originalSource,
    required this.updatedSource,
  });

  /// Path relative to the repository root (e.g. `.github/workflows/ci.yml`).
  final String path;
  final String originalSource;
  final String updatedSource;

  /// False when the rewritten content equals what is on disk — nothing to
  /// write (idempotency).
  bool get changed => originalSource != updatedSource;
}

/// The validated workflow sync: files to (possibly) write plus the paths
/// that were skipped because the file is not present.
class WorkflowSyncPlan {
  const WorkflowSyncPlan({
    required this.updates,
    required this.skippedMissing,
  });

  final List<WorkflowFileUpdate> updates;
  final List<String> skippedMissing;
}

/// Reads and validates the workflow files under [root] BEFORE any write:
/// - [ciWorkflowPath] missing → [ReleaseException] (broken repo state: the
///   CI workflow is the gate that cross-checks the pin; a silent skip would
///   strip the sync protection while looking successful);
/// - an existing workflow file whose source exposes no matchable
///   `flutter-version:` line → [ReleaseException] naming the exact file and
///   the expected line shape (a merely logged skip would recreate the very
///   pin/input drift this sync exists to prevent);
/// - [releaseWorkflowPath] missing → listed in [WorkflowSyncPlan
///   .skippedMissing] (parked workflow; the pin invariant is enforced by
///   [ciWorkflowPath] alone).
Future<WorkflowSyncPlan> planFlutterWorkflowSync({
  required Directory root,
  required String version,
}) async {
  final updates = <WorkflowFileUpdate>[];
  final skippedMissing = <String>[];
  for (final path in const [ciWorkflowPath, releaseWorkflowPath]) {
    final file = File('${root.path}/$path');
    if (!file.existsSync()) {
      if (path == ciWorkflowPath) {
        _fail('$ciWorkflowPath not found — that workflow is the gate that '
            'cross-checks the $flutterPinFilePath pin, so it must exist. '
            'Without it the pin/workflow-input sync cannot be verified and '
            'the pin invariant stands unenforced. Nothing was written.');
      }
      skippedMissing.add(path);
      continue;
    }
    final source = await file.readAsString();
    final updated = updateWorkflowFlutterVersion(source, version);
    if (updated == null) {
      _fail('cannot sync the flutter-version: input in $path — the file '
          'contains no matchable `flutter-version: X.Y.Z` line (expected on '
          'its own line, as the input of the subosito/flutter-action step). '
          'The workflow must expose that line again before the pin can be '
          'rewritten; the tree was left untouched.');
    }
    updates.add(WorkflowFileUpdate(
      path: path,
      originalSource: source,
      updatedSource: updated,
    ));
  }
  return WorkflowSyncPlan(updates: updates, skippedMissing: skippedMissing);
}

/// The shared stop path of both pin-staging routes (first-ever pin and
/// re-pin on mismatch): validate the workflow sync FIRST, then write the
/// pin file, then update each workflow file whose content actually changes
/// (skipping unchanged ones — idempotent), then stop the run via
/// [flutterPinWriteStopMessage]. A malformed workflow therefore never
/// leaves behind a half-updated pin + workflow combination.
Future<Never> writeFlutterPinAndStop({
  required Directory root,
  required String version,
}) async {
  final plan = await planFlutterWorkflowSync(root: root, version: version);
  final pinFile = File('${root.path}/$flutterPinFilePath');
  await pinFile.parent.create(recursive: true);
  await pinFile.writeAsString(formatFlutterPinFile(version));
  for (final update in plan.updates) {
    if (!update.changed) {
      print('${update.path} already pins flutter-version: $version — '
          'left unchanged.');
      continue;
    }
    await File('${root.path}/${update.path}')
        .writeAsString(update.updatedSource);
    print('Set the flutter-version: input to $version in ${update.path}.');
  }
  for (final skipped in plan.skippedMissing) {
    print('$skipped is not present — skipped.');
  }
  _fail(flutterPinWriteStopMessage(version));
}

/// Dry-run note for both pin-staging routes: validates the workflow sync
/// (a dry run performs checks and may fail — that failure happens now,
/// before the real pin staging later), prints the would-be pin file content
/// and the would-be-updated workflow files, and writes nothing.
Future<void> printFlutterPinSyncDryRunNote({
  required Directory root,
  required String version,
}) async {
  final plan = await planFlutterWorkflowSync(root: root, version: version);
  print('dry-run note: outside a dry run, --accept-flutter-version would '
      'now write $flutterPinFilePath with:');
  print(formatFlutterPinFile(version));
  print('dry-run note: and set the flutter-version: input:');
  for (final update in plan.updates) {
    if (update.changed) {
      print('  ${update.path} — set to flutter-version: $version');
    } else {
      print('  ${update.path} — already flutter-version: $version '
          '(would be left unchanged)');
    }
  }
  for (final skipped in plan.skippedMissing) {
    print('dry-run note: $skipped is not present — skipped.');
  }
  print('dry-run note: continuing with the checks only, nothing written.');
}

/// Failure message for an installed-vs-pinned Flutter version mismatch
/// without `--accept-flutter-version`. A mismatch always fails the run —
/// this message is the remediation: switch the installed SDK to the pinned
/// version, or re-pin the installed version with the flag — that run
/// rewrites the pin and syncs the workflow inputs itself, so one commit
/// then collects all changed files, followed by rebuild and rerun.
String flutterPinMismatchMessage({
  required String installed,
  required String pinned,
}) {
  return 'FLUTTER VERSION MISMATCH: installed SDK $installed, pinned '
      '$pinned in $flutterPinFilePath. The run cannot continue — the pin '
      'file is what the F-Droid recipe parses from the tagged commit, and '
      'CI fails the tag when it has drifted from the used SDK. Fix it by '
      'either\n'
      '  (a) switching the installed Flutter SDK to the pinned version '
      '($pinned), or\n'
      '  (b) making $installed the new pin: rerun with '
      '--accept-flutter-version — that run rewrites $flutterPinFilePath '
      'and updates the flutter-version: input in the CI workflows '
      '(.github/workflows/ci.yml, and .github/workflows/release.yml when '
      'present) itself, then stops.\n'
      'Either way: commit all changed files (the pin and the workflow '
      'files), rebuild the release APK on that SDK (checklist step 4: '
      '`flutter build apk --release`), and rerun this script.';
}

/// Stop message after a successful re-pin (also the first-run staging
/// path): the pin file was rewritten with `version` and the workflow
/// `flutter-version:` inputs were synced to it; the run stops so the
/// operator commits all changed files, rebuilds, and reruns.
String flutterPinWriteStopMessage(String version) {
  return 'Wrote and pinned the installed SDK version $version in '
      '$flutterPinFilePath, and updated the flutter-version: input in '
      '.github/workflows/ci.yml (and in .github/workflows/release.yml when '
      'present) to $version. The run stops here — commit the pin and the '
      'updated workflow files:\n'
      '  git add $flutterPinFilePath .github/workflows/* && git commit '
      '-m "pin Flutter SDK version"\n'
      'Then rebuild the release APK on that SDK (checklist step 4: '
      '`flutter build apk --release`) and rerun this script: the F-Droid '
      'recipe parses the committed pin from the tagged commit, so the '
      'committed pin is what a Flutter-version bump publishes.\n'
      'Stopping keeps the tree clean — tag and push must not run with a '
      'fresh, uncommitted pin.';
}

/// Framework-free equivalent of the parked CI flow's
/// `ls build-tools/*/apksigner | sort -V | tail -1`: picks the numerically
/// newest build-tools directory name. Non-version entries are ignored; null
/// when nothing qualifies.
String? newestBuildToolsDirectory(Iterable<String> directoryNames) {
  String? best;
  List<int>? bestKey;
  for (final name in directoryNames) {
    final key = _versionKey(name);
    if (key == null) continue;
    if (bestKey == null || _compareVersionKeys(key, bestKey) > 0) {
      best = name;
      bestKey = key;
    }
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

/// Assembles the GitHub release notes body: the two machine-checkable trust
/// lines. `gh release create --generate-notes` appends the auto-generated
/// changelog after this body (documented behavior the runbook relies on).
String buildNotesBody({
  required String certificateFingerprint,
  required String apkSha256,
}) {
  return 'SHA-256 certificate fingerprint: '
      '${normalizeFingerprint(certificateFingerprint)}\n'
      'APK SHA-256: ${apkSha256.trim().toLowerCase()}\n';
}

Never _fail(String message) => throw ReleaseException(message);

/// The APK's SHA-256 checksum via the Linux `sha256sum` binary.
Future<String> _sha256sumOfApk() async {
  final result = await Process.run('sha256sum', [defaultApkPath]);
  if (result.exitCode != 0) {
    _fail('sha256sum failed (exit ${result.exitCode}): '
        '${result.stderr}\n'
        'This tool targets the Linux release machine by design.');
  }
  return (result.stdout as String).trim().split(RegExp(r'\s+')).first;
}

String _resolveAndroidHome() {
  final environment = Platform.environment;
  final home = environment['ANDROID_HOME'] ?? environment['ANDROID_SDK_ROOT'];
  if (home == null || home.isEmpty) {
    _fail('ANDROID_HOME is not set — cannot locate the Android SDK '
        'build-tools (apksigner/aapt).');
  }
  return home;
}

/// Resolves the newest `build-tools/<version>` directory like the parked CI
/// workflow does (`sort -V | tail -1`).
String _resolveNewestBuildTools(String androidHome) {
  final buildToolsRoot = Directory('$androidHome/build-tools');
  if (!buildToolsRoot.existsSync()) {
    _fail('no build-tools under $androidHome — install the Android SDK '
        'build-tools (checklist step 4 already built the APK, so the SDK '
        'must exist somewhere; check ANDROID_HOME).');
  }
  final names = buildToolsRoot
      .listSync()
      .whereType<Directory>()
      .map((directory) =>
          directory.path.substring(directory.path.lastIndexOf('/') + 1))
      .toList();
  final newest = newestBuildToolsDirectory(names);
  if (newest == null) {
    _fail('could not resolve a build-tools version directory under '
        '$androidHome/build-tools.');
  }
  return '${buildToolsRoot.path}/$newest';
}

void main(List<String> arguments) async {
  try {
    await runRelease(arguments);
  } on ReleaseException catch (error) {
    stderr.writeln('ERROR: ${error.message}');
    exit(1);
  }
}

Future<void> runRelease(List<String> arguments) async {
  final options = parseArguments(arguments);
  final tag = options.tag;
  final versionName = tagToVersion(tag);

  print('Release script — per-release checklist step 7 of docs/release.md '
      'for $tag.');

  // --- 1. version sanity (pubspec vs tag) --------------------------------
  final pubspecFile = File('pubspec.yaml');
  if (!pubspecFile.existsSync()) {
    _fail('pubspec.yaml not found — run from the repository root.');
  }
  final version = parsePubspecVersion(await pubspecFile.readAsString());
  if (version == null) {
    _fail('pubspec.yaml has no `version: X.Y.Z+N` line — fix the version '
        'bump before releasing.');
  }
  print('pubspec version: ${version.name}+${version.build}; tag: $tag');
  if (!tagMatchesVersion(tag, version.name)) {
    _fail('TAG/VERSION MISMATCH: tag $tag (versionName ${tagToVersion(tag)}) '
        'does not match pubspec.yaml (${version.name}). A half-committed '
        'bump publishes wrong-version APKs — fix pubspec.yaml or the tag.');
  }

  // --- 2. Flutter SDK pin (tool/flutter-version vs installed SDK) ---------
  // tool/flutter-version is what the F-Droid build recipe parses from the
  // tagged commit, so a pin that has drifted from the actually used SDK
  // would silently publish a different Flutter build than the one tested
  // locally. No `git` involvement here: the pin compares against the
  // installed binary, not the tag history.
  final flutterPinFile = File(flutterPinFilePath);
  final pinFileExists = flutterPinFile.existsSync();
  final pinnedFlutter = pinFileExists
      ? parseFlutterPinFile(await flutterPinFile.readAsString())
      : null;
  final flutterProbe = await Process.run('flutter', ['--version']);
  if (flutterProbe.exitCode != 0) {
    _fail('flutter --version failed (exit ${flutterProbe.exitCode}): '
        '${flutterProbe.stderr}\nCannot compare the installed SDK against '
        '$flutterPinFilePath.');
  }
  final installedFlutter =
      parseInstalledFlutterVersion(flutterProbe.stdout as String);
  if (installedFlutter == null) {
    _fail('could not parse an X.Y.Z version from `flutter --version` '
        'output:\n${flutterProbe.stdout}');
  }

  if (pinFileExists && pinnedFlutter == null) {
    _fail('pin file $flutterPinFilePath exists but contains no '
        'X.Y.Z version line — fix it by hand (`#` comments allowed) '
        'or delete it and rerun with --accept-flutter-version to pin '
        'the installed SDK ($installedFlutter).');
  }
  if (!pinFileExists) {
    print('NO FLUTTER VERSION PIN YET — the installed SDK is:');
    print('  Flutter SDK: $installedFlutter');
    if (options.stopsAfterWritingFlutterPin) {
      await writeFlutterPinAndStop(
        root: Directory.current,
        version: installedFlutter,
      );
    }
    if (!options.dryRun || !options.acceptFlutterVersion) {
      _fail('no pin file at $flutterPinFilePath and no '
          '--accept-flutter-version given — the pinned SDK version is '
          'required (an un-pinned SDK lets a Flutter upgrade silently '
          'change the release build). Make sure the installed SDK above '
          'is the one to release with, then rerun with '
          '--accept-flutter-version to pin it.');
    }
    await printFlutterPinSyncDryRunNote(
      root: Directory.current,
      version: installedFlutter,
    );
  } else {
    print('Flutter SDK: $installedFlutter; pinned in '
        '$flutterPinFilePath: $pinnedFlutter.');
    if (installedFlutter != pinnedFlutter) {
      // A drifted pin never lets the run continue (no bypass). The flag
      // doubles as the re-pin mechanism: as on the first-run path, it
      // rewrites the pin from the installed SDK, syncs the workflow
      // inputs, and stops for commit + rebuild + rerun; a dry run only
      // prints the would-be changes.
      if (options.stopsAfterWritingFlutterPin) {
        await writeFlutterPinAndStop(
          root: Directory.current,
          version: installedFlutter,
        );
      }
      if (options.acceptFlutterVersion && options.dryRun) {
        await printFlutterPinSyncDryRunNote(
          root: Directory.current,
          version: installedFlutter,
        );
      } else {
        _fail(flutterPinMismatchMessage(
          installed: installedFlutter,
          // Non-null here: the guard above fails the run on an unparsable
          // pin file before this branch is ever reached.
          pinned: pinnedFlutter!,
        ));
      }
    }
  }

  // --- 3. clean tree ------------------------------------------------------
  final status = await Process.run('git', [
    'status',
    '--porcelain',
  ]);
  if (status.exitCode != 0) {
    _fail('git status failed (exit ${status.exitCode}): ${status.stderr}');
  }
  final uncommitted = (status.stdout as String).trim();
  if (uncommitted.isNotEmpty) {
    _fail('dirty working tree — commit or stash everything before tagging. '
        'A half-committed version bump is how wrong-version APKs happen:\n'
        '$uncommitted');
  }

  // --- 4. tag must not exist ---------------------------------------------
  final existingTag = await Process.run('git', [
    'rev-parse',
    '-q',
    '--verify',
    'refs/tags/$tag',
  ]);
  if (existingTag.exitCode == 0) {
    _fail('tag $tag already exists locally (docs/release.md re-tag salvage '
        'pointer — note the runbook\'s parked-CI salvage flow does not map '
        '1:1 here because the artifact already exists). The right remedy: '
        '`git tag -d $tag` to remove the local tag; if it was already '
        'pushed: `git push origin :refs/tags/$tag`. Deleting a pushed tag is '
        'an operator decision — make it explicitly.');
  }

  // --- 5. the APK exists (built earlier, checklist step 4) ----------------
  final apk = File(defaultApkPath);
  if (!apk.existsSync()) {
    _fail('no release APK at $defaultApkPath — build it first (checklist '
        'step 4: `flutter build apk --release`). This script does not build.');
  }
  if (apk.lengthSync() == 0) {
    _fail('release APK at $defaultApkPath is empty — rebuild (checklist '
        'step 4).');
  }

  // --- 6. signature pin (debug-fallback / wrong-key guard) ----------------
  final buildTools = _resolveNewestBuildTools(_resolveAndroidHome());
  print('build-tools: $buildTools');

  final apksigner = '$buildTools/apksigner';
  if (!File(apksigner).existsSync()) {
    _fail('apksigner not found at $apksigner.');
  }
  final certs = await Process.run(apksigner, [
    'verify',
    '--print-certs',
    defaultApkPath,
  ]);
  if (certs.exitCode != 0) {
    _fail('apksigner verify failed (exit ${certs.exitCode}): '
        '${certs.stderr}');
  }
  final actualFingerprint = parseCertificateFingerprint(certs.stdout as String);
  if (actualFingerprint == null) {
    _fail('could not parse the SHA-256 certificate digest from apksigner '
        'output:\n${certs.stdout}');
  }

  final pinFile = File(pinFilePath);
  var fingerprint = actualFingerprint;
  if (pinFile.existsSync()) {
    final pinned = parsePinFile(await pinFile.readAsString());
    if (pinned == null) {
      _fail('pin file $pinFilePath exists but contains no fingerprint line '
          '— fix it by hand (bare hex, lowercase; `#` comments allowed).');
    }
    if (!fingerprintsMatch(pinned, actualFingerprint)) {
      _fail('SIGNATURE MISMATCH: the APK certificate fingerprint is '
          '$actualFingerprint, the pin file $pinFilePath expects $pinned. '
          'Wrong key or the debug-signing fallback — never publish. '
          '(Unexpectedly rekeyed? Correct the pin file after checking the '
          'new certificate; do not bypass this check.)');
    }
    print('certificate fingerprint matches pinned release key: '
        '$fingerprint');
  } else if (options.acceptFingerprint) {
    print('NO PIN FILE YET — the APK certificate fingerprint is:');
    print('  SHA-256 certificate fingerprint: $fingerprint');
    if (options.stopsAfterWritingPin) {
      await pinFile.writeAsString(formatPinFile(fingerprint));
      _fail('Wrote and pinned the fingerprint above in $pinFilePath. The '
          'run stops here — commit the pin, then rerun the script: the '
          'rerun matches the APK against the pin and proceeds.\n'
          '  git add $pinFilePath && git commit -m "pin release '
          'certificate fingerprint"\n'
          '(the fingerprint is public — it goes into the release notes '
          'anyway). Stopping keeps the tree clean — tag and push must not '
          'run with a fresh, uncommitted pin.');
    }
    print('dry-run note: outside a dry run, --accept-fingerprint would '
        'now write $pinFilePath and stop; the pin would be committed '
        'before the rerun proceeds.');
  } else {
    _fail('no pin file at $pinFilePath and no --accept-fingerprint given. '
        'Check that the APK certificate fingerprint below is your RELEASE '
        'key (a debug fingerprint means the key.properties debug-signing '
        'fallback struck — do NOT pin it), then rerun with '
        '--accept-fingerprint to pin it:\n'
        '  SHA-256 certificate fingerprint: $fingerprint');
  }

  // --- 7. embedded version check (best effort, via aapt) ------------------
  final aapt = '$buildTools/aapt';
  if (!File(aapt).existsSync()) {
    print('aapt not found at $aapt — embedded version check skipped '
        '(best-effort check).');
  } else {
    final badging = await Process.run(aapt, [
      'dump',
      'badging',
      defaultApkPath,
    ]);
    final info = badging.exitCode == 0
        ? parseAaptBadging(badging.stdout as String)
        : null;
    if (info == null) {
      print('WARNING: aapt output could not be parsed — embedded version '
          'check skipped.');
    } else {
      print('embedded APK version: versionName=${info.versionName} '
          'versionCode=${info.versionCode}');
      if (info.versionName != versionName) {
        _fail('STALE APK: embedded versionName "${info.versionName}" != '
            '$versionName — rebuild (checklist step 4) before publishing.');
      }
      if (info.versionCode != version.build) {
        print('WARNING: embedded versionCode ${info.versionCode} != pubspec '
            'build number ${version.build}. Equal is expected for the '
            'universal APK (ABI splits offset the code — see '
            'android/app/build.gradle.kts); not a hard abort, but '
            'double-check you are publishing the right artifact.');
      }
    }
  }

  // --- 8. checksum --------------------------------------------------------
  final apkSha = await _sha256sumOfApk();
  print('APK: $defaultApkPath');
  print('APK SHA-256: $apkSha');

  // --- 9. upgrade-test gate ------------------------------------------------
  // A dry run never reaches the question: it performs checks only and has
  // no publishing side effects to gate — it prints a note instead.
  if (options.promptsForUpgradeTest) {
    stdout.writeln(
        'Publishing NOW: tag $tag, push to origin, and create the GitHub '
        'release.');
    stdout.write('Has the device upgrade test (checklist step 6) been '
        'completed with THIS exact APK? Type "yes" to continue: ');
    final answer = stdin.readLineSync()?.trim().toLowerCase() ?? '';
    if (answer != 'yes') {
      _fail('upgrade-test confirmation not given — nothing was published. '
          'Complete the device upgrade test first (checklist step 6). '
          '--tested exists for scripted use and must never be used to skip '
          'the real test.');
    }
  } else if (options.dryRun) {
    print('dry-run note: on a real run without --tested, the script here '
        'asks for confirmation that the device upgrade test (checklist '
        'step 6) was done with this exact APK before publishing.');
  } else {
    print('upgrade test: asserted done via --tested.');
  }

  final notesBody = buildNotesBody(
    certificateFingerprint: fingerprint,
    apkSha256: apkSha,
  );

  // --- 10. dry run ----------------------------------------------------------
  if (options.dryRun) {
    print('');
    print('dry run — would publish with these values:');
    print('  tag:            $tag');
    print('  versionName:    $versionName');
    print('  versionCode:    ${version.build}');
    print('  fingerprint:    $fingerprint');
    print('  APK path:       $defaultApkPath');
    print('  APK SHA-256:    $apkSha');
    print('  gh command:     gh release create $tag $defaultApkPath '
        '--generate-notes --notes '
        '"${notesBody.trim().replaceAll('\n', '\\n')}"');
    print('nothing was tagged, pushed, or released.');
    return;
  }

  // --- 11. publish ---------------------------------------------------------
  Future<void> git(List<String> args) async {
    final result = await Process.run('git', args);
    if (result.exitCode != 0) {
      _fail('git ${args.join(' ')} failed (exit ${result.exitCode}): '
          '${result.stderr}');
    }
  }

  await git(['tag', tag]);
  print('tagged $tag at HEAD.');
  await git(['push', 'origin', tag]);
  print('pushed $tag to origin.');

  final release = await Process.run('gh', [
    'release',
    'create',
    tag,
    defaultApkPath,
    '--generate-notes',
    '--notes',
    notesBody,
  ]);
  if (release.exitCode != 0) {
    _fail('gh release create failed (exit ${release.exitCode}): '
        '${release.stderr}\nThe tag is already pushed; the release may not '
        "exist yet — retry `gh release create $tag $defaultApkPath "
        '--generate-notes --notes <body>` or inspect first (see '
        'docs/release.md).');
  }

  print('');
  print('Release published: ${release.stdout.trim()}');
  print('Next: checklist steps 8–9 of docs/release.md — distribute '
      '(sideload → testers, Play internal track, F-Droid MR) and watch the '
      'store dashboards.');
}
