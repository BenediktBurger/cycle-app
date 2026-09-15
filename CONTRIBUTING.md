# Contributing

Setup path, daily commands, and project conventions. Open work and upcoming
milestones are tracked in [`docs/roadmap.md`](docs/roadmap.md).

## 1. Install the Flutter SDK (stable channel)

The official quick-start guide at
<https://docs.flutter.dev/install/quick> is **the** source of truth for
installing the stable SDK. We do **not** require a specific folder — any
location works as long as `<sdk>/bin` is on your PATH — but we recommend
`~/flutter` as a typical path. Put the `PATH` export into your shell profile
(`~/.bashrc` / `~/.zshrc`) so it persists, then verify:

```sh
export PATH="$HOME/flutter/bin:$PATH"
flutter --version
```

`flutter doctor` will complain about missing Android Studio / Xcode etc. —
that is fine for the web iteration target. What you need for everything below
is only the Flutter SDK itself.

## 2. Platform scaffolding

`android/`, `ios/`, `.metadata` and the IDE module files exist at the repo
root (project name `cycle_app`). You do not need to regenerate them normally.

If platform files ever go missing or need (re)generation, run from the repo
root:

```sh
flutter create --platforms=android,ios --project-name cycle_app .
```

`flutter create .` **preserves already-existing files**, so it is always the
safe route.
Always run `git status` right afterwards.

## 3. Fetch dependencies and run

```sh
flutter pub get
flutter run -d chrome
```

`-d chrome` runs the app as a Flutter web app in Chrome — that is the
iteration/test target (see
[ADR-0003](docs/adr/0003-target-platforms-web-iteration.md)); the product
targets Android + iOS.

Note (Phase 2 onwards): running on web with a database needs drift's
`sqlite3.wasm` + worker assets — this section will be updated in that
milestone.

## 4. Analyze, test, build

```sh
flutter analyze
flutter test
flutter build web
```

All three must pass before you push. CI runs exactly these (see
[.github/workflows/ci.yml](.github/workflows/ci.yml) and
[ADR-0006](docs/adr/0006-ci.md)).

If `flutter analyze` or `flutter test` fails with hand-written code, please
report the full analyzer/test output back so issues can be fixed promptly.

## Conventions

- **Architecture decisions** get an ADR under
  [`docs/adr/`](docs/adr/README.md) — one numbered Markdown file with the
  sections Title / Date / Status / Context / Decision / Consequences; the
  status vocabulary (Accepted / Hypothesis / Proposed) is defined there.
- **Localization** is German-first via `flutter gen-l10n` (`l10n.yaml`,
  `lib/l10n/`), with English mirrored. Add new UI strings to both
  `.arb` files.
- **Package name** `cycle_app` is a placeholder ([ADR-0002](docs/adr/0002-package-name-cycle-app-placeholder.md));
  do not rely on it in code
- **Unresolved working assumptions** are marked in code and docs — in
  particular the overall "Mode M" product shape
  ([ADR-001](docs/adr/0001-iner-mode-m-hypothesis.md), status: Hypothesis),
  the NFP 0–4 mucus mapping table, and the cycle-boundary rule. Treat marked
  comments like `// TODO(user-review)` as questions to bring to INER experts,
  not as settled behavior.
