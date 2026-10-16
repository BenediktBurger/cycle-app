// Shared fixtures for the release-tooling tests (release_names,
// publish_release, download_and_sign): the pinned trust anchors, the
// handoff-manifest JSON builders and the changelog-files gate's Git
// Trees/Blobs API fixture.
//
// Pure seam: the gate fixture builds JSON answers for an injectable gh API
// runner — no real gh call ever leaves a test.
import 'dart:convert';
import 'dart:io';

import '../../tool/release_names.dart';

/// The pinned release-certificate fingerprint, duplicated here from the
/// committed [pinFilePath] content so the tests pin the exact trust anchor
/// the release pipeline must enforce.
const pinnedReleaseFingerprint =
    '0aa5749804b8ed9e3c207f851b5902775d762207d60c2485a26b5d75eff5355b';

/// A well-formed 40-char lowercase head SHA for the manifest fixtures.
const validHeadSha = '978dbc5b9ee19ff0aedfc03594a603013f0e034a';

/// Malformed tags every helper's release-tag validation must reject.
const badTagList = [
  'v1.2',
  '1.2.3',
  'v1.2.3.4',
  '',
  'vx.y.z',
  'v1.2.3-rc1',
  'V1.2.3',
  'v1.2.3+4',
];

/// Builds a handoff-manifest JSON fixture out of RAW JSON fragments, so
/// malformed variants (wrong types, missing keys) stay writable.
String manifestJsonRaw({
  String? tag,
  String? versionName,
  String? versionCodeBase,
  String? runId,
  String? headSha,
  String? defaultChangelogOnly,
}) {
  final fields = <String>[
    if (tag != null) '"tag":$tag',
    if (versionName != null) '"versionName":$versionName',
    if (versionCodeBase != null) '"versionCodeBase":$versionCodeBase',
    if (runId != null) '"runId":$runId',
    if (headSha != null) '"headSha":$headSha',
    if (defaultChangelogOnly != null)
      '"defaultChangelogOnly":$defaultChangelogOnly',
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
  defaultChangelogOnly: 'false',
);

/// Builds the recursive Git Trees fixture the changelog-files gate requests
/// at its head SHA plus the blob map its symlink entries point to: every
/// locale in [targets] carries [authoringName] as a blob in git mode
/// [authoringMode] (a regular file by default), and every name with a
/// non-null target in that locale's map becomes a symlink entry (mode
/// 120000) whose blob decodes to the given filename — unless the name is in
/// [regularNames], where it is committed as a regular file (mode 100644).
/// [includeAuthoringEntry] drops the authoring blob itself, for the
/// default-changelog-only trees whose gate must not require the authoring
/// file. Blob shas stay unique per locale so a caller fetching one
/// locale's blob can never be answered by another's.
({String tree, Map<String, String> blobs}) changelogGateFixture({
  required String authoringName,
  required List<String> linkNames,
  required Map<String, Map<String, String>> targets,
  bool includeAuthoringEntry = true,
  String authoringMode = '100644',
  Set<String> regularNames = const {},
  bool truncated = false,
}) {
  final blobs = <String, String>{};
  final entries = <String>[];
  for (final MapEntry(key: locale, value: names) in targets.entries) {
    entries.add(
      '{"path":"$fdroidMetadataPath/$locale","mode":"040000",'
      '"type":"tree","sha":"tree-$locale"}',
    );
    final prefix = '$fdroidMetadataPath/$locale/changelogs/';
    if (includeAuthoringEntry) {
      entries.add(
        '{"path":"$prefix$authoringName","mode":"$authoringMode",'
        '"type":"blob","sha":"sha-$locale-authoring"}',
      );
    }
    for (final name in linkNames) {
      final target = names[name];
      if (target == null) continue;
      if (regularNames.contains(name)) {
        entries.add(
          '{"path":"$prefix$name","mode":"100644",'
          '"type":"blob","sha":"sha-$locale-file-$name"}',
        );
        continue;
      }
      final sha = 'sha-$locale-$name';
      blobs[sha] =
          '{"content":"${base64Encode(utf8.encode(target))}",'
          '"encoding":"base64"}';
      entries.add(
        '{"path":"$prefix$name","mode":"120000",'
        '"type":"blob","sha":"$sha"}',
      );
    }
  }
  return (
    tree: jsonEncode({
      'tree': [for (final entry in entries) jsonDecode(entry)],
      'truncated': truncated,
    }),
    blobs: blobs,
  );
}

/// A pure-seam gh runner serving one recursive tree answer plus one blob per
/// requested sha; anything else exits 1 like an unexpected gh call, so a
/// stray invocation cannot pass silently.
GhApiRunner changelogGateRunner(
  ({String tree, Map<String, String> blobs}) data,
) {
  return (arguments) async {
    final call = arguments.length > 1 ? arguments[1] : arguments.join(' ');
    const treePrefix = 'repos/$releaseRepo/git/trees/';
    const blobPrefix = 'repos/$releaseRepo/git/blobs/';
    if (call.startsWith(treePrefix) && call.endsWith('recursive=1')) {
      return ProcessResult(0, 0, data.tree, '');
    }
    if (call.startsWith(blobPrefix)) {
      final sha = call.substring(blobPrefix.length);
      final blob = data.blobs[sha];
      if (blob == null) {
        return ProcessResult(0, 1, '', 'gh: blob $sha not found');
      }
      return ProcessResult(0, 0, blob, '');
    }
    return ProcessResult(0, 1, '', 'unexpected gh call: $arguments');
  };
}
