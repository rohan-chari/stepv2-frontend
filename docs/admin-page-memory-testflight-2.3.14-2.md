# Per-page admin snapshots — TestFlight 2.3.14 (2)

The user authorized production deployment and the carrying TestFlight update. All nine admin analytics pages now request their own 15-minute snapshot. Unopened pages do no analytics work; expired completed snapshots remain visible while one refresh runs. Purchase history and usernames remain independently paginated. System Health retains its separate live refresh.

## Verified source and artifacts

Frontend implementation `94ee67b` passed 77 focused tests and independent SHIP review. The final 2.3.14+2 source also passed `flutter analyze --no-pub`; all 549 source/configuration/artwork fingerprints were unchanged at upload. Existing assertions were preserved. The manual UI placement checklist is in `docs/admin-page-memory-requirements.md`; physical device execution remains pending.

Both production artifacts were built and verified:

- iOS 2.3.14 (2): distribution signature, production APNs, bundle/team identity, all 12 required defines, native Meta configuration, current compiled pending-status UI, archive/export executable sections and retained assets.
- Android 2.3.14 / versionCode 203155: production flavor/backend/ad configuration, upload signature, non-debuggable manifest, all three fresh AOT ABI libraries through merge/strip/package stages, current UI and retained assets. The previous generated app output was isolated before building with Gradle caching disabled, then removed after verification.

Android uses the next monotonic code above 203154. The ordinary decimal version formula would regress below previously uploaded 2.3.13 builds, so the existing documented monotonic exception continues. Both platforms retain version name 2.3.14.

The new status text contains a Unicode ellipsis and is stored as UTF-16 in Dart AOT. Artifact inspection verifies the actual UTF-8 or UTF-16 representation, rather than incorrectly treating absence from ASCII strings as stale code.

Artifacts and verification reports are retained under ignored `build/release-candidates/admin-page-memory-2.3.14-2/`. No private keys or local define values are committed.

## Backend deployment verified first

Production runtime `9471f15` passed all nine view checks, with cached requests taking 7–80 ms. Cold Activity completed in about 23 seconds with pending follow-ups. The old full Activity endpoint returned 200 after its expected initial cold 503; purchase records contain username fields. There was no schema migration or capacity change. Two HTTP workers, one resolution worker and one cron worker retain pool ceiling 32; staging remains stopped. The backend passed 97 distinct HTTP tests and independent SHIP review.

These are individual smoke timings, not sustained-load or database-CPU reduction claims. Backend release evidence is in its `docs/admin-page-memory-deployment-20260913.md`.

## Apple upload status

Upload succeeded at 2026-09-13T22:12:29Z using the existing App Store Connect API key, with both `Upload succeeded` and `EXPORT SUCCEEDED`. Apple build `2bf70a28-b993-4f79-af0d-80feb07f33a8` is **VALID / IN_BETA_TESTING**, confirmed in the existing **bara testers** internal group at `2026-09-13T22:18:18.735Z`. The unchanged exempt-encryption declaration matches the prior verified build. The existing AppLovinSDK and FBAudienceNetwork missing-dSYM warnings repeated; they did not block upload. No new SDK or native configuration changes were introduced. No App Review submission, customer release or Google Play upload is included.
