# ADR-0012: Public web demo on GitHub Pages (docs landing at Pages root, app under /app/)

- **Date:** 2026-09-28
- **Status:** Accepted
  (amended in place, 2026-10: publishing switched from the Actions-artifact
  deployment to the `gh-pages` branch, the site was organized into
  three tiers — released demo under `/app/` from the published-release
  tag, current development under `/branches/main/` auto-deployed on push
  to main, and on-demand stakeholder branch deploys — and browser
  storage was made per-deployment so the tiers no longer share one
  slot; see the update at the bottom)

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
- **Publishing a release runs the Pages deploy** (the workflow checks out
  the released tag, builds `flutter build web --base-href /cycle-app/app/`,
  and commits the assembled site to the `gh-pages` branch — see the update
  below).
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
  contents (this static demo, the script-free docs page, and the published
  branch deploys — see the update below) and accepted for the demo — the
  confidentiality bar from ADR-0005 continues to apply to native, not to
  this demo.
- Every push to `main` republishes the current development version and
  every release its `/app/` build — publication is part of CI's
  observable state.

## Update 2026-10: gh-pages publishing and the tiered site layout

The Pages source switched from the Actions-artifact deployment to the
`gh-pages` branch ("Deploy from branch", folder `/`) — the two publishing
modes are mutually exclusive, so the source is a one-time owner switch in
the repo settings (see [`docs/release.md`](../release.md)). All Pages
workflows commit to the branch instead of uploading an artifact. The
release-tier deploy force-pushes a fresh orphan commit each time, so
`gh-pages` carries no history. A branch ruleset (deletion-only, no
bypass actors) protects the branch; it targets `gh-pages` by name.
Write restrictions stay off because they would also
bind the Pages workflows' server-side `GITHUB_TOKEN` — branch rulesets
cannot bypass-list the GitHub Actions app — and break the force-push
deploys. In practice only the Pages workflows commit to `gh-pages`: the
branch deployer fast-forwards and stages only its own
`branches/<slug>/` subtree, and any stray push is wiped by the next
release deployment. Restricting writes
via a deploy-key bypass remains a future option, rejected for now
because it would reintroduce a repo secret.

### Tiered layout

The site serves three tiers, all from the same origin and under the same
Pages URL prefix:

- **Released demo at `/cycle-app/app/`**: publishing a GitHub release
  triggers the Pages workflow (`.github/workflows/pages.yml`), which
  checks out the released tag, builds with base href `/cycle-app/app/`,
  and refreshes the landing page from that commit — so `/app/` mirrors
  the published APK (same `tool/flutter-version` pin parsed the same
  way). A `workflow_dispatch` run with an explicit `ref` — tag, branch,
  or commit SHA — redeploys any ref manually (a failed run, a re-deploy).
- **Current development at `/cycle-app/branches/main/`**: every push to
  `main` redeploys it automatically (see the branch deploys below), so
  the landing page's development link is always current instead of
  duplicating `/app/`.
- **Stakeholder branches at `/cycle-app/branches/<slug>/`**, on demand
  per the ownership model below.

URL hosting is unchanged by the tiered layout: the landing page stays at
the Pages root and `/app/` remains the app's base href; a release deploy
stages only `app/`, the root, and `.nojekyll` onto the current
`gh-pages` tree, so the `branches/` subtree and its ownership markers
carry through untouched. The ownership-marker model below applies at the
`branches/` paths unchanged — pushing `main` redeploys its own slug.

### Branch deploys

A second workflow (`.github/workflows/pages-branches.yml`) publishes web
builds of git branches on the same site, so stakeholders can try a branch
before it merges and compare it side-by-side with the released demo:

- Triggers: every push to `main` redeploys
  `/cycle-app/branches/main/`, and any other branch publishes on
  `workflow_dispatch` (deploy on demand, cleanup on demand) — no
  auto-publication on every branch push — plus automatic cleanup when
  the branch is deleted.
- Slugs: the branch name is lowercased and every non-`[a-z0-9-]`
  character is replaced with a dash; the deploy lives under
  `/cycle-app/branches/<slug>/`, built with the matching base href.
- Isolation: normal deploys of the branch workflow write only under
  `branches/<slug>/` — `app/`, the landing page, `.nojekyll`, and the
  Pages root stay the release deploy's paths; when `gh-pages` is
  absent (fresh setup, deletion, or a fork), the branch deploy creates
  the whole site instead, staging the landing page and `.nojekyll`
  alongside its own deploy (see below). The release deploy in turn
  stages onto the current `gh-pages` tree, so existing branch deploys
  survive it. The workflows share one concurrency group, so their writes
  to `gh-pages` serialize instead of racing.
- Ownership: distinct branch names sanitize to the same slug
  (`feature/x`, `feature.x`, `Feature-X`), and an explicit dispatch slug
  could otherwise let one branch overwrite or clean another branch's
  deploy. Each deploy therefore records the publishing branch name in
  `branches/<slug>/.preview-owner` and refuses to publish over a slug
  whose marker names a different branch; deleting a branch removes only
  its own deploy. A manual `cleanup` dispatch with an explicit slug
  stays the operator's escape hatch and skips the marker check.

### The released `/app/` tier and the no downgrade guard

The released-demo tier always serves the newest published release: every
release publish, and every explicit `ref` dispatch of `pages.yml`, rewrites
`app/` wholesale (`rm -rf app` before staging). The tier's first build
arrives with the first release publish — until then, `/app/` and the
landing page's released-demo link 404. A `ref` dispatch with `ref: main`,
a commit SHA, or a lightweight tag can publish the current development
state to `/app/` — no version tag, no Android release, no GitHub release —
entirely at the owner's discretion.

Releases and `ref` dispatches deploy unconditionally — deliberately
without a version comparison anywhere in the deployer: every run
redeploys `/app/`, even if the ref were accidentally older than the
currently served build. The owner fixes forward instead of ever
intending to ship an older version; a comparison-based guard would
silently withhold a deploy and turn a mistaken tag into a persistent
wrong `/app/`, with an unclear distinction between the bug and the
guard firing. Redeploys stay continuous for existing demo users: the
`/app/` build opens the `cycle_storage` browser-storage slot (below),
so a release deploy leaves their data in place.

### Browser storage per deployment

Storage is per deployment, not shared: a `/app` page opens the historical
`cycle_storage` slot — users of the released `/app` build keep their
existing `cycle_storage` data across every release, because redeploys
preserve the slot and their data stays in place — and every
`/branches/<slug>/` deployment opens `cycle_storage-<slug>`. The slug
derivation is deliberately loose: any path segment sequence containing an
exact `branches` segment yields the following segment as the slug,
sanitized like the deploy slugs (see `lib/db/web_storage_name.dart`);
coupling it to the repo-root prefix (`cycle-app`) was rejected because a
repo rename would silently move existing preview users' storage slots.
A migration run in one demo
therefore can never touch the OPFS or IndexedDB data another deployment
opens. This removes the reason to walk
stakeholders through private windows; private windows remain an
available scratch option, and data entered there vanishes with the
window.

## Amendment 2026-10-20: supported deployment, shared origin accepted, iPhone check pending

**Status: Accepted (amends the "demo does not change the platform decision"
clause and the demo framing above; the released/development/branch tiers and
the storage-slot-per-deployment rule are unchanged).** The original text
above is kept for the record; where it conflicts with this amendment, the
amendment governs.

The Pages site now serves a **supported web deployment**, not only a demo:
web is a supported secondary target
([ADR-0003](0003-target-platforms-web-iteration.md)), and the deployment is
how that target is used. The three tiers stay as described above — released
`/app/`, current development `/branches/main/`, and on-demand
`/branches/<slug>/` previews.

Supported: data entry, statistics, the cycle view, PDF, JSON export/import,
and the installed PWA. Not guaranteed: Safari-tab durability, at-rest
encryption, sync, raw database-file copy, and background notifications.

- **Shared origin accepted.** The deployment keeps using the shared
  `BenediktBurger.github.io` origin, which also hosts other Pages projects
  and the branch previews. All of them are same-origin, so same-origin
  scripts sit inside the trust boundary: a script served by another Pages
  project or by a branch preview could read this browser profile's storage.
  Per-deployment storage slots isolate the databases (the rule above), not
  origin trust.
- **The static, third-party-script-free mitigation stands.** The site
  remains static and carries no third-party scripts, which bounds the
  origin's script surface. No custom domain is planned.
- **On-device iPhone verification is pending.** No iPhone was available; the
  deployment has been exercised on desktop browsers only, and nothing here
  claims a mobile result. The verification path is the in-app diagnostics
  card: its copy action produces `buildDiagnosticsText` from the web storage
  card — user agent, installed state, persistence, drift's storage backend,
  missing features, and the storage estimate — so a report from a real
  iPhone can be checked against this ADR.
