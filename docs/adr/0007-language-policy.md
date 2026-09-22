# ADR-0007: Language policy — English code, multilingual app

- **Date:** 2026-09-15
- **Clarified:** 2026-09-22
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
- Existing German-named files were a historical exception and have been
  **mechanically renamed to English identifiers**; the rename carried no
  behavior change.
- **German wording is authoritative for everything**: when the German and
  English translations of a string (or a store-listing text) diverge, the
  German wording wins and the English text is corrected to mirror it — the
  NER/Rötzer terminology is German in origin
  ([ADR-0002](0002-package-name-cycle-app-placeholder.md)).
- **English's first position is purely mechanical**: `app_en.arb` must stay
  the gen-l10n template (see `l10n.yaml`) so untranslated terms fall back
  to English — never German. New keys therefore *start* in English, but
  that does not make the English wording authoritative.

## Consequences

- Naming no longer depends on the current product language; contributors
  who don't read German can navigate the codebase.
- The rename touched `lib/ui/*` imports, `main.dart`, and the prose
  mentions in `README.md` and the roadmap; as intended, it landed as its
  own commit, separate from feature work.
- New files start with English names from now on, so the renamed set was
  finite; there is no renumbering
  or archive step for historical commits that used the German names.
- The wording-authority rule resolves into two workflows by mechanism:
  store metadata is drafted German-first and mirrored in English
  (`fastlane/metadata/android/README.md`), while ARB keys are entered
  English-first only because of the template mechanism (`l10n.yaml`).
  In practice: a new key is drafted in `app_en.arb`, the German
  translation is added in `app_de.arb`, and afterwards the German text is
  the proofread authority — any English deviation is corrected to mirror
  the German wording.
