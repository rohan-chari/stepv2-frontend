# Bara+ and coin purchases — product concept

Status: discussion draft, 2026-09-06. User requested planning only. No prices,
benefit quantities, implementation, or release are approved by this document.
This is an early product proposal, not an implementation-ready requirements spec.

## Product proposal

Keep one visible coin balance. Sell three coin packs. Coins buy existing shop
items and optionally fund the existing box reroll instead of a rewarded ad.
Bara+ is a monthly membership offering ongoing personalization, a cosmetic-shop
discount, and an allowance of included ad-free rerolls.

| Offer | Proposed contents | Status |
|---|---|---|
| Small coin pack | 100 coins, US reference $0.99 | Existing Aug 18 planning candidate; reconfirm |
| Medium coin pack | 550 coins, US reference $4.99 | Existing Aug 18 planning candidate; reconfirm |
| Large coin pack | 1,200 coins, US reference $9.99 | Existing Aug 18 planning candidate; reconfirm |
| Coin-funded reroll | Spend coins instead of watching the existing reroll ad | Price unresolved |
| Bara+ | Monthly cosmetic, member profile treatment, cosmetic-shop discount, included reroll allowance | Monthly price, discount, and allowance unresolved |

Prices displayed to customers come from their platform store and locale.
Do not label an offer popular without actual supporting purchase data.

## Membership value and boundaries

- Grant a curated cosmetic each paid billing period and keep it owned after
  normal cancellation. Decide how calendar-themed releases map to billing periods
  before promising a specific monthly schedule.
- Member badge/profile customization and discount last through paid entitlement.
- Discount initially applies to coin-priced cosmetic goods, not powerups,
  upgrades, rerolls, cash coin packs, or the subscription itself.
- Included rerolls substitute for ad/coin payment. All methods share the same
  one-reroll-per-item limit and outcome rules. There are no extra paid attempts.
- One included credit replaces one existing ad action, including Reroll All;
  clearly disclose batch coverage. Grant allowances once per paid billing period,
  not again at a calendar-month boundary. Prevent cancel/resubscribe double grants.
- Propose no monthly coin stipend initially: the above benefits already have
  value and their interaction should be understood before adding coin issuance.
- Start with one monthly subscription tier. Annual terms and trials are future
  decisions after the value and renewal pattern are understood.
- Normal cancellation stops renewal; perks remain until the paid period ends.
  Coins and owned cosmetics remain. Refund/revocation behavior requires a
  separate purchase policy and implementation spec.
- Reroll allowance reset, rollover, and expiry must be explicit before pricing;
  recurring membership benefits must not be confused with separately purchased
  consumable balances.

## Customer experience

Use the existing playful shop style and capybara content, with a compact Bara+
card showing the current cosmetic. Do not introduce a new bottom-navigation tab.

1. Shop: retain existing store/inventory and category navigation. Add a membership
   card and label eligible cosmetic member prices clearly. Excluded powerups
   keep normal pricing. Members see allowance and benefit status.
2. Get Coins: three straightforward pack cards plus accessible existing earn
   methods. Keep purchase amounts, localized prices, and confirmation explicit.
3. Reroll: use one action opening payment choices (included allowance when
   available, watch ad when available, or coins). Display actual applicable odds,
   replacement warning, and coin cost before confirmation. Keeping the original
   item without rerolling remains easy. Once rerolled, all payment choices close.
4. Bara+ detail: show this period's cosmetic, exact discount eligibility,
   allowance/reset terms, localized recurring price, renewal disclosure, and
   manage/restore access. Avoid interrupting race results with a subscription pitch.
5. Profile/settings: provide membership status and manage/restore access.

## Balance and business reasoning

Coin packs already enable paid powerups; cosmetic-only membership discounts do
not remove that existing competitive tradeoff. Paid rerolls add convenience;
even identical odds can increase usage. Do not sell better odds or additional
attempts to subscribers.
Cosmetic savings also indirectly free coins for powerups. Before pricing rerolls,
check whether rerolling then discarding rewards can return more coins than the
reroll cost, including batch sizes and available daily discard rewards.

A hypothetical 20% shop discount gives 25% more purchasing power on eligible
goods. For an unchanged basket it reduces coin removal by 20%. This is math,
not a selected discount. Model discount, included rerolls, coin-pack purchases,
and displaced rewarded-ad revenue together before assigning benefit amounts.

Measure net purchase/subscription revenue after fees/refunds, ad revenue,
subscription renewals, retention for paying and nonpaying players, coin balances
and sinks, and race outcomes. Engagement with ad rerolls is not proof of paid demand.

## Implementation constraints for the later spec

Existing anchors: `lib/screens/get_coins_screen.dart:29`,
`lib/screens/tabs/shop_tab.dart:174`, and reroll flows in
`lib/screens/race_detail_screen.dart:7322`. Prior pack proposal:
`docs/feature-batch-2026-08-18-requirements.md:43`. Older economy section 13 pack
prices conflict with that proposal and must not silently be reused.

The later spec must reconcile prior purchase limits/provenance rules and all
single/batch reroll paths; pin server-authoritative grants, entitlements, prices,
refunds, duplicate prevention, and atomic debit+reward before implementation.
One visible balance does not imply losing purchase provenance internally.

Support iOS and Android together, including restore/reinstall and account
switches. Old binaries continue earning/spending and rendering existing content;
new offers must not require old clients to handle new fields. Backend first,
then both apps, with no new release flags. New cosmetic availability must respect
the repo's bundled-art/version compatibility requirement. No final API contract
or migration design is being claimed at this concept stage.

Apple and Google require ongoing subscription value; purchased random rewards
require odds disclosure. The final proposal must meet both policies without
assuming store approval:
- https://developer.apple.com/app-store/review/guidelines/
- https://support.google.com/googleplay/android-developer/answer/9900533
- https://support.google.com/googleplay/android-developer/answer/9858738

## Decisions to resolve next

1. Accept cosmetic-only discount eligibility, or deliberately include powerups?
2. Commit to recurring cosmetic production, or choose a different ongoing benefit?
3. Select subscription price, discount, reroll price and allowance together.
4. Specify billing-period reward schedules, allowance rollover, refund behavior,
   item ownership, and cross-platform entitlements.
5. Decide the cosmetic substitute for an already-owned reward, including
   resubscriptions; define what an active member sees and receives on older apps.

## Revision log

- Pass 1: separated historical pack candidates from approval; restricted discount
  eligibility; clarified shared reroll cap and no unsupported popularity labels.
- Pass 2: added cancellation/ownership, allowance ambiguity, prior-spec conflicts,
  both-platform/version constraints and explicit early-concept status.

## Review and manual placement plan

Economy review: sound with changes. Incorporated batch credit semantics,
billing-period grants, indirect competitive effects, and reroll/discard analysis.
Architect concept review: approved with no required changes; added duplicate
cosmetic and older-member experience decisions from its suggestions. This is
concept approval only, not user approval or implementation authorization.
No UI or purchase implementation has been performed.

Manual UI-placement checklist (ui-test-planner, verbatim):

1. **Shop — real screen:** **Get there:** Home → Shop, using member and nonmember test accounts. **Verify:** One membership card above the catalog; member pricing beside eligible item prices, including item details; no duplicated card or competing purchase controls.
2. **Get Coins — shared screen:** **Get there:** Home coin balance → Get Coins; repeat through Shop coin balance and Shop’s insufficient-coins prompt. **Verify:** The same three packs appear once in each route, with existing free earning options still reachable.
3. **Membership detail — real screen:** **Get there:** Shop → Bara+; repeat from Profile → Bara+. **Verify:** Both reach the same layout; benefits precede purchase/manage controls, restore is reachable, and no second membership page appears underneath.
4. **Race boxes — real screens:** **Get there:** Active race → open one box; repeat with multiple saved boxes → Open All. **Verify:** Funding choices sit together below revealed rewards; the former standalone ad button is absent; continue/close remains reachable. Repeat on iOS and Android.
5. **Held powerups — separate sheets:** **Get there:** Active race → inventory → an eligible held powerup; repeat with a Pocket Watch. **Verify:** Both sheets use the agreed reroll placement without retaining a duplicate ad-only action.
6. **Tutorial mirrors:** **Get there:** Profile → Settings → Help & Legal → View Shop Tutorial, then View Tutorial. **Verify:** Shop’s four spotlights still ring their targets after adding the card; Profile’s membership entry follows the agreed preview treatment; Home and race inventory spotlights remain correctly positioned.
7. **Demo race — onboarding:** **Get there:** Fresh account → onboarding → demo race → box-opening beat. **Verify:** Reveal and continue controls remain clear of coach chrome; paid controls are absent if demo purchasing is intentionally excluded, with no duplicated actions.

Placement risks: Open All, held-item and Pocket Watch sheets have separate
controls. Shop and tab tutorials are separate; Profile preview reuses the real
tab. Paid choices must not disappear merely because rewarded ads are unavailable.
Proposal: preview/demo flows never initiate real purchases; keep membership
entries out of scripted tutorial targets until their explicit preview is designed.
