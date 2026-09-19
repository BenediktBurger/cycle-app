# Product vision: cycle-app

## Product goal

A **local-first, open-source mobile app (iOS + Android; PWA bonus)** for
tracking menstrual-cycle symptoms and **manually evaluating them per NER rules
(Rötzer), in the INER spirit**: the user evaluates and stays the authority; the
app is a **tool** (visualization, arithmetic, statistics), not the
decision-maker.

**Mode M** (assisted marking: the user places marks, the app computes
baseline/counts/lines/stats) is the product shape; **Modes S** (suggest +
override) **and A** (automatic) are explicitly deferred.

> **Note on ADR-0001:** Mode M as the product shape is recorded in
> [ADR-0001](../adr/0001-iner-mode-m-hypothesis.md) with status **Accepted**
> (owner decision, 2026-09-19) — accepted by the owner, *not* endorsed by
> INER. The app supports the user but never gives the final answer; knowing
> the method (book or course) is a prerequisite for reliable interpretation.

## Functional requirements

1. **Daily symptom entry**: BBT, bleeding (incl. exclude flags for
   interruptions — illness, alcohol, travel — and spotting), cervical mucus
   (the cheat sheet's fertility-sign vocabulary: t / Ø / f / S, with
   superscript quality qualifiers on S), optional cervix, plus
   pain/mood/desire/sex/notes.
2. **Assisted marking tools for NER evaluation** (first-higher-measurement,
   baseline/coverline from six prior low measurements, mucus peak day, calendar
   fertile window, interruptions) — **data-model-ready in M1, UI deferred**.
3. **Generated statistics** (cycle lengths, phase lengths, distributions) —
   **no status conclusions**.
4. **PDF export** of cycles as Auswertungsbogen — deferred past M1.
5. **Partner evaluates on same phone** (profiles in the v0 schema, UI later);
   file-based sharing a nice-to-have.
6. **Password/biometric lock** (PIN stub in settings; ADR notes web
   limitations, `flutter_secure_storage` on native later).
7. **Local-first, no cloud, no analytics**; JSON export/import in Settings
   from M1.
8. **Open source**, eventually GPL-3-acceptable, license TBD for now; app size
   well below 50 MB.
9. **i18n**: German default + full English from day one via `flutter gen-l10n`
   (ARB template = de, plus en); Polish/Italian prepared-for only.

## Non-functional requirements

- **Local-first**: all data stays on the device — no cloud, no analytics, no
  network permissions (req. 7).
- **Security/privacy**: password/biometric lock; on native SQLCipher-encrypted
  storage later, PIN lock only on web (req. 6, ADR-005).
- **Licensing & size**: open source, eventually GPL-3-compatible (license TBD
  meanwhile), app size well below 50 MB (req. 8).

## Evaluation-mode table

| Mode | Name | Who decides | How the app helps | Status in this project |
| ---- | ---- | ----------- | ----------------- | ---------------------- |
| **M** | **Assisted marking** | **Human decides fully.** The user places every mark on the cycle chart themselves. | The app provides visualization and arithmetic: baseline/coverline from the six prior low measurements, counts, phase lines, statistics — it computes only, it never suggests or interprets autonomously. | **Current product shape** — recorded in [ADR-0001](../adr/0001-iner-mode-m-hypothesis.md) with status **Accepted** (owner decision, 2026-09-19, not an INER-endorsed resolution). |
| **S** | Suggest + override | Human decides, informed by app suggestions. | The app suggests marks/phases per a **rules engine**; the user can override every suggestion. | Explicitly deferred. |
| **A** | Automatic | App evaluates per a **rules engine** + **trust concept**. | The app places marks and evaluates automatically; the human supervises. | Explicitly deferred. |

Mode M is the current product shape: the user stays fully in charge — the app
only does the arithmetic the user would otherwise do by hand (baseline
calculations, counts, lines, statistics), and it warns about arithmetic
anomalies instead of giving a fertility verdict.
