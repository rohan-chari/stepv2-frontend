# Team Race Fixes — Requirements

Batch of 5 production issues on the newly-shipped **team races** feature. Spec
follows the CLAUDE.md PM/BA workflow. Contract-first, then two Opus agents
(backend + frontend) implement in parallel, tests-first.

- **Repos:** frontend `/Users/rohan/repos/stepv2-frontend`, backend `/Users/rohan/repos/stepv2-backend`
- **Date:** 2026-07-16
- **Author:** PM/BA pass (Claude)

---

## Summary & user story

Five defects/enhancements surfaced after the team-races launch:

1. **Race detail is too small/hard to read for team races.** Redesign the
   team standings + head-to-head so it's legible and hierarchy-forward,
   Clash-Royale-clear, staying on the app's parchment/wood identity.
2. **Lobby is hard to read + the team-hop capybara animation is choppy.**
   Usernames are 11px; the hop uses hard-coded geometry, double easing, and a
   single-frame overlay→slot swap that "pops."
3. **Prod bug (July 15, ~9:23PM ET): accepting a team race from the homepage
   throws a raw error.** The homepage ACCEPT sends no team; backend requires a
   side → `400 "Pick a team (TEAM_A or TEAM_B)…"` rendered verbatim as
   `Could not accept: <raw>`. Fix functionally **and** make errors friendly.
4. **Owner can't edit the buy-in on a PENDING race once people have paid.**
   Allow full editing (raise/lower + toggle paid↔free) with correct coin
   refunds/re-charges.
5. **Forfeit confirmation is an unstyled Material `AlertDialog`.** Rebrand it to
   the app's `Dialog`+`TrailSign`+`PillButton` pattern.

**Who:** all team-race players (iOS Bara + Android). **Why:** launch polish +
one active prod bug that's been failing frozen old clients for ~a day.

---

## Scope / non-goals

**In scope**
- Backend: auto-assign team on team-less accept/join (§Issue 3); stable error
  `code`s on all respond/join failures (§Issue 3); editable buy-in with
  refund/re-charge reconciliation + affordability gate + push notify (§Issue 4);
  a `raceParticipant.buyInVersion` migration; a `BUYIN_EDIT_ENABLED` kill flag.
- Frontend: redesign team-race **detail standings + H2H** (§Issue 1); redesign
  **lobby** legibility + rewrite the **hop animation** (§Issue 2); friendly error
  mapping on the two homepage handlers (§Issue 3); **edit-buy-in** UI unlock +
  refund/charge consequence copy (§Issue 4); **branded forfeit modal** (+ the
  sibling "Leave the lobby?" dialog for consistency) (§Issue 5).

**Non-goals**
- No change to solo/ranked race UI (only team-race branches).
- No change to race settlement/payout math, powerups, or scoring.
- No change to how buy-ins are charged **at join** time (only at **edit** time).
- No mid-race buy-in edits (PENDING only, as today).
- No new "choose a side" UI on the homepage card (decision: auto-assign).
- Not redesigning the completed/winner boards beyond what legibility requires.

---

## Decisions locked (interview, 2026-07-16)

| # | Decision |
|---|----------|
| 3 | Homepage team-race accept → **auto-assign the smaller side** (Team A on tie). Implement **backend-side** so frozen old clients are fixed on deploy. |
| 4 | Buy-in edits → **full flexibility**: raise/lower the amount **and** toggle the race paid↔free (toggle→free refunds everyone fully). |
| 4 | If a raise (or free→paid) leaves any already-joined player unable to afford → **block the edit**, naming the offending player(s). No silent removal/charge. |
| 1/2/5 | Design → **keep the parchment/wood identity**, apply Clash-Royale clarity, hierarchy, and juice. Load the mobile-design skill before any UI work. |

---

## Backward-compat & the #1 rule (frozen old clients)

The prod backend serves **all** app versions at once; a shipped binary is frozen
and App Store rollout is phased ~a week. Every change below is designed so an
**old app + current backend** and a **new app + current backend** both work:

- **Issue 3 (auto-assign):** old clients call `PUT /races/:id/respond` and
  `POST /races/:id/join` with **no team** — today they get the 400 error. After
  the backend change they auto-assign to the smaller side and **succeed**. This
  is a strict improvement for frozen clients; no old client relied on the 400.
- **Issue 3 (error codes):** adding `code` to error bodies is additive; old
  clients ignore `code` and still show `error`. New clients map `code`→friendly.
- **Issue 4 (buy-in edit):** `buyInVersion` is an additive column (default 0);
  `potCoins` recompute is server-internal. Old clients that cached a race's
  `buyInAmount` just show a stale number until their next fetch and are charged
  the **current** `race.buyInAmount` if they join — unchanged behavior. An old
  client can't *trigger* an edit that unlocks buy-in (its edit screen still
  blocks it), so no old client can create an inconsistent state.
- **Issues 1/2/5:** client-only; ship in the app build, no backend dependency.

**Deploy order:** backend first (all §Issue 3 + §Issue 4 backend, additive and
old-client-safe), then the app build (all UI + error mapping + edit UI).

---

# API contract (pinned BEFORE either agent implements)

## Issue 3 — Auto-assign + error codes

### 3a. Auto-assign team on team-less accept/join
Applies to **both** `PUT /races/:raceId/respond` (`respondToRaceInvite.js`) and
the join core (`joinRaceCore.js`, used by `POST /races/:raceId/join` and
`POST /races/share/:token/join`).

Rule when `race.isTeamRace` and the request omits `team` (or sends null):
1. Compute ACCEPTED member counts per side.
2. Target = the side with **fewer** ACCEPTED members; **tie → `TEAM_A`**.
3. If the target side is **full** (`memberCount >= teamSize`), fall back to the
   other side.
4. If **both** sides are full → `409 { error, code: "TEAM_FULL" }`.
5. Otherwise assign the participant to the chosen side and proceed exactly as if
   that side had been passed explicitly (same buy-in charge, same response body).

If `team` **is** provided explicitly (in-app lobby paths), behavior is unchanged
(honor it; `TEAM_FULL` if that specific side is full). The `400 "Pick a team…"`
throw for the team-less case is **removed**.

**Response:** unchanged success payload (participant/race map). No shape change.

### 3b. Stable error codes on respond/join
Every `RaceInviteResponseError` / `RaceJoinError` must carry a stable `code` in
addition to its human `error` string, so the client can map to friendly copy.
Add these codes (keep existing messages as the `error` fallback):

| Condition | HTTP | `code` |
|-----------|------|--------|
| Race not found | 404 | `RACE_NOT_FOUND` |
| No longer accepting responses / new participants | 400 | `RACE_NOT_ACCEPTING` |
| Not invited | 403 | `NOT_INVITED` |
| Already responded / already in this race | 400 | `ALREADY_RESPONDED` |
| App too old for team races | 400 | `UPDATE_REQUIRED` *(exists)* |
| Team race already started | 409 | `RACE_ALREADY_STARTED` *(exists)* |
| Team full (specific or both) | 409 | `TEAM_FULL` *(exists)* |
| Can't join paid race after someone finished | 400 | `PAID_RACE_LOCKED` |
| Not enough coins for buy-in | 400 | `INSUFFICIENT_COINS` |
| Unexpected | 500 | *(no code; client shows generic)* |

Codes are additive; the `error` message stays for old clients.

### 3c. Frontend consumption
- `main_shell.dart` `_acceptRaceInviteFromCard` (:1252) and `_joinRaceFromCard`
  (:1150): switch bare `catch (e)` → `on ApiException catch (e)` and render
  `e.code != null ? teamRaceErrorCopy(e.code) : (e.message ?? generic)`.
- Extend `teamRaceErrorCopy` (`lib/utils/team_race.dart:298`) to add friendly
  copy for `RACE_NOT_FOUND`, `RACE_NOT_ACCEPTING`, `NOT_INVITED`,
  `ALREADY_RESPONDED`, `PAID_RACE_LOCKED`, `INSUFFICIENT_COINS`. Keep the
  existing safe generic `default`.
- With auto-assign live, the happy path from the homepage now succeeds; the
  friendly mapper covers the residual real failures (both teams full, race
  started, insufficient coins, etc.). **No team/solo branching is needed in the
  homepage handler** — it keeps calling `respondToRaceInvite`/`joinPublicRace`
  with no team; the backend owns auto-assign for team races and ignores it for
  solo. After auto-assign a player can still change sides later via the lobby
  (`setRaceTeam`), and auto-assigning the smaller side plays nicely with the
  even-team start gate.

## Issue 4 — Edit buy-in on a PENDING race

Extends the existing `PATCH /races/:raceId` (editRace). Owner-only, `status ===
"PENDING"` (both already enforced).

### Request (additive fields; all optional)
```json
{
  "buyInAmount": 150,        // new amount in coins; validated 10..200 when paid
  "buyInEnabled": true       // false => race becomes free (buyInAmount forced 0)
}
```
- `buyInEnabled:false` (or `buyInAmount:0`) ⇒ toggle to **free**.
- A previously-free race with `buyInEnabled:true` + `buyInAmount:N` ⇒ toggle to
  **paid** at N.
- Amount-only change (still paid) ⇒ raise or lower to the new N.

### Behavior
The reconciliation set is **all `ACCEPTED` participants** (they are the ones "in"
the race and holding/owing a buy-in) — **not** just the currently-`HELD` subset.
This matters for **free→paid**, where every ACCEPTED participant is `buyInStatus
NONE` and must be charged; a "charged-only" set would silently make free→paid a
no-op. `INVITED` participants are excluded — they pay at accept time at the
then-current amount. For each ACCEPTED participant: `oldAmt =
participant.buyInAmount` if `buyInStatus ∈ {HELD, COMMITTED}` else `0`; `newAmt` =
the race's new effective buy-in (0 if toggled free).

1. **Lock for serialization:** take `FOR UPDATE` on the **race row** at the top of
   the txn (see Concurrency below), then load participants inside the txn.
2. **Validate config:** `validateRaceBuyInConfig` (min 10 / max 200 / preset)
   when the result is paid.
3. **Affordability precheck (block rule):** for every ACCEPTED participant with
   `delta = newAmt - oldAmt > 0`, require `user.coins >= delta`. If **any** fail
   → `400 { error: "<Name> doesn't have enough coins for the new buy-in.", code:
   "BUYIN_UNAFFORDABLE" }` — put the offending name(s) **in the `error` message**
   (do not rely on a `data` object; the client's `ApiException` only carries
   `error`+`status`+`code`). The owner is a participant and is checked too.
   **No** state mutated on block.
4. **Reconcile** (still in the txn), for each ACCEPTED participant where `delta !=
   0`:
   - `awardCoins({ userId, amount: -delta, reason: "race_buy_in_adjust", refId:
     "<raceId>:<userId>:v<newVersion>" })` — one call; `-delta` is negative to
     charge (raise / free→paid), positive to refund (lower / paid→free).
   - Set `participant.buyInAmount = newAmt`; increment `participant.buyInVersion`
     (`newVersion`).
   - Status: `newAmt === 0` ⇒ `buyInStatus = "REFUNDED"`; `newAmt > 0` and it was
     `NONE`/`REFUNDED` ⇒ `buyInStatus = "HELD"`; otherwise leave `HELD`.
   - **Ledger gotcha (critical):** edit-time movements ALWAYS use reason
     `race_buy_in_adjust` + the **versioned** `refId` and **never** reuse the
     join-time refIds (`${raceId}:${userId}` for `race_buy_in_hold` /
     `race_buy_in_refund`). Reusing them makes `awardCoins`'s `(userId, reason,
     refId)` idempotency **silently skip** the movement — e.g. a re-charge after
     a refund would no-op, yielding a free race. `newVersion` guarantees a unique
     `refId` per edit even for repeated edits to the same amount.
5. **Recompute pot + preview:** `race.buyInAmount = newAmt`, internal enabled
   flag; `race.potCoins = Σ buyInAmount over HELD participants`; ensure the
   returned `finishReward`/pool preview is derived from the new `potCoins`.
6. **Notify:** for each ACCEPTED participant **except the owner** whose amount
   actually changed, send a push via the existing notification service:
   `"Buy-in updated"` / `"<race name>'s buy-in is now <N> coins."` (or
   `"…is now free."`). Best-effort; a push failure must not fail the edit. (This
   is the one cuttable item if the notification path proves risky — flag it.)
7. **Response:** the updated race payload (same shape as any editRace success),
   reflecting new `buyInAmount`, `potCoins`, `finishReward`, and participants'
   `buyInAmount`.

### Concurrency (edit vs. a concurrent join)
Without serialization, an owner raising 100→150 while a player concurrently joins
at 100 leaves an inconsistent pot. Both `editRace` and the join core
(`joinRaceCore`) must take `FOR UPDATE` on the **race row** before reading
participants / charging, so the two operations serialize: whichever commits first
is fully seen by the second (a late joiner pays the new amount; an edit that runs
first-or-second still recomputes `potCoins` over the committed participant set).
If join doesn't already lock the race row, add it (small, safe change).

### Kill switch
Gate the *unlock* behind an `AppSetting` `BUYIN_EDIT_ENABLED` (default **true**).
When false, editRace keeps the old hard block (`code: "IMMUTABLE_FIELD"` /
existing message) so we can disable the feature without a redeploy.

### Data model / migration
- Add `raceParticipant.buyInVersion INT NOT NULL DEFAULT 0` (Prisma migration
  `migrate deploy` + `generate`). Backfill: default 0 for all existing rows —
  safe, no data rewrite. Reads default-safe (absent ⇒ 0).
- No other schema change. `potCoins`, `buyInAmount`, `buyInStatus` already exist.

### Frontend consumption (Issue 4 UI)
- `edit_race_screen.dart`: relax `_buyInLocked` (:65, :111-114) so the buy-in
  toggle/input are **editable** while PENDING even if participants have paid.
  Show a clear consequence line ("Changing the buy-in refunds or re-charges
  everyone who's already joined").
- On save, send `buyInAmount`/`buyInEnabled` as today (the diff logic at
  :418-419/:511-513 already only sends buy-in when it changed).
- Handle `BUYIN_UNAFFORDABLE`: the server already puts the specific player
  name(s) in `error`, so for this code show **`e.message`** (the server's
  specific line) rather than a generic. Add a generic `BUYIN_UNAFFORDABLE`
  fallback to `teamRaceErrorCopy` only for the (unexpected) empty-message case.
- Refresh wallet + race after a successful edit.

---

# Frontend plan (UI issues 1, 2, 5)

All client-only, no API change. **Load the `mobile-design` skill before any UI
work** (per CLAUDE.md + memory `ui-redesign-feedback-rules`). Keep parchment/wood
identity + `TeamColors` (A red `0xFFC15A46`, B blue `0xFF3E7CB1`). iOS + Android
build in lockstep (same Dart). States to cover: loading (skeleton already
exists), empty (no members yet), error (existing toast path).

## Issue 1 — Team-race detail: standings + H2H legibility
Files: `race_detail_screen.dart` (`_buildTeamGroupedRows` :4745, standings card
:3189-3206, H2H wrap :3160-3187), `team_h2h_banner.dart`, `leaderboard_plank.dart`.

- **Standings card** (:3196): raise interior padding from `all(8)` toward the
  app-standard `all(14)`; give the two rosters clear vertical separation.
- **Team group headers** (:4764): from 12px to a bold **~18–20px** team banner
  with the team color fill/plaque (Clash-Royale team-header feel), showing team
  name + **team total** prominently.
- **Member rows**: either bump `LeaderboardPlank` sizing *in the team context*
  (name 15→~17, steps 16→~18, avatar 32→larger) **without** regressing solo
  races (introduce a team/compact variant or size params — do **not** globally
  resize the shared plank if it changes solo layout), or a team-specific row.
- **H2H banner**: enlarge end-post team names (12→~16) and totals; keep the tug
  rope but make the lead state obvious. Bigger, juicier, still parchment.
- Confetti stays scoped to race *finish* only (memory rule) — no new confetti.

## Issue 2 — Lobby: legibility + hop animation
File: `team_lobby_board.dart`.

- **Usernames**: `_filledSlot` name (:389-397) 11px → **~14–15px**; enlarge the
  avatar (34→larger) and revisit `_slotHeight` (45) so text isn't cramped. Team
  plaque name (:221) and counts up for readability. "TAP TO JOIN" legible.
- **Hop animation rewrite** (root causes confirmed):
  - **Measure real geometry**, not hard-coded 56px constants. Note the departed
    slot no longer exists in the new tree (the player is now on the other side),
    so you can't `GlobalKey`-measure the "from" slot after the rebuild. Because
    all slots are uniform, measure the **real slot metrics once** (actual slot
    height/gap + each column's origin/width) post-layout via a `RenderBox` /
    `LayoutBuilder`, then compute any slot center **analytically** from those
    measured metrics + the known indices: `fromIndex` from `oldWidget.participants`
    (available in `didUpdateWidget`) and `toIndex` from the new list. This fixes
    both mis-anchored takeoff/landing and reflow drift without depending on a
    widget that's gone.
  - **Single easing:** drive the arc off one `Curve` (or the bezier alone) — not
    `Curves.easeInOut` composed on top of a bezier. One consistent motion.
  - **Distance-scaled peak:** arc height a function of the from→to distance, not
    a fixed −52px, so short and long jumps both look right.
  - **Cross-fade handoff:** fade the arriving capy into its real slot over the
    last ~100–120ms instead of the single-frame `hideCapy` swap that "pops."
  - **Guard restarts:** only `forward(from:0)` when `myTeam` actually changed and
    no hop is mid-flight (or finish/replace cleanly); ignore unrelated parent
    rebuilds / poll refreshes so the arc isn't restarted mid-air.
  - Keep dispose (already present). Keep squash/stretch + dust, but tuned to the
    new single-curve timing.

## Issue 5 — Branded forfeit (+ leave-lobby) modal
File: `race_detail_screen.dart`.

- Replace the Material `AlertDialog` in `_forfeitTeamRace` (:942-992) with the
  branded pattern used by the paid-invite confirm (:758-799):
  `Dialog(backgroundColor: transparent, child: TrailSign(...))` + two
  `PillButton`s ("KEEP RACING" / "FORFEIT ANYWAY"). Keep the three consequence
  lines (steps freeze, no refund, permanent) styled in-theme with icons.
- Apply the same rebrand to the sibling **"Leave the lobby?"** `AlertDialog`
  (:1040) for consistency (same un-branded pattern).
- No API change; existing `forfeitRace`/leave calls unchanged.

---

# Test plan (tests-first, both agents)

Backend (use `test:unit` / `test:integration`, **never** bare `npm test`, never
point at prod DB):
- **Auto-assign:** team-less accept → smaller side; tie → TEAM_A; smaller side
  full → other side; both full → 409 `TEAM_FULL`; explicit team still honored.
- **Error codes:** each respond/join failure returns the right `code` + status.
- **Buy-in edit — lower:** charged participants refunded the delta; `potCoins`
  recomputed; `buyInVersion` incremented; per-participant `buyInAmount` updated.
- **Buy-in edit — raise (affordable):** charged participants debited the delta;
  ledger rows written with the versioned `refId` (no idempotency skip).
- **Buy-in edit — raise (unaffordable):** `400 BUYIN_UNAFFORDABLE` with
  `data.players`; **no** coin movement, **no** state change (rollback verified).
- **Buy-in edit — toggle→free:** everyone fully refunded, `buyInStatus REFUNDED`,
  `potCoins 0`, `race.buyInAmount 0`.
- **Buy-in edit — toggle free→paid:** everyone charged; unaffordable → blocked.
- **Idempotency/refId:** two sequential edits to the same amount both apply
  (distinct versions) — proves the refId gotcha is handled.
- **Kill switch:** `BUYIN_EDIT_ENABLED=false` → old hard block.
- **Non-PENDING / non-owner** edit rejected (existing guards intact).

Frontend (`flutter test`; do not modify/delete existing tests — surface any that
look wrong):
- `teamRaceErrorCopy` returns friendly copy for every new code + safe default.
- Homepage handlers map `ApiException.code`→friendly (widget/unit test the
  mapping, not the network).
- Edit-race screen: buy-in editable while PENDING with paid participants;
  `BUYIN_UNAFFORDABLE` surfaces the named-player message.
- Hop animation: a golden/widget smoke test that the board builds and the
  controller starts/stops on a team change without exceptions (geometry logic
  unit-tested where extractable).

---

# Acceptance criteria / definition of done

- [ ] Accepting/joining a **team** race from the homepage **succeeds** (smaller
      side, Team A on tie) — verified against a team race; the July 15 error is
      gone for both new and **frozen old** clients after backend deploy.
- [ ] Every residual respond/join failure shows **friendly copy**, never a raw
      `Could not accept: <backend English>`.
- [ ] Owner can **raise, lower, and toggle paid↔free** the buy-in on a PENDING
      race with paid participants; coins refund/re-charge correctly; `potCoins`
      stays consistent; a raise nobody can afford is **blocked** with the name.
- [ ] `buyInVersion` migration applied to local/staging (never prod for tests);
      no ledger double-charge or silent skip.
- [ ] Team-race **detail** standings + H2H are visibly larger/clearer, on-theme.
- [ ] Lobby **usernames** are legible; the **hop** starts and lands on the right
      slots, uses one easing, scales its arc, and cross-fades in (no pop, no
      mid-air restart).
- [ ] Forfeit (and leave-lobby) confirmation uses the **branded** dialog.
- [ ] **Both** iOS and Android build clean; solo/ranked race UI unregressed.
- [ ] Backend deploys first; app build ships after; kill switch verified.

---

# Revision log

**Pass 1 — correctness / edge cases**
1. **Free→paid hole (critical):** the reconcile set was "participants with
   `buyInStatus ∈ {HELD,COMMITTED}`". On a free race everyone is `NONE`, so
   free→paid would charge nobody yet flip the race to paid. Changed the set to
   **all ACCEPTED participants**, with `oldAmt=0` for `NONE` and correct
   `buyInStatus` transitions (`NONE/REFUNDED → HELD` on charge, `→ REFUNDED` on
   free). Excluded `INVITED` (they pay at accept).
2. **Ledger refId reuse restated as a hard rule:** all edit-time coin movements
   use `race_buy_in_adjust` + a **versioned** refId and never the join-time
   hold/refund refIds, else `awardCoins` idempotency silently no-ops a re-charge.
3. **Concurrency:** added a `FOR UPDATE` race-row lock to both `editRace` and the
   join core so a concurrent join can't desync `potCoins`.
4. **Pot/preview:** made `potCoins` + `finishReward` recompute explicit in the
   response.

**Pass 2 — contract / client-reachability / rollout**
5. **`data.players` unreachable:** the client's `ApiException` only carries
   `error`+`status`+`code` (per `_decodeJsonResponse`). Moved the unaffordable
   player name(s) **into the `error` message**; the client shows `e.message` for
   `BUYIN_UNAFFORDABLE`. Dropped the `data` object — no ApiException change needed.
6. **Animation "from" slot is gone after rebuild:** a per-slot `GlobalKey` can't
   measure the departed slot. Switched to measuring **uniform slot metrics once**
   and computing anchors analytically from measured metrics + known old/new
   indices (`oldWidget.participants` in `didUpdateWidget`).
7. **Homepage handler needs no team branching:** clarified the frontend keeps
   sending no team; backend owns auto-assign. Noted auto-assigned players can
   still switch sides in the lobby and that auto-assign aids the even-team gate.
8. **Push notify** flagged as the single cuttable item if the notification path
   proves risky.
