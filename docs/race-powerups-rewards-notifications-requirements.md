# Tournament Ad, Race Powerups, Reward Reveal, and Reminder Notifications

Status: Approved to implement (2026-07-19); contract frozen, agents dispatched
Date: 2026-07-18 (rev 2026-07-19)
Repositories: `stepv2-frontend` and `stepv2-backend`
Supersedes: `race-powerups-rewards-notifications-spec-2026-07-18.md`

## 1. Summary & User Story

Six improvements to race powerups, mystery-box reveal, tournament monetization,
daily-reward retention, and race-ending reminders.

- *As a tournament viewer*, I want the sponsored ad to sit still above the
  bracket instead of being dragged through a pan/zoom transform, so it renders
  correctly and stops emitting AdMob policy warnings.
- *As a team racer*, I want both roster columns to stay aligned regardless of
  how many powerup effects are active on each racer.
- *As a Leech user*, I want the powerup to feel like a heist rather than pure
  vandalism: the steps I drain land in my own score.
- *As someone opening a mystery box*, I don't want the result spoiled in my
  inventory behind the still-spinning reel.
- *As a lapsed daily player*, I want a playful nudge in the evening if I haven't
  opened my free box yet.
- *As a racer in a timed race*, I want a heads-up about two hours before it ends
  so I can get a final push in.

The first compatibility rule governs everything below: the shared backend must
keep serving every previously shipped app binary. Response changes are additive,
new request parameters optional, existing endpoint behavior preserved.

## 2. Scope / Non-Goals

In scope: tournament sponsored banner, team-racer effect rail, Leech 2:1
uncapped transfer, mystery-box reveal synchronization, daily-reward reminders,
race-ending-soon reminder.

Explicitly **out of scope**:

- **Next-box progress on the race menu.** Cut during review — see §11, Pass 3.
- Any change to race-detail or other existing ad placements.
- Rewarded-ad extra-spin reminders.
- Changes to Leech **duration** (stays 30 min), target restrictions, shield/Mirror
  behavior, or stacking limits. (Leech **conversion ratio, cap, and price** *are* in
  scope — see §5.)
- Redesigning the solo-race leaderboard plank or the team **standings** planks
  (`LeaderboardPlank`). §4 covers only the two-column roster cells.
- Changing mystery-box odds or animation duration.
- Fixing the pre-existing `TEAM_LEAD_CHANGED`/`TEAM_LEAD_CHANGE` and unmapped
  `DAILY_MOVER` routing bugs (noted in §7 as precedent, not fixed here).
- Production deployment.

## 3. Tournament Sponsored Banner

### Problem

`lib/widgets/tournament_sponsor_card.dart:52-64` builds a `NativeAd` with the
SDK's small `NativeTemplateStyle`, boxed at `SizedBox(height: 90)` (`:107`). It
is positioned inside the bracket canvas at
`lib/widgets/tournament_bracket_board.dart:286-293`, whose `Stack` is the child
of the `InteractiveViewer` at `:179-195`. The platform view therefore lives under
an active pan/zoom `Matrix4`; the file's own comment at `:24-26` concedes this is
"best-effort." This produces `MediaView is too small for video` and
`Advertiser assets outside native ad view` warnings.

### Required Experience

- Retire `TournamentSponsorCard` and its `_HouseAd` fallback (`:145-197`) from
  the champion node.
- Add one `AdBannerSlot` between `_infoStrip` and the bracket board in
  `_bracketLayout` (`lib/screens/tournament_detail_screen.dart:560-577`), fixed
  in the layout so it neither pans nor zooms.
- **Use the existing `AdBannerSlot`** (`lib/widgets/ad_banner_slot.dart:24`). It
  already provides anchored-adaptive sizing (`:64-76`), the remote kill switch
  (`:65`), and collapse-to-zero on no-fill/failure (`:87-98`, `:131`). Do not
  write a new banner widget.
- The label is **`SPONSOR`**, not `SPONSORED` — matching the string already used
  at `ad_banner_slot.dart:149` and `:176`. `AdBannerStyle.trackside` already
  renders it; reuse the style rather than adding a bespoke label.
- Ad unit comes from `AdService.bannerAdUnitId` (`ADMOB_BANNER_AD_UNIT_ID`), not
  `nativeAdUnitId`. Note `AdService.bannersEnabled` (`ad_service.dart:111-114`)
  already gates on the *banner* unit id, so the existing kill switch carries over
  unchanged.
- Do not overlay, crop, clip, or restyle the AdMob creative.
- No house-ad placeholder. Removing `_HouseAd` intentionally forgoes
  inventory-free fill; the band collapses to zero height instead.

### Ad Instance Note

There is **no global ad limiter or registry** in the app. `TournamentDetailScreen`
is always a pushed route (`main_shell.dart:1531`, `races_tab.dart:210`,
`public_races_screen.dart:215`, `create_race_screen.dart:364`,
`race_detail_screen.dart:3453`), never a nav tab, so the shell's `AdBannerSlot`
(`main_shell.dart:2146-2160`) stays mounted underneath it. Net effect: one
*visible* ad, two live `BannerAd` objects. This matches how race detail and daily
reward already behave, so it is acceptable — but confirm memory behavior on a
low-end Android device before shipping.

### Test Plan

- `test/ad_placements_test.dart` **must pass unmodified.** Its contract
  (`:28-37`) is "exactly ONE `AdBannerSlot` at shell level; nav tabs host none."
  Tournament detail is a pushed route, so adding a slot is consistent — verify,
  do not edit the test.
- Before deleting `TournamentSponsorCard`, grep the test tree for any test that
  asserts its presence (or a `NativeAd` on the tournament screen). Such a test now
  encodes retired behavior — **surface it to the requester** rather than silently
  editing, exactly as the Leech-test flag in §5 requires.
- New widget test: tournament screen contains no `NativeAd`/`NativeTemplateStyle`.
- New widget test: with ads disabled, the sponsored band contributes zero height.

### Acceptance Criteria

- No native-ad size or asset-boundary warnings originate from the tournament screen.
- The bracket reclaims the champion-area space and still pans/zooms normally.
- The banner is fully visible on supported iOS and Android widths, including safe
  areas and rotation.
- Missing configuration or no fill leaves no blank gap.

## 4. Team-Racer Active-Effect Layout

### Problem

`_teamColumnCell` (`lib/screens/race_detail_screen.dart:5279-5401`) is a
free-flowing `Column` with no fixed height. Effect badges are appended as a
trailing `Wrap` at `:5367-5382`, so only affected racers grow taller. Because
`_buildTeamTwoColumns` (`:5237-5246`) uses
`crossAxisAlignment: CrossAxisAlignment.start`, the two columns go ragged.

### Required Experience

- Give every roster cell the same minimum height regardless of effect count.
- Reserve a **narrow** effect rail on the right of every card, present even when
  empty, so reserving it never shifts only affected cards.
- Keep rank/avatar, name, and steps centered in the remaining content area.
- Stack all active-effect icons vertically in the rail — every type, not just
  Leech. Preserve existing artwork and the Leech attacker-name tooltip suffix
  (`_effectIconsFor`, `:5623-5638`).
- Overflow: show the maximum that fits, then a final `+N` indicator. The card must
  not grow vertically.
- Continue hiding effects for stealthed participants (`:5367`) and dimming
  forfeited ones (`:5297-5298`).

### Hit Targets — Resolved

The rail stays **narrow**; the 44×44 guideline is **relaxed** for effect icons.
Rationale: at 18px icons in a half-width column, a 44pt rail consumes ~25% of the
cell and starves the name/steps. Target ~28–32pt touch area. This is a deliberate,
documented deviation from the accessibility guideline, not an oversight.

### Tooltip Repositioning — Required

`_EffectIconWithTooltip` (`:5970-6079`) is not a Flutter `Tooltip`; it is a manual
`OverlayEntry` positioned with **hardcoded** `offset.dx - 60, offset.dy - 68`
(`:6006-6008`). Moving icons to the right edge of a right-hand column will push
bubbles off-screen. The implementation must clamp the bubble to the screen bounds
(respecting `maxWidth: 200`) rather than keeping fixed offsets.

The `+N` indicator needs a **multi-line** tooltip listing the remaining effects —
the current bubble renders a single effect string and must be generalized.

### Known Inconsistency (document, do not fix)

`_teamColumnCell` renders the **real name and step count** for a stealthed racer,
hiding only cosmetics and effect badges — whereas `LeaderboardPlank` renders
`'???'` (`leaderboard_plank.dart:63, 195`). Pre-existing; out of scope. Do not
"fix" it opportunistically as part of this work.

### Test Plan

- Widget test: two cells in the same roster row report equal height with 0, 1, and
  5 effects on one side.
- Widget test: `+N` appears past the fit limit and the card height is unchanged.
- Widget test: an effect icon near the screen edge places its tooltip fully
  on-screen.
- Golden/semantics: every supported effect is identifiable via its semantics label.

### Acceptance Criteria

- Opposing cells stay aligned with zero, one, or several effects.
- Solo-race leaderboard and team standings planks are visually unchanged.

## 5. Leech 2:1 Uncapped Step Transfer

### Final Rules

| Rule | Value |
| --- | --- |
| Duration | 30 minutes |
| Conversion | 2 eligible attacker steps transfer 1 step |
| Transfer | Target `-1`; attacker `+1` bonus step |
| Per-use cap | **None** — bounded only by the target's available balance |
| Price | **150 coins** (was 300) |
| Pair stacking | One active Leech per attacker-target pair |
| Victim stacking | At most two distinct active leechers |
| Team targeting | Enemies only |
| Target floor | Zero steps |
| Compression Socks | Blocks application, consumed under existing rules |
| Mirror | Does not reflect Leech |

**The per-use cap is removed entirely.** Previously the mechanic was
double-limited: a `min(1000, ...)` transfer cap *and* the target floor. Now the
**target floor is the only limiter** — a leecher who walks enough over the 30-min
window can drain the target's entire eligible contribution and mint all of it to
their own score. This is a deliberate power increase paired with the price drop to
150. Flag for playtest: two uncapped leechers on one victim can zero out that
victim's window steps quickly; the deterministic ordering below keeps it zero-sum,
but the balance team should watch score-delta telemetry after launch.

**Remove `LEECH_STEP_CAP = 3000` outright.** It is currently duplicated as two
independent literals (`src/commands/usePowerup.js:79` and
`src/queries/getRaceProgress.js:68`) and referenced at
`getRaceProgress.js:362,379` and `usePowerup.js:75,480,892,906`. Delete all of
them; the scorer's only clamp becomes `targetAvailable`. Update the gang-stall
guard comment at `usePowerup.js:480` — the worst case is no longer
`-2 * LEECH_STEP_CAP` but "the victim's window steps drained to zero, split
deterministically between at most two leechers." The `LEECH_MAX_PER_VICTIM = 2`
limit is unchanged.

### Step-Window Measurement — Resolved

Step data is stored in **hourly** buckets (`prisma/schema.prisma:250-269`;
client floors to clock hours at `health_service.dart:197-231`), so a 30-minute
window cannot be measured exactly. `sumStepsInWindow` linearly prorates partial
buckets (`src/models/stepSample.js:164-190`).

**Decision: accept proration, but freeze the divisor.** The in-progress hour is
**excluded** from `attackerWindowSteps` until that bucket is closed. Rationale:
the live hour's `periodEnd` is `endTime` rather than the hour boundary, so its
duration — and therefore its prorated contribution — changes on every re-upsert
(`stepSample.js:46-61`). Under the old 1:1 debuff nobody audited this; under a
transfer the attacker *sees* the number, and a shifting divisor would make their
score move backwards.

Consequence to accept and document in the changelog: transferred steps land with
up to an hour of lag, and the total remains an estimate (a leecher who walks in
a burst still drains a uniform-rate share of the hour). It is now at least
**monotonic** — the property that matters when steps are minted to a visible
recipient.

### Scoring Definition

For each active or historical Leech effect, during both live progress and
settlement:

```text
attackerWindowSteps = eligible source steps in [startsAt, expiresAt],
                      EXCLUDING the in-progress hour bucket
earnedTransfer = floor(attackerWindowSteps / 2)          // no upper cap
actualTransfer = min(earnedTransfer, targetAvailable)

targetScore    -= actualTransfer
attackerScore  += actualTransfer
```

`actualTransfer`, not `earnedTransfer`, is credited to the attacker — this is what
keeps the mechanic zero-sum when the target is near zero or is hit by two leechers.
With the cap gone, `targetAvailable` is the sole ceiling.

Use cumulative window steps with `floor(total / 2)`, never per-sync rounding, so
remainders carry across uploads (1 + 1 steps eventually transfers 1).

### Attribution — New Structure Required

Today Leech has **no per-effect attribution**: it is folded into a scalar
`frozenSteps` (`getRaceProgress.js:369-381`) indistinguishable from Leg Cramp or
Rainstorm, and the zero-floor is applied once at the end on the whole participant
total (`:643`, mirrored at `raceStateResolution.js:190-198`). A zero-sum transfer
cannot be expressed in that shape.

`computeEffectModifiers` must return per-leech `actualTransfer` values alongside
the existing aggregates. Because it is shared by live progress
(`getRaceProgress.js:641`), settlement (`raceStateResolution.js:176-188`), and
sync-v2 reconcile (`reconcileUploaderRaces.js:93-105`), all three move together —
which is the desired outcome.

**`targetAvailable` is defined as** the target's total after all *other* modifiers
(freeze/buff/reverse/boost/bonus) are applied, floored at zero, minus any transfer
already taken by an earlier-ordered leech. Leech therefore resolves **last**,
against what actually remains. When two leeches compete for a limited balance,
order deterministically by `startsAt`, then effect ID, so live display and
settlement always agree.

### Must Also Fix — Home Card Divergence

`src/queries/getHomeRaceCard.js:274` prefetches only `POWERUP_EFFECT_TYPES` and
**omits LEECH**, so the home card total already disagrees with race detail.
`computeEffectModifiersFallback` (`getRaceProgress.js:71-113`) likewise has no
leech branch. Both must include LEECH before this ships — once leech *mints*
steps, an unfixed divergence means the home card shows a smaller number than the
race the user just left.

### Frozen Totals — Accepted Limitation

Recomputation is from scratch each read, so unresolved effects adopt the new rule
automatically. But these keep old-rule numbers permanently:

- Finished/forfeited participants return a frozen `totalSteps`
  (`getRaceProgress.js:606-618`, `reconcileUploaderRaces.js:60-67`).
- Replayed sync-v2 idempotency keys return a stored `responseJson`
  (`recordStepSyncV2.js:160-272`).

Accepted: no backfill. The deploy should land when few races are mid-flight.

### Other Backend Requirements

- Credit transferred steps as a derived bonus component. **Never** mutate
  HealthKit/Health Connect samples or raw step rows.
- Extend new-use metadata to `{ ratio: 2, scoringVersion }` (no `cap`/`transferCap`
  — the cap is gone). Today it is only `{ cap }` (`usePowerup.js:906`) and the
  scorer ignores it; the scorer must now read `ratio` (defaulting absent metadata
  to the new 2:1) so a future ratio change doesn't require another migration.
- Unresolved effects created under the old 1:1/3:1 rules adopt 2:1-uncapped
  immediately; absent metadata reads as the new default. This avoids running an
  inconsistent mechanic for 30 more minutes and keeps one rule across all clients.
- **Shop price: 300 → 150** in `prisma/seed.js:152`. Leech is a single-price
  store-only item (not in the `powerupUpgrades.js` ladder), so this is the only
  price reference. The catalog is served from the DB via API, so old clients pick
  up the new price on their next catalog fetch.
- Socks/Mirror behavior is list-membership driven (`usePowerup.js:44, 53`) and needs
  no leech-specific change. A socks-blocked leech creates no effect row, so the
  attacker gains nothing — confirm that stays true.
- Keep all use endpoints and request bodies unchanged so old clients can activate Leech.
- Update the DB seed copy (`prisma/seed.js:150-151`), which drives the shop via API.

### Frontend Requirements

New copy: `For 30 min, every 2 steps you take steals 1 step from a chosen rival and
adds it to your score.`

The shop reads its description from the API and needs no change. But **two
hardcoded strings are compiled into the binary** and will go stale:

- `race_detail_screen.dart:135-136` — long description (target picker + tooltip)
- `race_detail_screen.dart:158` — `'LEECH': 'Steps being leeched'`

Target selection, badges, notifications, inventory, purchase, shield behavior, and
team restrictions are unchanged. Treat any new scoring/effect fields as optional
and nullable.

### Test Plan

- 0 and 1 attacker steps transfer 0; 2 transfers 1; 10,000 walked transfers 5,000
  with **no ceiling** — assert the old 1,000/3,000 cap no longer clamps.
- Remainders carry across step-sync batches (1 + 1 eventually transfers 1).
- The in-progress hour is excluded, and the transferred total never decreases
  across successive recomputes of the same window.
- A target at 40 cannot fund more than 40 credited bonus steps, even when the
  attacker's `earnedTransfer` far exceeds it (verifies the target floor is now the
  only limiter).
- Two leechers resolve by `(startsAt, id)` without making the target negative or
  minting steps.
- Live totals equal settled totals.
- Metadata `ratio` is read: an effect row tagged `ratio: 2` and one with absent
  metadata score identically.
- **New:** home-card total equals race-detail total for a race with an active Leech.
- Existing suites are updated in place only where they assert the old 3:1/cap
  numbers (those assertions are now wrong, not "modified to pass"); the structural
  tests — socks block, Mirror non-reflect, pair/victim stacking, team-targeting,
  expiration, push — pass untouched: `test/commands/leechPowerup.test.js`,
  `test/handlers/leechPush.test.js`,
  `test/integration/powerups-batch-leech-xray.test.js`. The math suite
  `test/queries/leechScoring.test.js` is rewritten for 2:1-uncapped. Surface any
  existing test whose intent is unclear before changing it.

## 6. Mystery-Box Reveal Synchronization

### Root Cause

The parent inventory mutation fires ~4.6s before the reveal. In
`race_detail_screen.dart:3695-3711`, `_optimisticallyApplyBoxOpen` is called
immediately on API response — before `_controller.forward()` runs its 4000ms
`easeOutQuart` (`case_opening_strip.dart:73-78`) plus the 600ms settle
(`:85-90`). Because the overlay route is non-opaque, the inventory row behind the
spinning reel already shows the result.

`MultiCaseOpeningScreen` has the same defect: `onResults` fires at `:112`, before
the phase flips to `revealing` and before any reel spins.

### Required State Flow

```text
idle -> requesting -> spinning -> revealed -> committed-to-visible-inventory
```

- Keep firing the server request from the swipe gate (`case_opening_screen.dart:165-184`)
  — this preserves server authority and prevents client-selected results.
- Hold the result inside the reveal screen while the reel spins. Do **not** invoke
  the parent mutation callback yet.
- When the reel completes, atomically reveal and commit the inventory transition.
- On failure, re-arm the unopened box and restore navigation. The strip already
  stays armed for retry (`case_opening_strip.dart:139`).
- If the app is killed after the server succeeds but before reveal, the next
  progress refresh shows server truth. No rollback endpoint needed.
- `Open All`: commit all results together after the coordinated reels land. This
  must also cover `_fallbackSingleOpens` (`race_detail_screen.dart:3648`), the
  404-compat path that fires N parallel single opens.

### Auto-Activation Leak

Fanny Pack auto-activates server-side when slots are full
(`src/commands/openMysteryBox.js:120-143`, returning `autoActivated: true`), and
`_optimisticallyApplyBoxOpen` (`:1435-1461`) **deletes the inventory row
immediately** in that case — the most visible spoiler. Deferring the commit fixes it.

### Navigation Locking — Net New

There is **no `PopScope` or `WillPopScope` anywhere** in the case-opening screens;
close is a bare `Navigator.pop()` (`case_opening_screen.dart:191-193`), live even
mid-spin. This work must **add** `PopScope` to both reveal screens, covering the
Android back button and the iOS swipe-back gesture on the `PageRouteBuilder`.

Double-tap guards already exist at three layers (`case_opening_strip.dart:127,183`;
`case_opening_screen.dart:187`; `race_detail_screen.dart:3582,3691`) — verify, don't rebuild.

### Test Plan

- Widget test: inventory is unchanged while the reel spins; updated only after reveal.
- Widget test: an auto-activated Fanny Pack row survives until reveal.
- Widget test: back/close is a no-op between request-accepted and reveal.
- Widget test: `Open All` commits all results in one frame, including the fallback path.

### Acceptance Criteria

- No result icon, name, rarity, or auto-activation state appears in inventory
  before its reel lands.
- A committed spin cannot be dismissed midway.
- Slow responses show the existing preparing state; fast responses still honor the
  full animation.
- Double taps create only one open request.

## 7. Daily Reward Reminder System

### User Experience

- Send only when today's free daily mystery box is unclaimed.
- 5:00 PM local; second at 9:00 PM local if still unclaimed.
- Title: `Your daily box is waiting`
- Body: `Your mystery box has been sitting here all day. Awkward.`
- Tapping opens the daily-reward screen.
- Claiming suppresses later reminders that day. The rewarded-ad extra spin must
  never trigger or suppress these reminders — it deliberately does not touch
  `lastDailyClaimDate` (`src/commands/claimExtraDailyRewardBox.js:31-34`).

### Architecture

Backend-scheduled visible pushes, not local notifications: the backend owns claim
truth, can suppress the 9 PM slot immediately after a claim, and works when the app
is terminated.

**iOS uses direct APNs over HTTP/2** (`src/services/apns.js`), **Android uses FCM**
(`src/services/fcm.js`), selected by `pushServiceFor` (`notificationHandlers.js:54-56`).
`Notification.type` is a free-form String by design (schema comment
`prisma/schema.prisma:1306-1312`), so new types need no migration.

### Timezone Persistence — Net New

**There is no `users.timezone` column.** `X-Timezone` is request-scoped only
(`src/middleware/extractTimezone.js:19-23`); the `America/New_York` fallback the
original spec cited lives on the *request*, not the user. Persisted timezones exist
only on Race/Tournament (`schema.prisma:704, 834`).

Required:

1. Add `timezone String?` to User, plus `@@index([timezone])`. The User model has
   **no `@@index` entries at all** today — this is greenfield.
2. Populate from `req.timeZone` using the **sticky-write** pattern already used for
   `clientFeatures`/`clientFeaturesAt` (`schema.prisma:76-88`) — write only when the
   value changed or is stale. Do **not** write on every authenticated request:
   commit `3e6c827` reverted an advisory lock precisely because extra per-request DB
   work drained the connection pool under prod load.
3. Users with no recorded timezone fall back to `America/New_York`, matching
   `extractTimezone.js:21` and `scripts/backfill-user-race-timezone.js:14-17`.

### Claim-Date Semantics — Correctness Trap

`lastDailyClaimDate` is a **client-supplied device wall-clock string**
(`"YYYY-MM-DD"`, built at `backend_api_service.dart:974`) — it is *not* derived from
`X-Timezone` and is not a DATE column (`schema.prisma:30`). The reminder job would
compute "today" from `users.timezone`. These two can disagree (traveler, device tz
differing from header tz).

**Resolution: bias toward silence.** Suppress the reminder when `lastDailyClaimDate`
matches the user's timezone-derived local date **or the adjacent day**. A missed
nudge is invisible; nagging someone who already claimed is a bug report.

### Deduplication — Do Not Use Advisory Locks

Crons are in-process `setInterval` registered at `src/index.js:58-93`; the comment at
`:44-51` states plainly that in-process guards "don't reach across processes." The
existing daily-job marker is **not** an atomic claim: `JobRun.markRan` is a plain
upsert written *after* the work completes (`src/models/jobRun.js:16-22`), so two
workers both read `lastRanFor !== dayKey` and both send.

Required design:

- Add a nullable unique delivery key to `Notification`, e.g.
  `daily-reward:<userId>:<localDate>:17`, with a partial unique index. Existing
  writers keep storing null.
- The job **inserts the key row first** and only sends on successful insert
  (catching the unique violation as "already claimed by another worker"). This is
  cross-process safe without holding any lock.
- Use per-zone `JobRun` keys (`daily_5pm:America/New_York`) for tick gating, with a
  CAS `updateMany({ where: { jobName, lastRanFor: { not: dayKey } } })` claim rather
  than the current read-then-upsert.
- **Do not** reach for `pg_advisory_xact_lock`. It is used elsewhere for settlement
  (`rankedWeek.js:74`, `season.js:38`, `rollPowerup.js:84`), but the most recent
  attempt to extend that pattern caused a site-wide pool exhaustion (`3e6c827`).

Existing 7-day notification retention (`src/jobs/notificationCleanup.js:8`) already
comfortably covers a local day.

### Scheduler Rules

- Ride the existing 5-minute tick, like `dailyMover` and `notificationCleanup`.
- Per tick, compute which IANA zones are currently in their 17:00 or 21:00 hour
  (via `getTimeZoneParts`, `src/utils/week.js`), then query
  `findMany({ where: { timezone: { in: zonesAtSlot } } })`. Real-world zone
  cardinality is a few dozen, so an indexed `IN` is the right shape — never scan all
  users computing `Intl` per row.
- **Catch-up window: 30 minutes.** A reminder fires only if the tick lands within
  30 minutes of the slot; missed slots are skipped entirely. This deliberately
  differs from `dailyRunKey` (`src/utils/etSchedule.js:34-40`), which self-heals all
  day and would fire a 5 PM reminder at 11 PM after a restart.
- Re-check before every send: preference enabled, ≥1 valid device token, claim-date
  test above, no existing audit row for that slot/local date.
- Record success and token-invalid outcomes consistently with existing infrastructure
  (410 → token deleted, `apns.js:168-204`).
- Kill switch `DAILY_REWARD_REMINDERS_DISABLED=true`, matching the established
  pattern at `index.js:70-83`.

### Preference API

```text
GET   /notifications/preferences
PATCH /notifications/preferences   { "dailyRewardRemindersEnabled": true }
```

`dailyRewardRemindersEnabled Boolean @default(true)` on User. There are **no
per-user notification preferences today** — only per-race `chatMuted` /
`placementAlertsMuted` (`schema.prisma:936, 942`). Old clients never call these
endpoints and keep default behavior. Device-token registration is unchanged.

### Settings UI

Settings is a **bottom sheet**, `_SettingsSheet`
(`lib/screens/tabs/profile_tab.dart:772-995`), not a screen. The existing
`_NotificationToggle` (`:997-1046`) is a one-way OS-permission button, not a toggle.

Copy the `_LeaderboardVisibilityToggle` pattern (`:1051-1108`): a `PixelSwitch` in a
parchment row with an optimistic write that reverts on backend failure. Add a
`DAILY REWARD REMINDERS` row, separate from race-level mute controls.

- When OS permission is granted, initialize from the backend preference; default on
  when the field/endpoint is unavailable.
- If OS permission is denied, show it off/disabled with guidance. Do not re-trigger
  the OS prompt.
- Read preference responses defensively; failure must not crash settings or silently
  change the displayed value.

### Routing

`NotificationRoute` (`lib/services/notification_service.dart:35`) has no
`dailyReward` value — add one, add the `case` in `routeFromType`, and handle it in
the shell listener (`main_shell.dart:228-259`).

**The backend `route` field is decorative** — Flutter switches purely on `type`.
Two existing types already silently no-op on tap because their case is missing or
misspelled (`TEAM_LEAD_CHANGED` vs `TEAM_LEAD_CHANGE`; `DAILY_MOVER` unmapped).
Adding the `type` case is therefore mandatory, not optional.

Old apps receiving the new type fall through to `default: return null` (`:385-386`) —
the alert still shows, only deep-linking is skipped. This is the established additive
pattern and is acceptable. The payload must carry no rewarded-ad or extra-spin CTA.

### Test Plan

- Sends once at each local slot when unclaimed and enabled.
- Does not send after claim, when opted out, without a token, twice for a slot, or
  outside the 30-minute catch-up window.
- Claim-date/timezone disagreement suppresses rather than sends.
- DST transitions and non-hour-offset zones (e.g. `Asia/Kolkata`) resolve correctly.
- Two concurrent workers cannot duplicate a reminder (unique-key insert race).
- Invalid/absent timezone falls back to `America/New_York`.
- Tap routing opens daily reward on both platforms.
- Preference API returns safe defaults when omitted by old clients.

## 8. Race-Ending-Soon Reminder

### User Experience

- Send one push to each active participant of a **timed** race roughly two hours
  before it ends.
- Title/body: a single playful "final push" nudge carrying the time remaining, e.g.
  `Race ending soon` / `<Race name> ends in about 2 hours — time for a final push.`
- Tapping opens the race detail screen.
- Exactly **one** reminder per participant per race. No repeats, no restart re-sends.

### Qualifying Races — `endsAt != null` Only

A race has a definite end instant **iff `endsAt` is non-null**. `endsAt` is a stored
UTC timestamp computed once at start (`src/commands/startRace.js:98-102`,
`startedAt + maxDurationDays*86400000`), so **DST and race timezone are irrelevant** —
the reminder just compares `endsAt` to `now`.

Open-ended step-target races carry `endsAt = null` (`race.js:415-419`, *"endsAt is
null for open-ended step-target races"*) and **must be excluded** — they have no
fixed end. Gate strictly on `endsAt != null`, exactly as the existing final-stretch
logic does (`placementRecompute.js:207-210`). This covers all `timeBased` races plus
any duration-capped target race.

There is **no near-end push for solo/individual races today** — the three existing
mechanisms (`TEAM_FINAL_STRETCH`, `TEAM_SLACKER_NUDGE`, and the final-stretch
step-sync pull) are all team-only or non-user-facing. This is the first end-of-race
reminder for the general roster.

### Host & Trigger

Host in **`placementRecompute.js`** (5-min tick). It already loads the exact
candidate set via `Race.findActiveInProgress` (`race.js:415-436`, returns
id/name/endsAt), loops each race, computes `msLeft` from `endsAt`
(`placementRecompute.js:115-116, 207-210`), enumerates accepted participants via
`RaceParticipant.findAcceptedByRace` (`:202`), and already has `eventBus` +
`Notification` injected (`:39-40`). No new query or schema change to the job.

Because the tick is every 5 minutes, do **not** test for an exact `== 2h`. Fire on
the first tick where `msLeft <= 2h` (and `msLeft > 0`), then rely on the durable
send-once dedup below so it never repeats. This self-heals across missed ticks and
restarts without a window edge case.

**Short-race guard.** User races have `maxDurationDays >= 1` (always > 2h), but
seeded races can use `durationHours` (`schema.prisma:783`) and could be scheduled for
under two hours. Such a race starts already inside the 2h window, so the first tick
would fire a "ends in ~2h" push moments after it began — nonsensical. Skip the
reminder when the race's **total** scheduled duration is `<= 2h`, i.e. only fire when
`endsAt - startedAt > 2h`. `findActiveInProgress`'s lean select does **not** include
`startedAt` (`race.js:421-434`); add `startedAt` to that select (additive, no schema
change) or compare against a threshold the query already exposes. A reminder for a
sub-2h race is out of scope by definition.

### Send-Once Dedup — Durable, Not In-Memory

Use the **audit-row** pattern, not the in-memory `Map` throttle that
`TEAM_FINAL_STRETCH` uses (`notificationHandlers.js:439, 474-481`) — that resets on
restart and can double-fire. Before emitting per participant, check
`Notification.findFirstByUserTypeRace(userId, "RACE_ENDING_SOON", raceId)`
(`src/models/notification.js:16-20`); skip if a row exists. The row written by
`sendNotificationToUser` (`notificationHandlers.js:120-129`) becomes the guard. This
is the exact pattern `TEAM_SLACKER_NUDGE` uses (`placementRecompute.js:157-162`) and
it survives restarts and multiple cluster workers. No new column needed.

### Recipients & Exclusions

Enumerate `RaceParticipant.findAcceptedByRace(race.id)` (`ACCEPTED` status). Exclude:

- **Finished** — `participant.finishedAt != null` (frozen standings; the placement
  loop already skips these, `placementRecompute.js:243`).
- **Forfeited** — `participant.forfeitedAt != null` (final-stretch filters these,
  `placementRecompute.js:121, 149`).

Mute gating: `TEAM_FINAL_STRETCH` respects no mute flag today, and there is no
dedicated "race reminders" opt-out column. Match that precedent — **gate on no mute
flag** for v1. (If product later wants an opt-out, reuse `placementAlertsMuted`
rather than adding a column.)

### Send & Payload

Add an `events.on("RACE_ENDING_SOON", ...)` handler in `notificationHandlers.js`,
modeled on `RACE_STARTED` (`:288-329`), using shared `sendNotificationToUser`
(`:71-130`). Canonical race-scoped payload:

```js
payload: { type: "RACE_ENDING_SOON", route: "race_detail", params: { raceId } }
```

`raceId` is auto-extracted from `payload.params.raceId` (`:125-128`), which is what
makes `findFirstByUserTypeRace` dedup work. Reuse `formatTimeLeft(endsAt)`
(`:441-448`) for the "about 2 hours" copy. A `collapseId` is optional (one-shot
push); if used, `race_ending_${raceId}`.

Kill switch: fold into the established pattern — either the existing
`LIVE_PLACEMENT_DISABLED` (since it rides that job) or a dedicated
`RACE_ENDING_REMINDER_DISABLED=true`. Prefer a dedicated switch so it can be killed
without stopping placement pushes.

### Frontend Routing

One-line change: add `case 'RACE_ENDING_SOON':` alongside the other race-scoped
cases before the `return NotificationRoute.raceDetail;` at
`lib/services/notification_service.dart:349`. Param extraction already reads
`params.raceId` from the nested payload (`:255-262`), and the shell listener already
routes `raceDetail` via `raceId` (`main_shell.dart:228-259`). Old apps fall through
to `default: return null` — the alert shows without deep-linking, the documented
additive-type rule.

### Test Plan

- Sends once to each accepted participant when a race with `endsAt` crosses the 2h
  mark.
- Does **not** send for `endsAt == null` (open-ended step-target) races.
- Does **not** send for a race whose total duration `<= 2h` (short seeded race that
  starts already inside the window).
- Does not send to finished or forfeited participants.
- Fires exactly once per participant per race across repeated ticks and across a
  simulated process restart (durable audit-row dedup).
- Two concurrent workers cannot double-send (audit-row check).
- Tap routing opens race detail on both platforms; old-client type falls through
  safely.

### Acceptance Criteria

- A timed race triggers exactly one reminder per active participant, ~2h before end.
- Step-target open-ended races never trigger it.
- The reminder deep-links to the correct race.

## 9. Frozen Cross-Agent API Contract & Data Model

This section is the **interface between the backend and frontend agents**. The
backend agent owns and lands it first; the frontend agent codes against it exactly
and invents nothing beyond it. Any change to this contract mid-build must be raised,
not made unilaterally.

### 9.1 Preference API

```text
GET /notifications/preferences        (auth required)
  200 → { "dailyRewardRemindersEnabled": boolean }
  401 → unauthenticated

PATCH /notifications/preferences      (auth required)
  body → { "dailyRewardRemindersEnabled": boolean }   // unknown fields ignored
  200  → { "dailyRewardRemindersEnabled": boolean }    // the persisted value
  400  → body present but field is non-boolean
  401  → unauthenticated
```

- Absent/never-set preference reads as `true` (the default).
- These endpoints are **new and additive**. Old clients never call them; device-token
  registration and all existing notification endpoints are untouched.
- The frontend reads `GET` on opening Settings (only when OS push permission is
  granted) and writes `PATCH` on toggle. On any non-200, the toggle keeps its
  displayed value and shows no silent change.

### 9.2 Push Notification Types & Payloads

Every payload nests `params` and carries a decorative `route` string; **the frontend
routes on `type` only** (the `route` field is ignored by the client — see §7).

```jsonc
// Race ending ~2h out — deep-links to the race
{ "type": "RACE_ENDING_SOON",        "route": "race_detail",  "params": { "raceId": "<id>" } }

// Daily-reward nudges — both deep-link to the daily-reward screen, no params
{ "type": "DAILY_REWARD_REMINDER_17", "route": "daily_reward", "params": {} }
{ "type": "DAILY_REWARD_REMINDER_21", "route": "daily_reward", "params": {} }
```

Frontend `routeFromType` mapping (add to `notification_service.dart`):

| `type` | `NotificationRoute` |
| --- | --- |
| `RACE_ENDING_SOON` | `raceDetail` (existing enum value) |
| `DAILY_REWARD_REMINDER_17` | `dailyReward` (**new** enum value) |
| `DAILY_REWARD_REMINDER_21` | `dailyReward` (**new** enum value) |

Both daily types map to the same new `dailyReward` route; the shell listener opens the
daily-reward screen (frontend agent locates the current navigation path to it). Old
apps fall through to `default: return null` — alert shows, no deep-link.

### 9.3 Additive `/races` and other response fields

None. The next-box helper that would have added `/races` fields was cut (§2). No
existing response shape changes in this batch.

### 9.4 Migrations

| Change | Table | Notes |
| --- | --- | --- |
| `timezone String?` + `@@index([timezone])` | `users` | Backfill null; sticky-write from `X-Timezone`. First index on this table. |
| `dailyRewardRemindersEnabled Boolean @default(true)` | `users` | Additive; old clients unaffected. Backs §9.1. |
| `deliveryKey String?` + partial unique index | `notifications` | Null for all existing writers; the daily-reminder job's atomic claim (§7). |

No migration is required for Leech (metadata is a JSON column), for the
race-ending-soon reminder (dedup uses existing `Notification` audit rows), or for any
§3/§4/§6 work. `Notification.type` is free-form String, so the new
`RACE_ENDING_SOON`, `DAILY_REWARD_REMINDER_17`, and `DAILY_REWARD_REMINDER_21` types
need no schema change.

## 10. Rollout and Backward Compatibility

1. Deploy backend first: Leech scoring + price + copy, home-card leech fix, timezone
   capture, preference API, the daily-reward scheduler **disabled** via
   `DAILY_REWARD_REMINDERS_DISABLED=true`, and the race-ending reminder **disabled**
   via `RACE_ENDING_REMINDER_DISABLED=true`. Do not deploy production without
   explicit approval at deploy time.
2. Let timezone capture populate for several days before enabling the daily-reward
   sends — the column is null for every existing user on day one. (The race-ending
   reminder does not depend on `users.timezone`; it uses the stored `endsAt`.)
3. Verify old-client contract tests against the new backend: existing endpoints,
   request bodies, race summaries, device-token registration, powerup use.
4. Release the frontend (iOS **and** Android in lockstep) with updated Leech copy,
   effect rail, reveal synchronization, tournament banner, preference toggle, and
   both new notification routes (`RACE_ENDING_SOON`, daily-reward).
5. Enable reminders gradually: race-ending first (no timezone dependency, simple
   dedup), then daily-reward after validating timezone coverage, dedup, and opt-out
   persistence.
6. Monitor: AdMob policy warnings, box-open errors, Leech score deltas (watch for any
   non-monotonic attacker totals and for uncapped drains zeroing victims faster than
   expected), reminder send/dedup counts, invalid tokens, and daily-claim conversion.

Deploy order matters most for Leech: the backend rebalance changes scores for users
still running the old binary, whose baked-in copy still says 1:1. This is accepted —
the mechanic must have one rule across all clients — but the app release should follow
closely.

## 11. Revision Log

**Pass 1 — codebase verification.** Every claim in the original spec was checked
against source. Corrections:

- §3: original said to add a banner without noting `AdBannerSlot` already provides
  adaptive sizing, kill switch, and collapse — rewritten as reuse. Label corrected
  `SPONSORED` → `SPONSOR` to match three existing call sites. Added the
  `test/ad_placements_test.dart` contract, which must pass unmodified.
- §4: original addressed only `_teamColumnCell`; clarified that team **standings**
  planks are a second surface and explicitly out of scope. Flagged the hardcoded
  tooltip offsets that a right-side rail would push off-screen.
- §5: original assumed a measurable 30-minute window. Documented the hourly-bucket
  reality and the shifting live-hour divisor. Documented that per-effect attribution
  does not exist and that the zero-floor is applied once on the whole total, so
  `targetPreLeechScoreAvailable` was undefined — replaced with a concrete
  `targetAvailable` definition and an explicit "leech resolves last" ordering rule.
- §5: found that `getHomeRaceCard` omits LEECH from its prefetch entirely — a
  pre-existing divergence that minting steps would worsen. Added as required work.
- §7 (old): found the three stated constraints mutually unsatisfiable —
  `stepsUntilNextPowerup` needs `baseAdjusted`, which cannot be read in bulk, and
  `totalSteps` is not a substitute because it is effect-sensitive.
- §8 (old, now §7): found `users.timezone` does not exist at all; the cited
  `America/New_York` fallback is request-scoped. Found `JobRun.markRan` is not
  atomic. Found `lastDailyClaimDate` is a client device-clock string, not
  timezone-derived.

**Pass 2 — hard-rule and edge-case audit.**

- Added the missing **Summary & user story**, **Scope / non-goals**, **Data model /
  migrations**, per-section **test plans**, and this revision log, per CLAUDE.md.
  Renamed the file to the required `<feature-kebab>-requirements.md` form.
- Flagged that the original's generic "use a distributed/durable dedup claim" would
  likely lead an implementer to `pg_advisory_xact_lock` — the exact pattern reverted
  in `3e6c827` for pool exhaustion. Replaced with an insert-first unique-key claim
  and an explicit prohibition.
- Flagged that persisting timezone on every request is itself a hot-path write, and
  specified the existing sticky-write pattern instead.
- Noted §6 requires **adding** `PopScope` — no pop interception exists anywhere in
  the case-opening screens today.
- Noted §6's `Open All` fix must also cover `_fallbackSingleOpens`, the 404-compat
  path.
- Added frozen-total and sync-v2-idempotency-cache limitations to §5 as accepted,
  documented behavior.
- Recorded the stealth name/steps inconsistency in `_teamColumnCell` as
  known-and-out-of-scope, to stop an implementer "fixing" it mid-task.

**Pass 3 — interview resolutions (2026-07-18).**

- Leech window: **accept proration, freeze the divisor** — exclude the in-progress
  hour so totals stay monotonic. Lag is accepted.
- Next-box progress on the race menu: **cut entirely**, moved to non-goals. This also
  removes the participant-snapshot migration it would have required.
- Effect rail: **narrow rail wins; 44×44 hit target relaxed** to ~28–32pt, recorded
  as a deliberate deviation.
- Reminder catch-up window: **30 minutes**; missed slots skipped.

**Pass 4 — added scope (2026-07-19).**

- **Leech rebalanced again**, per request: **2:1** (was 3:1), **cap removed
  entirely** (was 1,000 transferred), duration 30 min unchanged, **price 300 → 150**.
  Scoring becomes `floor(attackerWindowSteps / 2)` with `targetAvailable` as the only
  ceiling. Verified against source: single-price store item, no upgrade ladder, and
  `LEECH_STEP_CAP = 3000` is referenced in seven places that must all be deleted.
  Metadata becomes `{ ratio: 2, scoringVersion }` and the scorer must read `ratio`.
  Flagged the balance implication of an uncapped, cheaper drain and updated the test
  plan (cap tests inverted to assert *no* ceiling).
- **New §8: Race-Ending-Soon reminder.** Researched end-to-end. Qualifies on
  `endsAt != null` only (open-ended step-target races are excluded); `endsAt` is a
  stored instant so DST/timezone are irrelevant. Hosts in `placementRecompute.js`
  (already has the candidate query, `msLeft`, participant enumeration, and injected
  deps). Send-once via the durable `findFirstByUserTypeRace` audit-row pattern —
  explicitly **not** the in-memory `Map` throttle `TEAM_FINAL_STRETCH` uses, which
  restart-resets and can double-fire. Excludes finished/forfeited; no mute gating in
  v1 (matches final-stretch). One-line frontend route add. No migration.
- Renumbered Data Model → §9, Rollout → §10, Revision Log → §11. Updated Summary,
  Scope, Data Model note, and Rollout for both additions (race-ending reminder has no
  timezone dependency, so it can enable ahead of the daily-reward sends).

**Pass 5 — two fresh-eyes gap passes (2026-07-19), pre-dispatch.**

- *Contradiction fixed:* §2 non-goals still listed Leech "price" as out of scope
  while §5 changes it 300→150. Rewrote the non-goal to scope in ratio/cap/price and
  keep duration/targeting/shield/stacking out.
- *Summary fixed:* "Five improvements" → "Six" (race-ending reminder was uncounted).
- *Cross-agent contract pinned:* consolidated the previously-scattered interface into
  new **§9.1–9.3** (preference API request/response/error shapes, the three push
  types with exact payloads, and the `type → NotificationRoute` table) so the frontend
  agent codes against a frozen contract. Confirmed §9.3 adds no `/races` fields (the
  cut feature was the only one that would have).
- *Edge case added (§8):* a seeded race with `durationHours <= 2` starts already
  inside the 2h window and would fire a reminder at launch. Added the
  `endsAt - startedAt > 2h` short-race guard, the `startedAt` select note, and a test.
- *Test-precedent added (§3):* before deleting `TournamentSponsorCard`, surface any
  existing test asserting its presence rather than silently editing it.
- *Stale cross-refs fixed:* `§8`→`§7` (routing-bug precedent), `§10`→`§11` (next-box
  cut).

### Resolved — Existing Leech Tests

CLAUDE.md says never modify existing tests and to surface a seemingly-wrong one. The
Leech value assertions in `test/queries/leechScoring.test.js` (3:1, cap 1,000)
correctly describe the *old* mechanic and are superseded by an explicit product
decision, not a bug. **Handling, authorized 2026-07-19:** the backend agent rewrites
only that math suite for 2:1-uncapped and must **enumerate every changed assertion in
its report** (no silent edits). The structural suites (`leechPowerup`, `leechPush`,
`powerups-batch-leech-xray`) stay untouched except where they literally hardcode the
old numbers; any test whose intent is unclear is surfaced, not changed.

### Resolved — Two More Superseded-Behavior Tests (2026-07-19, during build)

Same category, surfaced by the frontend agent rather than pre-authorized:

- `test/tournament_bracket_board_stealthed_test.dart` — dropped the
  `TournamentSponsorCard` import + its "collapse when kill switch off" case (the card
  is retired by §3); kept the "masked player renders `???`" case. Collapse-to-zero is
  now covered by the new §3 banner test. (This is the §3-authorized exception.)
- `test/multi_case_opening_screen_test.dart` — the "open all" case asserted
  `onResults` fires the instant the reels *start* spinning, the exact pre-§6 behavior
  §6 retires. Updated to assert the commit is **deferred** (`handedBack` null while
  spinning, non-null only after every reel lands) — strengthening it to encode the
  §6 guarantee. Both cases in the file pass.
