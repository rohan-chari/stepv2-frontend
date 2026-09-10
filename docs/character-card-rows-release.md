# Character card rows correction

The user corrected the build22 layout: character cards must match existing
Leech/Xray merchandise cards, rather than floating action pills. Unowned cards
use artwork, separated full-width name, then full-width gold price strip; no
standalone Buy button. Tapping the card/price opens the existing purchase flow.
Owned cards use full-width stacked Edit and Equip rows. Preserve server price
and policy, account guards, revision handling, and purchase confirmation.

This supersedes build22's side-by-side buttons and the extra minimum card width
used to fit those buttons. Match the established artwork/name/price geometry
and styling; preserve artwork scale and avoid an additional OWNED text row.
Keep tutorial anchor and update its copy to refer to the coin-price row.
No backend, economic, artwork, or store-product change. Both platforms use
shared Dart. Prior implement-and-release authorization continues for this
correction: target iOS2.3.13(23), matching Android203153, TestFlight and replaced
App Review submission with all3coin packs500/3000/7500. Manual customer release.

## Manual UI-placement checklist
1. Home → Shop → Characters: compare unowned Turtle with Leech/Xray; artwork,
   separated full-width name then coin price. Owned cards stack Edit then Equip.
   No standalone Buy, floating pills, duplicate price or inset oversized Edit.
2. Home coin-balance + → Characters: same row order; price opens purchase,
   Edit opens customization, Equip has no intermediate menu.
3. Settings → View Shop Tutorial → character step: spotlight includes complete
   card/action rows; guide chrome does not obscure them; return leaves no menu.
4. Billing preview → Shop/Coins → Open Shop → Characters: same separated rows.
Repeat on both platforms, narrow screens and larger text. Demo race and tab
onboarding do not render these cards; wardrobe accessory grid is unchanged.

Tests-first row regression failed against build22;335/335tests across16relevant
suites pass after correction. Analysis and diff-check clean, independent review
SHIP. Five real-widget captures pass and were inspected (390/375/360px,
320px at1.6text scale, night). Screenshots use preview fixture prices; actual
prices remain backend-controlled. Prior36Admin baseline failures not rerun.
Artifact and final submission verification in progress.
