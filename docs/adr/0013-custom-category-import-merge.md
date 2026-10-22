# ADR-0013: Imported custom category definitions merge into the stored ones

- **Date:** 2026-10-22
- **Status:** Accepted

## Context

The JSON export carries the user-defined diary categories — name, visibility
and entry labels — as the additive `customCategories` root key. On device they
live as one ordered list in the `customDiaryCategories` settings row
([ADR-0010](0010-settings-key-value-table.md)).

A stored day references its category and label names verbatim: `custom_marks`
is a label-keyed object, and the definitions are display vocabulary only. That
makes a replace of the definitions row by the document's list destructive in
two ways. A foreign list can hide or strand labels that stored days still carry
(no definition offers them any more), and two devices evolving the same
category independently — one adds "Kraft" to Sport, the other "Intervall" —
would silently drop each other's additions on the next import.

Constraints:

- Definitions are one settings row, not one row per category; a merge is a
  list computation, not a database upsert.
- The UI enforces write caps at edit time (10 categories, 15 labels, 40
  characters). The JSON decoders stay lenient, so older or hand-edited rows
  keep rendering.
- The definition merge must never rewrite or strand the ticks stored on days.
  Day history is not part of this decision: a document that carries day rows
  still overwrites those days' `custom_marks` under the entries overwrite
  policy.

## Decision

- **Definitions merge by exact category name.** Identity is the name string
  without trimming or case folding: "Sport", "sport" and " Sport" are three
  different categories.
- **Stored order is kept.** A document category whose name is new appends
  after the stored definitions, in document order.
- **A colliding name resolves in place.** The definition keeps its stored
  position, takes the document's `visible` value, and unions its labels:
  stored labels first, verbatim (including duplicates a stored row already
  has), then the document's labels that are not yet present, in document
  order.
- **Document rows are gated, stored rows are trusted.** A row with a blank or
  whitespace-only name is skipped and counted; a duplicate name inside one
  document keeps its first occurrence and is counted. Stored definitions are
  taken as they are, so a no-change import of the stored list cannot become a
  change.
- **The imported visibility wins, and the flip is warned about before
  applying.** The import dialog lists the affected names (stored order, joined
  with `, `, untruncated) in the error style: visibility is the one
  destructive part of the merge, because a hidden category's chips disappear
  from the diary form.
- **UI write caps are not enforced at import.** A merge may exceed 10
  categories, 15 labels or 40 characters and is stored untruncated; the caps
  remain edit-time guards.
- **Unchanged definitions write nothing.** The merged list is compared
  value-wise with the stored list; only a difference rewrites the settings
  row, updates the in-session provider and counts as a change in the import
  summary. A document without the key — and one with an explicitly empty list
  — leaves the stored definitions alone.
- **Preview and apply share one computation.** The planner produces the
  merged list plus the added-category count, the visibility flips and the
  skipped/duplicate row counts; the dialog preview renders that same plan the
  apply writes.
- The success message distinguishes a definitions-only change from "nothing to
  change", so a merge is reported without implying that day, mark or method
  rows were imported.

## Consequences

- **A label deletion no longer travels between devices or configs** — the
  accepted tradeoff. Importing an older definition list resurrects the deleted
  label, because the union re-adds it. That is the price of the primary
  guarantee: the definition merge never strands or rewrites the ticks stored
  on days (day rows that a document carries still overwrite those days' marks
  under the entries overwrite policy).
- **The union covers the two definition lists, not the day history.** A label
  present in neither list stays stored on its days but is not rendered (no
  definition offers it). Known-visible categories follow their chips on the
  next save; invisible or unknown ones keep their stored labels verbatim.
- Re-importing the same document is idempotent: the second merge is value-equal
  to the stored list, writes no settings row and reports no change.
- Documents from older apps (no `customCategories` key) and hand-edited empty
  lists keep the stored definitions; a list from another device adds to this
  device's definitions instead of replacing them.
- The merge lives in the pure planner (`lib/domain/export_import.dart`,
  `mergeCustomCategoryDefinitions`); the database adapter only reads the
  stored row into the plan and writes the merged list back when it changed.
  Preview and apply therefore cannot drift apart.
