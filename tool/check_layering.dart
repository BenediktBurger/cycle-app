/// Enforces the import direction between the layers under `lib/`.
///
/// Run with `dart run tool/check_layering.dart`. Exits non-zero on a new
/// edge that points upward. Edges that existed when the rule landed are
/// listed in [_legacyEdges]; those may only be removed.
///
/// The rules are the module boundaries in AGENTS.md. A file directly under
/// `lib/` is the composition root (`providers.dart`, `main.dart`) and may
/// import any layer; layers must not import it.
library;

// ignore_for_file: avoid_print

import 'dart:io';

/// Layer -> layers it must not import.
const _forbidden = <String, Set<String>>{
  'domain': {'db', 'ui', 'pdf', 'platform', 'root', 'flutter', 'dart:ui'},
  'db': {'ui', 'pdf', 'root'},
  'pdf': {'db', 'platform', 'ui', 'root'},
  'platform': {'db', 'ui', 'pdf', 'root'},
  'ui': {'db'},
};

/// Known upward edges, as `from-file|target-layer`. Remove an entry when
/// the edge is gone; never add one for new code.
const _legacyEdges = <String>{
  'lib/ui/json_export.dart|db',
  'lib/ui/settings/web_storage_card.dart|db',
  'lib/ui/settings/export_import_card.dart|db',
  'lib/ui/settings/general_info_card.dart|db',
  'lib/ui/settings/pdf_export_card.dart|db',
  'lib/ui/settings/drip_import_card.dart|db',
  'lib/ui/measurement_method_dialog.dart|db',
  'lib/ui/diary.dart|db',
  'lib/pdf/cycle_pdf.dart|ui',
  'lib/pdf/pdf_curve.dart|ui',
};

final _directive = RegExp(r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]''');

class Edge {
  const Edge(this.from, this.to, this.line);

  final String from;
  final String to;
  final int line;

  String get key => '$from|$to';
}

void main() {
  final edges = <Edge>[];
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (entity.path.endsWith('.g.dart') || entity.path.contains('/l10n/')) {
      continue;
    }
    edges.addAll(edgesIn(entity.path, entity.readAsLinesSync()));
  }

  final violations = violationsIn(edges);
  final stale = staleAllowancesIn(edges);

  for (final edge in violations) {
    stderr.writeln(
      'layering: ${edge.from}:${edge.line} imports '
      '${edge.to}, which points upward',
    );
  }
  for (final key in stale) {
    stderr.writeln(
      'layering: stale allowlist entry "$key" — the edge is '
      'gone, remove it from tool/check_layering.dart',
    );
  }
  if (violations.isEmpty && stale.isEmpty) {
    print('layering: ${edges.length} internal edges, all downward');
    return;
  }
  exitCode = 1;
}

/// The edges from one file, using [source] instead of disk for tests.
List<Edge> edgesIn(String fromPath, List<String> source) {
  final result = <Edge>[];
  for (var i = 0; i < source.length; i++) {
    final match = _directive.firstMatch(source[i]);
    if (match == null) continue;
    final target = resolveTarget(fromPath, match.group(1)!);
    if (target == null) continue;
    result.add(Edge(fromPath, target, i + 1));
  }
  return result;
}

/// The layer (or `flutter` / `dart:ui` / `root`) a directive points at, or
/// null when it stays inside the same layer or leaves the app.
String? resolveTarget(String fromPath, String uri) {
  String? path;
  if (uri.startsWith('package:cycle_app/')) {
    path = 'lib/${uri.substring('package:cycle_app/'.length)}';
  } else if (uri.startsWith('package:flutter/') || uri == 'dart:ui') {
    return uri.startsWith('dart:ui') ? 'dart:ui' : 'flutter';
  } else if (!uri.startsWith('dart:') && !uri.startsWith('package:')) {
    path = _normalize('${_dirname(fromPath)}/$uri');
  }
  if (path == null || !path.startsWith('lib/')) return null;

  final parts = path.split('/');
  if (parts.length < 3) return 'root';
  return parts[1];
}

/// The layer that is the source of [path], or null for the composition root.
String? layerOf(String path) {
  final parts = path.split('/');
  if (parts.length < 3) return null;
  return parts[1];
}

bool _isViolation(Edge edge) {
  final source = layerOf(edge.from);
  if (source == null) return false;
  if (edge.to == source) return false;
  return _forbidden[source]?.contains(edge.to) ?? false;
}

/// The upward edges that are not in [allowed].
List<Edge> violationsIn(
  Iterable<Edge> edges, {
  Set<String> allowed = _legacyEdges,
}) => [
  for (final edge in edges)
    if (_isViolation(edge) && !allowed.contains(edge.key)) edge,
];

/// Allowlist entries whose edge is gone.
Set<String> staleAllowancesIn(
  Iterable<Edge> edges, {
  Set<String> allowed = _legacyEdges,
}) {
  final present = {
    for (final edge in edges)
      if (_isViolation(edge)) edge.key,
  };
  return {...allowed.difference(present)};
}

String _dirname(String path) {
  final slash = path.lastIndexOf('/');
  return slash == -1 ? '.' : path.substring(0, slash);
}

String _normalize(String path) {
  final out = <String>[];
  for (final part in path.split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (out.isNotEmpty) out.removeLast();
      continue;
    }
    out.add(part);
  }
  return out.join('/');
}
