# Bug Batch 2026-07-21 — Requirements

Seven user-reported bugs (one already handled as a prod data correction). Two repos:
frontend `/Users/rohan/repos/stepv2-frontend`, backend `/Users/rohan/repos/stepv2-backend`.

## Summary & user stories

| # | Bug | Fix side |
|---|-----|----------|
| B1 | Race activity feed reveals what people got from mystery boxes | Backend |
| B2 | Mirrored Shortcut sends the attacker a "you stole steps from yourself" push | Backend |
| B3 | Rainstorm (store item) gets stranded in one race's inventory when its use is rejected | Backend (+ frontend copy) |
| B4 | Second player can't Rainstorm back while one storm is active — product decision | Backend (decision pending) |
| B5 | Pocket Watch sheet has no Discard option | Frontend |
| B6 | Races-tab state pill counts are plain text — put a circle badge around them | Frontend |
| B7 | Keyboard doesn't dismiss in tournament (= race) chat | Frontend |

- As a racer, I don't want everyone to see what I pulled from a mystery box (B1).
- As an attacker whose Shortcut got Mirrored, I shouldn't get a nonsense "X stole steps
  from you" push where X is me (B2).
- As a Rainstorm buyer, a rejected cast must not eat my purchase into a race I can't
  use it in (B3), and the "one storm" rule should feel fair in back-and-forth play (B4).
- As a powerup holder I can discard a Pocket Watch like any other powerup (B5).
- Small UI polish: badge the pill counts (B6); chat keyboard dismisses on tap-away/drag (B7).

## Scope / non-goals

- **In scope:** the seven items above, backend-first deploy, tests-first.
- **Out of scope:** any Rainstorm price/duration rebalance; redesign of the activity
  feed; a general un-redeem/refund system for all shop powerups (only the redeem
  pre-flight in B3); retroactive rewriting of historical feed-event *descriptions*
  (B1 is fixed by filtering, which retroactively hides old rows too); the Maizehhh
  prod data correction (already done 2026-07-21: her two held `pocket_watch` rows in
  "wyd Step bro" were set to `discarded`, then one restored to `held` on request).

---

## B1 — Mystery-box reveals in the race activity feed

### Root cause
The app's Activity tab reads `GET /races/:raceId/messages?kind=SYSTEM`
(`lib/services/race_feed_service.dart:84-89`), served by
`src/modules/social/queries/getRaceMessages.js`. That query filters only
`POWERUP_IMPOSTER` (`getRaceMessages.js:157`); the `MYSTERY_BOX_OPENED` filter exists
only in the *legacy* `/races/:raceId/feed` endpoint (`races/queries/getRaceFeed.js:47`).
So "X opened a mystery box — Leech!" (written by
`powerups/commands/openMysteryBox.js:162-168`) has shown in the feed ever since the app
moved to the merged messages endpoint. Answer to "has it always been like that?": yes,
since the chat-merged feed shipped; the older feed endpoint hid it.

There is a second leak: the Fanny-Pack full-inventory auto-activate branch writes
`eventType: "POWERUP_EARNED"` with description "… opened a mystery box — X!
Auto-activated — extra slot unlocked." (`openMysteryBox.js:132-138`). `POWERUP_EARNED`
cannot be blanket-filtered (it is also used for legitimate "earned a mystery box"
milestone events from `rollPowerup`/`joinRaceCore`).

**Owner question resolved:** only `FANNY_PACK` itself can auto-activate — the branch
is gated on `rolled.type === "FANNY_PACK" && occupiedCount >= maxSlots`
(`openMysteryBox.js:128`). A Leech (or any other type) can never auto-activate; the
leaked name in that branch is always "Fanny Pack".

### Fix (backend)
1. In `getRaceMessages.js`, exclude `MYSTERY_BOX_OPENED` from the SYSTEM items.
   **Do the exclusion in the DB query, not in JS after fetch.** The current
   imposter filter runs after `findByRace(limit: pageLimit+1)`; box-open events are
   frequent, so a JS filter can under-fill a page and prematurely terminate
   pagination (`nextCursor` computed from post-filter `merged.length` at
   `getRaceMessages.js:186-191`). Extend `RacePowerupEvent.findByRace` (or add an
   option) to accept `excludeEventTypes: [...]` translated to a Prisma
   `eventType: { notIn: [...] }`, and move the existing `POWERUP_IMPOSTER` filter
   into it as well. Keep the JS filter as a belt-and-suspenders no-op.
2. Fanny-pack auto-activate branch (`openMysteryBox.js:132-138`) — **decision:
   hide it.** Change the branch's `eventType` from `"POWERUP_EARNED"` to
   `"MYSTERY_BOX_OPENED"` (keep the descriptive text for the audit row). This both
   hides it from the feed via fix #1's filter AND fixes a latent undercount in the
   admin "unique box openers" metric, which today misses auto-activate opens
   because they don't write `MYSTERY_BOX_OPENED` (see the comment at
   `openMysteryBox.js:156-159`). Historical `POWERUP_EARNED` auto-activate rows
   remain visible but are rare and only ever say "Fanny Pack" — no redaction
   needed. Implementer must confirm the admin metric counts `MYSTERY_BOX_OPENED`
   by eventType (not by description) so the renamed rows are counted.

### Backward compat
Server-side only; all frozen app versions read the same endpoint and immediately stop
seeing box contents. Removing items from a feed cannot crash any client (they render
server text verbatim — `lib/widgets/feed_bubble.dart:130-135`). Legacy `/feed`
endpoint already filters; no change there.

---

## B2 — "You stole steps from yourself" push after a Mirror reflect

### Root cause
`usePowerup.js` Mirror reflect swaps roles (`resolvedTargetUserId = originalAttacker`
at `usePowerup.js:879`) but the closing `events.emit("POWERUP_USED", { userId, …,
targetUserId: resolvedTargetUserId })` (`usePowerup.js:1918-1924`) still passes the
original attacker as `userId`. After a reflect, `userId === targetUserId`. The
notification handler (`notifications/notificationHandlers.js:718-761`) then pushes
`"${attackerName} stole steps from you with Shortcut!"` to `targetUserId` — the
attacker, about themselves. Same bug applies to every reflectable type in the push
whitelist: `SHORTCUT`, `LEG_CRAMP`, `RED_CARD`, `WRONG_TURN`.

### Fix (backend)
In the `POWERUP_USED` handler in `notificationHandlers.js` (~line 720), guard early:
`if (!targetUserId || targetUserId === userId) return;` before any DB reads. This
kills the self-push for all reflected offensive types in one place, keeps the fix
robust to future emit sites, and leaves the feed's `POWERUP_REFLECTED` event (which
already tells both users what happened) untouched.

**Decision (Q2): suppress only.** No replacement reflect push — the in-race
`POWERUP_REFLECTED` feed event already tells the story.

**Implementer must also verify** the `POWERUP_USED` *feed event* description written
in the reflected path doesn't read "X used Shortcut on X" (the reflect writes a
`POWERUP_REFLECTED` feed row at `usePowerup.js:885-892`; confirm the generic
`POWERUP_USED` feed row is either absent or sensible in the reflected case, and fix
its name substitution if not).

### Backward compat
Push payload route/cases unchanged; we only suppress (or add) sends. Old clients
unaffected.

---

## B3 — Rainstorm stranded in a race when use is rejected

### Root cause
Store powerups are global inventory (`UserPowerupItem`). Using one from a race runs
client `_redeemAndUsePowerup` (`race_detail_screen.dart:1565-1609`): it first calls
`POST /races/:raceId/powerups/redeem` — which **decrements global inventory and mints
a race-scoped HELD `RacePowerup`** (`powerups/commands/redeemPowerupToRace.js:45-64`)
— then calls the use endpoint. Rainstorm's use pre-checks ("a Rainstorm is already
active in this race", `usePowerup.js:446-449`; caster signal-jammed 409 guard,
`usePowerup.js:379-390`) throw *after* redeem. There is no un-redeem path, so the
storm stays HELD, tied to that `raceId`/`participantId`, unusable anywhere else.

### Fix (backend — pre-flight the redeem)
In `redeemPowerupToRace.js`, **before** decrementing inventory, run the same cheap
pre-checks that would doom the subsequent use:
- Caster has an active `SIGNAL_JAMMER` effect in this race → reject
  `409 { error: "Powerups are jammed…", code: "SIGNAL_JAMMED" }` (mirror the use
  guard's copy/status).
- `powerupType === "RAINSTORM"` and the *redeeming user* already has an active
  RAINSTORM effect in the race (per-caster rule, matching B4) → reject
  `409 { error: "Your Rainstorm is already active in this race", code: "RAINSTORM_ACTIVE" }`.
- (Also pre-check the "no eligible other runners" rainstorm condition,
  `usePowerup.js:451-456`, → `400 { code: "NO_ELIGIBLE_TARGETS" }`.)

This is TOCTOU-imperfect (a storm could start between redeem and use) but shrinks the
stranding window from "always" to "a race-condition sliver". Do **not** build a
general un-redeem/refund endpoint in this batch (non-goal) — but note: any *already*
or *future* stranded HELD shop powerup can still be `discard`ed by the user once B5's
pattern exists (discard is type-agnostic, `discardPowerup.js:39`), it just isn't
refunded.

### Existing stranded rows
**Decision (Q4): no prod repair.** Already-stranded held Rainstorms stay where they
are (still usable in the race they're stuck in; under B4's per-caster rule they
become castable in far more situations anyway).

### Fix (frontend, next build)
- `_usePowerup`'s catch (`race_detail_screen.dart:1475-1477`) and
  `_redeemAndUsePowerup`'s catch (`:1590-1593`) show raw `e.toString()`. Map the new
  `code`s (`SIGNAL_JAMMED`, `RAINSTORM_ACTIVE`, `NO_ELIGIBLE_TARGETS`) to friendly
  copy via the existing error-copy pattern (cf. `teamRaceErrorCopy` usage at
  `race_detail_screen.dart:955`). Fallback to the server message for unknown codes
  (old backend compat).
- Old clients + new backend: they already toast the server `error` string on redeem
  failure (`:1591`) — behavior improves for them automatically (item stays in stash).

### Backward compat
Redeem rejection uses an error shape old clients already handle (`{ error }` + 4xx →
`ApiException` toast). New `code` field is additive. Deploy backend first; the fix
helps frozen clients immediately.

---

## B4 — Rainstorm concurrency: per-caster limit with 0.5x clamp (DECIDED)

Today the limit is **per-race global**: `usePowerup.js:446-449` rejects if *any*
active RAINSTORM effect exists in the race, regardless of caster. In the tournament
incident, the counter-storm was blocked for the storm's full 1h.

**Decision (Q3): per-caster limit, effects clamp at 0.5x.**
- Each user may have one active storm at a time; different users' storms may
  overlap. Change the check to
  `raceEffects.find(e => e.type === "RAINSTORM" && e.sourceUserId === userId)`
  (`RaceActiveEffect.sourceUserId`, schema:1109). Error copy becomes "Your Rainstorm
  is already active in this race".
- **Stacking clamp is a hard requirement:** a victim under two storms has two
  `RaceActiveEffect` rows. Scoring must apply **0.5x once, not 0.25x** (rule: any
  ≥1 active RAINSTORM effect on the victim → a single 0.5x). Implementer must locate
  every scoring site that applies the rainstorm multiplier (steps-sync scoring path;
  the additive scoring model per the 2026-07-04 rainstorm build) and assert
  once-only application in an end-to-end test.
- A caster's own active storm does not exempt them from *other* players' storms
  (they're a normal victim of someone else's storm — no change to victim selection).
- Mirror never reflects shop powerups (`SHOP_POWERUP_TYPES`, `usePowerup.js:64`) —
  unchanged.
- B3's redeem pre-flight `RAINSTORM_ACTIVE` check must use the same per-caster rule
  (only reject when the *redeeming user* already has an active storm).

### Backward compat
Old clients already render N active-effect rows (AoE storms create one row per
victim); an extra overlapping storm just adds rows to the same rails. The
`@@unique([powerupId, targetParticipantId])` constraint permits two different
powerups targeting the same participant. No API shape change.

---

## B5 — Pocket Watch has no Discard option (frontend only)

### Root cause
Tapping a powerup goes through `_showPowerupActions`
(`race_detail_screen.dart:1914`), which early-returns Pocket Watch into its dedicated
`PocketWatchSheet` (`:1924-1927`) — a widget with only the buffs/debuffs toggle and
tier buttons (`lib/widgets/pocket_watch_sheet.dart:228-271`). The generic sheet's
DISCARD `PillButton` (`race_detail_screen.dart:2017-2032` → `_discardPowerup:1611`)
is never reachable for Pocket Watch. Backend discard is already type-agnostic
(`discardPowerup.js:39` gates on status only) — no backend change.

### Fix
- Add an optional `onDiscard` callback to `PocketWatchSheet` (alongside `onConfirm`,
  `pocket_watch_sheet.dart:163`) and render a DISCARD `PillButton` after the tier
  buttons (after `:266`), styled like the generic sheet's discard (muted/destructive,
  visual parity with `race_detail_screen.dart:2017-2032`).
- Wire it in `_showPocketWatchSheet` (`race_detail_screen.dart:1900-1907`):
  `onDiscard: () { Navigator.pop(ctx); _discardPowerup(powerup); }`.
- Match the generic sheet's confirmation behavior exactly (currently: no extra
  confirm dialog — pop and discard).

---

## B6 — Circle badge around races-tab pill counts (frontend only)

`_buildStatePills` (`lib/screens/tabs/races_tab.dart:1164`) renders each
ACTIVE/PENDING/COMPLETED pill's count as bare `Text('$count')`
(`:1216-1225`). Wrap the count in a small circular badge consistent with the existing
`_CountBadge` (`races_tab.dart:2126-2146`): rounded/circular container, translucent
background, thin border; selected pill → dark-on-light badge, unselected →
parchment-on-translucent, matching current color logic (`:1219-1224`). Keep the
existing `Key('personal-state-count-…')` on the count text so tests keep working.
Badge must not change pill height; two-digit counts must fit (min-width circle,
`padding` not fixed `width`).

Also check the sibling `_RaceMetricText` count strip (`races_tab.dart:2080-2095`) —
**leave it as-is** (only the state pills were reported), but do not regress it.

---

## B7 — Keyboard won't dismiss in tournament chat (frontend only)

There is no separate tournament chat: matchups push the regular `RaceDetailScreen`
(`lib/screens/tournament_detail_screen.dart:426`). The chat tab simply has zero
dismissal affordances: message `ListView` (`race_detail_screen.dart:4482`) lacks
`keyboardDismissBehavior`, composer `TextField` (`:4583-4603`) lacks `onTapOutside`,
and no unfocus `GestureDetector` wraps the tab.

### Fix (applies to all race chats, fixing the tournament report)
1. `keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag` on the chat
   `ListView` (`:4482`).
2. `onTapOutside: (_) => FocusScope.of(context).unfocus()` on the composer
   `TextField` (`:4583`) — house pattern per `display_name_screen.dart:295`.
   Ensure tapping the send button still works (unfocus must not swallow the tap;
   send button is not "outside" handling — verify on device/simulator).
3. Do **not** wrap the whole screen in a global unfocus `GestureDetector` — the race
   detail screen has many interactive layers; scope the change to the chat tab.

---

## API contract

No new endpoints. Changes are behavioral:

| Endpoint | Change | Old-client impact |
|---|---|---|
| `GET /races/:raceId/messages` | SYSTEM items exclude `MYSTERY_BOX_OPENED` (DB-level `notIn`, alongside existing `POWERUP_IMPOSTER`) | Feed items disappear; renderers show server text verbatim — safe |
| `POST /races/:raceId/powerups/redeem` | New pre-flight rejections: `409 {error, code:"SIGNAL_JAMMED"}`, `409 {error, code:"RAINSTORM_ACTIVE"}`, `400 {error, code:"NO_ELIGIBLE_TARGETS"}` | Old clients toast `error` string (already handled path); `code` additive |
| `POST /races/:raceId/powerups/:id/use` | Rainstorm check becomes per-caster; error copy "Your Rainstorm is already active…" | Same 400 shape; copy change only |
| Push notifications | `POWERUP_USED` push suppressed when `targetUserId === userId`; no new pushes | Suppression is invisible to clients |

## Data model / migrations

**None.** No schema changes. One manual prod data repair (B3, Q4) executed by hand,
not by migration.

## Backward-compat & rollout

1. **Deploy backend first** (B1, B2, B3 pre-flight, B4 decision). All three user-facing
   backend fixes benefit every frozen app version immediately.
2. Frontend fixes (B3 copy, B5, B6, B7) ride the next App Store/Play build alongside
   the already-pending uncommitted work; iOS + Android in lockstep.
3. No feature flags needed except: if Q2 adds a *new* push route case the client
   doesn't know, gate it dark (env flag) until the carrying build rolls out.

## Test plan (tests FIRST, integration-first; never against prod DB)

Backend (`test/integration/`, real HTTP + test Postgres):
1. **B1:** seed a race, open a mystery box via the real endpoints, then
   `GET /races/:id/messages?kind=SYSTEM` and merged (no `kind`) → no
   `MYSTERY_BOX_OPENED` item, no description containing the rolled powerup name from
   the normal-open path; `POWERUP_EARNED` milestone events still present. Fanny-pack
   auto-activate open (full inventory) writes a `MYSTERY_BOX_OPENED` row (hidden
   from feed) and the slot increment still happens; the admin box-opener metric
   counts it.
   Pagination test: seed > pageLimit box-open events interleaved with other events →
   pages stay full and `nextCursor` walks the full feed (regression for the
   JS-filter under-fill).
2. **B2:** integration: A uses SHORTCUT on B who holds an active MIRROR → assert via
   a captured push-sender stub that **no** push goes to A claiming theft from A;
   (if Q2 yes) assert the reflect push content/recipient. Assert unreflected
   SHORTCUT still pushes B.
3. **B3:** with an active rainstorm in the race, `POST …/redeem` (RAINSTORM) → 409
   `RAINSTORM_ACTIVE`, `user_powerup_items.quantity` unchanged, no new
   `race_powerups` row. Same for jammed caster → 409 `SIGNAL_JAMMED`. Happy-path
   redeem still works.
4. **B4:** two different users each cast RAINSTORM → both succeed; same user
   twice → 400 "Your Rainstorm is already active…"; victim under two storms scores
   at exactly 0.5x (not 0.25x) through the real steps-sync path; redeem pre-flight
   allows user B to redeem while user A's storm is active.
Frontend (widget/integration tests pumping real screens):
5. **B5:** pump race detail with a HELD `POCKET_WATCH` → open sheet → DISCARD button
   exists; tapping it calls the discard API (mock at the HTTP boundary) and removes
   the item from the rail.
6. **B6:** pump races tab with counts → count is inside a badge widget (find by key
   `personal-state-count-*` and assert its ancestor decoration), pill height
   unchanged, double-digit count renders.
7. **B7:** pump race detail chat tab, focus the composer → drag the message list →
   `FocusScope` loses focus; tap outside the field → unfocused; tapping send with
   text still sends.
Existing tests: **never modified or deleted**; surface any that look wrong.

## Acceptance criteria / definition of done

- [ ] Activity feed (messages endpoint, both `kind=SYSTEM` and merged) never shows
      what a mystery box contained; milestone "earned a box" events still show.
- [ ] Feed pagination returns full pages across stretches of box-open events.
- [ ] Reflected offensive powerups produce no self-push for the attacker
      (SHORTCUT, LEG_CRAMP, RED_CARD, WRONG_TURN); normal attack pushes unchanged.
- [ ] Redeeming a RAINSTORM that cannot be cast is rejected *before* inventory is
      spent; the item remains in the global stash.
- [ ] Per-caster Rainstorm limit live; overlapping storms clamp victims at exactly
      0.5x (end-to-end scoring test proves it).
- [ ] Pocket Watch sheet has a working DISCARD with visual parity.
- [ ] Races-tab pill counts render in circular badges in selected + unselected states.
- [ ] Chat keyboard dismisses on drag and tap-outside in regular and tournament
      matchup races; send button unaffected.
- [ ] Backend deployed to staging + prod before any app build; iOS + Android built in
      lockstep for the frontend items.
- [ ] All new tests written first, failing for the right reason, then green;
      `test:unit`/`test:integration` (never bare `npm test`), never against prod DB.

## Owner decisions (interview 2026-07-21 — all resolved, zero open questions)

- **Q1 (B1):** Hide the fanny-pack auto-activate reveal. (Owner asked how a Leech
  could auto-activate — it can't; only `FANNY_PACK` auto-activates, see B1 root
  cause. Implemented by switching that branch's eventType to `MYSTERY_BOX_OPENED`.)
- **Q2 (B2):** Suppress only; no replacement reflect push.
- **Q3 (B4):** Per-caster limit; overlapping storms clamp victims at 0.5x.
- **Q4 (B3):** No prod repair of already-stranded Rainstorms.

## Revision log

- **Pass 1 (fresh-eyes):**
  - Moved B1's filter from JS post-fetch to the DB query after spotting that the
    existing pattern under-fills pages and can falsely terminate pagination when a
    page is dense with filtered events; added a pagination integration test.
  - Added the whitelist enumeration to B2 (bug covers LEG_CRAMP/RED_CARD/WRONG_TURN,
    not just SHORTCUT) and a check on the reflected `POWERUP_USED` *feed* row text.
  - Pinned B4's stacking clamp (0.5x once) as an explicit spec item — the naive
    per-caster change would silently quarter victims' steps.
  - Noted the new-push-route-case "ship dark" rule for Q2 (reminder-push precedent).
- **Pass 2 (fresh-eyes):**
  - B3: pre-flight added the `NO_ELIGIBLE_TARGETS` rainstorm condition, not just
    jam/active — any doomed use must fail before inventory spend; also required
    B3's redeem check to track whatever concurrency rule Q3 picks.
  - B3: clarified old-client behavior on the new 409 (existing toast path — verified
    client code path `race_detail_screen.dart:1590-1593`).
  - B6: added constraints — keep existing widget `Key`s (tests), min-width circle for
    two-digit counts, no pill-height change; explicitly excluded `_RaceMetricText`.
  - B7: scoped dismissal to the chat tab only (global unfocus wrapper risks breaking
    the screen's other gesture layers) and added a send-button-tap regression check.
  - Test plan: added explicit "milestone POWERUP_EARNED still visible" assertion so
    B1's fix can't over-filter.
- **Pass 3 (post-interview):**
  - Folded in all four owner decisions (Q1–Q4); removed conditional branches.
  - B1: replaced "genericize description" with the cleaner eventType switch to
    `MYSTERY_BOX_OPENED` after confirming only Fanny Pack can auto-activate — also
    fixes the admin box-opener metric undercount; added metric-counting check.
  - B4: added the "caster is still a normal victim of others' storms" clarification
    and required B3's redeem pre-flight to use the same per-caster rule.
