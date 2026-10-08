import 'package:cycle_app/l10n/app_localizations_de.dart';
import 'package:cycle_app/l10n/app_localizations_en.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final de = AppLocalizationsDe();
  final en = AppLocalizationsEn();

  group('deleteDataDialogBody', () {
    test('German singular nouns at count 1', () {
      final text = de.deleteDataDialogBody(1, 1);
      expect(text, contains('1 Tagebucheintrag'));
      expect(text, contains('1 Markierung'));
      expect(text, isNot(contains('Tagebucheinträge')));
      expect(text, isNot(contains('Markierungen')));
    });
    test('English singular nouns at count 1', () {
      final text = en.deleteDataDialogBody(1, 1);
      expect(text, contains('1 diary entry'));
      expect(text, contains('1 mark'));
      expect(text, isNot(contains('diary entries')));
      expect(text, isNot(contains('marks')));
    });
    test('German plural nouns at count 2', () {
      final text = de.deleteDataDialogBody(2, 2);
      expect(text, contains('2 Tagebucheinträge'));
      expect(text, contains('2 Markierungen'));
    });
  });

  group('deleteDataDone', () {
    test('German mixed counts flex per noun', () {
      expect(
        de.deleteDataDone(1, 2),
        contains('1 Tagebucheintrag und 2 Markierungen'),
      );
      expect(
        de.deleteDataDone(2, 1),
        contains('2 Tagebucheinträge und 1 Markierung'),
      );
    });
    test('English plural branch stays intact', () {
      expect(
        en.deleteDataDone(2, 2),
        contains('2 diary entries and 2 marks deleted.'),
      );
    });
  });

  group('termCycleDays', () {
    test('German singular at 1', () {
      expect(de.termCycleDays(1), '1 Tag');
    });
    test('English plural at 2', () {
      expect(en.termCycleDays(2), '2 days');
    });
  });

  group('pdfExportCyclesSelectedSummary', () {
    test('German singular cycle with one cycle available', () {
      expect(
        de.pdfExportCyclesSelectedSummary(1, 1),
        '1 von 1 Zyklus ausgewählt',
      );
    });
    test('German noun follows the total', () {
      expect(
        de.pdfExportCyclesSelectedSummary(1, 5),
        '1 von 5 Zyklen ausgewählt',
      );
    });
    test('German renders a zero selection as the number', () {
      expect(
        de.pdfExportCyclesSelectedSummary(0, 1),
        '0 von 1 Zyklus ausgewählt',
      );
    });
    test('English plural when total exceeds 1', () {
      expect(en.pdfExportCyclesSelectedSummary(2, 5), '2 of 5 cycles selected');
    });
    test('English singular cycle with one cycle available', () {
      expect(en.pdfExportCyclesSelectedSummary(1, 1), '1 of 1 cycle selected');
    });
    test('English renders a zero selection as the number', () {
      expect(en.pdfExportCyclesSelectedSummary(0, 1), '0 of 1 cycle selected');
    });
  });

  group('importSummary', () {
    test('German singular nouns at count 1', () {
      final text = de.importSummary(1, 1, 1, 1, 1, 1);
      expect(text, contains('1 Tag neu'));
      expect(text, contains('1 Markierung neu'));
      expect(text, contains('1 doppelte Zeile'));
      expect(text, contains('1 ungültige Zeile'));
      expect(text, isNot(contains('Tage:')));
      expect(text, isNot(contains('Markierungen:')));
    });
    test('English plural shapes at count 2', () {
      final text = en.importSummary(2, 2, 2, 2, 2, 2);
      expect(text, contains('2 days new'));
      expect(text, contains('2 marks new'));
    });
  });

  group('dripImportSummary', () {
    test('German singular nouns at count 1', () {
      final text = de.dripImportSummary(1, 1, 1, 1, 1);
      expect(text, contains('1 Tag importiert'));
      expect(text, contains('1 leerer Tag übersprungen'));
      expect(text, contains('1 ungültige Zeile'));
      expect(text, isNot(contains('leere Tage')));
    });
    test('English plural shapes at count 2', () {
      final text = en.dripImportSummary(2, 2, 2, 2, 2);
      expect(text, contains('2 days imported'));
      expect(text, contains('2 empty days skipped'));
    });
  });
}
