# Backend catalog authority release

The app previously suppressed specific powerups and supplied bundled product policy when server metadata was absent. This followup to the Decoy/Shop release removes those rules so supported content follows backend availability, prices, upgrade tiers and reward previews. Older installed binaries retain their old filters until updated.

## Backend

Runtime commit: `aa14b99`, deployed and verified live at 20:13 UTC on September 10, 2026. Decoy remains 150 coins and the new preview metadata is present. Code-only deployment; no schema, configuration, price, actual reward-selection or capacity changes. Inventory presentation uses the shared retirement policy after cache reads. Canonical held ownership and slot occupancy remain intact. The optional `powerupData.dropOdds.reelPreviewAvailable` is derived for each viewer using already loaded state, outside shared snapshots, with no new database queries.

Validation: five new real HTTP/Postgres/Redis tests and two malformed-state tests passed; 3,399 unit tests passed. Expanded integration run passed 58/63. The same five C3 artifact/replay/stale-cache failures reproduced on unchanged baseline `29e86f6`; protected assertions were retained. Independent review approved with no required changes.

## App release and review submission

Released to TestFlight: iOS **2.3.13 (19)**, Apple build `4aeba851-b067-45c6-a3d6-76837f109ea0`, verified VALID / IN_BETA_TESTING in the existing bara testers group. Upload succeeded at 20:32:50 UTC on September 10, 2026. Matching Android **2.3.13 / 203149** was built and verified locally; no Play upload.

Runtime commit `d8d26ca`; build-source commit `e85d5a0`. Subsequent commits changed tests and documentation only. All 541 build-source fingerprints remained unchanged. Both signatures, production configuration and fresh compiled code were verified; iOS archive/export executable sections matched, and Android's three ABIs matched fresh compiler output. Existing nonblocking AppLovinSDK/FBAudienceNetwork dSYM warnings remain. Artifacts: `build/release-candidates/backend-catalog-authority-2.3.13-19/`; tag `testflight/2.3.13-19`.

The user subsequently authorized replacing App Review build 15 with build 19 and retaining in-app purchases. At 20:41:37 UTC, replacement submission `be0d34d0-7c8b-4486-a8f4-53b3a4405808` entered WAITING_FOR_REVIEW with four verified items: app version 2.3.13/build 19 and the 500, 2,800 and 6,000 coin packs. Each purchase also reports WAITING_FOR_REVIEW. Existing version metadata and MANUAL release mode were preserved; no customer release was performed.

Bara+ Monthly and Permanent were not submitted: their purchase entry points remain on hold in build 19, and their existing Apple drafts have missing metadata. The user was informed that reviewing them requires an app change and a newer build. No screenshots, pricing or metadata for those drafts were changed.

Final analysis is clean. The full Flutter run passed 3,316 tests and failed 40. All 36 previously documented admin design failures matched baseline `eca6acf` exactly. Four additional guide fixture expectations relied on compiled catalog membership; all four were corrected, and their isolated suites passed (18 guide tests and one Red Card test). No unrelated admin assertions were weakened. Focused authority, purchase, reward, responsive Shop and wardrobe checks passed, and independent review approved the runtime changes.

The Shop now has pencil Edit buttons inside eligible owned character tiles, opening that character's wardrobe directly. The former bottom Edit outfit button is removed. Standard card geometry remains unchanged; large-text layouts gain height to keep the controls readable.

Scope and the manual UI checklist are in [the requirements](backend-catalog-authority-requirements.md).

## Evidence and manual verification

- [Release artifact verification](artifacts/backend-catalog-authority-19/release-verification.json)
- [TestFlight availability](artifacts/backend-catalog-authority-19/testflight-status.json)
- [App Review submission and all three purchases](artifacts/backend-catalog-authority-19/app-review-submission.json)
- [Test baseline comparison](artifacts/backend-catalog-authority-19/test-baseline-comparison.json)

The manual checklist remains in the requirements. On a device, verify Decoy at 150 coins; each eligible character tile's pencil Edit opens the correct wardrobe; the bottom Edit outfit button is absent; repeat Shop tutorial and small-screen/large-text layouts. Automated widget checks cover these routes; no completed manual device pass is claimed.
