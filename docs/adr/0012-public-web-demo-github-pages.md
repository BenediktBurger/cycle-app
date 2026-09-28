# ADR-0012: Public web demo on GitHub Pages (docs landing at Pages root, app under /app/)

- **Date:** 2026-09-28
- **Status:** Accepted

## Context

The web build (ADR-0003's iteration target, drift over Web/OPFS storage per
ADR-0005) can run in any browser without installing anything, which makes it
a convenient way for testers and interested users to try the app. GitHub
Pages is already the project's home (the repository lives on GitHub) and can
host a static web build for free.

Constraints: the deployment runs at
`https://BenediktBurger.github.io/cycle-app/`, so the Pages root hosts a
documentation landing page and the app itself lives under `/app/` (base
href). The storage backing the app on web is browser-local
(OPFS/IndexedDB) and — per ADR-0005 — unencrypted. The page is entirely
static: no server, no analytics, no uploads.

## Decision

- **A public demo of the web build is served on GitHub Pages** at
  `https://BenediktBurger.github.io/cycle-app/`: a hand-written,
  JavaScript-free bilingual (German-first) landing page at the Pages root
  ([`pages/index.html`](../../pages/index.html), deployed verbatim), and the
  Flutter web build under `/app/`.
- **The deploy runs automatically on push to `main`** (GitHub Actions
  workflow building `flutter build web --base-href /cycle-app/app/` and
  uploading the assembled artifact).
- **The residual risks of the public demo are accepted by owner decision**,
  see [ADR-0005](0005-storage-and-encryption.md): the browser-local storage
  is unencrypted and readable by same-origin scripts.
  - Mitigations in the deployment itself: only the static demo and its
    script-free landing page share the origin — no third-party scripts that
    could read the storage; and the landing page states the storage situation
    (nothing uploaded, no sync between browsers/devices).
- **The demo does not change the platform decision:** web stays the
  iteration target; Android + iOS remain the product targets (ADR-0003).

## Consequences

- Anyone can try the app at the Pages URL; testers need no APK and no
  Flutter setup. Installable where the browser supports it (PWA manifest
  with app icons).
- Data entered in the demo stays in the browser that entered it: cleared by
  the browser's "clear site data", gone in private windows, and never
  synced/ported to another browser or device. The JSON export in the
  Einstellungen screen is the way data leaves the browser.
- The unencrypted same-origin-readability risk is bounded by the origin's
  contents (this static demo + the script-free docs page, nothing else) and
  accepted for the demo — the confidentiality bar from ADR-0005 continues to
  apply to native, not to this demo.
- Every merge to `main` republishes the demo — publication is part of CI's
  observable state.
