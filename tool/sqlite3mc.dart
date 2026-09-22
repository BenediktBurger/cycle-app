// Maintenance tool for the sqlite3mc amalgamation vendored under
// native/sqlite3mc/ (see that directory's README.md for the full context):
//
//   dart run tool/sqlite3mc.dart check   — CI/local parity check
//   dart run tool/sqlite3mc.dart update  — refresh an outdated vendoring
//
// The `sqlite3` package's build hook compiles the vendored sources into the
// bundled SQLite engine (pubspec.yaml `hooks.user_defines`), so the app's
// native database layer is feature-identical to what upstream's own
// pipeline produces only while the vendored amalgamation matches what the
// `sqlite3` release pins in its tool/download_sqlite.dart. Upgrading the
// `sqlite3` package can change that pin; this tool makes the resulting
// drift obvious (check, also wired into .github/workflows/ci.yml) and
// turns refreshing the vendoring into a single command (update).
//
// Tooling constraints: no extra dependencies (the transitive `archive` and
// `crypto` packages already in pubspec.lock are reused), plain dart:io
// networking without any proxy configuration, and downloads cached under
// .dart_tool/sqlite3mc-cache/ (a gitignored directory, keyed by source
// URL). Nothing outside native/sqlite3mc/ and the cache directory is ever
// written (pubspec.lock is only read).

// ignore_for_file: avoid_print
// `archive` (zip extraction) and `crypto` (SHA-256) are NOT direct
// dependencies of the app — the tooling deliberately avoids new
// dependencies while both live transitively in pubspec.lock (adding direct
// entries would churn pubspec.yaml and re-resolve the lock file for
// everyone). Lint the import contract here instead.
// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

/// Default location of the vendoring (overridable via --vendored-dir so a
/// perturbed copy can be pointed at for testing).
const String defaultVendoredDir = 'native/sqlite3mc';

/// The two files vendored from the amalgamation archive. Only these two —
/// the same the `sqlite3` project's download script copies out.
const String amalgamationCName = 'sqlite3mc_amalgamation.c';
const String amalgamationHName = 'sqlite3mc_amalgamation.h';
const List<String> amalgamationNames = [
  amalgamationCName,
  amalgamationHName,
];

/// Suffix of all SMMC amalgamation release archives; also the URL marker
/// the upstream pin is found by.
const String amalgamationSuffix = 'amalgamation.zip';

/// Path of the dependency lockfile (read-only for this tool).
const String lockFilePath = 'pubspec.lock';

/// Download cache root — under .dart_tool/ (gitignored, auto-created by
/// `flutter pub get`), wiped by cleaning the project.
const String cacheRootDir = '.dart_tool/sqlite3mc-cache';

const Duration requestTimeout = Duration(seconds: 120);

/// Redirect budget for the HTTP layer (GitHub release assets redirect).
const int maxRedirects = 10;

/// Every stable log line starts with this prefix (CI grep-ability).
const String logPrefix = 'sqlite3mc: ';

const String helpText =
    '''usage: dart run tool/sqlite3mc.dart <check|update> [<flags>]

Keeps the sqlite3mc amalgamation vendored under native/sqlite3mc/ identical
to what the `sqlite3` package of pubspec.lock pins upstream in
tool/download_sqlite.dart at git tag sqlite3-<version>:

  check    Verifies the integrity of the vendored files against the SHA-256
           hashes recorded in the vendored README.md, then (with network)
           compares their content against the amalgamation upstream pins.
           --offline       Run the integrity part only, no network.
           --vendored-dir  Directory of the vendoring
                           (default: $defaultVendoredDir).
  update   On drift: refreshes the two vendored files and the provenance
           block in the vendored README.md (URL, versions, hashes,
           vendored-on date). Nothing else is ever written.
           --dry-run       Print what would change; touch nothing.
           --vendored-dir  Directory of the vendoring
                           (default: $defaultVendoredDir).

Exit codes: 0 up to date / no damage, 1 drift/integrity failure/tooling
error. Run from the repo root; in CI, run it right after `flutter pub get`
(in particular: pub get creates the .dart_tool directory serving as the
download cache — without it the cache is a plain no-op, not an error).''';

/// Failure of a tool stage — always loud, always exit 1.
class ToolException implements Exception {
  ToolException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Bad command-line arguments — abort before anything runs.
class UsageException extends ToolException {
  UsageException(String message) : super('$message\n\n$helpText');
}

/// An HTTP fetch that did not return 200 — carries the status code as a
/// structured field so callers can branch on it (instead of matching the
/// message wording).
class FetchStatusException extends ToolException {
  FetchStatusException({required this.statusCode, required String url})
      : super('HTTP $statusCode while fetching $url');

  /// The HTTP status of the failed response.
  final int statusCode;
}

/// Parsed command line.
class Options {
  const Options({
    required this.check,
    required this.offline,
    required this.dryRun,
    required this.vendoredDir,
  });

  /// `check` when true, `update` otherwise.
  final bool check;

  /// check only: skip the networked drift part.
  final bool offline;

  /// update only: print the would-be changes instead of writing them.
  final bool dryRun;

  /// Directory holding the vendoring; --vendored-dir overridable for
  /// testing (a perturbed copy can be pointed at without touching the
  /// real vendored files).
  final String vendoredDir;
}

/// Validates and normalizes the command line. Pure — throws a
/// [UsageException] on anything unexpected.
Options parseArguments(List<String> arguments) {
  String reject(String message) =>
      throw UsageException('$message (got: ${arguments.join(' ')})');

  String? command;
  var offline = false;
  var dryRun = false;
  var vendoredDir = defaultVendoredDir;

  var i = 0;
  while (i < arguments.length) {
    final argument = arguments[i++];
    switch (argument) {
      case 'check':
      case 'update':
        if (command != null) {
          reject('duplicate subcommand ($command as well as $argument)');
        }
        command = argument;
      case '--offline':
        offline = true;
      case '--dry-run':
        dryRun = true;
      case '--vendored-dir':
        if (i >= arguments.length) {
          reject('--vendored-dir needs a directory argument');
        }
        vendoredDir = arguments[i++];
      default:
        reject('unexpected argument: $argument');
    }
  }

  if (command == null) {
    reject('no subcommand: expected `check` or `update`');
  }
  if (offline && command != 'check') {
    reject('--offline applies to check, not to $command');
  }
  if (dryRun && command != 'update') {
    reject('--dry-run applies to update, not to $command');
  }
  if (vendoredDir.isEmpty) {
    reject('--vendored-dir must not be empty');
  }

  return Options(
    check: command == 'check',
    offline: offline,
    dryRun: dryRun,
    vendoredDir: vendoredDir,
  );
}

// --- paths & hashing -------------------------------------------------------

String vendoredFilePath(String vendoredDir, String fileName) =>
    '$vendoredDir/$fileName';

String vendoredReadmePath(String vendoredDir) => '$vendoredDir/README.md';

/// Cache path is the SHA-256 of the full URL (plus a human extension):
/// no URL-derived filesystem mangling, deterministic key.
String cachePathFor(String url, {required String extension}) =>
    '$cacheRootDir/${sha256.convert(utf8.encode(url)).toString()}$extension';

String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

String isoDate(DateTime date) =>
    date.toLocal().toIso8601String().split('T').first;

// --- pubspec.lock ----------------------------------------------------------

/// Extracts the pub.dev (hosted) version of package `sqlite3` from the
/// text of a pubspec.lock. Pure — throws a [ToolException] on anything
/// unexpected (missing package, non-hosted source, missing version line).
String hostedSqlite3Version(String lockText) {
  final lines = LineSplitter.split(lockText).toList();
  final start = lines.indexOf('  sqlite3:');
  if (start == -1) {
    throw ToolException(
        '$lockFilePath: no package `sqlite3` — run `flutter pub get`');
  }

  // The package block runs until the next 2-space-indented `name:` header
  // (the lockfile's per-package separator).
  final block = <String>[];
  for (var i = start + 1; i < lines.length; i++) {
    final line = lines[i];
    if (line.isEmpty) break;
    if (RegExp(r'^  \S+:$').hasMatch(line)) break;
    block.add(line);
  }

  if (!block.contains('    source: hosted') ||
      !block.contains('      url: "https://pub.dev"')) {
    throw ToolException(
        '$lockFilePath: `sqlite3` is not a hosted (pub.dev) package — '
        'this tool only understands the hosted case');
  }

  for (final line in block) {
    final version = RegExp(r'^    version: "([^"]+)"\s*$').firstMatch(line);
    if (version != null) return version.group(1)!;
  }
  throw ToolException('$lockFilePath: `sqlite3` block has no version line');
}

// --- upstream pin ----------------------------------------------------------

/// The URL of the download script a `sqlite3` package release's own
/// binary-building pipeline runs.
String downloadScriptUrlFor(String pubVersion) =>
    'https://raw.githubusercontent.com/simolus3/sqlite3.dart/'
    'sqlite3-$pubVersion/tool/download_sqlite.dart';

/// Parses the SQLite3MultipleCiphers amalgamation URL out of the text of
/// the upstream tool/download_sqlite.dart (the constant upstream's own
/// pipeline resolves into its archives). Pure. [vendoredDir] is the
/// vendoring in use — error messages name its README, not the default.
///
/// Multiple distinct candidate URLs are rejected as ambiguous so a future
/// upstream layout change can never silently pin the wrong archive.
AmalgamationPin parseAmalgamationPin(
  String downloadScriptText, {
  required String vendoredDir,
}) {
  final candidates = RegExp(r'''https://[^\s'"`]+''')
      .allMatches(downloadScriptText)
      .map((match) => Uri.tryParse(match.group(0)!))
      .whereType<Uri>()
      .where((url) =>
          url.path.toLowerCase().endsWith(amalgamationSuffix) &&
          url.path.toLowerCase().contains('sqlite3multiple'))
      .toSet();
  if (candidates.isEmpty) {
    throw ToolException(
        'no SQLite3MultipleCiphers amalgamation URL found in the upstream '
        '`tool/download_sqlite.dart` — its layout must have changed; '
        'compare it to the provenance in '
        '${vendoredReadmePath(vendoredDir)} and refresh manually');
  }
  if (candidates.length > 1) {
    throw ToolException(
        'ambiguous SQLite3MultipleCiphers amalgamation URLs in the '
        'upstream `tool/download_sqlite.dart`:\n'
        '${candidates.join('\n')}\n'
        'Refresh the vendoring by hand; then consider adapting '
        'tool/sqlite3mc.dart to the new layout.');
  }

  final url = candidates.single;
  final versions = RegExp(
          r'sqlite3mc-([\w.+-]+)-sqlite-([\w.+-]+)-amalgamation',
          caseSensitive: false)
      .firstMatch(url.path);
  return AmalgamationPin(
    url: url,
    smmcVersion: versions?.group(1),
    engineSqliteVersion: versions?.group(2),
  );
}

/// All facts that define what is vendored: the upstream pin URL plus the
/// versions it encodes (nullable when the URL layout defeats the parser —
/// `check` still works on content alone, `update` then renders the
/// provenance with an explicit "not derivable" marker).
class AmalgamationPin {
  const AmalgamationPin({
    required this.url,
    required this.smmcVersion,
    required this.engineSqliteVersion,
  });

  /// The SQLite3MultipleCiphers amalgamation release zip pinned upstream.
  final Uri url;

  /// SMMC release version (from the zip file name, e.g. 2.5.0).
  final String? smmcVersion;

  /// SQLite engine version the SMMC release was built on (from the zip
  /// file name, e.g. 3.53.4).
  final String? engineSqliteVersion;

  String get versionDescription =>
      smmcVersion != null && engineSqliteVersion != null
          ? 'SQLite3MultipleCiphers $smmcVersion built on SQLite '
              '$engineSqliteVersion'
          : 'SQLite3MultipleCiphers (version not derivable from the pin '
              'URL)';
}

/// The upstream pin facts together with the already-fetched amalgamation
/// members (bytes) and their SHA-256 hashes.
class UpstreamPin {
  const UpstreamPin({
    required this.pubVersion,
    required this.pin,
    required this.members,
  });

  final String pubVersion;
  final AmalgamationPin pin;

  /// amalgamation members as fetched from the pinned archive, keyed by
  /// basename. Content source of truth for compare + update.
  final Map<String, Uint8List> members;

  Map<String, String> get memberHashes =>
      members.map((name, bytes) => MapEntry(name, sha256Hex(bytes)));
}

// --- vendored README (provenance) ------------------------------------------

/// SHA-256 hashes of the vendored files as recorded in the README's
/// provenance block. Pure — throws when a hash is missing (layout drift).
/// [vendoredDir] is the vendoring in use — error messages name its README.
Map<String, String> recordedHashes(String readmeText,
    {required String vendoredDir}) {
  final hashes = <String, String>{};
  for (final name in amalgamationNames) {
    final record =
        RegExp('`$name`\\s*([0-9a-fA-F]{64})').firstMatch(readmeText);
    if (record == null) {
      throw ToolException(
          '${vendoredReadmePath(vendoredDir)} does not record a '
          'SHA-256 hash for `$name` — provenance layout drifted; restore '
          'it from a vendoring commit and refresh manually');
    }
    hashes[name] = record.group(1)!;
  }
  return hashes;
}

/// The source-archive URL recorded in the README provenance block
/// (null when none is recorded — never an error: the URL documents, the
/// hashes are the binding record).
Uri? recordedSourceUrl(String readmeText) {
  for (final match in RegExp(r'''https://[^\s'"`]+''').allMatches(readmeText)) {
    final url = Uri.tryParse(match.group(0)!);
    if (url != null &&
        url.path.toLowerCase().endsWith(amalgamationSuffix) &&
        url.path.toLowerCase().contains('sqlite3multiple')) {
      return url;
    }
  }
  return null;
}

/// The provenance block as it must read after a refresh — the verbatim
/// layout of the committed block (between `## Provenance` and
/// `## Licensing` in the vendored README.md), values substituted. Pure.
String provenanceBlock({
  required String sourceUrl,
  required String versionFacts,
  required String pubVersion,
  required String vendoredOn,
  required Map<String, String> hashes,
}) {
  return '''
- Source archive:
  $sourceUrl
  (from the tooling the `sqlite3` package itself pins in
  `tool/download_sqlite.dart` at tag `sqlite3-$pubVersion`)
- Content: $versionFacts.
  Only `$amalgamationCName` and `$amalgamationHName` from the
  archive are vendored here (the same two files the `sqlite3` project's
  download script copies).
- Vendored on $vendoredOn by `dart run tool/sqlite3mc.dart update`.
- SHA-256:
  - `$amalgamationCName`
    ${hashes[amalgamationCName]}
  - `$amalgamationHName`
    ${hashes[amalgamationHName]}''';
}

/// Replaces the provenance block (the region between the `## Provenance`
/// and `## Licensing` headings) wholesale. Pure — throws when the README
/// has lost its heading structure. [vendoredDir] is the vendoring in use —
/// error messages name its README.
String withRewrittenProvenance(String readmeText, String newBlock,
    {required String vendoredDir}) {
  final provenanceHeading = readmeText.indexOf('## Provenance');
  final licensingHeading = readmeText.indexOf('## Licensing');
  if (provenanceHeading == -1 ||
      licensingHeading == -1 ||
      licensingHeading < provenanceHeading) {
    throw ToolException('${vendoredReadmePath(vendoredDir)} lost its '
        '`## Provenance` / `## Licensing` heading structure — cannot '
        'rewrite the provenance block; restore the layout manually');
  }
  return readmeText.replaceRange(
      provenanceHeading, licensingHeading, '## Provenance\n\n$newBlock\n\n');
}

// --- networking ------------------------------------------------------------

/// Plain dart:io networking: no proxy configuration, explicit redirect
/// following, hard per-request timeout.
Future<Uint8List> httpGet(String url) async {
  final client = HttpClient()..connectionTimeout = requestTimeout;
  try {
    var current = url;
    for (var redirect = 0; redirect <= maxRedirects; redirect++) {
      final request =
          await client.getUrl(Uri.parse(current)).timeout(requestTimeout);
      final response = await request.close().timeout(requestTimeout);

      if (response.isRedirect) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>();
        if (location == null) {
          throw ToolException('redirect without Location header fetching '
              '$current');
        }
        current = location;
        continue;
      }

      if (response.statusCode != 200) {
        throw FetchStatusException(
            statusCode: response.statusCode, url: current);
      }

      final chunks = BytesBuilder(copy: false);
      await for (final chunk in response) {
        chunks.add(chunk);
      }
      return chunks.takeBytes();
    }
  } finally {
    client.close(force: true);
  }
  throw ToolException('more than $maxRedirects redirects fetching $url');
}

/// Fetch with a URL-keyed file cache under [cacheRootDir].
Future<Uint8List> fetchWithCache(String url,
    {required String extension}) async {
  final cacheFile = File(cachePathFor(url, extension: extension));
  if (await cacheFile.exists()) {
    print('${logPrefix}using cached download ${cacheFile.path}');
    return cacheFile.readAsBytes();
  }
  print('${logPrefix}fetching $url');
  final bytes = await httpGet(url);
  await Directory(cacheRootDir).create(recursive: true);
  await cacheFile.writeAsBytes(bytes, flush: true);
  return bytes;
}

/// Both networked pieces in one: the upstream download-script constant
/// (pin URL), and the archive content behind it, extracted member-wise.
/// [vendoredDir] is the vendoring in use — error messages name its README.
Future<UpstreamPin> fetchUpstreamPin({required String vendoredDir}) async {
  final lockFile = File(lockFilePath);
  if (!await lockFile.exists()) {
    throw ToolException('$lockFilePath not found — run `flutter pub get`');
  }
  final pubVersion = hostedSqlite3Version(await lockFile.readAsString());

  final scriptUrl = downloadScriptUrlFor(pubVersion);
  final AmalgamationPin pin;
  try {
    pin = parseAmalgamationPin(
        utf8.decode(await fetchWithCache(scriptUrl, extension: '.dart')),
        vendoredDir: vendoredDir);
  } on FetchStatusException catch (error) {
    if (error.statusCode == 404) {
      throw ToolException(
          'no `tool/download_sqlite.dart` at git tag `sqlite3-$pubVersion` '
          'in simolus3/sqlite3.dart — does that tag exist for the pub '
          'release $pubVersion? If the tooling moved: compare the '
          'provenance in ${vendoredReadmePath(vendoredDir)} and refresh '
          'manually.');
    }
    rethrow;
  }

  final zipUrl = pin.url.toString();
  final cacheFile = File(cachePathFor(zipUrl, extension: '.zip'));
  Map<String, Uint8List> members;
  try {
    members = extractFromZip(await fetchWithCache(zipUrl, extension: '.zip'),
        'the pinned amalgamation archive $zipUrl');
  } on ToolException {
    if (!await cacheFile.exists()) rethrow;
    // Corrupt/stale cache entry (e.g. an interrupted download): drop it
    // once and refetch; a freshly downloaded broken archive still aborts.
    print('${logPrefix}cached download unreadable — refetching');
    await cacheFile.delete();
    members = extractFromZip(await fetchWithCache(zipUrl, extension: '.zip'),
        'the pinned amalgamation archive $zipUrl');
  }

  return UpstreamPin(pubVersion: pubVersion, pin: pin, members: members);
}

// --- archive ---------------------------------------------------------------

/// Extracts the two amalgamation members out of zip bytes. Pure. Throws a
/// [ToolException] when the bytes are not a zip or a member is missing
/// (members are located by basename, under any directory nesting).
Map<String, Uint8List> extractFromZip(Uint8List zipBytes, String sourceLabel) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(zipBytes);
  } catch (error) {
    throw ToolException('not a readable zip archive ($sourceLabel): $error');
  }

  final extracted = <String, List<int>>{};
  for (final file in archive.files) {
    final basename = file.name.split('/').last;
    if (amalgamationNames.contains(basename)) {
      extracted[basename] = List<int>.from(file.content as List);
    }
  }
  final missing =
      amalgamationNames.where((name) => !extracted.containsKey(name));
  if (missing.isNotEmpty) {
    throw ToolException('zip archive ($sourceLabel) lacks '
        '${missing.join(', ')} — the vendoring refresh needs exactly '
        'those two amalgamation members');
  }
  return extracted
      .map((name, bytes) => MapEntry(name, Uint8List.fromList(bytes)));
}

// --- vendored side ---------------------------------------------------------

/// SHA-256 of each vendored amalgamation file. Throws when a file is
/// missing.
Future<Map<String, String>> hashVendoredFiles(String vendoredDir) async {
  final hashes = <String, String>{};
  for (final name in amalgamationNames) {
    final path = vendoredFilePath(vendoredDir, name);
    final file = File(path);
    if (!await file.exists()) {
      throw ToolException('vendored file missing: $path — restore it from '
          'a vendoring commit or fix --vendored-dir');
    }
    hashes[name] = sha256Hex(await file.readAsBytes());
  }
  return hashes;
}

// --- subcommand: check -----------------------------------------------------

Future<int> runCheck(Options options) async {
  final vendoredHashes = await hashVendoredFiles(options.vendoredDir);
  final readmeText =
      await File(vendoredReadmePath(options.vendoredDir)).readAsString();
  final recorded = recordedHashes(readmeText, vendoredDir: options.vendoredDir);

  final mismatches = <String>[];
  for (final name in amalgamationNames) {
    if (vendoredHashes[name] != recorded[name]) {
      mismatches.add(
          '  $name: recorded ${recorded[name]}, actual ${vendoredHashes[name]}');
    }
  }
  if (mismatches.isNotEmpty) {
    for (final line in mismatches) {
      print('${logPrefix}INTEGRITY FAILURE: $line');
    }
    print('${logPrefix}integrity check failed — the vendored files under '
        '${options.vendoredDir}/ no longer match the hashes recorded in '
        'README.md; restore the vendoring (git) rather than editing the '
        'sources');
    return 1;
  }
  print('${logPrefix}integrity ok — ${amalgamationNames.length} vendored '
      'files match the README.md hashes');
  if (options.offline) {
    print('${logPrefix}up-to-date check against the upstream pin skipped '
        '(--offline)');
    return 0;
  }

  final pinned = await fetchUpstreamPin(vendoredDir: options.vendoredDir);
  final pin = pinned.pin;
  print('${logPrefix}comparing the vendored files against the upstream '
      'pin (sqlite3 ${pinned.pubVersion}): ${pin.url} — '
      '${pin.versionDescription}');

  final drifted = amalgamationNames
      .where((name) => vendoredHashes[name] != pinned.memberHashes[name])
      .toList();
  if (drifted.isEmpty) {
    print('${logPrefix}up to date with sqlite3 ${pinned.pubVersion} — '
        'the vendored sources are identical to the upstream pin');
    final recordedUrl = recordedSourceUrl(readmeText);
    if (recordedUrl != pin.url) {
      print('${logPrefix}provenance URL is stale though — README.md '
          'records $recordedUrl while upstream pins ${pin.url}; '
          'README-side refresh: dart run tool/sqlite3mc.dart update');
    }
    return 0;
  }

  print('${logPrefix}DRIFT — the vendored amalgamation differs from what '
      'upstream pins for sqlite3 ${pinned.pubVersion}');
  print('${logPrefix}upstream pin URL: ${pin.url} '
      '(${pin.versionDescription})');
  for (final name in drifted) {
    print('$logPrefix$name:');
    print('$logPrefix  vendored: ${vendoredHashes[name]}');
    print('$logPrefix  pinned:   ${pinned.memberHashes[name]}');
  }
  print('${logPrefix}refresh the vendoring: '
      'dart run tool/sqlite3mc.dart update (then rebuild and run the '
      'full test gate)');
  return 1;
}

// --- subcommand: update ----------------------------------------------------

Future<int> runUpdate(Options options) async {
  final pinned = await fetchUpstreamPin(vendoredDir: options.vendoredDir);
  final pin = pinned.pin;
  final readmePath = vendoredReadmePath(options.vendoredDir);
  final readmeText = await File(readmePath).readAsString();
  final records = recordedHashes(readmeText, vendoredDir: options.vendoredDir);
  final vendoredHashes = await hashVendoredFiles(options.vendoredDir);

  // Absolute truth is the freshly-fetched content: the vendored files
  // must end up being it, and the README block must end up describing it.
  final contentDrift = amalgamationNames
      .where((name) => vendoredHashes[name] != pinned.memberHashes[name])
      .toList();
  final finalHashes = pinned.memberHashes;
  final readmeStale =
      records[amalgamationCName] != finalHashes[amalgamationCName] ||
          records[amalgamationHName] != finalHashes[amalgamationHName] ||
          recordedSourceUrl(readmeText) != pin.url;

  if (contentDrift.isEmpty && !readmeStale) {
    print('${logPrefix}already up to date with sqlite3 '
        '${pinned.pubVersion} — nothing to do');
    return 0;
  }

  print('${logPrefix}drift against the upstream pin '
      '(sqlite3 ${pinned.pubVersion}): ${pin.url} — '
      '${pin.versionDescription}');
  print('${logPrefix}SHA-256 of the pinned amalgamation members:');
  for (final name in amalgamationNames) {
    print('$logPrefix  $name ${finalHashes[name]}');
  }

  final newBlock = provenanceBlock(
    sourceUrl: pin.url.toString(),
    versionFacts: pin.versionDescription,
    pubVersion: pinned.pubVersion,
    vendoredOn: isoDate(DateTime.now()),
    hashes: finalHashes,
  );

  if (options.dryRun) {
    print('${logPrefix}dry run — nothing is written');
    if (contentDrift.isEmpty) {
      print("${logPrefix}would leave the two vendored files untouched "
          '(they already match the pinned members)');
    } else {
      for (final name in contentDrift) {
        print('${logPrefix}would replace '
            '${vendoredFilePath(options.vendoredDir, name)}: '
            'vendored ${vendoredHashes[name]} → pinned '
            '${finalHashes[name]}');
      }
    }
    if (readmeStale) {
      print('${logPrefix}would rewrite the provenance block in '
          '$readmePath:');
      print(newBlock);
    } else {
      print('${logPrefix}would leave README.md untouched');
    }
    print('${logPrefix}dry run done — rerun without --dry-run to apply');
    return 0;
  }

  // Rewrite the README before touching the vendored files: the rewrite
  // is pure and can still abort on a drifted README layout, so a failure
  // here leaves the vendored files untouched (the README rewrite alone is
  // idempotent to repeat afterwards).
  if (readmeStale) {
    await File(readmePath).writeAsString(
        withRewrittenProvenance(readmeText, newBlock,
            vendoredDir: options.vendoredDir),
        flush: true);
    print('${logPrefix}rewrote the provenance block in $readmePath');
  }
  if (contentDrift.isEmpty) {
    print('${logPrefix}vendored files already match the pinned archive — '
        'left untouched');
  } else {
    for (final name in contentDrift) {
      final path = vendoredFilePath(options.vendoredDir, name);
      await File(path).writeAsBytes(pinned.members[name]!, flush: true);
      print('${logPrefix}replaced $path');
    }
  }
  if (contentDrift.isEmpty) {
    print('${logPrefix}update complete — only the provenance block was '
        'stale, the vendored sources are unchanged and no rebuild is '
        'forced');
    return 0;
  }
  print('${logPrefix}update complete. Rebuild and run the full test gate '
      'next — the bundled engine changed, so the cipher behaviour '
      '(`PRAGMA cipher` over an opened database, see '
      'lib/db/database_opener.dart) has to re-verify');
  return 0;
}

// --- entry point -----------------------------------------------------------

Future<void> main(List<String> arguments) async {
  if (arguments.contains('--help') ||
      arguments.contains('-h') ||
      arguments.contains('help')) {
    print(helpText);
    return;
  }

  try {
    final options = parseArguments(arguments);
    final exitCode =
        await (options.check ? runCheck(options) : runUpdate(options));
    if (exitCode != 0) exit(exitCode);
  } on UsageException catch (error) {
    stderr.write('${error.message}\n');
    exit(1);
  } on ToolException catch (error) {
    stderr.write('$logPrefix${error.message}\n');
    exit(1);
  }
}
