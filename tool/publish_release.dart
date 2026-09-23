// Release helper 2 of 2 (the publish half): `dart run tool/publish_release.dart
// vX.Y.Z [--dry-run]`.
//
// It consumes EXACTLY the build/gh-release/ tree that
// tool/download_and_sign.dart staged: the handoff manifest
// build/gh-release/source.json (tag, versionName, versionCodeBase, runId,
// headSha — written at the END of a complete signing run) plus the three
// signed APKs under their publish names. Everything here fails loudly when
// the staging tree is missing, empty, or describes another tag — a stale or
// copied staging directory is the same wrong-asset risk as a version
// mismatch. It re-resolves NO run and consults NO Android SDK and NO
// keystore: the head SHA it tags with comes from the manifest, so the
// release is dated to the exact commit CI built even when newer runs landed
// on the release branch or `flutter clean` aged build/ci-artifacts/ away.
//
// What it does: real checksums (`sha256sum` per staged APK — computable
// read-only, which is what makes the rehearsal exact); release assembly —
// missing release → `gh release create vX.Y.Z <staged apks> --target
// <headSha from the manifest> --generate-notes --notes-file <notes body
// with the fingerprint line + fresh checksum lines>` (that one command
// authors the TAG too, at the manifest's head SHA — tag, release, and
// signed assets appear atomically), existing release → `gh release upload
// --clobber` + checksum splice into the fetched notes body; post-release PR
// plumbing (release/vX.Y.Z → development, `gh pr merge --merge --auto`,
// lenient already-exists handling, SOFT-FAIL — once the release is out, PR
// failures print the exact manual commands and never abort the run); post
// info (one F-Droid verification URL per split versionCode from the
// manifest's versionCodeBase, the upgrade-test reminder, the exact adb
// install lines).
//
// `--dry-run` (print-only, the rehearsal the download helper deliberately
// does not have): prints the manifest fields as resolved, the REAL per-APK
// checksums computed from the staged files (no `<computed-on-the-real-run>`
// placeholders — checksums are computable without mutating anything), the
// would-be create (with `--target`) or `--clobber`+spliced-edit payloads
// with the would-be (resp. spliced) notes body, and the PR payloads —
// before any mutating step; it never touches the release or the PRs.
//
// Parser/semantics split with the download helper: the lenient certificate-
// fingerprint parser (apksigner output) and the pubspec/envelope decoding
// live with tool/download_and_sign.dart; the checksum splice, the notes
// body, and the gh release/PR payloads live here. The lenient
// "already exists" / "Not Found" narrow routes and the merge-commit PR
// convention carry over unchanged.
//
// Linux-release-machine note: this tool targets the project's Linux release
// machine — it shells out to `gh` (authenticated) and `sha256sum` only.
//
// Shared pieces (naming, tag/branch helpers, staged-APK validation,
// manifest codec, adb/info lines, the loud-failure exception) live in
// tool/release_names.dart.

// ignore_for_file: avoid_print

import 'dart:io';

import 'release_names.dart';

/// The base branch the post-release PR merges into: `development`, the
/// repo's integration branch (merge commits; the release commit must stay
/// an ancestor of it).
const String prBaseBranch = 'development';

const String usage =
    'usage: dart run tool/publish_release.dart vX.Y.Z [--dry-run]';

/// Parsed command line.
class Options {
  const Options({required this.tag, required this.dryRun});

  /// The release tag, `vX.Y.Z` — must agree with the handoff manifest's tag.
  final String tag;

  /// Check-only rehearsal: prints the manifest fields as resolved, the REAL
  /// per-APK checksums, and every would-be `gh` command — and stops before
  /// anything mutates the release or opens PRs.
  final bool dryRun;
}

/// Validates and normalizes the command line. Pure — throws [UsageException]
/// on anything unexpected. NOTE: there is deliberately NO `--run-id` here —
/// the run identity (and head SHA) comes from the handoff manifest, not from
/// a fresh run resolution.
Options parseArguments(List<String> arguments) {
  String? tag;
  var dryRun = false;

  for (final argument in arguments) {
    switch (argument) {
      case '--dry-run':
        dryRun = true;
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
      'the handoff manifest\'s staging and the GitHub release',
      usage: usage,
    );
  }
  return Options(tag: tag, dryRun: dryRun);
}

// --- plumbing -------------------------------------------------------------------

/// Combined stdout/stderr text of a failed process run (the script-local
/// twin of tool/download_and_sign.dart's helper — the split keeps both
/// scripts import-independent).
String processOutputText(ProcessResult result) =>
    '${result.stderr} ${result.stdout}'.trim();

// --- checksums --------------------------------------------------------------------

/// The digest from a `sha256sum <file>` output line (`<hash>  <file>`);
/// null when the output holds no token.
String? parseSha256sum(String sha256sumOutput) {
  final token = sha256sumOutput.trim().split(RegExp(r'\s+')).firstOrNull;
  if (token == null || token.isEmpty) return null;
  return token.toLowerCase();
}

/// The process layer the checksum computation runs through. Injectable so
/// the real-checksum dry-run can be exercised pure-seam.
typedef Sha256Runner = Future<ProcessResult> Function(List<String> arguments);

/// The real runner: `sha256sum <file>` (Linux release machine posture).
Future<ProcessResult> defaultSha256Runner(List<String> arguments) =>
    Process.run('sha256sum', arguments);

/// Real checksums for the staged APKs, keyed by publish name in attach
/// order. Read-only — this is what makes the `--dry-run` rehearsal able to
/// print exact, non-placeholder checksums. The per-APK `APK SHA-256:` lines
/// go through the injected [printer] (defaults to [print]) so they land in
/// the run's collected output rather than leaking past it.
Future<Map<String, String>> stagedChecksums({
  required Directory root,
  required String versionName,
  Sha256Runner? sha256Runner,
  Printer? printer,
}) async {
  final runSha256 = sha256Runner ?? defaultSha256Runner;
  final out = printer ?? (line) => print(line);
  final stagedPaths = stagedPublishPaths(versionName);
  final publishNames = publishApkNames(versionName);
  final shaByPublishName = <String, String>{};
  for (var i = 0; i < stagedPaths.length; i++) {
    final file = File('${root.path}/${stagedPaths[i]}');
    final result = await runSha256([file.path]);
    if (result.exitCode != 0) {
      throw ReleaseToolException(
        'sha256sum failed for ${stagedPaths[i]} (exit ${result.exitCode}):\n'
        '${processOutputText(result)}\n'
        '(this tool targets the Linux release machine by design)',
      );
    }
    final digest = parseSha256sum(result.stdout as String);
    if (digest == null) {
      throw ReleaseToolException(
        'could not parse the digest from sha256sum output for '
        '${stagedPaths[i]}:\n${result.stdout}',
      );
    }
    shaByPublishName[publishNames[i]] = digest;
    out('APK SHA-256: ${publishNames[i]} $digest');
  }
  return shaByPublishName;
}

// --- notes body + checksum splice (checksum lines are this script's domain) -------

/// Assembles the GitHub release notes body: the certificate fingerprint line
/// (single release key shared by all three APKs) plus one checksum line per
/// published APK name, in map order (the asset order). On `gh release create
/// --generate-notes` the auto-generated changelog is appended after this
/// body (documented behavior the runbook relies on).
String buildNotesBody({
  required String certificateFingerprint,
  required Map<String, String> apkSha256ByPublishName,
}) {
  final buffer = StringBuffer(
    'SHA-256 certificate fingerprint: '
    '${normalizeFingerprint(certificateFingerprint)}\n',
  );
  apkSha256ByPublishName.forEach((publishName, sha256) {
    buffer.write('APK SHA-256: $publishName ${normalizeFingerprint(sha256)}\n');
  });
  return buffer.toString();
}

/// A checksum line as assembled by [buildNotesBody] (one per published APK).
final RegExp _checksumLinePattern = RegExp(
  r'^APK SHA-256:[ \t]+(\S+)[ \t]+[0-9a-fA-F]+[ \t]*$',
);

/// Splices freshly computed checksum lines into a fetched release body:
/// the whole existing `APK SHA-256:` block is removed and the fresh block is
/// put exactly where the first old checksum line stood — everything else
/// (fingerprint line, changelog, prose) is preserved byte-for-byte. A body
/// without checksum lines gets the fresh block appended, and stale checksum
/// lines for names no longer published vanish along with the block.
String spliceChecksumLines(
  String releaseBody,
  Map<String, String> freshShaByPublishName,
) {
  final lines = releaseBody.split('\n');
  final checksumIndexes = <int>[
    for (var i = 0; i < lines.length; i++)
      if (_checksumLinePattern.hasMatch(lines[i])) i,
  ];
  final freshLines = [
    for (final entry in freshShaByPublishName.entries)
      'APK SHA-256: ${entry.key} ${normalizeFingerprint(entry.value)}',
  ];

  if (checksumIndexes.isEmpty) {
    final needsLeadingNewline =
        releaseBody.isNotEmpty && !releaseBody.endsWith('\n');
    return '$releaseBody${needsLeadingNewline ? '\n' : ''}'
        '${freshLines.join('\n')}\n';
  }
  final result = <String>[];
  for (var i = 0; i < lines.length; i++) {
    if (i == checksumIndexes.first) {
      result.addAll(freshLines);
      continue;
    }
    if (checksumIndexes.contains(i)) {
      // Other old checksum lines are dropped in favor of the fresh block.
      continue;
    }
    result.add(lines[i]);
  }
  return result.join('\n');
}

/// The notes file this script stages into [ghReleaseStagingDir] (gitignored)
/// and feeds to `gh release edit/create --notes-file`.
String notesFilePath(String tag) => '$ghReleaseStagingDir/notes-$tag.md';

// --- release-existence probe --------------------------------------------------------

/// The process layer the gh invocations run through. Injectable so fetch
/// and the soft-fail PR contract can be tested pure-seam (no real gh).
typedef GhRunner = Future<ProcessResult> Function(List<String> arguments);

/// The real runner: shelling out to gh, handing back the process result
/// (the plumbing below does all the deciding).
Future<ProcessResult> defaultGhRunner(List<String> arguments) =>
    Process.run('gh', arguments);

/// Output sink for the PR plumbing, the checksum and staged-APK prints, and
/// the end-to-end prints (defaults to [print]; the tests inject a collecting
/// sink so the soft-fail contract stays assertable).
typedef Printer = void Function(String line);

/// Whether a failed `gh release view` plausibly means "no release exists for
/// this tag yet": a missing release surfaces as an API 404, and gh prints it
/// with "Not Found" in its error line (matched case-insensitively and
/// deliberately lenient, same convention as the PR "already exists" route —
/// gh CLI and API wording both carry the phrase). Transient (auth, network,
/// rate-limit) failures must never match: mistaking them for "release
/// missing" would re-create a release instead of using the existing one.
bool releaseMissing(String ghErrorOutput) =>
    ghErrorOutput.toLowerCase().contains('not found');

/// Whether a release for [tag] exists. Returns the body of the release when
/// it does; null when gh reports the release as missing (the narrowed
/// "not found" route — the caller then takes the create path). Any other gh
/// failure aborts loudly: it must not be mistaken for "release does not
/// exist".
Future<String?> fetchReleaseBody(String tag, {GhRunner? ghRunner}) async {
  final runGh = ghRunner ?? defaultGhRunner;
  final result = await runGh([
    'release',
    'view',
    tag,
    '--repo',
    releaseRepo,
    '--json',
    'body',
    '-q',
    '.body',
  ]);
  if (result.exitCode == 0) {
    return (result.stdout as String).trim();
  }
  if (!releaseMissing(processOutputText(result))) {
    throw ReleaseToolException(
      'gh release view for $tag failed (exit ${result.exitCode}):\n'
      '${processOutputText(result)}\n'
      'Only a clean "Not Found" answer may take the release-create path; '
      'this failure looks transient or environmental — resolve it and '
      'rerun before anything is attached.',
    );
  }
  return null;
}

// --- dry-run payloads ----------------------------------------------------------

/// The `gh release create` payload shown on a tag whose release does not
/// exist yet: the tag, all staged APKs in attach order,
/// `--target <headSha>` (the command authors the tag too, pointing at the
/// exact commit CI built — here: the manifest's headSha), a notes-file
/// hint, and the would-be notes body.
String formatDryRunGhCreateCommand(
  String tag,
  List<String> apkPaths,
  String notesBody, {
  required String headSha,
}) {
  return 'gh release create $tag ${apkPaths.join(' ')} '
      '--repo $releaseRepo --target $headSha --generate-notes '
      '--notes-file ${notesFilePath(tag)}\n'
      "-- (this command also creates the tag $tag, pointing at the commit "
      'the CI run built: $headSha)\n'
      '-- notes body:\n'
      '$notesBody';
}

/// The would-be `gh pr create` + `gh pr merge --auto` payloads shown before
/// any mutating step (the rehearsal prints the PR plumbing, never runs it).
String formatDryRunPrCommands({required String branch, required String tag}) {
  return 'gh pr create --repo $releaseRepo --base $prBaseBranch '
      '--head $branch --title "Release $tag" '
      '--body "${prCreateBody(tag)}"\n'
      'gh pr merge --merge --auto $branch (merge-commit method; needs '
      '"Allow auto-merge" in the repository settings)';
}

/// The `gh release upload` + `gh release edit` payloads shown on a tag
/// whose release exists (re-attach path), followed by the would-be updated
/// notes body.
String formatDryRunGhUpdateCommands(
  String tag,
  List<String> apkPaths,
  String updatedBody,
) {
  return 'gh release upload $tag ${apkPaths.join(' ')} --clobber\n'
      'gh release edit $tag --notes-file ${notesFilePath(tag)}\n'
      '-- updated notes body:\n'
      '$updatedBody';
}

// --- post-release PR plumbing (soft-fail) -------------------------------------

/// The one-line body for the release-branch → [prBaseBranch] pull request:
/// one sentence on what the PR carries, the release URL, and why the merge
/// method is fixed.
String prCreateBody(String tag) =>
    'Merge the release branch back into $prBaseBranch: the release branch '
    'carries the version bump (+ any release-only commits). Release: '
    'https://github.com/$releaseRepo/releases/tag/$tag. Merge commit only — '
    'the release commit (the commit CI built, which the tag created at '
    'publish time points at) must stay an ancestor of $prBaseBranch.';

/// argv for opening the release-branch → [prBaseBranch] pull request:
/// `gh pr create --repo BenediktBurger/cycle-app --base development
/// --head release/vX.Y.Z --title "Release vX.Y.Z" --body …`.
List<String> prCreateArguments({required String branch, required String tag}) =>
    [
      'pr',
      'create',
      '--repo',
      releaseRepo,
      '--base',
      prBaseBranch,
      '--head',
      branch,
      '--title',
      'Release $tag',
      '--body',
      prCreateBody(tag),
    ];

/// argv for queueing the auto-merge with the merge-commit method:
/// `gh pr merge --merge --auto <branch>` (never squash/rebase — the release
/// commit itself must become an ancestor of development; this mirrors the
/// repo's own merge-commit history).
List<String> prAutoMergeArguments(String branch) => [
  'pr',
  'merge',
  '--merge',
  '--auto',
  branch,
];

/// Whether `gh pr create` output indicates that a pull request for the
/// head branch already exists (rerun safety: in that case the plumbing
/// continues straight to the auto-merge step instead of reporting a
/// failure). Matched case-insensitively and deliberately lenient: both `gh`
/// CLI and API wording contain "already exists".
bool prAlreadyExists(String ghOutput) =>
    ghOutput.toLowerCase().contains('already exists');

/// Post-release PR automation (both publish routes: create AND re-attach):
/// open `release/vX.Y.Z` → development and queue the auto-merge.
///
/// SOFT-FAIL by design: the release itself (tag + assets + notes) is already
/// published at this point, so a PR failure must NOT abort the run with
/// exit 1 — every failure below is printed together with the exact manual
/// remediation command, and the function returns normally so the run
/// finishes at exit 0.
Future<void> openReleasePr({
  required String branch,
  required String tag,
  GhRunner? ghRunner,
  Printer? printer,
}) async {
  final runGh = ghRunner ?? defaultGhRunner;
  final out = printer ?? (line) => print(line);

  out('');
  out(
    'PR plumbing: getting the published release branch back into '
    '$prBaseBranch (pull request + queued auto-merge, merge-commit method).',
  );

  final create = await runGh(prCreateArguments(branch: branch, tag: tag));
  if (create.exitCode == 0) {
    out(
      'opened the pull request into $prBaseBranch: '
      '${(create.stdout as String).trim()}',
    );
  } else {
    final ghOutput = processOutputText(create);
    if (prAlreadyExists(ghOutput)) {
      out(
        'a pull request from $branch into $prBaseBranch already exists — '
        'continuing with the auto-merge step.',
      );
    } else {
      out(
        'gh pr create failed (exit ${create.exitCode}): $ghOutput\n'
        'The release itself is already published — a soft failure the '
        'publish path does not treat as fatal. Create the pull request by '
        'hand when convenient:\n'
        '  gh pr create --repo $releaseRepo --base $prBaseBranch '
        '--head $branch --title "Release $tag" '
        '--body "${prCreateBody(tag)}"',
      );
    }
  }

  final merge = await runGh(prAutoMergeArguments(branch));
  if (merge.exitCode == 0) {
    out('auto-merge queued (merge-commit method); CI gates the merge.');
  } else {
    out(
      'gh pr merge failed (exit ${merge.exitCode}): '
      '${processOutputText(merge)}\n'
      'The release itself is already published — a soft failure the '
      'publish path does not treat as fatal. Queue the auto-merge by hand '
      'when convenient (requires "Allow auto-merge" in the GitHub '
      'repository settings):\n'
      '  gh pr merge --merge --auto $branch',
    );
  }
}

// --- staged-tree consumption (stage 1) --------------------------------------------

/// Stage 1 of the publish flow, as a sandbox-testable unit: reads the
/// handoff manifest from [root], validates it loudly ([decodeHandoffManifest]),
/// cross-checks it against the requested [tag], and then requires every
/// staged APK (the staged lines go through the injected [printer]). Any
/// failure aborts the run before a single checksum is computed.
HandoffManifest consumeStagedRelease({
  required Directory root,
  required String tag,
  Printer? printer,
}) {
  final manifestFile = File('${root.path}/$handoffManifestPath');
  if (!manifestFile.existsSync()) {
    throw ReleaseToolException(
      '$handoffManifestPath is missing — build/gh-release/ is staged by '
      '`dart run tool/download_and_sign.dart $tag`; run it first (the '
      'manifest plus the non-empty staged APK set together mean "a '
      'complete signing run happened for this tag").',
    );
  }
  final HandoffManifest manifest;
  try {
    manifest = decodeHandoffManifest(manifestFile.readAsStringSync());
  } on ReleaseToolException catch (error) {
    throw ReleaseToolException(
      '$handoffManifestPath is invalid — ${error.message}\n'
      'Re-run `dart run tool/download_and_sign.dart $tag` to restage the '
      'staging dir for $tag.',
    );
  }
  if (manifest.tag != tag) {
    throw ReleaseToolException(
      'TAG MISMATCH: $handoffManifestPath describes ${manifest.tag}, but '
      'the requested release is $tag — a stale or copied '
      '$ghReleaseStagingDir is the same wrong-asset risk as a version '
      'mismatch; run `dart run tool/download_and_sign.dart $tag` to '
      'restage for $tag.',
    );
  }
  requireStagedApks(
    root: root,
    versionName: manifest.versionName,
    sink: printer,
  );
  return manifest;
}

// --- fresh-release fingerprint line ------------------------------------------------

/// Loud helper for the create path: turns pin-file content into the
/// normalized pinned fingerprint for the fresh notes body (the re-attach
/// path keeps the body's existing fingerprint line instead of reading the
/// pin file).
String pinnedFingerprintForNotes({required String pinFileContent}) {
  final pinned = parsePinFile(pinFileContent);
  if (pinned == null) {
    throw ReleaseToolException(
      '$pinFilePath exists but contains no 64-hex fingerprint line — the '
      'fresh release notes carry the fingerprint line; fix the pin file by '
      'hand (bare hex, lowercase; `#` comments allowed).',
    );
  }
  return pinned;
}

void main(List<String> arguments) async {
  try {
    await runPublishRelease(arguments);
  } on ReleaseToolException catch (error) {
    stderr.writeln('ERROR: ${error.message}');
    exit(1);
  }
}

Future<void> runPublishRelease(
  List<String> arguments, {
  GhRunner? ghRunner,
  Sha256Runner? sha256Runner,
  Printer? printer,
  Directory? root,
}) async {
  final options = parseArguments(arguments);
  final tag = options.tag;
  final repoRoot = root ?? Directory.current;
  final out = printer ?? (line) => print(line);
  final runGh = ghRunner ?? defaultGhRunner;

  out(
    'Publish helper for $tag — consumes the build/gh-release/ staging tree '
    '(signed APKs + handoff manifest, staged by '
    '`dart run tool/download_and_sign.dart`; docs/release.md).',
  );

  // --- preconditions ---------------------------------------------
  out('preconditions …');
  final authStatus = await runGh(['auth', 'status']);
  if (authStatus.exitCode != 0) {
    throw ReleaseToolException(
      'gh auth status failed (exit ${authStatus.exitCode}):\n'
      '${processOutputText(authStatus)}\n'
      'Authenticate gh before publishing (this helper needs no Android SDK '
      'and no keystore — everything Android already happened in '
      'tool/download_and_sign.dart).',
    );
  }
  out('gh auth: authenticated');

  // --- stage 1: consume build/gh-release loudly ----------------------------
  final manifest = consumeStagedRelease(
    root: repoRoot,
    tag: tag,
    printer: printer,
  );
  out(
    'handoff manifest resolved: tag=${manifest.tag} '
    'versionName=${manifest.versionName} '
    'versionCodeBase=${manifest.versionCodeBase} runId=${manifest.runId} '
    'headSha=${manifest.headSha}',
  );

  // --- stage 2: checksums for real (read-only) --------------------------------
  final shaByPublishName = await stagedChecksums(
    root: repoRoot,
    versionName: manifest.versionName,
    sha256Runner: sha256Runner,
    printer: printer,
  );
  out('');

  // --- stage 3: release assembly ---------------------------------------------
  final existingBody = await fetchReleaseBody(tag, ghRunner: runGh);
  if (options.dryRun) {
    // Print-only rehearsal: the checksums above are real; every payload
    // below carries them exactly as the real run would.
    out(
      'dry run: the manifest and staged APKs above were validated and '
      'the checksums above were computed for real — nothing below '
      'touches the release.',
    );
    out('');
    if (existingBody == null) {
      final freshBody = buildNotesBody(
        certificateFingerprint: _pinnedNotesFingerprint(repoRoot),
        apkSha256ByPublishName: shaByPublishName,
      );
      out(
        formatDryRunGhCreateCommand(
          tag,
          stagedPublishPaths(manifest.versionName),
          freshBody,
          headSha: manifest.headSha,
        ),
      );
    } else {
      out(
        formatDryRunGhUpdateCommands(
          tag,
          stagedPublishPaths(manifest.versionName),
          spliceChecksumLines(existingBody, shaByPublishName),
        ),
      );
    }
    out('');
    out(formatDryRunPrCommands(branch: releaseBranchForTag(tag), tag: tag));
    out('');
    out('dry run complete — nothing was uploaded or edited.');
    return;
  }

  if (existingBody == null) {
    // Tagless flow, publish half: this one command authors the TAG (pointing
    // at the exact commit CI built, via the manifest's headSha) and the
    // release with the signed assets — tag, release, and assets appear
    // atomically; no dangling tag if this fails. No tag exists beforehand.
    final freshBody = buildNotesBody(
      certificateFingerprint: _pinnedNotesFingerprint(repoRoot),
      apkSha256ByPublishName: shaByPublishName,
    );
    final notesFile = notesFilePath(tag);
    final stagedNotesFile = File('${repoRoot.path}/$notesFile');
    await stagedNotesFile.parent.create(recursive: true);
    await stagedNotesFile.writeAsString(freshBody);
    final createArguments = [
      'release',
      'create',
      tag,
      ...stagedPublishPaths(manifest.versionName),
      '--repo',
      releaseRepo,
      '--target',
      manifest.headSha,
      '--generate-notes',
      '--notes-file',
      notesFile,
    ];
    final create = await runGh(createArguments);
    if (create.exitCode != 0) {
      throw ReleaseToolException(
        'gh release create failed (exit ${create.exitCode}): '
        '${processOutputText(create)}\n'
        'The staged APKs remain under $ghReleaseStagingDir — retry '
        '`gh ${createArguments.join(' ')}` (the command also creates the '
        'tag $tag, pointing at the commit CI built: ${manifest.headSha}) '
        'or inspect first.',
      );
    }
    out('created the release: ${(create.stdout as String).trim()}');
  } else {
    final updatedBody = spliceChecksumLines(existingBody, shaByPublishName);
    final notesFile = notesFilePath(tag);
    final stagedNotesFile = File('${repoRoot.path}/$notesFile');
    await stagedNotesFile.parent.create(recursive: true);
    await stagedNotesFile.writeAsString(updatedBody);
    final uploadArguments = [
      'release',
      'upload',
      tag,
      ...stagedPublishPaths(manifest.versionName),
      '--clobber',
      '--repo',
      releaseRepo,
    ];
    final upload = await runGh(uploadArguments);
    if (upload.exitCode != 0) {
      throw ReleaseToolException(
        'gh release upload failed (exit ${upload.exitCode}): '
        '${processOutputText(upload)}\n'
        'The staged APKs remain under $ghReleaseStagingDir — retry '
        '`gh ${uploadArguments.join(' ')}`.',
      );
    }
    out('uploaded the APKs over the existing release (with --clobber).');
    final editArguments = [
      'release',
      'edit',
      tag,
      '--repo',
      releaseRepo,
      '--notes-file',
      notesFile,
    ];
    final edit = await runGh(editArguments);
    if (edit.exitCode != 0) {
      throw ReleaseToolException(
        'gh release edit failed (exit ${edit.exitCode}): '
        '${processOutputText(edit)}\n'
        'The APKs are uploaded, but the notes still carry the old '
        'checksums — retry `gh ${editArguments.join(' ')}`.',
      );
    }
    out('release notes updated with the fresh checksum lines.');
  }

  // --- stage 4: post-release PR plumbing (soft-fail, BOTH routes) --------------
  // Runs after BOTH routes above — a create and a re-attach both leave the
  // release published, so both open/refresh the release-branch PR. SOFT-FAIL
  // by design: PR plumbing failures print manual commands and keep exit 0.
  await openReleasePr(
    branch: releaseBranchForTag(tag),
    tag: tag,
    ghRunner: runGh,
    printer: out,
  );

  // --- stage 5: post-release info ----------------------------------------------
  printPostReleaseInfo(tag, [
    for (final abi in releaseAbis)
      manifest.versionCodeBase * 10 + abiCodes[abi]!,
  ]);
}

/// Reads [pinFilePath] under [repoRoot] for the fresh notes body's
/// fingerprint line; loud when missing/unparsable. The re-attach route
/// never calls this (the spliced body keeps its fingerprint line).
String _pinnedNotesFingerprint(Directory repoRoot) {
  final pinFile = File('${repoRoot.path}/$pinFilePath');
  if (!pinFile.existsSync()) {
    throw ReleaseToolException(
      '$pinFilePath is missing — the fresh release notes carry the pinned '
      'fingerprint line (the F-Droid verification anchor); restore the pin '
      'file from the repository before publishing.',
    );
  }
  return pinnedFingerprintForNotes(pinFileContent: pinFile.readAsStringSync());
}
