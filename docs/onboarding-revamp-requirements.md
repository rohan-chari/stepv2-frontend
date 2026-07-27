# Onboarding revamp — requirements

**Status:** awaiting owner approval
**Author:** PM/BA pass, 2026-07-26
**Spec covers:** Phases 1–5 of the agreed roadmap (flag flip → gate collapse → identity → referral landing → instrumentation)

---

## 1. Summary & user story

Today a brand-new user signs in and is then held behind up to four sequential
full-screen gates before they can touch the app at all. One of those gates
(health) is a hard block with a genuine dead end on Android and a silent
false-pass on iOS. We cannot currently measure how many people fall out at each
step, because the analytics vocabulary exists but is almost entirely unwired.

**User story.** *As a new Bara user, I want to be racing within a tap or two of
signing in, and if something goes wrong with permissions I want a way forward
instead of a wall.*

**Owner-facing story.** *As the operator, I want to see exactly which onboarding
step loses people, and I want to be able to roll the new flow back from an admin
screen without a DB touch or an App Store submission.*

This spec does four things:

1. Ships the already-built v2 flow (removes the blocking tutorial gate).
2. Makes the health gate survivable — a real recovery path on Android, and
   detection of the iOS silent-denial case that currently strands users at 0 steps
   forever.
3. Moves the notification ask out of the critical path to the first mystery-box
   open.
4. Wires the activation funnel end-to-end so the next iteration is data-driven.

---

## 2. Scope / non-goals

### In scope

- Flip `onboardingV2Enabled` on in prod (Phase 1).
- New `onboardingV3Enabled` flag gating everything else in this spec (see §5.1).
- Health gate rework: framing, programmatic settings deep-link, post-2-failure
  escape hatch, iOS read-probe, and a shared **degraded "steps not connected"**
  app state (Phase 2).
- Notification permission ask relocated to first mystery-box open, with a
  session-count backstop (Phase 2).
- Single-source-of-truth `isOnboarding` (fixes a latent 4-copy divergence bug).
- Inline rename affordance on first Home render (Phase 3).
- Referred users land on their inviter's race instead of the generic Daily intro
  (Phase 4).
- Server-side guarantee that a signup never enrolls in zero races, and
  starter-reward eligibility unpinned from `DAILY_10K`.
- Full activation funnel instrumentation + `onboardingSessionId` correlation +
  an admin funnel view (Phase 5).
- Admin UI switches for all client-served feature flags.
- **Tutorial revamp: 10 steps → 5**, moved back into the v3 critical path, with
  evicted concepts becoming just-in-time tips (§5.11).
- Fix the team-lead-change push routing typo (§5.12) — unrelated rider.

### Non-goals

- **Character pick during onboarding.** Cut by owner decision — characters are
  paid shop items (`AccessorySlot.CHARACTER`) with no free tier; granting one at
  signup is an economy change, not an onboarding change.
- Building out the full just-in-time tip set. The *mechanism* plus three tips
  ship here (§5.11.6); the remaining concepts are a deliberate follow-up.
- Interactive/tap-through tutorial steps. Owner chose passive tap-through; the
  spotlight keeps swallowing taps as it does today.
- Changing sign-in providers, the auth token flow, or the display-name generator.
- Any new push notification type. The notification ask promises only what
  already ships (§5.4).
- Backfilling historical activation data. The funnel starts accumulating from
  the deploy forward.

---

## 3. Decisions taken (owner, 2026-07-26)

| # | Question | Decision |
|---|---|---|
| 1 | Roadmap scope | All five phases in one batch |
| 2 | Health gate posture | **Keep hard-blocking**, better framing + recovery path |
| 3 | iOS undetectable denial | **Read-probe + recovery surface** — do not re-block at the gate; arm a persistent reconnect banner when steps stay 0 |
| 4 | Android hard denial | **Settings deep-link + escape after 2 failed attempts** into the degraded state |
| 5 | Notification ask timing | **On first mystery-box open.** Copy must be vague and race-oriented — there is no box-ready push |
| 6 | Character pick | **Cut** from onboarding |
| 7 | Empty-state enrollment | **Fix both** — guarantee enrollment, and unpin starter reward from `DAILY_10K` |
| 8 | Analytics depth | **Full session funnel + admin view** |
| 9 | Referral landing | **Inviter's race replaces the Daily intro** when available |
| 10 | Admin flag UI | **All client-served flags** (the `featureFlags` envelope) |
| 11 | Tutorial placement | **Blocking, but tiny** — back in the v3 critical path at ~15–20s |
| 12 | Tutorial content | **5 steps**: walk → race → boxes → rivals → coins. The other 12 concepts become JIT tips |
| 13 | Tutorial interactivity | **Passive tap-through.** Reuse existing spotlight mechanics; no hit-testing work |
| 14 | Tutorial test edits | **Authorized, tightly scoped** — two files only, enumerated in §5.11.7 |
| 15 | Team-lead push fix | **Both halves** — backend emits the string shipped clients match, client accepts both |

**Reconciling #2 with #3/#4.** "Hard-blocking" is the default posture, not an
absolute. The gate blocks until the OS has demonstrably stopped cooperating —
two failed Android attempts, or an inconclusive iOS probe. Both escape paths
land in the *same* degraded state (§5.2), so this is one implementation, not
two. A user who simply hasn't tapped Allow yet is still blocked.

---

## 4. Current-state findings (the audit this spec is built on)

These are load-bearing. Each is cited so the implementing agents can verify.

### 4.1 The iOS health gate is not actually a gate

`lib/services/health_service.dart:154-162`:

```dart
    if (!requested) return false;

    // Persist that the user has gone through the authorization flow.
    // Note: iOS always returns true here regardless of what the user chose,
    // and hides read-permission status for privacy. We cannot detect revocation.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHealthAuthorized, true);
```

An iOS user who taps **Don't Allow** passes the gate, reaches Home, and races
with 0 steps indefinitely. `restoreHealthAuthState()` (`:99-103`) only re-reads
the persisted bool, so revocation is never detected either.

### 4.2 The Android health gate has a genuine dead end

`lib/screens/main_shell.dart:684-722` — on `HealthSetupResult.denied` the user
gets an error string instructing them to open Health Connect settings manually.
`OnboardingPermissionGate` (`lib/widgets/onboarding_permission_gate.dart:12-76`)
renders exactly one button and has no skip, no dismiss, no back. If the OS stops
re-showing the prompt after a second denial, the user cannot proceed — and
`isOnboarding` suppresses the entire tab bar (`main_shell.dart:2301`), so there
is no app to fall back to.

### 4.3 There is no degraded mode and no reconnect surface

`main_shell.dart:2111-2142` renders `OnboardingFlow` as the *only* content when
`isOnboarding`. `_restoreAndFetch` hard-returns before loading anything when
health isn't authorized (`:613-644`, esp. `:622`). A full-repo grep finds **no**
"reconnect health" UI anywhere — no settings row, no banner, no revocation
detection. Contrast notifications, which do have re-entry points
(`lib/screens/settings_screen.dart:533-582`,
`lib/screens/race_detail_screen.dart:2814-2831`).

`lib/screens/tabs/home_tab.dart:40-47, 90-97` still accepts `healthAuthorized` /
`onEnableHealth` props but never reads them — dead props, confirmed by the
comment at `:128-130`.

### 4.4 `isOnboarding` is duplicated four times and three copies are wrong

Canonical, `main_shell.dart:2098-2103`:

```dart
    final isOnboarding = widget.authService.onboardingV2Enabled
        ? !_healthAuthorized || !widget.authService.firstRaceOnboardingSeen
        : !_healthAuthorized ||
              _notificationsState == null ||
              !widget.authService.tutorialOnboardingSeen ||
              !widget.authService.firstRaceOnboardingSeen;
```

The copies at `:324-328`, `:431-435`, and `:520-524` **omit
`!tutorialOnboardingSeen`** from the v1 branch. Consequence: under v1 a
share-link drain or inviter-race offer can fire while the user is still sitting
on the tutorial step. The v2 branch also omits `notificationsState` even though
v2 renders the notifications gate, so the drain guards consider a user on that
gate "not onboarding".

### 4.5 A signup can silently enroll in zero races

`src/modules/races/commands/autoEnrollNewUser.js:117-120` queries
`{ seedId: { not: null }, status: { in: ["ACTIVE","PENDING"] } }`. The whole
function is wrapped in a warn-only try/catch (`:145-151`). A user ends up in
nothing if no `RaceSeed` is active, or every seeded race is at
`maxParticipants` (`:124-125` `continue`s), and gets no welcome boxes if the
only seeded race is PENDING (`:130`).

This propagates: `src/routes/onboarding.js:11-26` pins starter-reward
eligibility to an ACTIVE race whose `seed.kind === "DAILY_10K"`, so the same
user's 100-coin claim 403s with `STARTER_REWARD_NOT_ELIGIBLE` (`:67-72`).

### 4.6 The analytics pipeline exists and is 85% unwired

`ActivationEvent` ingestion is real and production-ready:
`src/modules/analytics/routes.js:143-167`, `POST /analytics/activation-events`,
idempotent via client-supplied `id` + `createMany({skipDuplicates:true})`
(`:155-158`). Table at `prisma/schema.prisma:422-440` — and it **already has an
`onboardingSessionId` column** (`:426`).

`ALLOWED_EVENT_NAMES` (`routes.js:9-30`) defines 20 names. The frontend emits
**three**: `onboarding_started` (`main_shell.dart:212-215`), `health_cta_tapped`
(`:685`), `daily_opened` (`:1740`). `ActivationAnalyticsService.record()`
supports `onboardingSessionId` (`lib/services/activation_analytics_service.dart:73-74`)
but **no caller ever passes it**, so nothing correlates into a funnel.

`health_cta_tapped` records the *tap*, never the outcome — even though
`allowedContext['result']` already permits `{granted, denied, ...}` (`:45`).

There is no `home_reached` / `signup_completed` event, so "how many signups
reach the home screen" is not answerable today.

### 4.7 `onboardingV2Enabled` is toggleable by API but has no UI

`PATCH /admin/settings` (`src/modules/admin/routes.js:137-180`) already accepts
any key in `KNOWN_FLAGS`, so the flag can be flipped with an admin bearer token
today. But `lib/screens/admin_screen.dart` renders only two switches —
`bannerAdsEnabled` and `dualBoxBannersEnabled` (`:257, 261, 290-291, 344, 374`).
Adding the rest requires **zero backend change**.

Note: `onboardingV2Enabled` is read nowhere in backend logic. It is purely
client-side remote config. Flag cache TTL is 30s (`appSettings.js:75`), so a
toggle takes up to 30s to reach all pm2 cluster workers.

### 4.8 No box or powerup push exists

Confirmed by exhaustive grep. `POWERUP_EARNED` is emitted as an event but its
only listener is a `console.log` (`src/modules/notifications/eventHandlers.js:64`).
The only box-adjacent push is `DAILY_REWARD_REMINDER_17/_21` — a nag about an
*unclaimed daily box*, not a box-ready alert — and per the rollout comment at
`src/index.js:115-124` it is the push most likely disabled in prod.

**This directly constrains the notification-ask copy.** See §5.4.

---

## 5. Design

### 5.1 Flag strategy — why a new `onboardingV3Enabled`

`onboardingV2Enabled` cannot carry this spec's changes. Builds already in the
wild (2.0.1) contain the v2 code path; flipping v2 on today immediately changes
their behavior — that is Phase 1, and it is safe and desirable. But the changes
in this spec ship in a *new* binary, and we need to be able to roll them back
without an App Store submission.

Therefore:

- `onboardingV2Enabled` — existing, default `false`. **Flip to `true` in prod as
  Phase 1, independently of this build.** Meaning is unchanged: skip the
  blocking tutorial gate.
- `onboardingV3Enabled` — **new**, default `false`. Read only by builds carrying
  this spec. Gates: health gate rework, degraded state, notification relocation,
  referral-first landing, rename affordance. When `false`, a v3-capable binary
  behaves exactly as v2 does today.

Frozen old clients ignore `onboardingV3Enabled` entirely — they read specific
keys off `featureFlags` and unknown keys are inert. No version gate is needed on
the server side.

**Precedence:** v3 implies v2. If `onboardingV3Enabled` is true, treat
`onboardingV2Enabled` as true regardless of its stored value, so a
half-configured pair can't produce an undefined flow.

### 5.2 The degraded "steps not connected" state

One state, reached by three routes: the Android escape hatch, an inconclusive
iOS probe, and later revocation. This is the single largest new surface in the
spec.

**Definition.** The user is `healthAuthorized == false` *or*
`stepsProbeInconclusive == true`, but has been let into the app. They get:

- Full tab navigation, all tabs, normal chrome.
- A persistent, **non-dismissible** banner pinned above the tab bar:
  "Steps aren't connected — you're scoring 0. **Fix this**". Tapping re-runs the
  permission request, or deep-links to OS settings if that has already failed.
- A "Connect Health" row in `settings_screen.dart`, styled like the existing
  `_NotificationToggle` (`:533-582`).
- Race screens render normally. The user's own step count shows `0` with the
  banner explaining why — **not** an error state, not a spinner.

**What it must not do:** it must not suppress the ad banner or tab bar (both
currently gated on `!isOnboarding`, `main_shell.dart:2282, 2301`) — the user is
no longer onboarding, so those render normally.

**Exit.** When a permission request subsequently succeeds *and* a probe returns
non-zero steps, clear the state, drop the banner, and fire
`health_recovered`.

**Interaction with `firstRaceOnboardingSeen` (critical).** A user who escapes
via the Android hatch never reaches the daily-intro step, so
`firstRaceOnboardingSeen` stays false and `isOnboarding` would loop them back
into the gate on next launch. **The escape hatch must set
`firstRaceOnboardingSeen` locally** (via
`markFirstRaceOnboardingSeenLocally`, `auth_service.dart:819`) at the moment of
escape. Without this the escape is not an escape.

**Sign-out.** `AuthService.signOut()` already clears persisted health auth
(`auth_service.dart:696`). The new degraded-state keys must be cleared in the
same place, for the same reason — device-scoped state must not leak across
accounts.

### 5.3 Health gate rework

**Framing.** Replace the bare permission screen with a payoff preview: show the
race card the user was just auto-enrolled into, with their position and step
count blurred, and the CTA "Connect steps to see your rank". Copy stays honest
about scope — the existing body text ("We do not read routes, workouts, or
location") is good and should survive. Load the `mobile-design` and
`frontend-design` skills before touching this screen.

**Attempt tracking.** `OnboardingPermissionGate` gains an attempt counter,
persisted (survives an app kill mid-onboarding).

**Android ladder:**

| Attempt | Behavior |
|---|---|
| 1 | Normal request. On `denied`, show the existing explanatory error + "TRY AGAIN". |
| 2 | Request again. On `denied`, swap the primary CTA to **"OPEN HEALTH CONNECT SETTINGS"** (programmatic launch), and reveal a secondary text button: **"Continue without steps"**. |
| 3+ | Both buttons remain. |

`HealthSetupResult.needsHealthConnect` (`health_service.dart:132-140`) is *not*
an attempt — it already opens the Play Store and is a legitimate retry.

**iOS probe.** iOS never returns `denied`, so instead: immediately after
`requestAuthorization()` returns, read total steps for the trailing 7 days.

- Non-zero → conclusive success. Proceed normally.
- Zero → **inconclusive.** We cannot distinguish denial from a genuinely new or
  idle device, so per decision #3 we do **not** re-block. Let the user through,
  set `stepsProbeInconclusive = true`, and arm the degraded banner.
- Re-probe on every app resume. The banner clears the moment steps appear, which
  makes the false-positive case (a real user who genuinely had 0 steps) self-heal
  without any user action.

**Do not arm the banner instantly on iOS.** A user who signs up at 6am with a
legitimately empty step history would see an alarming banner within seconds.
Require **both** conditions: probe returned zero **and** ≥6 hours elapsed since
onboarding completed. Until then the state is latent, not visible.

### 5.4 Notification ask relocation

Removed from `OnboardingFlow` entirely under v3. Instead:

**Primary trigger — first mystery-box open.** Fire the ask immediately after the
first box-reveal animation completes, once per install, only if
`getPermissionState()` returns `null` (`notification_service.dart:215-220`).
New users receive 3 welcome boxes at signup
(`autoEnrollNewUser.js:138-144`), so this fires reliably inside session one.

**Copy constraint (owner decision #5).** There is no box-ready push and no
powerup-earned push (§4.8). The copy must **not** imply one. Use vague,
race-oriented framing:

> **Stay in the race**
> Get notified about what's happening in your races.
> *[ENABLE ]  [ NOT NOW ]*

This is honest — `RACE_STARTED`, `PLACEMENT_CHANGED`, `RACE_ENDING_SOON`,
`POWERUP_USED`, `RACE_COMPLETED` and the `TEAM_*` family all exist and all
route correctly today.

**Backstop.** If the user never opens a box (possible if enrollment still
lands them somewhere box-less), ask on the **third** app session regardless.
Without this, a subset of users would never be asked at all — a regression
against today's behavior, where everyone is asked during onboarding.

**"Not now" is not permanent.** Declining in-app (as opposed to at the OS
prompt) leaves `getPermissionState()` as `null`, so the backstop can still fire.
Cap total asks at two per install; the Settings toggle
(`settings_screen.dart:533-582`) remains the permanent path.

**`isOnboarding` consequence.** Under v3, `notificationsState` is not part of
the expression at all.

### 5.5 `isOnboarding` — single source of truth

Extract to one getter on `_MainShellState` and replace all four inline copies
(`main_shell.dart:324-328, 431-435, 520-524, 2098-2103`):

```dart
  bool get _isOnboarding {
    final auth = widget.authService;
    if (auth.onboardingV3Enabled) {
      // v3: notifications are no longer a gate; the degraded state is not
      // onboarding. The 5-step tutorial IS a gate again — see §5.11.3.
      return !_healthGateSatisfied ||
          !auth.tutorialOnboardingSeen ||
          !auth.firstRaceOnboardingSeen;
    }
    if (auth.onboardingV2Enabled) {
      return !_healthAuthorized || !auth.firstRaceOnboardingSeen;
    }
    return !_healthAuthorized ||
        _notificationsState == null ||
        !auth.tutorialOnboardingSeen ||
        !auth.firstRaceOnboardingSeen;
  }
```

where `_healthGateSatisfied` is `_healthAuthorized || _escapedHealthGate`.

This is a **behavior fix for v1 as well** — the three divergent copies currently
let share-link drains fire during the tutorial step. Call it out in the PR; it
changes v1 behavior for anyone still on the old flow.

### 5.6 Server-side enrollment guarantee

Two changes in `autoEnrollNewUser.js`:

1. **Capacity relaxation for signups.** If every seeded race is full, join the
   most recently started ACTIVE seeded race anyway, over capacity. Rationale: a
   full race is a soft product constraint; a dead-on-arrival signup is not
   recoverable. Log when this fires.
2. **Zero-enrollment alarm.** If the loop completes with no joins, `console.warn`
   with a distinctive tag (`AUTO_ENROLL_EMPTY`) including the seeded-race count,
   so it's greppable in prod logs. Do **not** mint a race on the fly — that risks
   creating unbounded races if a seed misconfiguration persists.

And in `src/routes/onboarding.js:11-26`, `findActiveDailyMembership` drops the
`seed.kind === "DAILY_10K"` constraint and accepts an ACCEPTED participant row
in **any** ACTIVE seeded race.

**Coin-minting note.** Unpinning widens starter-reward eligibility, which mints
more 100-coin grants.

To be precise about what is and isn't protected: there are **two distinct**
100-coin onboarding grants — the legacy tutorial reward
(`POST /tutorial/complete-reward`) and the starter reward
(`POST /onboarding/starter-reward/claim`). Both deliberately write the *same*
ledger key — `reason: "tutorial_complete"`, `refId: userId`
(`src/routes/onboarding.js:6-9`, comment: *"Deliberately identical to the legacy
tutorial grant… this is one ledger key across old tutorial and new Daily
activation flows"*). `awardCoins` is idempotent on `(userId, reason, refId)`,
with the unique ledger index — not the preflight read — as the concurrency
boundary (`src/shared/economy/awardCoins.js:14-48`).

So a user who completes the tutorial **and** claims the starter reward receives
100 coins total, not 200. That protection is unaffected by this change.

The exposure from unpinning is therefore bounded and non-stacking: **one**
100-coin grant, once, to a user who today receives **zero** because their only
ACTIVE seeded race isn't `DAILY_10K`. Watch the `tutorial_complete` grant rate
for a week post-deploy, but the per-user ceiling cannot move.

### 5.7 Inline rename affordance (Phase 3)

The generated name (`SwiftCapybara07`) is good default friction-reduction but
users don't know it's changeable. On first Home render after onboarding, show a
one-time inline chip under the greeting: *"You're **SwiftCapybara07** — tap to
change"*. Tapping opens the existing display-name editor. Dismisses permanently
once tapped or after being shown three times.

No new endpoint — `PUT /me/display-name` already exists
(`src/modules/users/commands/setDisplayName.js`).

### 5.8 Referral-first landing (Phase 4)

When the user was referred *and* the inviter is in a joinable race, the
post-permission step shows that race instead of the generic Daily intro:
*"Race Priya — she's 2,400 steps in"*, CTA **"JOIN PRIYA'S RACE"**.

Requires one new endpoint (§6.3). **Must degrade safely**: if the endpoint 404s,
errors, times out, or returns `{ race: null }`, fall through to
`OnboardingDailyIntroStep` exactly as today. The referral welcome step
(`onboarding_flow.dart:346-439`) already has this fallback shape — mirror it.

### 5.9 Analytics funnel (Phase 5)

**Session correlation.** Mint an `onboardingSessionId` (UUID) at first launch
post-signup, persist it, and pass it on **every** `record()` call. The column
already exists (`schema.prisma:426`); the client parameter already exists
(`activation_analytics_service.dart:73-74`). This is pure wiring.

**Events to emit.** Wire the existing allowlisted names that are currently dead,
plus new ones:

| Event | Status | When |
|---|---|---|
| `onboarding_started` | exists, emitted | First onboarding render (extend to v1/v3, not just v2) |
| `health_cta_tapped` | exists, emitted | Unchanged |
| `health_result` | **new** | Outcome of every attempt: `result ∈ {granted,denied,unsupported,failed}` |
| `health_escaped` | **new** | User took the Android escape hatch |
| `health_probe_inconclusive` | **new** | iOS probe returned 0 steps |
| `health_recovered` | **new** | Degraded state cleared |
| `notif_prompt_shown` | **new** | The relocated ask rendered |
| `notif_result` | **new** | `result ∈ {granted,denied,dismissed}` |
| `daily_intro_viewed` | allowlisted, dead | Daily intro rendered |
| `daily_opened` | exists, emitted | Unchanged |
| `referral_continued` | allowlisted, dead | Referral welcome dismissed |
| `inviter_race_shown` | **new** | Referral-first landing rendered |
| `home_reached` | **new** | **The funnel denominator's other end** — first Home render with `isOnboarding == false` |
| `tutorial_opened/completed/skipped` | allowlisted, dead | v1 only; wire for completeness |
| `starter_reward_claimed` | allowlisted, dead | Claim succeeds |

**Backend allowlist resilience (compat-critical).** `routes.js:70-77` currently
**400s the entire batch** on one unknown event name. Since batches are 1–50
events, a single new name from a newer client poisons a whole batch of otherwise
valid events. Change unknown-*name* handling to: drop that event, keep the rest,
still return `202` with an accurate `accepted`/`inserted` count. Malformed
structure, bad `appVersion`, bad `platform`, and disallowed *context* values keep
their current 400 behavior. This makes every future client-side event addition
safe regardless of deploy order.

**Admin funnel view.** Extend `getAdminStats.js` with a session-joined query:
count distinct `onboardingSessionId` reaching each stage, over 7/30d, split by
platform. Output shape in §6.4.

### 5.10 Admin flag UI

Add switches to `lib/screens/admin_screen.dart` for every flag in the
`featureFlags` envelope: `onboardingV2Enabled`, `onboardingV3Enabled`,
`teamRacesEnabled`, alongside the existing `bannerAdsEnabled` and
`dualBoxBannersEnabled`. Server-only flags (`buyInEditEnabled`,
`tournamentsEnabled`, `fundedPrizePoolsEnabled`, `stepSampleBucketMinutes`) stay
out of the UI per decision #10.

Backend change required: add `onboardingV3Enabled` to `KNOWN_FLAGS` and to the
`withRuntimeFlags` envelope. `PATCH /admin/settings` needs no change — it
already accepts any `KNOWN_FLAGS` key.

Show the 30s propagation caveat in the UI ("takes up to 30s to reach all
servers") so a toggle that appears not to work isn't re-tapped.

### 5.11 Tutorial revamp — 10 steps → 5

**The setup nobody expects.** Flipping `onboardingV2Enabled` on (Phase 1) does
not merely de-emphasise the tutorial — it **deletes it from onboarding
entirely**. `onboarding_flow.dart:145-156` early-returns the Daily intro before
execution ever reaches the tutorial check at `:159`, and
`test/onboarding_v2_test.dart:60` asserts `START TUTORIAL` is never rendered
under v2. After Phase 1 the only path to the tutorial is Profile → SETTINGS →
HELP & LEGAL → **VIEW TUTORIAL** (`settings_screen.dart:296-319`).

So this section is not "trim the tutorial." It is **deliberately putting a
much smaller one back into the critical path.**

**What's wrong with the current one** (`lib/tutorial/tutorial_screen.dart:38-123`):

- **10 spotlight steps teaching 17 distinct concepts** — shop, inventory,
  referral links, prize-pool funding, leaderboard filters — before the user has
  walked a single step.
- **Zero interactivity.** `spotlight_overlay.dart:52-54` is an opaque
  `GestureDetector` swallowing every tap. It is a slideshow wearing real screens.
- **Steps 4 and 5 are near-duplicates**, both about finding/adding friends, both
  ending with the identical clause *"race and rank against each other."*
- Teaches the word "rank" twice (steps 4, 5) while never explaining Ranked.

**What is worth keeping.** `TutorialRealHost`
(`lib/tutorial/tutorial_real_screens.dart:22-166`) hosts the genuine production
widgets against a full mock backend (`tutorial_preview_data.dart:22-340`). That
infrastructure is good and is **reused as-is** — only the step list and copy
change.

#### 5.11.1 The new five steps

Passive tap-through (owner decision — keep the existing spotlight mechanics; do
not build tap-through hit-testing). `$healthSource` resolves as today
(`tutorial_screen.dart:39`).

| # | Page | Spotlight key | Title | Body |
|---|---|---|---|---|
| 1 | home | `home.steps` | **Just walk.** | "Bara counts your steps from $healthSource automatically. Nothing to start, nothing to log." |
| 2 | races | `races.card` | **Race your friends.** | "Most steps when the clock runs out wins." |
| 3 | races | `races.box` | **Grab mystery boxes.** | "Walking earns boxes full of powerups." |
| 4 | raceDetail | `raceDetail.powerups` | **Mess with rivals.** | "Boosts and shields for you. Freezes and steals for them." |
| 5 | home | `home.shop` | **Win coins.** | "Every race pays out. Spend coins on gear for your capy." |

Bodies are ≤14 words. Titles are declarative sentences, not noun phrases —
"Just walk." reads as an instruction; "Track today" reads as a feature name.

**`races.box` already exists as an anchor and is currently targeted by no step**
(`tutorial_real_screens.dart:129`, covered by `test/races_tab_test.dart:109,127`).
Step 3 finally uses it. No new anchor keys are required — every key above is
already wired.

**Page sequence** is home → races → races → raceDetail → home. The final hop
back to home is intentional: the tutorial ends on the screen the user is about
to be dropped into.

#### 5.11.2 Placement in the v3 flow

Referral welcome (if any) → health gate → **tutorial (5 steps)** → inviter race
*or* daily intro → Home.

The tutorial sits **before** the race intro, because the race intro's CTA drops
the user straight into a live race — they should know what a race is first.
Budget: ~15–20 seconds, five taps.

**SKIP stays on every step.** A blocking step with no escape is the exact
failure mode §5.2 exists to fix. Skipping forfeits the reward, as today
(`tutorial_screen.dart:256-261`).

#### 5.11.3 `isOnboarding` consequence — supersedes §5.5

Because the tutorial is back in the critical path, `tutorialOnboardingSeen`
**re-enters** the v3 expression. The getter in §5.5 becomes:

```dart
    if (auth.onboardingV3Enabled) {
      return !_healthGateSatisfied ||
          !auth.tutorialOnboardingSeen ||
          !auth.firstRaceOnboardingSeen;
    }
```

Notifications remain absent (§5.4). **v2's branch is unchanged** — the tutorial
must stay invisible under v2 so `test/onboarding_v2_test.dart:60` keeps passing
unmodified.

#### 5.11.4 The abandonment hole

`TutorialScreen` has no `PopScope`/`WillPopScope`, so an OS back-swipe pops the
route without ever calling `_finish` — no reward, no analytics — while
`main_shell.dart:1785` marks it seen anyway on the `await` return. Tolerable
when the tutorial was optional; not tolerable now that it gates the app. Add a
`PopScope` that routes a back-gesture through the same path as SKIP.

#### 5.11.5 The 100 coins

Unchanged: 100 coins for reaching the last step and tapping DONE
(`tutorial_screen.dart:272-279` → `POST /tutorial/complete-reward`). It shares
one ledger key with the starter reward (§5.6), so a v3 user who completes the
tutorial has effectively already collected the starter reward — the latter
becomes a no-op for them. That is correct and needs no code change; it is stated
here so nobody "fixes" it into a double grant.

#### 5.11.6 Concepts evicted, and where they go

Removed from the tutorial: milestones, shop/inventory detail, friend search,
referral invite links, prize-pool funding mechanics, leaderboard filters, race
wins as a metric. Never covered anyway: ranked, teams, tournaments, streaks,
race chat.

These move to **just-in-time tips** — a one-shot coach tip fired the first time
a user actually reaches the surface, keyed by a persisted seen-set.

**Scope discipline:** this batch builds the *mechanism* plus exactly **three**
tips. The rest are a deliberate follow-up, not an oversight:

| Trigger | Tip |
|---|---|
| First milestone reached on Home | "Tap it to claim your coins." |
| First time the Friends tab opens | "Add friends to race them. Invite one and you both earn coins." |
| First leaderboard view | "Switch between everyone and just your friends." |

**No JIT tip fires on box open.** Boxes and powerups are now taught by tutorial
steps 3–4, and the notification ask already fires there (§5.4). Two
interruptions on one trigger would be worse than the problem being solved. The
notification ask keeps that moment to itself.

#### 5.11.7 Authorized test edits (owner sign-off, 2026-07-26)

Repo rules forbid agents editing existing tests. Two are structurally impossible
to preserve through any tutorial revamp, and the owner has authorized changes to
**these two only**:

1. **`test/tutorial_screen_test.dart`** — taps `find.text('NEXT')` nine times and
   asserts per-step strings (`'13,420'`, `"Today's coins"`, `'SHOP'`,
   `'Search by display name'`, `'@Maya Chen'`,
   `'INVITE FRIENDS & EARN COINS'`, `'RACES'`, `'Weekend 10K'`,
   `'LEADERBOARD'`). Rewrite for four NEXT taps and the five new steps. The SKIP
   test at `:64-79` must keep asserting SKIP exists and fires `onComplete`.
2. **`test/dark_theme_coverage_test.dart:66-79`** — asserts the literal
   `'Track today'`. Change that string to `'Just walk.'`. **Do not** touch
   `:34-40` (the `OnboardingTutorialStep` / "Earn your first 100 coins"
   assertion) — that step is unchanged.

**Explicitly NOT authorized**, and must pass unmodified:
`test/onboarding_v2_test.dart`, `test/races_tab_test.dart`,
`test/home_tab_no_help_button_test.dart`, and every fixture-only file that sets
`tutorialOnboardingSeen: true` to bypass onboarding
(`ad_placements_test.dart`, `main_shell_friends_and_public_test.dart`,
`main_shell_nav_order_test.dart`, `main_shell_team_share_link_test.dart`).

#### 5.11.8 Analytics

Wire the three already-allowlisted, never-emitted names:
`tutorial_opened`, `tutorial_completed`, `tutorial_skipped`
(`activation_analytics_service.dart:28-30`, `analytics/routes.js:18-20`), each
carrying `onboardingSessionId`. Add per-step drop-off via
`context.source` — this is the number that tells you whether five steps is still
too many.

---

### 5.12 Team-lead-change push routing fix — UNRELATED RIDER

> **This item has nothing to do with onboarding.** It surfaced while enumerating
> the push catalog (needed to write honest notification-ask copy, §5.4) and is
> carried here only because it is small and was already in hand. It shares no
> code, no flag, and no deploy dependency with the rest of the spec. **If this
> batch needs trimming, cut this section first** — nothing else references it.

**The bug.** The backend sends `payload.type = "TEAM_LEAD_CHANGED"`
(`src/modules/notifications/notificationHandlers.js:494`). The client's route
switch matches `'TEAM_LEAD_CHANGE'` — no trailing D
(`lib/services/notification_service.dart:350`). The alert displays fine, but
tapping it does nothing: the type falls through to the default case and never
resolves to race detail.

**Blast radius, verified by grep.** The backend uses `TEAM_LEAD_CHANGED`
consistently in all 3 source sites and all 5 test assertions. The frontend uses
`TEAM_LEAD_CHANGE` in exactly 2 places: the switch case and one existing test.

**The fix is two-sided. Both halves are in scope (owner approved 2026-07-26).**

**Half 1 — backend emits the string every shipped client understands.** Change
the push `payload.type` at `notificationHandlers.js:494` from
`"TEAM_LEAD_CHANGED"` to `"TEAM_LEAD_CHANGE"`. This is the half that matters:
100% of deployed binaries match the D-less string, so deep-linking is repaired
for **every existing user the moment the backend deploys**, with no App Store
wait.

> **Explicit owner sign-off, required because it edits an existing test.**
> `test/handlers/notificationHandlers.teamRaces.test.js:87` asserts
> `payload.type === "TEAM_LEAD_CHANGED"`. The backend agent is authorized to
> change **that one assertion string only**. It may not touch any other
> assertion in that file, and it may not touch the four event-bus assertions
> (`test/jobs/placementRecompute.teamRaces.test.js:107,116,128,150,164`) — those
> cover the internal event name, which is not changing.

**Half 2 — client accepts both strings**, so the fix is order-independent and
survives any future re-flip:

```dart
      case 'TEAM_LEAD_CHANGE':   // what the backend sends after this batch
      case 'TEAM_LEAD_CHANGED':  // what it sent before; keep both forever
```

A two-line fallthrough in `notification_service.dart:350`. Breaks zero tests —
`test/team_race_push_routing_test.dart:10-12` asserts the D-less string routes,
which remains true.

**Why both halves, not just the backend.** Accepting both on the client makes
the two deploys independent: whichever lands first, no user is worse off at any
point. Backend-only would work today but would silently re-break if anyone ever
"corrected" the spelling back.

**Scope boundary.** The internal event-bus name
(`events.emit("TEAM_LEAD_CHANGED")`, `placementRecompute.js:161`, consumed at
`notificationHandlers.js:468`) is a **separate concern** and is NOT touched.
Only the outbound push `payload.type` string changes.

---

## 6. API contract

**This section is pinned before either agent implements. The frontend agent
consumes exactly this and invents nothing.**

### 6.1 `GET /me`, `POST /auth/apple`, `POST /auth/google` — envelope addition

One additive key in `featureFlags`. No other change.

```jsonc
{
  "user": {
    "id": "…",
    "displayName": "SwiftCapybara07",
    "featureFlags": {
      "bannerAdsEnabled": false,
      "dualBoxBannersEnabled": false,
      "teamRacesEnabled": true,
      "onboardingV2Enabled": true,
      "onboardingV3Enabled": false,   // NEW, default false
      "stepSampleBucketMinutes": 5     // omitted for clients < 1.7.1
    }
  },
  "sessionToken": "…"
}
```

**Old-client compat:** frozen clients read named keys off `featureFlags` and
ignore unknown ones. Adding `onboardingV3Enabled` is inert for every shipped
build. No `X-App-Version` gate needed.

### 6.2 `PATCH /admin/settings` — no shape change

`onboardingV3Enabled` becomes accepted automatically once it is in
`KNOWN_FLAGS`. Boolean validation path at `admin/routes.js:167-171` already
covers it.

```jsonc
// Request
{ "onboardingV3Enabled": true }
// 200
{ "settings": { "onboardingV2Enabled": true, "onboardingV3Enabled": true, … } }
// 400 — unknown key
{ "error": "Unknown setting: foo" }
```

### 6.3 `GET /referrals/inviter-race` — NEW

Returns the referring user's most joinable current race, for the referral-first
landing.

**Auth:** required. **Query params:** none — the inviter is derived from the
caller's `Referral` row.

```jsonc
// 200 — inviter found and is in a joinable race
{
  "race": {
    "id": "race_abc",
    "name": "Weekend Warriors",
    "status": "ACTIVE",
    "endsAt": "2026-07-28T04:00:00.000Z",
    "participantCount": 6,
    "alreadyJoined": false
  },
  "inviter": {
    "id": "user_xyz",
    "displayName": "Priya",
    "profilePhotoUrl": null,
    "steps": 2400
  }
}

// 200 — no referral, no inviter, or no joinable race. NOT an error.
{ "race": null, "inviter": null }
```

**Selection rule:** among races where the inviter is an ACCEPTED participant and
`status IN (ACTIVE, PENDING)`, prefer ACTIVE over PENDING, then most recent
`startedAt`. Exclude races the caller has already joined (set
`alreadyJoined: true` and still return it, so the UI can say "you're both in
this one"). Exclude tournament matchup races. Exclude races at capacity.

**Errors:** `401` unauthenticated. No other error case — every miss is
`{ race: null }`.

**Old-client compat:** purely additive endpoint. No existing client calls it. A
new client hitting an old backend gets `404` and **must** fall back to the Daily
intro (§5.8) — this is the single most important degradation path in the spec,
because backend and app deploy independently.

### 6.4 `POST /analytics/activation-events` — behavior change, no shape change

Request and response shapes are **unchanged**. The only change is unknown-name
handling:

```jsonc
// Request (unchanged)
{ "events": [
    { "id": "uuid", "name": "home_reached", "onboardingSessionId": "uuid",
      "context": { "source": "onboarding" },
      "appVersion": "2.1.0", "platform": "ios",
      "timestamp": "2026-07-26T18:00:00.000Z" }
] }

// 202 — was: 400 if any name unknown. Now: unknown names dropped, rest accepted.
{ "accepted": 1, "inserted": 1 }
```

Still 400 on: malformed body, `events` empty or >50, unknown top-level keys,
bad `appVersion`/`platform`, disallowed **context** keys or values, timestamps
outside the ±window. Only unknown **names** become a silent per-event drop.

New names added to `ALLOWED_EVENT_NAMES`: `health_result`, `health_escaped`,
`health_probe_inconclusive`, `health_recovered`, `notif_prompt_shown`,
`notif_result`, `inviter_race_shown`, `home_reached`.

> **Corrected 2026-07-26 during the build.** An earlier draft of the example
> above showed `occurredAt` as the request field. That was wrong — the real
> field is **`timestamp`**; `occurred_at` is only the DB column.
> `validateActivationEvent` 400s on unknown top-level keys, so sending
> `occurredAt` would reject every batch. The shape is genuinely unchanged from
> today; only the name allowlist and unknown-name handling move.

**Old-client compat:** old clients send a subset of the allowlist. Widening the
allowlist and softening rejection can only increase what's accepted. Zero risk.

### 6.5 `GET /admin/stats` — additive section

```jsonc
{
  "…existing sections unchanged…",
  "onboardingFunnel": {
    "windowDays": 7,
    "byPlatform": {
      "ios": {
        "onboarding_started": 412,
        "health_cta_tapped": 401,
        "health_granted": 355,
        "health_escaped": 0,
        "health_probe_inconclusive": 22,
        "daily_intro_viewed": 350,
        "home_reached": 341
      },
      "android": { "…same keys…": 0 }
    }
  }
}
```

Counts are **distinct `onboardingSessionId`** per stage, not raw event counts.
Additive — the admin screen ignores unknown sections today, so an old admin
build is unaffected.

### 6.6 `GET /onboarding/starter-reward` — eligibility widened, shape unchanged

```jsonc
{ "eligible": true, "coins": 100, "claimed": false }
```

Unchanged response. Only the server-side predicate widens (any ACTIVE seeded
race, not only `DAILY_10K`). Old clients calling this simply see `eligible: true`
in cases where they previously saw `false` — strictly better, no shape change.

---

## 7. Data model / migrations

### Backend

**No schema migration is required.** Every table this spec needs already exists:

- `AppSetting` (`schema.prisma:1495-1502`) — `onboardingV3Enabled` is just a new
  row, created on first `setFlag`. `getFlag` returns the `KNOWN_FLAGS` default
  when no row exists (`appSettings.js:95-107`), so no backfill.
- `ActivationEvent` (`schema.prisma:422-440`) — already has
  `onboardingSessionId`, already indexed on `[name, createdAt]` and
  `[appVersion, platform, createdAt]`.

**One index to consider.** The funnel query groups by `onboardingSessionId`,
which is currently unindexed. If `EXPLAIN` shows a seq scan at prod row counts,
add `@@index([onboardingSessionId])` in a follow-up migration — do not add it
speculatively.

**Code-only change:** add `onboardingV3Enabled: false` to `KNOWN_FLAGS`
(`appSettings.js:12-71`) and to the `withRuntimeFlags` envelope
(`users/routes.js:120-131`).

### Frontend (SharedPreferences)

New keys, all device-scoped, all cleared in `AuthService.signOut()` alongside
the existing health-auth clear (`auth_service.dart:696`):

| Key | Type | Purpose |
|---|---|---|
| `auth_onboarding_v3_enabled` | bool | Mirrors the server flag, default `false` |
| `health_attempt_count` | int | Drives the Android ladder; survives app kill |
| `health_escaped_gate` | bool | User took the escape hatch |
| `health_probe_inconclusive` | bool | iOS probe returned 0 steps |
| `health_probe_armed_at` | int (epoch ms) | Start of the 6h latency before the banner shows |
| `onboarding_session_id` | String | UUID for funnel correlation |
| `notif_ask_count` | int | Cap of 2 |
| `notif_asked_after_box` | bool | Primary trigger fired |
| `app_session_count` | int | Drives the 3rd-session backstop |
| `rename_chip_shown_count` | int | Cap of 3 |

**Default-safe reads.** Every one must default to a value that reproduces
current behavior when absent, so an upgrade-in-place user is never worse off.

---

## 8. Frontend plan

### 8.0 Load the design skills first

Before any UI work the frontend agent **must** load `mobile-design` and
`frontend-design`. Non-negotiable per repo convention. The health gate, the
degraded banner, the notification ask, and the rename chip are all new visual
surfaces.

### 8.1 `lib/services/health_service.dart`

- Add `Future<int> probeTrailingSteps({int days = 7})`.
- Add `HealthSetupResult.inconclusive`.
- `setUpHealthAccess()` runs the probe on success; returns `inconclusive` when
  the probe is zero on iOS.
- Add `openPlatformHealthSettings()` — Health Connect settings intent on
  Android, `app-settings:` on iOS.
- Do **not** change the existing `_keyHealthAuthorized` semantics; the probe is
  additive state.

### 8.2 `lib/widgets/onboarding_permission_gate.dart`

- Accept `attemptCount`, `onOpenSettings`, `onEscape` (all optional/nullable).
- Render the secondary "Continue without steps" text button **only** when
  `onEscape != null` — the widget stays dumb, `MainShell` decides.
- Preserve the existing single-CTA layout when the new params are absent, so the
  notifications gate (v1/v2) is visually untouched.

### 8.3 `lib/screens/onboarding_flow.dart`

- Add the v3 branch. Order under v3: referral welcome (if any) → health gate →
  **[no notifications gate]** → inviter race step *or* daily intro.
- Keep the v1 and v2 branches byte-identical. The comment block at `:126-133`
  documents a previously-fixed ordering bug — do not regress it.
- New `OnboardingInviterRaceStep`, modeled on `OnboardingDailyIntroStep`
  (`:179-340`) including its `initState` fetch + fallback shape.

### 8.4 `lib/screens/main_shell.dart`

- Replace all four `isOnboarding` copies with the `_isOnboarding` getter (§5.5).
- `_enableHealthData`: increment the attempt counter, emit `health_result` with
  the outcome, handle `inconclusive`, wire the settings launcher.
- New `_escapeHealthGate()`: sets `health_escaped_gate`, calls
  `markFirstRaceOnboardingSeenLocally()`, emits `health_escaped`.
- Remove the notifications gate from the v3 path; add the box-open and
  third-session triggers.
- Add the degraded banner above the tab bar when the degraded predicate holds.
- Re-probe on resume; clear degraded state and emit `health_recovered` on
  success.
- `_restoreAndFetch` (`:613-644`) currently hard-returns when health isn't
  authorized. Under v3 it must proceed when `_escapedHealthGate` is true —
  otherwise the degraded user sees a permanently empty app.

### 8.5 `lib/services/activation_analytics_service.dart`

- Mint/persist `onboardingSessionId`; attach to every `record()` automatically
  rather than at each call site.
- Add the eight new names to the client-side allowlist (`:19-47`) — the client
  drops unknown names locally (`:57`), so this is required or the events never
  leave the device.

### 8.6 `lib/screens/settings_screen.dart`

- Add a "Connect Health" row mirroring `_NotificationToggle` (`:533-582`),
  visible whenever the degraded predicate holds.

### 8.7 `lib/screens/admin_screen.dart`

- Add switches for `onboardingV2Enabled`, `onboardingV3Enabled`,
  `teamRacesEnabled`. Reuse the existing switch pattern at `:290-291`.
- Add the 30s propagation note.

### 8.8 `lib/screens/tabs/home_tab.dart`

- Add the rename chip (§5.7).
- The dead `healthAuthorized` / `onEnableHealth` props (`:40-47, 90-97`) become
  **live** under v3 — the degraded state means HomeTab can now render with health
  unconnected. Update the stale comment at `:128-130`.

### 8.9 `lib/tutorial/tutorial_screen.dart` + the JIT tip mechanism

- Replace `_buildSteps()` (`:38-123`) with the five steps in §5.11.1. Keep the
  `healthSource` platform switch (`:39`).
- **Do not touch** `spotlight_overlay.dart` mechanics, `TutorialRealHost`, or
  `tutorial_preview_data.dart` — the hosting/mocking infra is reused unchanged.
  The `STEP n / 10` badge (`spotlight_overlay.dart:213`) is already derived from
  `stepCount`, so it becomes `STEP n / 5` for free.
- Add a `PopScope` routing back-gestures through the SKIP path (§5.11.4).
- Emit `tutorial_opened` / `tutorial_completed` / `tutorial_skipped` with
  `onboardingSessionId` and a per-step drop-off context.
- New reusable one-shot coach-tip widget + a persisted seen-set, with the three
  tips in §5.11.6. Design-skill work — it is a new visual surface.
- `onboarding_flow.dart`: the v3 branch renders the tutorial **before** the race
  intro. The v2 branch must remain byte-identical so
  `test/onboarding_v2_test.dart:60` keeps passing.

### 8.10 `lib/services/notification_service.dart`

- Add a `'TEAM_LEAD_CHANGED'` case alongside the existing `'TEAM_LEAD_CHANGE'`
  at `:350` (§5.12). Fallthrough, not a replacement — the existing test asserts
  the old string still routes.
- No other change to the routing switch in this batch.

### 8.11 Degradation summary — what a v3 client does when the backend is older

| Missing thing | Behavior |
|---|---|
| `onboardingV3Enabled` absent from `featureFlags` | Defaults `false` → v2 flow. Entire spec dormant. |
| `GET /referrals/inviter-race` 404s | Fall back to `OnboardingDailyIntroStep`. |
| New event names rejected (old backend, pre-§6.4) | Client-side allowlist still sends them; old backend 400s the batch. **Mitigated by deploy order** (§9) — backend ships first. Events are best-effort and queued, never user-visible. |
| Starter reward still `DAILY_10K`-pinned | `eligible: false` as today. No crash. |

### 8.12 iOS + Android lockstep

Both platforms ship together. Platform-specific work exists on both sides
(Health Connect settings intent + attempt ladder on Android; the read-probe and
its 6h arming delay on iOS), so **neither can be considered done until both are
built and verified**.

---

## 9. Backward-compat & rollout

### Deploy order (strict)

1. **Backend first.** `onboardingV3Enabled` in `KNOWN_FLAGS` + envelope, the
   analytics allowlist widening + soft-drop, `GET /referrals/inviter-race`,
   enrollment guarantee, starter-reward unpin, admin funnel query.
   All of it is additive or strictly-widening; **no shipped client changes
   behavior** when this lands, because `onboardingV3Enabled` defaults `false`
   and nothing else is client-visible.
2. **Phase 1 flag flip (independent, can happen immediately).** Set
   `onboardingV2Enabled = true` in prod. This takes effect for builds *already
   in the wild* — they contain the v2 code path. Watch for a day.
3. **App Store + Play submission** carrying the v3 client. Phased rollout ~1 week.
4. **After the build has meaningfully rolled out**, set
   `onboardingV3Enabled = true`. Older builds continue on v2 forever, which is a
   fully supported flow.

### What a frozen old client does against the new backend

- Ignores `onboardingV3Enabled` — reads only the keys it knows.
- Never calls `/referrals/inviter-race`.
- Sends its 3 existing event names; still accepted.
- **Benefits silently** from the enrollment guarantee and the widened
  starter-reward eligibility. Both are server-side and shape-compatible.

### What a new client does against a stale backend

Covered in §8.9. The critical one is the `/referrals/inviter-race` 404 →
Daily-intro fallback. If deploy order is honored this never occurs, but the
fallback must exist regardless.

### Rollback

- `onboardingV3Enabled = false` via the new admin switch reverts every
  client-side change instantly (30s cache TTL). No submission needed.
- The server-side pieces (enrollment guarantee, starter unpin, analytics) have
  no flag and are not intended to be rolled back independently. They are strictly
  widening; revert by deploy if genuinely needed.
- Tag before deploy, per repo convention.

### Users mid-onboarding when a flag flips

A user sitting on the notifications gate when `onboardingV3Enabled` goes true
will, on next rebuild, find that gate gone and be advanced. This is benign — but
the v3 `isOnboarding` must not require `notificationsState`, or they would be
stuck on a gate the flow no longer renders. The getter in §5.5 handles this;
it is called out here because it is the exact class of bug that the existing
4-copy divergence (§4.4) already caused once.

---

## 10. Test plan (written FIRST, before any logic)

Both agents write tests before business logic, and **never modify or delete an
existing test**. If an existing test looks wrong, surface it to the owner.

### Backend — `test/integration/onboarding-revamp.test.js`

Real HTTP, real DB, real handler chain. Never against prod.

1. `GET /me` returns `featureFlags.onboardingV3Enabled: false` by default.
2. `PATCH /admin/settings {onboardingV3Enabled:true}` → `GET /me` reflects it
   (respecting cache bust).
3. `PATCH /admin/settings` with an unknown key → 400.
4. Signup with **zero** ACTIVE seeded races → user created, no crash, warn
   logged, `GET /races` returns an empty list (not a 500).
5. Signup when all seeded races are **at capacity** → user is enrolled anyway in
   the most recent ACTIVE seeded race.
6. Signup with a PENDING-only seeded race → enrolled, **no** welcome boxes.
7. Starter reward is claimable when the user's only ACTIVE seeded race is **not**
   `DAILY_10K`.
8. Starter reward still cannot be double-claimed alongside the tutorial reward
   (shared ledger key).
9. `POST /analytics/activation-events` with a batch containing one unknown name
   → **202**, valid events inserted, unknown dropped, counts accurate.
10. Same endpoint still 400s on a disallowed **context** value.
11. Same endpoint remains idempotent on duplicate `id` replay.
12. `GET /referrals/inviter-race` — referred user with an inviter in an ACTIVE
    race returns the race; unreferred user returns `{race:null}`; inviter with no
    race returns `{race:null}`; unauthenticated returns 401.
13. `GET /referrals/inviter-race` excludes tournament matchup races and
    at-capacity races.
14. `GET /admin/stats` includes `onboardingFunnel` with distinct-session counts.
15. A `TEAM_LEAD_CHANGED` event-bus emit produces a push whose `payload.type` is
    `"TEAM_LEAD_CHANGE"` (§5.12). The four event-bus assertions in
    `test/jobs/placementRecompute.teamRaces.test.js` must pass **unmodified** —
    only the single `payload.type` assertion at
    `notificationHandlers.teamRaces.test.js:87` may change.

### Frontend — `test/onboarding_revamp_test.dart` (pump real widgets)

1. v3 off → `OnboardingFlow` renders the v2 sequence exactly (regression guard).
2. v3 on → the notifications gate is **never** rendered.
3. Android, first denial → error + "TRY AGAIN", no escape button.
4. Android, second denial → "OPEN HEALTH CONNECT SETTINGS" **and** "Continue
   without steps" both present.
5. Tapping escape → tabs render, degraded banner present,
   `firstRaceOnboardingSeen` set locally.
6. Killing and relaunching after an escape → user is **not** returned to the
   gate (this is the regression that makes the escape real).
7. iOS probe returns 0 → user proceeds, banner **not** shown before 6h.
8. iOS probe returns 0 and 6h elapsed → banner shown.
9. Probe later returns non-zero → banner clears, `health_recovered` emitted.
10. First box open → notification ask rendered exactly once; copy contains no
    box/powerup promise (assert on the literal string).
11. Never opening a box → ask fires on the third session.
12. Ask capped at two per install.
13. Referred user with an inviter race → `OnboardingInviterRaceStep` renders.
14. Inviter-race endpoint 404s → `OnboardingDailyIntroStep` renders instead.
15. `_isOnboarding` parity: a table-driven test over all flag/state combinations
    asserting the single getter matches the intended v1/v2/v3 semantics.
16. Every emitted activation event carries a non-null `onboardingSessionId`, and
    all events in one onboarding share the same value.
17. Sign-out clears every new SharedPreferences key.
18. Admin screen renders all five flag switches.
19. `routeFromType('TEAM_LEAD_CHANGED')` routes to race detail (the new
    spelling). The existing `TEAM_LEAD_CHANGE` assertion in
    `test/team_race_push_routing_test.dart` must still pass **unmodified** —
    both spellings route.

### Frontend — tutorial (`test/tutorial_revamp_test.dart`, plus the two
authorized rewrites)

20. The tutorial renders exactly **5** steps; the badge reads `STEP 1 / 5`.
21. Four `NEXT` taps reach the last step; the CTA then reads `DONE`.
22. Each of the five titles renders verbatim per §5.11.1.
23. `SKIP` is present on **every** step, and skipping claims **no** reward.
24. Completing all five claims the reward exactly once; a replay returns
    `granted:false` and shows no modal.
25. An OS back-gesture routes through the SKIP path — no reward, and
    `tutorial_skipped` is emitted (regression test for §5.11.4).
26. Under **v3**, the tutorial renders between the health gate and the race
    intro. Under **v2**, it does not render at all —
    `test/onboarding_v2_test.dart` must pass **unmodified**.
27. `_isOnboarding` stays true until `tutorialOnboardingSeen` is set (v3 only).
28. `tutorial_opened`/`completed`/`skipped` all carry the same
    `onboardingSessionId`.
29. Each of the three JIT tips fires once and never again after dismissal.
30. **No JIT tip fires on box open** — that trigger belongs to the notification
    ask alone (§5.11.6).

**Authorized rewrites — no other existing test may change:**
`test/tutorial_screen_test.dart` (nine NEXT taps + per-step strings → four taps
+ the new five) and `test/dark_theme_coverage_test.dart:66-79`
(`'Track today'` → `'Just walk.'`; leave `:34-40` alone).

### Structural guard

A source-level test asserting `isOnboarding` appears in `main_shell.dart` exactly
once (as the getter), preventing the 4-copy divergence from recurring.

---

## 11. Acceptance criteria

- [ ] `onboardingV2Enabled` is `true` in prod and the blocking tutorial gate is
      gone for shipped clients.
- [ ] `onboardingV3Enabled` exists, defaults `false`, is served in
      `featureFlags`, and is toggleable from the admin screen.
- [ ] With v3 off, a v3-capable binary is behaviorally identical to today's v2.
- [ ] An Android user who denies health twice can reach the app, with a
      persistent reconnect banner, and stays there across relaunches.
- [ ] An iOS user who denies health reaches the app and sees the reconnect banner
      within 6h; the banner self-clears if steps appear.
- [ ] Settings has a working "Connect Health" row whenever health is
      unconnected.
- [ ] The notification ask fires on first box open, its copy promises only
      race-related notifications, and a user who never opens a box is still asked
      by session three.
- [ ] `isOnboarding` exists exactly once in `main_shell.dart`.
- [ ] A signup never lands in zero races when at least one ACTIVE seeded race
      exists, even at capacity; zero-enrollment is logged distinctively.
- [ ] Starter reward is claimable from any ACTIVE seeded race.
- [ ] A referred user sees their inviter's race, and falls back cleanly to the
      Daily intro when the endpoint is unavailable.
- [ ] The rename chip appears once and leads to the existing editor.
- [ ] Every activation event carries `onboardingSessionId`; `home_reached` is
      emitted; `GET /admin/stats` reports a per-platform session funnel.
- [ ] `POST /analytics/activation-events` no longer 400s a whole batch over one
      unknown name.
- [ ] The tutorial is 5 steps, sits between the health gate and the race intro
      under v3, is invisible under v2, and takes under ~20 seconds end to end.
- [ ] SKIP works on every tutorial step and a back-gesture behaves identically.
- [ ] Exactly two existing test files were modified
      (`tutorial_screen_test.dart`, `dark_theme_coverage_test.dart:66-79`);
      `onboarding_v2_test.dart`, `races_tab_test.dart`, and every
      `tutorialOnboardingSeen: true` fixture file are untouched.
- [ ] The three JIT tips fire once each; none fires on box open.
- [ ] Team-lead-change pushes deep-link to race detail on **both** a shipped
      build and a new build; backend emits `TEAM_LEAD_CHANGE`, client accepts
      both spellings; exactly one existing backend assertion was changed
      (`notificationHandlers.teamRaces.test.js:87`) and
      `test/team_race_push_routing_test.dart` is unmodified.
- [ ] iOS **and** Android both built and verified before the batch is called
      done.
- [ ] All new tests written before their logic; no existing test modified or
      deleted.

---

## 12. Revision log

### Gap pass 1 (fresh re-read)

1. **Missing flag separation.** The draft used `onboardingV2Enabled` for
   everything, which would have made the Phase 1 flip and the new-binary
   behavior inseparable — and left no rollback for the new flow short of an App
   Store submission. Added `onboardingV3Enabled` (§5.1) with an explicit
   v3-implies-v2 precedence rule.
2. **Notification backstop missing.** Moving the ask to first-box-open would have
   left any box-less user never asked — a regression against today, where
   everyone is asked. Added the third-session backstop and the two-ask cap
   (§5.4).
3. **Analytics batch poisoning.** The draft added client events without noticing
   that `analytics/routes.js:70-77` 400s the *entire* batch on one unknown name.
   A new client against an old backend would have silently lost all activation
   data, not just the new events. Added the soft-drop behavior change (§6.4) and
   made it a compat requirement rather than a nicety.
4. **Starter-reward coin implication unstated.** Unpinning eligibility mints more
   100-coin grants. Verified the shared ledger key prevents double-claim, and
   documented the expected delta as a watch item (§5.6).
5. **No statement of what happens to users mid-onboarding at flip time.** Added
   §9's final subsection.

### Gap pass 2 (second independent re-read)

6. **The escape hatch wasn't an escape.** Escaping the health gate leaves
   `firstRaceOnboardingSeen` false, so `_isOnboarding` would return the user to
   the gate on next launch — an infinite loop that would have shipped. Fixed by
   requiring `markFirstRaceOnboardingSeenLocally()` at escape time (§5.2), and
   added test 6 specifically to catch it.
7. **`_restoreAndFetch` would starve the degraded user.** It hard-returns when
   health isn't authorized (`main_shell.dart:622`), so an escaped user would have
   reached a fully empty app — tabs present, no data in any of them. Added the
   explicit carve-out (§8.4).
8. **Sign-out leak.** New device-scoped keys would have survived an account
   switch, exactly the bug the existing health-auth clear at
   `auth_service.dart:696` was written to prevent. Added to §7 and test 17.
9. **iOS banner false-positive.** The probe fires immediately, so a 6am signup
   with an empty step history would have been told their health was broken within
   seconds of onboarding. Added the 6h arming delay and the self-healing re-probe
   (§5.3).
10. **Referral landing had no contract.** Phase 4 was described as UI only, with
    no endpoint — the frontend agent would have had to invent one, which the repo
    rules forbid. Pinned `GET /referrals/inviter-race` (§6.3) including the
    selection rule, the `{race:null}`-not-an-error convention, and the mandatory
    404 fallback.
11. **Degraded state vs. ad banner / tab bar.** Both are gated on
    `!isOnboarding` (`main_shell.dart:2282, 2301`). Since the degraded user is no
    longer onboarding, they render normally — stated explicitly so it isn't
    "fixed" into a suppression (§5.2).
12. **Unindexed funnel grouping.** `onboardingSessionId` has no index. Rather
    than speculatively migrating, added the measure-then-index instruction (§7).
13. **Structural guard added.** Given §4.4 shows this exact duplication already
    caused a real bug, added a source-level test asserting `isOnboarding` appears
    once.

### Gap pass 3 (post-review, owner feedback 2026-07-26)

14. **Ambiguous "double-claim" wording.** §5.6 said a user "cannot collect twice"
    without saying twice *what*, which read as "cannot claim the starter reward
    twice." The actual protection is broader and more interesting: the starter
    reward and the legacy tutorial reward share one ledger key by design, so a
    user who does both gets 100 coins, not 200. Rewritten with the citations, and
    the risk restated as bounded (one grant, once, to users who currently get
    zero).
15. **Team-lead push typo folded in** (§5.12), moved out of non-goals. Grep
    confirmed the blast radius: 3 backend source sites + 5 backend tests all use
    `TEAM_LEAD_CHANGED`; the frontend uses `TEAM_LEAD_CHANGE` in the switch and
    one test. The client-side fallthrough fixes new builds while breaking zero
    tests. The backend-side flip — which would repair every shipped client
    instantly — is surfaced as an owner decision rather than taken, because it
    requires editing `notificationHandlers.teamRaces.test.js:87`.

### Gap pass 4 (owner feedback, 2026-07-26)

16. **Backend half of the push fix approved.** §5.12 now flips the backend
    `payload.type` to `TEAM_LEAD_CHANGE` — the spelling every shipped binary
    already matches — so deep-linking is repaired for existing users on deploy
    rather than on update. The one-assertion test edit is explicitly authorized
    and tightly bounded; the four event-bus assertions are ring-fenced.
17. **§5.12 relabelled an unrelated rider.** Owner correctly challenged why a
    push-routing typo is in an onboarding spec. It isn't — it surfaced from the
    push-catalog sweep done for §5.4's copy. Marked as cut-first if the batch
    needs trimming.

### Gap pass 5 (tutorial revamp folded in, 2026-07-26)

18. **The premise was inverted.** The ask was "the tutorial is too detailed."
    The audit showed Phase 1 *deletes it from onboarding outright* — v2
    early-returns before the tutorial check, and a test asserts it never renders.
    §5.11 is therefore framed as deliberately reinstating a smaller tutorial, not
    trimming an existing one. Without this the batch would have shipped a
    "simplified tutorial" that no new user ever saw.
19. **§5.5 contradicted §5.11.** Putting the tutorial back in the critical path
    means `tutorialOnboardingSeen` must re-enter the v3 `isOnboarding`
    expression. The original getter omitted it, which would have let users skip
    the tutorial by simply reaching Home. §5.11.3 supersedes and the getter in
    §5.5 is updated in place.
20. **Two triggers collided on first box open.** The notification ask (§5.4) and
    a would-be powerup JIT tip both wanted that moment. Resolved by teaching
    boxes/powerups in tutorial steps 3–4 and reserving the box-open trigger for
    the notification ask alone.
21. **Abandonment hole promoted to a defect.** `TutorialScreen` has no
    `PopScope`, so a back-swipe exits with no reward and no analytics while
    onboarding marks it seen. Harmless when optional; a real hole now that it
    gates the app. §5.11.4.
22. **Test blast radius enumerated before authorizing.** Rather than a blanket
    "fix the tests," §5.11.7 names the two files, the exact assertions, and an
    explicit deny-list of the eight files that must stay untouched — including
    `onboarding_v2_test.dart`, which stays valid precisely because v2's branch is
    unchanged.
23. **Non-goals corrected.** They previously read "Redesigning the tutorial
    itself… its content is untouched," which the new scope directly contradicts.
    Replaced with the two real non-goals: the full JIT tip set and tap-through
    interactivity.

### Gap pass 6 (build-time corrections, 2026-07-26)

24. **§6.4's request example named the wrong field.** It showed `occurredAt`;
    the real request field is `timestamp` (`occurred_at` is only the DB column),
    and `validateActivationEvent` 400s on unknown top-level keys — so the example
    as written would have rejected every batch the new client sent. Corrected in
    place, and the frontend agent was warned mid-build. The prose ("shapes are
    unchanged") was right; only the example was wrong.
25. **§6.3's selection rule contradicted itself** — "exclude races the caller has
    already joined (set `alreadyJoined: true` and still return it)". The
    parenthetical is the intent; joined races are returned, flagged, not
    excluded. At-capacity disqualifies only when the caller is not already in.
26. **§6.5 pinned a 7-day window** while the design text asked for 7/30d.
    Resolved by keeping the frozen shape verbatim and adding
    `byPlatformLast30Days` as an additional key rather than mutating a pinned
    contract mid-build.
27. **Two further backend tests authorized** (owner, 2026-07-26), both mechanical
    consequences of approved scope, both surfaced by the agent rather than
    silently fixed: `test/http/onboarding-starter-reward.test.js` asserts the
    exact `DAILY_10K` constraint §5.6 removes, and `test/http/auth-flow.test.js:72`
    deepEquals the `featureFlags` object that §6.1 adds a key to.
28. **`getReferralPreview` enum-ordering bug folded in** (owner approved).
    `RaceStatus` declares `PENDING` first (`schema.prisma:733-738`) and Postgres
    sorts enums by declaration order, not label text — so
    `orderBy: {status:"asc"}` in `src/modules/social/queries/getReferralPreview.js`
    prefers PENDING over ACTIVE, the opposite of its own comment. Invitees
    opening a referral link have been shown not-yet-started races instead of live
    ones. Same surface as §5.8; fixed by sorting explicitly in JS.

### Gap pass 7 (implementation findings, 2026-07-26)

29. **§5.2 and §5.11.3 contradicted each other — spec error, caught at
    implementation.** Gap pass 5 put `tutorialOnboardingSeen` back into the v3
    gate and updated the §5.5 getter, but never propagated the change to §5.2's
    escape-hatch rule, which still said to set only `firstRaceOnboardingSeen`.
    An escapee would have cleared the health term and looped straight into the
    tutorial gate — making test 5 ("escape → tabs render") unsatisfiable.
    **The escape hatch must close BOTH terms.** This is now the spec's position.
30. **§5.11.8's per-step drop-off was not implementable as written.**
    `context.source` allows only `{onboarding, profile, races, empty_state,
    share_link}`, and §6.4 deliberately keeps 400-ing disallowed *context*
    values — only unknown *names* soft-drop. Emitting a step index would have
    poisoned entire batches. Resolved (owner approved) by adding a `step`
    context key accepting integers 1–10, emitted on `tutorial_skipped` as the
    1-indexed step the user bailed on. `tutorial_completed` carries no step.
31. **The admin funnel view was specced nowhere.** §5.9 promised "an admin funnel
    view" and §6.5 pinned the `onboardingFunnel` payload, but §8's frontend plan
    never listed a screen to render it — so Phase 5 data would have accumulated
    invisibly. Owner approved building the card; it must render nothing at all
    when the section is absent (older backend), per §8.11.
32. **`PackageInfo.fromPlatform()` never resolves inside `testWidgets`'
    fake-async zone**, so `ActivationAnalyticsService.record()` hangs mid-write
    in widget tests. Pre-existing (the existing analytics test uses plain
    `test()`). Any widget test asserting on activation events must call
    `PackageInfo.setMockInitialValues` in `setUp`.
33. **Three test files do not compile on `main`** from other agents' uncommitted
    work — `race_detail_signal_jammer_targets_test`,
    `race_detail_team_targeting_test` (fake `usePowerup` overrides missing
    `targetEffectId`), and `home_leaderboard_highlights_test` (eight named params
    `HomeTab` no longer accepts). Their compile errors kill the shared resident
    compiler and surface as a spurious "Dart compiler exited unexpectedly"
    against whatever suite runs next. Not caused by this batch; verified
    independently.

### Gap pass 8 (cross-agent integration, 2026-07-26)

34. **`context.step` wire type was ambiguous and the two agents diverged.** The
    contract said "accepting integers 1 through 10" without pinning the JSON
    type. The backend validated `Number.isInteger`; the client sends `"3"`,
    because its context map is `Map<String, String>` and `ALLOWED_CONTEXT` is
    key → Set-of-**strings**. Every batch containing a tutorial skip would have
    400'd — and since activation events are best-effort and swallowed, the skip
    metric would have silently read as **zero skips forever**, indistinguishable
    from a perfect tutorial. Resolved in favour of the **decimal-string form**
    (`"1"`…`"10"`), consistent with every other context value. Exactly one wire
    type is accepted, not both, so stored data stays queryable.
    **Lesson for future contracts: pin the JSON type, not just the value range.**
35. **Funnel retention deliberately does not chain through side exits.**
    `health_escaped` and `health_probe_inconclusive` are exits, not stages users
    flow through; chaining them would produce authoritative-looking nonsense
    ("5% of users who escaped went on to see the race intro"). Step-over-step
    retention runs along the spine only (`started → cta → granted → race intro →
    home`); the two exits render as indented branch rows showing their share of
    top-of-funnel. All seven stages still appear in the pinned order.
36. **`position_aware_drops_odds_sheet_test` is flaky** — passed and failed on
    consecutive isolated runs, including with this batch's new files absent.
    Another agent's uncommitted work; not touched, but do not treat it as a
    signal when validating this batch.

### Open questions

None.
