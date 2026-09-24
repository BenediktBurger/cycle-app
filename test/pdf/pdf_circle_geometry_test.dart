// Tests of the PDF painter's circle primitives (lib/pdf/cycle_pdf.dart's
// pdfFillCircle / pdfStrokeCircle): the actual emitted PDF path geometry of a
// generated page. The pdf package's PdfGraphics.drawEllipse greps CENTER +
// HALF-AXES (its curves run x+r1 / y+r2 through the given point) — these
// helpers must pass the true center and the radius so dots, rings and the
// ruled glyphs of the export all sit where the draw list says they do.
//
// The document is generated uncompressed (smoke-path style) and the page's
// content stream is parsed: every path operator's operands are transformed
// through the emitted `cm` transforms and pooled into a bounding box that
// must equal exactly the intended circle's geometry. This is a byte-level
// pin, not a widget-tree approximation — it fails on any coordinate drift.
import 'dart:convert';

import 'package:cycle_app/pdf/cycle_pdf.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter_test/flutter_test.dart';

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

/// Extracts the page's content stream bytes: the de-referenced
/// `/Contents <n> 0 R` object's uncompressed stream (compress: false).
String contentStreamOf(List<int> bytes) {
  final latin = latin1.decode(bytes);
  final ref = RegExp(r'/Contents (\d+) 0 R').firstMatch(latin);
  if (ref == null) {
    fail('no /Contents reference in the generated document');
  }
  final obj = RegExp(
    '${ref.group(1)} 0 obj(.*?)endstream',
    dotAll: true,
  ).firstMatch(latin);
  if (obj == null) {
    fail('content object ${ref.group(1)} not found');
  }
  final start = obj.group(1)!.indexOf('stream\n');
  return obj.group(1)!.substring(start + 'stream\n'.length);
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

Future<PathBounds> circleBounds({
  required void Function(PdfGraphics canvas) paint,
}) async {
  final doc = pw.Document(compress: false);
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(0),
      build: (_) => pw.CustomPaint(
        size: const PdfPoint(120, 90),
        painter: (canvas, size) => paint(canvas),
      ),
    ),
  );
  return pathBoundsOf(contentStreamOf(await doc.save()));
}

void main() {
  group('pdfFillCircle / pdfStrokeCircle (emitted PDF path geometry)', () {
    test('a filled circle is EXACTLY the requested circle: centered on the '
        'point, radius as given', () async {
      final bounds = await circleBounds(
        paint: (canvas) => pdfFillCircle(canvas, 60, 45, 6),
      );
      expect(bounds.sawPoint, isTrue);
      expect(bounds.minX, closeTo(54, 1e-6), reason: 'center 60 minus r 6');
      expect(bounds.maxX, closeTo(66, 1e-6));
      expect(
        bounds.maxY - bounds.minY,
        closeTo(12, 1e-6),
        reason: 'the drawn path must span the full diameter twice r',
      );
      expect(
        (bounds.minX + bounds.maxX) / 2,
        closeTo(60, 1e-6),
        reason: 'the circle is centered on the requested point\'s x',
      );
      expect(
        (bounds.minY + bounds.maxY) / 2,
        closeTo(45, 1e-6),
        reason: 'the circle is centered on the requested point\'s y',
      );
    });

    test(
      'a stroked circle\'s path is centered on the requested point',
      () async {
        final bounds = await circleBounds(
          paint: (canvas) => pdfStrokeCircle(canvas, 50, 40, 9),
        );
        expect(bounds.sawPoint, isTrue);
        expect((bounds.minX + bounds.maxX) / 2, closeTo(50, 1e-6));
        expect((bounds.minY + bounds.maxY) / 2, closeTo(40, 1e-6));
        expect(bounds.maxY - bounds.minY, closeTo(18, 1e-6));
      },
    );
  });
}
