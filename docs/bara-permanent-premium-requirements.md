# Monthly Bara+ and permanent premium

Status: implementation authorized by the user: “finish all code” before external
ASC/GP/RC setup. Use the stated timing recommendations below. Supersedes the
annual sale option in the previous billing plan.
No production/store configuration has been changed.

## Confirmed scope

Offer monthly Bara+ and one-time permanent premium; remove annual from new sales.
Keep existing coin packs and monthly $4.99 benefits unless explicitly changed.
Use RevenueCat for both platforms. Permanent premium is a non-consumable purchase,
not an auto-renewing subscription with an artificial expiry. Existing account,
sandbox, verified-payment, refund and restore safeguards remain applicable.

## Approved product terms — 2026-09-07

- Monthly Bara+: $4.99/month, seven-day trial. Existing monthly paid bundle stays
  500 coins + 10 paid reroll credits per actual payment.
- Permanent Bara+: $19.99 once; 500 coins + 10 paid reroll credits every month
  forever. No trial on the one-time purchase.
- Same 15% shop discount, member styling and UTC calendar cosmetic benefits.
- Coin packs, 50-coin reroll price, credit rollover, original-account ownership,
  sandbox isolation and bounded refund shortfall policy remain unchanged.
- Permanent costs approximately 4.006 monthly payments. User chose the price;
  this is an intentional commercial tradeoff, not a pending pricing proposal.

## Final timing and overlap policy

User authorized finishing all code after the recommendations were presented.
Use these defaults, announced again at implementation start:

1. Initial permanent bundle immediately, then purchase-anniversary monthly.
   Missed months accumulate without an activity requirement.
2. With existing verified paid subscription coverage, permanent access begins
   immediately, but its first currency bundle waits until that paid period ends.
   The original period end becomes the immutable anniversary anchor. A trial
   does not delay permanent rewards; its remaining temporary credits end on
   the verified permanent payment. Ignore later renewals when setting an
   already-persisted anchor; every actual separate subscription payment still
   receives its existing bundle. Existing paid coins/credits remain usable.
3. Restore, additional store receipts, refund reversal and repurchase never reset
   the identity schedule. Month-end dates clamp against the original UTC day.
4. Same UTC calendar cosmetics begin at permanent purchase, independently of the
   delayed currency anchor. Refunded access stops future rewards. Reversal restores
   the original interval and unissued owed rewards, without duplicating prior grants.

Lifetime ownership retains management links and clear cancellation guidance for
separately active subscription payments. The non-consumable does not cancel or
replace a monthly subscription. New monthly/annual checkout is unavailable while
permanent access is active. Historical annual receipts remain recognized; annual
is not offered for sale even against an older backend. No external setup is in
scope for this code implementation.

## Code impact and implementation order

1. Backend catalog `src/modules/billing/catalog.js`: retire annual from offers,
   add versioned permanent non-consumable product. Retain historical annual
   receipt recognition for compatibility; never reinterpret an annual SKU.
2. Provider `services/revenueCatProvider.js`: verify non-consumable ownership,
   purchase/revocation/refund/reversal and sandbox provenance through existing
   paginated reconciliation. Receipt presence alone cannot imply permanent access
   after refund. Coin consumables must not accidentally receive access.
3. `models/billingState.js`, `queries/bootstrap.js`, `services/memberPrice.js`:
   represent durable permanent access independently of subscription expiry;
   combine qualifying sources, retain monthly management information, support
   revocation and restoration, and select one shared effective discount.
   Determine additive schema/migration with durable period grants as below.
4. Introduce unique per-identity,
   benefit-period grants and durable due work. Store renewal webhooks cannot
   schedule these because a non-consumable has no renewals. Define UTC/anniversary
   boundaries, catch-up, overlap and refund provenance explicitly in final spec.
5. Preserve paid-credit carryover and UTC cosmetic publication, with permanent
   eligibility and explicit overlap/refund behavior. Avoid replaying an upfront
   bundle on restore or across devices/accounts.
6. Frontend `lib/models/billing.dart`, `live_billing_controller.dart`,
   `store_billing_client.dart`: distinguish lifetime product from consumable coin
   products and subscriptions, parse nullable expiry defensively, support exact
   transaction recovery, show permanent ownership and retain original-account
   restrictions. Permanent ownership must not be reduced to an expired timestamp.
7. `bara_plus_screen.dart`, billing cards and previews: replace annual
   offer with one-time disclosure and accurate benefit copy; no navigation redesign.
   Disable repeat lifetime purchase; retain restore and subscription management
   where relevant. Mirror real/demo/tutorial surfaces.
8. Update setup guide, contract, public terms/privacy as needed, deployment
   instructions and tests. Prepare exact product IDs and store configuration
   after approved policy; do not reuse annual identifiers.

## API and compatibility

Keep routes and existing response fields. Add optional permanent plan/access
metadata and a distinct non-consumable kind. Do not repurpose subscription
renewal fields; membership expiry may legitimately be null for permanent access.
Old clients ignoring unknown products must remain usable. Test both old frontend
against new backend and new frontend against absent/old billing capabilities.
Backend deploy precedes app release, with separate production approval.

## Additive data model and API

- Add a permanent-access record tied to the original billing identity and verified
  source purchase. Store access/revocation state, immutable reward anchor,
  next-due cursor and eligibility version. Keep a source record per verified
  purchase so multiple-store receipts do not erase refund provenance.
- The permanent purchase itself grants zero direct coins/credits: activation
  creates the reward schedule, and period zero is its only initial bundle.
  Catalog coins/credits describe recurring benefits, not generic receipt grants.
- Add permanent reward grants unique by identity, immutable benefit version and period
  index; each links to its source purchase, exact period boundary, 500-coin ledger
  entry and 10-credit lot. Ledger/grant/credit/cursor writes are one transaction
  behind existing identity lease and wallet ordering. No grant from client time.
- Batches of at most 12 overdue reward periods per identity transaction process overdue periods, persist progress, and requeue remaining
  work. Wakeup is the minimum of provider reconciliation due and reward due; do
  not create another unbounded full-table cron scan. Recovery must work without
  login, SDK callbacks or store renewals. Missing provider data is not a refund.
- Refund/revocation disables future source-funded grants and uses all attributable
  grants to bound recovery from current balance, preserving earned-coin recovery,
  unused-credit revocation, no debt and retained cosmetics. A reversal restores
  entitlement and only reverses actual recovery; define eligibility intervals
  explicitly so refunded gaps and duplicate receipts cannot mint extra bundles.
- Retain current HTTP routes, status/error codes and `bara-billing-v1` fields.
  Add catalog product `{id:"plus_permanent",kind:"non_consumable",plan:"permanent",
  coins:500,credits:10,storeProductId:"bara_plus_permanent_v1"}` for both stores.
  Extend recognized plans; unknown products remain safely ignored by older UI.
- Permanent membership example:

```json
{
  "givesAccess": true,
  "status": "active",
  "plan": "permanent",
  "accessUntil": null,
  "renews": false,
  "discountPercent": 15,
  "nextRewardAt": "2026-10-07T18:00:00.000Z",
  "subscription": {
    "plan": "monthly",
    "renews": true,
    "accessUntil": "2026-09-20T18:00:00.000Z"
  }
}
```

Top-level `managementUrl` remains present for a separately active/cancelled-but-
unexpired subscription. `subscription` is optional/null when absent. Existing
`credits`, `coins`, `cosmetic`, legal URLs and reroll fields are unchanged.
Paid pack purchases never grant permanent access. Repeated permanent checkout
on another store must not create an additional reward schedule.

## Architect-required implementation refinements

- One immutable schedule per identity; no new schedule generation on restore,
  second-store purchase, repurchase or reversal. Sources are per canonical receipt.
  A valid second source preserves access when another is refunded. Choose the
  earliest eligible valid source deterministically for each unissued period; an
  issued grant's source never changes. No retroactive extra schedule.
- Anniversary boundaries derive from the original UTC anchor each time (Aug 31 →
  Sep 30 → Oct 31, at the same UTC time), rather than adding a month to the last
  clamped date. For delayed first rewards, use the original paid
  period end as the permanent anchor, including legacy annual coverage. The announced recommendations are the implementation policy.
- Every actual later monthly/legacy annual payment retains its existing bundle,
  even if the user has not cancelled that separate subscription. Explain this
  overlap accurately. Neither discounts nor permanent schedules duplicate.
- A currently revoked source cannot fund new historical currency grants, even
  for boundaries before its refund. Keep intervals for explicit reversal and
  historical cosmetics; never mint refunded backlog during catch-up.
- Track source eligibility/refund intervals durably. Reversal restores access
  retrospectively for the reversed interval and catches up unissued eligible
  periods. Return only previously recovered coins/credits, never absorbed debt.
  Repeated cycles must preserve per-grant recovery totals and operation IDs.
- Postgres owns access, schedules, grants, due work and eligibility intervals;
  no Redis dependency for money. Preserve worker-zero ownership, existing durable
  leases and request-generation fencing. Index next due time. Limit catch-up to
  12 periods per transaction, requeue remaining work immediately; never discard
  owed periods. During provider outage retain known access but defer new grants
  until successful verification, then catch up on original boundaries.
- Permanent receipt activation is fulfilled even if its first reward is deferred;
  exact native transaction sync must not remain pending until next month.
- Freeze final full bootstrap examples and non-consumable provider state mapping
  before frontend implementation. Cover permanent-only, permanent+monthly, refunded
  permanent+monthly, and historical annual. Never infer purchase ownership solely
  from the aggregate entitlement shared with monthly. Unknown/pending purchase
  states cannot activate permanent access.
- New frontend suppresses annual offers even against the older backend. Preserve
  historical annual membership presentation/management. Test the frozen decoder
  and screen: current code maps unknown permanent plan to null and then renders
  monthly benefits, so unknown-product ignoring alone is insufficient. Resolve
  compatibility presentation in the final contract before coding.
- Android installed dependency is purchases 10.19.1 via hybrid-common 18.33.1,
  above documented 7.11.0 non-consumable support. Still require actual store proof
  that permanent is acknowledged without consumption and survives reinstall.
- Extend tests for repeated refund/reversal, second receipts, late/out-of-order
  evidence, provider outages, month-end anchors, interrupted catch-up, and
  delayed initial reward completing checkout before any currency grant.

Architecture final review APPROVED this policy update; backend pinned complete
response fixtures in bara-billing-contract.md before frontend implementation. The UI checklist is saved verbatim in
`bara-permanent-premium-ui-checklist.md` for final spec approval.

## Store setup changes (external work deferred)

Apple: keep monthly auto-renewing subscription, create non-consumable
`bara_plus_permanent_v1` at US $19.99; do not create yearly for this launch.
Google: keep `bara_plus_v1:monthly`, create one-time permanent product with the
same permanent identifier and configure RevenueCat non-consumable treatment.
Attach monthly and permanent to entitlement `bara_plus`; keep coins unattached.
Verify actual native dependency supports Android non-consumables, direct product
fetch uses nonSubscription, and repeat checkout cannot consume/rebuy permanent.
Keep server notifications and historical refund export recovery for one-time
purchase refunds. Update setup guide and public terms only after final spec.

## Tests first / acceptance

Real HTTP + dedicated test DB: verified permanent purchase, repeated sync and
restore, refunded/reversed permanent access, other-account receipt, sandbox
isolation, both-access-source combinations, retained paid credits, calendar grants,
missed callbacks/webhooks, killed-app recovery and retired annual historical
receipts. For recurring permanent rewards, test boundaries, overdue
catch-up, concurrency and unique grant provenance through public/worker paths.

Pump real Flutter screens: monthly versus permanent pricing/disclosure, no annual
sale, permanent ownership with null expiry, product loading/cancellation/pending,
restore, monthly management while permanent, missing backend fields, and tutorial
purchase isolation. Run clean analysis and both native builds. Obtain architecture,
economy, UI-placement and implementation code reviews before handoff.

## UI scope clarified during placement review

Settings has no existing Bara+ purchase/management tile. Do not add one implicitly;
verify its tutorial entrypoints instead. PreviewBillingController hand-forks plan
and scenario fixtures: add permanent and permanent-with-monthly fixtures. Keep
disabled BillingScope in real-screen tutorials, including nested Shop → Get Coins.

## Revision log / gap passes

- Pass 1: permanent access cannot use subscription expiry or renewal events;
  identified provider non-consumable verification and internal grant scheduling.
- Pass 2: separate ownership from underlying monthly subscription management;
  preserve historical annual receipts and define duplicate reward/refund rules.

## References

- https://www.revenuecat.com/docs/platform-resources/non-subscriptions
- https://www.revenuecat.com/docs/getting-started/entitlements
- https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-types

## Implementation authorization and final gap pass

The user explicitly requested completing all code; do not add another approval
gate. Backend pins the additive contract first, then the two implementation agents
work against it. Root owns public legal pages, setup documentation and integration
verification. Required final code review and both platform verification remain.

## Manual UI-placement test plan

The planner text below is preserved verbatim. Its then-pending timing reference
is now resolved by the final timing policy above. Settings entrypoints remain
tutorial-only; no additional billing tile is part of this change.

**Manual UI-Placement Test Plan — Monthly and permanent Bara+**

*Elements under test:*\
Replace the yearly purchase option with permanent premium beside monthly.\
Add permanent ownership and next-reward information to the membership screen.\
Retain subscription management and add cancellation guidance when permanent ownership overlaps a monthly subscription.\
Update existing Shop, Get Coins and Profile membership cards without moving navigation.

*Checklist*

1. **Real membership screen — available offers**
   - **Get there:** With a nonmember test account, open Shop → Bara+.
   - **Verify:** Monthly and permanent options appear together in the existing offer area. The yearly purchase option is absent. Monthly trial information stays with monthly; permanent purchase information stays with permanent. Purchase, restore and legal controls remain reachable below the benefits without duplicate buttons.

2. **Real membership screen — permanent owner**
   - **Get there:** With a permanent-owner test account, open Profile → Bara+.
   - **Verify:** Permanent ownership and the next-reward date appear in the membership area. No repeat permanent-purchase button or monthly signup remains. Restore and legal controls remain reachable. There is no empty expiry placeholder or leftover yearly selector.

3. **Real membership screen — permanent plus monthly**
   - **Get there:** Use a prepared account with permanent access and a separate renewing monthly subscription → Profile → Bara+.
   - **Verify:** Permanent ownership remains visible alongside the monthly management link and cancellation guidance. They do not replace or cover each other. If guidance uses a dialog, both its action and dismissal remain visible. Next-reward placement follows the approved overlap policy; its exact timing is pending that decision.

4. **Real entry points and navigation**
   - **Get there:** Visit Shop, Profile, Home → Get Coins, and Shop → an unaffordable item → Get Coins.
   - **Verify:** Shop and Profile each retain one membership card below their header. Get Coins retains one membership card after coin packs and before earning options. Each opens the updated membership screen. Profile’s badge remains beside its existing identity area. No yearly sales tile, extra tab or duplicated membership card appears; back navigation returns to the originating screen.

5. **Standalone billing preview**
   - **Get there:** Open the supplied billing-preview build → Preview Controls; select nonmember, permanent-owner and permanent-plus-monthly scenarios.
   - **Verify:** Check its Plus, Shop, Coins and Profile pages against checkpoints 1–4, including Shop → Get Coins. Annual offers are absent here too. Preview-only navigation stays confined to this build.

6. **Settings and tutorial mirrors**
   - **Get there:** Profile → Settings → View Tutorial; then Settings → View Shop Tutorial. In shop replay, open Get Coins through the coin entry and an unaffordable item where available.
   - **Verify:** Tutorial screens and nested Get Coins contain no membership sales cards or permanent offers. Existing tutorial spotlights still surround their intended elements. Settings retains its existing layout; no duplicate billing entry appears.

7. **Both platforms and constrained layouts**
   - **Get there:** Repeat the membership offer and overlapping-membership screens on iOS and Android, using the smallest available device and enlarged system text.
   - **Verify:** Options, ownership, next-reward information and cancellation guidance do not overlap. Purchase/management, restore, legal and back controls remain reachable by scrolling and clear the bottom system inset.

*Surfaces confirmed unaffected:*\
Demo race tutorial and race-detail tutorial preview: shared race screens are wrapped in disabled billing scopes; neither hosts the membership offer selector.\
Single/multiple box-opening screens and race reroll sheets: no plan-selection or ownership placement changes are proposed.\
Home, Races, Friends and leaderboard content: no membership selector is embedded; Home only routes to Get Coins.\
Production and tutorial tab bars: separate implementations exist, but neither requires a placement change.\
Settings: no existing Bara+ purchase or management tile was found; its relevant routes are tutorial replay.

*Risks found while planning:*\
Preview plans and account scenarios are hand-maintained; permanent ownership and overlapping monthly access need explicit fixtures.\
The current membership screen assumes monthly/yearly selection in several places; replacing only the offer tile can leave a yearly change-plan dialog or stale controls.\
Permanent owners with a remaining monthly subscription need both access information and management controls visible together.\
Tutorial billing-card absence is intentional here because those hosts explicitly disable billing; nested Get Coins must preserve that scope.
