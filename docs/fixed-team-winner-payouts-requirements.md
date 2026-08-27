# Fixed team-winner payouts

## Summary and user story

Replace funded team races' divisible walker-funded pool with an immutable,
duration-based reward for each eligible winner. A team-race win should buy a
meaningful amount in the 200-coin powerup shop: 100 coins for the shortest
race, 200 for a three-day race, 500 for a seven-day race, and 1,000 for a long
race. The total liability scales with the number of eligible winners; it is not
redistributed when a teammate forfeits.

> As a team-race participant, I want a week-long win to pay enough for multiple
> useful shop purchases, so that the commitment and all-or-nothing result feel
> worthwhile.

The motivating production race, `boyz vs gorls`, is a seven-day 5v5. Under this
design its projected pool is 2,500 and each of five eligible winners receives
500, replacing the current V2 projection of 600 total / 120 each.

## Scope and non-goals

In scope:

- app-funded, user-created team races;
- projection and settlement parity on every existing race response;
- wins, ties, forfeits, payout rounding, immutable completed history, and
  recovery/idempotency;
- immutable creation-time economy stamping;
- an explicitly authorized, upward-only repair of open affected races;
- economy safeguards required for the aggressive reward curve.

Out of scope:

- individual races, seeded challenges, legacy buy-in races, and tournament
  matchups;
- changing the 200-coin shop price or any powerup price;
- changing team scoring, team assignment, or winner selection;
- recalculating completed races or issuing retroactive ledger credits;
- a release flag, kill switch, rollout percentage, or runtime payout toggle;
- new Flutter UI or a new API endpoint. Existing prize-pool and payout-tier UI
  consumes the backend-owned amounts.

## Product rules

### Winner rewards

The proposed aggressive curve is:

| Priced duration | Per eligible winner | Full 1v1 pool | Full 5v5 pool |
|---|---:|---:|---:|
| 1 day | 100 | 100 | 500 |
| 2–3 days | 200 | 200 | 1,000 |
| 4–7 days | 500 | 500 | 2,500 |
| 8+ days | 1,000 | 1,000 | 5,000 |

The row is selected from the same canonical race duration used at creation and
start; custom-window repricing must update the duration and payout stamp in the
same write. The listed band boundaries are approved.

For a decisive result:

```text
eligible winners = accepted members of winnerTeam with forfeitedAt == null
award per winner = race.teamWinnerRewardCoins
settled pool      = eligible winners * award per winner
```

Every eligible winner receives the full stamped reward. No remainder exists.
A forfeiter receives zero and their missing share is not redistributed. Losers
receive zero. Team size therefore never changes the per-person incentive, and
1v1 cannot extract a larger individual award than 5v5.

“Eligible” retains the existing recipient rule: accepted + winning team + not
forfeited. There is deliberately no personal-step minimum; a non-forfeited
winning teammate may earn the reward even if their own persisted steps are
zero. The user rejected the proposed 2,000-raw-step gate.

### Ties

Every non-forfeited member of both teams receives half the
stamped winner reward. With balanced teams this preserves the same total
liability and makes equal-skill EV explicit. Payout-rounding V1 rounds any
positive fractional/non-five award through the existing shared planner. The
same accepted + not-forfeited eligibility applies, with no personal-step
minimum; an absent/forfeited member's tie share is not redistributed.

### Formation and projection

Pending and active projections use the larger non-forfeited team count as the
possible winning cohort, matching the existing liability-safe convention:

```text
projected pool = max(eligible TEAM_A count, eligible TEAM_B count)
                 * teamWinnerRewardCoins
```

`payoutTiers` contains one placement-1 row per projected recipient, each with
the fixed reward. A completed response uses persisted participant
`payoutCoins`; `prizePoolCoins` is the sum actually awarded.

## API contract

No request key or endpoint changes. Existing payout objects retain their shapes,
and every relevant race payload additively returns two authoritative markers:

```json
{ "teamPayoutVersion": 1, "teamWinnerRewardCoins": 500 }
```

Both keys are always `integer|null`. They are non-null only for a valid funded
team V1 stamp; legacy, non-team, malformed, and partial stamps normalize both
to `null` and retain legacy payout behavior. Frozen clients ignore the additive
keys. Relevant endpoints continue returning their established payout shapes:

- `POST /races` and existing team join/start/edit commands;
- `GET /races/:raceId`;
- `GET /races/:raceId/progress`;
- `GET /races`, public/featured/shared-preview routes, and Home race cards.

For a full active seven-day 5v5, the established fields normalize to:

```json
{
  "prizePool": {
    "funded": true,
    "coins": 2500,
    "projected": true,
    "playerCount": 10
  },
  "projectedPotCoins": 2500,
  "payouts": { "first": 500, "second": 500, "third": 500 },
  "payoutTiers": [
    { "placement": 1, "amount": 500 },
    { "placement": 2, "amount": 500 },
    { "placement": 3, "amount": 500 },
    { "placement": 4, "amount": 500 },
    { "placement": 5, "amount": 500 }
  ]
}
```

The tier `placement` values remain ordinal list positions for compatibility,
even though every member of the winning team ultimately has race placement 1.
This preserves the current Flutter parsing contract.

Every existing `prizePool` key remains present. For fixed-team rows, `coins` is
fixed-award liability/actual awards and `playerCount` remains the accepted or
settled walker count for compatibility. `durationDays`, `durationPoints`,
`coinUnit`, `maxCoins`, and `atMax` remain compatibility/accounting metadata;
they no longer derive `coins`. Stamps and settlement inputs come from Postgres;
settlement never reads Redis.

Older app versions already display server-provided `prizePool`, `payouts`,
`payoutTiers`, and `myPayoutCoins`; they ignore the additive markers and safely
show the new amounts. Newer apps require the authoritative marker pair before
showing fixed-winner explanatory copy and fall back safely when an older backend
omits them. The app never calculates the reward.

## Data model and migration

Add nullable, immutable fields to `races`:

```prisma
teamPayoutVersion      Int? @map("team_payout_version")
teamWinnerRewardCoins Int? @map("team_winner_reward_coins")
```

- `NULL` version/reward means legacy pool-splitting behavior exactly as today.
- New funded team races stamp `teamPayoutVersion = 1` and the duration-selected
  reward at creation.
- Non-team, non-funded, seeded, and tournament races stamp `NULL`.
- Editing a pending race's duration re-stamps the reward atomically with the
  duration. Starting a custom-window race re-prices both in the same start
  transaction if the canonical duration changes.
- Projection and settlement read only the row stamp; they never read a live
  env value or infer a new reward for an in-flight race.
- Keep the existing prize calculation, unit, maximum, multiplier, and rounding
  stamps for compatibility/accounting. Team payout V1 takes precedence only
  when both new fields validate as positive integers; malformed or partial
  stamps fall back to the legacy formula rather than paying zero.

Mixed workers require two code deployments. Deployment A adds the columns and
teaches every projection, settlement, and cache path to read them, while all
writers continue writing `NULL`. After both PM2 workers are verified on A,
Deployment B begins permanently stamping new/edited races. No runtime flag is
used. Open-race repair is considered only after both workers run B.

## Backend implementation plan

1. Write HTTP integration tests first against a dedicated test Postgres. Do not
   run any integration test against production.
2. Add the migration and Prisma fields.
3. Add a pure duration-to-team-reward resolver and stamp it from
   `createRace.js`, `editRace.js`, and the canonical custom-window/start path.
4. Extend `teamPayoutPlan.js` with fixed-award win and tie planning while
   retaining the legacy divisible-pool path for unstamped rows.
5. Route `racePrizePool.js` projection and `completeRace.js` settlement through
   the same stamped planner, bypassing `computeSettledRacePool` for valid fixed
   stamps. Persist actual awarded totals in
   `prizePoolCoins`, `potCoins`, participant `payoutCoins`, rounding metadata,
   and the existing idempotent coin ledger.
6. Thread the two stamps through every full/lean race select and Redis race-list
   snapshot so list, detail, progress, public, featured, preview, and Home agree.
7. Restore the permanent five-membership ceiling inside the existing Postgres
   funded-exposure user-guard transaction. It replaces the retired coin/rate
   thresholds rather than creating a parallel admission system.
8. Update `docs/economy.md` with the shipped curve, EV, sources, exploit model,
   and monitoring queries.

## Frontend plan

Flutter continues to read, never recompute, backend amounts through
`RacePayoutPresentation` and the existing results models. The shared payout
sheet adds one compact established-style fact row such as `500 PER ELIGIBLE
WINNER`, sourced from the server payout tier. Replace team copy that only says
the pool is split, including `race_detail_screen.dart`'s legacy compatibility
copy. If tiers are missing, malformed, or inconsistent, retain today's generic
team copy and never derive a reward locally. Results keep using persisted
`myPayoutCoins`.

Use the existing race-detail typography, plaque/card chrome, spacing, and
dark-mode tokens—this is a refinement, not a new visual language. Verify both
platforms, narrow devices, and text scaling. Real-screen widget tests cover the
new value and old-backend fallback. The UI-placement checklist is appended
before approval.

## Economy and abuse safeguards

The aggressive curve gives one equal-skill entrant EV/day of 50, 33.3, 35.7,
and 35.7 coins for the four bands—roughly 3.2–4.8 times current median recurring
income from one race. Production is already strongly inflationary, and the same
walking can currently score in unlimited funded races.

The game-economy review marked this curve `UNSOUND` under unlimited funded
memberships. Product rejected unlimited participation, so restore an atomic
maximum of five simultaneous user-created funded competitions per account,
counting funded races and funded tournaments together under the existing
funded-exposure lock. Count accepted, non-forfeited/unfinished memberships in
`PENDING|ACTIVE` user-created funded races plus accepted, non-eliminated
memberships in `PENDING|ACTIVE` user-created funded tournaments. A tournament
counts once, never once per matchup. Creation counts the creator; invitations
and join requests count only on acceptance. Leave, forfeit, kick, cancellation,
completion, and tournament elimination release a slot. Seeded auto-enrollment,
tournament matchups, and non-funded competitions are excluded. Accounts already
above five are grandfathered but cannot add until below five, and every counted
state retains a frozen-client-compatible exit. This is permanent behavior, not
a rollout control. A sixth admission returns HTTP 409 with the existing code:

```json
{ "error": "Finish or leave another funded competition before joining this one.",
  "code": "FUNDED_EXPOSURE_LIMIT" }
```

There is deliberately no minimum-step recipient gate. The five-membership cap
limits, but does not eliminate, duplicated-step earning and passive teammates.

The final economy review remains `UNSOUND`: two colluding accounts can fill five
one-day 1v1 slots and mint 250 coins/account/day from zero-step ties, or 500/day
for a token-step designated winner. The one-day equal-skill EV is 50/day versus
35.7/day at seven/fourteen days.

1. zero-total-activity races are no-contests with zero payout, plus a durable
   rolling funded-entry/payout velocity limit;
2. lower/time-normalize the one-day reward plus a competition-level activity
   threshold; or
3. explicitly override `UNSOUND` and accept zero/token-step farming.

**Approved product decision:** option 3. Product explicitly accepts the
quantified zero-step tie, token-step win, one-day duration-arbitrage, repeated
cohort, and account/Sybil farming risks in exchange for keeping the
100/200/500/1,000 reward ladder with no activity qualification. This approval
does not authorize weakening the five-competition cap, omitting monitoring, or
deploying/repairing production without fresh authorization.

Fixed recipient awards do eliminate forfeiture concentration: forfeited winners
neither receive nor donate a share. Required daily/7-day monitoring covers
fixed-team coins/day (warn >2,000 for two days; page >4,000), share of issuance
and sinks, membership p50/p90/p99 and cap churn, paid zero-step recipients,
ties/one-day share, forfeits, repeated cohorts, hashed provider concentration,
and identities earning over 1,000 team coins per seven days.

## Open-race repair and rollout

Backend deploys before the app update, although frozen clients remain compatible.
Each code deployment and every production repair stage requires fresh explicit
authorization.

Proposed repair scope after both PM2 workers run Deployment B:

- select all `PENDING`/`ACTIVE`, funded, user-created team races with no team
  payout stamp;
- stamp the approved reward from each race's already-frozen canonical duration;
- never touch completed/cancelled, buy-in, seeded, or tournament rows;
- produce a before/after read-only report and exact row count before writing;
- enqueue one deterministic command per race through the leased admin-command
  runner. Under the race write fence, re-read lifecycle/stamps, skip
  completed/cancelled/downward/partial rows, compute both-side liabilities, and
  CAS-write both fields;
- invalidate race-progress and every participant's race-list cache after commit,
  then verify projections. Do not bulk-rewrite participant exposure rows.

The dry-run report, enqueue, and execution each require separate authorization.

The read-only report must separately identify a race whose repaired projection
would decrease. The repair is upward-only: such a row is skipped and surfaced
for a product decision. It must also calculate the exact maximum liability
under both possible winning sides before any write.

For `boyz vs gorls`, the proposed repair changes the active projection from
600 total / 120 each to 2,500 total / 500 each. This upward-only correction is
an explicit exception to immutable in-flight pricing; leaving all open races on
legacy behavior is the alternative product choice.

Rollback is code rollback for future/unstamped races only. Never lower an
already advertised or settled stamped reward. A bad open-race repair is rolled
forward with a corrected positive stamp, not erased.

## Tests-first plan

Backend integration tests must exist and fail for the intended reason before
business logic:

1. Create funded team races in every approved duration band; assert immutable
   stamps and exact detail/list/progress/public/Home projections.
2. Settle balanced 1v1 and 5v5 wins through the real expiry path; assert every
   eligible winner receives the fixed amount and total ledger/pool stamps match.
3. Forfeit one winning member; assert zero for the forfeiter, unchanged rewards
   for surviving winners, and a reduced total rather than redistribution.
4. Tie both teams; assert the approved per-person tie amount, rounding, ledger
   rows, and stamped pool.
5. Edit pending duration and exercise custom-window start repricing; assert the
   duration and payout stamps change atomically and freeze once active.
6. Legacy `NULL` rows retain byte-for-byte pool splitting; individual, seeded,
   buy-in, and tournament payouts are unchanged.
7. Recovery/double settlement emits no duplicate coin transaction and does not
   increase participant payout twice.
8. All serializers and the Redis lean/list path agree; missing/partial stamps
   safely take the legacy path.
9. Test the ceiling on race/tournament creation, public/share join, invite
   acceptance, private-request approval, and tournament equivalents. Cover
   concurrent fifth-vs-sixth cross-type requests, invitations not counting,
   idempotent retries, grandfathering, all release seams, and exclusions.
10. Cover Deployment A mixed-worker behavior, Redis DB 15 and Redis-unset modes,
    repair racing settlement/cache invalidation, the final zero/token-step rule,
    1/3/7/8/14/30-day boundaries, asymmetric ties/forfeits, payout-double from
    persisted awards, and repair dry-run/rerun idempotency.

Frontend widget tests pump real payout/results widgets with the new server
amounts and legacy/missing data. No local formula is introduced.

Verification: backend `npm run test:unit` and `npm run test:integration` (never
bare `npm test`), frontend `flutter analyze` and relevant `flutter test`, with
both iOS and Android behavior accounted for.

## Manual UI-placement test plan

**Elements under test:** The shared race-detail payout sheet adds a compact
`500 PER ELIGIBLE WINNER` fact for fixed-award team races, positioned with the
prize-pool summary and before the payout explanation/body; the obsolete
“winning team splits the whole pool evenly” copy is removed from that location.

**Elements under test:** Legacy or malformed team payout payloads retain the
generic team explanation in the same payout-sheet area and do not show the new
per-winner fact.

1. **Active team race detail — real screen**
   - **Get there:** On production after the open-race repair, open “boyz vs
     gorls” from Races → tap the prize-pool chip or scroll to PAYOUT → VIEW
     PAYOUTS.
   - **Verify:** `500 PER ELIGIBLE WINNER` appears once in the payout sheet,
     below the pool summary and above the remaining payout explanation/body.
     Confirm the old split-pool sentence is absent and the fact is not duplicated
     elsewhere in the sheet.
2. **Pending or shared-preview team race — real screen**
   - **Get there:** Open an invite/shared preview for a newly created funded
     4–7-day team race before joining → open its payout details.
   - **Verify:** The same per-winner fact appears once in the same sheet position
     before the explanation/body. Confirm it is not still represented by the old
     split-pool copy elsewhere.
3. **Legacy fallback — real screen**
   - **Get there:** Open a legacy funded team race whose response has no valid
     fixed-winner payout tiers, then open payout details.
   - **Verify:** No `PER ELIGIBLE WINNER` fact appears. The generic team
     explanation occupies the established callout/body area once, with no blank
     gap or duplicate where the new fact would sit.
4. **Narrow device, large text, dark appearance — real screen**
   - **Get there:** On a narrow phone, set system text size to approximately
     200% and dark appearance, then open the payout sheet for a fixed-award team
     race.
   - **Verify:** The per-winner fact remains between the pool summary and payout
     body, stays fully inside the sheet, and does not overlap the pool amount,
     PROJECTED badge, PAYOUTS heading, body, home indicator, or sheet edge.
     Scroll only if the sheet intentionally becomes scrollable; confirm no
     second copy appears above or below.
5. **iOS and Android parity — real screen**
   - **Get there:** Repeat checkpoint 1 on one iPhone and one Android device.
   - **Verify:** On both platforms the fact appears once in the same order,
     remains above the payout body, and is not clipped by the bottom safe area or
     covered by navigation/system UI.

**Surfaces confirmed unaffected:** Demo race tutorial (`DemoRaceHost` → real
`RaceDetailScreen`) is backed by a hand-built solo `TOP3_70_20_10` fixture, so
the team-only fact should not appear; during onboarding, reach the demo race and
confirm its existing payout sheet has no `PER ELIGIBLE WINNER` row.

**Surfaces confirmed unaffected:** Tab tutorial race-detail preview
(`TutorialRealScreens` → real `RaceDetailScreen`) is also seeded as a solo race,
so re-run the tutorial from Profile/Admin → reach the race-detail preview and
confirm no team-only fact appears in its payout sheet.

**Surfaces confirmed unaffected:** Create-race and invite screens do not render
`RacePrizePoolSheet`; the new fact is server-driven after a race response exists.

**Surfaces confirmed unaffected:** Race results summary uses persisted personal
payout UI, not the shared projection sheet, so its placement does not change.

**Surfaces confirmed unaffected:** Home and Races cards show pool totals but do
not instantiate the payout sheet; they should not gain the per-winner fact.

**Risks found while planning:** Both tutorial/demo race-detail mirrors reuse the
production screen, but their fixtures are solo races. They cannot visually
exercise the new team branch; absence there is expected, not evidence that team
placement works.

**Risks found while planning:** `race_detail_screen.dart` still contains a
separate legacy payout-sheet implementation with the obsolete split-pool copy.
Although the shipped route currently uses `RacePrizePoolSheet`, implementation
must update the legacy compatibility copy too so a future fallback cannot revive
incorrect wording or placement.

**Risks found while planning:** The fixed-award fact must appear only when server
tiers authoritatively and consistently identify the per-winner amount. Missing,
malformed, or inconsistent tiers must leave the established generic layout
intact without reserving an empty row.

**Risks found while planning:** The sheet has a fixed `0.84` height and a
non-scrollable top column around an expanded body; adding a row increases
overflow risk on narrow devices, large text, and devices with substantial
bottom safe areas.

## Acceptance criteria and definition of done

- A seven-day full 5v5 projects and settles 500 coins per eligible winner and
  2,500 total when all five winners remain eligible.
- Every duration and tie rule matches the approved table.
- Forfeits reduce total issuance and never enlarge another winner's award.
- Projection and settlement agree for identical stamped inputs; a pre-result
  maximum-liability projection may exceed settlement after forfeiture or a
  smaller-side win.
- Existing API keys and frozen clients remain compatible.
- Legacy and unrelated competition payouts do not change.
- Tests are written first and pass; backend and Flutter verification are green.
- `docs/economy.md` records the final curve and risk decision.
- Architect and post-implementation code reviews pass; the game-analyst returns
  `SOUND`/`SOUND WITH CHANGES`, or product explicitly records an `UNSOUND`
  override before implementation.
- No production deploy or data repair occurs without separate explicit approval.

## Revision log

- Initial draft: replaced divisible team pools with duration-stamped fixed
  winner rewards; preserved the existing wire contract; added fixed-award
  forfeiture behavior, tie proposal, legacy fallback, open-race repair, and
  tests-first implementation paths.
- Gap pass 1: found that current recipient eligibility and pool-contribution
  eligibility diverge; added an explicit 2,000 raw-step recommendation and
  clarified that it does not solve cross-race step reuse.
- Gap pass 2: applied eligibility consistently to ties, prohibited downward
  open-race repricing, required side-by-side maximum-liability reporting, and
  made missing tie shares non-redistributable.
- Product interview: approved the 100/200/500/1,000 bands, rejected unlimited
  funded participation in favor of a permanent five-competition ceiling,
  rejected a personal-step eligibility minimum, retained half rewards on ties,
  and approved an upward-only repair of all affected open funded team races.
- Architect review: required two compatibility deployments, precise atomic cap
  semantics, a fixed-planner bypass of legacy walker-pool math, compatibility
  metadata semantics, race-fenced admin-command repair with cache invalidation,
  server-driven per-winner UI, and expanded concurrency/Redis/repair tests.
- Game-economy review: returned `UNSOUND` despite the five-membership cap,
  quantified zero/token-step short-race farming, and added a final safeguard or
  explicit-risk decision plus monitoring and abuse-boundary coverage.
- Product economy override: selected the documented `UNSOUND` path, retaining
  the full curve and no activity threshold while preserving the five-live cap,
  monitoring, tests, and separate production authorization gates.
- Post-review gap pass: confirmed the override changes no API/migration logic,
  ensured it cannot be read as deployment authorization, and retained explicit
  zero/token-step integration coverage rather than hiding the accepted risk.
- UI-placement review: added the real-screen fixed/legacy checks, platform and
  accessibility coverage, demo/tutorial negative checks, legacy-sheet mirror,
  authoritative-tier gating, and fixed-height overflow risk.
