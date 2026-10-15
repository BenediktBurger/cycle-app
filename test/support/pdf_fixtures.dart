// Shared test data for the PDF-generation tests (font fixture, date helper).
import 'dart:io';

/// A date in the fixtures' fixed year 2026.
DateTime d(int month, int day) => DateTime.utc(2026, month, day);

/// The bundled asset font, read from the checkout (the smoke path mirrors
/// what the app loads via rootBundle; see lib/pdf/cycle_pdf.dart).
List<int> fixtureFontBytes() =>
    File('assets/fonts/NotoSans-Regular.ttf').readAsBytesSync();
