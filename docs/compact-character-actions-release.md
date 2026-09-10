# Compact character actions release

Authorized: update character price/action presentation, upload to TestFlight,
and replace the waiting App Review submission with the new build and all three
coin-pack products. Customer release stays manual. Target iOS2.3.13(22),
matching Android203152 (built and verified locally; no Play upload requested).

Unowned character cards show the backend gold price and Buy. Owned characters
show compact Edit and Equip actions; active state remains visible. Existing
purchase confirmation, server policy, revisions, idempotency and account guards
are retained. No backend change, price change, migration, or new artwork.
Backend default-outfit revision correction340b405 is already live.

App Store preflight confirmed build21 waiting for review and all three coin
packs500/3000/7500 included. The same purchase IDs, configured prices, product
metadata and review screenshots are retained. Bara+ drafts remain outside the
currently enabled coin-pack flow and are not represented as submitted.

All39new real-screen regressions pass; flutter analyze clean. Independent
reviewSHIP after semantic tap, stale confirmation, phone artwork, and tablet
minimum-width fixes. Five real-widget visual captures passed (390/375/360px,
320px at1.6text scale, and night theme), recorded under docs/artifacts.
Full suite:3395passed/41failed. Exactly36failures match the previously
recorded unrelated Admin baseline; five assertions still targeted the removed
menu/icon/geometry and were updated to the requested direct actions. Final
rerun of all15affected suites:295/295passed, including all39new regressions.
No remaining change-related failures. Signed artifact/submission verification
is in progress.
Manual placement checklist: [requirements](compact-character-actions-requirements.md#manual-ui-placement-test-plan).
