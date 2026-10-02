# Roadmap

**Open work only** — this is a to-do list, not a diary. What has landed is
git history; *why* it landed that way is in
[\`docs/adr/\`](adr/README.md). When an item is done, its checkbox gets
ticked only until it is folded into the next release note/commit — unchecked
items are the queue.

Work-package numbering comes from the internal plan file (ephemeral, not
versioned); the durable record of that numbering is git history, in the
commit messages tagged with it. Any legacy or remaining IDs are mapped
here and appear nowhere else: not in code comments, prose docs, or tool
names (see [`AGENTS.md`](../AGENTS.md)).

## Backlog — issues & improvements

Collector for real issues and improvement ideas that are not (yet) part of a
milestone or the internal plan. Readiness convention: **a plain bullet means
needs discussion** — not startable, the line states what must be resolved
first; **an unchecked checkbox means ready to be implemented** — an agent may
pick it up. When an item is done, it is **removed** from here, not ticked —
the sections above track planned work, git history keeps the record (see
[`AGENTS.md`](../AGENTS.md)).

### Bugs

#### Android

- Verify the entry-form date row on a real device and at large system
  font scales — under widget-test fallback metrics it now lays out
  overflow-free at every pumped width (down to 320 dp), but those are not
  device fonts or font scales.
- Confirm on device that the `_dependents.isEmpty` framework assertion no
  longer occurs: the underlying import-dialog dismissal race is fixed and
  guarded by widget tests, but the literal assertion text could not be
  byte-reproduced under test conditions.

### Necessary

### Convenience

### Deferred for later
