# ADR-0010: General settings persist in a drift key-value table (`app_settings`)

- **Date:** 2026-09-19
- **Status:** Accepted

## Context

The app's three general settings — language (explicit choice vs. system),
theme mode, and the cycle chart's temperature display range — were plain
in-memory Riverpod state: every choice silently reverted to its default on
the next app start. The roadmap had scoped their persistence as ONE batch,
before any further settings arrive (PDF export options: anonymize flag,
name, birth date, count of included observed cycles; see
[`docs/roadmap.md`](../roadmap.md)).

Constraints:

- Storage is already settled: **drift/SQLite, one local database**
  ([ADR-0005](0005-storage-and-encryption.md)). Adding a second persistence
  stack (`shared_preferences` etc.) would mean two storage mechanisms, two
  encryption stories, two things to back up — for a handful of scalar rows.
- The settings providers must **stay `StateProvider`s with unchanged
  defaults**: the settings screen, the app root widget and several tests
  override/write them directly, and that contract should not churn.

## Decision

- Settings live in the **SAME drift database**, in one generic
  key-value table `app_settings` with a TEXT `key` primary key and a TEXT
  `value` column. Values are always **JSON-encoded text** — one generic
  encode/decode path serves any JSON-representable future setting. Schema
  version bumps 9 → **10**.
- The table is deliberately **schema-stable**: new settings follow the
  **key-based future-proofing** rule — a new key plus a typed accessor in
  `SettingsStore` (the only per-setting surface), never a new column, never
  a schema bump. Unknown keys are ignored on read; a corrupt value
  (broken JSON, wrong shape, unknown token) falls back to that setting's
  default without affecting the other rows.
- The destructive-upgrade policy of
  [ADR-0005](0005-storage-and-encryption.md) applies unchanged: while the
  app is unpublished, upgrades drop and recreate all tables, so the v9 →
  v10 upgrade needs no incremental migration — `createAll()` simply creates
  `app_settings` (and an upgraded file carries no surviving data by policy
  anyway).
- **Hydration shortly after the first frame is accepted**: the app root
  applies the persisted snapshot into the three providers right after the
  database opens, while the splash gate is showing. The app skeleton may
  therefore render a single frame in its defaults (system language, system
  theme, 36–38 °C) before the hydrated values land. An extra loading phase
  on top of the database gate was deliberately *not* added.
- **Write-through errors are ignored by policy**: every provider change is
  echoed into `app_settings` as a fire-and-forget upsert on the already-open
  database. A storage failure cannot undo the in-memory change — it only
  means the choice reverts to its default on the next start.

## Consequences

- One storage backend, one encryption story, one export/import surface —
  settings ride the same drift database that
  [ADR-0005](0005-storage-and-encryption.md) governs (including its
  SQLCipher-later / web-no-encryption split).
- Future settings are cheap: constant + typed helper + a settings-screen
  input, nothing else. The first candidates are the PDF-export options.
- The one-frame default flash is a cosmetic, sub-second artifact; if it
  ever matters, the fix is display-side (e.g. delaying the first frame),
  not a new persistence layer.
- Until the first published release, upgrading still erases the database
  (and with it the settings) — that is the pre-release policy, not a
  property of this design. From that release on, migrations must preserve
  data; `app_settings` itself is version-stable and needs none.

## Update 2026-09-21: encryption wording

The consequence above references ADR-0005's "SQLCipher-later /
web-no-encryption split"; native encryption has since landed pre-release
via SQLite3MultipleCiphers, always-on (see the amendment in
[ADR-0005](0005-storage-and-encryption.md)). The settings decisions in
this ADR are unaffected.
