/// Enforces the file-size guard rails from AGENTS.md.
///
/// Run with `dart run tool/check_file_sizes.dart`. Files above [warnAt]
/// print a warning; files above [errorAt] fail unless they are listed in
/// [_allowance], which records the size at which a file was grandfathered
/// in. An allowlisted file may shrink but not grow.
library;

// ignore_for_file: avoid_print

import 'dart:io';

/// Above this, a file is reported but does not fail the gate.
const warnAt = 800;

/// Above this, a file must be split before it grows further.
const errorAt = 1200;

/// Grandfathered files and the line count they may not exceed.
///
/// Lower a number when its file shrinks; delete the entry when the file is
/// back under [errorAt].
const _allowance = <String, int>{
  'lib/pdf/cycle_pdf.dart': 1379,
  'lib/ui/cycle_chart.dart': 1536,
  'lib/ui/diary.dart': 1237,
  'test/cycle_mark_sheet_test.dart': 2152,
  'test/db/export_adapter_test.dart': 1603,
  'test/domain/drip_import_test.dart': 2174,
  'test/domain/evaluation_test.dart': 2299,
  'test/domain/export_import_test.dart': 1986,
  'test/domain/pdf_export_model_test.dart': 1258,
  'test/pdf/pdf_cycle_pages_test.dart': 2160,
  'test/statistics_screen_test.dart': 1531,
  'test/tool/release_scripts_test.dart': 3477,
};

enum SizeStatus { ok, warning, error }

void main() {
  final findings = <({String path, int lines, SizeStatus status})>[];
  for (final dir in ['lib', 'test']) {
    for (final entity in Directory(dir).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('.g.dart') || entity.path.contains('/l10n/')) {
        continue;
      }
      final lines = entity.readAsLinesSync().length;
      final status = classifySize(entity.path, lines, allowance: _allowance);
      if (status != SizeStatus.ok) {
        findings.add((path: entity.path, lines: lines, status: status));
      }
    }
  }

  var failed = false;
  for (final finding in findings) {
    if (finding.status == SizeStatus.ok) continue;
    final allowed = _allowance[finding.path];
    final isError = finding.status == SizeStatus.error;
    failed |= isError;
    final detail = _detail(
      isError: isError,
      allowanceForFile: allowed,
      lines: finding.lines,
    );
    stderr.writeln(
      'file-size: ${finding.path} has ${finding.lines} lines, $detail',
    );
  }
  if (failed) exitCode = 1;
  if (!failed) print('file-size: ${findings.length} warning(s), no errors');
}

String _detail({
  required bool isError,
  required int? allowanceForFile,
  required int lines,
}) {
  if (isError) {
    return allowanceForFile == null
        ? 'past the $errorAt-line budget; split it by seam'
        : 'past its $allowanceForFile-line allowance; split it rather than '
              'raising the allowance';
  }
  if (allowanceForFile == null) return 'split it before it grows';
  if (lines <= warnAt) return 'its allowance is stale, drop it';
  return 'its allowance is ${allowanceForFile - lines} lines above the '
      'current size; lower it';
}

/// Classifies [lines] for [path] against the budgets and [allowance].
SizeStatus classifySize(
  String path,
  int lines, {
  Map<String, int> allowance = _allowance,
}) {
  final allowed = allowance[path];
  if (allowed != null) {
    if (lines > allowed) return SizeStatus.error;
    if (lines <= warnAt) return SizeStatus.warning;
    if (allowed - lines >= 100) return SizeStatus.warning;
    return SizeStatus.ok;
  }
  if (lines > errorAt) return SizeStatus.error;
  if (lines > warnAt) return SizeStatus.warning;
  return SizeStatus.ok;
}
