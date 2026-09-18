# Meta, Shop, artwork and Red Card release — 2026-09-10

User explicitly authorized production backend deployment after unrelated-failure
verification, then App Store Connect upload using the existing API key. This is
not App Review submission or customer-release authorization.

## Backend production

- Deployed `3a60332e17dac7f843f107fb788e8479875104ef` from origin/main; previous
  compatible revision `68da3a1fc7b01461b0bed9ddc18e8d1862382ff4`.
- Independent final deployment review: SHIP. All 92 original full-suite failures
  were accounted for: 88 baseline-reproduced; four isolated passes on changed
  code. Full suite remains red, as disclosed and conditionally accepted.
- No schema, dependency or runtime configuration change. Read-only migration
  census: 256 applied, zero unfinished, zero missing. The legacy helper expected
  laptop-only `PROD_DATABASE_URL`; the equivalent read-only census used the
  server's existing connection without modifying its env.
- Preserved server `.env` and modified `package-lock.json`, byte-compared after
  deployment. Backup directory: `/root/backups/meta-shop-red-card-20260910/`.
- Canonical copy preview showed only the Red Card description change; applied
  through the audited npm command. Current and legacy catalog requests returned
  HTTP200 and the 10,000-step cap description.
- Guarded PM2 reload passed: exactly two HTTP workers, one resolution, one cron;
  aggregate pool ceiling32. Staging stayed stopped; all previous PIDs exited.
- Required referral audit/apply/audit returned zero missing/inserted rows.
- Public health and both privacy routes returned200. New privacy bundle served.
  Authenticated Redis check returned PONG. No production attack/test fixtures ran.

## Artwork and goodwill

- Both new immutable PNG URLs returned200 and matched the SHA-256 values in
  `meta-batch-production-handoff.md` before either catalog update.
- Existing admin PATCH contracts switched Turtle to `a87ad177f0a0` and Hitchhike
  to `6fbfe79192cf`. Exact bounded SQL comparisons proved every other catalog
  column unchanged. Turtle peer mirror returned attempted=true, ok=true.
- Public manifest confirmed both new URLs and Turtle animationFrames=8. Existing
  immutable URLs remain available. An already-open app may need a catalog refresh.
- Soch received +500 through the existing ledgered grant CLI, using one-connection
  process-local `all` pool configuration. Preview was read-only; exact canonical
  identity and existing ledger were checked first. Exactly one +500 admin_grant
  row verified for reference `red-card-goodwill-2026-09-10`. Restricted identity,
  balance and ledger evidence stays in the server backup directory. No notification,
  message or historical step reversal was sent/performed.

## Mobile upload

- Frontend runtime source `13e0d8f`; subsequent economy/release notes are docs only.
- iOS2.3.13(13): API-authenticated Xcode upload succeeded at12:16:52UTC, with
  `Upload succeeded` and `EXPORT SUCCEEDED`, exit0. Apple subsequently confirmed VALID / IN_BETA_TESTING, automatically present in
  bara testers; build ID `b0e24778-757a-4d77-8285-eb7ade3da3cd`,
  checked12:33:43UTC. No export-compliance or tester-group mutation was needed.
- Existing AppLovinSDK and FBAudienceNetwork missing-dSYM warnings remain
  nonblocking; there was no CoreKit symbol-upload failure.
- Matching Android2.3.13/203143 signed production AAB built and verified; retained
  locally, no Play upload requested.
- Exact signed artifact hashes and configuration checks are in
  `meta-batch-validation.md`; final pair/logs under
  `build/verification/meta-batch-dart-defines/`.
- ASC key path, ID and issuer are now stored in ignored local `.env` (0600), per
  user request. Actual private key remains in its pre-existing external location.
  Neither repository tracks a private-key file; `.env` is not a Flutter asset.
  No private-key contents or credential values were printed by the env update.

## Remaining user checks

[Manual Shop/device checklist](shop-sectioned-frontend-validation.md) covers both
platforms and mirrored screens; full scope is in `meta-app-events-requirements.md`.
Actual Meta Events Manager receipt/AEM eligibility needs the installed carrying
build. Pinned-SDK intercepted-request tests do not prove live campaign eligibility.
