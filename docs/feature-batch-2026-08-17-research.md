# Feature Batch 2026-08-17 — Research Notes

Purpose: research-only pass for the requested feature set.  
Status: **No implementation.**  
Each feature below keeps the same template so we can append findings quickly and keep
decisions auditable.

## Batch ledger

| # | Feature | Surface | Research status | Owner decision needed |
|---|---|---|---|---|
| 1 | Pending | — | Not started | Yes |

## Research template (copy for each feature)

### [N] Feature

- User ask / success criteria:
- Current behavior (what’s happening today):
- Likely cause (code-path-level hypothesis):
- Evidence checked:
  - Files/areas reviewed:
  - Relevant conditions / constants:
  - Failure mode:
- Risk and compatibility check:
  - Old clients behavior / version skew impact:
  - Backend contract risk:
  - Platform-specific notes:
- What to do next (high-confidence plan):
  - Option A:
  - Option B:
  - Recommended direction:
- Open questions / dependencies:
- Tests/verification to add before implementation:

## Items (research notes)

### 1. 2x daily event push timing

- User ask / success criteria: investigate why push notifications can arrive up to ~5 minutes late.
- Current behavior (what’s happening today): notifications for global event starts are delayed, with occasional 5-minute lag.
- Likely cause (code-path-level hypothesis): notification scheduler runs on a 5-minute interval on backend; events are only detected on that tick window.
- Evidence checked:
  - `stepv2-frontend` uses route mapping only for `GLOBAL_EVENT_STARTED` and is not scheduling these pushes.
  - Backend scheduler in `stepv2-backend/src/modules/steps/jobs/globalStepEventScheduler.js` uses 5-minute cadence.
  - Matching guard in `stepv2-backend/src/modules/steps/globalStepEvent.js` has a catch-window check for late ticks.
- Risk and compatibility check:
  - Old clients: push payload handling is tolerant to timing variation and unknown fields; no breaking API shape change.
  - Backend changes affect all app versions; timing behavior must remain deterministic and idempotent under retries.
- What to do next (high-confidence plan):
  - Option A: keep 5-minute cadence (status quo), and document expected jitter.
  - Option B: increase scheduler frequency to reduce jitter (higher infra/push cost).
  - Recommended direction: decide if user-facing timing is required; if yes, move to shorter scheduling plus stricter dedupe controls.
- Open questions / dependencies:
  - Is the product requirement strict-delivery to a specific minute, or "within X minutes" is acceptable?
  - What is expected operational cost budget for higher cron frequency?
- Tests/verification to add before implementation:
  - Backend integration test around scheduler tick/catch-window behavior and one-off edge cases.

