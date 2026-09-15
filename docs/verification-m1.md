# M1 verification checklist (Phase-3 handoff)

Work through this top-to-bottom on your own machine (outside any coding-agent
sandbox) and tick as you go. If a step fails, capture the FULL output — it is
the input for the next fix round. Ticking = you observed it passing.

## Environment & toolchain

- [ ] 1. Flutter stable SDK installed per [CONTRIBUTING.md](../CONTRIBUTING.md)
       §1 (`flutter --version` prints a stable release).
- [ ] 2. `flutter pub get` succeeds (also runs gen-l10n for the ARBs).
- [ ] 3. `flutter analyze` → **0 issues** (already verified in the agent
       sandbox, but re-run as your own gate).

## Automated tests (first runtime observation)

`flutter test` could not run in the coding-agent sandbox (it must bind a
loopback socket), so the runtime pass of every test file is first observed
HERE:

- [ ] 4. `flutter test` → all tests pass, in particular:
       - `test/db/cycle_database_test.dart` (schema, DAOs, constraints)
       - `test/domain/` (cycle grouping, statistics, NFP mucus mapping,
         decimal parsing, export/import codec + merge plan)
       - `test/app_shell_test.dart` (widget smoke: 4 tabs, PIN stub inert)
       on Linux, `libsqlite3-dev` may be needed for the DB tests (§4 of
       CONTRIBUTING).

## Web run (persistence!) with the real database

- [ ] 5. `flutter run -d chrome` — app opens past the "Lade Datenbank …"
       splash into the four tabs **Tagebuch / Zyklus / Statistik /
       Einstellungen**.
- [ ] 6. In Einstellungen (or any tab), create at least one Tagebuch entry
       (temperature + bleeding + anything else) on today's date.
- [ ] 7. **Reload the page (F5)** → the entry is still listed below the
       form. (Web persistence runs through drift-wasm over
       OPFS/IndexedDB; the vendored `web/sqlite3.wasm` +
       `web/drift_worker.js` make this work offline-first.)
- [ ] 8. Zyklus tab shows the temperature curve and the bleeding/mucus
       symbol row; tapping a day switches to Tagebuch with that date loaded
       in the form.
- [ ] 9. Einstellungen: switch language to **English** → all four tabs and
       content switch. (Reload resets to German — documented M1 limitation,
       see CONTRIBUTING §Conventions.)

## Export / import round trip

- [ ] 10. Einstellungen → JSON-Export → copy the JSON (or download on web).
- [ ] 11. Alter one day's entry (e.g. change the temperature), then import
       the SAVED JSON: the count summary must report overwritten days and
       the stored values return to the document's content.
- [ ] 12. Feed a garbage string as JSON → the dialog rejects it with the
       "ungültiges Dokument" snackbar, nothing is written.

## Statistics discipline

- [ ] 13. Statistik tab: shows **only** lengths/averages/dates/buckets and
       the "no conclusions" caption. No day classification, no fertile
       window, no phase lengths (marking UI comes with Mode M later).
- [ ] 14. The four exclusion flags (illness/alcohol/travel/other) are set on
       a day → that day never starts a cycle (assumption under review);
       Statistik's caption stays truthful about it.

## Settings stubs & honesty checks

- [ ] 15. PIN lock toggle is visible but **cannot be switched** (stub,
       ADR-0005).
- [ ] 16. Language note states the in-memory-only behaviour.

## CI

- [ ] 17. Push → GitHub Actions green (`analyze` + `test` + `build web`).
       Report back any red job output so fixes can follow immediately.
