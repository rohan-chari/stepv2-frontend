# Demo Race Tutorial — Requirements

Status: **DRAFT — awaiting owner approval.** Do not spawn implementation agents
until approved (CLAUDE.md Phase 4).

Supersedes: the five-step spotlight tutorial **in onboarding only**. See §2.

---

## 1. Summary & user story

Replace the passive spotlight walkthrough in onboarding with a **playable
90-second demo race that the user wins.**

> As a brand-new user, I am dropped into a race with 2:00 on the clock, sitting
> in 2nd place with a Shortcut and two mystery boxes. A coach walks me through
> opening a box, using a boost, getting attacked by a rival, and finally
> stealing the lead with my Shortcut. I win. Then I'm dropped into my real
> first race already knowing what the buttons do.

The current tutorial *describes* powerups. This one makes the user *use* one to
win. That is the entire thesis: the core loop of this app is not "walk" — it is
"walk, get boxes, mess with rivals." No amount of spotlight copy teaches that as
well as one Shortcut landing on the leader.

### Why this is architecturally cheap

The seam already exists and is already load-bearing:

- `RaceDetailScreen` takes an injectable `backendApiService` + `authService`
  (`lib/screens/race_detail_screen.dart:63-92`) and routes **every** read and
  write through `_api` (`:272`).
- The existing tutorial already renders the **real** `RaceDetailScreen` behind
  its spotlight, fed by `TutorialPreviewBackendApiService extends
  BackendApiService` (`lib/tutorial/tutorial_preview_data.dart:43`,
  `lib/tutorial/tutorial_real_screens.dart:10`).
- `CaseOpeningScreen` takes an `openMysteryBox` **callback**, not a service
  (`lib/screens/case_opening_screen.dart:126`) — already fully injectable.
- `RaceChatService` receives `api: widget.backendApiService`
  (`race_detail_screen.dart:559-562`), so the chat/activity feed rides the same
  injection for free.

Today's preview service is a **stateless stub** returning fixed maps. This spec
makes it **stateful**. We are not building a screen; we are building a fake
backend for a screen we already ship.

**Backend work is close to zero** (§6): no endpoint, no table, no migration.

---

## 2. Scope / non-goals

### In scope

1. A deterministic, offline, client-side demo race engine.
2. A `BackendApiService` subclass that serves that engine to the real
   `RaceDetailScreen`.
3. A coach-mark overlay that advances on **engine beats**, not NEXT taps.
4. Removing the tutorial step from the onboarding flow and re-pointing the
   onboarding gate at demo completion.
5. Suppressing ads, pushes, deep links, share links and every other real side
   effect while the demo is on screen.
6. Activation telemetry for the new funnel.

### Explicitly out of scope

- **Deleting the spotlight tutorial.** *Owner decision, 2026-07-26:* it stays,
  reachable from Profile → Settings → VIEW TUTORIAL
  (`lib/screens/settings_screen.dart:310-322`). That entry point already
  constructs `TutorialScreen` directly and is untouched by this work. The five
  steps and their tests keep their value.
- **A server-side demo race.** Rejected: it would create real `Race`,
  `RaceParticipant`, `Powerup` and `CoinTransaction` rows, run through real
  settlement, and have to exist forever for every frozen client. A client-side
  simulation cannot corrupt prod and cannot be broken by a backend deploy.
- **Any change to real race, powerup, or settlement logic.** The demo must not
  be able to reach any of it.
- **New powerup art, copy, or types.** The demo uses shipped types only.
- **Character/animal selection**, cosmetics, shop. Out, as in the last spec.

---

## 3. Owner decisions — ALL RESOLVED 2026-07-26

| # | Decision | Resolution |
|---|---|---|
| D1 | **Stall clock** — what if a user idles at 0:15 mid-lesson? | **Floor at 0:20 until the final beat.** Ticks down in real time, never jumps backwards, never expires early; the floor lifts at beat 8. See §5.5. |
| D2 | **Script depth** — 3 taps or 5? | **5 taps, ~90s.** Includes the shield-then-blocked beat. See §5.3. |
| D3 | **Skippable?** | **Yes, from beat 1.** A forced 90s tutorial is worse than the drop-off it prevents. |
| D4 | **What does a skip grant?** | Satisfies the onboarding gate, **no coins**. Mirrors today's `_skipTutorialOnboarding` (`main_shell.dart:2093-2095`). |
| D5 | **Does the 100-coin reward move to demo completion?** | **Yes, same ledger key.** A user who also replays the settings tutorial still gets 100 total, not 200. See §6.2. |
| D6 | **Win screen** — real results screen or in-demo card? | **In-demo win card.** `COMPLETED` does not auto-route (G5), so this is viable without faking a second screen's API surface. |
| D7 | **Does the demo replay from Settings?** | **No.** Settings keeps the spotlight tutorial. One replay path, not two. |
| D8 | **Gate rename** — move the marking out of `TutorialScreen`, breaking a ring-fenced test? | **Move it. Test edit to `test/tutorial_screen_test.dart` is AUTHORIZED** for this change only. See §5.8. |

D1, D2, D5 and D8 were put to the owner directly. D3, D4, D6 and D7 were
locked at the recommendation as routine calls.

---

## 4. Current-state findings

Load-bearing facts discovered while exploring. Each reshapes the design.

**F1 — `RaceDetailScreen` makes ~25 distinct `_api.*` calls.** Enumerated from
source: `fetchRaceDetails` `:641`, `fetchRaceProgress` `:722`,
`fetchPowerupInventory` `:1675`, `usePowerup` `:1499`, `useQuicksand` `:1493`,
`openMysteryBox` `:4485`, `openMysteryBoxBatch` `:4459`, `discardPowerup`
`:1765`, `redeemPowerupToRace` `:1714`, `fetchSneakySwapTargets` `:1795`,
`fetchStarterReward` `:346`, `claimStarterReward` `:376`, `fetchMe` `:802`,
`startRace` `:1231`, `leaveRace` `:1208`, `forfeitRace` `:1099`, `cancelRace`
`:1338`, `kickRaceParticipant` `:5963`, `inviteToRace` `:1376`,
`respondToRaceInvite` `:922`, `acceptTeamRaceInvite` `:960`, `setRaceTeam`
`:968`, `createRaceShareLink` `:4995`, `setRaceChatMute` `:5069`,
`setRacePlacementMute` `:5064`, plus `fetchRaceMessages` / `markRaceChatRead`
via `RaceChatService`.

**Any one of these not overridden is a live HTTPS request against prod with a
fabricated race id.** The transport helpers (`_sendGetRequest`,
`_sendJsonRequest`) are private, so the base class cannot be cheaply sealed.
This is the single largest risk in the project and §8.4 exists to contain it.

**F2 — `SHORTCUT` is a targeted powerup** (`lib/constants/powerup_copy.dart:39`,
inside `kTargetedPowerupTypes`), copy "Steal 1,000 steps from a rival"
(`:417`). So the real use path runs through `_showTargetPicker`
(`race_detail_screen.dart:1477`). Good news pedagogically — choosing the leader
and taking their steps is the best five seconds in the app — but it is the most
code, and the picker is fed from `_progress['participants']` via
`TeamRace.offensiveTargets` (`:1409-1414`), which the engine must populate
correctly or the picker renders empty and the demo dead-ends.

**F3 — The screen polls standings every 30s and counts down every 1s**
(`:813-822`). Four standings refreshes in two minutes is far too coarse to feel
alive. But `_loadProgress()` is already called immediately after a powerup use
(`:1605`) and after box opens (`:4445`, `:4555`). So **progress is
action-driven for free** — the leaderboard moves the instant the user acts.
Cause, then effect. The 30s poll only needs to carry ambient rival drift.

**F4 — `TutorialRealHost` sets `disableAnimations: true`**
(`tutorial_real_screens.dart:52-56`) because the spotlight measures its target
rect the instant a page mounts and a mid-bounce element measures misaligned.
**A demo race cannot do this** — it is entirely juice. Coach marks anchored to
live, animating targets is real work, not a detail. See §8.5.

**F5 — The ad banner is a `const` widget with no injection at its call site**
(`race_detail_screen.dart:2779`). `AdBannerSlot` *does* expose `hidden`
(`lib/widgets/ad_banner_slot.dart:36,60`), so suppression is a one-line change
plus a flag threaded into `RaceDetailScreen`.

**F6 — The onboarding gate consumes `tutorialOnboardingSeen`**
(`lib/utils/onboarding_gate.dart:27,33,41`), and the v3 branch requires it.
Deleting the tutorial step from `onboarding_flow.dart:171-176` without
re-pointing that term leaves the gate permanently unsatisfied — the user
re-enters onboarding on every launch. This is the same infinite-loop class the
previous spec had to fix twice (see §5.10 there). §5.8 addresses it.

**F7 — Activation event names are allowlisted on both ends**
(`lib/services/activation_analytics_service.dart:21-52`,
`stepv2-backend/src/modules/analytics/routes.js:9-38`), and the backend
**soft-drops unknown names while keeping the 202** (§6.4 of the previous spec).
`tutorial_opened` / `tutorial_completed` / `tutorial_skipped` and the `step`
context key (range 1..10, wire type **string**, `routes.js:66-68`) already
exist. §6.3 exploits this to make the funnel work even if the backend allowlist
deploy is skipped.

**F8 — The onboarding tutorial launcher marks the step seen on return whether
the user finished or bailed** (`main_shell.dart:2073-2088`). The demo host must
preserve exactly this property, including the "user backgrounded the app and
came back" path.

---

## 5. Design

### 5.1 Components

Three new pieces, one modified screen.

```
DemoRaceEngine            pure Dart. No Flutter, no network, no clock of its own.
   ↑ state
DemoRaceApiService        extends BackendApiService. Translates engine → wire JSON.
   ↑ injected
RaceDetailScreen          THE REAL SCREEN. demoMode:true only suppresses side effects.
   ↑ overlaid
DemoRaceHost              coach marks, beat sequencing, win card, skip affordance.
```

Files:

| Path | New? | Purpose |
|---|---|---|
| `lib/demo/demo_race_engine.dart` | new | Simulation state + script |
| `lib/demo/demo_race_api_service.dart` | new | `BackendApiService` subclass |
| `lib/demo/demo_race_host.dart` | new | Coach marks + beats + win card |
| `lib/demo/demo_race_script.dart` | new | The beat list, copy, anchors |
| `lib/screens/race_detail_screen.dart` | modified | `demoMode` flag (§5.7) |
| `lib/screens/onboarding_flow.dart` | modified | Tutorial step → demo step |
| `lib/screens/main_shell.dart` | modified | Launcher (§5.8) |
| `lib/utils/onboarding_gate.dart` | modified | Gate term (§5.8) |

### 5.2 `DemoRaceEngine`

Pure Dart. Holds:

- `participants`: 4 racers with `userId`, `displayName`, `totalSteps`, and a
  scripted drift rate.
- `virtualRemaining`: `Duration`, the race clock (§5.5).
- `inventory`: 1 `HELD` Shortcut + 2 `MYSTERY_BOX` rows.
- `beatIndex`: which scripted beat is live.

Methods: `advanceTo(beat)`, `openBox(id)`, `usePowerup(type, targetUserId)`,
`tick(wallElapsed)`.

**Scripted, not simulated. No RNG anywhere.** Box 1 always rolls a Protein
Shake; the Shortcut always steals exactly enough; the user always wins. A
tutorial the user can lose teaches them they are bad at the game. Determinism
is also what makes the whole thing testable without flake.

### 5.3 The script (D2 recommendation — 5 taps, ~90s)

Every powerup below is chosen for **instant, visible effect**. In a 120-second
demo, anything measured in hours teaches nothing (see G6).

| Beat | Coach copy | User action | Engine effect | Teaches |
|---|---|---|---|---|
| 1 | "2 minutes left. You're in 2nd." | tap to continue | — | orientation, stakes |
| 2 | "Walking earns mystery boxes. Open one." | tap box | real `CaseOpeningScreen` reel → **Protein Shake** | boxes exist, boxes come from walking |
| 3 | "Boosts add steps. Use it." | tap Protein Shake | **+1,500 steps**; still 2nd (leader drifted) | boosts help; the race is live |
| 4 | "One box left. Open it." | tap box | reel → **Compression Socks** | not everything is offense |
| 5 | "Sam's coming for you. Shield up." | tap Socks | shield armed | defense is pre-emptive |
| 6 | *(no tap)* "Sam tried to steal 1,000 steps — **blocked.**" | — | scripted rival Shortcut resolves as `blocked` | **rivals attack you**, and shields work |
| 7 | "Now take the lead." | tap Shortcut → **real target picker** → Sam | −1,000 Sam, +1,000 you → **1st** | offense, targeting, the payoff |
| 8 | clock → 0:00 | — | race COMPLETED, you won | the loop closes |
| 9 | Win card + 100 coins | tap CONTINUE | gate satisfied, reward claimed | — |

Beat 6 is deliberately not a tap. Being attacked is the one lesson that must
happen *to* the user rather than *by* them — and putting the shield **before**
the attack turns a punishment into a save, which is a far better feeling at the
one moment the user is most likely to bail.

Beat 6 also exercises the real `blocked` outcome path the screen already renders
(`race_detail_screen.dart:1518-1520`), so the demo teaches a real UI state
rather than a bespoke one.

Beat 7 uses the **real** target picker (F2), not a mock. The whole point is
that the next time they see that picker it is familiar.

Powerup semantics are pinned from `lib/constants/powerup_copy.dart`:
`PROTEIN_SHAKE` "+1,500 bonus steps instantly" (`:420`), `COMPRESSION_SOCKS`
"Shield against the next attack" (`:418`), `SHORTCUT` "Steal 1,000 steps from a
rival" (`:417`).

### 5.4 Rival drift

Between beats, rivals gain steps on the 30s poll (F3) so standings are never
frozen. Drift is scripted per beat, not per second, so the outcome is identical
regardless of how long the user takes.

### 5.5 The clock (D1)

The one genuinely delicate decision.

`endsAt` is served as `wallNow + virtualRemaining`. The screen's own 1s
countdown (`:822`) ticks it down locally; every fetch re-pins it.

Rules:
1. `virtualRemaining` decreases in real time.
2. It is **floored at 0:20** until beat 8 fires.
3. It is never re-pinned *upward*. If wall-clock drift would raise it, it holds.

Consequence: the clock always ticks down, feels urgent, and cannot expire while
a slow user reads a coach mark. At beat 8 the floor lifts and it runs to 0:00.

Rejected alternative: pausing the virtual clock during coach marks. It produces
a visible jump when `endsAt` re-pins upward on the next fetch, and the 30s poll
means that jump can be up to 30 seconds.

### 5.5b Identity and the wallet (G1, G2)

The demo must render as **the user's own race**, not a stranger's. So it needs
the real display name, user id, and coin balance. But the real screen *writes*
through the auth service:

- `_usePowerup` calls `widget.authService.updateCoins(coins - coinsSpent)`
  (`race_detail_screen.dart:1508-1511`)
- `_refreshWallet` calls `_api.fetchMe` then `updateCoins`
  (`race_detail_screen.dart:800-805`)

Passing the real `AuthService` would let demo actions **decrement the user's
displayed coin balance.**

Required: a `DemoAuthService` wrapper that **proxies every read** (`userId`,
`displayName`, `coins`, accessories) from the real service and **no-ops every
write** (`updateCoins`, `applyBackendUser`, …). Belt and braces: the engine
always returns `coinsSpent: 0`, so even a leaked write is a no-op.

`_myUserId` resolves to `authService.userId` (`:271`). The engine's participant
list **must contain the real user id**, or: standings never highlight "you",
`TeamRace.offensiveTargets` (`:1409-1414`) fails to exclude the user from their
own target picker, and beat 7 breaks. Identity is injected into the engine at
construction — never hardcoded the way `tutorial_preview_data.dart:15` does it.

### 5.6 What the demo must never do

Enumerated because each is a live side effect reachable from the real screen:

- request or render an ad (F5)
- **render the notification opt-in card or fire the OS permission prompt (G3
  — the sharpest edge in this spec).** `RaceAlertOptInCard` renders whenever
  `status == 'ACTIVE' && myStatus == 'ACCEPTED' && onboardingV2Enabled &&
  _alertPermissionUndetermined` (`race_detail_screen.dart:2830-2834`) — which
  is *exactly* the demo's state, and a brand-new user's permission is always
  undetermined. Tapping it calls `notificationService.requestPermission`
  (`:2842`) for real. Worse: the previous spec relocated the notification ask
  to the **first mystery-box open**, and the demo opens two boxes at beats 2
  and 4 — so without suppression the demo both fires the prompt over a fake
  race *and* burns the real first-box trigger, meaning the user never gets the
  ask at the moment it was designed for. Demo box opens must not count toward
  that trigger.
- fire a real push registration
- create a share link (`:4995`) or open a share sheet
- write chat messages or read receipts to the server
- claim the *starter* reward (`:346`, `:376`) — distinct from the tutorial
  reward, and claiming it here would mint 100 coins against a fake race
- start/leave/forfeit/cancel/kick anything
- emit analytics with a fabricated `raceId`

### 5.7 `demoMode` on `RaceDetailScreen`

A single `final bool demoMode` (default `false`), threaded to:

- `AdBannerSlot(hidden: demoMode)` at `:2779` (F5)
- skip `_loadStarterReward()` / `_loadAlertPermissionState()` at `:327-328`
- force `showAlerts = false` at `:2830` regardless of permission state (G3)
- suppress the share/invite/forfeit/kick affordances
- suppress the review prompt

`demoMode` must **not** change any rendering of standings, powerups, boxes, the
course, or the target picker. If it did, the demo would stop being the real
screen and the whole premise collapses.

### 5.7b Interaction policy — the user can wander (G7)

§8.5 forbids a tap-swallowing overlay, because the user must be able to tap the
thing the coach points at. The consequence the draft missed: **everything else
is tappable too.** The real screen offers chat, the activity feed, the odds
sheet, participant rows, powerup **discard** (`:2420`, `:2526`), upgrade
ladders (`:2295`, `:2417`), and an **OPEN ALL** button (`:7103`) that would
open both boxes at once and skip beats 4–5 outright.

Policy:

1. **Beats are state-driven, not sequence-driven.** A beat completes when the
   engine reaches its goal *state*, not when a specific widget is tapped. If
   the user opens both boxes with OPEN ALL, beats 2 and 4 both satisfy and the
   coach advances to beat 5. The script must be reachable from any legal state.
2. **Destructive or off-script actions are disabled in `demoMode`**: discard,
   upgrade ladders, and OPEN ALL. Discarding the Protein Shake would dead-end
   the script with no recovery.
3. **Everything read-only stays enabled** — chat, activity feed, odds sheet,
   participant taps. Wandering is fine; it is how a curious user learns. The
   coach simply waits.
4. **Back / swipe-back is the skip affordance** (§D3), not a silent exit. It
   routes through the same skip path so the gate is always satisfied.

### 5.7c The case-opening screen (G8)

Beats 2 and 4 push the **real** `CaseOpeningScreen`, which is full-screen. Two
consequences the draft missed:

- It renders **two `AdBannerSlot`s** (`case_opening_screen.dart:263,292`), both
  `const` with no injection — same fix as F5, a `demoMode` flag threaded to
  `hidden`. `multi_case_opening_screen.dart:160,183` needs the same treatment
  if OPEN ALL is ever enabled in demo (it is not, per §5.7b).
- It **covers the coach-mark overlay.** The host must pause the beat while the
  reel is presented and resume on return, and the skip affordance must be
  reachable again immediately on return.

### 5.8 Onboarding integration and the gate (F6)

`onboarding_flow.dart:171-176` currently returns `OnboardingTutorialStep` in the
v3 branch. It returns `OnboardingDemoRaceStep` instead — same position (before
the inviter-race step), same two callbacks (`onStart`, `onSkip`).

The gate term is the delicate part. `tutorialOnboardingSeen`
(`onboarding_gate.dart:27,33`) currently means "saw the tutorial". It must now
mean **"cleared the onboarding teaching step"**, satisfied by *any* of:

- completing the demo,
- skipping the demo,
- (legacy) having completed the old tutorial before this build.

**The settings-tutorial replay must NOT set it** — it is not an onboarding
step. Today `TutorialScreen` marks it internally, which is correct for the
onboarding path and harmless for replay because the flag is already set by then.
Under this spec the replay path can run for a user who reached settings via a
skip, so the marking must move out of `TutorialScreen` and into the host.

Recommended: rename the field to `onboardingTeachingSeen` at the **Dart layer
only**, keeping the wire field `tutorialOnboardingSeen` unchanged in both
directions (`auth_service.dart:579-581`, `markTutorialOnboardingSeen`). Renaming
the wire field would break every frozen client.

**G9 / D8 — RESOLVED.** Moving the marking out of `TutorialScreen` will likely
break `test/tutorial_screen_test.dart`. This was surfaced to the owner before
approval, per CLAUDE.md, and **the owner authorized the edit — for this change
only.** Every other ring-fenced file in §10 remains off-limits, and any further
existing-test breakage must still be surfaced rather than fixed.

### 5.9 Telemetry

Reuses the existing `tutorial_*` names, disambiguated by `source` (F7):

| Event | `source` | When |
|---|---|---|
| `tutorial_opened` | `onboarding` | demo mounts |
| `tutorial_skipped` | `onboarding` | skip, carrying `step` = beat index |
| `tutorial_completed` | `onboarding` | win card CONTINUE |

Plus three **new** names for the actions that are the point of the exercise:
`demo_box_opened`, `demo_powerup_used`, `demo_won`.

The spotlight tutorial in settings keeps emitting the same three `tutorial_*`
names with `source: 'profile'`, so the two funnels stay separable.

`step` reuses the existing 1..10 string-typed context key — **no backend
pattern change**, and the wire type is a **decimal string** (F7,
`routes.js:66-68`). Do not send a number.

---

## 6. API contract

### 6.1 New endpoints

**None.** No new route, no changed response shape, no migration.

### 6.2 Reward (D5)

Demo completion calls **`authService.claimTutorialReward()`** — the same method
`TutorialScreen` uses on full completion (`lib/tutorial/tutorial_screen.dart:275`).
This is *not* the starter-reward route (`/onboarding/starter-reward/claim`),
which is a separate grant the demo must never touch (§5.6).

Both land on the same ledger key: `STARTER_REWARD_REASON = "tutorial_complete"`
with `refId = userId`
(`stepv2-backend/src/routes/onboarding.js:6-9`), idempotent through
`awardCoins` (`src/shared/economy/awardCoins.js:14-48`). A user who finishes
the demo **and** later replays the settings tutorial receives 100 coins total,
not 200. The per-user ceiling cannot move.

### 6.3 Analytics allowlist (the only backend change)

Add to `ALLOWED_EVENT_NAMES` (`src/modules/analytics/routes.js:9-38`):
`demo_box_opened`, `demo_powerup_used`, `demo_won`. Mirror in
`allowedEventNames` (`activation_analytics_service.dart:21`).

Widening an allowlist can only increase what is accepted, so **no shipped
client is affected.** And because the backend soft-drops unknown names while
keeping the 202 (F7), a newer app against an older backend loses only these
three events — the reused `tutorial_*` funnel still works. **The demo funnel
degrades, it never breaks.**

### 6.4 Wire shapes the engine must produce

The engine serves the shapes the real screen already parses. Reference:
`tutorial_preview_data.dart:481-494` (`fetchRaceDetails`) and `:550-582`
(`fetchRaceProgress`, including `powerupData.enabled`, `powerupSlots`,
`inventory[]` with `HELD` / `MYSTERY_BOX` status, and `activeEffects[]`).

`usePowerup` and `openMysteryBox` responses must carry the fields the screen
reads defensively — `result.coinsSpent` (`:1508`), the `outcome` / `blocked` /
`reflected` discriminators (`:1518-1520`) — or the screen takes an error path.

---

## 7. Data model / migrations

**None.** No table, no column, no backfill. The demo is entirely
device-local and leaves no server-side trace beyond activation events and the
one idempotent coin grant.

---

## 8. Frontend plan

### 8.1 Order of work

1. `DemoRaceEngine` + its tests (pure, fast, no widgets).
2. `DemoRaceApiService` + the §8.4 structural guard.
3. `demoMode` on `RaceDetailScreen`.
4. `DemoRaceHost` coach marks + beats.
5. Onboarding flow + gate rewiring (§5.8).
6. Telemetry.

### 8.2 States

- **Loading**: none. The engine is synchronous and offline; the demo opens
  instantly. This is a feature — it is the fastest screen in the app.
- **Error**: unreachable by construction. If the engine throws, the host
  catches, marks the step seen, and exits to the next onboarding step rather
  than trapping the user. **Failing open is mandatory** — an exception here
  must never brick onboarding.
- **Empty**: not applicable.

### 8.3 Degrading safely when a field is missing

Inverted here versus a normal feature: the engine is the *producer*, so it
always emits every field this build reads. The compat risk is the reverse — a
**future** `RaceDetailScreen` reading a field the engine doesn't produce. §8.4's
guard does not catch that. Mitigated by §10's widget tests, which pump the real
screen and assert the demo renders.

### 8.4 The network-leak guard (F1) — mandatory

A structural test over source: enumerate every `_api.<method>(` call site in
`race_detail_screen.dart` and assert `DemoRaceApiService` overrides each one.

This is the "structural guard over source" carve-out in CLAUDE.md's testing
policy, and it is the same pattern as the existing `isOnboardingGate`
declared-exactly-once guard (`onboarding_gate.dart:1-8`). It is the only
mechanism that fails **when someone adds a 26th API call to the race screen a
year from now** — which is precisely when this breaks, silently, in production.

Belt and braces: `DemoRaceApiService` overrides its base URL to an unroutable
value so a leak fails fast and loudly in dev rather than quietly succeeding.

### 8.5 Coach marks over live animation (F4)

The demo cannot freeze animations. Options, in preference order:

1. Anchor coach marks to **stable layout containers** (the standings card, the
   powerup tray) rather than to individual animating chips.
2. Where a moving target is unavoidable, re-measure on a post-frame callback
   each frame the mark is visible.
3. Fall back to a non-anchored bottom sheet for that beat.

Do not reuse `SpotlightOverlay` unmodified — it measures once on mount
(`lib/tutorial/spotlight_overlay.dart`) and its opaque `GestureDetector`
swallows every tap, which is fatal here: **the user must be able to tap the
thing the coach is pointing at.** This is the central UI difference between the
two tutorials and the most likely place to get it wrong.

### 8.6 iOS + Android

Identical Dart; no platform channels, no permissions, no native work. Both
platforms must still be built and verified in lockstep before this is called
done (CLAUDE.md). The only platform-visible difference is the health-source
name, which the demo does not mention.

### 8.7 Design skills

`mobile-design` and `frontend-design` must be loaded before any UI work on the
host or the win card (CLAUDE.md, and the `ui-redesign-feedback-rules` memory).
Confetti is permitted on the beat-8 win — that is a race finish, the one place
the rules allow it.

---

## 9. Backward-compat & rollout

**Deploy order:**

1. **Backend first** — §6.3 allowlist widening only. Purely additive; no shipped
   client changes behavior.
2. **App Store + Play in lockstep**, phased ~1 week.
3. **Flag on.**

**Flag.** Ride the existing `onboardingV3Enabled`. No shipped binary contains
v3 behavior yet — the v3 build is still uncommitted — so v3 is free to absorb
this. **This saving is only available until 2.1 ships;** after that a new flag
would be required. If the owner intends to ship v3 before the demo is ready,
this decision must be revisited.

**What a frozen old client does.** Nothing changes for it. It has no demo code,
its onboarding is unchanged, and the gate field it reads and writes is the same
wire field (§5.8). Old clients continue to satisfy the gate via the old
tutorial.

**Rollback.** Flip `onboardingV3Enabled` off. Onboarding reverts to the v2 path
for new users with no App Store submission. Users mid-demo are unaffected —
the demo is device-local.

**Kill switch caveat.** Flipping v3 off also reverts the health-gate rework and
the rest of the previous spec. If the demo needs to be killed independently, it
needs its own flag. Flagged as a known coupling, not a blocker.

---

## 10. Test plan (tests FIRST, per CLAUDE.md)

Integration-first: pump the real screen and assert what renders. Note the
`PackageInfo.setMockInitialValues` requirement in `setUp` for any widget test
asserting activation events — without it the write hangs silently in the
fake-async zone (memory: `flutter-widget-test-packageinfo-hang`).

**Widget / integration (the default):**

1. Demo mounts → real `RaceDetailScreen` renders, user is 2nd, clock ~2:00.
2. Beat 2 → tapping the box pushes the real `CaseOpeningScreen`.
3. Reel lands → Protein Shake appears in the real inventory tray.
4. Beat 3 → using it increases the user's steps; still 2nd.
5. Beat 4 → the scripted Leg Cramp renders in the real activity feed.
6. Beat 5–6 → Quick Rinse clears the effect from the real effects row.
7. Beat 7 → tapping Shortcut opens the **real** target picker with 3 rivals.
8. Selecting Sam → user takes 1st in the real standings.
9. Beat 8 → clock reaches 0:00 and the race renders as won.
10. Win card → CONTINUE satisfies the gate and advances onboarding.
11. **Skip at every beat** (1..9) → gate satisfied, no coins, no crash.
12. Backgrounding mid-demo and returning → no duplicate beats, no double
    reward, gate still correct (F8).
13. Clock floor: idle past the natural expiry → clock holds at 0:20, demo
    still completable (§5.5).
14. Clock monotonicity: the countdown never increases across a poll.
15. `demoMode` → no `AdBannerSlot` renders.
16. `demoMode` → starter reward is never fetched or claimed.
16a. `demoMode` → `RaceAlertOptInCard` never renders even with permission
     undetermined, and `notificationService.requestPermission` is never
     called (G3).
16b. Demo box opens do **not** consume the real first-mystery-box notification
     trigger: after a full demo, a subsequent real box open still fires the
     ask (G3).
16c. The user's coin balance is unchanged by every demo action; the win-card
     grant is the only mutation (G1).
16d. The engine's participant list contains the **real** `authService.userId`,
     "you" is highlighted in standings, and the beat-7 target picker excludes
     the user (G2).
16e. Beat 6 renders the real `blocked` outcome UI, not bespoke demo copy.
16f. `demoMode` → no `AdBannerSlot` renders on `CaseOpeningScreen` either (G8).
16g. Discard, upgrade ladders and OPEN ALL are disabled in `demoMode` (G7).
16h. Wandering does not break the script: opening chat, the odds sheet and a
     participant row mid-beat, then returning, still advances (G7).
16i. Back / swipe-back mid-demo routes through skip; the gate is satisfied and
     the user is never returned to the demo (G7).
17. Engine determinism: two full runs produce identical standings.
18. Telemetry: `tutorial_opened`/`completed`/`skipped` carry
    `source: 'onboarding'`; skip carries `step` as a **string**.
19. Settings tutorial still renders all five spotlight steps (regression).
20. Settings tutorial does **not** satisfy the onboarding gate (§5.8).

**Structural:**

21. §8.4 guard: every `_api.` call site in `race_detail_screen.dart` is
    overridden by `DemoRaceApiService`.
22. `isOnboardingGate` still declared exactly once (existing guard holds).

**Unit (only where an integration test structurally cannot reach):**

23. Engine clock arithmetic across the floor boundary.
24. Engine step math for steal/boost/cramp interaction.

**Backend:**

25. Integration: the three new event names are accepted (202) through the real
    endpoint. **Against the local test DB only** — never prod.
26. Integration: an old client's payload without them still succeeds.

**Ring-fenced — do not modify:** `test/onboarding_v2_test.dart`,
`test/races_tab_test.dart`, and every fixture setting
`tutorialOnboardingSeen: true`. Any breakage in these must be **surfaced to the
owner**, never fixed.

**`test/tutorial_screen_test.dart` — edit AUTHORIZED (D8)**, scoped strictly to
the §5.8 marking move. No other change to that file.

---

## 11. Acceptance criteria

- [ ] A new user on v3 is dropped into the demo race instead of the spotlight.
- [ ] The demo is the **real** `RaceDetailScreen`, not a mock.
- [ ] The user opens a box, uses a boost, is attacked, counters, and wins with
      the Shortcut through the real target picker.
- [ ] The user always wins. No path loses.
- [ ] Skip works at every beat and never traps the user.
- [ ] Zero network requests leave the device during the demo (asserted, §8.4).
- [ ] No ad renders, no push prompt fires, no share link is created.
- [ ] The onboarding gate is satisfied by completion *and* by skip; the
      settings tutorial does not satisfy it.
- [ ] 100 coins granted once ever, sharing the existing ledger key.
- [ ] Spotlight tutorial still reachable and intact at Profile → Settings.
- [ ] Backend allowlist deployed **before** the app build ships.
- [ ] iOS **and** Android built and verified.
- [ ] No existing test modified without owner approval.

---

## 12. Revision log

### Gap pass 1

Six findings, all verified against source rather than assumed.

- **G1 — the demo would have spent the user's real coins.** `_usePowerup`
  (`:1508-1511`) and `_refreshWallet` (`:800-805`) both write through
  `authService.updateCoins`. Passing the real service means demo actions
  decrement the visible balance. Added §5.5b: a read-proxying, write-no-oping
  `DemoAuthService`, plus `coinsSpent: 0` as a second line of defense.
- **G2 — identity was unspecified, and the obvious implementation breaks beat
  7.** `_myUserId` is `authService.userId` (`:271`). Copying
  `tutorial_preview_data.dart`'s hardcoded `'preview-user'` would leave the
  user unable to be excluded from their own target picker. Identity is now
  injected. This also fixes a UX miss the draft didn't notice: the demo would
  have shown a stranger's name in the standings.
- **G3 — the notification prompt fires inside the demo, and burns the real
  trigger.** Verified at `:2830-2834`: the opt-in card's render condition is
  exactly the demo's state. Compounding it, the previous spec moved the
  notification ask to the first mystery-box open — which the demo performs
  twice. The draft's one-line "suppress the notification opt-in card" badly
  understated this; it is now the headline item in §5.6 with two tests.
- **G4 — the reward method was wrong.** The draft said "the existing path"
  while §5.6 simultaneously forbade touching the starter reward. The actual
  call is `authService.claimTutorialReward()`
  (`tutorial_screen.dart:275`). Pinned in §6.2, and the two grants are now
  explicitly distinguished.
- **G5 — `COMPLETED` verified safe.** `:664` and `:777` only stop polling and
  reload details; there is no auto-route to the results screen. D6's in-demo
  win card is viable. Recorded so it isn't re-litigated during implementation.
- **G6 — the script taught nothing at beats 4–6.** The draft used a Leg Cramp
  ("freeze a rival's steps for **2 hours**") and Quick Rinse ("cut remaining
  time on opponent effects **in half**") inside a **120-second** race. Both are
  invisible at that timescale. §5.3 was rewritten around instantly-visible
  powerups only, and reordered so the shield is armed *before* the attack —
  turning beat 6 from a punishment into a save, at the exact moment a new user
  is most likely to quit. It now also exercises the real `blocked` outcome UI
  (`:1518-1520`) instead of bespoke copy.

### Gap pass 2

Three findings. Where pass 1 was about *side effects leaking out*, pass 2 is
about *the user not following the script* — the draft implicitly assumed a
compliant user, which is exactly the wrong assumption for an onboarding
tutorial.

- **G7 — the draft had no answer for a user who wanders.** §8.5 rules out a
  tap-swallowing overlay (correctly — the user must tap the highlighted
  thing), but that leaves the entire real screen live: chat, odds sheet,
  participant rows, powerup **discard**, upgrade ladders, and an **OPEN ALL**
  button that opens both boxes at once and skips beats 4–5 outright.
  Discarding the Protein Shake at beat 3 would dead-end the demo with no
  recovery path. New §5.7b: beats become **state-driven rather than
  sequence-driven**, destructive actions are disabled in `demoMode`, read-only
  exploration stays enabled, and back/swipe-back routes through skip instead
  of silently exiting.
- **G8 — the case-opening screen was treated as a detail; it is a second
  screen.** It renders two of its own `AdBannerSlot`s
  (`case_opening_screen.dart:263,292`) that F5's fix does not reach, and being
  full-screen it **covers the coach overlay**, so the host must pause and
  resume the beat around it. New §5.7c.
- **G9 — §5.8's gate rename collides with a ring-fenced test.** Moving the
  "mark seen" call out of `TutorialScreen` will very likely break
  `test/tutorial_screen_test.dart`, which §10 itself ring-fences. The draft
  created a requirement that silently violates its own testing rule. Now
  called out with an explicit instruction to surface it to the owner, plus a
  documented fallback that needs no test change.

### Phase 3 — interview (2026-07-26)

D1, D2, D5 and D8 answered by the owner; D3, D4, D6, D7 locked at the
recommendation. D8 is the notable one: the owner chose the **cleaner semantics
over the zero-test-change fallback**, explicitly authorizing the
`tutorial_screen_test.dart` edit. The gate now means what it says — "cleared
the onboarding teaching step" — rather than carrying a known lie for the
convenience of a test.

### Open questions

**None.** All decisions resolved; the spec is ready for the approval gate.
