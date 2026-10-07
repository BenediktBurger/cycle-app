// F-Droid changelog file generator for the fastlane metadata tree:
// `dart run tool/fdroid_changelog_links.dart [<repo-root>]`.
//
// Reads `version: X.Y.Z+N` from pubspec.yaml (the authoring names) and, for
// every locale under `fastlane/metadata/android/`, ensures the changelog
// names the stores key on exist:
//
// - `<versionName>.txt` — the authoring file; the release notes are
//   written by hand there (docs/release.md's changelog-files step).
// - `<N*10 + abiCode>.txt` for the three ABI splits (armeabi-v7a → 1,
//   arm64-v8a → 2, x86_64 → 3, mirroring android/app/build.gradle.kts) —
//   F-Droid matches a changelog file against every versionCode its Builds
//   entries produce, so each split versionCode needs its own file.
// - `default.txt` — the latest-build fallback so an unlisted next build
//   still shows the newest notes.
//
// Every generated file is a relative symlink to the authoring file: the
// notes exist once, in each locale, and stay in sync by construction. The
// numeric name space is generated-only — any regular file sitting on a
// numeric name is an error, never deleted or overwritten by this script
// (an operator must resolve it; the script never destroys data).
//
// Idempotent: existing correct links pass untouched, so the per-release
// checklist can run it repeatedly. Loud failure (exit 1) on anything it
// would otherwise have to guess at.

// ignore_for_file: avoid_print

import 'dart:io';

const String usage =
    'usage: dart run tool/fdroid_changelog_links.dart [<repo-root>] '
    '(default: the current directory)';

/// Failure of a changelog-links run — loud, exit 1.
class ChangelogLinksException implements Exception {
  ChangelogLinksException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// ABI version-code offsets, mirroring tool/release_names.dart and
/// android/app/build.gradle.kts: a split APK's versionCode is
/// `N * 10 + abiCode` (N = pubspec build number).
const Map<String, int> abiCodes = {
  'armeabi-v7a': 1,
  'arm64-v8a': 2,
  'x86_64': 3,
};

/// The metadata root the script operates on, relative to the repository
/// root.
const String fdroidMetadataRoot = 'fastlane/metadata/android';

const String defaultChangelogName = 'default.txt';

/// Parsed `version: X.Y.Z+N` line from pubspec.yaml.
({String versionName, int versionCode}) parsePubspecVersion(
  String pubspecSource,
) {
  final match = RegExp(
    r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$',
    multiLine: true,
  ).firstMatch(pubspecSource);
  if (match == null) {
    throw ChangelogLinksException(
      'pubspec.yaml has no parseable `version: X.Y.Z+N` line — the '
      'versionName and the base versionCode come from it.',
    );
  }
  return (
    versionName: match.group(1)!,
    versionCode: int.parse(match.group(2)!),
  );
}

/// Creates or verifies one relative symlink [name] → [targetName] inside
/// [changelogsDir]. Missing → create; existing with the right target →
/// no-op; any other prior state (wrong target, regular file, directory) →
/// loud error. [displayPath] is the repo-relative form used in the printed
/// action lines.
void ensureChangelogLink(
  Directory changelogsDir, {
  required String name,
  required String targetName,
  required String displayPath,
}) {
  final linkPath = '${changelogsDir.path}/$name';
  final priorType = FileSystemEntity.typeSync(linkPath, followLinks: false);
  if (priorType == FileSystemEntityType.notFound) {
    Link(linkPath).createSync(targetName);
    print('created: $displayPath -> $targetName');
    return;
  }
  if (priorType == FileSystemEntityType.link) {
    final actualTarget = Link(linkPath).targetSync();
    if (actualTarget == targetName) {
      print('ok: $displayPath -> $targetName');
      return;
    }
    throw ChangelogLinksException(
      '$displayPath is a symlink to "$actualTarget" but must point at '
      '"$targetName" — fix it by hand (this script never deletes or '
      'rewrites existing links).',
    );
  }
  throw ChangelogLinksException(
    '$displayPath exists and is not a symlink — the "$name" changelog '
    'name space is generated-only, so an unowned file here must be '
    'resolved by hand before this script can proceed (it never deletes '
    'or overwrites data).',
  );
}

/// Fails on any regular all-digits `.txt` file that is not one of
/// [expectedNumericNames] — e.g. a stale file left over after the version
/// bookkeeping moved on; the numeric names are owned by this script.
/// Existing symlinks are skipped here: a stale one is the wrong-target
/// error of [ensureChangelogLink], not a foreign source of truth.
void rejectForeignNumericFiles(
  Directory changelogsDir,
  Set<String> expectedNumericNames,
) {
  for (final entity in changelogsDir.listSync()) {
    if (entity is! File || FileSystemEntity.isLinkSync(entity.path)) continue;
    final name = entity.uri.pathSegments.last;
    if (!RegExp(r'^\d+\.txt$').hasMatch(name) ||
        expectedNumericNames.contains(name)) {
      continue;
    }
    throw ChangelogLinksException(
      'unowned numeric changelog file: ${entity.path} — the all-digits '
      'names are generated-only (the per-ABI versionCodes plus '
      '$defaultChangelogName), and no pending versionCode claims this '
      'name. Resolve it by hand (this script never deletes data).',
    );
  }
}

void main(List<String> arguments) {
  try {
    run(arguments);
  } on ChangelogLinksException catch (error) {
    stderr.writeln('ERROR: ${error.message}');
    exit(1);
  }
}

void run(List<String> arguments) {
  final root = _parseArguments(arguments);
  final pubspecFile = File('${root.path}/pubspec.yaml');
  if (!pubspecFile.existsSync()) {
    throw ChangelogLinksException(
      'no pubspec.yaml under ${root.path} — the version line comes from the '
      'repository root (adjust the argument accordingly).',
    );
  }
  final version = parsePubspecVersion(pubspecFile.readAsStringSync());
  final authoringName = '${version.versionName}.txt';
  final generatedNames = [
    for (final entry in abiCodes.entries)
      '${version.versionCode * 10 + entry.value}.txt',
    defaultChangelogName,
  ];
  final expectedNumericNames = {
    for (final name in generatedNames)
      if (RegExp(r'^\d+\.txt$').hasMatch(name)) name,
  };

  final metadataRoot = Directory('${root.path}/$fdroidMetadataRoot');
  if (!metadataRoot.existsSync()) {
    throw ChangelogLinksException(
      'no $fdroidMetadataRoot under ${root.path} — the F-Droid fastlane '
      'tree is missing.',
    );
  }
  final locales = [
    for (final entity in metadataRoot.listSync())
      if (entity is Directory)
        entity.uri.pathSegments.where((segment) => segment.isNotEmpty).last,
  ];
  if (locales.isEmpty) {
    throw ChangelogLinksException(
      '$fdroidMetadataRoot carries no locale directory — nothing to link.',
    );
  }

  print(
    'changelog links for versionName ${version.versionName} '
    '(versionCode base ${version.versionCode}): '
    '${generatedNames.join(' ')}',
  );

  for (final locale in locales) {
    final changelogsPath = '$fdroidMetadataRoot/$locale/changelogs';
    final changelogsDir = Directory('${root.path}/$changelogsPath');
    if (!changelogsDir.existsSync()) {
      changelogsDir.createSync(recursive: true);
      print('created: $changelogsPath/');
    }
    final authoringPath = '$changelogsPath/$authoringName';
    // Not existsSync: a symlinked authoring file would silently validate
    // whatever it points at.
    final authoringType = FileSystemEntity.typeSync(
      '${root.path}/$authoringPath',
      followLinks: false,
    );
    if (authoringType == FileSystemEntityType.notFound) {
      throw ChangelogLinksException(
        '$authoringPath is missing — the authoring file is the source of '
        'truth for this release; write the release notes there first ('
        'docs/release.md changelog-files step).',
      );
    }
    if (authoringType != FileSystemEntityType.file) {
      throw ChangelogLinksException(
        '$authoringPath is not a regular file — the authoring file is the '
        'hand-written source of truth for this release; write the release '
        'notes there (docs/release.md changelog-files step).',
      );
    }
    rejectForeignNumericFiles(changelogsDir, expectedNumericNames);
    for (final name in generatedNames) {
      ensureChangelogLink(
        changelogsDir,
        name: name,
        targetName: authoringName,
        displayPath: '$changelogsPath/$name',
      );
    }
  }
}

/// Validated argument set: an optional repo-root directory (else the
/// current directory).
Directory _parseArguments(List<String> arguments) {
  if (arguments.isEmpty) return Directory.current;
  final first = arguments.singleOrNull;
  if (first == null || first.startsWith('-')) {
    throw ChangelogLinksException(usage);
  }
  return Directory(first);
}
