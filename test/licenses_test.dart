// The bundled license texts: the app's own Apache-2.0 text and the Noto Sans
// font's SIL OFL 1.1 text. Offline-readable redistribution obligations
// (Apache-2.0 §4, SIL OFL 1.1 §§ 2–3) make these texts part of an actual
// distribution — keeping the files asset-declared keeps the shipped binary
// self-contained. The collector feeding LicenseRegistry is tested directly
// against the abstract LicenseEntry interface, independent of the registry.
import 'package:cycle_app/licenses.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Joins a license entry's paragraphs back into one string so assertions can
/// check for distinctive phrases without caring how the text was split.
String _entryText(LicenseEntry entry) =>
    entry.paragraphs.map((paragraph) => paragraph.text).join('\n\n');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('bundled license assets', () {
    test("the app's Apache-2.0 license text is bundled", () async {
      final text = await rootBundle.loadString('LICENSE');
      expect(text, isNotEmpty);
      expect(text, contains('Apache License'));
    });

    test("the Noto Sans font's OFL-1.1 license text is bundled", () async {
      final text = await rootBundle.loadString(
        'assets/fonts/LICENSE-NotoSans.txt',
      );
      expect(text, isNotEmpty);
      expect(text, contains('SIL OPEN FONT LICENSE'));
    });
  });

  group('extraLicenses collector', () {
    test('yields exactly the app license and the font license', () async {
      final entries = await extraLicenses().toList();
      expect(entries, hasLength(2));

      final appEntry = entries.singleWhere(
        (entry) => entry.packages.contains('cycle-app'),
      );
      expect(_entryText(appEntry), contains('Apache License'));

      final fontEntry = entries.singleWhere(
        (entry) => entry.packages.contains('Noto Sans'),
      );
      expect(_entryText(fontEntry), contains('SIL OPEN FONT LICENSE'));
    });
  });
}
