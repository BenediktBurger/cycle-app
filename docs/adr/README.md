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
