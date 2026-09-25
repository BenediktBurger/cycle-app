# ADR-0011: License texts bundled as assets behind the in-app license page (package licenses auto-collected)

- **Date:** 2026-09-25
- **Status:** Accepted

## Context

The app is Apache-2.0 ([docs/release.md](../release.md), Gate G2) and bundles
the Noto Sans font (SIL Open Font License 1.1) for the PDF export. Both
licenses carry redistribution obligations that a distributed binary must meet
on its own: Apache-2.0 §4 requires giving recipients a copy of the license,
and SIL OFL 1.1 §4 requires shipping the OFL text alongside the font files.
Until now the About page's license section only *named* Apache-2.0 and
pointed to the repository's `LICENSE` file — the distributed binary itself
contained no readable license text, and `showAboutDialog` was rejected
earlier for this page (see `lib/ui/about.dart`; the dialog surface can host
neither the German-first warning content nor the first-start action).

The pointer also cannot be resolved offline: a user holding a store
distribution without the repository cannot read either license text.

## Decision

- Both license texts live at their canonical locations — the repository root
  `LICENSE` (Apache-2.0) and `assets/fonts/LICENSE-NotoSans.txt` (SIL OFL
  1.1) — and are declared **directly as assets** in `pubspec.yaml`. No
  second copy under `assets/`, so nothing can drift from the canonical
  files.
- A small module (`lib/licenses.dart`) exports the two texts as
  `LicenseEntry` streams; `main()` registers it with
  `LicenseRegistry.addLicense`. Registration is synchronous, asset loading
  lazy — the texts are only read when a license page collects entries.
- The About page's license section keeps its heading/body and gains ONE new
  tappable row (own card, own l10n key, own handler) that calls
  `showLicensePage` with the app name, the installed binary's version, and
  the attribution line as legalese. The full texts then render in-app,
  offline, for both the app and the font license.
- The **pub packages' license texts are not bundled by hand** and also not
  harvested by extra tooling (no flutter_oss_licenses): the build's license
  collector already auto-collects every package root's `LICENSE`/`NOTICES`
  (all packages of the package config — the pub dependencies and the app
  root itself) into the built `NOTICES` file, which the license page reads
  through `LicenseRegistry`. The pub-package licenses therefore surface on
  the same in-app license page, without any app-side upkeep.
- The registration covers the text auto-collection misses: the bundled Noto
  Sans font's OFL file is an asset, not a package-root `LICENSE`, so it
  ships through the same registration as the app's Apache text under the
  curated package name (`cycle-app`), keeping the license page's first-row
  naming aligned with the About attribution instead of the tooling's
  root-package label (`cycle_app`).
- The About body keeps ONE sentence pointing to the repository
  (github.com/BenediktBurger/cycle-app) as an additional, deeper reference
  (full sources) — not as a substitute for the in-app texts.

## Consequences

- Every distributed binary satisfies the two offline-readable obligations;
  the texts stay in sync with the canonical files by construction (they ARE
  the canonical files).
- The in-app license page shows both texts under their package names
  (`cycle-app`, `Noto Sans`) and, additionally, every auto-collected
  package text under its tooling-reported name (`drift`,
  `flutter_riverpod`, …; the app's own Apache text also under the root
  package's collector name `cycle_app`); keeping the curated texts current
  is therefore reduced to updating the font or the LICENSE file itself.
- Pub-package license attribution is kept current by the tooling (the same
  build that upgrades a dependency collects its license); no app-side
  license list can drift out of sync. The repository remains the deeper
  reference for users who want the sources or the issue history, not the
  only place the licenses are readable — this closes the earlier gap where
  users without repository access saw only the app's own texts.
- Tests cover the bundling (`test/licenses_test.dart`: asset presence +
  collector content) and the About row's navigation
  (`test/about_page_test.dart`).
