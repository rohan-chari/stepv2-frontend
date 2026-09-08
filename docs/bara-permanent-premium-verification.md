# Permanent Bara+ implementation verification

Scope: monthly $4.99 with a seven-day trial, plus $19.99 permanent membership
with 500 coins and 10 paid reroll credits every monthly anniversary. Annual is
retired from sale, with historical receipt recognition retained. External App
Store Connect, Google Play and RevenueCat setup is deferred by the user.

## Product behavior

Permanent access begins with verified payment. Its currency schedule begins
immediately for free/trial accounts, or at the original paid subscription period's
end for existing paid members. UTC anniversary dates clamp to the original day
without drifting across short months. Missed eligible months remain owed.

One identity has one schedule regardless of restore, second-store receipts,
repurchase or reversal. Refunds recover only attributable issued rewards within
the existing bounded-wallet policy; currently revoked sources issue no new
currency or cosmetics. A reversal restores recovered value and eligible backlog
without repeating grants or returning absorbed shortfall. Known access survives
provider outages while unverified new grants are deferred with retry backoff.

A separate subscription is not cancelled by a permanent purchase. Its management
controls remain available for active and resumable billing states independently
of whether it currently supplies access. Actual separate paid renewals retain
their existing bundles. First permanent payment ends unused trial-only credits.

## Verification results

- Final `flutter analyze`: clean.
- Full Flutter suite: **3,061 passed**, zero failures. Focused billing UI and
  controller checks: **51 passed**. An intermittent cache-test teardown race was
  fixed by awaiting existing background prefetch after all assertions; no
  production cache behavior or assertion changed.
- Both native compile checks passed: iOS simulator debug `Runner.app` and
  Android `prod` debug APK, using the production backend URL. These are compile
  checks, not signed release artifacts or live purchase verification.
- Full backend unit suite: **3,362 passed**, zero skipped. Final permanent HTTP
  suite: **24 passed**. Combined billing/permanent/realm/legacy-shop checks:
  **88 passed** before the final three additional permanent regressions.
- Final independent code review: **SHIP**, no blockers, issues or nits.
  Architect, economy and UI-placement reviews were completed.
- `git diff --check`: clean in both repositories.

Public purchase terms/privacy: new HTTP assertions failed before implementation;
all three legal-page tests passed afterward. The final static web build contains
four prerendered pages and 15 bundled assets. Terms text was checked at a 390px
viewport with no horizontal overflow. Existing annual legal assertions remain as
historical-plan disclosures, rather than being removed.

## Existing repository failures

The earlier complete backend run and separate baseline attribution remain in
`bara-billing-verification.md`: full repository integration was not green.
Historical results are not relabelled as a passing permanent-premium run.
The final complete backend integration run on dedicated local
`steps-tracker-integration_test` finished with **2,944 tests: 2,913 passed,
30 failed, one existing skip**. All billing tests passed. This is not a green
repository-wide integration result.

Twenty-seven failure locations match the previously recorded baseline failures.
Three additional locations passed on the subsequent targeted current-source run:

- `friends.test.js:402`: the full run failed in `beforeEach` database cleanup
  with a deadlock, before the friend-request assertion. PostgreSQL showed the
  cleanup DELETE competing with a background authentication metadata UPDATE.
  The complete friends suite passed on rerun and in the baseline checkout.
- `notification-domain-isolation.test.js:307`: the full run observed one database
  waiter where the capacity assertion expected zero. It passed on current-source
  and baseline reruns. Three separate known notification assertions remained red
  on the current-source rerun; they also fail in the baseline.
- `stepSyncV2.test.js:261`: the full run observed two recovered events instead
  of one. All 20 step-sync tests passed on both current-source and baseline reruns.

The three-file current-source rerun finished **58/61 passed**, with only the three
known notification failures remaining. These reruns identify intermittent results;
they do not erase the original full-run failures or prove their root causes are
resolved. No existing assertion was weakened, skipped or deleted.

Logs retained locally: `/tmp/permanent-backend-full.txt`,
`/tmp/permanent-backend-targeted-rerun.txt`, `/tmp/permanent-flutter-final.txt`,
`/tmp/permanent-final-analyze.txt`, `/tmp/permanent-ios-build.txt`, and
`/tmp/permanent-android-build.txt`.

## External verification still required

After code verification, configure stores and RevenueCat using
`bara-billing-store-setup.md`. Then verify real purchases, interrupted recovery,
refunds/reversals, monthly trial conversion, subscription management, and
permanent ownership after reinstall on both stores. Specifically verify Android
permanent acknowledgement without consumption. Compile checks and provider
fixtures cannot substitute for these live store checks.

Manual UI placement: `bara-permanent-premium-ui-checklist.md`.
No production/staging deployment, store configuration, upload or release is
included in this code-only handoff.

## Main-branch save — September 8, 2026

The user explicitly requested committing and pushing the current work directly
to `main` for later resumption, while leaving deployment and ASC/Google Play/
RevenueCat setup for later. No new feature branch is required to resume billing.

Backend billing commit `4b4e563` was merged with upstream `409154a` in `867062d`.
The 18 incoming commits were retained; the only shared modified path was
`prisma/schema.prisma`, which merged additively without conflict. Independent
merge review: SHIP, no findings. Frontend implementation is `2afe99e`.

Post-merge checks:

- The 87-test billing/legal/upstream regression selection passed 84 initially;
  three upstream publication cases failed without a configured Redis instance.
  The complete affected five-test suite then passed 5/5 using a dedicated local
  Redis instance, which was stopped afterward. All selected billing cases passed.
- Full backend unit run: 3,366 passed, four failed, zero skipped (3,370 total).
  All four failures reproduced on unchanged upstream `409154a`: three cases in
  `localGlobalEventEntitlement.test.js` and the mutation-inventory assertion in
  `raceWriteFenceInventory.test.js`. This is not a green full unit result.
- Local test migrations applied and Prisma generation succeeded. No production
  database or service was changed. Frontend runtime code is unchanged from the
  earlier clean analysis, 3,061 passing tests and two native compile checks.
- Staged whitespace checks passed after Markdown hard-break normalization and
  removing extra terminal blank lines in two unshipped migration files.

Resume with `bara-billing-store-setup.md` and the manual UI checklist. Still
required: external product/credential setup, authorized backend deployment, real
store purchase acceptance, and matching signed release artifacts. Repository
push does not claim deployment or customer-release readiness.
