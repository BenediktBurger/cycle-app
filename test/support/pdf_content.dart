// Shared PDF content-stream parsing for test/pdf/: page-marker counting,
// content-stream extraction and the text-run / painted-path / path-bbox
// parsers over the UNCOMPRESSED byte stream (compress: false), so these
// operator reads are byte-exact.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

/// Counts the uncompressed page markers: with `compress: false` every page
/// object dictionary appears verbatim as `/Type/Page/` (the `/Pages` node
/// does not match — its "Page" is followed by an "s", not a "/").
int countPageMarkers(List<int> bytes) {
  final pattern = '/Type/Page/'.codeUnits;
  var count = 0;
  for (var i = 0; i + pattern.length <= bytes.length; i++) {
    var hit = true;
    for (var j = 0; j < pattern.length; j++) {
      if (bytes[i + j] != pattern[j]) {
        hit = false;
        break;
      }
    }
    if (hit) count++;
  }
  return count;
}

/// The [index]-th page's content stream bytes (0-based, print order): the
/// index-th `/Contents <n> 0 R` de-referenced, uncompressed stream
/// (compress: false).
String pageContentStream(List<int> bytes, int index) {
  final latin = latin1.decode(bytes);
  final refs = RegExp(r'/Contents (\d+) 0 R').allMatches(latin).toList();
  if (index >= refs.length) {
    fail('page $index has no /Contents reference (found ${refs.length})');
  }
  final n = refs[index].group(1)!;
  final obj = RegExp('$n 0 obj(.*?)endstream', dotAll: true).firstMatch(latin);
  if (obj == null) {
    fail('content object $n not found');
  }
  final start = obj.group(1)!.indexOf('stream\n');
  return obj.group(1)!.substring(start + 'stream\n'.length);
}

/// The first page's content stream bytes.
String firstPageContentStream(List<int> bytes) => pageContentStream(bytes, 0);

/// One extracted text run: the decoded text, its baseline origin and the used
/// font size, in page coordinates (y-up).
final class PdfTextRun {
  const PdfTextRun(this.text, this.x, this.y, this.fontSize);

  final String text;
  final double x;
  final double y;
  final double fontSize;
}

/// One painted path of the page: its color (fill or stroke), whether it
/// is filled, and the bounding box of the path's points, in page
/// coordinates (y-up).
final class PdfInkPath {
  const PdfInkPath(
    this.color,
    this.minX,
    this.minY,
    this.maxX,
    this.maxY, {
    this.filled = true,
  });

  final List<double> color;
  final double minX;
  final double minY;
  final double maxX;
  final double maxY;

  final bool filled;
}

/// The document's ToUnicode CMap: glyph code → Unicode rune (the pdf package
/// writes one CMap per font as `beginbfchar <code> <unicode> endbfchar`).
Map<int, int> _codeToRuneMap(String document) {
  final map = <int, int>{};
  final block = RegExp('beginbfchar([\\s\\S]*?)endbfchar');
  final entry = RegExp('<([0-9A-F]{4})> <([0-9A-F]{4})>');
  for (final match in block.allMatches(document)) {
    for (final pair in entry.allMatches(match.group(1)!)) {
      map[int.parse(pair.group(1)!, radix: 16)] = int.parse(
        pair.group(2)!,
        radix: 16,
      );
    }
  }
  return map;
}

/// A 2D transform as the PDF operand order (a b c d e f); the returned matrix
/// applies [inner] first, then [outer].
List<double> _compose(List<double> outer, List<double> inner) => [
  outer[0] * inner[0] + outer[2] * inner[1],
  outer[1] * inner[0] + outer[3] * inner[1],
  outer[0] * inner[2] + outer[2] * inner[3],
  outer[1] * inner[2] + outer[3] * inner[3],
  outer[0] * inner[4] + outer[2] * inner[5] + outer[4],
  outer[1] * inner[4] + outer[3] * inner[5] + outer[5],
];

List<double> _apply(List<double> m, double x, double y) => [
  m[0] * x + m[2] * y + m[4],
  m[1] * x + m[3] * y + m[5],
];

PdfInkPath _pathOf(
  List<double> color,
  List<List<double>> points, {
  bool filled = true,
}) {
  var minX = points.first[0];
  var minY = points.first[1];
  var maxX = minX;
  var maxY = minY;
  for (final p in points.skip(1)) {
    if (p[0] < minX) minX = p[0];
    if (p[1] < minY) minY = p[1];
    if (p[0] > maxX) maxX = p[0];
    if (p[1] > maxY) maxY = p[1];
  }
  return PdfInkPath(color, minX, minY, maxX, maxY, filled: filled);
}

/// Extracts a page's (default: the first's) text runs and painted paths
/// (fills and ink strokes).
(List<PdfTextRun>, List<PdfInkPath>) extractPageContent(
  List<int> bytes, {
  int page = 0,
}) {
  final document = latin1.decode(bytes);
  final runes = _codeToRuneMap(document);
  final tokens = RegExp(
    '[^ ]+',
  ).allMatches(pageContentStream(bytes, page)).map((m) => m.group(0)!).toList();

  final runs = <PdfTextRun>[];
  final paths = <PdfInkPath>[];

  var ctm = <double>[1, 0, 0, 1, 0, 0];
  final saved = <List<double>>[];
  final pending = <double>[];
  final pathPoints = <List<double>>[];
  var fill = <double>[0, 0, 0];
  var stroke = <double>[0, 0, 0];
  double fontSize = 0;
  double textX = 0;
  double textY = 0;

  for (final token in tokens) {
    final value = double.tryParse(token);
    if (value != null) {
      pending.add(value);
      continue;
    }
    if (token.startsWith('[') && token.endsWith(']TJ')) {
      // The text-showing token carries the font's glyph codes as one hex
      // string: "[<0123…>]TJ" (Identity-H, 2-byte codes).
      final hex = RegExp('<([0-9A-Fa-f]*)>').firstMatch(token)!.group(1)!;
      final text = StringBuffer();
      for (var i = 0; i + 4 <= hex.length; i += 4) {
        final code = int.parse(hex.substring(i, i + 4), radix: 16);
        final rune = runes[code];
        if (rune != null && rune > 0) text.writeCharCode(rune);
      }
      runs.add(PdfTextRun(text.toString(), textX, textY, fontSize));
      pending.clear();
      continue;
    }
    switch (token) {
      case 'q':
        saved.add(ctm);
      case 'Q':
        ctm = saved.removeLast();
      case 'cm':
        ctm = _compose(ctm, [
          pending[0],
          pending[1],
          pending[2],
          pending[3],
          pending[4],
          pending[5],
        ]);
      case 'm' || 'l':
        pathPoints.add(_apply(ctm, pending[pending.length - 2], pending.last));
      case 'c':
        for (var i = pending.length - 6; i < pending.length; i += 2) {
          pathPoints.add(_apply(ctm, pending[i], pending[i + 1]));
        }
      case 're':
        final x = pending[pending.length - 4];
        final y = pending[pending.length - 3];
        pathPoints
          ..add(_apply(ctm, x, y))
          ..add(
            _apply(
              ctm,
              x + pending[pending.length - 2],
              y + pending[pending.length - 1],
            ),
          );
      case 'rg':
        fill = pending.sublist(pending.length - 3);
      case 'RG':
        stroke = pending.sublist(pending.length - 3);
      case 'f' || 'f*':
        if (pathPoints.isNotEmpty) paths.add(_pathOf(fill, pathPoints));
        pathPoints.clear();
      case 'S' || 's':
        if (pathPoints.isNotEmpty) {
          paths.add(_pathOf(stroke, pathPoints, filled: false));
        }
        pathPoints.clear();
      case 'Td':
        final at = _apply(ctm, pending[pending.length - 2], pending.last);
        textX = at[0];
        textY = at[1];
      case 'Tf':
        fontSize = pending.last;
      // Any other path-closing operator discards the collected points
      // (the clips and the multiline-paint combos are not needed; fills
      // and ink strokes are extracted above).
      default:
        if (pathPoints.isNotEmpty) pathPoints.clear();
    }
    pending.clear();
  }
  return (runs, paths);
}

/// The pooled bounding box of one path operator walkthrough.
final class PathBounds {
  var minX = double.infinity;
  var maxX = double.negativeInfinity;
  var minY = double.infinity;
  var maxY = double.negativeInfinity;
  var sawPoint = false;

  void add(double x, double y) {
    minX = minX < x ? minX : x;
    minY = minY < y ? minY : y;
    maxX = maxX > x ? maxX : x;
    maxY = maxY > y ? maxY : y;
    sawPoint = true;
  }
}

/// Walks the content stream's path operators (m, l, c, re) through the
/// emitted `cm` transforms and pools every driven point into one bbox.
/// Numbers are plain-Dart doubles, the PDF float text form.
PathBounds pathBoundsOf(String stream) {
  final token = RegExp(r'[-+]?[0-9.]+|[A-Za-z]+');
  final numbers = <double>[];
  // The current CTM (only its affine part matters for point mapping).
  var tx = 0.0, ty = 0.0, sx = 1.0, sy = 1.0;
  final bounds = PathBounds();

  void drive(int count, {bool isRect = false}) {
    for (var i = numbers.length - count; i < numbers.length; i += 2) {
      if (isRect) {
        // `x y w h re` — the four corners.
        final x = sx * numbers[i] + tx;
        final y = sy * numbers[i + 1] + ty;
        bounds.add(x, y);
        bounds.add(x + sx * numbers[i + 2], y + sy * numbers[i + 3]);
        return;
      }
      bounds.add(sx * numbers[i] + tx, sy * numbers[i + 1] + ty);
    }
  }

  for (final match in token.allMatches(stream)) {
    final t = match.group(0)!;
    final value = double.tryParse(t);
    if (value != null) {
      numbers.add(value);
      continue;
    }
    switch (t) {
      case 'm' || 'l':
        drive(2);
        numbers.clear();
      case 'c':
        drive(6);
        numbers.clear();
      case 're':
        drive(4, isRect: true);
        numbers.clear();
      case 'cm' when numbers.length == 6:
        // The widget pipeline emits single-level `q a b c d e f cm … Q`
        // painting blocks; track the current block's transform verbatim.
        sx = numbers[0];
        sy = numbers[3];
        tx = numbers[4];
        ty = numbers[5];
        numbers.clear();
    }
  }
  return bounds;
}
