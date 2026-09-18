# Architecture Decision Records

This directory holds the project's ADRs, numbered `0001`, `0002`, … .

Every ADR uses the same sections: **Title**, **Date**, **Status**, **Context**,
**Decision**, **Consequences**.

## Status vocabulary

A record is in exactly one of these states:

| Status         | Meaning                                                                                                                                                                                                                                                                                          |
|----------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **Accepted**   | A real decision. The team/project treats it as settled; changing it requires a new ADR that supersedes this one.                                                                                                                                                                                 |
| **Hypothesis** | A **working assumption**, *not* a settled decision. It records a shape/posture under test that is explicitly not confirmed by external authority (e.g. INER experts) or by practice yet. Hypotheses are expected to change or be validated into an Accepted decision later, via a follow-up ADR. |
| **Proposed**   | Under discussion; not yet decided. Nothing depends on it in a guaranteed way.                                                                                                                                                                                                                    |

A status is never "silently downgraded": when a Hypothesis is validated (or
rejected), a new ADR is written that supersedes the old one and references it.

## Index

| ADR | Title | Status |
|-----|-------|--------|
| [0001](0001-iner-mode-m-hypothesis.md) | INER-compatible "Mode M" product shape | Hypothesis |
| [0002](0002-package-name-cycle-app-placeholder.md) | Package name `cycle_app` is a placeholder | Accepted |
| [0003](0003-target-platforms-web-iteration.md) | Web/Chrome as iteration target; Android + iOS as product targets | Accepted |
| [0004](0004-riverpod-flchart-flutter.md) | Riverpod for state management; fl_chart for the temperature curve | Accepted |
| [0005](0005-storage-and-encryption.md) | Storage drift/SQLite; encryption split native-SQLCipher vs. web-none | Accepted |
| [0006](0006-ci.md) | Automated verification — local testing AND GitHub Actions CI (analyze + test + build web) | Accepted |
| [0007](0007-language-policy.md) | Language policy — English code, multilingual app | Accepted |
| [0008](0008-cycle-start-as-mark.md) | Cycle start is a user-owned mark; bleeding only suggests | Accepted |
