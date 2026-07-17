# Feature Batch — 2026-07-17 (combined spec)

**Status:** DRAFT — awaiting Rohan's approval. Nothing touches code until approved.
**Delivery mode chosen:** one combined spec covering all 12 items; approve the whole thing, then build.
**Interview:** complete (decisions folded in below).

This doc covers 12 items. Each item carries the CLAUDE.md template sections that apply
to it (summary/user story, scope/non-goals, API contract, data model, frontend plan,
backward-compat & rollout, test plan, acceptance criteria). Brainstorm items (#3, #12)
carry options + a recommendation instead of a pinned contract.

**The #1 hard rule threaded through every item:** a shipped app binary is frozen and the
prod backend serves *all* app versions at once. Every backend change keeps a compat path
for older clients; every new frontend dependency on a backend field degrades safely when
the field is missing. New powerups / cosmetics / features gate `testOnly` or behind a
client-feature header until the carrying App Store build has rolled out (~a week, phased).

**Contract-first sequencing (Phase 5):** the backend agent pins & lands each item's API
contract before the frontend agent codes against it. Both agents write tests FIRST, never
edit/delete existing tests, and never point tests at the prod DB.

---

## Global build order & risk map

| # | Item | Type | Repos | Deploy risk |
|---|------|------|-------|-------------|
| 1 | Open All Boxes | Feature | BE + FE | Med (new batch-open endpoint) |
| 2 | Leech + Defense Scanner powerups | Feature | BE + FE + art | High (scoring model) |
| 3 | Disable Imposter for now | Decision | BE only | Low (env-gated, reversible) |
| 4 | Invite links flawless (iOS focus) | Bug/hardening | BE + FE + native config | Med |
| 5 | Featured row: drop future races | Tweak | FE only | Low |
| 6 | Rainstorm badge in team races | Bug | FE only | Low |
| 7 | Onboarding auto-enroll redesign | Feature | FE only (BE already done) | Low |
| 8 | Remove `?` button (sun overlap) | Tweak | FE only | Low |
| 9 | Admin stat: unique box-openers/day | Feature | BE + FE | Med (needs new logging) |
| 10 | Daily spin: cap powerup share | Tweak | BE only | Low |
| 11 | Tournament detour → `???` | Bug | BE + FE | Low |
| 12 | Native ads on bracket | Brainstorm | FE (+ ad config) | Low |

**Recommended deploy sequence:** backend items first (2, 9, 10, 11, plus #1's batch
endpoint and #4's landing page), each behind a client-feature gate or additive-only;
then the app build (iOS + Android in lockstep) carrying all frontend items. Items 5, 6,
7, 8, 12 are frontend-only and ride the same build.

---

## Item 1 — "Open All Boxes" button (race detail)

### Summary & user story
As a racer with several unopened mystery boxes, I tap **Open All** and watch every box's
reel spin **simultaneously** in a grid, instead of tapping through them one at a time.

### Decisions (from interview)
- Layout: **grid of reels, all spin on one tap**, and **include queued/overflow boxes**.

### Scope / non-goals
- In scope: a multi-reel screen; a single "spin all" trigger; opening slot boxes **and**
  queued overflow boxes in one action; per-reel result reveal + aggregate summary.
- Non-goals: changing box odds, changing single-open UX (kept as-is), auto-activating
  results (except the existing Fanny-Pack auto-activate path, unchanged).

### Current state (cited)
- Inventory + slots: `lib/screens/race_detail_screen.dart:3707` `_buildInventoryContent()`;
  slots render `ItemSlot(state: mysteryBox)` with `onTap → _openMysteryBox(pw['id'])`
  (`:3723-3732`).
- Queued overflow count: `_queuedBoxCount` (`:309`, from `_powerupData['queuedBoxCount']`
  at `:677`), shown via `_queuedBoxesChip()` (`:3683-3705`). **Queued boxes have no
  client-side ids today** — they are a count only.
- Single open: `_openMysteryBox(boxId)` (`:3517`) pushes `CaseOpeningScreen`
  (`case_opening_screen.dart:149`) with a **deferred** `openMysteryBox:` closure — the
  server roll fires from inside the reel's swipe gate, not on screen open.
- Reel engine: `CaseOpeningReel` (`lib/widgets/case_opening_strip.dart:13-374`): own
  `AnimationController` (4000ms, `easeOutQuart`), `_startSpin()` awaits `onSpinRequested`
  (the server roll) **before** `_controller.forward()`. Already parameterized
  (`itemCount`, `resultIndex`, `itemBuilder`, `onSpinRequested`, `onComplete`).
- Open API: `BackendApiService.openMysteryBox()`
  (`lib/services/backend_api_service.dart:1739-1752`) → `POST
  /races/{raceId}/powerups/{powerupId}/open`, returns `{result:{type,rarity,autoActivated}}`.
- Backend open command: `stepv2-backend/src/commands/openMysteryBox.js` (flips
  `RacePowerup` MYSTERY_BOX→HELD/USED, fills type/rarity).

### API contract (NEW — backend agent pins first)
Queued boxes need materialized ids to be opened. Two-part contract:

**A. Batch-open existing slot + queued boxes**
`POST /races/{raceId}/powerups/open-batch`
Request: `{ "powerupIds": ["<id>", ...], "includeQueued": true, "maxCount": 20 }`
- `powerupIds`: explicit box ids to open (the slot boxes the client already knows).
- `includeQueued`: if true, the server also materializes and opens up to `maxCount`
  queued boxes for this user in this race (server owns queued-box identity).
Response:
```json
{
  "results": [
    { "powerupId": "abc", "type": "SPEED_BOOST", "rarity": "RARE", "autoActivated": false, "queued": false },
    { "powerupId": "def", "type": "COINS",       "rarity": "COMMON","autoActivated": false, "queued": true }
  ],
  "remainingQueuedBoxCount": 0,
  "powerupSlots": 3
}
```
- Each result mirrors the single-open shape so the frontend reveal reuses existing code.
- Server enforces `maxCount` cap (default 20) and returns only boxes it actually opened.
- Idempotency: reuse the single-open transactional guard per box; a re-sent request with
  already-opened ids returns their existing type/rarity rather than erroring (defensive).

**Backward-compat:** additive new endpoint. Old app binaries never call it; they keep
using single `.../open`. New app + old backend (during phased rollout window before this
BE deploys): the frontend **must feature-detect** — if the batch endpoint 404s, fall back
to firing N parallel single `.../open` calls for the known slot ids and simply omit queued
boxes from "Open All" (they can't be opened without ids on an old backend). Gate the
"include queued" affordance behind the presence of the endpoint.

### Frontend plan
- New `MultiCaseOpeningScreen` (variant of `CaseOpeningScreen`) laying out N
  `CaseOpeningReel`s in a responsive grid (2-wide phones; scrollable if many).
- Add a programmatic start path to `CaseOpeningReel._startSpin` (today it only starts on
  swipe/tap) so one "SPIN ALL" button (or auto-start on screen open) triggers every reel.
  Each reel keeps its own `onSpinRequested` closure resolving to that box's result from
  the single batch response (resolve the batch call once, then hand each reel its slice).
- States: loading (awaiting batch response), all-spinning, settling, done → an aggregate
  summary sheet ("You opened N boxes: …"). Empty/error: if batch fails, show a retry and
  fall back to sequential single opens.
- Entry point: an **Open All** button near `_queuedBoxesChip()` /
  `_buildInventoryContent()` header, visible only when ≥2 openable boxes exist. Reuse
  `_optimisticallyApplyBoxOpen` per result, then `_loadProgress()` on close.
- iOS + Android identical (pure Dart/Flutter).

### Test plan (tests first)
- BE integration: batch-open opens exactly the requested slot ids + up to `maxCount`
  queued; respects cap; idempotent on re-send; never opens another user's boxes; returns
  correct `remainingQueuedBoxCount`.
- BE unit: queued-box materialization picks the right rows; transactional roll per box.
- FE widget: multi-reel screen starts all reels on one trigger; renders N results; falls
  back to sequential single-open when the endpoint 404s; aggregate summary correct.

### Acceptance criteria
- [ ] One tap spins all openable boxes (slots + queued) simultaneously.
- [ ] Results match what single-open would have produced; inventory updates correctly.
- [ ] Old backend (pre-deploy): "Open All" still works for slot boxes via fallback.
- [ ] No double-open / lost boxes under retry.

---

## Item 2 — Two new store powerups: Leech + Defense Scanner

### Summary & user stories
- **Leech:** As a racer I buy Leech, pick one rival, and for **30 minutes every step *I*
  take also removes one step from that rival** (1:1, up to 3000). I keep my own steps; the
  rival's total shrinks the more I walk. It's a walk-to-sabotage debuff, not a transfer —
  I don't pocket the removed steps.
- **X-Ray (defense scanner):** As a racer I use X-Ray and instantly see, for **all
  opponents at once**, who currently has an active defense up (Compression Socks shield,
  Mirror) and when it expires — so I know who's safe to attack.

### Confirmed values (from interview)
- Leech: **1:1 leecher-driven debuff** — each step the leecher takes during the window
  removes 1 step from the target. **Duration 30 minutes.** **Hard cap 3000 steps removed
  per Leech.** Leecher keeps their own steps and does NOT gain the removed ones. **Max 2
  concurrent leechers per victim** (gang-stall guard → worst case −6000). Blocked by
  Compression Socks; NOT reflected by Mirror. Price **300 coins**.
- Scanner shipped name: **X-Ray**, `powerupType = DEFENSE_SCAN`. Price **150 coins**.

### Decisions (from interview)
- Leech mechanic: **leecher-driven 1:1 debuff** — for the duration, every step the
  *leecher* takes removes one step from the chosen rival (leecher keeps own steps, does NOT
  gain the removed steps). Pure sabotage tied to the leecher's own walking.
- Scanner: **reveals all opponents' active defenses** in one use.
- Art: **generate both powerup icons via the Codex `$imagegen` pipeline** (do NOT
  hand-draw), style-matched to existing `assets/images/powerups/*.png`.

### Scope / non-goals
- In scope: two new `POWERUP_TYPE`s, shop catalog entries, purchase, use/apply, scoring
  (Leech only), a client-side reveal UI (Scanner), icons, client-feature gating.
- Non-goals: rebalancing existing powerups; making Scanner reveal offensive effects (it's
  defenses-only per decision); Leech stacking beyond the rules below.

### Current state (cited)
- Additive scoring: `stepv2-backend/src/queries/getRaceProgress.js:604`
  `total = max(0, baseAdjusted - frozenSteps + buffedSteps - 2*reversedSteps +
  globalBoostedSteps + bonusSteps)`; effect accumulation `computeEffectModifiers` (~`:121`).
- Rainstorm precedent (fan-out to victims, per-victim shield check, additive -0.5x folded
  into `frozenSteps`): use handler `usePowerup.js:999-1080`; scoring `getRaceProgress.js:287-350`.
- Shop powerup type set: `usePowerup.js:44` `SHOP_POWERUP_TYPES = [IMPOSTER, RAINSTORM,
  SIGNAL_JAMMER]`; durations `:55-64`; targeted set `:51`.
- Shield/defense primitives: `COMPRESSION_SOCKS` (shield) + `MIRROR` (reflect), precedence
  documented in `stepv2-backend/POWERUPS.md:82-127`.
- Catalog model: `stepv2-backend/src/models/powerupShopItem.js`; catalog query
  `getPowerupShopCatalog.js` (Signal Jammer gated by `jammer` client feature, `:33-36`).
- Purchase: `purchasePowerupItem.js` (atomic debit + inventory upsert + ledger).
- Active-effects payload to client: `getRaceProgress.js:735-749` (`activeEffects` entries:
  `type,expiresAt,onSelf,targetUserId,sourceUserId`).
- FE store: `lib/screens/tabs/shop_tab.dart:205` `_purchasePowerup`; icon map
  `lib/widgets/powerup_icon.dart:20-45`; catalog fetch `backend_api_service.dart:2004`.

### Data model / migrations
- Add enum values `LEECH`, `DEFENSE_SCAN` (name TBD) to the `PowerupType` enum (Prisma +
  DB). Enum-add is additive and safe for old clients (they just never send/receive them,
  and defensive reads ignore unknown types — verify FE `powerup_icon.dart` has a fallback
  icon for unknown types; add one if missing so an old client can't crash on a new type).
- Two new `powerupShopItem` rows (sku, name, description, priceCoins, powerupType). Seed
  via the backend's catalog seed path. **Prices (confirmed):** Leech **300 coins**; X-Ray
  **150 coins** (info-only, cheaper). Ship both gated by a new client feature (single
  `powerups2` feature covering both) so old binaries never see them in the catalog until
  the app ships.
- Leech needs a timed effect row analogous to rainstorm (`LEECH` effect, **30 min**
  duration, `sourceUserId`=leecher, `targetUserId`=victim). The effect must record the
  **leecher's step baseline at activation** (or the scorer derives it from the leecher's
  step history) so the debuff = leecher's steps accrued *during* `[start, min(now, end)]`,
  capped at 3000. Add `LEECH` to the durations map (`usePowerup.js:55-64`) at 30 min.
  Scanner is **instantaneous**, grants **no** timed effect (see below) — it's a query.

### API contract (backend pins first)

**Catalog** — `GET /shop/powerups` gains the two items **only when** the client advertises
the gating feature (mirror the Signal-Jammer filter at `getPowerupShopCatalog.js:33-36`):
```json
{ "sku": "leech", "name": "Leech", "description": "Siphon a rival's steps to you for 1 hour.", "priceCoins": 300, "powerupType": "LEECH" }
{ "sku": "xray",  "name": "X-Ray", "description": "Reveal every opponent's active defenses.",   "priceCoins": 150, "powerupType": "DEFENSE_SCAN" }
```

**Leech use** — reuses `POST /races/{raceId}/powerups/use` with
`{ "powerupType": "LEECH", "targetUserId": "<rival>" }`. Targeted (enemy-only in team
races). Blocked by victim's Compression Socks (like rainstorm); **Mirror does NOT reflect
Leech** (put it in `SHOP_POWERUP_TYPES` so Mirror skips it, matching
rainstorm/jammer/imposter). Leech creates a `LEECH` effect (`sourceUserId`, `targetUserId`,
`expiresAt = now + 30min`, plus the leecher's step baseline).

**Victim visibility (confirmed): NOT stealthy.** On use, the backend must (a) include the
`LEECH` effect in the **victim's** `activeEffects` (targetUserId=victim) so a badge renders
on their row — including in team races (#6), and (b) **send the victim a push
notification** ("🩸 You're being leeched by <attacker>! Keep moving.") via the existing
push path used by other offensive powerups. The attacker's identity IS shown to the victim
(consistent with rainstorm). This prevents a new "why are my steps dropping?" confusion —
the anti-confusion theme of this batch. Also write a race-feed event (like other offensive
powerups) so it's legible.

**Scanner use** — reuses the use endpoint with `{ "powerupType": "DEFENSE_SCAN" }` (no
target). Because it's an instantaneous intel read, the **response** carries the reveal:
```json
{
  "ok": true,
  "scan": {
    "expiresAtSnapshot": "2026-07-17T18:00:00Z",
    "opponents": [
      { "userId": "u1", "displayName": "Otter42", "defenses": [ { "type": "COMPRESSION_SOCKS", "expiresAt": "..." } ] },
      { "userId": "u2", "displayName": "Capy7",   "defenses": [] }
    ]
  }
}
```
- The scan reads current shield/mirror effects for all opponents at call time. It consumes
  one Scanner from inventory. It writes **no** effect visible to others (silent recon).
- Backward-compat: additive. Old clients never send `DEFENSE_SCAN`; the endpoint rejects
  unknown types today, so guard the new branch behind the type existing. A new client on
  an old backend: use call returns an error → FE shows "not available yet" and does not
  offer the item (feature-gated anyway).

### Scoring (Leech) — `getRaceProgress.js`
- Add a `LEECH` branch. Unlike rainstorm (victim-driven), Leech is **leecher-driven**: for a
  victim V with an active Leech from source S, compute the number of steps **S accrued during
  the leech window** `[start, min(now, start+30min)]` and **subtract that count from V's
  total** (add it to V's `frozenSteps`), capped at **3000** per Leech. The leecher S gains
  nothing here — S's own steps already count normally; there is no `buffedSteps` add (this is
  a pure debuff, not a transfer).
  - Implementation: reuse the per-user step-history/delta the scorer already computes for
    rainstorm/reverse windows. `leechDebuff(V) = Σ over active leeches on V of
    min(3000, stepsOf(S) during that leech's window)`.
- **Balance guardrails (confirmed):**
  - Hard cap **3000 steps removed per Leech**.
  - Stacking: at most one active Leech per (source→victim) pair; a victim can be leeched by
    **at most 2 sources at once** (gang-stall guard) → worst-case −6000.
  - Suspend the debuff accrual during the victim's own frozen/reversed windows if it would
    double-penalize (match rainstorm's suspension logic `:317-350`); the debuff floors the
    total at 0 (`max(0, …)` already at `:604`).
  - Compression Socks blocks Leech application (victim protected) — consistent with rainstorm.
  - Because it keys off the *leecher's* steps, a leecher who doesn't walk drains nothing —
    the powerup rewards the buyer's own activity.

### Frontend plan
- Store: both items appear automatically from the gated catalog; `shop_tab.dart` renders
  them via the existing map-based flow (no new Dart model). Add icons to
  `powerup_icon.dart:20-45` type→asset map.
- **Icons via Codex `$imagegen`** (per CLAUDE.md — never hand-draw): generate
  `assets/images/powerups/leech.png` and `.../defense_scan.png` matching the existing
  powerup-icon look (study `rainstorm.png`, `signal_jammer.png`, `imposter.png` as refs;
  these are UI icons, not side-profile capy accessories — match *their* framing, not the
  accessory rules). Generate into scratch, critique on white, install after approval.
- Leech usage UX: reuse the existing **targeted-powerup** picker (same flow as
  rainstorm/imposter targeting) to choose the rival. **Victim side:** render the Leech
  badge (with attacker name in the tooltip) via the `activeEffects` → effect-icon path
  (must also render in team races — see #6), and handle the incoming push notification
  (deep-link into the race). Attacker side: optionally show how many steps drained so far.
- Scanner UX: on use, present a **recon sheet** listing opponents and their active
  defenses (shield/mirror icon + countdown), "no defenses up" state per opponent, and an
  empty state. It's an ephemeral modal fed by the use-response `scan` object — degrade
  safely if `scan` is missing (old backend): show "Recon unavailable."
- iOS + Android identical.

### Backward-compat & rollout
- Deploy backend first (enum + catalog + use handlers + scoring), items gated by client
  feature so no old client sees them. Then ship the app (iOS + Android lockstep) that
  advertises the feature + bundles the two icons. Only after the App Store build rolls out
  (~a week) are the items reachable by real users. `powerup_icon.dart` gains an unknown-type
  fallback so any client is crash-safe against unknown powerup types.

### Test plan (tests first)
- BE unit: Leech scoring math (debuff = leecher's in-window steps, 3000 cap, 30-min window
  boundary, floors at 0, suspension during victim frozen/reversed, 2-leecher stacking cap,
  leecher-who-doesn't-walk drains nothing); Compression Socks blocks Leech; Mirror does not
  reflect Leech; leecher gains no bonus steps.
- BE integration: purchase both; Leech use creates the effect + affects both totals;
  Scanner use returns correct defense snapshot for all opponents and consumes inventory;
  team-race enemy-only targeting for Leech.
- FE widget: store shows items only when feature-gated on; Leech targeting picker;
  Scanner recon sheet renders defenses/empty/missing states; unknown-type icon fallback.

### Acceptance criteria
- [ ] Leech: each leecher step removes 1 from the chosen rival for 30 min, capped at 3000;
      leecher keeps own steps and gains no bonus; blocked by shield; not reflected by Mirror;
      max 2 leechers per victim.
- [ ] Scanner reveals all opponents' active defenses in one use, consumes one, reveals
      nothing to others.
- [ ] Both icons generated via imagegen, style-matched, installed.
- [ ] Old clients never see or crash on the new types.

---

## Item 3 — Disable Imposter for now (decision made)

### The problem (diagnosed)
Imposter today is **purely cosmetic**: `usePowerup.js:972-996` self-applies an `IMPOSTER`
effect storing `metadata.swapWithUserId`; the display swap happens only in the read path
`getRaceProgress.js:756-829` — it swaps two users' **leaderboard array slots** for all
viewers, **but each row keeps its own real name and real steps**, settlement ignores it
(`:757,:976`), and it writes **no feed event** (`:992-995`) and shows **no on-row
indicator**. A user "moves up" visually yet still displays their own lower step count and it
changes nothing about who wins — the mismatch between "swap positions" and "rows still show
truth" is the confusion engine driving the prod complaints.

### Decision (from interview): **disable Imposter for now** — stop selling it and make it
inert, leaving a clean re-introduction/rework for later (the fuller brainstorm options —
legibility fixes, real identity-disguise, or full replacement — are parked, not chosen).

### Scope / non-goals
- In scope: remove Imposter from the shop catalog going forward; make its use a safe no-op
  so no one can activate a confusing swap; hide the dead item from inventory on the new
  build; do it without breaking anyone.
- Non-goals: no refunds/inventory migration (see compat), no new mechanic, no copy rewrite
  beyond hiding it. Re-enable is a future item.

### Plan (backend-first, additive/gated)
1. **Remove from catalog.** In `getPowerupShopCatalog.js`, filter out `IMPOSTER` (same
   pattern as the Signal-Jammer feature filter `:33-36`, but unconditional) so no client
   version — old or new — is offered Imposter anymore. This alone stops new purchases across
   all app versions immediately on deploy.
2. **Neuter the effect.** In the read path `getRaceProgress.js:756-829`
   (`collectRaceIllusions` / the slot-swap at `:818-829`), gate the swap behind a kill flag
   (env `IMPOSTER_ENABLED=false`, default off) so **existing** held/active Imposters stop
   swapping rows — killing the confusion for everyone at once, regardless of app version.
3. **Reject new use.** In `usePowerup.js:972-996`, when disabled, reject an `IMPOSTER` use
   with a friendly "temporarily unavailable" error (or silently consume-and-noop — prefer
   reject so the user keeps the item). Guard so it can't crash old clients that still show a
   "use" affordance.
4. **Hide from inventory on the new build (FE, confirmed).** On the new app version, hide
   IMPOSTER from the powerup inventory/store display entirely (no dead button). The item
   stays in the DB and is restored if we re-enable. Old app versions unavoidably still show
   it; the server-side reject (step 3) keeps them safe.

### Data model / migrations
- None. Existing `userPowerupItem` rows with `IMPOSTER` are **left in place** (no refund, no
  deletion) — they simply become unusable while disabled, and re-enabling later restores
  them. This avoids a destructive/irreversible inventory change.

### Backward-compat & rollout
- **Backend-only, all handled server-side**, so it applies to **every frozen app version at
  once** on deploy — the ideal shape for killing a live complaint. Old clients may still
  render Imposter in a cached catalog view until refetch, and may show a "use" button;
  server rejects the use gracefully. No client change strictly required, though the app
  build should also drop Imposter from any hardcoded FE lists if present (verify
  `race_detail_screen.dart:98/126` name/description maps aren't the sole catalog source —
  they're display maps, safe to leave).
- Env-gated (`IMPOSTER_ENABLED`) so we can re-enable instantly if we change our minds or
  ship a rework.

### Test plan (tests first)
- BE unit/integration: catalog omits IMPOSTER; a use request for IMPOSTER is rejected when
  disabled and the item is NOT consumed; the read path performs no slot-swap when disabled;
  existing IMPOSTER inventory rows are untouched.

### Acceptance criteria
- [ ] Imposter no longer purchasable on any app version.
- [ ] Active/held Imposters no longer swap leaderboard rows (confusion gone).
- [ ] New app build hides the dead Imposter item from inventory.
- [ ] No inventory destroyed; re-enable is a single env flip.

---

## Item 4 — Make all invite links flawless (iOS tournament repro)

### Summary
A shared **tournament** invite on **iOS** "opened the app, then opened Safari with the
prompt to open the app" — i.e. the universal link was **not honored**, falling back to the
Safari landing page which re-prompts via the custom scheme. Make the whole invite flow
(race `/r/`, referral `/r/BARA-`, tournament `/t/`) flawless.

### Decision (from interview): **iOS focus** for the repro; but harden all invite types.

### What we verified (so we don't chase the wrong thing)
- **AASA is correct and live on BOTH hosts.** `https://steptracker-api.org/.well-known/
  apple-app-site-association` and `https://barastep.com/.well-known/apple-app-site-
  association` both serve `appIDs:["4NRKZL9H5J.com.rohanchari.steptracker"]` with
  components `/r/*` **and** `/t/*`. So the AASA content is NOT the bug.
- iOS entitlements already list `applinks:barastep.com` + `applinks:steptracker-api.org`
  (whole-domain) — `ios/Runner/Runner.entitlements:28-32`.
- FE already routes `/t/`: `deep_link_service.dart:85` `_extractTToken`, drain
  `main_shell.dart:357-408` → `joinTournamentByShareToken` → `_openTournament`.
- Share URL host = `PUBLIC_BASE_URL` (`sharing.js:6`, default `steptracker-api.org`;
  possibly overridden to `barastep.com` in prod env).

### Ranked iOS root-cause candidates (investigation, in order)
1. **Frozen-client / capability gap (most likely).** If the currently-installed App Store
   build predates tournament deep-link handling — OR was built before
   `applinks:barastep.com`/`steptracker-api.org` (or the Associated Domains capability on
   the App ID + provisioning profile) was in place — iOS won't hand `/t/` to that binary,
   so it bounces to Safari. **Action:** confirm the shipped build's entitlements + that the
   App ID has Associated Domains enabled and the App Store provisioning profile includes
   it. If the fix only exists in a newer build, this is only fully resolved once that build
   rolls out (~a week, phased) — the #1 rule bites here. The graceful fallback (item below)
   is what protects users in the meantime.
2. **AASA CDN propagation / association staleness.** Apple's CDN caches AASA; a recently
   added `/t/` or a freshly associated domain can lag. **Action:** confirm via a clean
   reinstall on a device that the app associates `/t/` (Xcode "Associated Domains"
   diagnostics / `swcutil`), and that both hosts return AASA with `Content-Type:
   application/json` and no redirect.
3. **Per-domain "open in Safari" preference.** Once a user taps the domain breadcrumb / long-
   press-opens in Safari, iOS remembers and stops opening the app until they use the in-app
   "Open" banner. **Action:** document; the fallback landing page must offer a reliable
   custom-scheme "Open in app" button (it does today — that's the prompt they saw).
4. **Host mismatch.** Confirm which host prod actually mints tournament links with
   (`PUBLIC_BASE_URL`) and that that exact host is in the entitlement (both are) and serves
   AASA (both do). Low likelihood given the verification above, but confirm the env value.

### The concrete fixes (regardless of which candidate)
1. **Dedicated tournament landing page.** Today `/t/` reuses the **race** landing renderer
   (`stepv2-backend/src/app.js:193-220` → `renderRaceLandingPage`), so the fallback shows
   generic race copy + "Open in app" for `bara://tournament/<token>`. Build a real
   `tournamentLandingPage.js` (parallel to `raceLandingPage.js`/`referralLandingPage.js`)
   with tournament-specific copy, the correct custom-scheme button, App Store/Play buttons,
   and OG tags. This makes the *unavoidable* fallback (frozen clients, per-domain prefs) a
   good experience.
2. **Android `/t/` App Link filter (parity/hardening).** `AndroidManifest.xml:63-75`
   `autoVerify` covers only `pathPrefix="/r/"`; add a `/t/` intent-filter so tournament
   links verify on Android too. (Ships in the app build.)
3. **Add the Play app-signing SHA-256** (`sharing.js:34` TODO) so App Links verify for Play
   Store installs across `/r/` and `/t/`. (Backend/env + assetlinks.)
4. **iOS verification checklist** baked into DEPLOYMENT notes: Associated Domains enabled on
   App ID; profile includes it; entitlements list both hosts; AASA reachable + JSON + no
   redirect on the exact `PUBLIC_BASE_URL` host.

### Backward-compat & rollout
- The landing page + assetlinks/Play key are **backend/config** — deploy anytime, they only
  improve the fallback and don't affect installed apps. The Android `/t/` filter ships in
  the app build (iOS + Android lockstep). The iOS capability/entitlement verification may
  require a new build; until it rolls out, frozen clients rely on the improved landing page.

### Test plan
- Manual device matrix (documented): fresh-install iOS tap `/t/` from Messages → app opens
  to tournament; same after "open in Safari" preference set → landing page → custom-scheme
  button opens app. Android `/t/` verified deep link opens app. `/r/` + referral regression
  pass on both platforms.
- BE: unit test the tournament landing renderer (correct token, copy, scheme URL, store
  links); assetlinks/AASA endpoints return expected JSON including the Play key.

### Acceptance criteria
- [ ] iOS `/t/` links open the app directly on a build with the capability in place.
- [ ] The Safari fallback is a tournament-specific page with a working "Open in app".
- [ ] Android `/t/` verifies and opens the app; Play-install `/r/` + `/t/` verify.
- [ ] `/r/` and referral links regression-clean on both platforms.

---

## Item 5 — Featured row: stop showing future races

### Summary & user story
Now that auto-join covers the next daily/weekly, the featured row no longer needs the
"upcoming/opt-in" card. As a user I see only the currently-active featured races.

### Current state (cited)
- `races_tab.dart:774` `_buildFeaturedSection()`; for each featured race it also renders an
  **upcoming** card when `race['upcoming']` exists — `_buildUpcomingCard(race, upcoming)`
  (`:797-801`, defined `:919-942`), a PENDING race with OPT-IN/countdown.
- Data: backend `getFeaturedRaces.js` attaches PENDING race as the additive `upcoming`
  field per seed (`summarizeUpcoming` `:64-83`, set `:127`).

### Plan (frontend-only, safest)
- Delete the upcoming-card branch at `races_tab.dart:797-801` (and stop calling
  `_buildUpcomingCard`; keep or remove the now-dead `:919-942` builder). Leave the backend
  `upcoming` field in place (harmless, and old clients still use it) — **do not** change
  `getFeaturedRaces.js`, so no old-client impact.
- Keep the auto-join gear/toggle in the featured header (that's the opt-out surface #7
  points users to).

### Backward-compat & rollout
Frontend-only; ships in the app build. Old binaries keep showing the upcoming card (fine).
No backend change → zero risk to other versions.

### Test plan
- FE widget: featured section renders only active cards; no upcoming card even when the
  payload still includes `upcoming`.

### Acceptance criteria
- [ ] No future/opt-in race card in the featured row; active featured races unaffected.

---

## Item 6 — Rainstorm (and all) powerup badges missing on opponents in team races

### Summary (bug)
In team races the rainstorm logo (and every powerup badge) doesn't show on opponents,
though it does in solo races.

### Root cause (cited)
- Solo path renders badges: `race_detail_screen.dart:_buildLeaderboardPlank` (`:5235`)
  filters `activeEffects` by row `userId` (`:5248-5253`) and passes `effectIcons:` into
  `LeaderboardPlank` (`:5271-5274`).
- **Team live view uses a different widget that renders NO effect icons:** `:3255`
  `_buildTeamTwoColumns` → `_teamRosterColumn` (`:5082`) → `_teamColumnCell`
  (`:5113-5216`) draws avatar + rank + name + steps only — no `activeEffects`, no
  `PowerupIcon`. The data IS in the payload (`getRaceProgress.js:735-749`; rainstorm not in
  `HIDDEN_FROM_OPPONENTS`).

### Plan (frontend-only)
- In `_teamColumnCell`, replicate the solo filter+render: filter `activeEffects` by that
  cell's `userId` and render the same `_EffectIconWithTooltip` badges (mirroring
  `:5248-5274`), laid out to fit the two-column cell.

### Backward-compat & rollout
Frontend-only; ships in the app build. No API change.

### Test plan
- FE widget: team-race cell shows an effect badge when `activeEffects` targets that user;
  none when empty; tooltip correct.

### Acceptance criteria
- [ ] Rainstorm (and other) badges appear on opponents in team races, matching solo races.

---

## Item 7 — Onboarding: auto-enroll + drop into the Daily race

### Summary & user story
As a new user I no longer pick a race during onboarding. I see "You're entered in the Daily
& Weekly challenge — turn it off anytime on the Races page," then land **straight in the
live Daily race**.

### Decision (from interview): **confirm → drop into the Daily race.**

### Critical finding — the backend already does the enrollment
`stepv2-backend/src/commands/autoEnrollNewUser.js` (called from `ensureAppleUser.js:90` +
the Google provisioner on account creation) already: sets `autoJoinFeaturedRaces:true`
(`:112-115`), enrolls the user into every seeded race ACTIVE+PENDING (daily+weekly,
`:117-136`), and grants the 3 welcome mystery boxes via the once-per-human
`OnboardingBoxGrant` ledger (`:47-104`). It **deliberately does not** set
`firstRaceOnboardingSeen` (`:19-27`) — which is why today's client still shows the redundant
"choose a race" step. **So this item is a frontend-only simplification.**

### Current state (cited)
- Onboarding steps: `lib/screens/onboarding_flow.dart:87-142`. Step 4 =
  `OnboardingFirstRaceStep` (class `:465-675`) — the "choose a race" step to replace.
- Routing: `main_shell.dart` `onJoinOnboardingRace → _joinOnboardingRace` (`:1343-1365`)
  → `_openRaceFromCard(raceId)` (`:1359`, pushes `RaceDetailScreen` `:1256-1272`);
  `onSkipFirstRace → _skipFirstRaceOnboarding` (`:1370`) sets `firstRaceOnboardingSeen`.
- The gate term: `firstRaceOnboardingSeen` in the `isOnboarding` condition
  (`main_shell.dart:1705-1744`).
- Daily race id: from `fetchFeaturedRaces()` where `seedKind == 'DAILY_10K'`
  (`getFeaturedRaces.js:106`, `SEED_RANK`).
- Auto-join opt-out surface to point users at: featured-row gear →
  `_FeaturedAutoJoinToggle` (`races_tab.dart:1873-1948`).

### Frontend plan
- Replace `OnboardingFirstRaceStep` with `OnboardingAutoEnrolledStep`: a confirmation
  screen — "You're in the Daily & Weekly challenge 🎉 / 3 mystery boxes waiting / turn
  auto-join off anytime on the Races page." Load the **mobile-design skill** before building
  it (per repo rules); make it juicy but on-brand.
- Primary CTA "Start the Daily challenge" → fetch the ACTIVE `DAILY_10K` race id via
  `fetchFeaturedRaces()`, call `markFirstRaceOnboardingSeenLocally()` +
  `_skipFirstRaceOnboarding()` (backend idempotent) to close the gate, then
  `_openRaceFromCard(dailyRaceId)`.
- **Degrade safely:** if no active daily race is returned (backend variance / different
  version), still close the gate and land on the Home tab with a gentle toast — never block
  onboarding on a missing race. Referral/pending-share deep link still takes precedence
  (keep the existing `_load()` auto-skip when a share token is pending).
- Since enrollment already happened server-side, **do not** double-join; this step only
  confirms + routes. Remove the now-unused "choose a race" fetch/join path if nothing else
  uses it (verify `_fetchOnboardingRaces`/`joinPublicRace(onboarding:true)` callers first).

### Backward-compat & rollout
Frontend-only; ships in the app build. Backend already correct in prod. Old binaries keep
the old choose-a-race step (harmless — enrollment already happened, so they just re-join
the same race or skip).

### Test plan
- FE widget: confirmation step renders; CTA closes the gate + routes into the daily race;
  missing-daily fallback lands home without blocking; pending-share deep link still wins.

### Acceptance criteria
- [ ] No race-picker in onboarding; user is auto-enrolled (already true server-side) and
      told they can opt out on the Races page.
- [ ] CTA drops the user into the live Daily race; safe fallback when none exists.

---

## Item 8 — Remove the `?` help button (sun overlap)

### Summary
The `?` help button is visually covered by the sun. The sun is **baked into the sky PNG**
(`home_hero_scene.dart:80-93`, `assets/images/home_hero_sky.png`), not a movable widget.

### Decision (from interview): **remove the `?` button for now.**

### Current state (cited)
- Button: `home_tab.dart:819-829` `Positioned(top: topInset+10, right:10, child:
  _HelpHeroButton(...))`; widget `_HelpHeroButton` `:1685-1730+`.

### Plan (frontend-only)
- Remove the `_HelpHeroButton` `Positioned` from the hero stack (`:819-829`). Verify nothing
  else depends on it (the help sheet it opens may still be reachable elsewhere — if the `?`
  was the only entry point, note that help is now unreachable from home; acceptable per
  "for now," but flag it). Keep `_HelpHeroButton` class or delete if fully unused (avoid a
  dead-code warning).

### Backward-compat & rollout
Frontend-only; ships in the app build. No API impact.

### Test plan
- FE widget: home hero renders without the help button; no layout/overlap regression.

### Acceptance criteria
- [ ] `?` button no longer present on the home hero; no visual artifact where it was.

---

## Item 9 — Admin stat: avg unique users who open a race box / day

### Summary & user story
As an admin I see "average unique users who open a **race (in-race mystery) box** per day"
in the admin stats.

### Decision (from interview): **in-race mystery box**, and accept that **we must add
logging now** — the metric is accurate only from the deploy forward (no history).

### Critical finding — the data does not exist today (cited)
- Opening a race mystery box (`openMysteryBox.js`) flips `RacePowerup` MYSTERY_BOX→HELD/USED
  and emits an **in-memory** `MYSTERY_BOX_OPENED` event that is **never persisted** (no
  handler in `eventHandlers.js`).
- `RacePowerupEvent` (`schema.prisma:1030-1045`) logs box **grants**, not the normal open
  path (only the rare Fanny-Pack auto-activate writes a row on open).
- `RacePowerup.updatedAt` is unreliable as "opened at" (bumped again on later use/upgrade);
  there is no `openedAt`.
- (For contrast, the **daily** spin box IS cleanly logged in `daily_reward_claims` — but the
  decision is the in-race box, so we add logging.)

### Data model / migrations
- **Add a persisted open event.** Cheapest: on the normal open path
  (`openMysteryBox.js:146`, after flipping the row), write a `RacePowerupEvent` row with
  `eventType:"MYSTERY_BOX_OPENED"`, `actorUserId`, `createdAt` (table already has
  `actorUserId` + `createdAt`, `schema.prisma:1030-1045`) — **no migration needed**, just a
  new event row on open. This gives `COUNT(DISTINCT actor_user_id) … GROUP BY ET date`.
  - Alternative (heavier, rejected): add an `openedAt` column to `race_powerups`.
- Backward-compat: additive event write; old clients still call the same open endpoint and
  now generate the event server-side — no client change required to start collecting data.

### API contract
- `GET /admin/stats` (`admin.js:153-161` → `getAdminStats.js`) gains one field under
  `activity`, e.g. `activity.avgUniqueBoxOpenersPerDay` (number, ET-day averaged). Computed:
  ```sql
  SELECT AVG(daily_users) FROM (
    SELECT (created_at AT TIME ZONE 'America/New_York')::date AS d,
           COUNT(DISTINCT actor_user_id) AS daily_users
    FROM race_powerup_events
    WHERE event_type = 'MYSTERY_BOX_OPENED'
    GROUP BY d
  ) t;
  ```
  (Anchored to `America/New_York` like the other metrics, `getAdminStats.js`.) Additive →
  old admin clients ignore the new field.

### Frontend plan
- `admin_screen.dart` `_AdminStatsCard` (`:274`, render `:353-429`): add a `_row('Avg box
  openers/day', '${activity?['avgUniqueBoxOpenersPerDay']}')` in the appropriate section
  (near the `TODAY`/activity rows `:402-408`). Null-safe (shows `—` if absent, since early
  on there's little/no data).
- Add the field to `fetchAdminStats` consumption (map read only; no model change).

### Backward-compat & rollout
Deploy backend (event logging + stat) first — data starts accruing immediately; the number
is meaningfully populated after a few ET days. Frontend row ships in the app build (or admin
web if applicable). Note in the UI that the metric is "since <deploy date>."

### Test plan (tests first)
- BE integration: opening a box writes a `MYSTERY_BOX_OPENED` event with the right
  `actorUserId`; the stat query averages distinct openers per ET day correctly across a
  seeded multi-day fixture; days with zero opens handled.
- FE widget: admin stat row renders the value; `—` when null.

### Acceptance criteria
- [ ] Every in-race box open logs a persisted event with user + timestamp.
- [ ] Admin stats show avg unique daily box-openers (ET), accurate from deploy forward.

---

## Item 10 — Daily spin: cap the powerup share so coins keep flowing

### Summary (not a bug — by-design crowding-out)
Adding powerups to the spin didn't lose coins; it changed the odds table. RARE used to fold
to 0 for users who owned all accessories (mass shifting into UNCOMMON **coins**); now
`powerupPoolSize>0` always, so RARE is alive at full odds (up to ~45% at high streak) and a
RARE pays a powerup/accessory, **not coins**. So high-streak / all-accessory users see far
fewer coin outcomes.

### Decision (from interview): **cap the powerup share** — keep a coins slice in the RARE
roll so coin flow returns, without touching accessory rewards.

### Current state (cited)
- Odds: `dailyBoxOdds.js` — `dailyBoxOddsForPool` (`:56-62`) keeps RARE alive if accessory
  OR powerup pool non-empty; `rollRarePrizeKind` (`:86-97`) picks ACCESSORY vs POWERUP
  (50/50 if both, else whichever stocked, `null` only if both empty → coins).
- Grant: `claimDailyRewardBox.js` — RARE→POWERUP `grantPowerupToUser` (`:119`, no coins);
  RARE→ACCESSORY `userShopItem.create` (`:128`, no coins); else `RARE_FALLBACK` coins
  (`:136-146`, now effectively dead).

### Plan (backend-only)
- In `rollRarePrizeKind` (`dailyBoxOdds.js:86-97`), introduce a **coins slice** in the RARE
  outcome: e.g. RARE resolves to `{ POWERUP: p, ACCESSORY: a, COINS: c }` with a tunable
  `RARE_COINS_SHARE` (proposed **~35-40%** of RARE hits pay `RARE_FALLBACK` coins instead of
  a powerup). This revives the `RARE_FALLBACK` coin branch (`claimDailyRewardBox.js:136-146`)
  and restores coin flow for high-streak users, while accessories are untouched.
- Keep accessory rewards prioritized when the user still has un-owned accessories (don't cap
  those away); the coins slice should mainly displace the **powerup** portion of RARE.
- Env-tunable share (like `AD_COIN_REWARD_AMOUNT` precedent) so we can adjust without a
  deploy: `DAILY_SPIN_RARE_COINS_SHARE`.

### Backward-compat & rollout
Backend-only; affects all app versions equally (the spin outcome is server-decided and the
frontend already credits `result['coins']` correctly — `daily_reward_screen.dart:296-298`).
No client change; safe for frozen clients. Deploy independently.

### Test plan (tests first)
- BE unit: with both pools stocked, RARE resolves to coins ≈ `RARE_COINS_SHARE` of the time;
  accessories still awarded when un-owned; env override respected; all-owned user now
  receives coins on a meaningful fraction of spins.

### Acceptance criteria
- [ ] High-streak / all-accessory users receive coins on a healthy share of spins again.
- [ ] Accessory rewards unaffected; share is env-tunable.

---

## Item 11 — Tournament detour → show `???` (not blank)

### Summary (bug)
A player detoured/masked in a tournament has their score **disappear** on the bracket with
no `???`, unlike the race leaderboard which shows `???` for hidden scores.

### Root cause (cited)
- Backend masks a masked/detoured player's steps to `null` in the tournament payload
  (`serializeTournament.js:110-114`, `viewerIsDetoured`/stealthed `:102-109`) but emits
  **no `stealthed`/masked flag** on the tournament player object (unlike the race
  leaderboard which sends `stealthed:true`).
- Frontend `Tournament.playerSteps` (`tournament.dart:354`) coalesces `null → 0`;
  `BracketSlot` (`tournament_bracket.dart:27`) has no masked field; `_filledSlot`
  (`tournament_bracket_board.dart:449-510`) only renders steps when `steps > 0` (`:501`) —
  so masked steps (0) render **nothing**, no `???`.
- The intended pattern is driven by a `stealthed` boolean: leaderboard plank
  (`leaderboard_plank.dart:195` `isStealthed ? '???' : formattedSteps`), race course
  (`race_detail_screen.dart:3113-3120`), races-tab placement (`races_tab.dart:1310-1315`).

### API contract (backend pins first)
- `serializeTournament.js:110-114` adds a masked flag on the player object, parallel to the
  race leaderboard: `{ userId, totalSteps: masked ? null : n, forfeited, stepsHidden: true }`
  (or reuse the existing `stealthed` name for consistency — **pick `stealthed` to match the
  race payload** so the frontend uses one convention).
- Backward-compat: additive boolean; old clients ignore it (they already render blank today,
  so no regression). New client + old backend (no flag yet): frontend must distinguish
  `totalSteps == null` from `0` itself as a fallback signal (see FE plan) so it shows `???`
  even before the backend flag ships.

### Frontend plan
- Stop coalescing `null → 0` for the masked case: carry a `stealthed`/`masked` bool onto
  `BracketSlot` (`tournament_bracket.dart:27`), set from the backend flag **or** from
  `totalSteps == null` (defensive, works pre-backend-deploy).
- In `_filledSlot` (`tournament_bracket_board.dart:501`), render `'???'` when
  `slot.stealthed` instead of hiding the value (mirror `leaderboard_plank.dart:195`).

### Backward-compat & rollout
Frontend can ship the `null → ???` inference immediately (works against current prod
backend). Backend flag is an additive hardening that makes intent explicit. Deploy order
flexible; frontend `null`-inference means we're not blocked on the backend.

### Test plan (tests first)
- BE unit: masked tournament player serializes with `stealthed:true` + `totalSteps:null`;
  unmasked unaffected.
- FE widget: bracket slot shows `???` when stealthed/`null`; shows the number otherwise;
  forfeit flag precedence unchanged.

### Acceptance criteria
- [ ] A detoured/masked player shows `???` on the bracket, matching the race leaderboard.
- [ ] Works against current prod backend via `null` inference; explicit flag added too.

---

## Item 12 — Native ads on the tournament bracket (BRAINSTORM)

### Summary & user story
ESPN/March-Madness-style: weave a sponsor/native ad into the bracket so it feels part of the
board, not a banner slapped on top.

### Decision (from interview): center on **bracket chrome / branding** placement.

### Current state (cited)
- Board: `lib/widgets/tournament_bracket_board.dart` — pannable/zoomable `InteractiveViewer`
  (`:178`); layout constants (`:39-49`); geometry `_computeGeometry` (`:73`); canvas
  `_buildCanvas` (`:209`) assembles round labels (`:232`), matchup boxes (`_centers`
  `:255-268`), champion cap (`:271-278`), elbow connectors (`_ConnectorPainter` `:600`).
  Whole board is a `Stack` of absolutely-positioned nodes sized by `_canvasSize` (`:112`).
- Existing native-ad plumbing exists in the app (native ad unit id is wired —
  `--dart-define=ADMOB_NATIVE_AD_UNIT_ID`, see README build flags), so we're not starting
  from zero on the ad SDK.

### Options (chrome/branding-focused)
**A. "Finals presented by" champion cap.** Brand the champion cap region (`:271-278`) — a
tasteful "Finals presented by <sponsor>" frame around the final/champion node. Highest-value
eyeball spot, minimal layout disruption.
**B. Framed board banner.** A sponsor banner integrated into the board's frame/header (near
round labels `:232`) styled in our parchment look — reads as "tournament brought to you by."
**C. Round-label sponsorship.** Sponsor woven into round labels (e.g. "Sweet 16 • <sponsor>")
— subtle, repeats down the board.

### Recommendation
**A (champion cap "presented by") + a parchment-framed banner (B) as the container.** The
champion cap is the natural hero moment and the least disruptive to the bracket geometry;
frame it in our style so it reads as branding, not an ad unit. Implement the sponsor content
as a **native ad** (using the existing native ad unit) rendered inside a parchment card
positioned in `_buildCanvas` as another `Positioned` child near the champion cap, so it
pans/zooms with the board. Keep it a single, classy placement — avoid peppering ads across
matchup nodes (reads cheap and hurts readability).

### Confirmed (from interview)
- **Labeled AdMob native ad** (via the existing `ADMOB_NATIVE_AD_UNIT_ID`) rendered in a
  parchment card positioned near the champion cap. **AdMob native-ad policy compliance is
  mandatory:** the card MUST carry the visible **"Ad"/Sponsored label + AdChoices icon**
  and use the required native-ad asset views (headline, media, CTA, advertiser) — do NOT
  disguise it as pure "Finals presented by" chrome (that would violate AdMob policy and
  risk the ad account). Style the parchment frame around a *properly labeled* native ad so
  it feels on-brand but is unambiguously an ad.
- House-ad fallback when no fill.
- **Gated behind the existing banner-ads remote kill switch** (AppSetting) — or a sibling
  remote flag — so we can disable instantly.

### Backward-compat & rollout
Frontend + ad config; ships in the app build; gate behind a remote flag. No API contract for
other versions. Load the **mobile-design skill** before building the placement.

---

## Cross-cutting: backward-compat & rollout summary

1. **Backend first, additive, gated.** New powerup types, batch-open endpoint, box-open
   logging, spin rebalance, tournament masking flag, tournament landing page — all additive
   and/or feature-gated so the prod backend keeps serving every frozen app version.
2. **Then the app build, iOS + Android in lockstep** — carries all frontend items (1 UI, 2
   UI+icons, 5, 6, 7, 8, 11 FE, 12), the Android `/t/` filter, and advertises new client
   features (`leech`/`scanner`/`powerups2`, batch-open capability).
3. **testOnly / feature gates** on the two new powerups until the App Store build rolls out
   (~a week, phased). Unknown-powerup-type fallback icon added so any client is crash-safe.
4. **Never point tests at prod DB; never edit/delete existing tests; tests-first** for both
   agents (backend `test:unit`/`test:integration`, never bare `npm test`).

## Phase-5 agent split (contract-first, then parallel)
- **Backend developer (Opus 4.8, medium):** owns and pins first — #2 enum+catalog+use+scoring
  (Leech 1:1 leecher-driven, 30m/cap3000/max2, X-Ray recon), #1 batch-open endpoint, #3 disable-Imposter (catalog filter
  + `IMPOSTER_ENABLED` kill + use rejection), #9 box-open logging + stat query, #10 spin
  rebalance, #11 masking flag, #4 tournament landing page + assetlinks/Play key. Writes tests
  first; keeps old-client compat paths.
- **Frontend developer (Opus 4.8, medium):** consumes the pinned contracts — #1 multi-reel
  screen, #2 store/targeting/X-Ray recon UI + Leech victim badge+push handling + imagegen
  icons (Leech + X-Ray), #3 hide disabled Imposter from inventory, #4 Android `/t/` filter,
  #5, #6, #7, #8, #11 FE `???`, #12 labeled AdMob native champion-cap placement. Loads
  design skills before UI work; iOS + Android lockstep. Writes tests first.

---

## Revision log

**Phase 2 — Gap pass 1 (fresh-eyes):**
- #1: caught that **queued boxes have no client-side ids** — added the batch-open endpoint
  with server-side queued materialization + a feature-detect fallback to N single opens for
  old backends.
- #2: added an **unknown-powerup-type fallback icon** requirement so a frozen client can't
  crash on the new enum values; pinned Mirror-does-not-reflect-Leech default; flagged the
  open balance numbers (fraction/cap/stacking) as approval questions rather than silently
  choosing.
- #4: added the **verification result** (both hosts serve correct AASA incl. `/t/`), which
  reframed the root cause away from AASA content toward capability/frozen-client + fallback,
  preventing a wasted "fix the AASA" effort.
- #9: caught that the in-race box has **no open log at all** — the metric is impossible
  without new logging; made "accurate from deploy forward, no history" an explicit accepted
  constraint rather than an unstated surprise.
- #11: added the **`null`-inference fallback** so the frontend fix works against the current
  prod backend without waiting on the backend flag (unblocks deploy ordering).

**Phase 2 — Gap pass 2 (second independent pass):**
- #2: made Leech scoring **suspend during victim frozen/reversed windows** (mirroring
  rainstorm) to avoid double-penalty stacking bugs; added the per-victim leecher cap to
  prevent gang-stall; noted the icons are UI icons (match existing powerup icons' framing),
  NOT side-profile capy accessories, so the imagegen prompt uses the right references.
- #4: separated fixes that ship **backend/config (anytime)** from those that need the **app
  build**, and called out that the iOS capability fix may only fully resolve on a new build
  rollout (~a week) — so the dedicated landing page is the interim protection, not optional.
- #7: verified that enrollment already happens server-side, so this is **frontend-only**;
  added the **missing-daily-race safe fallback** (land Home, don't block onboarding) and
  preserved pending-share-deep-link precedence.
- #5/#6/#8: confirmed all three are **frontend-only, zero-API-change** and safe for frozen
  clients; for #8 flagged that removing the `?` may leave help unreachable from home ("for
  now" accepted) to avoid a silent loss of the entry point.
- #10: made the RARE coins share **env-tunable** (`DAILY_SPIN_RARE_COINS_SHARE`) following
  the `AD_COIN_REWARD_AMOUNT` precedent so we can adjust without a deploy; confirmed the
  frontend already credits `result['coins']` so no FE change is needed.
- Global: added the **contract-first Phase-5 split** so the frontend agent never codes
  against a moving contract; reaffirmed tests-first / no-prod-DB / no-existing-test-edits.

**Phase 3 — interview (decisions folded in):**
- #1 grid + include queued; #2 Leech = 1:1 leecher-driven debuff (each of your steps −1 on
  target, 30 min, cap 3000, max 2 leechers, 300 coins) + X-Ray reveals all opponents'
  defenses (150 coins), icons via Codex `$imagegen`; #3 →
  **disable Imposter for now** (backend-only, reversible, no refunds); #4 iOS focus + full
  invite hardening; #5 drop future races (FE); #7 confirm→drop into Daily race; #8 remove
  `?` button; #9 in-race box, log going forward; #10 cap powerup share (env-tunable); #11
  `???` via backend flag + FE `null`-inference; #12 AdMob native at champion cap behind the
  kill switch. All open questions closed.

## Open questions — RESOLVED (Phase 3 interview)
1. **#2 Leech mechanic & balance:** ✅ **1:1 leecher-driven debuff** — each step the leecher
   takes removes 1 from the target; **30-min** window; **hard cap 3000**; leecher keeps own
   steps, gains nothing; max 2 concurrent leechers per victim; blocked by shield, not
   Mirror-reflected. Prices: Leech **300**, X-Ray **150**. Scanner name: **X-Ray**.
2. **#3 Imposter:** ✅ **Disable for now** (backend catalog filter + `IMPOSTER_ENABLED` kill
   + graceful use rejection; no refunds, re-enable is a flag flip).
3. **#12 Bracket ads:** ✅ AdMob native ad at the champion cap ("Finals presented by"),
   house-ad fallback, **gated behind the banner-ads remote kill switch**.
4. **#4:** minor — I'll confirm the prod `PUBLIC_BASE_URL` host from the server env during
   implementation (both hosts already serve correct AASA, so this only targets the iOS
   capability check at the right host; not a blocker).

**No open questions remain. Ready for approval.**
</content>
</invoke>
