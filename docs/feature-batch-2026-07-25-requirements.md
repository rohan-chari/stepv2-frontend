# Feature Batch — 2026-07-25

**Status:** OWNER DECISIONS LOCKED (Phase 3 complete) — awaiting approval to spawn agents (Phase 4)
**Repos:** `stepv2-backend` (API), `stepv2-frontend` (Flutter, iOS + Android)
**App version at time of writing:** `2.0.0` (pubspec). Prod backend `3288eba`.

Ten items: 3 bug fixes, 4 UX/copy fixes, 2 features, 1 investigation-with-answer.
**Item 2 (phone sign-in) is DROPPED by owner decision** — see §2. Nine items ship.

### Owner decisions (locked 2026-07-25)

| D | Decision |
|---|---|
| **D1** | §1 — **Kill `TOURNAMENT_COMPLETED` entirely.** Champion gets `TOURNAMENT_CHAMPION`; everyone else already got one `TOURNAMENT_ELIMINATED` at their own knockout. No runner-up exception. |
| **D2** | §2 — **Phone sign-in DROPPED**, not deferred. Apple + Google remain the only sign-in methods. No follow-up spec. |
| **D3** | §3 — **Fix Uprising's team gate only.** The wider raw-`totalSteps` targeting audit stays a tracked follow-up (§11). |
| **D4** | §7 — **Daily ad-unlock cap = 1 TOTAL**, shared across powerups and cosmetics (not 1 of each). |
| **D5** | §7 — **Flip `POWERUP_UNLOCK_MAX_SHORTFALL` 150 → 20 immediately**, with the deploy. Owner accepts that frozen 2.0.0 clients will watch ads before a 400 (see §7.4 for the exact exposure and the required mitigation). |
| **D6** | §9 — **Show the power chip for default capybara users too** (teaches the Herd Bonus, advertises that characters have powers). |
| **D7** | §9 — **Flip `CHARACTER_POWERS_ENABLED=true` in prod as part of this batch.** This lights up Herd Bonus + Corgi Zoomies + Turtle Shell simultaneously. Its preconditions and guardrails are §9.2 — this is the single largest-blast-radius change in the batch and it gets its own rollout step. |

---

## 1. Summary & user story

| # | Item | Type | Verdict from exploration |
|---|---|---|---|
| 1 | No tournament pushes after you're eliminated | Bug | Confirmed: `TOURNAMENT_COMPLETED` fans out to every non-champion, incl. eliminated |
| 2 | Sign in with phone number | Feature | **Recommend: separate build.** Heavier than it looks — see §2 |
| 3 | Verify Uprising targets the losing *team* in team races | Verify | **Already correct.** But a real input bug found — see §3 |
| 4 | What is the bracket settlement period? ("1m → 0m → soon") | Question + Bug | Answer: **up to 5 min** (raceExpiry cron). Countdown copy is the bug |
| 5 | View chat/activity of other matchups in your bracket | Feature | Spectate is already wired for *standings*; chat + feed still 403 |
| 6 | Dark-mode `x1` owned-pill unreadable in shop | Bug | Confirmed: badge text token flips to near-black at night |
| 7 | Ad-to-buy: extend to cosmetics, drop 150 → 20, once/day, abuse check | Bug + Feature | **Abuse check DONE — no abuse.** See §7.1 |
| 8 | Shop fonts too small | UX | Confirmed sizes 8–14pt |
| 9 | Home-screen notice of your current character power | Feature | New collapsible affordance |
| 10 | Character shop descriptions must include the power (corgi missing) | Bug | Confirmed: **prod DB row is stale**, source JSON is correct |

**User story.** As a player, I want the app to stop pestering me about brackets I'm
out of, to let me follow my bracket-mates' matchups, to read the shop comfortably in
either theme, to understand what my chosen character actually *does*, and I want the
watch-ads-to-buy escape hatch to be a genuine top-up rather than an infinite faucet.

---

## 2. Scope / non-goals

### In scope
Items 1, 3, 4, 5, 6, 7, 8, 9, 10.

### Out of scope (explicit non-goals)

- **Item 2 — phone sign-in: DROPPED (D2).** Not deferred, not tracked as a follow-up.
  Apple and Google remain the only sign-in methods. Rationale, kept on the record so
  the decision can be revisited knowingly:
  - The app already carries `firebase_core` + `firebase_messaging` (`pubspec.yaml:49-50`)
    but **not** `firebase_auth`. Adding Firebase Phone Auth means: a new pod/gradle
    dependency that links into *both* platform builds (the exact class of coupling
    `CLAUDE.md` warns about), APNs auth-key upload for silent-push verification on iOS,
    a reCAPTCHA/Play-Integrity fallback path on Android, and a new App Store /
    Play privacy-disclosure entry for phone numbers.
  - Backend identity is **single-provider per user** by design — `appleId` and
    `googleSub` are two nullable+unique columns with no linking table
    (`prisma/schema.prisma:9-16`). A third provider forces a decision about
    account *linking* (does a phone login find the existing Apple account?) that
    the current schema has no answer for. Getting that wrong duplicates accounts,
    and accounts hold coins.
  - Phone is the cheapest identity to farm at scale, and this app mints coins per
    account (daily reward, referral double-sided reward, onboarding boxes). A phone
    provider without rate limiting is a coin faucet.
  - Real SMS cost per verification, and a new on-call surface when delivery fails.
  - **Estimate had it been built: its own 2-agent build, comparable in size to the
    referral feature.** Owner elected to drop rather than schedule it.
- Rewriting the raw-`totalSteps` targeting convention across *all* powerups (§3 fixes
  Uprising's gate only; the wider audit is noted as a follow-up).
- Any change to the bracket settlement *cadence* itself (§4 changes display only).
- Retroactive clawback for item 7 — none is needed (§7.1).

---

## 3. Item-by-item detail

### §1 — Eliminated players get no further tournament pushes

**Current behaviour (verified).**
`src/modules/tournaments/commands/advanceTournament.js:154-170` — when a champion is
crowned it queues `TOURNAMENT_CHAMPION` to the winner, then loops
`for (const p of allParticipants)` and queues **`TOURNAMENT_COMPLETED` to every other
participant**, with no eliminated check. That is the "X took the crown" push
(`notificationHandlers.js:1283-1296`).

Every other tournament push is already correctly scoped:
- `TOURNAMENT_ROUND_STARTED` is queued per created race, i.e. survivors only
  (`advanceTournament.js:220-233`).
- `TOURNAMENT_MATCHUP_WON` / `TOURNAMENT_ELIMINATED` are per-matchup, to the two
  players in it.
- Race-level pushes (`RACE_STARTED`, race-ending-soon) are already suppressed for
  tournament races via `if (data && data.tournamentId) return;`
  (`notificationHandlers.js:297-300, 406-407`).

So the fix is **one loop**.

**Change.** In `advanceTournament.js`, skip `TOURNAMENT_COMPLETED` for any participant
with `eliminatedInRound != null`. Since every non-champion in a completed bracket is
eliminated, the net effect is: **`TOURNAMENT_COMPLETED` is no longer sent at all.**
Rather than leave dead code, delete the fan-out loop and the
`events.on("TOURNAMENT_COMPLETED")` handler is left in place (harmless, and removing
it is a behaviour change for any other future emitter).

**D1: kill it entirely** — **plus a follow-up correction (owner-confirmed
2026-07-25).**

> **The paragraph that stood here was factually wrong.** It claimed every non-champion
> "already got one `TOURNAMENT_ELIMINATED` at their own knockout" and that D1 removed a
> runner-up `ELIMINATED` + `COMPLETED` double push. Neither is true of the **final's
> loser**: `TOURNAMENT_ELIMINATED` is emitted only on the round *r* → *r+1* transition
> (`advanceTournament.js:209-218`), and the final has no next round. The runner-up's
> **only** end-of-run push was ever `TOURNAMENT_COMPLETED` — so D1 as literally written
> left them with **nothing at all**. Caught during implementation.

**Final behaviour (implemented):** the `TOURNAMENT_COMPLETED` fan-out is deleted, **and**
the champion branch now explicitly emits `TOURNAMENT_ELIMINATED` for the final's loser
(`advanceTournament.js`, champion branch). Net result — and this is the actual intent of
D1 — **every player receives exactly one end-of-run push**: the champion gets
`TOURNAMENT_CHAMPION`; everyone else, including the runner-up, gets exactly one
`TOURNAMENT_ELIMINATED` at their own knockout. Nobody eliminated earlier is told who
eventually won. Pinned by the §9 item 1 integration test.

**Backward compat.** Backend-only. A frozen old client simply receives fewer pushes;
its `tournament_completed` route case goes unused, which is inert. No app change, no
`X-Client-Features` token, no deploy ordering constraint.

---

### §2 — Phone sign-in

**DROPPED (D2).** No work in this batch and no follow-up spec. See §2 of Scope above
for the rationale on the record.

---

### §3 — Uprising in team races: verification result

**Answer to the question as asked: yes, it already works on the losing team only.**
`src/modules/powerups/commands/usePowerup.js:1121-1156`:

```js
if (isTeamRace) {
  // sum totalSteps per team
  if (teamTotals[myTeam] >= teamTotals[otherTeam]) throw "Uprising can only be used by the losing team";
  beneficiaries = acceptedParticipants.filter(p => p.team === myTeam && isAliveTarget(p));
} else {
  // solo race: bottom-half-of-standings gate, bottom half are the beneficiaries
}
```

The bottom-half branch is `else`-only — it never runs in a team race. Beneficiaries are
**every alive member of the caster's team**, not the bottom half of anything. Correct.

**But exploration found a real defect in its *inputs*.** The gate sums
`p.totalSteps`, while the team standings the player is looking at when they decide to
fire come from `getRaceProgress`, which recomputes from `stepTotals`
(`getRaceProgress.js:526-538, 922`). Those two numbers diverge in live play.

> **Root-cause correction (from implementation).** The draft called `p.totalSteps` "the
> raw participant column", implying raw-vs-effective. That is **not** the mechanism:
> all four scoring paths (`getRaceProgress:540`, `raceStateResolution:776`,
> `raceExpiry:295`, `reconcileUploaderRaces:152`) already write the **effective** total
> into `totalSteps`. The real divergence is **staleness** — the board recomputes live at
> request time, whereas the gate read whatever was last persisted. The fix (resolve
> state, then sum with the board's own helper) closes it either way, but the §11
> follow-up audit must chase **staleness**, not a raw-vs-effective mismatch, or it will
> look in the wrong place.

**Failure scenario.** Team A is behind on the board the player sees (effective steps,
because a Rainstorm halved them), but ahead on raw steps. The player taps Uprising and
gets *"Uprising can only be used by the losing team"* — a rejection that contradicts the
screen. The mirror case is worse: a team that is *winning* on the board can fire
Uprising because it trails on raw steps.

**Change.** Compute the team totals in the Uprising gate from the same effective-step
source the standings use, so the gate and the board can never disagree.

**Blast radius warning.** `sortedActiveParticipants` (`usePowerup.js:356-358`) is the
same raw-`totalSteps` sort, and it also backs the **solo** bottom-half gate, Hitchhike's
FRONT/BEHIND targeting, `participantRank`, and `adjacentParticipant`. This spec fixes
**Uprising's team branch only**; widening it to every targeting site is a separate
audit (added to §11 follow-ups) because it changes targeting for a dozen powerups at
once.

**D3: Uprising's team gate only.** The solo bottom-half gate, Hitchhike FRONT/BEHIND,
`participantRank` and `adjacentParticipant` keep their raw-steps behaviour in this
batch; the audit is tracked in §11. The implementing agent must not "helpfully" widen
the fix — changing `sortedActiveParticipants` itself is out of scope and would silently
alter targeting for a dozen powerups.

---

### §4 — Bracket settlement period

**Answer: up to 5 minutes.** There is no "settlement period" constant — it is the
`raceExpiry` cron's tick interval: `INTERVAL = 5 * 60 * 1000`
(`src/modules/races/jobs/raceExpiry.js:425`). When a matchup race's `endsAt` passes,
nothing happens until the next tick, which settles the race
(`completeRace` → `advanceTournament`, `completeRace.js:139`) and, as a backstop for a
crash between settling the last matchup and advancing, `raceExpiry.js:399-410` calls
`advanceTournament` directly. So worst case ≈ 5 minutes + settlement work.

**The "1m → 0m → soon" the owner saw is a display bug**, in
`lib/screens/tournament_detail_screen.dart:862-873`:

```dart
String _countdownShort(DateTime ends) {
  final diff = ends.difference(_now);
  if (diff.isNegative) return 'soon';
  ...
  return '${mn}m';          // 119s -> "1m", 59s -> "0m", 0s -> "0m"
}
```

Three defects, one line each:
1. Under 60s it renders **"0m"** — a countdown that reads zero but hasn't fired.
2. At zero it flips to **"soon"** under the label `ROUND ENDS IN`, so the bar reads
   "ROUND ENDS IN soon" — and it stays there for up to 5 minutes, which is what made
   it look stuck.
3. The timer ticks every second (`:170`) but the smallest unit shown is a minute, so
   59 of every 60 ticks repaint nothing.

**Change.**
- Under 1 minute, show seconds: `45s`, `9s`.
- Once `ends` has passed, swap the whole bar: label `ROUND ENDS IN` → **`SETTLING`**,
  value → **`Results in a few minutes`** (or a compact `…`), and stop the per-second
  timer. This tells the truth: the round is over and the server is catching up.
- The bar already has a refresh tile beside it (`_refreshTile`, `:679`), so the user
  has a manual way to pull the result.

**Backward compat.** Frontend-only, reads no new field. Old builds keep the old copy —
cosmetic only.

---

### §5 — Spectate chat + activity of other matchups in your bracket

**Current state.** More is already built than expected. The bracket UI already routes a
tap on *any* matchup into the race screen —
`tournament_detail_screen.dart:602-605`:

```dart
onTapMyMatchup: _openMatchup,
// Spectate any other matchup — the race screen renders read-only
onTapMatchup: _openMatchup,
```

And the backend already has the exact gate this needs:
`src/modules/tournaments/services/tournamentAccess.js` —
`isTournamentParticipant(tournamentId, userId)`, documented as *"Read-only spectate
gate … INCLUDING eliminated … Used ONLY by the matchup-race READ queries … Never relax
any write path."* It is wired into `getRaceDetails.js:24-30` and
`getRaceProgress.js:204-210`.

**The gap:** it was never wired into the two *feed* queries. So a spectator gets the
standings but their chat/activity panel 403s:
- `src/modules/social/queries/getRaceMessages.js:104-109` — hard
  `race.participants.find(p => p.userId === userId)` → 403.
- `src/modules/races/queries/getRaceFeed.js:15-16` — same 403.

**Change (backend).** Apply the identical relaxation already used by
`getRaceDetails`/`getRaceProgress` to `getRaceMessages` and `getRaceFeed`: if the
requester is not a participant **and** the race has a `tournamentId` **and**
`isTournamentParticipant(race.tournamentId, userId)` → allow **read**. Otherwise keep
the 403 exactly as-is.

Two things must not be relaxed:
- **Writes stay participant-only.** `sendRaceMessage` / `deleteRaceMessage`
  (`src/modules/social/commands/`) are untouched. A spectator POSTing a message must
  still 403.
- **Stealth redaction still applies.** `getRaceMessages:111-133` redacts
  `STEALTH_MODE` participants' names for anyone who isn't the stealthed user. A
  spectator is not the stealthed user, so the existing branch already does the right
  thing — but the test plan pins it, because spectators are a new caller of that code.

**Change (frontend).** `RaceDetailScreen` must render read-only for a spectator: hide
the message composer and any powerup/action affordances. It needs to know it is
spectating — derive it from the participants list already in the details payload
(am-I-in-it), **not** from a new backend field, so the screen degrades correctly
against any backend version.

**Backward compat.** Backend relaxation is additive — no response shape changes, no new
field, no `X-Client-Features` token. Frozen old clients gain the ability to load a
bracket-mate's chat, which is the desired behaviour and matches what their bracket UI
already tries to do (their standings already load today, so this only makes the screen
*less* broken). Deploy backend first; the frontend composer-hiding ships after.

---

### §6 — Dark-mode owned-count pill

**Root cause (exact).** `lib/screens/tabs/shop_tab.dart:1573-1601`, the `_ShopTile`
badge:

```dart
color: highlighted ? pillGold : roofMid,          // fill
border: highlighted ? pillGoldDark : roofDark,
child: Text(badge!, style: PixelText.title(size: 8,
  color: highlighted ? textDark : parchment)),    // <-- the bug
```

In the night palette (`lib/styles.dart:329-405`):

| token | light | night |
|---|---|---|
| `roofMid` (fill) | `0xFF2E5D47` | `0xFF214637` (dark green) |
| `roofDark` (border) | — | `0xFF142A25` (near black) |
| `parchment` (**text**) | `0xFFFFFBF5` cream | **`0xFF1B2A34` near-black navy** |

`parchment` is the *surface* token; it flips dark at night by design. Using it as a
**text** color paints near-black text on a dark-green pill — exactly the screenshot.
This is the same night-flip trap logged for `ink`/`pillGold` in the 2026-07-23 batch.

**Change.** Use `textLight` for the badge text — `0xFFFFFBF5` in light,
`0xFFF7F1E7` in night, i.e. cream in **both**, which is what the light-mode design
already intended. Fill/border stay `roofMid`/`roofDark` (dark green + black outline is
on-brand and cream-on-`roofMid` clears contrast in both themes).

The `highlighted` branch (`pillGold` fill + `textDark` text) is **already correct** —
`textDark` flips to cream at night over the violet night `pillGold`. Do not touch it.

**Audit obligation.** `parchment`-as-text-color is a class of bug, not one site. The
implementing agent must grep the whole `lib/` tree for `color: AppColors.of(context).parchment`
inside a `TextStyle`/`PixelText`/`HomeText` and fix every hit found, listing them in
the PR. (Same for `parchmentLight`.)

**Backward compat.** Frontend-only, no API.

---

### §7 — Ad-to-buy: abuse check, cosmetics, 150 → 20, once/day

#### §7.1 — Abuse check: **clean, no action needed**

Read-only prod query (`ad_reward_grants`, `powerup_purchase_requests`,
`coin_transactions`), run 2026-07-25:

```
reward_kind      | count | consumed | first                   | last
extra_daily_spin |    69 |       67 | 2026-07-07 13:49:53     | 2026-07-25 06:39:11
coin_reward      |    55 |       54 | 2026-07-08 03:14:27     | 2026-07-25 04:58:25
powerup_unlock   |     2 |        2 | 2026-07-25 04:30:20     | 2026-07-25 04:30:36
```

Both `powerup_unlock` grants belong to **Rohan**, both for `POWERUP_LEECH`, consumed at
the same instant — one unlock, two ads. The matching ledger row is the only
`powerup_unlock_ads` transaction in prod: `Rohan, -244 coins, 2026-07-25 04:30:38`
(244 coins spent toward a 300-coin Leech). **Nobody but the owner used it, and it was a
single self-test. No clawback, no repair.**

#### §7.2 — The abuse vector is real, though

`POWERUP_UNLOCK_REWARD_KIND` is a **distinct** `rewardKind` from `coin_reward`
(`adRewards.js:65-71`), so `AD_COIN_REWARD_DAILY_CAP` (3/day) **does not apply to it**.
`unlockPowerupWithAds.js` has an idempotency key, a shortfall gate, and an SSV-verified
watch check — but **no per-day limit of any kind**. A user at 0 coins could watch 3 ads,
take a 150-coin powerup, and repeat all day. The owner's read is correct.

#### §7.3 — Changes

1. **`POWERUP_UNLOCK_MAX_SHORTFALL: 150 → 20.** `adRewards.js:82`. With
   `POWERUP_UNLOCK_COINS_PER_AD = 50`, `adsNeededFor(≤20)` is always **1**, so the flow
   collapses to a single-ad top-up — which is the intent ("you're *just* short"). Make
   the constant env-overridable via the existing `positiveIntEnv` helper
   (`POWERUP_UNLOCK_MAX_SHORTFALL`) so it can be tuned without an App Store cycle,
   following the `AD_COIN_REWARD_AMOUNT` precedent.
2. **Once per local day.** New env-tunable `POWERUP_UNLOCK_DAILY_CAP` (default **1**).
   Enforced **inside the same transaction** as the unlock, counting *consumed*
   `powerup_unlock` grants for that user for that local day. The existing
   `grantedDate` column already carries the local date and `claimAdCoinReward.js:33-47`
   is the pattern to mirror. New error code `DAILY_CAP_REACHED`, HTTP **409**, message
   *"You've already used your daily ad unlock — come back tomorrow."*
   - The `localDate` must be **client-supplied and server-validated** the same way
     `claimAdCoinReward` does it (`isValidLocalDate` + `withinOneDayOfServer`) — a
     server-UTC day would let a user in a late timezone unlock twice around midnight,
     and would silently break the existing 3/day coin cap's semantics if we used a
     different notion of "day" for the two.
   - **Old-client trap:** frozen 1.7.x/2.0.0 clients call `unlockPowerupWithAds`
     **without** a `localDate` (see the request shape in
     `backend_api_service.dart`). The backend must therefore accept a missing
     `localDate` and fall back to the server's date rather than 400 — otherwise every
     shipped binary's unlock button breaks the moment the backend deploys. This is the
     #1 rule in `CLAUDE.md` and it is the single most likely way to get this item wrong.
3. **Extend to accessories + characters.** Today the flow is powerup-only:
   `unlockPowerupWithAds` reads `powerupShopItem` and grants into `userPowerupItem`.
   Cosmetics live in a different table (`shop_items` / `user_shop_items`) with their own
   purchase command (`src/modules/cosmetics/purchaseShopItem.js`) and their own
   idempotency table (`shop_purchase_requests`).
   **Approach: a sibling endpoint, not a generalized one.** Add
   `POST /shop/unlock-with-ads` mirroring the powerup endpoint's exact shape and
   safety properties against the cosmetics tables. Reasons: the two paths have
   different item tables, different grant tables, different idempotency tables and
   different `testOnly` semantics; a single polymorphic command would need branches at
   every one of those points and would put the coin-zeroing debit behind a
   type-switch. Two small, near-identical commands are safer than one branchy one.
   - Same SSV `custom_data` convention, distinct prefix: `shop_unlock:<userId>:<sku>`,
     stamped with a new `rewardKind = "shop_unlock"`.
   - **The daily cap is shared across both flows** — one ad-unlock per day *total*,
     not one powerup + one cosmetic. Counted over
     `rewardKind IN ('powerup_unlock','shop_unlock')`.
   - `testOnly` filtering must be applied identically (`testOnlyFilter(channel)`), so a
     `testOnly` cosmetic can't be ad-unlocked by a prod client.

**D4: 1 total across powerups + cosmetics**, exactly as specced above.

#### §7.4 — Backward compat (this item is the risky one)

The shortfall drop from 150 → 20 is a **server-side tightening that frozen clients
don't know about**. `shop_tab.dart:120` hardcodes `_maxAdUnlockShortfall = 150` and
computes `adsNeeded` locally. A 2.0.0 user who is 90 coins short will still see
**"Watch 2 ads"**, watch both, and then get a 400 `SHORTFALL_TOO_LARGE` with
*"Too many coins short — get more coins first"* — **after** sitting through two ads.
That is a bad, and entirely foreseeable, experience.

**D5: flip immediately.** Owner accepts the old-client exposure. Recording the exact
exposure so it is a known cost rather than a surprise:

- **Who is affected:** any user on 2.0.0 or earlier whose shortfall is **21–150 coins**.
  Below 21 the old and new clients agree. At/above 151 the old client already routes to
  Get-coins.
- **What they see:** the tile offers "Watch 1/2/3 ads", they sit through them, and the
  unlock call returns 400 `SHORTFALL_TOO_LARGE` → toast *"Too many coins short — get
  more coins first"* (`shop_tab.dart:1141-1142` surfaces `error.message` directly).
  **No coins are lost and no ad grant is consumed** — the shortfall gate runs before any
  consume/debit (`unlockPowerupWithAds.js:78-92`), so the failure is wasted time only.
- **How long:** until 2.1.0 completes its ~1-week phased rollout, and indefinitely for
  users who never update.

**Two mitigations are mandatory given the flip is immediate:**

1. **Serve the threshold anyway** (§4.3 `adUnlock` block). This is what makes 2.1.0
   correct on day one and lets the number be tuned later without another App Store
   cycle. Not optional just because the flip isn't gated.
2. **Improve the error copy for this specific case.** Since old clients render
   `error.message` verbatim, the 400 `SHORTFALL_TOO_LARGE` message is the *only* thing
   those users will see after watching ads. Change it from the current
   *"Too many coins short — get more coins first"* to something that explains the
   change and doesn't read as a bug — e.g. **"Ad unlocks now only cover the last 20
   coins. Update the app for the latest rules."** This is a one-line change that
   materially softens the accepted exposure.

The daily cap (`POWERUP_UNLOCK_DAILY_CAP = 1`) ships in the same deploy and is
**not** exposed to this problem: it fails *before* the first ad of the second unlock,
and its 409 message renders fine on every client.

---

### §8 — Bigger shop fonts

Current type scale in `lib/screens/tabs/shop_tab.dart`:

| element | current | proposed | note |
|---|---|---|---|
| tile owned/EQUIPPED badge | `PixelText.title(8)` | **10** | `:1592` — 8pt pixel type is barely legible |
| tile name | `PixelText.title(11)` | **13** | `:1618` — inside a fixed `height: 34` box, 2 lines max |
| tile action strip | `PixelText.title(12)` | **13** | `:1658` — inside a fixed `height: 30` strip |
| sheet chip | `PixelText.title(10)` | **11** | `:1653`-ish `_sheetChip` |
| sheet description | `PixelText.body(14)` | **15** | `:733` |
| sheet title | `PixelText.title(20)` | 20 (unchanged) | already fine |

**Hard constraint:** the tile has two fixed-height boxes (`height: 34` name,
`height: 30` strip) and a `maxLines: 2` + `TextOverflow.ellipsis` name. Raising the
name to 13pt without raising the box will silently start ellipsising two-word names.
The implementing agent must raise the name box to ~`38` and the strip to ~`34`, then
**verify on the narrowest supported width** that long names ("Compression Socks",
"Signal Jammer", "Ghost Pepper") still render two lines un-ellipsised. Load the
`mobile-design` skill before touching this.

> **Correction from implementation (Pass 4).** The constraint above is
> **unachievable as written**, and was already failing before this batch. The grid is
> `crossAxisCount: 4`, so a tile is 67.5dp wide at 320dp. Measured against the real
> pixel font, "Compression" alone is 121px at **11pt** — it has never fit at any
> supported width, at the *current* size. A flat 13pt would additionally have
> *regressed* "Ghost Pepper" and "Signal Jammer", which do fit today at 11pt on a
> 390dp phone. Raising the box height does not address this.
>
> **As built:** a `_FittedTileName` widget — nominal **13pt**, stepping down through
> 12/11/10/9 only as far as a given tile requires. Short names get the full 13pt;
> long names render **whole instead of ellipsised**; nothing renders smaller than it
> does today. This satisfies the owner's actual ask (bigger, more readable) without
> the impossible guarantee.
>
> **Follow-up (out of scope):** names like "Spinning Basketball" really want a
> **3-column grid**. Separately, the action-strip label "Watch 3 ads" is 143px in a
> 68–85px tile and has always ellipsised — pre-existing, untouched.

**Backward compat.** Frontend-only.

---

### §9 — Home-screen character-power notice

**Context.** Three characters exist, each with a power
(`src/modules/races/services/characterPowers.js`):

| character | power | detail |
|---|---|---|
| capybara (default, incl. no CHARACTER cosmetic) | **Herd Bonus** | `100 × (capybaras in race, cap 10)` bonus steps per race-local day, capped 1,000/day |
| `corgi_puppy` | **Zoomies** | two secret 10-min 3× windows per user-local day |
| `turtle` | **Shell** | 30% chance to bounce any box-rollable incoming attack |

The home tab already knows the equipped character: `equippedAnimal`
(`lib/screens/tabs/home_tab.dart:53, 833`), and the sprite table
`lib/config/animals.dart` already maps `null`/unknown → capybara.

**Change.** A collapsed, tappable **power chip** on the home screen, expanding in place
to a short panel with the power's name + one-line effect. Requirements:
- Collapsed by default (owner: *"it should be hidden and a click to open kind of thing"*).
- Expand/collapse is **animated**, in the app's existing motion language — not a
  `showDialog`. It sits with the capy hero, so it reads as "this is *my* capy's power".
- Remembers its expanded state for the session only (no persistence, no new API).
- Load the **`mobile-design`** and **`frontend-design`** skills before building it, per
  the standing UI rule.

**D6: the chip shows for capybara users too** — i.e. for every user, since a user with
no CHARACTER cosmetic *is* a capybara by definition (`characterPowers.js:48-53`).

**The compat landmine.** Character powers are behind a **server-side** env gate,
`CHARACTER_POWERS_ENABLED`, read at call time (`characterPowers.js:25`). Even though
D7 flips it on, the app must **never** hardcode the assumption: the flag is a kill
switch, and if it is flipped back off the chip must disappear on its own.

**Therefore:** the backend exposes the flag additively (a `characterPowersEnabled`
boolean, §4.4) and the chip renders **only when the field is present and `true`**. A
missing field (older backend) → chip hidden. That is the default-safe read `CLAUDE.md`
requires, and it doubles as the kill-switch response.

**Copy must match reality**, and reality is env-tunable — the herd-bonus numbers come
from balance config. Keep the copy qualitative ("a step bonus for every capybara in
your race") rather than restating tunable constants the app would then render stale.

#### §9.2 — Flipping `CHARACTER_POWERS_ENABLED=true` (D7)

**This is the largest-blast-radius change in the batch** and it is the one thing here
that alters live scoring. It gets its own rollout step and its own watch.

**Preconditions — all verified as already met:**
- ✅ **The herd-bonus race-feed line is implemented and already in prod code**
  (`src/modules/races/jobs/characterEffectScheduler.js:167-255`, `HERD_BONUS` event
  type, shipped in backend `0956cc3`, currently inert behind the flag). This was the
  stated precondition for flipping the flag: feed lines are **server-rendered strings**,
  so every client ever shipped will see an explanation for its inflated step total.
  Without it, frozen binaries would just see numbers change with no reason given.
- ✅ Turtle and Corgi remain `testOnly: true` in prod, so only TestFlight builds can
  equip them. Their art shipping is **not** a precondition for this flip.
- ✅ Kill switches exist and are read at call time: `CHARACTER_POWERS_ENABLED` (all
  three powers), `TURTLE_SHELL_DISABLED` (Shell only), `ZOOMIES_PUSH_DISABLED`
  (Zoomies push only). All reversible with no redeploy.

**What actually changes at the flip:**
| power | who it touches |
|---|---|
| **Herd Bonus** | **every capybara in every active race — i.e. essentially the entire user base.** `bonusSteps` gains `100 × (capybaras in race, cap 10)` per race-local day, capped 1,000/day |
| **Corgi Zoomies** | TestFlight corgi owners only (two secret 10-min 3× windows/day) |
| **Turtle Shell** | TestFlight turtle owners only (30% block on box-rollable attacks) |

**Required guardrails on the flip:**
- Flip it **last**, after the rest of the backend deploy is verified healthy — not in
  the same motion.
- **Watch the first settlement after the flip.** Herd bonus changes `bonusSteps` for
  every capybara in every active race; a mid-race flip means races that started under
  the old scoring finish under the new one. That is accepted, but it must be observed
  rather than assumed.
- Confirm the `HERD_BONUS` feed line actually appears in a real race feed after the
  first cron tick. If it does not, **flip back immediately** — silent step inflation
  with no explanation is the exact UX failure this line exists to prevent.
- Per the standing rule, box progress must remain **raw `baseAdjusted` only**: the herd
  bonus is part of `bonusSteps` and is explicitly never minted as rows and never folded
  into box progress (`raceStateResolution.js:162`). Pin this with a test (§9, test 18).

**Backward compat.** The new field is additive; frontend hides on absence. The flip
itself is invisible to old clients except through the server-rendered feed line, which
is the intended channel. Deploy backend first. iOS + Android identical.

---

### §10 — Character descriptions must include the power

**Root cause (verified against prod).** The source of truth is correct; the **prod row
is stale**.

`stepv2-backend/data/cosmetics.json`:
```
corgi_puppy | Trade your capybara for a stubby-legged speedster. Zoomies: 3x steps for 10 minutes, twice a day!
turtle      | Slow and steady — and armored. Shell: 30% chance to bounce off any attack a rival throws your way.
```

Prod `shop_items` (read-only query, 2026-07-25):
```
corgi_puppy | Trade your capybara for a stubby-legged speedster.        <-- Zoomies line MISSING
turtle      | Slow and steady — and armored. Shell: 30% chance to ...   <-- correct
```

The corgi row predates the Zoomies copy and was never re-applied. The turtle row is
correct because it was seeded *after* its description was written. Both rows are
`test_only = t, active = t`.

**Change.**
1. Apply the current `data/cosmetics.json` descriptions to prod — via the sanctioned
   path, **not** hand-written SQL. Note the two standing traps: the deploy-time seed's
   clobber semantics (the "Leech price 300" lesson) and the prod checkout's
   uncommitted `data/cosmetics.json` tuning drift that blocks `git pull` — the drift
   must be stashed and the DB treated as source of truth for `renderMetadata`, while
   `description` comes from the repo.
2. **Add a guard so this can't silently recur:** a test asserting every `CHARACTER`-slot
   entry in `data/cosmetics.json` names its power. Structural source guards are the
   sanctioned unit-test case in `CLAUDE.md`.
3. Confirm the shop sheet renders the full description — it does
   (`shop_tab.dart:729-740`, `PixelText.body(14)`, no `maxLines`), and §8 bumps it to
   15pt.

**Backward compat.** Pure data. Every app version reads `description` off the API, so
all clients get the fix at once with no release. **This item can ship first, on its
own.**

---

## 4. API contract

Pinned **before** either agent implements. The frontend agent must not invent fields.

### 4.1 `POST /shop/powerups/unlock-with-ads` (existing — modified)

> **Corrected 2026-07-25 (Pass 4).** The draft wrote this path as
> `POST /powerups/shop/:sku/unlock-with-ads`, which does not exist. The real,
> shipped route is `POST /shop/powerups/unlock-with-ads` with the **sku in the
> body** (`src/routes/shop.js:131`). The path must NOT change — every shipped
> binary calls it. Verified against both repos after implementation.

Request (`sku` existing; `localDate` additive and **optional**):
```json
{ "sku": "POWERUP_LEECH", "idempotencyKey": "...", "localDate": "2026-07-25" }
```
Headers: `Idempotency-Key` (existing, required).

`localDate` is **optional**. Omitted (every currently-shipped client) → the server
falls back to its own date. Present and malformed → **400** (matching
`claimAdCoinReward` validation). Present and >1 day from server time → **400**.

Success **200** (unchanged shape, two additive fields):
```json
{
  "coins": 0,
  "adsWatched": 1,
  "inventory": { "powerupType": "LEECH", "quantity": 2 },
  "item": { "sku": "POWERUP_LEECH", "name": "Leech", "priceCoins": 300, "powerupType": "LEECH" },
  "idempotent": false,
  "adUnlockRemainingToday": 0,
  "adUnlockDailyCap": 1
}
```

Errors (existing codes unchanged; one new):
| status | code | when |
|---|---|---|
| 400 | `ALREADY_AFFORDABLE` | shortfall ≤ 0 |
| 400 | `SHORTFALL_TOO_LARGE` | shortfall > `POWERUP_UNLOCK_MAX_SHORTFALL` |
| 409 | `AD_NOT_VERIFIED` | fewer verified unconsumed watches than needed |
| 409 | `AD_ALREADY_SPENT` | watches consumed by a concurrent unlock |
| **409** | **`DAILY_CAP_REACHED`** | **new** — daily ad-unlock already used |
| 404 | — | sku not found / inactive / testOnly-filtered |

### 4.2 `POST /shop/:sku/unlock-with-ads` (**new**)

> Implemented at **both** `/shop/:sku/unlock-with-ads` (sku in path) and
> `/shop/unlock-with-ads` (sku in body), sharing one handler
> (`src/routes/shop.js:218-219`), so it mirrors the powerup route's body-style
> convention as well. Registration order matters: `/powerups/unlock-with-ads` is
> registered first (`:131`), so it is never shadowed by `/:sku/...`.

Same request shape, same headers, same error table. Success:
```json
{
  "coins": 0,
  "adsWatched": 1,
  "item": { "sku": "corgi_puppy", "name": "Corgi Puppy", "priceCoins": 400, "slot": "CHARACTER" },
  "owned": true,
  "idempotent": false,
  "adUnlockRemainingToday": 0,
  "adUnlockDailyCap": 1
}
```
SSV `custom_data`: `shop_unlock:<userId>:<sku>`; grants stamped
`rewardKind = "shop_unlock"`, `shopItemId = <sku>`.
A **404** here is the frozen-old-client signal — clients treat it as "feature absent"
and fall back to the Get-coins route, following the existing session-scoped
capability-cache convention (`backend_api_service.dart`, "only a 404 flips one to
`unsupported`").

### 4.3 Shop catalog response (additive fields)

On the existing shop/powerup-store catalog payload:
```json
{
  "adUnlock": {
    "maxShortfall": 20,
    "coinsPerAd": 50,
    "maxAds": 3,
    "dailyCap": 1,
    "remainingToday": 1
  }
}
```
Clients that don't understand `adUnlock` ignore it and keep their compiled-in 150.
New clients render **entirely** from it and must not fall back to a local constant when
the block is present.

### 4.4 Home/session payload (additive field)

```json
{ "characterPowersEnabled": false }
```
Mirrors `process.env.CHARACTER_POWERS_ENABLED === "true"`, read per request.
Absent → clients treat as `false` (hide the §9 chip).

> **As built:** served on `GET /home/race-card` (`src/modules/home/routes.js:62`)
> and on the session/`me` payload (`src/modules/users/routes.js:305`). The client
> reads it from the home race-card batch and accepts an explicit `true` from
> either source. Verified consistent across both repos after implementation.

### 4.5 Read relaxations (no shape change)

`GET` race messages and `GET` race feed accept a tournament-sibling spectator. No new
request or response fields; the only observable change is 403 → 200 for that caller.
Write endpoints unchanged.

### 4.6 Push changes (no shape change)

`TOURNAMENT_COMPLETED` is no longer emitted (pending Q1). No payload/route changes;
the client's route case becomes unused, which is inert on every version.

---

## 5. Data model / migrations

**No schema migration is required.** Everything reuses existing columns:

- `ad_reward_grants` already has `reward_kind`, `granted_date`, `shop_item_id`,
  `consumed_at`, `reward_type`, `powerup_type`. The new `shop_unlock` kind is a new
  **value**, not a new column. `reward_type` for a cosmetic unlock is `"COSMETIC"` —
  confirm the column is a free-text/enum that admits it; **if it is a Prisma enum, that
  is the one migration in this batch** and the backend agent must add the value with a
  default-safe read (old rows unaffected).
- `shop_purchase_requests` already exists for cosmetic idempotency; the new endpoint
  reuses it exactly as `purchaseShopItem` does.
- `tournament_participants.eliminated_in_round` already exists (§1 reads it).
- No backfill. No default changes.

**Data change (not a migration):** the corgi `description` in prod (§10).

---

## 6. Frontend plan

All items ship **iOS + Android in lockstep** from the same Dart. Load `mobile-design`
+ `frontend-design` before any UI work (§6, §8, §9 are all UI).

| item | files | states |
|---|---|---|
| 4 | `lib/screens/tournament_detail_screen.dart` (`_countdownShort`, `_countdownBar`, timer at `:170`) | live (`2d 3h` / `4h 12m` / `45s`) → settling (`SETTLING · Results in a few minutes`, timer stopped) |
| 5 | `lib/screens/race_detail_screen.dart` | spectator: feed + chat render read-only, composer hidden, action affordances hidden. Loading / empty / 403-fallback all covered |
| 6 | `lib/screens/tabs/shop_tab.dart:1592` + repo-wide `parchment`-as-text audit | light + dark both verified |
| 7 | `lib/screens/tabs/shop_tab.dart` (`_maxAdUnlockShortfall`, `_storePowerupTile`, `_powerupSheetAction`, new cosmetic equivalents), `lib/services/backend_api_service.dart` | affordable / ad-unlockable / cap-reached (strip reads `Get coins`, sheet explains) / endpoint-absent (404 → Get coins) |
| 8 | `lib/screens/tabs/shop_tab.dart` type scale + the two fixed-height boxes | verified at narrowest supported width, long names un-ellipsised |
| 9 | `lib/screens/tabs/home_tab.dart` + new widget | collapsed (default) / expanded / **hidden** when `characterPowersEnabled` is absent or false |

**Degrade-safely rules for this batch (all mandatory):**
- §7 — if `adUnlock` is absent from the catalog, keep today's behaviour. If
  `remainingToday == 0`, don't offer the ad button at all (fail before the ad, never
  after).
- §7 — a `404` on `/shop/:sku/unlock-with-ads` caches `unsupported` for the session and
  routes to Get-coins. Never a crash, never a retry loop.
- §9 — chip hidden unless `characterPowersEnabled == true`.
- §5 — spectator-ness is derived from the participants list already in the payload,
  never from a new field.
- §4 — pure client-side date math, no new field.

---

## 7. Backward-compat & rollout

**Deploy order: backend first, then app.** Never the reverse.

| # | ships | old frozen client hitting the new backend |
|---|---|---|
| 10 | **data only, first, alone** | gets the corrected description immediately. No risk. |
| 1 | backend | receives one fewer push. Inert. |
| 5 | backend, then app | **gains** working spectate chat. Its composer is still visible though — a spectator's send will 403 with a toast. Acceptable; the app fix removes it. |
| 3 | backend | Uprising gate matches the board. No shape change. |
| 7 — daily cap | backend, **immediately** | second unlock in a day 409s *before* any ad is watched. Message renders correctly. |
| 7 — 150 → 20 | backend, **flipped immediately (D5)** | a user 21–150 short watches ads, then 400s. **No coins or grants lost.** Softened by the new error copy (§7.4). Ends when 2.1.0 rolls out. |
| 7 — cosmetic endpoint | backend, then app | old client never calls it (404 → Get coins). Inert. |
| 9 — chip field | backend field, then app | old client ignores the field. Inert. |
| 9 — **powers flag ON (D7)** | backend, **flipped last, after the deploy is verified** | every capybara's `bonusSteps` changes mid-race. Explained to **all** client versions by the server-rendered `HERD_BONUS` feed line. Reversible in one env flip. |
| 4, 6, 8 | app only | no backend involvement. |

**Env/config checklist for the backend deploy (in order):**
1. `POWERUP_UNLOCK_DAILY_CAP` = **1**.
2. `POWERUP_UNLOCK_MAX_SHORTFALL` = **20** (D5 — flipped immediately, not held).
3. Deploy, verify healthy.
4. **Then, as a separate step:** `CHARACTER_POWERS_ENABLED` = **true** (D7), followed by
   the §9.2 watch — confirm the `HERD_BONUS` feed line appears and observe the first
   settlement.
5. Unchanged: `TURTLE_SHELL_DISABLED` (unset), `ZOOMIES_PUSH_DISABLED` (unset),
   `testOnly` stays `true` on turtle + corgi.

**Kill switches — every new behaviour is env-reversible with no redeploy:**
`POWERUP_UNLOCK_DAILY_CAP` (raise to disable the cap), `POWERUP_UNLOCK_MAX_SHORTFALL`
(restore 150), `CHARACTER_POWERS_ENABLED` (all three character powers, and the §9 chip
along with them), `TURTLE_SHELL_DISABLED`, `ZOOMIES_PUSH_DISABLED`.

---

## 8. Open questions

**None.** All six were resolved in the Phase 3 interview; the answers are recorded as
D1–D7 at the top of this document and folded into the relevant sections. Two of them
(D5, D7) overrode a recommendation in the draft — both are annotated in place with the
exposure the owner accepted, so neither reads as an oversight later.

---

## 9. Test plan (tests FIRST, before business logic)

Integration tests by default (`CLAUDE.md`). Backend: `test/integration/`, real HTTP,
real handler chain, **test DB only — never prod**. Frontend: pump the real widget.
Neither agent may modify or delete an existing test; surface it to the owner instead.

### Backend (`test:integration` unless noted)
1. **§1** — 4-bracket run to completion: champion receives `TOURNAMENT_CHAMPION`;
   **no** eliminated participant receives `TOURNAMENT_COMPLETED`. Assert on the
   notifications actually recorded, not on a handler's return.
2. **§3** — team race where raw and effective steps **disagree** (apply a debuff to the
   raw-leader). Assert the losing team by the *board* can fire Uprising and the winning
   team cannot. Plus: beneficiaries are every alive member of the caster's team, and
   **never** anyone on the other team, at 1v1 through 5v5.
3. **§5** — eliminated bracket participant `GET`s a sibling matchup's messages **and**
   feed → 200. A user in **no** relation to the tournament → 403. A spectator **POSTing**
   a message → 403. A stealthed participant's name is redacted for the spectator.
4. **§7 cap** — two unlocks same local day → second is 409 `DAILY_CAP_REACHED`,
   and **no coins were debited and no ad grant consumed** on the failed call.
5. **§7 cap crosses flows** — powerup unlock then cosmetic unlock same day → second
   409s (per D4: one total, not one of each).
6. **§7 old-client compat** — request with **no** `localDate` succeeds (this is the
   regression that would break every shipped binary).
7. **§7 shortfall** — with `MAX_SHORTFALL=20`: 15 short → 1 ad, succeeds; 90 short →
   400 `SHORTFALL_TOO_LARGE` with **no** grant consumed.
8. **§7 cosmetics** — cosmetic unlock grants into `user_shop_items`, zeroes coins,
   writes the ledger row, is idempotent on retry with the same key, and a `testOnly`
   cosmetic is **not** unlockable on the prod channel.
9. **§7 catalog** — the `adUnlock` block is present and reflects the env values.
10. **§9** — `characterPowersEnabled` reflects the env var both ways.
11. **§10** (unit, structural guard — sanctioned) — every `CHARACTER` entry in
    `data/cosmetics.json` mentions its power.
18. **§9.2 (D7 flip safety)** — with `CHARACTER_POWERS_ENABLED=true`: a race with N
    capybaras credits the herd bonus into `bonusSteps`, emits exactly **one**
    `HERD_BONUS` feed line per participant per race-local day, and **box progress is
    unchanged** (raw `baseAdjusted` only — the bonus must never move a box). This is
    the test that protects the flip; it is not optional.
19. **§7.4** — the 400 `SHORTFALL_TOO_LARGE` path consumes **no** ad grant and debits
    **no** coins, so the accepted old-client exposure really is "wasted time only".

### Frontend (widget/integration — pump the real screen)
12. **§4** — countdown renders `45s` under a minute; past `endsAt` the bar renders the
    settling state and the per-second timer is cancelled.
13. **§5** — race detail for a non-participant spectator renders the feed and **no**
    composer; for a participant the composer is present.
14. **§6** — the owned-count badge's text color is the cream token in **both**
    palettes (assert the resolved color, so the night flip can't regress silently).
15. **§7** — with `adUnlock.maxShortfall = 20`, a 90-short tile shows **Get coins**, not
    a watch-ads button; with `remainingToday = 0` the ad button is absent; with the
    `adUnlock` block **absent** the legacy 150 behaviour is preserved.
16. **§8** — long item names render two lines un-ellipsised at the narrowest supported
    width.
17. **§9** — chip hidden when `characterPowersEnabled` is absent/false; present and
    collapsed when true; expands on tap; correct copy per equipped animal incl. the
    null → capybara default.

---

## 10. Acceptance criteria / definition of done

- [ ] Eliminated players receive no tournament push after their own `TOURNAMENT_ELIMINATED`.
- [ ] Phone sign-in: **no work done** (D2 — dropped). Listed here only so its absence is
      deliberate rather than forgotten.
- [ ] Uprising in a team race is proven — by integration test — to buff the whole
      losing team and no one on the winning team, using the same steps the board shows.
- [ ] Bracket countdown shows seconds under a minute and an honest settling state; the
      5-minute settlement window is documented in this spec (§4).
- [ ] A bracket participant (including eliminated) can read any sibling matchup's chat
      and activity; cannot post; stealth redaction holds.
- [ ] The shop owned-count pill is legible in dark mode, and every other
      `parchment`-as-text-color site found by the audit is fixed and listed.
- [ ] Ad-to-buy: works for accessories and characters; threshold is served by the API
      **and** flipped to 20 in prod (D5); capped once per local day across both flows
      (D4); the `SHORTFALL_TOO_LARGE` copy is updated for stranded old clients; abuse
      check documented (§7.1); **no shipped client is broken by the deploy** (verified
      by the no-`localDate` test).
- [ ] Shop type scale raised with no new ellipsising at the narrowest width.
- [ ] Home shows a collapsed, tappable character-power notice for **every** user
      including default capybaras (D6), hidden whenever `characterPowersEnabled` is
      absent or false.
- [ ] `CHARACTER_POWERS_ENABLED=true` in prod (D7), flipped **after** the deploy was
      verified, with the `HERD_BONUS` feed line confirmed live in a real race and the
      first post-flip settlement observed.
- [ ] Corgi's shop description names Zoomies in **prod**, with a guard test preventing
      recurrence.
- [ ] `flutter build ipa` **and** `flutter build appbundle --flavor prod` both succeed
      with the same version/build number and `--dart-define`s (lockstep rule).
- [ ] Backend `test:unit` and `test:integration` green (against the test DB), with any
      pre-existing failures identified as pre-existing rather than "fixed".
- [ ] No existing test was modified or deleted.

---

## 11. Follow-ups (deliberately not in this batch)

- **Turtle + Corgi `testOnly` → `false`** — only after an App Store build carrying
  `turtle_walk_right.png` has rolled out. Unrelated to the D7 flag flip, which does not
  depend on the art.
- **Shop tile grid: 3 columns instead of 4.** Names like "Spinning Basketball" cannot
  fit a 4-up tile at any readable size (§8 correction).
- **Ad-unlock daily-cap race.** The cap is a `COUNT` inside the transaction, so under
  READ COMMITTED two concurrent unlocks holding two distinct unconsumed watches could
  both pass it. The conditional consume still prevents double-spending the *same*
  watch. This matches the guarantee `claimAdCoinReward` already gives; closing it needs
  a unique key or `SELECT … FOR UPDATE` on the user row. Low real-world risk (requires
  two verified watches and a deliberate race), but real.
- **Stale-`totalSteps` targeting audit** (see the §3 root-cause correction — the issue
  is staleness, not raw-vs-effective). `sortedActiveParticipants`
  (`usePowerup.js:356-358`) sorts on the raw column, and it backs the solo Uprising
  bottom-half gate, Hitchhike FRONT/BEHIND, `participantRank` and `adjacentParticipant`.
  Every one of those can disagree with the standings the player sees, for the same
  reason as §3. Worth a dedicated pass.
- **`TOURNAMENT_COMPLETED` handler removal** — left in place as dead code (§1); clean up
  once nothing can emit it.

---

## 12. Revision log

**Pass 1 (fresh-eyes gap pass).**
- §7 was specced as "add a daily cap" with no notion of *whose* day. Added the
  `localDate` requirement and, critically, the **optional-`localDate` old-client
  compat rule** — the original draft would have 400'd every currently-shipped binary
  the moment it deployed. This was the single worst defect in the draft.
- §7 originally generalized `unlockPowerupWithAds` to cover cosmetics. Traced the
  cosmetic path and found it uses different item, grant, **and** idempotency tables
  (`shop_items` / `user_shop_items` / `shop_purchase_requests`), which would have put a
  coin-zeroing debit behind a type-switch. Changed to a sibling endpoint and pinned
  both contracts in §4.
- §7 had no answer for frozen clients that hardcode `_maxAdUnlockShortfall = 150`
  (`shop_tab.dart:120`). Added §7.4: serve the threshold in the catalog, hold the env
  flip until the release rolls out. Added Q5.
- §9 asserted the character power copy unconditionally. Found `CHARACTER_POWERS_ENABLED`
  is **off in prod**, so the chip would have advertised a power that does nothing.
  Added the additive `characterPowersEnabled` field and the hide-on-absence rule.
- §6 was "fix the pill". Traced the exact tokens and found the cause is
  `parchment`-used-as-*text*, which flips to near-black at night — a class of bug.
  Added the repo-wide audit obligation and the note that the `highlighted` branch is
  already correct and must not be touched.
- §3 was going to be "confirmed correct, close it". Second read of the inputs found the
  gate sums raw `totalSteps` while the board shows effective steps. Added the divergence,
  the failure scenario, the blast-radius warning, and Q3.

**Pass 2 (second independent gap pass).**
- §5 claimed new access-control work. Found `tournamentAccess.isTournamentParticipant`
  **already exists** and is already wired into `getRaceDetails`/`getRaceProgress` — the
  gap is only the two feed queries. Rewrote §5 to reuse it; the item shrank from a
  feature to a two-file change.
- §5 had no write-path statement. Added the explicit "writes stay participant-only"
  requirement, the spectator-POST-403 test, and the stealth-redaction test (spectators
  are a **new caller** of redaction code written for participants).
- §1 said "suppress for eliminated players". Realized every non-champion in a completed
  bracket *is* eliminated, so the rule is equivalent to deleting the push. Surfaced that
  as Q1 rather than silently shipping a bigger change than asked. Also noted the
  runner-up double-push that exists today.
- §8 raised font sizes with no regard for the two fixed-height boxes
  (`height: 34` / `height: 30`) and the `maxLines: 2` + ellipsis on the name. Added the
  box-height requirement and the narrowest-width verification.
- §4 answered "what is the settlement period" but not why it *looked* stuck. Traced
  `_countdownShort` and found three separate defects (`0m`, `soon` under a
  `ROUND ENDS IN` label, and a 1s timer with 1min granularity). Specced all three.
- §5/§10 test list: added the case that a user with **no** tournament relation still
  gets 403 — the draft only tested the positive path, which would have passed against
  an accidentally-open endpoint.
- §7: added the "no coins debited / no grant consumed on the failed call" assertion to
  the cap test. A 409 that has already consumed the ad grant is the expensive failure.
- §5 rollout row was "inert" for old clients. Corrected: an old client's composer is
  still visible to a spectator, so a send 403s with a toast until the app ships.
- §10: found `data/cosmetics.json` is already correct and only **prod** is stale, so the
  fix is a data apply, not a code change — and it can ship first, alone, with zero risk.
  Added the standing prod-cosmetics-drift and seed-clobber traps.
- §5: **no** `X-Client-Features` token is needed anywhere in this batch (confirmed
  against `backend_api_service.dart:126-128`); the draft had implied one for §5.

**Pass 3 (post-interview, folding in D1–D7).**
- D2 changed item 2 from "deferred with a follow-up spec" to **dropped**; removed it
  from §11 so no phantom work is tracked.
- D5 inverted §7.4's recommendation. Rather than just deleting the warning, quantified
  the accepted exposure (who: 21–150 short on ≤2.0.0; what: wasted ads, **no** coin or
  grant loss, verified against `unlockPowerupWithAds.js:78-92`; how long: until 2.1.0
  rolls out) and added a **required** mitigation the owner didn't have to ask for —
  rewriting the `SHORTFALL_TOO_LARGE` message, since that string is the only thing a
  stranded old client will see. Kept the served-threshold work, which the draft had
  bundled with the gating; it is independently necessary.
- D7 added a live-scoring change that the draft had explicitly ruled out. Verified its
  stated precondition rather than assuming: the `HERD_BONUS` race-feed line **is**
  implemented and already in prod code
  (`characterEffectScheduler.js:167-255`, backend `0956cc3`), inert behind the flag —
  so the flip is unblocked. Added §9.2 with the blast-radius table (herd bonus touches
  effectively the whole user base; Zoomies/Shell only TestFlight), an ordered rollout
  step separating the flip from the deploy, the observe-first-settlement requirement,
  the feed-line-or-roll-back rule, and test 18 pinning that the bonus never moves box
  progress.
- D7 also made §9's "hide when the flag is off" rule look redundant. It is not — kept
  and re-justified: the flag is a kill switch, so the chip must vanish on its own if it
  is flipped back.
- D6 confirmed the chip shows for capybaras, which means **every** user sees it; noted
  that explicitly, since "no CHARACTER cosmetic == capybara" makes this universal
  rather than a subset.
- Added test 19 pinning the no-loss claim in §7.4 — the claim is load-bearing for
  accepting D5, so it should be enforced by a test rather than by a code reading.

**Pass 4 (post-implementation corrections).** Both build agents pushed back on the
spec; four of their objections were correct and are folded in above.
- **§1's premise was wrong** and D1 as written silently dropped the runner-up's only
  end-of-run push. Verified against `advanceTournament.js:209-218`, escalated to the
  owner, who approved emitting `TOURNAMENT_ELIMINATED` for the final's loser. Fixed in
  code; the batch's own test (which had correctly pinned the undesired behaviour rather
  than widening scope on its own) was updated to guard the new one.
- **§3's root cause was misdiagnosed** — the divergence is staleness, not
  raw-vs-effective. Corrected in place, and the §11 follow-up retitled so it hunts the
  right thing.
- **§4.1's endpoint path did not exist.** Real route is
  `POST /shop/powerups/unlock-with-ads` with the sku in the body. Corrected; both agents
  had independently done the right thing, so no code was affected.
- **§8's "hard constraint" was impossible** and had been failing before this batch.
  Replaced with the shipped fitted-name approach and a 3-column-grid follow-up.
- **§5's `grantedDate` assumption was wrong** — unlock watches arrive stamped with the
  *server* date, so the consume now restamps to the resolved local date. Noted here so
  the cap's "per user's day" semantics aren't mistaken for something the column gave
  for free.
- Owner also approved rewriting three stale `feature-batch-2026-07-24-shop.test.js`
  cases (they hardcoded 120/50-coin shortfalls as successes, impossible under D5's
  20-coin ceiling). Rewritten to sub-20 shortfalls rather than pinning the suite to the
  old threshold, which would have hidden the shipped default. Suite is 7/7 green.
