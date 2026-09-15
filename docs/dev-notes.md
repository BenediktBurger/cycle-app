# Dev notes

Short-lived operational lessons and how-tos that do not merit an ADR.
(There is no history here — git history is the record of executed steps.)

## Never move `flutter create` output up a directory tree

**Cautionary tale from 2026-09-15 — how the original `README.md` got clobbered.**

The platform scaffolding was *not* created by the safe command. The project
owner had earlier run `flutter create cycle_app` (which creates a
**subfolder**) and then moved its contents up with `mv cycle_app/* ./`. Two
problems:

1. Template non-dotfiles (`README.md`, `pubspec.yaml`, `lib/main.dart`,
   `test/widget_test.dart`, `web/index.html`, …) **overwrote** the project's
   own hand-reviewed files of the same name at the repo root — this is
   literally how the hand-written `README.md` was replaced by flutter's
   "A new Flutter project" template (repaired 2026-09-15).
2. `mv cycle_app/*` **skips dotfiles** — flutter's `.gitignore`, `.metadata`,
   `.idea/` etc. stayed inside the leftover `cycle_app/` directory or were
   dropped entirely.

**Rule going forward:** never move scaffold output up a level like that. To
(re)generate platform files, run `flutter create .` against the existing
tree — it **preserves already-existing files**:

```sh
flutter create --platforms=android,ios --project-name cycle_app .
```

(Web is not listed here because `web/index.html` and `web/manifest.json`
already exist in this repo and are preserved untouched. `flutter create`
never clobbers existing files, so the web pair survives either way.)

Even so, run `git status` right afterwards: if any tracked file shows up as
*modified*, restore it with `git checkout -- <file>` and investigate before
continuing (`flutter create` for web never clobbers `web/manifest.json` and
does not require icon files for a web build).

A related tripwire lives in `pubspec.yaml`: if that file ever reverts to
"A new Flutter project" defaults, a `flutter create` run has clobbered it —
restore from git history.

## `flutter test` cannot run inside the omac sandbox

The omac coding-agent sandbox denies `bind()` on any 127.0.0.1 port, while
`flutter test` spawns `flutter_tester`, which opens a temporary loopback
WebSocket server socket (`Failed to create server socket (OS Error:
Permission denied, errno = 13)`). Run `flutter test` in a normal terminal
outside the sandbox — or rely on CI. (An intent was declared in the omac
sandbox log so this limitation is on record.)
