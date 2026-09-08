# Bara billing verification — 2026-09-07

The authorized code implementation and required architecture, economy, UI-plan,
and code reviews are complete. The code-review verdict is SHIP. This is not a
claim that the entire repository or a store release is green: existing backend
integration failures and external purchase testing remain outstanding.

## Feature checks

- Flutter full suite: 3,039 passed before the final additive grace-access change.
- Final Flutter grace/components/native adapter checks: 35 passed; analysis clean.
- Final source builds: iOS simulator debug and Android production-flavor debug.
  These are compile checks, not signed store submissions or live checkout tests.
- Backend financial, permanent sandbox isolation, and legacy shop integration:
  66 passed on the final advisory-lock migration and wallet lock changes.
- Additional converted zero-price receipt acknowledgement integration: one passed.
- Static public web build: four pages, 15 assets; three HTTP legal-page tests passed.
- Final full backend unit result is recorded in `bara-billing-contract.md`.

All database tests ran against dedicated localhost databases. Nine additive
billing migrations were applied only to the local integration database.
Production and staging were not deployed or started.

## Full backend integration result and attribution

The npm script previously passed an unquoted recursive glob to the shell and
missed top-level integration suites. The script now quotes the glob. The actual
full run exercised 2,912 tests: 2,882 passed, 29 failed, one existing test skipped.

A separate detached checkout at pre-billing HEAD `4e4ac85`, independently installed
Prisma client, and separate local `bara_billing_baseline_20260907_test` database
were used for comparison. No production configuration or credentials were copied.

Of the 29 failures:

- 26 reproduced at the same test locations on unchanged code.
- The Uprising duration test also reproduced its identical HTTP 400 assertion on
  unchanged code during a bounded repeat. The current complete file subsequently
  passed all 10 tests. This is an existing intermittent failure.
- The tournament spectating failure was a new realm-lock deadlock. It is fixed;
  its complete six-test suite passed after the migration change.
- The Redis catalog failure passed on targeted rerun and did not reproduce in
  the baseline comparison. Its original failure remains recorded as intermittent,
  rather than being silently removed from the full-run result.

The full suite has not been represented as passing. Existing failures include
stored-timezone handling, legacy response expectations, notification/onboarding
behavior, standings/queue behavior, and old powerup expectations. Their assertions
were preserved; changing unrelated product behavior was outside this implementation.

## Concurrency regression details

Four new realm regression cases failed before the fix: account metadata/admission
lock coupling, stale-snapshot isolation, admission-first conversion, and
conversion-first admission. They now pass. Realm guards use transaction-scoped
shared advisory locks and fresh READ COMMITTED reads; conversion fails promptly
when an admission is in flight instead of waiting while holding a user row lock.

Billing wallet guards use FOR NO KEY UPDATE, matching the canonical coin-only
UPDATE lock strength. A newly authored synthetic wallet regression originally
used stronger FOR UPDATE, exposing a foreign-key lock upgrade independent of
realm isolation. Its SQL fixture was corrected to the actual wallet primitive;
both success assertions remain unchanged. Account deletion retains its stronger
lock. No existing assertion was weakened or skipped.

## External acceptance still required

Follow `bara-billing-store-setup.md` to configure both stores and RevenueCat,
deploy the reviewed backend with separate production approval, publish the first
UTC cosmetic, provision isolated testers, and exercise the complete purchase
lifecycle on real store builds. Then produce matching signed IPA/AAB artifacts.
The manual placement checklist is in `bara-billing-ui-checklist.md`.

## Monthly/permanent follow-up

The final permanent-premium implementation and its separate verification results
are recorded in [bara-permanent-premium-verification.md](bara-permanent-premium-verification.md).
The historical results above remain unchanged.
