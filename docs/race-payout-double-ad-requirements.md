# Race-payout double rewarded ad — requirements

> **Product correction — 2026-08-18:** the hard bonus ceiling is **100 coins**
> per results batch and per rolling 24-hour provider identity. The August 17
> “full additional copy” override is revoked. The authoritative formula is
> `bonusCoins = min(baseCoins, 100, rolling24hRemaining)`, where the rolling
> allowance starts at 100. Any older `500` examples below are historical design
> records, not the live limit. Offer preparation and claim settlement must each
> independently enforce the 100-coin ceiling; a persisted legacy offer above
> 100 is serialized, claimed, and durably repaired at no more than 100.

Status: **Implementation complete; corrected backend deployment pending**
Owners: frontend + backend  
Platforms: iOS and Android  
Last updated: 2026-08-18

## 1. Summary and user story

When the existing Home race-results popup reports one or more newly completed
races, a user who earned qualifying **system-funded** race prize coins may
watch one rewarded ad to receive up to 100 additional coins from those combined
prizes, capped at **100 bonus coins per results batch and per rolling 24 hours**. If the
popup contains qualifying prizes of 40, 0, and 80 coins, it
presents one offer for **+100 coins**; one completed, server-verified ad grants
100 more coins. If the combined payout is 800, the offer clearly says **+100
maximum bonus** rather than falsely promising a complete double. It does not
grant the combined amount per race or double the user's entire wallet.

As a racer reviewing newly completed races, I want one clear chance to watch an
ad and double the race coins shown in this results batch, so that the reward
feels connected to the races I just finished.

The current app already batches unseen completed races in
`lib/screens/main_shell.dart:1920` and renders each settled
`myPayoutCoins` value in `lib/screens/race_results_summary_screen.dart:26`.
The backend persists the display payout on `RaceParticipant.payoutCoins`
(`prisma/schema.prisma:1203`) and exposes it as `myPayoutCoins` from
`src/modules/races/queries/getRaces.js:387`. The new bonus must use that stored
server value, but eligibility comes from authoritative `CoinTransaction` rows
with reasons `race_prize_pool_payout` or `race_finish_reward`. Legacy
`race_buy_in_payout` transfers and refunds are never doubled. The client never
submits a coin total.

## 2. Product behavior

### 2.1 Eligible results batch

- A batch consists of the completed, accepted, unseen race rows that the
  existing `_maybeShowRaceResults` flow places in one popup.
- The backend returns a top-level `payoutDoubleOffer` only to a client that
  advertises the new `race_payout_double` capability and only while the remote
  kill switch is enabled and the dedicated unit allowlist is non-empty.
- The offer's `raceIds` must match the not-yet-doubled eligible rows in the
  completed page returned by that same `GET /races` request. Every offer ID
  must be present in the popup batch, but the popup may also contain a
  previously doubled race after a lost response/relaunch. The completed page is already
  capped by the existing query; older unseen results, if any, form a later
  popup/offer after the first page is acknowledged.
- `baseCoins` is the sum of eligible positive system-funded coin-ledger credits
  attributable to those races. `myPayoutCoins` remains display-only and may be
  larger when it includes a legacy buy-in transfer. Zero/ineligible races stay
  visible in the results batch but add zero to the offer.
- Attribute eligibility with **exact** ledger keys for the authenticated user
  and that participant's persisted placement:
  `reason = race_prize_pool_payout` with
  `refId = <raceId>:<placement>`, or `reason = race_finish_reward` with
  `refId = <raceId>:rank:<placement>`, and `amount > 0`. Use equality against
  the fully constructed ref ID—never a broad reason sum, prefix/`LIKE`, or
  client value. Mixed/malformed/collision-like ref IDs contribute zero.
- No offer is returned when `baseCoins <= 0`, every eligible payout in the
  batch was already offered, rolling allowance is zero, preparation policy or
  cohort is off, the dedicated AdMob unit allowlist is empty, or the client
  capability is absent.
- `bonusCoins = min(baseCoins, 500, rolling24hRemaining)`. The rolling allowance
  is `500 - sum(RacePayoutDoubleVelocityGrant.bonusCoins where claimedAt is in
  (databaseNow-24h, databaseNow])` for the durable provider identity and is
  computed under that identity-row lock. Before an ad is
  loaded, the backend persists one offer containing the exact eligible race
  participants and their authoritative payout snapshot. A unique item row per
  participant prevents a modified client from splitting one popup into several
  offers to bypass the cap. A user may have at most one `PENDING` offer; no
  later/disjoint batch is prepared until it becomes terminal.

### 2.2 Popup interaction

Preserve the existing arcade/parchment result presentation. Below the race
cards, add a compact gold reward plaque that reads:

> **DOUBLE +120 COINS**  
> Watch one ad to get another 120.

When `bonusCoins == 500 && bonusCoins < baseCoins`, truthful maximum copy is:

> **GET THE MAX +500 BONUS**  
> Your qualifying race prizes earn the maximum ad bonus.

For every other partial award, render the actual server value without “double”
or “maximum,” for example:

> **GET +50 BONUS COINS**  
> Watch one ad to earn 50 bonus coins on your qualifying race prizes.

The plaque, button label, loading/retry/early-close/success text, and accessibility
semantics always use the actual `bonusCoins`. “Double” is allowed only when
`bonusCoins == baseCoins`; “MAX +500” is allowed only for an actual 500 bonus.

The rewarded action is a full-width, visually primary `PillButton` with a
video/play mark. The existing `START YOUR NEXT RACE` and `NICE` actions remain
available and keep their current navigation results. The screen must never
trap a user behind an ad.

States:

1. **No offer / unsupported:** render the existing popup byte-for-byte, with no
   reserved gap.
2. **Loading ad:** disable only the rewarded button and show concise
   `LOADING AD…` progress; navigation/dismiss remains available.
3. **Ad unavailable:** keep the popup open, restore the enabled action, and
   show `Ad didn't load. Your coins are unchanged.`
4. **Ad closed early / no earned callback:** no claim request and no coins;
   show `Finish the ad to earn +<bonusCoins> bonus coins.`
5. **SSV pending:** show `VERIFYING…`; retry the claim with the same offer ID
   up to five times at two-second intervals, matching the existing rewarded
   reroll pattern.
6. **Success:** update `AuthService` from the authoritative returned balance,
   replace the offer with an earned state such as
   `120 PAYOUT + 120 AD BONUS`, and
   leave the normal results dismissal/next-race action available. Do not show a
   second ad action.
7. **Already claimed / lost-response retry:** render the same success state
   from the idempotent server response without another grant.
8. **Claim rejected, disabled, or stale batch:** no optimistic balance change;
   remove an ineligible offer or provide a retry for a transient error using
   server error codes defined below.

Accessibility: the action's semantic label includes the exact bonus and that
an ad will play; loading/success changes are announced; 44-point minimum tap
target, dynamic text, narrow phones, landscape, light/dark palettes, and reduce
motion must remain usable.

### 2.3 Results acknowledgement

The current shell marks every shown race seen after the popup route closes
(`lib/screens/main_shell.dart:1987`). Keep that contract:

- Watching or claiming does not itself dismiss the popup.
- Dismissing or starting the next race still calls `POST /races/results/seen`
  for the entire shown batch.
- Explicit dismissal by a capable client permanently forfeits every unclaimed
  offer in that shown batch. There is no later claim screen, inbox item, or Home reminder. Before
  route close, the app durably queues a user/backend-scoped results
  acknowledgement, suppresses those IDs locally, and retries the unchanged
  seen request until the server commits.
- A successful claim marks the immutable offer `CLAIMED`; it does not update
  settlement-sensitive participant rows or mark results seen. Unique offer
  items plus terminal offer status are the durable doubled/forfeited marker.
- Before showing the ad, create/reuse one server-owned pending offer for the
  exact batch. If the app dies after preparation or the earned callback/SSV but
  before claim, the next capable `GET /races` returns that pending offer ID so
  the client retries it before offering another ad. Pending-offer selection and
  popup construction explicitly precede the shell's `myResultsSeen == false`
  filter: recovery remains available even if a tokenless client marked those
  participants seen. This is completion recovery, not a separate later offer.
  A capability-bearing `POST /races/results/seen` atomically forfeits any
  pending offer touching the dismissed rows, so explicit capable-client
  dismissal is permanent across sessions once acknowledged. A second device
  can remain stale only until that acknowledgement reaches the server.

## 3. Scope

In scope:

- One combined rewarded-ad offer on the existing race-results popup.
- Exact server-side summation of all eligible race payouts in that popup.
- AdMob SSV verification, grant consumption, idempotent coin ledger writes,
  remote kill switch, client capability gate, and defensive UI behavior.
- Separate dedicated rewarded ad unit IDs for iOS and Android.
- AdMob console setup steps and production/staging release notes.
- All active build commands and ad-unit documentation in `README.md` and
  `DEPLOYMENT.md`, plus the synchronized command summaries in `AGENTS.md` and
  `CLAUDE.md` if those summaries enumerate rewarded defines.
- Frontend widget/integration coverage and backend HTTP integration coverage.

## 4. Non-goals

- Doubling the user's wallet balance, referral rewards, step milestones, daily
  rewards, tournament rewards, shop refunds, buy-in transfers, or any ledger
  source outside the two exact eligible race reasons in §2.1.
- Replacing the existing results popup or results-seen endpoint.
- Interstitial ads, banner changes, ad mediation changes, or a reusable generic
  multiplier system.
- Client-attested ad completion or client-calculated payouts.
- Deploying to production without a separate, in-the-moment approval.

## 5. API contract

All response reads in the app are defensive. Missing/null/malformed new fields
mean “feature unavailable”; they never prevent results from rendering or being
acknowledged.

### 5.1 `GET /races` — additive offer

Request header for capable builds:

```http
X-Client-Features: ...,race_payout_double
```

Existing response keys are unchanged. When eligible and enabled, add:

```json
{
  "active": [],
  "pending": [],
  "completed": [
    {
      "id": "race-a",
      "myStatus": "ACCEPTED",
      "myResultsSeen": false,
      "myPayoutCoins": 40
    },
    {
      "id": "race-b",
      "myStatus": "ACCEPTED",
      "myResultsSeen": false,
      "myPayoutCoins": 80
    }
  ],
  "payoutDoubleOffer": {
    "offerId": null,
    "raceIds": ["race-a", "race-b"],
    "baseCoins": 120,
    "bonusCoins": 120,
    "maxBonusCoins": 500,
    "rolling24hRemainingBeforeClaim": 500
  }
}
```

Rules:

- `payoutDoubleOffer` is omitted, not null, unless every server-side eligibility
  rule passes.
- `offerId` is null before preparation. If an exact pending server offer already
  exists (for example after app termination), it is a UUID string and the app
  attempts its claim before loading another ad. In that recovery case,
  `MainShell` limits this popup to the offer's race IDs; any race that completed
  after the offer was frozen stays unseen for the next popup. This preserves
  “all races shown are one batch” and prevents dismissal from forfeiting a
  newer race that was never part of the watched ad.
- Load a user's pending offer from Postgres before prospective derivation. For
  capable clients, inject all of its item races into `completed` even if more
  than 10 newer completions would normally evict them. Tokenless responses keep
  the existing capped completed query byte-compatible.
- Return that pending offer before every prospective gate. Recovery ignores the
  current prepare switch, rollout percentage, rolling allowance, cap decrease,
  and `resultsSeenAt`, and remains visible while claims are disabled so the UI
  can show temporary unavailability. This supports mixed-version accounts where
  a tokenless device acknowledged results after a capable device prepared the
  otherwise invisible entitlement.
- Only literal positive integers are valid for `baseCoins`/`bonusCoins` in the
  app. Race IDs must be non-empty strings and every offer ID must occur exactly
  once among the popup's shown IDs; otherwise the app hides the offer. Popup
  races absent from the offer still render normally and add nothing to the
  bonus.
- `maxBonusCoins` is informational and must equal or exceed `bonusCoins`.
  Missing/malformed values hide the offer rather than allowing misleading
  copy. The app never hardcodes payout math; it renders the server's bounded
  `bonusCoins` and selects capped/qualifying copy whenever
  `bonusCoins < baseCoins`, whether caused by the batch cap, rolling allowance,
  or a downward-tuned cap.
- Defensive parsing requires
  `0 < bonusCoins <= min(baseCoins, maxBonusCoins,
  rolling24hRemainingBeforeClaim)` and `maxBonusCoins <= 500`.
- `baseCoins` means qualifying system-funded prizes, not necessarily the sum of
  displayed `myPayoutCoins`. Copy must say “qualifying race prizes” whenever
  those differ. The response also includes positive
  `rolling24hRemainingBeforeClaim`; malformed/missing allowance hides the offer.
- The offer is informational, not authority. The claim endpoint re-reads all
  race/participant rows under transaction and recomputes the amount.

Old clients do not send the feature token, receive their current response, and
ignore additive fields even if a proxy/cache ever includes them. A new client
against an old backend sees no `payoutDoubleOffer` and renders today's popup.

### 5.2 `POST /races/results/double-payout/offer` — freeze the batch

Authenticated request, sent only after the user taps the rewarded action and
before any ad is loaded:

```json
{
  "raceIds": ["race-a", "race-b"]
}
```

Success (`201` for a new offer, `200` for idempotent recovery):

```json
{
  "offerId": "d05cb2a4-16b7-463f-977d-58231987a0ac",
  "raceIds": ["race-a", "race-b"],
  "baseCoins": 120,
  "bonusCoins": 120,
  "maxBonusCoins": 500,
  "rolling24hRemainingBeforeClaim": 500,
  "status": "PENDING"
}
```

Rules:

- Require authentication, the `race_payout_double` capability,
  `ADS_RACE_PAYOUT_DOUBLE_PREPARE_ENABLED=true`, non-empty allowlist, positive
  rolling allowance, and membership in the deterministic rollout percentage.
  Bound `raceIds` to the existing 10-row completed page and require distinct
  valid IDs. Otherwise create nothing.
- Re-read the same capped completed page used by `GET /races`. The submitted
  set must exactly equal its current eligible not-yet-offered set. This check
  happens before ad playback, so a mismatch costs no ad and tells the app to
  refresh.
- In one transaction, revalidate every participant/race, compute the server
  eligible ledger sum, rolling-24-hour allowance, and bounded bonus; create one
  `RacePayoutDoubleOffer`, and create one immutable
  offer-item snapshot per race participant.
- A concurrent/retried exact request returns the existing pending offer only.
  A different request while any pending offer exists returns
  `409 OFFER_PENDING` and creates no rows.
  Unique participant item rows make overlapping/subset/superset offers fail
  closed; the client refreshes instead of creating a second batch.
- Enforce the one-pending invariant with a transactional user-row lock and a
  PostgreSQL partial unique index on `user_id WHERE status = 'PENDING'`. A
  concurrent exact loser rolls back before reading/returning the winner.
- Once created, later race completions do not change this offer. They belong to
  a later results batch.

### 5.3 `POST /races/results/double-payout/:offerId/claim` — redeem verified ad

Authenticated request has no client-controlled amount or race list:

```json
{}
```

The AdMob request sets:

```text
user_id    = <authenticated user id>
custom_data = race_payout_double:<user id>:<offerId>
```

Success (first redemption):

```json
{
  "awarded": true,
  "alreadyClaimed": false,
  "baseCoins": 120,
  "bonusCoins": 120,
  "maxBonusCoins": 500,
  "rolling24hRemainingBeforeClaim": 500,
  "coins": 845,
  "raceIds": ["race-a", "race-b"]
}
```

Idempotent replay after the original response was lost:

```json
{
  "awarded": false,
  "alreadyClaimed": true,
  "baseCoins": 120,
  "bonusCoins": 120,
  "maxBonusCoins": 500,
  "rolling24hRemainingBeforeClaim": 500,
  "coins": 845,
  "raceIds": ["race-a", "race-b"]
}
```

Validation and authority rules, in state-check order:

- Validate authentication, canonical offer ID, and ownership first. `CLAIMED`
  returns HTTP 200 with immutable offer amounts/IDs and the user's **current**
  authoritative balance, even if the feature was later disabled.
- Only `PENDING` proceeds and requires capability, non-empty allowlist, and
  `ADS_RACE_PAYOUT_DOUBLE_CLAIM_ENABLED=true`. Turning preparation off does not
  invalidate an already-prepared/verified entitlement. The claim switch is an
  exceptional exploit brake, not the normal rollout control. `FORFEITED`
  returns its terminal 409.
- Lock the offer, immutable item snapshots, current participants, and grant.
  Current races must remain completed and owned by the same user. A capable
  acknowledgement forfeits pending offers; a tokenless acknowledgement may
  mark results seen but does not invalidate an invisible offer.
- Recompute the current payout sum and require it to equal the immutable
  eligible ledger-source sum and require it to equal the immutable `baseCoins`
  snapshot. The offer's bonus already freezes both cap snapshots;
  ignore all AdMob reward amount/item strings.
- Consume exactly one unconsumed `AdRewardGrant` for this user with
  `rewardKind = race_payout_double` and `contextId = offerId`.
- Require that grant's signed `adUnit` to be an exact member of the backend's
  configured dedicated iOS/Android race-payout-double unit allowlist. A
  modified client must not turn an SSV callback from extra-spin, get-coins, or
  reroll into a variable-value race payout.
- In one DB transaction, credit only through
  `awardCoins({ tx, userId, amount: bonusCoins, reason:
  "race_payout_ad_double", refId: offerId })`, mark
  the offer `CLAIMED`, stamp the consumed grant's `consumedAt`,
  `rewardType = COINS`, and `coinAmount = bonusCoins`, then return the
  authoritative balance.
- `CoinTransaction`'s existing unique `(userId, reason, refId)` constraint
  (`prisma/schema.prisma:506`) is the second idempotency fence behind the
  unique offer items, conditional offer transition, and consumed grant.
- A retry of the same claimed offer returns immutable offer fields plus the
  user's current authoritative balance. Offer items'
  unique participant IDs prevent any selected race from entering a new offer.

Error responses retain the standard `{ "error": "..." }` key and add `code`:

| HTTP | Code | Meaning / client behavior |
| --- | --- | --- |
| 400 | `INVALID_REQUEST` | Malformed/duplicate IDs or offer ID; hide/reload offer. |
| 401 | existing auth code | End flow; normal auth handling. |
| 403 | `PREPARATION_DISABLED` | No new offer: switch, cohort, capability, allowance, or configuration disallows preparation; collapse prospective panel. |
| 403 | `CLAIMS_DISABLED` | Confirmed-exploit brake is active; preserve the pending offer and show temporarily unavailable rather than consuming/forfeiting it. |
| 404 | `OFFER_NOT_FOUND` | Unknown/foreign batch; refresh races and remove stale offer. |
| 409 | `OFFER_CHANGED` | Preparation snapshot no longer matches; refresh before any ad. |
| 409 | `OFFER_PENDING` | Another batch is unresolved; recover it first. |
| 409 | `OFFER_FORFEITED` | Results were dismissed; no credit or later recovery. |
| 409 | `RESULTS_ALREADY_SEEN` | Offer expired by dismissal elsewhere; remove offer. |
| 409 | `AD_NOT_VERIFIED` | SSV has not arrived; bounded retry with the same offer ID. |
| 503 | `REWARD_TEMPORARILY_UNAVAILABLE` | Keep coins unchanged and allow retry while popup remains open. |

### 5.4 `GET /ads/ssv` — additive reward namespace

Keep the existing unauthenticated, signature-verified callback contract
(`src/modules/economy/routes/ads.js:12`). Extend the custom-data parser in
`src/modules/economy/commands/grantAdReward.js:10` with:

```text
^race_payout_double:([^:]+):(<canonical RFC 4122 UUID>)$
```

A canonical UUID parse from an allowlisted unit stamps
`rewardKind = race_payout_double` and the offer ID into a new nullable
`contextId`. The user ID repeated in custom data must exactly match the signed
callback's `user_id`; otherwise no usable race-double grant is created. Any
payload beginning with reserved `race_payout_double:` that fails UUID,
embedded-user, or unit validation fails closed with HTTP 200 and no grant. Reject
the namespace at grant creation when `ad_unit` is not allowlisted, while still
returning HTTP 200 to prevent Google retry storms. Legacy fallback applies only
outside all reserved namespaces; it must never reinterpret a malformed reserved
payload as an extra spin. Duplicate
AdMob transaction IDs continue returning HTTP 200 without minting a second
grant.

### 5.5 `POST /races/results/seen`

No request/response shape changes. In one transaction it still marks the shown
participant rows seen and now also marks every `PENDING` payout-double offer
touching those same user-owned participants as `FORFEITED` **only when the
request advertises `race_payout_double`**. A tokenless/old/missing-define client
may mark results seen but cannot forfeit an offer it never displayed; a later
capable response injects that pending offer's races and may claim it despite
`resultsSeenAt`. Unknown IDs remain safe no-ops. This capability-aware coupling
makes explicit capable-client dismissal permanent
server-side. The client durably queues this unchanged call before route close
and retries transient failures; only a successful transaction establishes
cross-device forfeiture.

## 6. Data model and migration

One additive migration in the backend repo (exact relation names may follow the
schema's conventions, but the constraints are contractual):

```prisma
model RacePayoutDoubleOffer {
  id              String   @id @default(uuid())
  userId          String   @map("user_id")
  baseCoins       Int      @map("base_coins")
  bonusCoins      Int      @map("bonus_coins")
  maxBonusCoins   Int      @map("max_bonus_coins")
  rolling24hRemainingBeforeClaim Int @map("rolling_24h_remaining_before_claim")
  providerSubHash String   @map("provider_sub_hash")
  status          String   @default("PENDING") // DB CHECK below
  claimedAt       DateTime? @map("claimed_at")
  forfeitedAt     DateTime? @map("forfeited_at")
  createdAt       DateTime @default(now()) @map("created_at")
  items           RacePayoutDoubleOfferItem[]

  @@index([userId, status, createdAt])
  @@map("race_payout_double_offers")
}

model RacePayoutDoubleOfferItem {
  id                String @id @default(uuid())
  offerId           String @map("offer_id")
  raceParticipantId String? @unique @map("race_participant_id")
  raceId            String? @map("race_id")
  raceIdSnapshot    String @map("race_id_snapshot")
  eligibleCoins     Int    @map("eligible_coins")
  sourceReason      String @map("source_reason")
  sourceRefId       String @map("source_ref_id")

  @@unique([offerId, raceIdSnapshot])
  @@map("race_payout_double_offer_items")
}

model AdRewardGrant {
  // existing fields...
  contextId String? @map("context_id")

  @@unique([userId, rewardKind, contextId])
}

model RacePayoutDoubleIdentity {
  providerSubHash String   @id @map("provider_sub_hash")
  cohortBucket    Int      @map("cohort_bucket")
  createdAt       DateTime @default(now()) @map("created_at")

  @@map("race_payout_double_identities")
}

model RacePayoutDoubleVelocityGrant {
  id              String   @id @default(uuid())
  providerSubHash String   @map("provider_sub_hash")
  offerId         String   @unique @map("offer_id")
  bonusCoins      Int      @map("bonus_coins")
  claimedAt       DateTime @default(now()) @map("claimed_at")

  @@index([providerSubHash, claimedAt])
  @@map("race_payout_double_velocity_grants")
}

model RacePayoutDoubleClaimReceipt {
  offerId          String    @id @map("offer_id")
  providerSubHash  String    @map("provider_sub_hash")
  bonusCoins       Int       @map("bonus_coins")
  claimedAt        DateTime  @map("claimed_at")
  accountDeletedAt DateTime? @map("account_deleted_at")

  @@index([claimedAt])
  @@map("race_payout_double_claim_receipts")
}
```

Required SQL/relations omitted from the abbreviated display above but required
in the real Prisma schema/migration:

- offer → `User(userId)` with `onDelete: Cascade` and the user back-relation;
- item → offer with `onDelete: Cascade` and the shown `items` back-relation;
- item → `RaceParticipant(raceParticipantId)` and item → `Race(raceId)` with
  nullable `onDelete: SetNull` relations so the existing account deletion,
  sentinel reassignment, and rollback paths never fail. Immutable snapshot
  fields retain the opaque race ID, exact eligible reason/ref, and amount for
  reconciliation after relational targets disappear;
- `CHECK (status IN ('PENDING','CLAIMED','FORFEITED'))` (or an additive Prisma
  enum with those exact values);
- partial unique index
  `CREATE UNIQUE INDEX ... ON race_payout_double_offers(user_id) WHERE status = 'PENDING'`.
- identity/velocity/claim-receipt tables deliberately have **no User foreign key** and never
  cascade on account deletion. They contain only the SHA-256 provider-sub hash,
  stable bucket, amount, opaque former offer ID, timestamp, and deletion
  tombstone. Use the existing
  provider-neutral `hashAppleSub(user.appleId || user.googleSub)` pattern; raw
  provider subjects never enter these tables. Velocity and claim-receipt rows
  are retained for at least 48 hours, safely beyond the rolling/reconciliation
  window, under the economy audit retention policy.
- DB checks require identity bucket `0..99`, item `eligibleCoins > 0`, velocity
  and claim-receipt `bonusCoins > 0`, and offer
  `0 < bonusCoins <= maxBonusCoins <= 500` plus nonnegative remaining allowance.

- Both new tables start empty; no backfill is required. Existing participants
  become prospectively eligible only through a capable request with unseen
  results, a positive combined payout, configured unit allowlist, and the
  default-off feature switch; deployment alone exposes nothing.
- Do not reinterpret `shopItemId` to hold a race offer ID. It is already the
  product identifier for shop unlock grants; repurposing it would create a
  cross-feature compatibility trap.
- No destructive migration, enum change, or required column is introduced.
- The unique offer-item `raceParticipantId` is the durable per-race fence and
  also makes forfeiture permanent. The offer freezes `baseCoins`, the cap, and
  rolling allowance before ad playback; each item freezes only qualifying
  system-funded ledger coins. `AdRewardGrant.contextId` binds a signed
  callback to that server-issued offer and supports lost-response replay.
- The composite unique constraint makes one client attempt resolve to at most
  one SSV grant. PostgreSQL permits the existing rows' null `contextId` values
  to coexist, so old reward kinds are unaffected.
- Offers, items, grants, ledger rows, cap snapshots, and every eligibility,
  authoritative preparation, claim, and forfeiture read are Postgres-only
  sources of truth. `GET /races` may use cached rollout settings only to hide a
  prospective panel; preparation rechecks Postgres directly.
  Redis must not supply values, locks, queues, or settlement authority; it may
  only receive the existing post-award cache invalidation. Tests run with
  `REDIS_URL` unset.
- Preparation, claim, and results-seen share one global lock order:
  durable provider-identity row → authenticated `user` row → `offer` rows ordered by ID → offer items ordered
  by participant ID → participant rows ordered by ID → matching grant → coin
  award. Every terminal change is a conditional `PENDING → CLAIMED` or
  `PENDING → FORFEITED` update. Retry the whole bounded transaction on Postgres
  `40P01`/serialization failure; never continue a partially failed lock path.
- Upsert then lock the durable provider-identity row at preparation. Derive its
  cohort bucket once from the stable provider hash and persist it. Compute the
  rolling allowance from `RacePayoutDoubleVelocityGrant` using the database
  clock and half-open window `(databaseNow - 24 hours, databaseNow]`. Claim
  inserts the velocity row and immutable claim receipt atomically with
  `awardCoins` and the offer/grant transitions. Delete/recreate with the same
  Apple/Google identity therefore retains allowance usage and cohort
  membership. Account deletion joins the same global lock order by acquiring
  the durable provider-identity row and then the user row before any payout
  offer/receipt query. Before the existing cascade, that transaction stamps
  `accountDeletedAt` on receipts selected through the user's claimed offer IDs.
  A concurrent claim therefore either loses before settlement or commits a
  receipt that deletion must observe and tombstone. This leaves no user foreign
  key or raw identity behind while distinguishing an explained cascade from
  settlement corruption.
- If implementation shows that concurrent offer assembly needs a covering
  index, add a narrow participant index only after checking the real query
  plan; do not speculate a broad index into the migration.

## 7. Backend implementation plan

Write the backend integration tests first and run them only against a confirmed
local/disposable `*_test` Postgres database.

1. Add the tables, nullable grant context, relations, and constraints described in
   §6.
2. In `src/modules/economy/adRewards.js`, add
   `RACE_PAYOUT_DOUBLE_REWARD_KIND` and a runtime
   preparation/claim policy. `ADS_RACE_PAYOUT_DOUBLE_PREPARE_ENABLED` defaults
   false and stops only new offers; `ADS_RACE_PAYOUT_DOUBLE_CLAIM_ENABLED`
   defaults false before launch, then remains true during normal rollout stops
   so prepared entitlements can settle. Parse a comma-separated
   `ADMOB_RACE_PAYOUT_DOUBLE_AD_UNIT_IDS` allowlist defensively; empty or
   malformed configuration keeps the feature off.
   Add `RACE_PAYOUT_DOUBLE_MAX_BONUS_COINS`, accepted only as an integer in
   `1..500` with a safe fallback of 500 for zero, negative, malformed, or
   greater values. The server response owns the value so future downward tuning
   does not require an app release or make frozen clients calculate it.
   The same bounded value is the rolling-24-hour cap; do not introduce a second
   independently tunable limit in this release.
3. Extend `grantAdReward.js` to recognize only the exact new custom-data
   namespace, verify its embedded user and allowlisted signed unit, and persist
   its server-issued offer ID as `contextId`, without changing any old prefix or bare-date
   behavior.
4. Add a small race-domain query/service that derives the prospective offer
   from the completed rows already selected for `GET /races` and Postgres coin
   ledger rows with reasons `race_prize_pool_payout` or `race_finish_reward`.
   Explicitly exclude `race_buy_in_payout`, refunds, and all other reasons. Do
   not issue a divergent uncapped race query that could advertise races the
   popup cannot show.
5. Gate the top-level offer on the `race_payout_double` client feature, runtime
   prepare switch, non-empty dedicated-unit allowlist, deterministic rollout
   cohort, and positive rolling allowance.
6. Add `createRacePayoutDoubleOffer` and `claimRacePayoutDouble` in the
   race/economy boundary. Preparation validates the exact current eligible
   page and freezes it; claim re-reads and locks the persisted offer,
   participant, race, and grant rows without regenerating a moving global batch,
   and performs grant consumption, offer transition, ledger award, and
   response snapshot in one transaction.
7. Add the preparation and claim routes before parameterized `/:raceId` routes
   so Express never interprets `results` as a race ID. Update the existing seen
   command to forfeit touching pending offers in the same transaction as the
   acknowledgement.
8. Use the durable offer/grant/coin-ledger/velocity/claim-receipt rows for
   initial operational metrics;
   no new speculative analytics/admin response is part of this release.
   `docs/economy.md` lists `race_payout_ad_double` as a new source and switch.
9. Document `ADS_RACE_PAYOUT_DOUBLE_PREPARE_ENABLED`,
   `ADS_RACE_PAYOUT_DOUBLE_CLAIM_ENABLED`, and
   `ADMOB_RACE_PAYOUT_DOUBLE_AD_UNIT_IDS` in backend `.env.example` and
   deployment configuration, using the two split switch names above rather
   than one ambiguous switch. Both start false; production's
   allowlist contains exactly the two dedicated unit IDs after console setup.
10. Follow backend module conventions: Prisma access in
    `src/modules/races/models/`; one-function command/query files with injected
    collaborators and `AppError` subclasses; thin `asyncHandler` routes using
    the standard error middleware; export from `src/modules/races/index.js` in
    dependency order. Put no business logic in the legacy route handler.
11. Add default-off app setting `racePayoutDoubleRolloutPercent` bounded to
    integer `0..100`. Persist cohort once on the durable provider identity as:
    SHA-256 UTF-8 bytes of
    `race_payout_double:v1:<providerSubHash>`, interpret the first 8 digest bytes
    as an unsigned big-endian integer, then modulo 100. Pin known vectors in
    tests. `GET /races` may use the existing rebuildable app-settings cache for
    advisory prospective visibility; `POST .../offer` directly re-reads and
    range-checks the Postgres app-setting row under transaction so the 30-second
    cache cannot bypass an automatic stop. Preparation requires persisted
    bucket < percent; pending recovery/claim ignores later decreases. Start at 10.
12. Add `buildRacePayoutDoubleReconcile` +
    `scheduleRacePayoutDoubleReconcile`, registered in `src/index.js` behind
    default-off `RACE_PAYOUT_DOUBLE_RECONCILE_ENABLED`. Run every five minutes;
    dedupe the UTC five-minute bucket through `JobRun.claimRun`. Over the
    trailing 24 database-clock hours require, per claimed offer and conversely:
    exactly one `race_payout_ad_double` transaction with `refId=offerId` and
    `amount=bonusCoins`; one consumed `race_payout_double` grant with
    `contextId=offerId`/matching `coinAmount`; one velocity grant; and one claim
    receipt with matching amount. A missing offer/grant/coin row is explained
    only when the matching velocity row and receipt both exist and the receipt
    has `accountDeletedAt` set; otherwise the orphan is a reconciliation
    failure. Require every surviving item source reason/ref to match §2.1 and
    aggregate sums across non-deleted offer/ledger/grant/velocity/receipt rows
    to be equal. Also report
    claims, bonus, distinct hashed identities, batches/identity/24h, cap hits,
    eligible reasons, and SSV→claim conversion. Add global time-scan indexes on
    offer status+claimedAt, grant kind+consumedAt, velocity claimedAt, receipt
    claimedAt, and rely
    on/add the reason+createdAt ledger index rather than user-leading indexes.
    If any equation/source check fails, or trailing-24h bonus exceeds 370 at
    initial rollout, emit structured error JSON event
    `race_payout_double_alert` to the production log/alert pipeline and
    idempotently write rollout percentage 0 through the canonical app-setting
    setter (including cache invalidation). This release adds no admin API.
13. Instrument rejected/duplicate SSV and preparation/claim failure codes as
    bounded structured JSON events through the backend's existing production
    logger/alert pipeline: event names `race_payout_double_ssv_metric` with fixed
    `outcome`, and `race_payout_double_endpoint_metric` with fixed
    `operation`/`code`. Never include transaction/ad IDs, provider hashes, user
    IDs, names, or health data. Emit through a synchronous-safe best-effort
    wrapper that catches logger/transport exceptions and never awaits delivery;
    observability failure must not alter an SSV status, economic endpoint
    response, or transaction. Tests inject a recorder and a throwing logger and
    assert every branch is counted when healthy and remains response-identical
    when logging fails. Durable success aggregates continue to come from
    Postgres reconciliation; no new metrics adapter or production config is
    required.

## 8. Frontend implementation plan

Write widget/integration tests first, observe the intended failures, then add
business/UI code.

1. Add per-platform no-fallback defines and getters to
   `lib/services/ad_service.dart`:
   `ADMOB_RACE_PAYOUT_DOUBLE_AD_UNIT_ID` and
   `ADMOB_RACE_PAYOUT_DOUBLE_AD_UNIT_ID_ANDROID`. A missing current-platform ID
   makes `racePayoutDoubleSupported` false and the offer disappears.
2. Refactor client-feature construction in
   `lib/services/backend_api_service.dart:84` so `race_payout_double` is added
   independently when its dedicated unit exists. Do not couple it to the
   existing extra-spin `ads` capability. The current load-bearing ternary
   duplicates the full token list: conditionally add the token in **both**
   branches and add a structural test guarding both branches.
3. Extend the rewarded-ad controller API (or add a narrowly typed sibling) so
   this surface can send `race_payout_double:<userId>:<offerId>` instead of the
   current date-shaped custom data. Preserve all existing controller call
   sites and wire formats.
4. Add a defensive `RacePayoutDoubleOffer.tryParse` model. It accepts only
   positive integer amounts and non-empty unique IDs whose set is a non-empty
   subset of the popup batch; every malformed/missing field results in no
   offer. Its optional `offerId` must be null or a canonical UUID.
5. Add `createRacePayoutDoubleOffer` and `claimRacePayoutDouble` to the single HTTP surface,
   `lib/services/backend_api_service.dart`, with defensive decoding and
   machine-code handling. Cache only a definite endpoint 404 as unsupported;
   never turn a timeout/5xx into permanent session disablement.
6. Convert `RaceResultsSummaryScreen` to own the injected ad controller and
   transient state, or extract a stateful reward panel while keeping the
   surrounding results screen stable. Inject fakes in widget tests; the screen
   must not import `google_mobile_ads` directly.
7. Pass the parsed offer, authenticated user ID/token, services, and a balance
   update path from `MainShell`. Preload lazily only when the offer is valid,
   the feature is supported, and the popup route is current. When recovering a
   non-null pending `offerId`, select/inject its races and construct the popup
   **before** applying the normal `myResultsSeen == false` filter; show only its
   race IDs even when those participants are already seen, and leave later
   unseen completions for the next popup/load.
   Add an explicit `_isOnboarding`/demo suppression guard before the shell can
   push the real results modal; onboarding must never be interrupted by an
   eligible production race payload.
8. On tap, prepare/recover the server offer before loading the ad. Use its
   immutable offer ID for SSV and every bounded claim retry. On relaunch, a
   returned pending offer is claimed first; `AD_NOT_VERIFIED` permits another
   ad attempt against that same offer regardless of participant seen state. Never load
   a second ad or create an overlapping offer concurrently.
9. On success, call `AuthService.updateCoins` with the returned integer balance
   and update the result presentation. Missing/malformed `coins` does not crash;
   refetch `/auth/me` before claiming success in the balance badge.
10. Keep results-seen acknowledgement, review-prompt sequencing, next-race
    routing, banner placement, confetti rules, and What's New suppression
    unchanged. Add durable user/backend-scoped pending-ack storage so explicit
    dismissal suppresses the shown IDs locally and retries the atomic server
    seen+forfeit call after transient failure.
    The versioned record is `{version, userId, backendBaseUrl, raceIds,
    racePayoutDoubleCapability, queuedAt}` in preferences, partitioned by
    `(userId, backendBaseUrl, racePayoutDoubleCapability)`.
    Persist whether the dismissal originally advertised the capability; old
    records decode it as false. Replay through a request-specific client-feature
    header override so a capable dismissal stays capable after restart/app
    update even if the running build lacks the define, while a tokenless record
    can never be upgraded by a later capable build. Merge/deduplicate IDs only
    inside the same capability partition; never upgrade/downgrade or coalesce
    false and true partitions. Persist before route pop, hydrate all matching
    user/backend partitions before the first result
    detection, suppress queued IDs during every race fetch, and retry on
    startup, resume, authenticated-user restore, and refresh. Clear a record
    only after a 2xx response. Send each partition independently with its own
    request-specific header, using sorted ID chunks of at most 50; clear only
    each acknowledged chunk in that partition and retain all others. Preserve unmatched user/backend records through
    sign-out and account/backend changes; only the matching authenticated
    context may send or clear them.
    Add `markRaceResultsSeenStrict`, which returns only after decoded 2xx and
    throws on network/non-2xx; keep the existing best-effort method as a wrapper
    for legacy callers so UI remains non-disruptive. If preference persistence
    fails, still permit dismissal, retain session-memory suppression, emit a
    diagnostic, and attempt the strict request immediately; document that a
    process death before its 2xx may re-show because durable local storage was
    unavailable.
11. Account for every construction site and mirrored surface found by the UI
    test planner, including widget tests and tutorial/demo fixtures that render
    the real popup or shell. The panel's exact placement is after every result
    card/podium/team card and before both existing action variants. Preserve the
    standalone `AdBannerSlot` below/outside `GameContainer`.

Design direction from `mobile-design`: extend the app's existing playful
arcade/parchment language rather than introducing a generic Material ad card.
Use one precise coin-count transition and restrained coin motion on success;
do not add custom pictorial art or a new asset pipeline for this feature.

## 9. AdMob console and build configuration

The feature needs a dedicated **Rewarded** unit per platform because AdMob unit
IDs are platform-specific and iOS/Android ship in lockstep:

| Platform | AdMob app | Unit | Dart define |
| --- | --- | --- | --- |
| iOS | Bara iOS (`ca-app-pub-4538901002392200~5288861983`) | `ca-app-pub-4538901002392200/6376353967` | `ADMOB_RACE_PAYOUT_DOUBLE_AD_UNIT_ID` |
| Android | Bara Android (verify app ID in console) | Pending | `ADMOB_RACE_PAYOUT_DOUBLE_AD_UNIT_ID_ANDROID` |

For each unit:

1. Create a Rewarded ad unit with reward amount `1` and reward item
   `race_payout_double`; the backend ignores those values and computes coins.
2. Configure server-side verification callback URL
   `https://steptracker-api.org/ads/ssv` and verify it. Confirm AdMob's bare
   verification ping receives HTTP 200 without minting a grant.
3. Record the generated unit ID in the secure release notes/process; unit IDs
   are not secrets, but do not guess or reuse an unrelated placement.
4. Register release/TestFlight devices as test devices and use Google's public
   rewarded test units only in debug/test. Never generate unmarked live test
   traffic.
5. Allow for AdMob fill propagation before production validation.

Repository documentation updates after IDs exist:

- Add the iOS define to every ad-enabled iOS build command in `README.md` and
  `DEPLOYMENT.md`, and explain that omission compiles the action out.
- Add the Android define to every ad-enabled prod Android command in both docs.
- Staging commands omit real SSV-backed units unless staging has its own AdMob
  units whose callback targets staging. This avoids a staging app watching a
  prod-verified ad and then claiming against the staging database.
- Add the define to the required-ad prose/checklists and the AdMob unit inventory.
- Update the short build-command examples in both `AGENTS.md` and `CLAUDE.md`
  together so their mirrored contract remains in sync.
- Do not sweep historical feature specs or obsolete planning files merely
  because they contain old commands; update current operator-facing commands.

The user created the iOS unit after the feature code was built; its ID is now
present in every active iOS command in `README.md`, `DEPLOYMENT.md`, `AGENTS.md`,
and `CLAUDE.md`. The Android commands retain an explicit
`<create in AdMob; omission disables race payout double>` placeholder until its
separate unit is supplied. Keep the backend allowlist empty and switches off
until both platform units exist so iOS and Android can roll out in lockstep.

## 10. Backward compatibility and rollout

1. Land backend integration tests, additive migration, endpoints, parser, and
   offer logic first. Keep prepare/claim switches false and rollout 0 in
   staging and production initially.
2. Deploy backend to staging only after confirming the test DB and migration.
   Production deployment always requires separate explicit approval.
3. Land the app with dedicated per-platform define support, placeholder release
   documentation, and the defensive offer parser. Build/verify iOS and Android
   without the new defines to prove safe compilation-out behavior.
4. The iOS unit is configured in documentation. After the user creates and
   supplies the Android unit, replace its active placeholders, configure the
   backend allowlist with both IDs, and build/verify iOS and Android from the
   same version with their platform-specific defines.
5. Test on staging only with staging-routed units or a controlled SSV test
   setup. Never point a staging claim flow at a prod-only callback.
6. Deploy compatible backend to production first, still dark.
7. Release iOS and Android builds. Missing define, old backend, malformed
   response, disabled switch, or absent fill all degrade to the old results
   popup; payout and acknowledgement still work.
8. Enable reconciliation first and observe at least one healthy scheduled run
   while rollout remains 0. During a staffed observation window, then set claim
   true, prepare true, and rollout to at most 10%. Expand only after
   cap/source/reconciliation metrics are healthy. On threshold breach set
   rollout to 0 and prepare false while
   leaving claim true for existing offers. Set claim false only for a confirmed
   active exploit where honoring prepared entitlements is riskier than denial.
9. Rollback is rollout 0 + prepare false first. Do not remove endpoints, columns, or
   response compatibility during rollback; app binaries are frozen.

Version-skew matrix:

| Client | Backend | Behavior |
| --- | --- | --- |
| Old | New | No feature token; receives old race response and old popup. |
| New | Old | No offer field/claim endpoint; renders old popup without error. |
| New, define missing | New | Does not send token; no offer. |
| New, define present | New, prepare off/cohort out | No new offer; owned pending offer may still settle. |
| New, define present | New, prepare+claim on/cohort in | Verified combined bounded flow. |

## 11. Tests-first plan

### 11.1 Backend integration tests

Create HTTP integration coverage through real routes and a dedicated test DB:

1. `GET /races` without capability is byte-compatible and omits all offer keys.
2. Capability + preparation policy returns the exact eligible ledger sum for
   one and multiple unseen completed races, including an ineligible/zero row in
   the popup but not the offer sum.
   A combined payout above 500 returns `baseCoins` unchanged and
   `bonusCoins/maxBonusCoins` of 500.
3. Seen, non-accepted, active, foreign, already-offered, and all-zero batches
   are ineligible.
4. SSV with valid signed `race_payout_double` custom data stamps the right kind
   and context; existing bare date, coins, unlock, and reroll formats retain
   parity.
5. Invalid SSV signature, duplicate transaction, unknown user, malformed
   prefix, and offer-ID collision mint no usable duplicate.
6. Claim before SSV returns `AD_NOT_VERIFIED` and changes no ledger, participant,
   grant, or balance row.
7. Preparing one or multiple races persists the exact authoritative snapshot;
   retries/concurrency return one offer, while overlapping/subset/superset
   attempts cannot create a second offer for any participant.
8. One verified ad with N races awards exactly `min(sum(eligible system-funded
   ledger credits), 500, rolling24hRemaining)`, writes one batch ledger credit, marks the offer
   claimed, consumes one grant, and returns the authoritative balance.
9. Client-supplied totals are impossible; duplicate/unknown/foreign/seen/
   not-completed IDs are rejected during preparation before any ad. A different
   race completing during ad playback does not invalidate the persisted offer.
10. Same offer retry returns immutable offer fields plus current balance without awarding twice; unique
   offer items prevent a selected race from entering any fresh offer.
11. A valid prefix arriving from any non-allowlisted rewarded unit cannot be
    consumed for a race payout; mismatched custom-data user IDs are rejected.
12. Two concurrent claims produce one combined award only.
13. Failure injected mid-transaction rolls back the grant, offer status,
    ledger, and balance together.
14. `POST /races/results/seen` always marks owned results seen, but forfeits
    touching pending offers only when that request advertises
    `race_payout_double`; a capable-forfeited offer cannot claim even if SSV
    arrives, while a tokenless acknowledgement preserves it.
15. Switch-off, empty allowlist, and missing-capability requests expose/award
    nothing.
16. More than 10 newer completions do not evict a pending offer's item races
    from a capable response; tokenless responses remain capped/unchanged.
17. Prepare/claim/seen concurrency uses the one lock order, conditional terminal
    transition, exact-preparation rollback recovery, and bounded
    `40P01`/serialization retry without double credit or deadlock leakage.
18. Cap configuration accepts `1..500`; zero, negative, malformed, and >500
    values safely fall back to 500. All integration paths pass with Redis unset.
19. Funded `race_prize_pool_payout` and seeded `race_finish_reward` credits are
    eligible; legacy `race_buy_in_payout`, every refund, tournament/referral,
    and unrelated reasons contribute zero even when `myPayoutCoins` displays a
    positive combined amount.
    Pin exact `<raceId>:<placement>` and `<raceId>:rank:<placement>` equality;
    mixed reasons, wrong placement, broad-prefix, and collision-like ref IDs
    contribute zero through real HTTP preparation.
20. Rolling allowance uses durable velocity grants in the exact
    `(databaseNow-24h, databaseNow]` window under the provider-identity lock:
    multiple batches cannot exceed
    500, boundary behavior is deterministic, zero remaining exposes no offer,
    and concurrent preparations cannot overspend allowance.
21. Stable cohort hashing and `0/10/100` rollout values gate preparation only.
    Prepare-off/rollout-down still permits claimed replay and pending claim;
    claim-off rejects pending settlement without consuming its grant.
22. Reconciliation detects offer/grant/ledger mismatches and unexpected
    buy-in-source inclusion, emits bounded aggregate metrics, and invokes the
    injected prepare-stop control idempotently.
23. A tokenless old/missing-define device can acknowledge a race with a pending
    offer without forfeiting it. A later capable device receives/injects and
    claims that offer despite results-seen, including SSV-pending state; a
    capable dismissal does forfeit it.
24. Delete/recreate through the public account/auth paths with the same Apple or
    Google subject retains provider hash, cohort bucket, and trailing velocity.
    Cover pending/claimed offers and two deleted participants in one completed
    race; account deletion and rollback remain unblocked by nullable SetNull
    item relations. The deletion path stamps the claim receipt before cascades;
    reconciliation accepts that explained missing settlement, but an otherwise
    identical velocity orphan without a deletion-stamped receipt stops rollout.
    A concurrent claim-versus-delete HTTP integration test proves the shared
    provider-identity → user lock order yields only two valid outcomes: no award,
    or a committed receipt tombstoned before cascade with healthy reconciliation.
25. Rollout bucket algorithm has fixed known vectors. Advisory GET may be cache
    stale, but preparation's direct Postgres recheck rejects immediately after
    rollout is set to zero.
26. The five-minute JobRun-deduped reconciliation equations, deletion-aware
    receipt rules, 48-hour receipt/velocity retention, 24h/370 alert, canonical
    rollout-zero action, external failure counters, and required global time
    indexes are covered with injected clock/logger/metrics/settings. Rollout
    cannot rise above zero until at least one healthy scheduled run is recorded.
27. Inject a throwing structured-event logger into valid, rejected, and
    duplicate SSV plus preparation/claim failure paths; HTTP status/body and
    every economic side effect remain identical to the healthy-logger cases.

Focused non-integration tests are allowed only for SSV regex parsing and pure
offer-set validation cases that cannot be expressed economically through HTTP.

### 11.2 Frontend widget/integration tests

Pump the real `RaceResultsSummaryScreen`/shell path with fake services:

1. One payout offers the exact bonus; multiple races show one summed offer.
2. Zero-only, missing, null, malformed, out-of-popup-ID, already-offered, old
   backend, and missing-unit states render the unchanged popup with no gap.
   A payout over 500 renders truthful maximum-bonus copy and never says it will
   fully double the payout.
   A displayed payout containing excluded buy-in coins says “qualifying race
   prizes” and renders only the server-provided eligible amount.
3. Ad loading disables only the ad action; NICE/next-race dismissal remains.
4. Tapping prepares exactly one server offer before ad load; earned callback
   claims its ID, while early close triggers no claim.
5. `AD_NOT_VERIFIED` retries 5x with the same offer ID and succeeds when SSV lands.
6. Successful and already-claimed responses update the balance and earned UI;
   the ad action cannot be invoked twice.
7. Timeout/5xx keeps balance unchanged and offers a safe retry; 404/disabled/
   stale removes a prospective offer without breaking acknowledgement.
   `CLAIMS_DISABLED` preserves a pending panel and retry state; only
   `PREPARATION_DISABLED` collapses a prospective panel.
8. Closing before, during a failed load, and after success still acknowledges
   the full shown batch exactly once and preserves next-race/review sequencing.
   A transient ack failure persists local suppression and retries without
   showing the dismissed popup again on that device.
9. App death after a prepared/earned attempt receives the same pending offer ID
   with its frozen batch; explicit capable dismissal forfeits it and no later
   popup or claim surface appears. A non-null pending offer whose races all have
   `myResultsSeen:true` still opens through the real `MainShell` path before the
   normal unseen filter. A race completed after preparation is excluded from
   the recovery popup and remains unseen for the next popup.
10. A failed results acknowledgement survives restart, refresh, sign-out, and
    account switching without re-showing for the matching user; only the
    matching user/backend retries it, and only 2xx clears it. Reinstall is not
    promised to preserve local suppression before the server receives the ack.
    Cover restart-before-hydration, merge/dedup, more than 50 queued IDs,
    per-chunk clearing, strict non-2xx/network behavior, and preference-write
    failure with session suppression/immediate request. Also cover capable
    dismissal → restart/app update into a missing-define build → replay: the
    stored request-specific capability still forfeits; legacy records default
    false and are never upgraded by the current build. Queue a legacy/false
    batch, then a capable/true dismissal before either succeeds; verify separate
    partitions, headers, retry/chunk clearing, and server outcomes for both.
11. `baseCoins=120`, `rolling24hRemainingBeforeClaim=50`, `bonusCoins=50`
    renders `+50` in plaque, button, early-close/retry, success, and semantics,
    and never promises a full double or `MAX +500`. An actual 500 partial bonus
    may use `MAX +500`; malformed inequalities or `maxBonusCoins>500` hide the
    panel.
12. Narrow/large screens, text scale, dark mode, and multiple long race names do
   not overflow; the footer banner remains at screen bottom.
13. Existing podium, team result, confetti, banner, and results-summary tests
    remain protected and green.

### 11.3 Verification

- `flutter pub get`
- `flutter analyze` (clean)
- Relevant widget suites first, then `flutter test`
- Backend: confirm `DATABASE_URL` identifies a local/disposable test DB; run
  the new integration suite, then `npm run test:integration` and
  `npm run test:unit` (never bare `npm test`)
- Build iOS `flutter build ipa` with the iOS define and Android
  `flutter build appbundle --flavor prod` with the Android define, aligned
  backend URL/version/build number
- Manual SSV verification on registered test devices for both platforms

## 12. Resolved product decisions

1. **Eligible coins:** one extra copy of the positive funded/seeded
   system-funded ledger portion of the shown race payouts. Legacy buy-in-pot
   transfers, refunds, and every non-race source are excluded even if included
   in displayed `myPayoutCoins`.
2. **Maximum:** 500 bonus coins per combined results batch **and** across a
   rolling 24 hours per durable provider identity. The UI always renders the
   actual bonus; “double” requires `bonusCoins == baseCoins`, and “MAX +500”
   requires an actual 500 bonus.
3. **Decline/recovery:** explicit dismissal from a capable client permanently
   forfeits the offer. There is no later claim surface. A server-owned pending
   offer recovers the prepared/started attempt on a capable client even if a
   tokenless client has since marked its exact results seen.
4. **Platforms:** ship code/configuration for both iOS and Android and create
   one dedicated rewarded unit for each.
5. **AdMob ownership:** the user creates both console units. The iOS unit is
   recorded; the Android unit remains required before release configuration is
   finalized.

### 12.1 Economy-review safeguards approved

The required game-economy review returned **UNSOUND** against the original
choices. On 2026-08-12 the user approved both required controls:

1. **Exclude legacy buy-in-pot payouts — approved.** Those
   coins are transfers of participant principal, not system-funded race prizes.
   Three colluding 200-coin entrants can direct a 600 pot to one account,
   recycle the principal, and use the ad to mint another 500 each race. Eligible
   sources would therefore be funded prize pools and seeded finish rewards;
   `race_buy_in_payout` and refunds would be excluded even though they contribute
   to the display-only `myPayoutCoins` total. The server-owned offer must derive
   eligible source amounts from the coin ledger, not infer them from the combined
   participant payout field.
2. **Add a 500-coin rolling-24-hour per-user cap — approved.** The batch cap blocks one windfall but not repeatedly opening after
   each race or successive completed pages. Production history observed as much
   as 835 eligible bonus coins in a user-day; theoretically seven capped batches
   could yield 3,500. The rolling cap changes the measured historical upper
   issuance by only about 2.3% while closing the timing/page-splitting strategy.

Preparation returns the bounded remaining allowance and
`bonusCoins = min(eligibleBatchCoins, 500, rolling24hRemaining)`. A zero
allowance exposes no offer. The transaction re-sums claimed
`race_payout_ad_double` velocity rows in `(databaseNow-24h, databaseNow]` under the same provider-identity lock
before freezing the offer, and claim uses the frozen amount.

The economy review also requires:

- deterministic percentage/cohort rollout beginning at 10% or less, controlled
  by a default-off backend app setting; process kill switch remains the global
  emergency stop;
- separate preparation and claim switches: normal shutdown stops new offers
  immediately but honors already-prepared verified offers, while a claim-stop
  switch is reserved for a confirmed exploit;
- aggregate monitoring/alerts for claims, bonus coins, distinct claimants,
  batches/user/24h, cap hits, payout source, SSV conversion, failure codes, and
  offer/grant/ledger reconciliation; begin with an alert around 370 bonus
  coins/day and automatically stop new offers on reconciliation failure or any
  unexpected legacy-buy-in eligibility.

## 13. Acceptance criteria / definition of done

- One completed ad can add the server-calculated combined eligible payouts in
  the current results popup, excluding transfer/refund sources and capped at
  500 per batch and rolling 24 hours per durable provider identity.
- Multiple races produce one sum, one ad, one atomic claim, and no duplicate
  payout under retry/concurrency/replay.
- The client never supplies or controls the payout amount; AdMob SSV is the
  only entitlement source.
- Old clients, old backends, missing fields, missing ad defines, disabled
  switches, no fill, and transient failures all preserve the existing results
  popup and already-settled coins.
- Both platform units/configurations and current operator build commands are
  documented; `AGENTS.md` and `CLAUDE.md` remain synchronized.
- Backend integration tests were written first and pass only against a test DB;
  frontend tests pump the real surface and pass; existing assertions are not
  weakened.
- `flutter analyze`, full relevant tests, iOS build, and Android build are
  green, or any skipped/red verification is reported plainly.
- Architect, game-analyst, UI-test-planner, and post-implementation code-reviewer
  requirements are satisfied. The UI planner's verbatim checklist is included
  in this document before approval.
- Backend deploy precedes app release; production actions receive explicit
  in-the-moment approval; release switch begins off and can disable the feature
  without an app update.

## 14. Manual UI-placement test plan

**Manual UI-Placement Test Plan — Race-payout double rewarded ad**

*Elements under test:* A compact combined-payout reward plaque is added below all race result cards and above the existing result actions.

*Elements under test:* One full-width rewarded-ad `PillButton` is added with the plaque; it must not appear inside an individual, podium, or team result card.

*Elements under test:* Loading, unavailable, early-close, verifying, retry, and earned states replace content in that same reward-panel position without moving or hiding the normal dismissal actions.

*Elements under test:* After success, the offer is replaced in place by one earned-payout summary; the rewarded action is removed rather than duplicated or moved elsewhere.

*Checklist*

1. **Real Home results popup — no-offer baseline**
   - **Get there:** On staging, use an account with one unseen completed accepted race, but disable the race-payout-double switch or install a build without the current platform’s dedicated ad-unit define. Launch or resume the app to Home.
   - **Verify:** The popup is unchanged: heading → result card → existing `NICE`, with no reward plaque, rewarded button, placeholder, or reserved gap where the offer would be. The popup’s footer banner remains fixed at the screen bottom and is not duplicated inside the parchment card.

2. **Real Home results popup — single, multiple, and capped offers**
   - **Get there:** In turn, launch/resume Home with staging fixtures for: one unseen payout race; several unseen races including a zero-payout race; and a combined payout above 500. Reset results to unseen between fixtures.
   - **Verify:** Each fixture shows exactly one combined reward panel after the final result card and before the existing action area. The single-race offer is not inserted inside that race card. The multi-race popup has one panel after all cards, not one per race, including no extra panel beside the zero-payout card. The capped fixture occupies the same position and does not add an uncapped/double offer elsewhere.

3. **Real Home results popup — existing CTA variants**
   - **Get there:** Open an eligible offer first with a resolved next-race recommendation, then without one.
   - **Verify:** With a next race, the order is result cards → reward panel/action → `START YOUR NEXT RACE` → secondary `NICE`. Without one, the order is result cards → reward panel/action → primary `NICE`, with no secondary duplicate. Both normal actions remain visible/reachable; neither appears above or inside the reward panel.

4. **Real Home results popup — individual podium and team cards**
   - **Get there:** Open eligible unseen results fixtures for: an individual result with a podium; a team victory; a team defeat; and a team tie. Include a mixed multi-race batch if available.
   - **Verify:** Podium and team outcome content stays wholly inside its result card. One combined reward panel follows the complete card or complete mixed card list. It is not inserted between the race name, podium, winner/team rows, or payout row, and no old/duplicate panel appears inside any variant.

5. **Real Home results popup — loading and failure states**
   - **Get there:** With a fake/staging rewarded controller, hold ad preparation/loading, then separately force ad-unavailable, early-close, transient claim failure, and stale/disabled rejection states.
   - **Verify:** Loading/progress and each inline failure/retry state occupy the reward-panel slot below the cards. Only the rewarded action changes or disables; `START YOUR NEXT RACE`/`NICE` remain below it and tappable. Messages do not overlay a result card or footer banner. When a stale/disabled offer is removed, the panel collapses completely with no gap and does not reappear elsewhere.

6. **Real Home results popup — verifying and success**
   - **Get there:** On a registered iOS or Android test device, complete the test rewarded ad; delay SSV long enough to see verification, then allow success. Also exercise an already-claimed/lost-response response through the staging fixture.
   - **Verify:** `VERIFYING…` stays in the same panel position and does not cover the existing actions. Success replaces that panel with one earned-payout summary below all cards; the rewarded button is absent and is not duplicated elsewhere. The normal dismissal/next-race actions remain below the earned summary, and the footer banner remains at the screen bottom.

7. **Real Home results popup — pending-offer relaunch**
   - **Get there:** Prepare an offer, terminate the app before claim completes, add a later completed race in the staging fixture, then relaunch to Home.
   - **Verify:** The recovered popup contains only the frozen offer’s race cards followed by its one reward/recovery panel. The later race and any second reward panel are absent from this popup; on the later popup, that race appears in the normal card position with at most its own one combined panel.

8. **Responsive popup and footer placement**
   - **Get there:** Repeat an eligible multiple-race/podium or team fixture on the smallest supported phone and a large phone/tablet. Rotate to landscape, set system text to the largest supported scale, test light and dark appearance from Profile → Settings, and enable Reduce Motion.
   - **Verify:** The full sequence remains reachable by vertical scrolling: heading → every complete result card → one reward panel → normal actions. Nothing overlaps, clips behind, or scrolls underneath the fixed footer banner; the banner stays outside the parchment card at the screen bottom. The full-width rewarded action retains a usable tap area, and no duplicate panel appears after rotation or text-scale relayout.

9. **Onboarding shell**
   - **Get there:** Sign in with a fresh account that still owes onboarding; progress through permissions, the tutorial/demo step, and first-race onboarding. Also use a staging fixture that would otherwise return an unseen completed result.
   - **Verify:** No race-results popup or payout reward panel appears over any onboarding, demo-race, or first-race step. After onboarding finishes and Home becomes active, any legitimate unseen result appears only in the normal real Home results popup position.

10. **Onboarding demo race**
    - **Get there:** Fresh account → onboarding → `START DEMO RACE`; finish the scripted race through its coach win card.
    - **Verify:** The demo’s existing coach/win chrome remains unchanged. No production results popup, combined-payout plaque, rewarded button, or footer-banner copy is added to the demo win card.

11. **Tab tutorial previews**
    - **Get there:** Profile → Settings → Help & Legal → `VIEW TUTORIAL`; advance through Home, Races, race-detail, Friends, Boards, and Profile beats.
    - **Verify:** No results popup or payout-double panel appears on any tutorial preview. The Races preview’s seeded completed card remains in its existing tab location only; it does not generate a modal. The hand-copied tutorial tab bar and all spotlight targets remain where they were.

*Surfaces confirmed unaffected:* `DemoRaceHost` reuses `RaceDetailScreen` and renders separate `_WinCard`/coach chrome; it never constructs `MainShell` or `RaceResultsSummaryScreen`.

*Surfaces confirmed unaffected:* `TutorialRealHost` constructs the five tab widgets and `RaceDetailScreen` directly, with a hand-copied `WoodenTabBar`; it never constructs the results popup or shell.

*Surfaces confirmed unaffected:* `tutorialPreviewRacesData()` includes a completed Races-tab card but omits the accepted/unseen results fields and payout offer needed to open the production popup.

*Surfaces confirmed unaffected:* `RankedResultsSummaryScreen` is a separate sibling popup and is not constructed by the race-results flow.

*Surfaces confirmed unaffected:* `RacesTab` completed-race cards are a list surface, not another construction of `RaceResultsSummaryScreen`; the new offer belongs only to the Home popup.

*Surfaces confirmed unaffected:* `main.dart`, `start_screen.dart`, and `display_name_screen.dart` all enter the same shared `MainShell`; there is no hand-forked production shell requiring a second visual implementation.

*Risks found while planning:* `_maybeShowRaceResults` currently has no `_isOnboarding` guard. Add an explicit implementation step to suppress the popup during onboarding and re-evaluate results after onboarding exits.

*Risks found while planning:* `RaceResultsSummaryScreen` is currently stateless and directly instantiated by five widget-test groups. Add an implementation step to provide safe optional defaults or update every constructor, while injecting fake ad/services for state tests.

*Risks found while planning:* The popup owns its own `AdBannerSlot` outside the parchment card. Add an implementation step to keep the reward panel inside the scrollable card and preserve exactly one fixed screen-bottom banner with enough bottom clearance.

*Risks found while planning:* Podium, team, long-name, and multi-race cards can make the popup substantially taller. Add an implementation step to place one combined panel after the generated card loop and keep the whole card/panel/action sequence scrollable at narrow, landscape, and large-text sizes.

*Risks found while planning:* Pending-offer recovery changes which unseen races belong in the shown popup. Add an implementation step to filter the displayed and acknowledged IDs to the frozen offer set so later races neither appear nor lose their separate future placement.

*Risks found while planning:* Demo and tutorial fixtures must remain offline and must not gain a valid `payoutDoubleOffer`. Add an explicit fixture step preserving their current omission and a regression check that no ad controller or network flow starts there.

*Risks found while planning:* Loading, error, verifying, and success states can accidentally append instead of replace. Add stable reward-panel keys and an implementation step ensuring exactly one mutually exclusive state occupies the slot.

*Risks found while planning:* Existing direct tests protect podium, team results, next-race/NICE ordering, and footer-banner placement. Update those fixtures without weakening their assertions, and add the new reward panel between the final result card and both existing action variants.

## 15. Revision log

- **Initial draft (2026-08-12):** traced the existing Home batch popup,
  results-seen acknowledgement, `myPayoutCoins` persistence/serialization,
  rewarded-ad controller, SSV grant ledger, and current build documentation.
- **Gap pass 1 (2026-08-12):** closed a cross-placement reward escalation:
  claim now requires the signed SSV `ad_unit` to match a backend allowlist of
  the two dedicated units, and the custom-data user must match `user_id`.
  Clarified that an offer may be a subset of the popup after a lost-response
  recovery (previously doubled races still render but cannot block new ones),
  and removed an unnecessary per-race response flag.
- **Gap pass 2 (2026-08-12):** identified the time-of-check race in which a
  newly completed race could change the global eligible set while an ad was
  playing. This led to the later server-owned frozen-offer design. Added a
  composite attempt uniqueness fence, moved the dedicated-unit check to SSV
  grant creation as well as claim defense, corrected the parser's subset rule,
  and clarified success copy so “total” cannot be mistaken for wallet balance.
- **Product interview (2026-08-12):** confirmed `myPayoutCoins` as the only
  eligible source, a 500-coin per-batch bonus cap, permanent forfeiture on
  explicit dismiss, iOS+Android dedicated units, and user-owned AdMob creation
  after the code is built. Added truthful capped copy, in-progress offer
  recovery, runtime cap configuration, and placeholder-to-real-ID release
  steps.
- **Post-interview gap pass 1 (2026-08-12):** closed a 500-cap bypass where a
  modified client could split one popup into several race subsets. Added a
  server-owned offer + immutable item snapshot prepared before ad playback,
  unique participant membership, one bounded batch ledger row, and offer-ID
  SSV binding.
- **Post-interview gap pass 2 (2026-08-12):** made dismissal permanent through
  atomic seen+forfeit behavior, removed fragile local nonce recovery, corrected
  capped award tests, and ensured a race completing after offer preparation is
  held for the next popup rather than being accidentally dismissed with the
  recovery batch.
- **Architect review (2026-08-12, REVISE):** required one pending offer per
  user with a partial unique index and user lock; unambiguous HTTP 200 claimed
  replay; a global Postgres lock order and conditional transitions; use of the
  canonical `awardCoins` seam; pending recovery beyond the normal completed-10
  page; canonical/fail-closed reserved SSV parsing; a hard configuration ceiling
  of 500; complete foreign keys/status constraint; Postgres-only authority;
  versioned durable dismissal acknowledgements; both client-feature ternary
  branches; standard backend module conventions; and insertion of the verbatim
  UI plan. All are incorporated; substantial economy-driven revisions will be
  returned for re-review after the open decisions resolve.
- **Game-economy review (2026-08-12, UNSOUND):** production analysis estimated
  a 100%-claim upper proxy of 1,177 bonus coins/day, +31.8% gross sources and
  +100.5% net issuance. Required exclusion of recyclable legacy buy-in
  transfers, a 500 rolling-24-hour user cap, ≤10% cohort rollout, split
  prepare/claim shutdowns, and reconciliation/velocity monitoring. Because the
  first two alter explicit product choices, §12.1 reopens them for user decision.
  The reviewer updated `docs/economy.md` only.
- **UI-placement review (2026-08-12):** mapped one production construction site,
  five direct widget-test groups, no demo/tutorial modal mirror, and the fixed
  footer banner. Required onboarding suppression, safe stateful constructor
  defaults/injection, one mutually exclusive keyed panel after all cards and
  before actions, pending-offer filtering, responsive scrolling, and fixture
  non-network guarantees. Folded into §8 and included verbatim in §14.
- **Economy decision (2026-08-12):** user approved exclusion of legacy buy-in
  transfers and a shared 500 rolling-24-hour user cap. Added ledger-source
  eligibility, truthful qualifying-prize copy, frozen allowance snapshots,
  deterministic ≤10% cohort rollout, split prepare/claim brakes, and bounded
  reconciliation/monitoring.
- **Post-economy gap pass 1 (2026-08-12):** removed remaining assumptions that
  `myPayoutCoins` equals the eligible amount; the offer/item snapshot and tests
  now use only funded/seeded ledger reasons, with buy-ins remaining display-only.
  Added rolling-cap transaction/concurrency/boundary tests.
- **Post-economy gap pass 2 (2026-08-12):** separated preparation-disabled from
  claims-disabled errors so a normal rollout stop cannot strand/erase prepared
  entitlements, confirmed claimed replay remains available after shutdown, and
  made rollout cohort membership server-stable and preparation-only.
- **Architect re-review (2026-08-12, REVISE):** found cross-device old-client
  acknowledgement of invisible pending offers, pending-recovery gate ordering,
  ambiguous ledger attribution, rolling-cap copy/parser bounds, unversioned
  rollout hashing/cache authority, underspecified reconciliation, account-delete
  FK hazards, and a non-observable best-effort ack transport. Added
  capability-aware forfeiture/recovery despite results-seen, exact reason/ref
  matching, `bonus<base` copy, fixed provider-hash bucket algorithm with direct
  Postgres preparation check, executable JobRun reconciliation/external failure
  metrics, SetNull snapshot relations, and strict queued/chunked acknowledgement.
- **Economy re-review (2026-08-12, SOUND WITH CHANGES):** verified buy-in farming
  and same-account batch/concurrency splitting are closed. Required allowance
  and cohort durability across delete/recreate plus a concrete failure-metrics
  source. Added permanent hashed provider identity/velocity tables, database
  clock boundary, delete/recreate coverage, and injected bounded external
  counters. `docs/economy.md` was updated to the revised measured model.
- **Economy closure pass (2026-08-12):** added a durable, provider-hashed claim
  receipt whose deletion tombstone distinguishes legitimate account-deletion
  cascades from missing settlement rows. Reconciliation now checks receipts in
  both directions, velocity/receipts have a 48-hour minimum retention, the
  rolling cap locks the durable provider identity, and rollout must remain zero
  until a healthy scheduled reconciliation run is observed.
- **Economy concurrency closure (2026-08-12):** account deletion now acquires
  the provider-identity and user locks in the global order before reading or
  tombstoning receipts. Added a public-path claim-versus-delete integration
  test requiring either no settlement or a tombstoned committed receipt with
  healthy reconciliation.
- **Architect closure pass (2026-08-12):** made pending-offer injection precede
  the shell's seen filter; persisted the original dismissal capability for
  request-specific acknowledgement replay; required actual-value copy in every
  UI/accessibility state; and replaced an abstract metrics sink with isolated,
  best-effort structured events through the existing logger/alert pipeline.
- **Acknowledgement partition closure (2026-08-12):** partitioned durable seen
  acknowledgements by user, backend, and original payout-double capability so
  legacy/tokenless and capable dismissals can coexist without upgrading or
  downgrading one another; merge, chunk, send, and clear are partition-local.
- **Final reviews (2026-08-12):** architect returned **APPROVE** with no required
  changes or suggestions; game-economy reviewer returned **SOUND** and confirmed
  `docs/economy.md` is aligned.
- **Implementation and code review (2026-08-12):** backend and Flutter work was
  completed tests-first against the locked contract. Combined review initially
  required queue/auth concurrency, strict AdMob configuration, reconciliation,
  deletion-race, copy, and accessibility hardening; all findings received
  regression coverage and the final reviewer returned **APPROVE — SHIP** with
  no remaining blockers, issues, or nits. Production remains dark pending the
  remaining Android rewarded unit ID and manual SSV/device validation.
