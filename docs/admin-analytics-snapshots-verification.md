# Admin snapshots and purchase usernames — verification

Initial implementation verification was local. Backend runtime `9f6add4` was subsequently deployed to production on 2026-09-13 after explicit user authorization: migration, guarded reload, authenticated snapshot/purchase checks and public health checks passed. Cached production summary returned in 13 ms. No staging startup, app-store upload or app release was performed. See backend `docs/admin-analytics-snapshots-deployment-20260913.md` for deployment evidence.

## Delivered behavior

Admin analytics reuse shared 15-minute snapshots across backend workers. Expired data remains visible while one bounded refresh runs; request concurrency cannot multiply rebuilds. Selected relational data is read in bounded pages and summarized in a DB-free worker thread. Large event summaries remain targeted SQL, with repeated daily scans removed. Cached hits still perform small authorization/configuration reads but no analytics queries.

Recent purchases under Ads & shop → Shop includes coin packs, subscriptions, and in-game purchases, with current public usernames. Renamed/deleted accounts, trials, refunds, ad-assisted acquisitions and unavailable historical cash amounts are explicit. Purchase history is paginated over a fixed trailing 30-day window.

Existing API fields remain compatible with older apps. A newer app on an older backend preserves analytics and shows purchase history unavailable. Backend deployment must precede the app release. No flags, native dependencies, version changes or database pools were added.

## Automated validation

- Flutter analyzer: clean.
- Real widget suite `test/admin_snapshots_purchases_test.dart`: 15/15 pass.
- API wire suite `test/admin_api_wire_contract_test.dart`: 39/39 pass.
- Backend: the final snapshot/purchase HTTP suite passes 17/17, including malformed historical purchase provenance. The other focused suites pass 6 DAU, 24 dashboard blocks, 17 contract and 27 telemetry cases: 91 distinct passing cases across runs. The last combined regression was 63/63 before adding the final provenance case.
- Structural engagement scan guard: passes; checks a performance property not visible through HTTP values.
- Frontend and backend whitespace checks: clean.
- Final iOS device debug build, unsigned, using the README production define file: passed.
- Final Android `prod` debug APK using README production configuration: passed.

These are debug compilation checks, not signed release artifacts or device acceptance tests. Both platforms use the same final Dart implementation.

## Existing failing tests

The broader backend compatibility audit initially passed 85/93 tests across seven suites. Six failures were independently reproduced on unmodified backend HEAD in an isolated worktree: two race-count fixtures do not account for signup-created races, and four onboarding expectations reflect older seed behavior. Two additional fixture assumptions were adapted without weakening assertions: artificial last-seen backdating now also expires its Redis admission proof, and version statistics assertions advance an injected clock through the approved snapshot interval. The final affected batch suite passes 13/15; only its two independently reproduced baseline race-count failures remain.

The protected Flutter dashboard suite had 14/15 failures reproduced before implementation. The system-health suite had 11/15 failures involving obsolete accordion keys; source inspection found the mismatch at HEAD, but this suite was not independently rerun in an isolated baseline. These assertions were not skipped or weakened. The complete repository suites are therefore not claimed green.

## Performance evidence

The backend report `docs/admin-analytics-snapshots-validation.md` and its `docs/evidence/admin-analytics-snapshots/benchmark.json` contain reproducible synthetic fixtures, query counts, timing, transfer size, memory samples and index plans.

Across ten dashboard sections, measured SELECT call time was 7.646 seconds originally, 3.861 seconds with corrected/shared SQL, and 3.867 seconds with hybrid snapshots. A warm summary took 3 milliseconds with zero analytics SQL. Hybrid extraction transferred about 7.82 MB; worker completion heap was 28.1 MB. These are local measurements, not production CPU measurements. The memory approach did not beat optimized shared SQL on this dataset; caching, reuse and eliminating repeated scans deliver the main demonstrated improvements.

Four additive concurrent indexes support bounded purchase pagination. They were applied and verified only in dedicated local test databases. Deployment must execute them outside a wrapping transaction and verify index validity before restarting the existing two production workers.

## Independent review

Final code-reviewer verdict: SHIP for frontend and backend, with no outstanding blockers, issues or nits. The normal Prisma migration deployment path was successfully rehearsed on two local test databases; no custom migration resolution is required.

## Manual acceptance

Run the verbatim [manual UI-placement checklist](admin-analytics-snapshots-purchases-requirements.md#manual-ui-placement-test-plan) on iOS and Android: overview/detail freshness, Shop purchase placement, all four filters, long usernames and pagination. The checklist identifies tutorial surfaces that do not mirror admin analytics. Physical-device visual checks remain outstanding.

## Subsequent TestFlight release

User-authorized 2.3.14 (1) is VALID / IN_BETA_TESTING in the existing bara testers group. Matching Android 203154 is signed and verified locally. See [release evidence](admin-analytics-testflight-2.3.14.md). The earlier no-upload statements describe the initial implementation/backend-deployment turns.
