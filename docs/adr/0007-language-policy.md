# ADR-0007: Language policy — English code, multilingual app

- **Date:** 2026-09-15
- **Status:** Accepted

## Context

The product is German-first ([ADR-0002](0002-package-name-cycle-app-placeholder.md)
placeholder aside): the NER/Rötzer evaluation method and its user community are
German, and the vision requires German + English localization from day one,
with Polish/Italian prepared-for later (requirement 9 in the
[vision](../product/vision.md)).

The scaffold, however, named the UI screen files after the German product
terms: `lib/ui/tagebuch.dart`, `lib/ui/zyklus.dart`,
`lib/ui/statistik.dart`, `lib/ui/einstellungen.dart`. This mixes two
layered concerns — user-facing language (localized via `flutter gen-l10n`,
already bilingual) and developer-facing language (code identifiers, file
names, internal documentation). Nothing depended on the German names beyond
imports and prose mentions, and more such names would likely accumulate while
the product language is German.

## Decision

- **User-facing language stays multilingual and German-first** — unchanged
  from the vision requirement: full German and English via `flutter
  gen-l10n` now; Polish/Italian and others later. User-facing strings are
  never hardcoded.
- **The project's technical language is English**: code identifiers, file
  and class names, comments, commit messages, and internal documentation
  (`docs/`, including ADRs) are written in English.
- Existing German-named files are a historical exception to be
  **mechanically renamed to English identifiers** — this is tracked as an
  open item in the roadmap; the rename carries no behavior change.

## Consequences

- Naming no longer depends on the current product language; contributors
  who don't read German can navigate the codebase.
- The rename must eventually touch `lib/ui/*` imports, `main.dart`, and the
  prose mentions in `README.md` and the roadmap — trivial, but it should
  land as its own commit, separate from feature work.
- New files start with English names from now on, so the listed rename
  candidates ("and any others") stay a finite set; there is no renumbering
  or archive step for historical commits that used the German names.
