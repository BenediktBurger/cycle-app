# Example data

Sample files to load into the app for a first look — anonymized real data
from publicly available NFP training material. Both import paths merge by
date with an overwrite policy — importing into a profile with real data
replaces the matching days. Export first, or import into an empty profile.

## JSON export format

Import via the JSON import in the settings screen.

- [`example-cycle.json`](example-cycle.json) — one complete cycle in the
  app's current JSON export format (schema v6), with BBT, mucus, cervix and
  marks.
- [`pregnancy-cycles.json`](pregnancy-cycles.json) — a multi-cycle series
  in the same JSON format: an anovulatory pregnancy gap and the
  postpartum return while breastfeeding (three `cycleStart` marks).

## Drip CSV format

Import via the drip CSV import (also in the settings).

- [`example-cycle-drip-format.csv`](example-cycle-drip-format.csv) — the
  example cycle transposed into the drip cycle tracker's CSV export format.
- [`drip-export-sample.csv`](drip-export-sample.csv) — a fuller drip export
  specimen (symptoms, exclusions, notes).
