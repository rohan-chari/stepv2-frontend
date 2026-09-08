# iOS-first billing setup verification — September 8, 2026

## Deployment update

The user subsequently authorized production backend deployment and TestFlight
upload. Backend `7e27dc1` is deployed, tagged
`deploy/ios-billing-20260908-7e27dc1`. All eleven billing migrations applied
successfully over a direct connection with a 5-second lock timeout and 60-second
statement timeout. Prisma was regenerated before the guarded reload. The reload
passed its topology and pool-budget checks: two HTTP workers, one cron worker,
one resolution worker, aggregate pool ceiling 32; staging remained stopped.
The previous server environment was backed up and its package-lock modification
was preserved byte-for-byte.

Production smoke checks confirmed:

- Public health and legal-page responses succeed.
- Authenticated legacy shop reads return HTTP 200.
- iOS billing bootstrap returns available with five products; Android returns
  unavailable with no products. The existing reviewer used for this check is
  still in the production billing realm; its account was not converted.
- A synthetic TEST webhook returns 401 without authorization and 200 with it.
  Repeating the same event produces one durable inbox row. This verifies the
  backend endpoint, not actual RevenueCat-to-backend delivery or store checkout.
- No unresolved migration failures; referral-contest convergence audits report
  zero missing activity and ownership rows. The existing billing scheduler has
  attempted queued reconciliation. Real provider fulfillment remains untested.
- The balance drift audit reports existing Decoy differences between the live
  configuration and committed snapshot. Live economy settings were preserved.

Xcode reported `Upload succeeded` and `EXPORT SUCCEEDED` for 2.3.13 (3).
Missing dSYM warnings for AppLovinSDK and FBAudienceNetwork did not block upload.
Apple processing is VALID. After recording the exempt-encryption declaration,
the build's internal state reached IN_BETA_TESTING. No App Store review
submission or customer release was requested.

The proposed support Google account does not yet exist in Bara. Obtain its
immutable Google identity before first login and pre-register its hash through
the existing sandbox identity mechanism. Ordinary signup auto-enrolls players
in races, which prevents later sandbox conversion. No support identity has
been registered yet; the mail-only OAuth grant does not expose its user ID.

The sections below retain the pre-deployment preparation record. Their pending
deployment statements are superseded by this update; sandbox account setup,
product localization and real purchase lifecycle tests are still outstanding.

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
