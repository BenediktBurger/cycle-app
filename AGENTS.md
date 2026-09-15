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

## File roles

- `docs/roadmap.md` — the to-do list: open work only, no diaries.
- `CONTRIBUTING.md` — timeless setup and conventions; nothing
  milestone-specific.
- `docs/adr/` — one ADR per decision; unresolved working assumptions stay
  marked (e.g. `TODO(user-review)`) and are questions for INER experts, not
  settled behavior.
