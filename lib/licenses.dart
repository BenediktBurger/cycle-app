// The license texts the app itself must ship: its own Apache-2.0 license and
// the Noto Sans font's SIL Open Font License 1.1. Both are read from bundled
// assets, so a distributed binary shows their full texts offline — the
// obligations that make this required live in the licenses themselves
// (Apache-2.0 §4: redistributions "must give ... recipients a copy of this
// license"; SIL OFL 1.1 §4: redistributions of font software must include
// the OFL text alongside the font files).
//
// Loading is deliberately lazy: the collector here is only a stream factory —
// no asset is read at construction time, and Flutter pulls the stream whenever
// a license page collects entries, so registering it at startup costs nothing.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Yields the app's and the bundled font's license entries for
/// [LicenseRegistry] (pass it directly to `LicenseRegistry.addLicense`).
Stream<LicenseEntry> extraLicenses() async* {
  yield LicenseEntryWithLineBreaks(const [
    'cycle-app',
  ], await rootBundle.loadString('LICENSE'));
  yield LicenseEntryWithLineBreaks(const [
    'Noto Sans',
  ], await rootBundle.loadString('assets/fonts/LICENSE-NotoSans.txt'));
}
