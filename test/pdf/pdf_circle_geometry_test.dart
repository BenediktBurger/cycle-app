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
import 'package:cycle_app/pdf/cycle_pdf.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter_test/flutter_test.dart';

import '../support/pdf_content.dart'
    show PathBounds, pageContentStream, pathBoundsOf;

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
  return pathBoundsOf(pageContentStream(await doc.save(), 0));
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
