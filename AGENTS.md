# AGENTS.md

Guidance for coding agents (and human contributors). Start with
[CONTRIBUTING.md](CONTRIBUTING.md) for setup, daily commands, and project
conventions; open work lives in [`docs/roadmap.md`](docs/roadmap.md),
decisions in [`docs/adr/`](docs/adr/README.md).

## Improvement notes: three destinations, never lost

Issues, dislikes, and improvement ideas go where they can actually take
effect, not into a generic pile:

- **Agent behavior you want changed** → a rule in **this file**. Do not
  backlog it — a backlog entry would let it recur instead of fixing it.
- **Doubt about a decision** → the ADR in question (unresolved assumptions
  are marked there, e.g. `TODO(user-review)`; they are questions for INER
  experts, not settled behavior).
- **Actual work items** (bugs, missing features, conveniences) → the
  `## Backlog` section of [`docs/roadmap.md`](docs/roadmap.md), grouped as
  bugs / necessary / convenience. No work-package IDs there: backlog items
  are not derived from the plan file. Necessary items take priority over
  convenience items unless the owner decides otherwise.

## Work-package IDs stay in docs/roadmap.md only

The internal plan file that defines the `WP1.x` / `WP2.x` numbering is
ephemeral and not versioned; [`docs/roadmap.md`](docs/roadmap.md) is the
single durable mapping of those IDs. Therefore:

- **Do not** put `WPx.y` identifiers in code comments, test headers,
  docstrings, `pubspec.yaml`, CI configs, commit-scoped prose docs
  (`README.md`, `CONTRIBUTING.md`), error messages, or tool/file names.
- Refer to work in plain language ("the drift database tests", "the Phase 2
  data-layer wiring") and link `docs/roadmap.md` when the schedule matters.
- Tagging a **commit message** `(WP2.1)`-style is fine — git history is
  milestone-appropriate context, source code is not.
- When an item lands, rewrite comments that deferred to it so they describe
  current behavior instead of the plan, and tick the roadmap checkbox only
  until the item is folded into history (see the roadmap preamble). The same
  applies to the backlog section: **done backlog items are removed** — the
  roadmap is a queue, git history is the diary.

## Running tests

Run tests with `flutter test`; the default `compact` reporter redraws one
line with carriage returns, so captured agent logs end up mangled and
failures only surface in a summary at the end. Instead:

- **Iteration** (fixing one thing, fast loop):
  `flutter test test/domain/<file>_test.dart --fail-fast --no-pub -r expanded`
  (`--plain-name '<substring>'` or `--name '<regexp>'` to narrow further).
- **Full gate** before "done" (matches CI):
  `flutter test --no-pub -r expanded` — drop `--fail-fast` here so the whole
  suite still runs.
- **Judge by the exit code, not the text.** `flutter test` exits non-zero on
  failure; a green-looking log tail can still hide a failure (and packages
  like `libsqlite3-dev` missing on Linux fail the `test/db/` suite at load
  time, which only `expanded`/`json` output shows clearly).
- **Machine-readable results**: `--file-reporter json:<path>` plus
  `-r failures-only` — keep this for scripted parsing (counts, timings,
  failure attribution). `-r expanded -r json`? No: use one reporter for
  stdout and `--file-reporter` for the JSON file. `flutter test --machine`
  is a hidden legacy alias for `-r json` (it even prepends one non-JSON
  handshake line) — prefer `-r json`/`--file-reporter` directly.
- **Sandbox note (resolved)**: an earlier omac sandbox denied `flutter test`
  (loopback bind) — that restriction is lifted; run `flutter test` directly
  (see [`docs/dev-notes.md`](docs/dev-notes.md) for the dated lesson). The
  host-VM smoke scripts remain useful fallbacks when hunting failures:
  `dart run tool/db_smoke.dart` / `dart run tool/smoke_export_import.dart`.

## File roles

- `docs/roadmap.md` — the to-do list: open work only, no diaries.
- `CONTRIBUTING.md` — timeless setup and conventions; nothing
  milestone-specific.
- `docs/adr/` — one ADR per decision; unresolved working assumptions stay
  marked (e.g. `TODO(user-review)`) and are questions for INER experts, not
  settled behavior.
