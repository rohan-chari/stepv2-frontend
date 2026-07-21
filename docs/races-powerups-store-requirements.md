# Races, Pocket Watch, Hitchhike, and Quick Rinse Requirements

**Status:** APPROVED — ready for contract-first implementation.
**Approved:** 2026-07-20.
**Delivery model:** backend contract first, then backend and frontend implementation in parallel; tests first in both repositories.

## 1. Summary and user stories

This batch makes tournaments feel like the races they contain, makes the Races tab easier to navigate, expands Pocket Watch without breaking its existing behavior, and adds two store powerups.

- As a racer, I see tournament activity alongside ordinary races in the state where I can act on it, including inventory and available boxes during a live matchup.
- As a racer, I can filter my personal race list by Active, Pending, and Completed with counts visible at a glance, while pending invitations stay pinned in view rather than hidden behind a filter.
- As a Pocket Watch holder, I can either extend my existing timed buffs or extend one active harmful debuff I personally applied to a rival.
- As a Hitchhike owner, I can copy an opponent's newly walked raw steps into my race score for an hour without taking steps from them.
- As a Quick Rinse owner, I can halve the remaining duration of every active timed opponent effect on me.

Daily-spin and race-ending notifications are already implemented and live; this spec records their verified state but does not add another notification system.

## 2. Scope and non-goals

### In scope

- Merge personal tournament entries into the normal personal race states.
- Add state-filter pills for the personal list, defaulted to Active.
- Surface live tournament-match inventory and mystery-box state in `GET /races`.
- Preserve Pocket Watch's existing self-buff behavior and add explicit single-debuff extension.
- Add store-only Hitchhike and Quick Rinse types, behavior, catalog entries, icons, inventory support, and client-feature gating.
- Raise Leech from 30 to 60 minutes for the carrying `powerups3` build while preserving the legacy 30-minute request contract (§7.5).
- Move powerup copy (name, description, short description, upgrade tier labels) to a backend-served per-type catalog with persistent and bundled client fallbacks, collapsing seven duplicated frontend maps into one (§9.5).
- Preserve iOS and Android behavior in lockstep and degrade safely against older backends.

### Non-goals

- Do not remove tournaments from the Featured discovery strip, or remove its `ALL / RACES / TOURNAMENTS` filter. (Relocating that filter into the Featured section header is in scope — see §4.1 — but it must keep working and keep scoping only the Featured strip.)
- Do not redesign the tournament bracket or public tournament discovery.
- Do not let Pocket Watch extend Hitchhike, untimed effects, another user's debuffs, or multiple rival debuffs in one use.
- Do not let Hitchhike copy bonuses, multipliers, debuff-adjusted totals, or steps copied by another Hitchhike.
- Do not let Hitchhike advance mystery-box progress.
- Do not make Quick Rinse affect self-buffs or untimed effects.
- Do not change the existing full Cleanse behavior.
- Do not deploy or write to production as part of implementation without separate, in-the-moment approval.

## 3. Current state

- Personal tournaments are returned in the additive `tournaments` bucket of `GET /races` and rendered in a separate `MY BRACKETS` section in `lib/screens/tabs/races_tab.dart`.
- Ordinary active race summaries already include `queuedBoxCount`, `mysteryBoxCount`, and `slotItems`; tournament summaries only expose `myCurrentMatchRaceId`.
- Pocket Watch currently extends all active timed self-buffs and rejects use when no eligible self-buff exists. Its upgrade durations are base `+1h`, level 1 `+1.5h`, level 2 `+2h`, and level 3 `+3h`.
- Pocket Watch is already present in the backend `RARE` tier in `src/utils/powerupOdds.js:7`; no rarity migration is needed. Note rarity is declared in **two** places — `powerupOdds.js:7` (drop tiers) and `powerupUpgrades.js:47` (`RARITY_BY_TYPE`, which drives the `[0, 15, 45, 135]` upgrade cost ladder). Both already list Pocket Watch as `RARE` and neither needs to change; the new store types need entries only where the code actually reads them.
- Full Cleanse remains a rare in-race drop but is retired from the store. It immediately expires all opponent-inflicted effects on the user.
- The powerup store uses a separate additive catalog and global inventory, with client-feature filtering for newer types.
- Production was verified on 2026-07-20 at backend revision `6fae32e`. It contains both reminder systems, and both reminder kill switches were unset.

## 4. Races page behavior

### 4.1 State filters

- Remove the personal `MY BRACKETS` section.
- Keep the Featured strip itself unchanged, but **relocate its `ALL / RACES / TOURNAMENTS` type filter into the Featured section header** as an inline control. Today that pill row (`races_tab.dart:428-500`) renders as a full-width segmented control that visually reads as a page-level filter while actually scoping only the Featured strip (`:793-794`); stacking a second, differently-scoped pill row beneath it would be ambiguous. Relocating it keeps the §2 non-goal (the filter is retained, not removed) while freeing the main pill row for state.
- **Invites are never hidden behind a pill.** Pending race and tournament invitations render as an always-visible strip **above** the pill row, retaining their inline Accept/Decline actions. Rationale: today `INVITES`, `PENDING`, and `ACTIVE RACES` all render simultaneously as collapsible sections (`races_tab.dart:1050-1088`); a pill defaulted to `ACTIVE` would hide the single most actionable item in the app on load. The invites strip is omitted entirely when the combined invite count is zero.
- Add the personal-list state filter below the invites strip:
  - `ACTIVE`
  - `PENDING`
  - `COMPLETED`
- Always show all three pills and a numeric count badge, including `0`.
- Initialize the selected state to `ACTIVE` whenever a new `RacesTab` state is created.
- Each pill renders one combined list of ordinary races and tournaments.
- Preserve pull-to-refresh, stale-data refresh indication, first-load skeleton, full-load error, and a state-specific empty message.
- The existing header metrics may remain; the new pills are the navigation control for the personal list.

#### Perf constraints (do not regress §9.5)

The Races tab was deliberately converted to lazy slivers; a redesign must not undo it.

- Keep each expanded state's rows in a `SliverList.builder` wrapped in `DecoratedSliver` for card chrome (`races_tab.dart:1096-1180`). Do **not** rebuild the list as a `Column` or `ListView(shrinkWrap: true)` — that materializes every row.
- Switching pills replaces which sliver list is emitted; it must not cause all four states' rows to build.
- Preserve the `_navigatingToRace` double-push guard (`:100`, `:303-306`).
- Pill count badges must be derived from the already-loaded `GET /races` payload. Do not issue additional requests, and do not block first paint on counts — a state whose bucket has not resolved yet renders its badge from the last known value rather than flickering to `0`.

### 4.2 Tournament-to-state mapping

Classify a personal tournament by the user's current action, not merely by the tournament's top-level status:

| Condition | Personal-list state |
|---|---|
| `myStatus == INVITED` and tournament is pending | Invites strip (pinned above pills) |
| `myStatus == INVITED` and tournament is already `ACTIVE` | Invites strip, rendered as expired/unavailable with Decline only |
| `myCurrentMatch != null` | Active |
| Accepted lobby participant | Pending |
| Accepted, alive, and between tournament rounds | Pending |
| Eliminated | Completed |
| Champion | Completed |
| Tournament completed | Completed |

The mapping must be defensive: missing or unknown status fields cannot crash the list. An accepted tournament with no live matchup and no conclusive completed/eliminated signal defaults to Pending.

### 4.3 Row behavior

- Active tournament rows reuse the active-race row's visual and inventory language.
- Show tournament name, a bracket/round marker, matchup countdown, placement or masked placement, three active inventory slots, and the queued slot.
- Tapping a row with `myCurrentMatch.raceId` opens `RaceDetailScreen`. The existing tournament banner inside the matchup provides navigation to the bracket.
- Tapping lobby, between-round, eliminated, champion, or completed entries opens `TournamentDetailScreen`.
- Tournament invitations retain inline Accept and Decline actions inside the pinned invites strip.
- Missing `myCurrentMatch`, `slotItems`, or count fields render empty slots and never throw.

## 5. Races API contract

### `GET /races` — additive tournament match summary

Retain the existing top-level buckets and retain `tournaments[*].myCurrentMatchRaceId` for clients already reading it. Add `myCurrentMatch` to each tournament summary:

```json
{
  "active": [],
  "pending": [],
  "completed": [],
  "tournaments": [
    {
      "id": "tournament-id",
      "name": "Bara Bracket",
      "status": "ACTIVE",
      "myStatus": "ACCEPTED",
      "myEliminatedInRound": null,
      "currentRound": 2,
      "myCurrentMatchRaceId": "race-id",
      "myCurrentMatch": {
        "raceId": "race-id",
        "endsAt": "2026-07-20T22:00:00.000Z",
        "myPlacement": 2,
        "myPlacementHidden": false,
        "queuedBoxCount": 1,
        "mysteryBoxCount": 1,
        "slotItems": [
          {
            "id": "powerup-id",
            "type": "LEG_CRAMP",
            "rarity": "UNCOMMON",
            "status": "HELD"
          },
          {
            "id": "box-id",
            "type": null,
            "rarity": null,
            "status": "MYSTERY_BOX"
          }
        ]
      }
    }
  ]
}
```

Rules:

- `myCurrentMatch` is `null` unless the viewer is an accepted participant in a currently active tournament matchup.
- Its inventory semantics match ordinary active race summaries.
- The backend must bulk-fetch match inventory/effect data; do not introduce per-tournament or per-row query amplification.
- An older client ignores the additive object. A new client talking to an older backend treats it as `null` and falls back to bracket navigation without inventory.

## 6. Pocket Watch

### 6.1 Behavior

- Preserve legacy behavior when `targetEffectId` is absent: extend every active timed self-buff belonging to the user.
- Preserve the existing upgrade durations and upgrade pricing behavior.
- Add a second mode that extends exactly one selected active timed harmful effect that the current user applied.
- Eligible targeted types are:
  - `LEG_CRAMP`
  - `WRONG_TURN`
  - `DETOUR_SIGN`
  - `SIGNAL_JAMMER`
  - `LEECH`
  - `RAINSTORM`
- `RAINSTORM` is AoE and writes one `RaceActiveEffect` row per affected rival. It stays eligible, and extending it prolongs **exactly one** rival's row — the same single-effect rule as every other type. The `MY DEBUFFS` sheet must therefore list each affected rival as its own selectable entry rather than one "Rainstorm" line, so the single-target scope is explicit before the user pays.
- Exclude Hitchhike, self-buffs, untimed effects, expired effects, effects from another source user, and effects in another race.
- The existing `isPocketWatchExtendable` predicate (`usePowerup.js:116-123`) already excludes untimed effects and opponent debuffs for the legacy path; the targeted path needs its own allowlist check rather than a change to that predicate, so legacy behavior stays bit-identical.
- The extension adds the selected tier's duration to the effect's current `expiresAt`.
- The extension modifies an effect that already passed defenses; it does not trigger Compression Socks or Mirror.
- Perform all validation before coin deduction or powerup consumption.

### 6.2 Progress capability contract

Add the effect identifier and capability flag to `GET /races/{raceId}/progress`:

```json
{
  "progress": {
    "powerupData": {
      "capabilities": {
        "pocketWatchTargetEffect": true
      },
      "activeEffects": [
        {
          "id": "active-effect-id",
          "type": "LEG_CRAMP",
          "expiresAt": "2026-07-20T23:00:00.000Z",
          "onSelf": false,
          "targetUserId": "target-user-id",
          "sourceUserId": "viewer-user-id"
        }
      ]
    }
  }
}
```

The frontend must not offer targeted mode unless `pocketWatchTargetEffect == true`. Missing, null, or malformed capability data means legacy self-buff mode only. This prevents a new client talking to an older backend from sending an ignored `targetEffectId` and extending the wrong effects.

### 6.3 Use contract

Extend the existing endpoint without changing legacy requests:

```http
POST /races/{raceId}/powerups/{powerupId}/use
```

Legacy self-buff request:

```json
{
  "upgradeLevel": 1
}
```

Targeted request:

```json
{
  "upgradeLevel": 1,
  "targetEffectId": "active-effect-id"
}
```

Targeted success:

```json
{
  "result": {
    "extendedEffects": 1,
    "extensionMs": 5400000,
    "extensionMode": "OWN_DEBUFF",
    "extendedEffect": {
      "id": "active-effect-id",
      "type": "LEG_CRAMP",
      "targetUserId": "target-user-id",
      "expiresAt": "2026-07-21T00:30:00.000Z"
    }
  }
}
```

Errors use the existing `{ "error": "...", "code": "..." }` envelope:

- `400 INVALID_EFFECT` — missing, expired, untimed, wrong race, or ineligible effect type.
- `403 EFFECT_NOT_OWNED` — `sourceUserId` is not the acting user.
- Existing race, inventory, upgrade, jammed, and insufficient-coin errors remain unchanged.

### 6.4 Frontend UX

- Replace the generic Pocket Watch action sheet with an explicit two-mode sheet:
  - `MY BUFFS` shows the count and explains that every eligible timed self-buff will be extended.
  - `MY DEBUFFS` shows eligible effects grouped by rival, with powerup icon, avatar/name, and current remaining time.
- Disable a mode with explanatory copy when its eligible count is zero.
- In either mode, show the existing four extension tiers and authoritative backend-driven coin costs.
- Targeted mode requires selecting one effect before confirming a tier.
- Canceling at any stage consumes nothing.
- Refresh progress after success and show copy naming the extended effect and rival.

## 7. Hitchhike

### 7.1 Product behavior

- Type: `HITCHHIKE`.
- Store-only; never roll it from a race mystery box or daily reward box.
- Price: 150 coins.
- Duration: **60 minutes** (`HITCHHIKE_DURATION_MS = 60 * 60 * 1000`).
- Target: an active opponent in the same race.
- Copy the target's recorded raw physical steps during the scoring window (§7.3) at 1:1 into the caster's race score.

**Why 60 minutes and not 30.** `StepSample` rows are hourly buckets prorated linearly into a window (`src/models/stepSample.js:127-160`). To keep credited steps monotonic, `computeLeechEarnedTransfer` excludes the in-progress hour bucket (`src/utils/leechTransfers.js:41-48`), accepting up to an hour of lag. Hitchhike reuses that rule, so a 30-minute window would frequently close *before* any bucket it depends on does — the caster would pay 150 coins, see zero effect for the powerup's entire life, and receive the steps only after it expired. A 60-minute window normally allows at least one bucket to close while the effect is still live, though delayed device sync can still postpone visible credit. This is a known, accepted tradeoff already shipped for Leech (`LEECH_DURATION_MS`, `usePowerup.js:82`); Hitchhike must not repeat it at a longer, more expensive price point.
- Do not remove or change the target's steps.
- Do not copy positive multipliers, negative modifiers, bonus steps, global-event bonuses, Leech transfers, or another Hitchhike's copied steps.
- Do not multiply the copied amount again through the caster's effects.
- Copied steps affect live placement, final results, and payouts.
- **Copied steps ARE drainable by a Leech on the caster.** The Hitchhike term is added into `preLeechTotal` before `applyLeechTransfers` resolves, so once copied the steps are ordinary steps for every downstream purpose. (Decision: consistency over safe-haven — there is no protected score category.)
- Copied steps do not advance the caster's mystery-box thresholds. This is satisfied structurally, not by a special case: `computeBoxEffectiveSteps` is `max(0, baseAdjusted)` and already ignores every non-`baseAdjusted` term (`src/utils/boxSteps.js:22-28`). The Hitchhike term must therefore be added at the `preLeechTotal` assembly and **never** folded into `baseAdjusted`.

### 7.2 Targeting, stacking, and counterplay

- Reject self, teammate, forfeited, finished, nonparticipant, and stealthed targets using the established targeted-powerup rules.
- A caster may have at most one active Hitchhike.
- **A target may have at most one active Hitchhike.** (Revised from two.) At 60 minutes, two simultaneous 1:1 copies mint a large additive amount against a player who cannot see the link coming and can only remove it with Cleanse. Unlike Leech — which is zero-sum and therefore self-limiting — Hitchhike creates new steps, so concurrent links compound. Reject a second link with `409 HITCHHIKE_TARGET_FULL`.
- **Target exits mid-window.** If the target finishes or forfeits while a link is active, the scoring window end clamps to their finish/forfeit time. Raw `StepSample` rows keep accruing from real-world walking after a participant leaves a race, so without this clamp a caster would copy steps taken after the target was out. This mirrors the existing Leech rule that finished/forfeited participants neither drain nor credit (`leechTransfers.js:68-70`). The link row is left in place and expires normally; only the window is clamped.
- Compression Socks blocks Hitchhike activation and is consumed through the existing blocked-outcome flow.
- Mirror does not reflect Hitchhike.
- These two rules are achieved by list membership alone, with no new branching: add `HITCHHIKE` to `OFFENSIVE_TYPES` (`usePowerup.js:44`) so Socks blocks it, **and** to `SHOP_POWERUP_TYPES` (`:53`) so Mirror's reflect guard skips it. Also add it to `TARGETED_TYPES` (`:60`). Do not add a hard-coded exception in the style of the `IMPOSTER` branch at `:785`.
- A successful link is visible on the target's effect rail and sends the existing targeted `POWERUP_USED` push.
- Full Cleanse immediately ends the active link. **Cleanse must clamp `expiresAt = now` and set `status = EXPIRED`, exactly as the existing Cleanse case does (`usePowerup.js:1064-1078`) — it must never delete the effect row.** Deleting it would erase the already-credited copy retroactively and drop the caster's visible score. Clamping is safe because the scoring window end is `min(expiresAt, …)` and any clamp value is `>= now`, so no already-closed bucket is lost.
- Quick Rinse halves its remaining duration. This is likewise non-retroactive for the same reason: the halved `expiresAt` is always `> now`, so it only shortens future accrual.

### 7.3 Persistence and scoring

- Add `HITCHHIKE` to `PowerupType` through an additive PostgreSQL enum migration.
- Persist one timed `RaceActiveEffect` targeting the walked-on participant, with the hitchhiker as `sourceUserId`.
- Store versioned metadata:

```json
{
  "copyRatio": 1,
  "scoringVersion": 1
}
```

`copyRatio` is read per-effect with a default of `1` when missing or malformed, following `leechRatio` (`leechTransfers.js:27-30`). This makes the copy strength a **data-only tuning lever** — rebalancing needs no code change or migration.

- Implement one shared Hitchhike calculation utility (`src/utils/hitchhikeCopies.js`) consumed by both live progress and race settlement/background resolution, mirroring the structure of `src/utils/leechTransfers.js`.
- **Scoring window** — identical rule to Leech, reusing `stepSampleModel.sumStepsInWindow` against the *target's* `targetUserId`:

```text
windowStart = effect.startsAt
rawEnd      = min(effect.expiresAt ?? now,
                  raceEndsAt ?? +inf,
                  targetFinishedAt ?? targetForfeitedAt ?? +inf)
windowEnd   = min(rawEnd, topOfCurrentHour)   // in-progress bucket excluded
copied      = floor(sumStepsInWindow(targetUserId, windowStart, windowEnd) * copyRatio)
```

- Excluding the in-progress hour bucket is **required**, not optional: that bucket's prorated contribution shifts on every re-upsert, and a shifting divisor on a visible recipient's score is the exact non-monotonicity that motivated the Leech rule.
- Do not estimate from a whole-day total when samples are absent; missing sample evidence contributes zero until a later sync supplies it.
- Recalculation must be deterministic and must not incrementally write copied steps into `bonusSteps`, which would double-credit repeated reads.

#### The live/settlement parity landmine

The *inputs* to scoring are shared (`computeEffectModifiers` is exported from `getRaceProgress.js:958` and imported by `raceStateResolution.js:8`), but the **final assembly line is duplicated verbatim** at `getRaceProgress.js:659` and `raceStateResolution.js:203-212`:

```text
preLeechTotal = max(0, baseAdjusted - frozenSteps + buffedSteps
                       - 2*reversedSteps + globalBoostedSteps
                       + (powerupsEnabled ? bonusSteps : 0))
```

A shared `computeHitchhikeCopies` utility is therefore **not sufficient** — its output is a new additive term that must be inserted at every assembly site, before `applyLeechTransfers` runs.

**CORRECTED (2026-07-20): there are SIX sites, not two.** This section originally named only `getRaceProgress.js` and `raceStateResolution.js`. A full `grep -rn "applyLeechTransfers" src/` finds six call sites:

| site | what breaks if the term is missing |
|---|---|
| `src/queries/getRaceProgress.js:698` | live race-detail total |
| `src/services/raceStateResolution.js:747` | settlement / final standings |
| `src/jobs/raceExpiry.js:143` | final settled standings at expiry |
| `src/services/reconcileUploaderRaces.js:136` | background reconcile |
| `src/queries/getHomeRaceCard.js:528` | **home-tab card total diverges from race detail** |
| `src/commands/forfeitRace.js:98` | **a forfeiting caster loses their accrued copy from their frozen final total** |

**The parity guard must DISCOVER these sites, not hardcode them.** A first implementation hardcoded a four-entry list and therefore passed while two sites were missing — worse than no guard, because it manufactured confidence. The guard must walk `src/`, find every file containing an `applyLeechTransfers(` call (excluding the two utility modules), and assert each wraps `applyHitchhikeCopies(`, so any future assembly site is covered automatically.

### 7.4 Use result and errors

Use the existing endpoint with `targetUserId`:

```json
{
  "targetUserId": "target-user-id"
}
```

Success:

```json
{
  "result": {
    "outcome": "APPLIED",
    "effect": {
      "id": "effect-id",
      "type": "HITCHHIKE",
      "sourceUserId": "caster-user-id",
      "targetUserId": "target-user-id",
      "startsAt": "2026-07-20T20:00:00.000Z",
      "expiresAt": "2026-07-20T21:00:00.000Z"
    },
    "durationMs": 3600000,
    "copyRatio": 1
  }
}
```

Additional errors:

- `409 HITCHHIKE_ALREADY_ACTIVE` — caster already has an active link.
- `409 HITCHHIKE_TARGET_FULL` — target already has an active link (limit is 1).
- Existing blocked and invalid-target envelopes remain unchanged.

## 7.5 Leech duration change (capability-versioned)

Leech becomes **60 minutes for clients advertising `powerups3`** so it matches Hitchhike and becomes visible while live. Same reasoning as §7.1: with the in-progress hour bucket excluded for monotonicity, a 30-minute window frequently closes before any bucket it depends on does, so a buyer can see zero effect for the powerup's entire life.

The duration change must not reinterpret an old client's request:

- Keep `LEGACY_LEECH_DURATION_MS = 30 * 60 * 1000` for requests without `powerups3`.
- Add `LEECH_DURATION_MS = 60 * 60 * 1000` for requests whose `clientFeatures` contain `powerups3`.
- Thread request-scoped client features into the existing use command and choose the duration at activation. Do not infer capability from the user's sticky stored feature union.
- Require `powerups3` for Leech catalog visibility going forward.

> **PREREQUISITE — verify before backend deploy.** An earlier draft asserted "Leech is currently `testOnly`." **That is not true in the repository.** `schema.prisma:535` declares `testOnly Boolean @default(false)`, and the Leech seed entry (`seed.js:148-156`) sets `active: true` and **never sets `testOnly`**, so it defaults to `false`. Leech's only gate today is `powerups2`, which the committed client already advertises (`08fa91b`); the app is at 1.6.5. Production rows do drift from seed (see the Cleanse note at `seed.js:135-138`), so the live value must be confirmed, not assumed.
>
> **Decision (confirmed 2026-07-20):** Leech is `testOnly:true` through this deploy **and** through the carrying binary's rollout. The owner flips it to `false` manually once that binary has shipped. The seed sets `testOnly: true` explicitly so fresh and staging databases match; the prod row is owner-executed.
>
> This is a deliberate, accepted removal of Leech from the store for current-build users. Note the `powerups3` catalog gate would remove it from those users regardless — the `testOnly` flag makes the removal explicit and intentional rather than a side effect, and gives a single lever to restore it.
>
> Scope of the Leech flag is narrow: Leech is already excluded from the daily-box prize pool (`getEligiblePowerupPool` filters both gated lists), so `testOnly` affects **store visibility only**. Contrast Rainstorm (§9.2.1), where it also removes box drops.
>
> `testOnly` gates **catalog visibility, not usage**: existing owners keep their Leeches and can still use them (the Cleanse precedent, `seed.js:133-137`). An old-build owner spending a banked Leech gets the legacy 30 minutes, which matches the copy their binary renders. No user is left with a powerup that behaves differently than their app describes.
>
> This step is **owner-executed**. No implementation agent may read or write production (§9.2). If the flip has not happened, the `powerups3` catalog-visibility requirement must not ship — it would remove a purchasable item from live users at deploy time, violating the repository's first rule from the backend side.
- Ratio stays 2:1, price stays 150, `metadata` stays `{ ratio: 2, scoringVersion: 2 }`, and the stacking guard (`usePowerup.js:488-497`, max 2 leechers per victim) is unchanged.
- In-flight effects are unaffected because existing `RaceActiveEffect` rows already have a concrete `expiresAt`.

### 7.5.1 Copy and rollout

- The backend copy catalog (§9.5) serves the 60-minute Leech description to the carrying `powerups3` client.
- Make the carrying binary's bundled emergency Leech description duration-neutral (for example, “Every 2 steps you take steals 1 step from a chosen rival and adds it to your score”). Do not hardcode either 30 or 60 minutes in the new fallback: a new client can temporarily talk to an old backend, which still applies 30 minutes, while the new backend applies 60 for `powerups3`. The authoritative backend row supplies the precise 60-minute copy whenever the new endpoint is available.
- Replace the old inline “30-minute window” comment with capability-aware wording rather than hardcoding 60.
- Do not update `PowerupShopItem.name` or `.description` manually in production; after §9.5 the shop response sources both from the copy catalog.
- Keep Leech `testOnly:true` and gated behind `powerups3` through the carrying build's rollout. Any later production launch is a separately approved catalog change.

This preserves every compatibility pairing: an old binary creates and describes 30 minutes; a new binary against an old backend shows truthful duration-neutral fallback and receives 30 minutes; and a new binary against the new backend fetches 60-minute copy and creates a 60-minute effect.

### 7.5.2 Existing-test preservation

`test/commands/leechPowerup.test.js:152` asserts that the legacy Leech window is exactly 30 minutes. **Do not modify it.** It becomes the backward-compatibility guard for a request without `powerups3`.

Write a new test first that sends request-scoped `powerups3` and expects exactly 60 minutes. Add another new test proving that a user's sticky stored feature union cannot upgrade a request that omitted the header. No existing test or assertion may be modified or deleted.

## 8. Quick Rinse

### 8.1 Product behavior

- Type: `QUICK_RINSE`.
- Store-only; never roll it from a race mystery box or daily reward box.
- Price: 75 coins.
- Self-only and instantaneous.
- Find every active effect targeting the user where `sourceUserId != targetUserId` and `expiresAt > now`.
- For each eligible effect:

```text
new expiresAt = now + floor((old expiresAt - now) / 2)
```

- This includes Hitchhike and existing timed opponent debuffs.
- It excludes self-buffs and effects without an expiry.
- Keep shortened rows active; normal expiry processing ends them at the new instant.
- If there are no eligible timed opponent effects, reject before consumption.
- **Signal Jammer blocks Quick Rinse**, like every other powerup. `usePowerup.js:277-292` blocks all powerup use while jammed, explicitly including Cleanse. Quick Rinse inherits this unchanged. Noted because it is counter-intuitive — Quick Rinse is the "get effects off me" item and Jammer is the most common lockout, so a jammed player holding a Quick Rinse cannot use it. This matches shipped Cleanse behavior; changing it would alter a live powerup and is a §2 non-goal. Do not add a bypass.

### 8.2 Use result and errors

Use the existing endpoint with an empty request body:

```json
{}
```

Success:

```json
{
  "result": {
    "shortened": 2,
    "reductionFraction": 0.5,
    "affectedEffects": [
      {
        "id": "effect-id",
        "type": "LEG_CRAMP",
        "expiresAt": "2026-07-20T23:15:00.000Z"
      }
    ]
  }
}
```

No eligible effects:

```json
{
  "error": "No timed debuffs to rinse",
  "code": "NO_TIMED_DEBUFFS"
}
```

Return status `409` and retain the inventory item.

## 9. Data model, catalog, gating, and artwork

### 9.1 Migration

- Add PostgreSQL enum values `HITCHHIKE` and `QUICK_RINSE` to `PowerupType` through an additive migration.
- **Ordering constraint:** `prisma/schema.prisma:581-628` documents that new values must be appended **before** `mystery_box` to match the declared enum ordering. Use `ALTER TYPE ... ADD VALUE ... BEFORE 'mystery_box'`, not a bare `ADD VALUE`, or the DB ordering diverges from the schema and the next `prisma migrate diff` produces spurious drift.
- Do not alter or remove existing enum values, tables, or columns.
- No backfill is required; no row uses the values before the new behavior is deployed.
- The deploy runs under pm2 **cluster** mode via `pm2 reload`, so old and new processes overlap briefly. Enum addition is safe under overlap (old processes simply never emit the new values); the migration must land before the reload.

### 9.2 Catalog

Add idempotent catalog entries:

| SKU | Name | Type | Price | Active | Initial `testOnly` |
|---|---|---|---:|---|---|
| `POWERUP_HITCHHIKE` | Hitchhike | `HITCHHIKE` | 150 | true | true |
| `POWERUP_QUICK_RINSE` | Quick Rinse | `QUICK_RINSE` | 75 | true | true |

- Introduce the `powerups3` client-feature token. Add a `POWERUPS3_GATED_TYPES = ["LEECH", "HITCHHIKE", "QUICK_RINSE"]` constant to `src/constants/powerupGating.js` alongside the existing `POWERUPS2_GATED_TYPES` (`:16`), remove `LEECH` from `POWERUPS2_GATED_TYPES`, and filter on the new group in `getPowerupShopCatalog.js:41-49` and `getEligiblePowerupPool.js:25-27` using the same shape.
- The shop catalog returns these types only when the requesting client advertises `powerups3`.
- Keep both types out of `getEligiblePowerupPool`, race mystery-box tiers, and daily reward powerup pools.

#### Rollout gating

**Both rows stay `testOnly:true` until the carrying build has rolled out.** This is double-gated on purpose:

- `powerups3` is a **per-build**, not per-user, signal — the test build and the shipped App Store build advertise the same token, so it cannot on its own distinguish the author from a real user. `testOnly` is the gate that can.
- `testOnly` is a **release-channel gate, not an account allowlist**: TestFlight-channel requests can see test-only rows and prod-channel requests cannot. Validate on staging and controlled TestFlight distribution; external TestFlight testers are real users and may spend real coins if given the build.
- Frozen old clients are protected twice over — they never advertise `powerups3` and never see `testOnly` rows.
- Flip to `testOnly:false` only **after** the carrying iOS and Android build has completed phased rollout, via a separately approved production DB change.
- Rollback stays gate-first (§11): re-set `testOnly:true` or drop `powerups3` from catalog visibility, without deleting enum values, effects, or user inventory.

**Neither implementation agent may perform any production catalog change.** Agents ship code, the migration, and staging data only. Every production flip is performed manually by the repository owner. This preserves `CLAUDE.md`'s hard rule that no production DB mutation happens without separate, in-the-moment approval.

### 9.2.1 Rainstorm withdrawal (follow-up, decided 2026-07-20)

Rainstorm is to be pulled from circulation via `testOnly:true`. **This is queued as a follow-up to the main batch** — relay to the backend agent only after it reports on the locked scope, so an in-flight tests-first run is not perturbed.

Current state: `seed.js:104-113` — `active: true`, `testOnly` unset (so `false`), 75 coins, live since 2026-07-04.

**Blast radius is wider than the store.** `getEligiblePowerupPool` derives its prize list from `PowerupShopItem.findActive({ channel })` (`getEligiblePowerupPool.js:20`), and `findActive` applies `testOnlyFilter(channel)` (`powerupShopItem.js:7-12`). So `testOnly:true` removes Rainstorm from:

- the powerup shop catalog, **and**
- the daily reward box RARE prize pool, **and**
- the spin-reel preview for `spinpowerups` clients

Rainstorm is not in the in-race drop tiers (`powerupOdds.js:7` does not list it), so store + daily box is its entire surface. The flip therefore removes it from circulation completely. **This is the intended outcome** — confirmed, not a side effect to be worked around.

Existing owners are unaffected: `testOnly` gates acquisition, not usage. Banked Rainstorms remain usable.

Gate via `testOnly`, **not** via `active:false`. Those mean different things: `active:false` is retirement (the Cleanse precedent, `seed.js:133-138`), `testOnly:true` is channel gating. Rainstorm is being gated, not retired.

Work split:

- **Agent:** add `testOnly: true` to the Rainstorm seed entry so fresh and staging databases match. Leave `active: true` untouched. The seed's `update` block must continue to omit `testOnly` so re-seeding can never stomp an owner-set value.
- **Owner (production):** the prod row is already seeded, so re-seeding will not flip it — it needs an explicit `UPDATE powerup_shop_items SET test_only = true WHERE sku = 'POWERUP_RAINSTORM';`. Same footgun as the Cleanse note at `seed.js:133-138`. No agent touches production.

**Both Leech and Rainstorm stay `testOnly:true` through this deploy and the carrying binary's rollout.** The owner flips both to `false` manually once that binary has shipped. There is no scenario in this batch where an agent changes a production catalog row.

### 9.3 Frozen-client handling

- Old clients do not advertise `powerups3` and never see the new store items.
- Hide Hitchhike active-effect entries from progress responses to clients without `powerups3`, while still applying the authoritative backend score.
- **Accepted consequence — unexplained score movement on frozen clients.** A target on an old build sees the caster's total climb with no effect icon and no explanation, because the effect entry is withheld while the score is not. This is the most visible old-client artifact in the batch and is accepted deliberately: the alternative — sending an unknown effect type to a binary that cannot render it — risks a worse failure than an unexplained number. The artifact disappears as builds update.
- **Use generic Hitchhike push copy for every recipient build.** A successful link fires the existing targeted `POWERUP_USED` push, but device tokens do not store per-build capabilities and `User.clientFeatures` is a sticky union across all of a user's devices. The server therefore cannot safely choose version-specific wording per token. Use generic copy such as “A rival linked to your steps” without interpolating the unrenderable type name. Routing continues to use the existing generic fallback for unknown types.
- Unknown feed/push types must continue using generic navigation and fallback rendering rather than crashing.
- Existing no-parameter Pocket Watch requests retain their exact legacy meaning.
- Every new response field is additive and every frontend reader defaults missing/null/malformed fields safely.

### 9.4 Artwork

- Generate Hitchhike and Quick Rinse icons through the Codex imagegen workflow; do not hand-draw shippable artwork or use `CustomPainter` for it.
- Generate in a scratch directory with several existing `assets/images/powerups/*.png` files as style references.
- Use chunky retro pixel art, a bold continuous black outline, clear small-size readability, and clean transparency.
- Composite against white for critique, verify clean alpha, preview at actual store/inventory sizes, and perform a targeted regeneration for any failed criterion.
- Every existing powerup icon is **128×128**, and 24 of 26 also ship a tightly-cropped `_thumb` variant used by thumb-first rendering (`PowerupIcon.assetPathFor`, `powerup_icon.dart:51-57`). `leech` and `defense_scan` shipped without thumbs; **do not repeat that gap.**
- Copy only approved icons to:
  - `assets/images/powerups/hitchhike.png` (128×128)
  - `assets/images/powerups/hitchhike_thumb.png`
  - `assets/images/powerups/quick_rinse.png` (128×128)
  - `assets/images/powerups/quick_rinse_thumb.png`
- Backfilling the missing `leech_thumb` / `defense_scan_thumb` is **out of scope** for this batch.
- Confirm both glob into `pubspec.yaml`.

#### Exact wiring checklist

Powerup names and descriptions are **duplicated across seven files with no single source of truth**. A partial edit ships a raw enum string (`HITCHHIKE`) into the UI, because every reader falls back to `_powerupNames[type] ?? type`. All seven must be migrated:

1. `lib/screens/race_detail_screen.dart:77-160` — `_powerupNames`, `_powerupDescriptions`, `_powerupShortDescriptions`
2. `lib/widgets/item_slot.dart:9`
3. `lib/screens/case_opening_screen.dart:13`
4. `lib/screens/multi_case_opening_screen.dart:35`
5. `lib/widgets/case_opening_strip.dart:647` (+ rarity map `:519`)
6. `lib/widgets/attack_outcome_modal.dart:15` (`_powerupDisplayNames`)
7. `lib/widgets/feed_bubble.dart:114` (`_powerupDisplayNames`)

Additionally:

- `lib/widgets/powerup_icon.dart:20-47` — add both to `_assetNames` and bump `knownTypeCount` (`:49`).
- `lib/screens/race_detail_screen.dart:171-184` — add `HITCHHIKE` to `_targetedPowerups` so it routes to `_showTargetPicker` (`:1627`). Quick Rinse is self-only and must **not** be added.
- `lib/services/backend_api_service.dart:107-109` — append `powerups3` to **both branches of the `_adsSupported` ternary.** Editing only one silently disables the feature on ad-less builds.
- Preserve the generic unknown-type fallback (`_PowerupFallbackIcon`, `powerup_icon.dart:86-106`) in all cases.

## 9.5 Backend-served powerup copy (single source of truth)

### 9.5.1 Problem

Powerup copy exists in two independently-editable places today, with nothing keeping them in sync:

- **Backend:** `PowerupShopItem.name` / `.description`, served by `getPowerupShopCatalog.js:53-58` and consumed by the shop tab (`shop_tab.dart:722,764,817`).
- **Frontend:** hardcoded maps duplicated across seven files (see §9.4 checklist), used by every in-race surface because `getRaceProgress` and the inventory payloads serve no copy.

Leech demonstrates the failure: `prisma/seed.js:150` and `race_detail_screen.dart:135-136` contain the *same sentence*, and §7.5 changes the behavior both describe. Any backend-driven value rendered as static client text has this problem — durations, ratios, prices, counts.

Coverage is also incomplete: **only 6 of 27 `PowerupType` values have a `PowerupShopItem` row** (`CLEANSE`, `DEFENSE_SCAN`, `IMPOSTER`, `LEECH`, `RAINSTORM`, `SIGNAL_JAMMER`). Twenty other usable types have no backend copy at all, and the final enum value is the non-usable `MYSTERY_BOX` container state. `PowerupShopItem` therefore cannot be the source of truth — it is keyed by SKU and scoped to purchasables.

### 9.5.2 Data model

Add Prisma model `PowerupCopy` mapped to table `powerup_copy`, keyed by `PowerupType`, with one row for each **user-renderable powerup type**. There are 26 today and 28 after adding Hitchhike and Quick Rinse. `MYSTERY_BOX` is intentionally excluded: it is an unopened-container/inventory state, not a usable powerup with use-sheet or effect copy.

| column | type | notes |
|---|---|---|
| `powerupType` | `PowerupType` | PK, mapped to `powerup_type` |
| `name` | `String` | e.g. `"Leech"` |
| `description` | `String` | long, use-sheet copy |
| `shortDescription` | `String?` | mapped to `short_description`; **nullable** — effect-rail label, e.g. `"Steps being stolen"` |
| `upgradeTierLabels` | `String[]` | mapped to `upgrade_tier_labels`; default `[]`; 4 entries for upgradeable types, empty otherwise |
| `updatedAt` | `DateTime` | mapped to `updated_at`; `@updatedAt` |

- Seeded idempotently from the current frontend maps plus the approved Hitchhike and Quick Rinse copy, so behavior is identical on day one apart from the intentional new types and 60-minute `powerups3` Leech copy.
- **Coverage is uneven and the schema must tolerate it.** `_powerupNames` and `_powerupDescriptions` have 26 entries each, but `_powerupShortDescriptions` has only **15** (`race_detail_screen.dart:144-160`). `shortDescription` is therefore nullable, seeded only where a string exists today.
- **CORRECTED (2026-07-20).** An earlier draft of this bullet claimed the client "omits the effect-rail subtitle entirely, exactly as it does now." **That was factually wrong.** The shipped code at `race_detail_screen.dart:3757-3759` resolves `_powerupShortDescriptions[type] ?? _powerupDescriptions[type] ?? ''` — it falls back to the **full** description, and 11 of 26 types rely on that path today. Omitting the line would blank the subtitle for those 11 types: a visible regression, not a preservation.
- **Required behavior:** when `shortDescription` is null, fall back to `description`, then to empty — preserving the shipped chain exactly. The original concern was about substituting a *truncated* description, which the code never did.
- `upgradeTierLabels` encodes durations (`"Extend 1h"`, `"Extend 1.5h"`…) and drifts for the same reason Leech did; upgrade *costs* are already backend-driven (`getRaceProgress` → `upgradeCosts`), so this makes tiers fully data-driven.
- **`PowerupShopItem.name` and `.description` stop being read.** `getPowerupShopCatalog` keeps returning both fields — old clients depend on the existing response shape — but sources both strings from this table. The old columns remain in place for additive-schema compatibility and are marked deprecated in comments. SKU, price, active state, `testOnly`, and inventory ownership remain shop concerns.

### 9.5.3 Contract

```http
GET /powerups/catalog
```

```json
{
  "version": "2026-07-20T22:15:00.000Z",
  "powerups": [
    {
      "type": "LEECH",
      "name": "Leech",
      "description": "For 60 min, every 2 steps you take steals 1 step from a chosen rival and adds it to your score. Compression Socks block it; Mirrors can't reflect it",
      "shortDescription": "Steps being stolen",
      "upgradeTierLabels": []
    },
    {
      "type": "POCKET_WATCH",
      "name": "Pocket Watch",
      "description": "…",
      "shortDescription": "…",
      "upgradeTierLabels": ["Extend 1h", "Extend 1.5h", "Extend 2h", "Extend 3h"]
    }
  ]
}
```

- `version` is the maximum catalog-row `updatedAt` serialized as an ISO-8601 string. It changes whenever any returned copy changes and lets the client identify the last-known-good snapshot deterministically.
- Unauthenticated-safe and client-feature-independent: returns all 28 user-renderable types, excluding only `MYSTERY_BOX`. Copy is not a capability — acquisition gating happens at the shop/roll layer, and receiving copy for a type a client cannot obtain is harmless.
- Response is additive-only. Future fields append; no client may require them.

### 9.5.4 Frontend consumption

- Fetch non-blockingly on app launch/authentication and whenever the app returns to the foreground. Coalesce concurrent refreshes so multiple rebuilding screens cannot issue duplicate requests.
- Keep the current snapshot in memory and persist each fully validated successful snapshot (`version` plus all rows) with `SharedPreferences`, which is already a project dependency. Copy is global rather than user-specific, so logout/session-capability reset must not delete the last-known-good snapshot.
- A 404 means “unavailable for this refresh,” not permanently unsupported: use fallback copy, then retry on the next cold launch or foreground transition. Timeouts and 5xx behave the same way. This endpoint is intentionally not locked out for the whole authenticated session because the backend may be deployed independently while the app remains installed or open.
- Never replace the persistent snapshot with a partial, empty, duplicate-type, malformed, or otherwise invalid response. Keep the previous good snapshot and record the refresh failure.
- **The bundled maps are not deleted — they are consolidated and demoted to emergency bootstrap fallback.** Resolution order for every string:
  1. current in-memory backend snapshot value, when present and non-empty
  2. persisted last-known-good backend snapshot value
  3. bundled emergency value
  4. the raw enum string (existing final fallback)
- This is the same backend-authoritative-with-bundled-fallback shape already used for upgrade costs (`race_detail_screen.dart:1931-1951`, `_parseCostTable:262-276`). Follow it deliberately.
- Consolidate the seven duplicated maps into **one** Dart source (`lib/constants/powerup_copy.dart`) that implements the resolution order above. Every call site in §9.4 reads from it. This is what makes the migration a single seam rather than seven.
- An offline returning user sees the persisted backend snapshot. A brand-new offline install, first paint before any successful fetch, and a new client against an old backend use bundled emergency copy — never an empty string or a raw enum name for a known type.

### 9.5.5 Compatibility

- **Old clients:** entirely unaffected. They never call `/powerups/catalog` and keep rendering bundled strings. The shop response shape is unchanged.
- **New client, old backend:** 404 → persisted last-known-good copy when available, otherwise bundled emergency copy; retry on the next launch/foreground refresh. Fully functional.
- **New client, new backend:** backend copy wins and is persisted; a copy fix appears on the next app launch/foreground refresh without an App Store or Play Store release.
- No enum, table, or column is removed. `PowerupShopItem.name` and `.description` are retained and simply unread by the new backend implementation.

### 9.5.6 Scope note

This is a deliberate expansion beyond the originally approved batch, accepted on the grounds that the batch already touches all seven duplicated maps for Hitchhike and Quick Rinse. Dynamic copy begins with the carrying release; frozen binaries continue using their existing bundled strings. Capability-versioned Leech behavior (§7.5) ensures those frozen binaries also retain the duration their copy describes.

## 10. Notifications status

No implementation change is required for this item.

### Daily reward reminders

- Production runs the scheduler at 5 PM and 9 PM in the user's recorded IANA timezone.
- A reminder is suppressed when the daily reward has already been claimed, the user preference is disabled, no valid device token exists, or that user/slot/day has already been claimed for delivery.
- The payload routes to the daily reward screen.

### Race-ending reminders

- Production evaluates timed races on the placement-recompute cadence and sends once when approximately two hours remain.
- Only races whose total duration exceeds two hours qualify.
- Open-ended races and finished/forfeited participants are excluded.
- The payload routes to race detail.

### Verified production state

- Backend revision: `6fae32e`.
- `DAILY_REWARD_REMINDERS_DISABLED`: unset.
- `RACE_ENDING_REMINDER_DISABLED`: unset.

Keep existing reminder routing and backend job tests green.

## 11. Backward compatibility and rollout

1. Backend agent pins the contracts above before frontend implementation begins.
2. Write backend tests first, then add the enum migration, behavior, serializers, catalog rows, and gates.
3. Run unit tests, then integration tests only against the dedicated local integration database.
4. Deploy to staging with the new catalog entries still `testOnly:true`; never point tests or catalog-apply scripts at production.
5. Frontend agent writes widget/service tests first, adds defensive readers and the new UI, and generates/installs approved artwork.
6. Validate the new app against both the new staging backend and an older backend shape with missing capabilities/fields.
7. Build and verify iOS and Android in lockstep with the same backend URL, version, and build number.
8. Production backend deployment requires explicit in-the-moment approval. Deploy backend and migration before distributing the app.
9. The copy-catalog migration and seed (§9.5) land in the backend deploy before the carrying app is distributed, so `/powerups/catalog` already serves 60-minute Leech copy when `powerups3` clients arrive.
10. Keep Leech, Hitchhike, and Quick Rinse `testOnly:true` and `powerups3`-gated during phased App Store/Play rollout.
11. After the carrying build has rolled out, request separate production approval before changing any catalog row to `testOnly:false`.

Rollback is gate-first: hide the catalog entries or remove `powerups3` visibility without deleting enum values, effects, or user inventory. Existing backend behavior for old clients remains available throughout.

## 12. Test plan

Both agents must add new tests before business logic and must not modify or delete existing tests.

### Backend unit tests

- Tournament summaries retain `myCurrentMatchRaceId` and add correct `myCurrentMatch` inventory.
- Tournament match inventory is bulk-fetched without per-row query growth.
- Pocket Watch with no `targetEffectId` preserves all legacy behavior.
- Targeted Pocket Watch validates source ownership, race, active status, expiry, and allowlisted type.
- Targeted Pocket Watch extends exactly one effect by each tier duration and bypasses Socks/Mirror.
- Pocket Watch remains in the rare tier.
- Hitchhike enforces target rules, one-per-caster, one-per-target, Socks blocking, and no Mirror reflection.
- Hitchhike raw-window calculation excludes all modifier/bonus/copied sources and is deterministic.
- Hitchhike excludes the in-progress hour bucket, and repeated computes across simulated re-upserts of that bucket never decrease the copied total (monotonicity).
- Hitchhike contributes to race score but not box progress (assert `computeBoxEffectiveSteps` is unchanged by an active link).
- Hitchhike copied steps are drainable: a Leech on the caster reduces a total that includes the copy.
- **Hitchhike × Leech ordering:** a race where A hitchhikes B while C leeches A. The Hitchhike term must land in `preLeechTotal` *before* `applyLeechTransfers` runs, at **both** assembly sites; assert live and settlement totals agree. This ordering can be correct in one site and wrong in the other, and would not surface in either powerup's own tests.
- Hitchhike rejects a second link on a target that already has one (`409 HITCHHIKE_TARGET_FULL`).
- Hitchhike stops copying when the target finishes or forfeits mid-window; steps the target walks after exiting are never copied.
- Quick Rinse is blocked while the user is jammed, consistent with Cleanse, and the item is not consumed.
- **Parity guard:** the live assembly (`getRaceProgress.js:659`) and settlement assembly (`raceStateResolution.js:203-212`) produce identical totals for a fixture with an active Hitchhike. This test must fail if the term is added to only one site.
- Cleanse on a live Hitchhike clamps `expiresAt` and preserves already-credited steps; it never reduces the caster's total.
- Quick Rinse halving a live Hitchhike never reduces the caster's already-credited total.
- Enum values are ordered before `mystery_box`.
- The unchanged legacy Leech test still proves a request without `powerups3` creates a 30-minute effect; a new test proves request-scoped `powerups3` creates a 60-minute effect. Ratio, price, and the 2-per-victim stacking guard are unchanged.
- A new test proves sticky per-user capabilities cannot upgrade a request that omitted `powerups3`.
- `powerups3` gating keeps Leech and both new types out of the shop catalog, while `testOnly:true` independently keeps them out of prod-channel requests. Assert both gates; `testOnly` is channel-based, not account-based.
- `GET /powerups/catalog` returns exactly the 28 user-renderable types, includes all drop-only types, excludes `MYSTERY_BOX`, and is not filtered by client features.
- `getPowerupShopCatalog` sources both `name` and `description` from the copy catalog, not `PowerupShopItem`, while preserving the response shape old clients consume.
- Seeded copy matches the pre-migration frontend strings for existing types except the intentional `powerups3` Leech duration update, and includes approved copy for both new types.
- `upgradeTierLabels` has 4 entries for every upgradeable type and is empty for the rest.
- Quick Rinse halves multiple remaining durations, includes Hitchhike, and excludes self/untimed effects.
- Quick Rinse returns `409 NO_TIMED_DEBUFFS` without consuming inventory.
- `powerups3` and `testOnly` gating hide new items from frozen clients.

### Backend integration tests

- Hitchhike display and final settlement agree for the same sample fixture.
- Target steps remain unchanged while caster score receives the copy.
- Two casters hitchhiking two DIFFERENT targets receive independent raw copies with no recursive copying; a second link on an already-linked target is rejected.
- Cleanse truncates Hitchhike immediately; Quick Rinse halves it.
- Race end truncates the scoring window.
- Repeated progress reads never double-credit the caster.
- Tournament active matchup inventory matches the underlying race inventory.

Run:

```bash
npm run test:unit
npm run test:integration
```

The integration command must use only the dedicated `steps-tracker-integration` database.

### Frontend tests

- State pills always render with badges and default to Active.
- Invites render above the pill row and are visible on first paint without interaction; the strip is absent when the invite count is zero.
- The Featured type filter renders in the Featured section header and still scopes only the Featured strip.
- Switching pills does not build the non-selected states' rows (lazy-sliver guard).
- Each state count combines ordinary races and tournaments correctly.
- Tournament invitations, lobbies, between-round waits, live matchups, eliminated entries, champions, and completed brackets map to the correct state.
- Active tournament rows show held powerups, open boxes, queued boxes, masked placement, and countdown.
- Missing tournament match/inventory data renders safely.
- Active tournament tap opens race detail; non-live tournament tap opens bracket detail.
- Pocket Watch capability absent/false exposes only legacy self mode.
- Pocket Watch targeted mode lists only owned eligible effects and selects exactly one.
- Tier price/effect labels and cancellation behave correctly.
- Hitchhike and Quick Rinse render in store/inventory/stash and use the expected target/self flows.
- Unknown new fields/types never crash older-shape fixtures.
- Powerup copy resolves current backend snapshot → persisted last-known-good snapshot → bundled emergency copy → raw enum, in that order, and never renders an empty string.
- Launch/authentication and foreground transitions trigger a non-blocking, coalesced catalog refresh.
- A successful validated response persists across logout and relaunch; malformed/partial responses never overwrite it.
- A 404, timeout, or 5xx from `/powerups/catalog` falls back to persisted or bundled emergency copy and retries on the next launch/foreground refresh; none permanently marks the endpoint unsupported.
- All seven former map call sites read from the single consolidated source.
- Copy renders correctly on first paint before the catalog fetch resolves, on a returning offline launch using persisted copy, and on a brand-new offline launch using emergency copy.
- A type with a null `shortDescription` omits the effect-rail subtitle rather than substituting truncated `description`.
- Existing reminder push routing remains green.

Run:

```bash
flutter analyze
flutter test
```

Then build both platforms using the release instructions in `DEPLOYMENT.md`.

## 13. Acceptance criteria / definition of done

- [ ] `MY BRACKETS` is removed from the personal list without removing Featured tournaments.
- [ ] Invites stay pinned above the pills; Active, Pending, and Completed pills always show combined counts and default to Active.
- [ ] Every personal tournament appears in exactly one actionable state.
- [ ] Live tournament matchup rows show the same box/inventory information as ordinary active races.
- [ ] New frontend builds work safely when `myCurrentMatch` and Pocket Watch capabilities are absent.
- [ ] Legacy Pocket Watch use remains unchanged.
- [ ] Targeted Pocket Watch extends exactly one eligible owned harmful debuff and remains rare.
- [ ] Hitchhike copies only recorded raw target steps for 60 minutes, leaves the target unchanged, and does not advance boxes.
- [ ] Hitchhike stacking (1 per caster, 1 per target), team targeting, Socks, Mirror, Cleanse, and Quick Rinse rules match this spec.
- [ ] Hitchhike stops copying when the target finishes or forfeits mid-window.
- [ ] Hitchhike-copied steps are drainable by a Leech on the caster, ordered identically at both assembly sites.
- [ ] Quick Rinse halves all eligible remaining durations and consumes nothing when none exist.
- [ ] Old clients never receive the new store catalog items, and both rows remain `testOnly:true` in production at the end of this batch.
- [ ] A request advertising `powerups3` to the new backend creates a 60-minute Leech; a legacy request remains 30 minutes; the new binary's emergency fallback is duration-neutral; and every backend/app pairing shows truthful copy.
- [ ] Powerup copy for all 28 user-renderable types is served from the backend catalog, `MYSTERY_BOX` is excluded, persistent and bundled fallbacks remain intact, and the seven duplicated maps are collapsed into one source.
- [ ] A new client against an old backend renders persisted or bundled copy everywhere; production old clients are unaffected, and an older TestFlight client using an already-owned Leech retains its 30-minute behavior.
- [ ] Backend copy changes appear after the next app launch/foreground refresh without requiring a new binary, and invalid responses never replace the last-known-good snapshot.
- [ ] Both icons pass the imagegen critique workflow and render correctly at inventory/store sizes.
- [ ] Backend live display and settlement totals agree.
- [ ] New tests are written first; no existing tests are modified or removed.
- [ ] Backend unit/integration suites, `flutter analyze`, and Flutter tests pass.
- [ ] iOS and Android builds are verified in lockstep.
- [ ] No production deploy or DB/catalog mutation occurs without separate explicit approval.

## 14. Implementation ownership and order

After this approved spec is committed, use exactly two medium-effort `claude-opus-4-8` implementation agents as required by `CLAUDE.md`:

1. **Backend developer:** owns and pins the request/response contract, migration, catalog gating, scoring parity, compatibility behavior, and backend tests.
2. **Frontend developer:** consumes the pinned contract exactly, owns the state-filter/tournament/Pocket Watch/store UX, generates artwork through the approved skill, and verifies iOS and Android.

The backend contract lands first. After it is fixed, both agents may work in parallel. Neither agent may change the contract unilaterally.

## 15. Revision log

### Fresh-eyes pass 1

- Added the Pocket Watch capability flag after identifying that an older backend would silently ignore `targetEffectId` and execute legacy self-buff behavior.
- Preserved `myCurrentMatchRaceId` while adding the nested tournament inventory object.
- Defined action-based tournament state mapping for eliminated and between-round users.
- Required bulk tournament inventory loading to avoid an N+1 regression.
- Added explicit no-consumption validation ordering for targeted Pocket Watch and Quick Rinse.

### Fresh-eyes pass 2

- Required one shared Hitchhike calculation across live display and settlement.
- Excluded recursive copies, modifiers, bonuses, and box progress from Hitchhike scoring.
- Defined the missing-sample behavior as zero until samples arrive rather than estimating from an unsafe whole-day total.
- Defined Quick Rinse behavior for untimed effects and empty eligibility.
- Added `powerups3`, `testOnly`, and old-client effect gating so frozen binaries never depend on new assets or types.
- Added gate-first rollback behavior and separate approval for the post-rollout production catalog flip.

### Fresh-eyes pass 3 — code-verified against the repositories

Every claim in the prior spec was checked against `stepv2-backend` and `stepv2-frontend` at backend rev `6fae32e`. Changes made:

**Corrections to false or unsupported claims**

- The spec's implied 30-minute Hitchhike was incompatible with the shipped monotonicity rule. `LEECH_DURATION_MS` is already 30 min and Leech already excludes the in-progress hour, so a 30-min Hitchhike would credit nothing during its life. Duration raised to 60 min with the reasoning recorded inline.
- "One shared Hitchhike calculation utility" was insufficient. The scoring *assembly line* is duplicated at `getRaceProgress.js:659` and `raceStateResolution.js:203-212`; a shared computation utility does not prevent live/settlement divergence. Added an explicit both-sites requirement and a parity test.
- An earlier draft of this pass claimed Cleanse/Quick Rinse would retroactively reduce the caster's score. **That was wrong and has been retracted.** Because window end is `min(expiresAt, …)` and any shortened `expiresAt` is `>= now`, shortening never claws back closed buckets. The residual real risk — Cleanse implemented as a row *delete* rather than an `expiresAt` clamp — is now called out explicitly.
- "Hitchhike does not advance box progress" needed no special case: `computeBoxEffectiveSteps` is `max(0, baseAdjusted)` and already ignores non-`baseAdjusted` terms. Restated as a structural constraint (never fold into `baseAdjusted`) rather than a behavior to implement.

**Landmines the spec omitted**

- `PowerupType` enum values must be added `BEFORE 'mystery_box'` per the schema's declared ordering.
- `X-Client-Features` is built by a two-branch ternary; `powerups3` must be added to both or ad-less builds lose the feature.
- Powerup name/description maps are duplicated across seven files; all seven are now enumerated.
- Powerup icons need `_thumb` variants (24 of 26 have them); the spec asked for only two PNGs.
- The §4.1 redesign risked regressing the §9.5 lazy-sliver work; explicit perf constraints added.

**Confirmed correct, left unchanged**

- `powerupData.capabilities` genuinely does not exist client-side, so §6.2 is truly additive.
- Socks-blocks / Mirror-does-not-reflect maps cleanly onto `OFFENSIVE_TYPES` + `SHOP_POWERUP_TYPES` with no new branching.
- §5's no-N+1 requirement is achievable via the existing `findEffectsForRaceParticipantsByTypes` bulk helper.
- Production reminder state at rev `6fae32e` is as described.

### Product interview decisions folded in — round 2 (2026-07-20)

- Hitchhike is **60 minutes at 1:1 for 150 coins** (chosen over 2h/300, 2h at 0.5 ratio, and 2h/150).
- Invites are **pinned above the pill row**, not a pill; pills are Active/Pending/Completed only.
- Hitchhike-copied steps **are drainable** by a Leech on the caster.
- The Featured type filter **moves into the Featured section header**.
- `RAINSTORM` stays Pocket-Watch-eligible, extending exactly one rival's row, with per-rival entries in the sheet.
- Both new icons ship **with `_thumb` variants**; backfilling leech/x-ray thumbs is out of scope.
- ~~Production catalog rows go `testOnly:false` immediately, gated only by `powerups3`.~~ **SUPERSEDED by round 3 below — do not implement.** The "manually by the owner, never by an implementation agent" constraint from this decision survives and still applies.

### Product interview decisions — round 3 (2026-07-20)

- **Rollout gating reverted.** The round-2 decision to ship `testOnly:false` in production was withdrawn. Both rows stay `testOnly:true` until the carrying build completes phased rollout, restoring the original double gate (§9.2). The "manually by the owner, never by an agent" constraint on production changes is retained and strengthened.
- **Leech duration raised 30 → 60 min** (§7.5) to match Hitchhike, for the same live-visibility reason. This decision was later refined in round 5 to be capability-versioned rather than global.

### Product interview decisions — round 4 (2026-07-20): backend-served copy

Triggered by the observation that hardcoded client copy is not best practice. Investigation found the architecture was already half-migrated — the shop reads DB copy, in-race surfaces do not — and that the same Leech sentence is stored in both `prisma/seed.js:150` and `race_detail_screen.dart:135-136`. Coverage was also incomplete: only 6 of 27 `PowerupType` values have a shop row.

- **Full migration now** (§9.5), chosen over the recommended smaller option of consolidating the frontend maps and deferring the backend work. Accepted scope increase; the batch already touches all seven maps, so consolidating now avoids extending the duplication.
- **Field scope: all four** — name, description, shortDescription, and `upgradeTierLabels`. Tier labels encode durations and drift for exactly the same reason Leech did; upgrade costs are already backend-driven, so tiers become fully data-driven.
- **The copy catalog is the sole source.** The shop endpoint keeps its response shape but sources `name` and `description` from the catalog; the old `PowerupShopItem` copy columns are retained-but-unread rather than dropped.
- The initial in-memory-only cache decision was later strengthened in round 5 with persistent last-known-good storage and launch/foreground refresh.

### Fresh-eyes pass 4 — open-issue sweep (2026-07-20)

A final sweep for unresolved ambiguity found seven items; all are now closed in the spec.

**Product decisions taken**

- **Hitchhike target limit reduced from 2 to 1** (§7.2). The 2-per-target cap was sized for a 30-minute powerup; at 60 minutes two concurrent 1:1 links mint substantially more against a player who cannot see them coming. Unlike Leech, Hitchhike is not zero-sum, so links compound.
- **Target exit clamps the scoring window** (§7.2, §7.3). Previously unspecified. `StepSample` rows keep accruing after a participant finishes or forfeits, so without a clamp a caster would copy real-world walking done after the target left the race. Mirrors the existing Leech frozen-participant rule.
- **Quick Rinse stays blocked while jammed** (§8.1). Verified that `usePowerup.js:277-292` blocks all powerup use including Cleanse. Documented explicitly because it is counter-intuitive, and marked do-not-bypass so an agent does not "fix" it.

**Contract gaps closed**

- `shortDescription` made **nullable**: `_powerupShortDescriptions` has only 15 entries against 26 for names and descriptions, so a NOT NULL column could not be seeded. Null omits the subtitle rather than substituting truncated text.
- Old-client unexplained score movement (§9.3) recorded as an accepted, deliberate artifact rather than an oversight.
- Hitchhike push copy is generic for every recipient because device tokens do not carry per-build capabilities (§9.3).

**Test coverage added**

- Hitchhike × Leech ordering test (§12), covering the interaction created by the round-2 "copied steps are drainable" decision. The term must enter `preLeechTotal` before `applyLeechTransfers` at both duplicated assembly sites — an ordering error that neither powerup's own tests would catch.

### Product interview decisions — round 5 (2026-07-20): cleanup and dynamic-copy contract

- Leech remains a one-hour product for `powerups3`, but legacy requests remain 30 minutes. This uses request-scoped capability data, not the user's sticky union, preserves frozen behavior, and turns the existing 30-minute test into a compatibility guard rather than modifying it.
- Leech joins Hitchhike and Quick Rinse behind the `powerups3` shop gate and remains `testOnly:true` through rollout.
- The backend is authoritative for name, description, short description, and upgrade-tier labels. The app persists a validated last-known-good snapshot and refreshes non-blockingly on launch/authentication and every foreground transition. Bundled copy is emergency bootstrap only.
- The catalog contains 28 user-renderable types after this batch and explicitly excludes `MYSTERY_BOX`.
- Invites remain pinned above exactly three state pills: Active, Pending, and Completed.
- Hitchhike permits one active link per caster and one per target.
- Generic Hitchhike push copy is used for every build because capabilities cannot be resolved per device token.
- `testOnly` is documented as TestFlight release-channel gating, not an account allowlist.

### Fresh-eyes pass 5 — verification of the round-5 revisions (2026-07-20)

The capability-versioned Leech design was checked against both repositories. It holds, with one correction.

**Verified sound**

- Request-scoped `powerups3` (not the sticky stored union) is the correct capability source. `requireAuth.js:41-70` does persist a union of features on the user, so reading it would silently upgrade a request from a binary that never advertised `powerups3`. The spec's explicit prohibition is well-founded.
- Treating a 404 from `/powerups/catalog` as transient rather than session-permanent is correct, and better than modelling it on `EndpointSupport`. The backend deploys independently of an installed app, so a session-long lockout would strand a client on stale copy for no reason.
- Persisting the copy snapshot across logout is correct — copy is global, not user-scoped.
- Excluding `MYSTERY_BOX` from `PowerupCopy` is correct; it is a container/inventory state with no use-sheet or effect-rail copy.
- The seven-file count is correct; an earlier draft said six by bundling `attack_outcome_modal.dart` and `feed_bubble.dart` into one item.
- Duration-neutral bundled fallback copy is necessary, not merely tidy: a new binary can talk to an old backend (30 min) or a new one (60 min), so hardcoding either number makes the fallback lie in one pairing.
- Preserving `leechPowerup.test.js:152` as the legacy-path guard is strictly better than the previously granted exception. **The round-3 existing-test exception is withdrawn — no existing test may be modified.**

**Corrected**

- The claim "Leech is currently `testOnly`" is **false in the repository** and has been replaced with an explicit, owner-executed prerequisite (§7.5). `testOnly` defaults to `false` (`schema.prisma:535`) and the Leech seed row never sets it (`seed.js:148-156`); its only gate is `powerups2`, which the committed client already advertises. Left unchecked, the `powerups3` catalog-visibility requirement would have removed a purchasable item from live users at backend-deploy time — the first rule of this repository, violated from the backend side.

### Consolidated product decisions

- Tournaments merge by actionable state.
- Invitations are pinned above the personal-list filters. The filters are Active, Pending, and Completed; default Active; Featured is unaffected.
- Pocket Watch selects one owned harmful debuff, bypasses defenses on extension, and cannot extend Hitchhike.
- Hitchhike copies raw physical steps, targets enemies, is visible, permits one active per caster and one per target, costs 150 coins, is blocked by Socks, is not reflected by Mirror, is cleanseable, and does not advance boxes.
- The discounted cleanse is named Quick Rinse, costs 75 coins, and halves all active timed opponent effects.
