# Full-screen shop deployment readiness

Status: shop implementation, source review and scoped verification complete. **Unconditional production readiness is withheld:** the documented pre-existing backend integration failures need a scope/acceptance decision. This document does not authorize production operations.

## Scope and delivered behavior

The approved [requirements](full-screen-shop-requirements.md) cover the dedicated Shop route with Back and Featured / Powerups / Characters navigation; independently saved character outfits and explicit activation; character-compatible accessories; compact powerup tiles; consistent primary Buy controls; transient billing feedback; and removal of the Profile membership entry. Preview and tutorial use the real routes. Existing ownership, purchase/reward policy and old-client equipment behavior are preserved.

No new art, prices, reward probabilities or accessory SKUs were introduced. No production deployment, content retirement, staging start or app upload has occurred. The separately authorized Birthday Hat grant to stepna is complete and preserved.

Frontend implementation/evidence commit: `7a86729`. Unrelated staged planning documents were preserved.

## Frontend verification

- Complete expanded Flutter suite passed **3,186/3,186** in 123 seconds, including explicit iOS/Android navigation and Profile variants, collection pagination/revision coverage, an Other-owned compatible-empty regression, and real standalone Get Coins checkout lifecycle coverage.
- The 31 affected wardrobe/Profile cases pass. Final analyzer reports **no issues**. Full source review and the final narrow review both returned **SHIP**, with no remaining required changes.
- [Frontend verification](evidence/full-screen-shop-frontend-verification.md) maps old layout assertions to approved behavior. [Command evidence and source fingerprints](evidence/full-screen-shop/frontend-final-checks.json) record the complete expanded run and checked source.
- Historical fixtures adapt old test data only. Dedicated v1 real-screen tests independently prove saved outfits, activation, stale responses, lost-result reconciliation, malformed authority, ownership and unsupported-backend behavior.
- Billing tests cover primary/localized Buy, success/error once, cancellation, pending reconciliation, retry, restore, account changes and disposal. The real Get Coins route also proves toast removal and suppression of late checkout completion after exit.
- iOS edge-back and Android system-back are exercised through the real route stack. Dirty iOS edge-back is disabled by native PopScope semantics; labeled Back retains Keep editing / Discard. Pending writes block exit. Both platforms run Profile absence checks with billing available.

Real offline captures: [Featured](evidence/full-screen-shop/shop-featured-preview.png), [Powerups](evidence/full-screen-shop/shop-powerups-preview.png), [Characters](evidence/full-screen-shop/shop-characters-preview.png), [Wardrobe](evidence/full-screen-shop/shop-wardrobe-preview.png). These use real widgets/bundled sprites at 390 × 844 logical pixels. They are not live-store or physical-device evidence.

## Production-based backend candidate

Production source was verified at `1bcf874f5cd8f2a84e7dbb980aada9c3feca9325`. The original implementation branch did not contain production's seven daily/weekly immediate-join commits. The isolated `shop-wardrobe-release-candidate` branch starts from that exact production source and preserves deployed schema, race/step behavior and worker ordering. Do not deploy the original implementation branch wholesale.

Final compatible-writer release A / rollback target is `00baf02b29e30ccb7c964c493d2d4d76405c2b4a`. B implementation is `65fbea7`; the reviewed candidate is `2f021c2698f41071e526308127ddaf2b6050c35e`. Production and corrected A are both candidate ancestors. The two ancestry reconstructions preserved each tested tree; final runtime, schema, test and terminal-log hashes were independently checked against the [candidate evidence](evidence/full-screen-shop/backend-candidate-checks.json). All original/provisional release hashes are superseded for deployment.

The release has four additive v1 routes, opaque ShopItem IDs, coherent bounded read snapshots, independently revisioned outfits, shared legacy/new writer locking, and projection-authoritative repair. Existing endpoints retain their inputs, outputs and carry-over behavior. A has no v1 endpoints; B can roll back to A while retaining additive schema and inactive outfits. Backend contract fixtures, measured SQL counts/plans and release protocol are retained in the backend candidate's `docs/evidence/character-wardrobe-*` and `docs/character-wardrobe-release.md`.

- Candidate full unit suite: **3,371/3,371 passed**, zero skips.
- Candidate targeted wardrobe/legacy shop/immediate-join checks exposed one account-deletion issue. Real signup automatically creates race assignments, and the deployed deletion handler removed participants before their referencing assignments, returning 500. The narrow transactional cleanup fix first reproduced on exact production source, then passed actual signup → DELETE with rollback, history and peer-data assertions. Combined deletion/wardrobe/immediate-join checks pass 42/42; corrected A passes its relevant three cases.
- Source review returned **SHIP** for production reconciliation, cleanup fix and rollback parity. A-only / mixed A+B / rollback HTTP protocol also passed on the final corrected boundaries; final appearance revision was 4.
- The complete candidate integration suite finished on explicitly verified dedicated local test PostgreSQL: **3,225 tests, 3,142 passed, 82 failed, one existing skip**, in 1,121 seconds. No wardrobe suite failed. The 31 failing suites were compared with exact deployed source on a separate dedicated local test database; that baseline run passed 390/477 with 87 failures. Narrow follow-ups resolved differing failures through production reproductions or reviewed fixture/fallback corrections. This completed broad run predates those corrections; no revised full-suite total is claimed. The exact residual 27-suite inventory and per-case dispositions are in the [baseline comparison](evidence/full-screen-shop/backend-baseline-comparison.json). Source approval does not waive remaining red assertions.

## Final backend checks and remaining scope

Final checks pass: full unit **3,371/3,371**, all wardrobe/account-deletion **29/29**, public Redis/presentation **8/8**, strict queue/no-Redis fixtures **9/9**, isolated PostgreSQL 18 budget **1/1**, and both signup-recovery cases **2/2 on candidate and deployed-source baseline**. Final A-only, mixed A+B and rollback checks pass. The final source/fixture reviewer returned SHIP. All verification processes are terminal; the temporary PostgreSQL 18 cluster was stopped. No staging/production service changed.

The late Redis correction catches a thrown guarded-cache lookup and uses the existing PostgreSQL fallback. Tests now restore previous cache settings. Queue fixtures claim their scenario race through the real database claim/lease/fence path. The apparent signup-recovery over-enrollment was retained seed-catalog contamination: exactly one membership per leftover test seed, not duplicate canonical enrollment. Isolating canonical seeds while restoring prior settings makes the unchanged assertions pass on both branches. No production enrollment defect is established by that test failure.

Remaining failures include deployed policy versus older test expectations (retired DECOY, tournament powerups and team leave), signup/count fixtures, standings index/tie ordering, immutable source-generation performance fixtures, and older queue/event/notification checks. These require focused work on their existing features. They are not all classified as harmless, and restoring older behavior or weakening their assertions is not part of the approved shop scope. The source-generation fixture's 483-versus-1908 count and the standings EXPLAIN 16-versus-15 row count are recorded accurately; neither is mislabeled as a new wardrobe price change or a SQL-query count.

Production source was rechecked at the same deployed base, with exactly two production workers online and staging stopped. The report's local verification does not claim the four new endpoints are deployed.

## Content and fit audit

The [basic catalog audit](evidence/full-screen-shop/shop-wardrobe-catalog-audit.json) and full SELECT-only [reference audit](evidence/full-screen-shop/wardrobe-full-reference-audit.json) cover the complete 69-item catalog and 227 purchase replay records. Final reference checkpoint: 2026-09-09T21:50:28.018Z. Production has no wardrobe tables before A; absence was not interpreted as proven zero saved references.

Classifications: **22 released items**, **13 owned/referenced unreleased items**, **34 needing historical investigation**, **zero proven safe retirement candidates**. All 20 released accessories, including Birthday Hat and earned Legend Crown, are preserved. The retirement manifest is intentionally empty until historical release evidence supports a concrete reviewed list. No ownership/history/assets were deleted.

The explicit fit manifest approves 56 pairs: 19 released non-crown accessories for default and corgi, 18 for turtle excluding shoes. Real frame-0 renderer evidence: [Capybara](evidence/full-screen-shop/wardrobe-fit-default.png), [Corgi](evidence/full-screen-shop/wardrobe-fit-corgi_puppy.png), [Turtle](evidence/full-screen-shop/wardrobe-fit-turtle.png). Crown currently renders a missing-art fallback; turtle shoes do not align convincingly. Those combinations remain preservation-only; actual saved/current legacy combinations remain grandfathered. This is not evidence for every animation frame, CDN path or physical device.

## Handoff and remaining release gates

1. **Complete:** expanded Flutter suite, analysis and both local platform release builds. [Artifact verification](evidence/full-screen-shop/platform-build-verification.json) records actual package versions, SHA-256 hashes and successful bundle validation. iOS export automatic increment was disabled for the validation re-export so both artifacts retain the intended version mapping.
2. **Pending decision:** resolve the documented remaining backend failures as separate scope, or obtain an explicit user instruction on accepting them for this release. Repository AGENTS.md says “never claim done with red tests”; this report does not declare unconditional production readiness.
3. The handoff includes the [manual placement checklist](full-screen-shop-requirements.md#manual-ui-placement-test-plan) and [Profile addendum](full-screen-shop-requirements.md#profile-membership-removal--manual-checklist-addendum). Physical-device and native-store checkout checks remain outstanding; no physical iPhone is currently connected.
4. Production authorization is a separate final step under backend AGENTS.md. Deploy migration/A, drain all old cosmetics writers, reconcile materialized active wardrobes, validate/apply reviewed fits, then B. Preserve exactly two HTTP workers and leave staging stopped. Verify deployed old/new read contracts before later app release.

README remains the build configuration source of truth. The existing iOS define file was checked against all ten required public defines, including the public RevenueCat key and seven retained ad units; inline native units are absent. Both successful local builds retain current version `2.3.13`, iOS build 10 / Android 203140 for validation only. A later store upload requires fresh monotonic build numbers on both platforms. No native dependencies or configuration changed.
