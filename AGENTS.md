# AGENTS.md

Guidance for coding agents (and human contributors). Start with
[CONTRIBUTING.md](CONTRIBUTING.md) for setup, daily commands, and project
conventions; open work lives in [`docs/roadmap.md`](docs/roadmap.md),
decisions in [`docs/adr/`](docs/adr/README.md).

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
  until the item is folded into history (see the roadmap preamble).

## File roles

- `docs/roadmap.md` — the to-do list: open work only, no diaries.
- `CONTRIBUTING.md` — timeless setup and conventions; nothing
  milestone-specific.
- `docs/adr/` — one ADR per decision; unresolved working assumptions stay
  marked (e.g. `TODO(user-review)`) and are questions for INER experts, not
  settled behavior.
