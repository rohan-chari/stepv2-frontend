# Backend catalog authority release

The app previously suppressed specific powerups and supplied bundled product policy when server metadata was absent. This followup to the Decoy/Shop release removes those rules so supported content follows backend availability, prices, upgrade tiers and reward previews. Older installed binaries retain their old filters until updated.

## Backend

Runtime commit: `aa14b99`, deployed and verified live at 20:13 UTC on September 10, 2026. Decoy remains 150 coins and the new preview metadata is present. Code-only deployment; no schema, configuration, price, actual reward-selection or capacity changes. Inventory presentation uses the shared retirement policy after cache reads. Canonical held ownership and slot occupancy remain intact. The optional `powerupData.dropOdds.reelPreviewAvailable` is derived for each viewer using already loaded state, outside shared snapshots, with no new database queries.

Validation: five new real HTTP/Postgres/Redis tests and two malformed-state tests passed; 3,399 unit tests passed. Expanded integration run passed 58/63. The same five C3 artifact/replay/stale-cache failures reproduced on unchanged baseline `29e86f6`; protected assertions were retained. Independent review approved with no required changes.

## App and release status

Target: iOS 2.3.13 (19), Android 2.3.13 / 203149. App verification, signed builds and TestFlight processing are pending. Do not interpret this preparation record as a completed release.

The previous release's 36 unrelated admin design test failures were reproduced on baseline `eca6acf`; this followup will report its final test results separately.

Scope and the manual UI checklist are in [the requirements](backend-catalog-authority-requirements.md).
