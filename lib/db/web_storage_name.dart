/// Drift storage name a web deployment opens, derived from its page URL:
/// paths containing a `branches` segment get `<prefix>-<slug>` (the slug
/// after it, lowercased and restricted to `[a-z0-9-]` like the deploy workflows' slugs; anything
/// else throws [ArgumentError]), every other path — including the
/// released demo at `/app` — opens `<prefix>` verbatim, so existing
/// `/app` users' data stays reachable.
String webDatabaseName(Uri pageUri, {String releasedPrefix = 'cycle_storage'}) {
  final segments = pageUri.pathSegments;
  final branchIndex = segments.indexOf('branches');
  if (branchIndex != -1) {
    final raw = branchIndex + 1 < segments.length
        ? segments[branchIndex + 1]
        : '';
    final slug = raw.toLowerCase();
    if (slug.isEmpty || !RegExp(r'^[a-z0-9-]+$').hasMatch(slug)) {
      throw ArgumentError.value(
        raw,
        'pageUri',
        'branch remainder is empty or not [a-z0-9-] after lowercasing',
      );
    }
    return '$releasedPrefix-$slug';
  }
  return releasedPrefix;
}
