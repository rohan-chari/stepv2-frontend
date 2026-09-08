# iOS-first billing setup verification — September 8, 2026

The user explicitly authorized iOS-only preparation and deferred Android.
RevenueCat iOS products, Apple credentials, notification settings and webhook
have been configured through the dashboard. Public and server keys are saved
in private, gitignored local configuration; no secrets belong in this report.

## Changes and checks

- Backend checkout availability now requires the requested platform's app ID.
  Shared reconciliation requires either configured store. iOS can therefore
  operate before Android setup; Android still reports unavailable checkout and
  retains the existing wallet/member response fields. No release flag was added.
- Regression tests first reproduced unavailable single-store bootstrap and
  recovery. Final checks passed: 80 billing/legal HTTP/database integration
  tests, 9 existing provider/date/scheduler tests, 66 Flutter billing tests and
  clean Flutter analysis. All database tests used the dedicated local test DB.
- Independent code review found no blockers in the final changes.
- Signed `build/ios/ipa/Bara.ipa`: version 2.3.13, build 3, bundle
  `com.rohanchari.steptracker`. Archive signature verified. All eleven expected
  production values were found in the app executable: backend URL, iOS SDK key,
  eight AdMob values and Google OAuth client ID. Server secrets were absent.
- IPA SHA-256:
  `d1bc5f3f939c2c1348c39f7400864058e100fe66ded2d5435db9fdaf63c8be05`.
- No upload, production mutation, staging startup or customer release occurred.

## Deployment still required

Read-only inspection found production at `8dbcca0`, without the billing module
or billing environment configuration. The final local source retains that
deployed summary-processing fix. Preserve the remote package-lock change when
preparing the deployment; do not reset the checkout blindly.

Apply the eleven billing migrations (from `20260907170000_bara_billing_v1`
through `20260908110000_permanent_source_provenance`) and regenerate Prisma
before starting the new runtime. Existing shop reads use the billing tables
even before checkout is configured, so migration-first ordering protects older
app versions. Install the prepared iOS-only environment, deploy the committed
legal pages, and reload the existing two HTTP workers and the existing worker
companions as required by the deployment runbook. Keep staging stopped.

After deployment, verify authenticated webhook delivery, the existing billing
reconciliation scheduler, old-client shop requests and sandbox bootstrap. A
fresh isolated Bara sandbox account is needed for TestFlight purchase testing;
ordinary player accounts reject sandbox fulfillment. Follow the lifecycle
matrix in [the store setup guide](bara-billing-store-setup.md).

The backend's `AGENTS.md` requires explicit confirmation before production
deployment or database changes. This document records preparation, not approval.

## Apple metadata

TestFlight uses sandbox purchases. Apple's minimum product metadata for sandbox
testing is the reference name, product ID, localized name and price. Complete
the missing product localizations before checkout tests. A review screenshot is
not listed in that minimum; full submission metadata and review remain separate
requirements. [Apple sandbox testing](https://developer.apple.com/documentation/storekit/in-app_purchase/testing_in-app_purchases_with_sandbox).
