# Feature Batch 2026-08-08 — Requirements

Source: Rohan's notes-app screenshots (IMG_3493–3497) + follow-up answers.
Repos: frontend `/Users/rohan/repos/stepv2-frontend`, backend `/Users/rohan/repos/stepv2-backend`.

Status legend: **[OPEN]** = awaiting Rohan's decision (Phase 3 interview).

## Summary & user stories

Twenty items: 14 features, 4 bug/tweak fixes, 1 art task, 1 perf investigation.
Broad goals: make powerups less dead-endy (discard for coins, ad reroll,
loading feedback), make races feel more rewarding (podium, team payout buff,
auto-start, milestone pushes), improve trust/marketing surfaces (privacy copy,
mission statement, suggestion box, social links, What's New), and admin
visibility (version + private-race stats).

## Scope / non-goals

- Non-goals: no changes to solo race payout presets, drop odds, or upgrade
  costs; no Android-only or iOS-only behavior (both platforms always) —
  **one amended exception**: the box-reroll rewarded ad is effectively
  iOS-only until Android ads roll out (see Item 11); no new cosmetics; no
  ads beyond the one new rewarded placement (box reroll).
- Item 15 (tap-outside closes powerup modal) is a **verify-only** item: the
  sheets already use `showModalBottomSheet` defaults (`isDismissible: true`) —
  `race_detail_screen.dart:2538`. Deliverable = a widget test asserting it,
  no behavior change.
- Item 17 (stands clash with animals in track art) is routed to the
  `accessory-art` pipeline as a separate parallel task, not to the
  implementation agents.
- Ignored per Rohan: Second Wind × Trail Mine, ad eCPM notes, powerup-balance
  faded line, Leg Cramp / Wrong Turn upgrade nerfs.

---

## Item 1 — Discard powerups for coins (rarity-priced, capped) + confirm dialog

Today `POST /races/:raceId/powerups/:powerupId/discard`
(`src/modules/powerups/commands/discardPowerup.js`) pays nothing. Change: a
discarded **HELD** in-race powerup awards coins by rarity.

**Economy (game-analyst verdict: SOUND WITH CHANGES — Rohan adopted):**
- Prices (DECIDED 2026-08-08): **COMMON 2 / UNCOMMON 5 / RARE 10**, stored in
  balance config (env-independent, admin-tunable like other balance values)
  so they can be raised later without an App Store release.
- **Daily cap: 40 coins/user/local-day**, env-tunable
  `POWERUP_DISCARD_DAILY_COIN_CAP` (precedent: `AD_COIN_REWARD_DAILY_CAP`;
  parse via the `positiveIntEnv` guard pattern so a malformed value can't
  read as "no cap"). Cap consumed = sum of `coin_transactions` with
  `reason='powerup_discard'` for the user's local date (tz from
  `users.timezone`, default ET), computed **in pure SQL**:
  `(created_at AT TIME ZONE 'UTC' AT TIME ZONE $tz)::date = $localDate` —
  prod datetimes are tz-naive and node-pg shifts them on the way out; never
  compute the day boundary in JS.
- **Cap semantics (architect-required, decided): partial award.** At 38/40
  with a RARE (10), award `min(price, capRemaining)` = 2; at 40/40 award 0.
  `coinsAwarded` in the response always reflects the actual award.
- **Cap is not atomic** (two concurrent discards can overshoot by one price).
  Accepted — worst case is one extra sub-10-coin award.
- **New index required**: `coin_transactions` has only `@@index([userId])`;
  the per-day cap sum would scan a user's whole ledger per discard. Add
  `@@index([userId, reason, createdAt])` in the same migration.
- **Unopened `MYSTERY_BOX` discards award 0** (still allowed to discard, as
  today). Otherwise never-opening dominates (exploit S4).
- Rarity source: the `RacePowerup.rarity` column; if null (stash-redeemed
  powerups have `rarity: null`), award **COMMON price** (floor, defensive).
- Scope (DECIDED): **in-race discard only**. Global-stash sell is explicitly
  out of scope (possible fast follow reusing the same price/cap service).

**API contract (backward compatible — additive response fields only):**
```
POST /races/:raceId/powerups/:powerupId/discard
200 → {
  ok: true,
  coinsAwarded: 10,          // NEW; 0 for MYSTERY_BOX status or cap reached
  coins: 1234,               // NEW; new balance
  capRemaining: 30           // NEW; after this discard
}
```
Old clients ignore the new fields and behave exactly as today (they still get
the coins server-side — harmless, invisible). No new required request fields.

**Idempotency (architect-corrected):** `discardPowerup.js` today does a plain
read-then-update (TOCTOU — two concurrent discards both pass, and both write
feed rows). Change the status write to a conditional
`updateMany({ where: { id, status: { in: ['HELD','MYSTERY_BOX'] } } })` and
proceed (award coins, feed event) only when `count === 1`. Defense in depth:
the coin award goes through `awardCoins` with `reason: 'powerup_discard'`,
`refId: racePowerupId` — the `@@unique([userId, reason, refId])` index on
`coin_transactions` makes a duplicate mint impossible even if the CAS is ever
bypassed. Integration test: two concurrent discards → one ledger row, one
feed row.

**Balance-config key (architect-required):** add `discardPrices` to
`defaultConfig()` in `balanceConfig.defaults.js` as an **optional** key —
validate only when present, do NOT bump `SCHEMA_VERSION` (stored rows predate
new keys and a version bump hard-rejects them), add a `SOFT_BOUNDS` entry.
Follow the `teamOnlyTypes` precedent exactly. Required test: round-trip
through the admin save path and `balance:apply` with a stored config that
lacks the key (the known partial-row-blocks-apply failure), plus a check that
every sanitizer copy passes the key through (tuner-wipe bug class).

**Frontend:**
- Confirm dialog before discard ("Discard <name> for <n> coins?" / for boxes
  "Discard this mystery box? You won't get coins for unopened boxes.") —
  attach at `_showPowerupActions` DISCARD button
  (`race_detail_screen.dart:2630-2645`) and the `pocket_watch_sheet.dart`
  `onDiscard` path. Hidden in `demoMode` (already is).
- Show `coinsAwarded` in the success toast; optimistically bump the coin
  badge. If the response lacks `coinsAwarded` (older backend), show the plain
  "Discarded" toast — degrade safely.
- When `capRemaining` is 0, the dialog says "Daily discard bonus reached —
  you'll get 0 coins" (still allows discard).

**Deploy order:** backend first (old clients unaffected), then app.

## Item 2 — Private races auto-start when all invitees have joined

When the last outstanding invite for a **private** (`isPublic:false`) race is
accepted, start the race immediately instead of waiting for the creator.

**Trigger conditions (all required):**
- Race `status === 'PENDING'`, `isPublic === false`, not seeded (`seedId`
  null), **not tournament-managed (`tournamentId` null)** — the tournament
  engine owns those races' lifecycle.
- No `scheduledStartAt` in the future (a scheduled race keeps its schedule).
- Every participant row is resolved: zero rows in `INVITED` status **whose
  invite is still live** — architect correction: nothing ever transitions an
  expired `INVITED` row out of that status, so the predicate must treat
  `status='INVITED' AND inviteExpiresAt <= now()` as resolved, or one silent
  invitee blocks auto-start forever. DECLINED rows don't block either.
- `countAccepted >= 2`; team races additionally require even sides (reuse
  `startRace`'s existing `TEAMS_UNEVEN` guard — if uneven, do NOT auto-start;
  leave pending, no error surfaced to the accepter).

**Implementation (architect-revised):**
- **Hook placement — NEVER inside `joinRaceCore` and never inside the join
  advisory lock.** `joinRaceCore` always runs under `withRaceJoinLock`
  (advisory lock), and `startRace` does per-participant steps lookups +
  updates + push emission — holding the lock across that is the 3e6c827
  pool-exhaustion outage shape. Hook in the **callers, after the locked
  section returns**: `joinPublicRace.js` / `joinRaceByShareToken.js`, and in
  `respondToRaceInvite.js` after the participant update commits. Never inside
  a transaction with the participant write.
- Call `startRace({ raceId, userId: race.creatorId })` — exactly what the
  cron does. **No new `bypassCreatorCheck` flag**: passing the accepter's id
  would mis-attribute the `RACE_STARTED` feed row and push to whoever
  accepted last.
- Never let auto-start failure fail the join: try/catch, log, leave PENDING
  (creator can still start manually).
- Latency bound: if the race has more than 10 participants, skip the inline
  auto-start and let the cron backstop pick it up on the next tick (the
  accept response shouldn't carry a large start's work on the one-vCPU box).
- `startRace`'s existing `updateIfPending` CAS makes double-fires safe.
- **Backstop (architect correction — needs a new model query):**
  `selectRacesToAutoStart` only sees rows from `Race.findScheduledDue`, whose
  where clause requires `scheduledStartAt: { not: null }` — an unscheduled
  private race is never a candidate. Add a new model query (PENDING,
  `isPublic:false`, `seedId:null`, `tournamentId:null`,
  `scheduledStartAt:null`, participants included) feeding the same 5-min
  tick, applying the full predicate above (this also catches races whose
  last invite expired).
- Kill switch: env `PRIVATE_RACE_AUTOSTART_DISABLED=true` (gates both the
  inline hook and the backstop query).

**Old clients:** they already render PENDING→ACTIVE transitions discovered by
poll (`getRaceDetails`), and `RACE_STARTED` push type already exists. The
accepter's own client may still show the pending screen until next fetch —
acceptable; new clients refresh after accept.

## Item 3 — Evening reminder push for uncollected milestone coins

Once per local day, **19:00 local** (single slot, catch-up 30 min), send a
push to users who have claimable step-milestone coins they haven't collected.
Never sends when there's nothing to collect (Rohan: "do not spam").

**Backend — new job `src/modules/notifications/stepMilestoneReminder.js`,
cloned from `dailyRewardReminder.js`:**
- Same skeleton: 5-min tick in `startCrons`, `zonesAtSlot`, per-zone
  `JobRun.claimRun('step-milestone-reminder', localDate + zone)` CAS,
  INSERT-FIRST `Notification.deliveryKey =
  'step-milestone:${userId}:${localDate}'` dedup, then
  `events.emit('STEP_MILESTONE_REMINDER', …)`; handler in
  `notificationHandlers.js` sends with `skipAudit: true`.
- Eligibility: **set-based SQL per zone** (not N per-user queries): join
  `steps` (local date's row, `steps >= 5000`) against a count of
  `step_milestone_claims` for that user/date; eligible when thresholds
  crossed > claims made. Thresholds from
  `src/modules/steps/constants/stepMilestones.js` ({5000,10}…{20000,50}).
  Architect requirements: the job needs its **own user query** — it must
  filter `stepMilestoneRemindersEnabled: true` AND `EXISTS (device_tokens)`
  (`findRemindableInZones` hardcodes the daily-reward pref and can't be
  reused as-is). Type mismatch: `steps.date` is a `DateTime` while
  `step_milestone_claims.claimed_date` is TEXT — the join needs an explicit
  cast. localDate derived from `users.timezone` server-side.
- **Bias-to-silence as a concrete rule** (mirroring `claimSuppresses`):
  suppress the push if any milestone claim exists for `localDate`,
  `localDate-1`, or `localDate+1` — the client's claim localDate can disagree
  with the server's by ±1 day near midnight; when in doubt, don't send.
- Note (accepted): the pref defaults to `true`, so frozen clients receive
  this new push type with no in-app opt-out until they update — same
  precedent as the daily-reward reminder launch.
- Copy: title "Coins waiting! 🪙", body "You crossed a step milestone today —
  collect your coins before midnight."
- Push `type: 'STEP_MILESTONE_REMINDER'`, payload routes new clients to
  `NotificationRoute.home` (`routeFromType` addition). **Old clients**: unknown
  type → alert with no deep link (existing safe fallback in
  `notification_service.dart:439`).
- Kill switch `STEP_MILESTONE_REMINDERS_DISABLED=true`; **ship dark** (switch
  on in prod only after verifying on staging). Inherit the null-timezone
  caution from `index.js:118-131`.
- Preference: new `users.stepMilestoneRemindersEnabled Boolean @default(true)`
  column; extend `GET/PATCH /notifications/preferences` (additive field — old
  clients' PATCH omitting it leaves it untouched; GET's extra field ignored).

**Frontend:** new toggle in Settings → NOTIFICATIONS mirroring
`_DailyRewardReminderToggle` (`settings_screen.dart:677`). Degrades: if GET
response lacks the field, hide the toggle.

**Deploy order:** backend (dark) → staging soak → enable in prod. Frontend
toggle ships whenever; not blocking.

## Item 4 — Podium screen when a race ends

Fun-Run-style 1st/2nd/3rd podium for **solo (classic) races**. Team races keep
the existing winning-team board (`_buildTeamWinnerBoard`); tournaments keep
their flow.

**Scope (DECIDED): both surfaces** — the completed race detail view
(replacing the single-winner card at `race_detail_screen.dart:5823-5867`)
and the post-race results popup (`race_results_summary_screen.dart`),
sharing one `RacePodium` widget.

**Frontend-only.** Data already present: participants ordered by
`orderRaceParticipantsForDisplay` → top 3 with `accessories`/`animal` for
`RacerAvatar`; payouts via `race_payouts.dart` + `payoutPlacementLabel`.
- `RacePodium` widget: three platforms (2nd left, 1st center raised, 3rd
  right), `RacerAvatar` on each, name + steps + coin payout beneath, confetti
  on entrance reusing the existing happy-moment confetti. Podium platform
  graphic: UI chrome (blocks/shadows) may be hand-coded; if a pictorial
  pixel-art podium is wanted, generate via `accessory-art` (do NOT hand-draw).
- Fewer than 3 finishers: render only the platforms that have occupants
  (2 participants → 1st + 2nd; degenerate 1 → existing winner card).
- States: forfeited viewers still see the podium; stealth is irrelevant
  (completed races unmask — `finishedAt` set clears stealth masking).
- Ordering dependency: the podium consumes
  `orderRaceParticipantsForDisplay` — **implement Item 18 (stealth ordering
  fix) first**, and include a podium test for a completed race that had
  stealth active during the run.
- Mirrors: tutorial/demo fixtures render completed states? Demo race ends at
  a scripted beat — `ui-test-planner` to enumerate; add fixture fields if the
  podium reads any key missing from `demo_race_engine.dart` /
  `tutorial_preview_data.dart`.

## Item 5 — Team race payout buff (game-analyst package)

Current: winning side splits `players × durationPoints × 20` evenly; losers
get 0; a 14-day race pays 22.9 coins/day — worse than one rewarded ad.

**DECIDED 2026-08-08 (Rohan, overriding the analyst's fuller package):**
increase **winner** payouts only. Losers stay at 0. No eligibility gates, no
step floor, no throttle, no winner/loser split. Target: 14-day 5v5 winner
320 → **600** each.

Implementation, all backend (architect-revised):
- **The multiplier lives in the shared pool formula, not only settlement.**
  Every read path projects the pool through `buildRaceMoneyView` →
  `computePrizePool` — multiplying only in `completeRace` would advertise
  320 during the race and pay 600 at the end. Thread a team multiplier
  through `computePrizePool` / `buildPrizePoolPayload` /
  `computeSettledRacePool` so projection and settlement are the same
  function. Tournaments call `computePrizePool` with their own params and
  must be explicitly unaffected (multiplier applies only when
  `isTeamRace === true`).
- **Stamp at creation, settle from the stamp** (project idiom for
  payout-sensitive knobs): new column `races.teamPoolMultBps Int?` written at
  race creation from env (`TEAM_POOL_MULT_SHORT=1.0` ≤3d,
  `TEAM_POOL_MULT_MID=1.5` 4–7d, `TEAM_POOL_MULT_LONG=1.875` ≥8d → stored as
  basis points, e.g. 18750). Projection and settlement both read the stamp;
  `null` (legacy/pre-deploy races) → 1.0. Consequence: an env edit affects
  only races created after it — in-flight races never reprice mid-race.
- Env parsing: floats via a guarded parser (generalize `positiveIntEnv`);
  malformed → fallback 1.0, never NaN (a NaN would zero payouts).
- Resulting per-head winner payouts: 14d = **600**, 7d = **240**,
  ≤3d unchanged, 1v1 14d = 600 (pool 320×1.875).
- `poolMax()` (16000) applies after multiplication — it now binds earlier
  for large/long team races (noted, accepted).
- Floor the final pool to an integer.

**Risk note (logged, accepted by Rohan):** the analyst's anti-farm gates were
declined. The 2-account 1v1 farm (exploit S2) pays 1.875× more after this
change and there is no concurrent-race limit. Revisit if coin supply spikes;
the multipliers are env-tunable for an instant partial rollback.

**Tie behavior (DECIDED by Rohan 2026-08-08):** on a funded team-race tie,
**mint the (multiplied) pool and split it evenly across ALL non-forfeited
members of both teams** — remainder to the overall top stepper (tiebreak
earliest `joinedAt`, then userId, matching the win branch). Buy-ins still
refunded as today. This replaces the current tie branch that never mints
the pool (latent pays-everyone-0 bug, `completeRace.js:161-181`).
Settlement test: tie scenario asserts exact even ledger rows + remainder.

**Old clients:** payout amounts are server-computed — no client change; the
results popup shows whatever `myPayoutCoins` says.

**Integration tests first**: settle path per scenario (14d/7d/3d team win →
exact per-head ledger rows; pool cap; multiplier env overrides) via the real
expiry path (`raceExpiry` → `completeRace`) on the test DB.

## Item 6 — Privacy pitch on the health-connect screen

Copy change on `onboarding_flow.dart:149-162` body +
add explanatory copy to `_ConnectHealthRow` (`settings_screen.dart:551`, which
today is a bare button). Draft copy (must remain truthful — we DO store step
counts + display name server-side; do not claim "we collect nothing"):

> "Bara only reads your step count — never your routes, workouts, heart rate,
> or location. Your steps are used for races and nothing else, and we never
> sell your data."

Final copy subject to Rohan approval in the spec review. Mirrors: onboarding
gate is rendered in onboarding v3 flow; `ui-test-planner` to enumerate.

## Item 7 — In-app suggestion box

Goal: catch feedback before it becomes a 1-star review. **DECIDED:** in-app
form stored server-side.

**Backend:** new module `src/modules/feedback/`:
- `model Suggestion { id, userId, text (≤2000 chars), category?, appVersion,
  platform, createdAt }` + migration. **`onDelete: Cascade` on the user FK
  and add the table to `deleteUserAccount`'s deletion set** (account deletion
  already fights a 5s transaction timeout; a blocking FK would break it).
  PII stance: free-text retained until account deletion, admin-only access,
  cascade-deleted with the account.
- `POST /feedback/suggestions` (requireAuth) → 201 `{ ok: true }`; rate-limit
  5/user/day (count rows per user per UTC day; 429 beyond). Reads
  `X-App-Version` header for provenance.
- `GET /admin/feedback/suggestions?limit=50&before=` (admin-gated) — newest
  first, for reading them in the admin screen.
- Old clients: endpoint is new — nothing to break.

**Frontend:** "SEND FEEDBACK" PillButton in Settings → HELP & LEGAL (above
SUPPORT), opening a bottom sheet: multiline field, char counter, SUBMIT →
"Thanks! We read every one." toast. Error state: offline → keep text, show
retry. Admin: simple list view appended to `AdminScreen`. (Single entry point
in Settings for v1; more entry points can follow if volume is low.)

## Item 8 — What's New sheet (every fresh install + every update)

Frontend-only. Bundled changelog: `lib/content/whats_new.dart` — an ordered
list of `WhatsNewEntry(version, List<String> bullets)`; the sheet shows the
newest entry matching `PackageInfo.version` (exact match; no entry → show
nothing).
- Persistence: `lastSeenWhatsNewVersion` via `OnboardingStateService`
  (SharedPreferences). Show when `lastSeenWhatsNewVersion !=
  currentVersion` — which includes fresh installs (null ≠ version), per
  Rohan's ask. **Exclude the key from `clearPersistedState()`** sign-out wipe
  (deliberate — same trap as the rename chip; document in code). Structural
  test required: assert the key is absent from
  `OnboardingStateService.allKeys` — the exclusion is enforced by omission
  and would be silently undone by the next person adding keys.
- Hook: `_maybeShowWhatsNew()` in `main_shell.dart` after
  `_loadHomeAndShowResults()` settles, ordered AFTER
  `_maybeShowRaceResults()`/`_maybeShowRankedResults()` and before the
  share-race drains — never stack two modals: if a results modal showed this
  session, defer What's New to next launch.
- Onboarding conflict (DECIDED): suppress during the onboarding session —
  fresh installs see the sheet on their **second** session; updaters see it
  immediately. Implement by recording `lastSeenWhatsNewVersion =
  currentVersion` when onboarding completes (marks it seen without showing).
- Release process note: add a "update whats_new.dart" step to DEPLOYMENT.md.

## Item 9 — Admin stats: users per app version + private race count

**Backend (architect-revised — write amplification):**
- Sticky-write `users.lastAppVersion` + `lastSeenAt` in `requireAuth.js`
  alongside the timezone sticky-write, but **fire only when `lastAppVersion`
  changed OR the stored `lastSeenAt` UTC date ≠ today** — never per-request
  (3e6c827 lesson), one combined UPDATE. Use a **dedicated model method that
  does NOT go through the `User.update` chokepoint** — that chokepoint DELs
  the `/auth/me` cache and a daily write per user would gut the hit rate of
  the #2 endpoint's cache. Neither column is added to the `/auth/me`
  payload. Validate with the existing `SAFE_APP_VERSION` regex; never fail
  the request. Migration adds nullable columns — old rows null until next
  request; old clients already send `X-App-Version`, so data populates
  immediately; clients without the header → bucket "unknown".
- `getAdminStats.js`: add `versions: [{version, platform, users}]` (group by
  `lastAppVersion` over users seen in last 30d — include a `null → "unknown"`
  bucket and a `since` date in the payload: at launch every row is null until
  each user's next request, and without the label the section reads as "all
  users on no version" for the first day) and
  `races: {privateTotal, privateActive, publicTotal, publicActive}`
  (`isPublic` grouped by status). Additive response fields — old admin
  clients ignore them.

**Frontend:** two new `_section` blocks in `AdminStatsCard`
(`admin_screen.dart:752`): "VERSIONS" and "RACES". Missing fields → hide
sections (defensive read).

## Item 10 — Social media links in Settings

New Settings section "COMMUNITY" between HELP & LEGAL and ACCOUNT: one row
per platform with logo + handle, launching via a new absolute-URL variant of
`_openUrl` (`LaunchMode.externalApplication`).
Platforms (DECIDED 2026-08-08): **Instagram
`https://instagram.com/bara.steps`** and **X
`https://x.com/barastepz`**. TikTok deferred (add the row later when the
account exists — keep the section layout ready for a third row).
Logos: use official brand glyphs as bundled PNG assets (brand logos are not
hand-drawn art and not capybara art — pixel-art restyling of trademarks is
not appropriate; use monochrome official glyphs tinted to theme ink).
Dark-mode: tint via theme tokens (ink flip trap from 07-23 batch).

## Item 11 — Rewarded-ad mystery box reroll (once per roll)

After a mystery box reveals its powerup, the user may watch a rewarded ad to
reroll it once. Reuses the SSV plumbing from the daily-spinner extra spin.

**Backend:**
- New reward kind `BOX_REROLL_REWARD_KIND = 'box_reroll'` in
  `src/modules/economy/adRewards.js`. Kill switch `ADS_BOX_REROLL_ENABLED`
  must default **OFF**: check `=== 'true'` (the existing `!== 'false'` idiom
  defaults ON — architect catch), and read it **at call time**, not module
  load.
- **Grant kind must be derived from a dedicated customData prefix** —
  architect catch: `grantAdReward` maps customData prefixes to kinds and
  falls back to `extra_daily_spin` for a bare date, so "customData
  unchanged" would mint extra-spin grants from reroll watches and the two
  features would eat each other's credits. Client sends
  `customData = 'box_reroll:<userId>:<localDate>'`; backend adds
  `BOX_REROLL_CUSTOM_DATA_RE` + kind mapping exactly mirroring
  `SHOP_UNLOCK_CUSTOM_DATA_RE`. Consume filter: `rewardKind='box_reroll' AND
  consumedAt IS NULL AND grantedDate = <user's local date>`. Grants are "1
  reroll credit", not bound to a specific box; binding happens at consume.
- New endpoint:
```
POST /races/:raceId/powerups/:powerupId/reroll
200 → { id, type, rarity, rerolled: true }
409 { code: 'ALREADY_REROLLED' }   // once per roll
409 { code: 'AD_NOT_VERIFIED' }    // no unconsumed grant yet (client retries ≤5x — same as extra spin)
400 { code: 'NOT_HELD' }           // only a HELD powerup that came from a box (rarity != null) can reroll
```
- Mechanics: consume an unconsumed `box_reroll` grant CAS-style
  (`updateMany where consumedAt: null` — same as `claimExtraDailyRewardBox`),
  then reroll **the same RacePowerup row** with a fresh
  `buildRollContext` at current position (result may be worse — result is
  final), update `type`/`rarity`, **restamp `configVersion`** (it audits
  which balance config produced the roll — a reroll under a newer config must
  not lie), and stamp new column `race_powerups.rerolledAt DateTime?`
  (migration). `rerolledAt != null` → 409 on repeat. Race must still be
  ACTIVE; powerup must be `HELD`, unused, `rarity != null`, and
  **`upgradeLevel === 0`** (reject otherwise — rerolling a cheaply-upgraded
  type into an expensive one while keeping paid levels is an exploit).
- No `invalidateRaceProgress` call is needed: `powerupData` is built in the
  per-viewer overlay, not the shared snapshot — do not add a redundant cache
  seam (architect note for the implementer).
- Feed: suppress a duplicate `MYSTERY_BOX_OPENED`-style event; write a
  `POWERUP_REROLLED` event filtered from the visible feed like box-opens.

**Frontend:**
- `CaseOpeningScreen`: after reveal (`_revealed`), show "REROLL · WATCH AD"
  button iff the backend advertises the feature (add `boxReroll: true` to
  `getRaceProgress.powerupData` when the kill switch is on AND client
  declares `ads` in `X-Client-Features`) and this box hasn't rerolled.
  Tapping: load + show rewarded ad via a new `AdService` controller cloned
  from `ExtraSpinAdController` (new ad unit id via `--dart-define`, PROD
  only, staging omits — same pattern as `ADMOB_EXTRA_SPIN_AD_UNIT_ID`), then
  call reroll with the extra-spin retry loop, re-spin the reel to the new
  result.
- Old clients: never see the button (no client change = no reroll) — fully
  additive. Demo mode: hidden (and `DemoRaceApiService` /
  `tutorial_preview_data.dart` must not advertise `boxReroll`).
- **Platform reality (architect catch, amending the batch non-goal):** the
  rewarded-ad define is prod-iOS-only today, so reroll ships **iOS-only for
  now** — same as the daily-spinner extra spin, and the user base is
  currently iOS-only. Android parity lands with the Android ads rollout;
  the Dart code stays platform-neutral (button appears wherever the ad
  controller reports ready).

**Deploy order:** backend dark → App Store build with button + ad unit →
flip `ADS_BOX_REROLL_ENABLED`.

## Item 12 — Loading indicators for powerup actions

Frontend-only.
- Add `loading` param to `PillButton` (`lib/widgets/pill_button.dart`):
  swaps label for a small spinner, implies disabled, preserves width.
- Replace the blanket `_isActing` disable with per-action busy tracking:
  `String? _actingPowerupId` alongside `_isActing` (keep `_isActing` as the
  global guard; the id drives which button shows the spinner).
- Wire into: stash USE rows (`stash-use-<TYPE>`), sheet USE/tier buttons,
  DISCARD, `_OpenAllButton` ("OPENING…" + spinner while the batch runs, which
  also covers queued→inventory movement), PocketWatch confirm.
- The action sheets currently pop before the async call; keep that pattern
  (indicator lives on the underlying screen's buttons) EXCEPT the stash
  confirm sheet, which stays open with an in-sheet spinner (it owns the
  two-round-trip redeem→use chain — `race_detail_screen.dart:1807`).
- Widget tests: pump race screen, tap USE, assert spinner present while the
  (mocked-at-HTTP-layer) request is in flight. PackageInfo mock in setUp
  (known hang trap).

## Item 13 — Rename "Solo" → "Classic" + mode descriptions

Frontend-only copy change in `create_race_screen.dart` (`:675` label
`'SOLO'` → `'CLASSIC'`; keys unchanged — `race-format-ffa` stays). Add a
one-line description under the format card that changes with selection:
- Classic: "Every player competes individually. Invite friends or let anyone join."
- Teams: "Two teams compete for the highest combined step total."
- Bracket: "Advance through head-to-head rounds until one winner remains."
No enum/API impact ("solo" exists only in the analytics allowlist — leave the
analytics value `solo` as-is so dashboards stay continuous). Update
`test/create_race_screen_test.dart` label assertions (mechanical). Demo
mirror: `CreateRaceScreen(demoMode:true)` renders the same copy —
`ui-test-planner` to list checks.

## Item 14 — Mission statement on the title screen

Add "We're on a mission to make your daily steps fun" to `start_screen.dart`
as a smaller line **under "STEP. RACE. WIN." (keep both — DECIDED)**. Don't
wrap the "Bara" title in new gestures (reviewer-login easter egg at `:32`).

## Item 16 — Remove participant chips between race art and standings

The chips in Rohan's screenshot (rows of `@name` pills with colored dots
below the track art on race detail). Candidate widgets identified:
on-track `_RunnerNameTag` overflow (`home_course_track.dart:1337`) vs. the
`goal_track.dart:212 _buildLegend` dot+name Wrap. **[OPEN — confirm exact
element before deletion]**: implementation must first reproduce the screenshot
(the row sits between the hero and STANDINGS and shows status dots — most
likely the legend Wrap), screenshot it, and get Rohan's confirm in the manual
checklist rather than guessing. Removal must be checked in the demo-race
tutorial + tab tutorial mirrors (both render the real screen).

## Item 18 — Stealth standings "1 2 1 2" fix

Root cause: backend nulls `placement` on stealthed rows
(`getRaceProgress.js:972`); frontend `orderRaceParticipantsForDisplay` is
all-or-nothing — any null placement makes ALL rows fall back to index ranks,
and stealthed rows then display their array index (1,2) while visible rows
display server placement (1,2,3).

**Fix (frontend-only — backend masking is intentional and old clients keep
current behavior):**
- `race_participant_display.dart`: stop the all-or-nothing fallback **for the
  partial-null (stealth) case only**. Order = stealthed rows pinned top (as
  server sorts), then by server placement when present, index fallback
  otherwise.
- **Detour Sign (architect catch):** when the viewer is detoured the backend
  nulls `placement` on EVERY row with `stealthed: false` — under the naive
  new rule every row would get an index-derived number, reproducing the bug
  in a different mask. Rule: when **all** rows have null placement, keep the
  existing wholesale `sortRaceParticipantsForDisplay` fallback and today's
  rendering (the detour illusion intends scrambled/unranked standings).
  Widget test covers this case explicitly.
- Rank display: stealthed rows show **"?"** on the shield (no number), never
  an index-derived number. `leaderboard_plank.dart` `_RankShield` gets a
  `hidden` state; `race_detail_screen.dart:7646` passes it; team cell
  `:6990` gets the same server-placement override + "?" treatment (it
  currently has none).
- `_myViewerPlacement` and the pinned-self gap marker assume contiguous
  ranks — re-verify with stealth rows present (widget test: 2 stealthed + 3
  visible → shields ?, ?, 1, 2, 3; viewer pin correct).

## Item 19 — Multiplier chip missing in team-race live scoreboard

Frontend-only. Extract `LeaderboardPlank._multiplierChip`
(`leaderboard_plank.dart:85`) into a shared widget; render it in
`_teamColumnCell` (`race_detail_screen.dart:6939`) next to the name, fed from
`p['currentMultiplier']` (backend already sends it for team races).
Suppressed when stealthed/null — same rules as solo. Defensive: absent field
→ no chip.

## Item 20 — App startup speed

Investigation + fix, frontend-only, no visual change:
- Pre-`runApp` (`main.dart:25-79`): `Future.wait` the independent disk/prefs
  inits (`persistBackendBaseUrl`, `AppThemeController.loadPreference`,
  `RemoteAssetCache.init`); move `InstallAttributionService
  .resolveOnFirstLaunch()` off the critical path (fire-and-forget with
  completion awaited before the first referral-dependent screen);
  Firebase/notification/deeplink inits stay ordered where required — verify
  each dependency before reordering.
- `_restoreAndFetch` (`main_shell.dart:785`): collapse
  `_loadOnboardingState`'s 4 sequential SharedPreferences reads into one
  `Future.wait`; parallelize the independent platform-channel calls
  (`enableHealthKitBackgroundDelivery`, `_checkNotificationState`).
- Measure before/after (timeline from `flutter run --profile`, cold start ×3
  on a real iPhone) and report numbers; do NOT ship a reordering that changes
  observable behavior (attribution, notification routing) without noting it.
  `Future.wait`-ing `RemoteAssetCache.init` alongside Firebase init is the
  reordering most likely to change observable behavior — measure it
  separately from the safe prefs batch.
- Explicitly out of scope: deferring `_persistSteps()` before the home batch
  (comment documents why it's ordered; needs its own investigation).

---

## Backward-compat & rollout (whole batch)

Deploy order: **backend first**, everything dark or additive:
1. Backend: discard coins (additive), auto-start (kill switch), milestone
   reminder (dark), team payouts (env-tunable — flip after review), reroll
   (dark), admin stats (additive), suggestions (new), prefs field (additive).
   Migrations: `users.lastAppVersion/lastSeenAt`,
   `users.stepMilestoneRemindersEnabled`, `race_powerups.rerolledAt`,
   `suggestions` table — all additive/nullable, no backfill needed.
2. Verify prod old-client behavior unchanged (spot-check current App Store
   build against staging-promoted backend).
3. Frontend release (iOS + Android in lockstep, same version/build): all
   client features degrade when a field is missing.
4. Flip switches: milestone reminders after staging soak; box reroll after the
   carrying build rolls out (~a week phased); team payout multiplier after
   Rohan confirms numbers.

## Test plan (tests-first, both agents)

Backend (`test/integration/feature-batch-2026-08-08.test.js` + focused files):
- Discard: HELD awards rarity price; MYSTERY_BOX awards 0; cap enforced
  across local-day boundary; double-tap doesn't double-mint; response fields.
- Auto-start: invite 2 → accept both → ACTIVE; decline doesn't block; team
  uneven doesn't start; scheduled-future doesn't start; public doesn't start;
  kill switch off → no start.
- Milestone reminder: eligible user gets exactly one Notification row per day
  (deliveryKey dedup); no-coins user gets none; pref off gets none; kill
  switch respected.
- Team payouts: each scenario in Item 5; assert exact coin ledger rows.
- Reroll: happy path (grant → reroll → new type persisted, rerolledAt set);
  second reroll 409; no grant 409 AD_NOT_VERIFIED; race completed 400;
  kill switch hides `boxReroll` flag in progress payload.
- Admin stats: seeded users/races → exact version buckets + private counts.
- Suggestions: post → 201 + row; 6th of day → 429; admin list gated.
- Prefs: PATCH new field; old-shape PATCH leaves it untouched.
- **Frozen-client contract tests** (architect suggestion, adopted): one test
  per changed response asserting the old shape still round-trips (discard
  without reading new fields; prefs GET/PATCH pre-field shape) — not just
  "additive, so fine".
- **One full backend suite run with `REDIS_URL` unset** — items 1/9/11 touch
  write paths whose cache invalidation hangs off Redis; the no-Redis
  configuration is a standing invariant.

Frontend (widget/integration tests, real screens pumped):
- Discard confirm dialog shows price; toast on success; degrade without field.
- Stealth standings: shields ?, ?, 1, 2, 3 (regression for 1-2-1-2).
- Team cell renders multiplier chip; absent → none.
- Powerup modal: tap outside dismisses (Item 15 verify).
- PillButton loading state; USE shows spinner during in-flight request.
- What's New: shows once per version incl. fresh install; not over results
  modal; survives sign-out.
- Create-race copy: CLASSIC label + per-mode descriptions.
- Podium: 3-, 2-, 1-finisher renders.

## Acceptance criteria / definition of done

- All tests above green (backend suites via `test:integration` on test DB;
  never prod).
- `ui-test-planner` manual checklist executed by Rohan (mirrors included).
- Both platforms build (`flutter build ipa`, `flutter build appbundle
  --flavor prod`) with correct defines.
- `code-reviewer` pass on the combined diff.
- game-analyst numbers as approved by Rohan committed to
  `docs/economy.md` (already drafted there).
- Art item 17 delivered via accessory-art with Rohan's visual approval.

## Manual UI-placement test plan

(From `ui-test-planner`, 2026-08-08, verbatim. Risks 1–8 at the bottom are
binding spec steps for the implementation agents.)

*Elements under test:*
1. Discard confirm dialog + coins toast — new, on race-detail powerup sheet and pocket-watch sheet.
2. `RacePodium` — replaces solo WINNER card on completed race detail (`race_detail_screen.dart:5823`) and inside `race_results_summary_screen.dart`.
3. Participant chip row (legend/name-tag Wrap between race art and STANDINGS) — removed. Exact widget still [OPEN]: `goal_track.dart:212 _buildLegend` vs `home_course_track.dart:1337 _RunnerNameTag`.
4. `PillButton` spinners — added to stash USE rows, sheet USE/tier, DISCARD, OPEN ALL, pocket-watch confirm.
5. "SOLO"→"CLASSIC" + per-mode description line — `create_race_screen.dart`, also rendered by demo prologue (`demo_race_host.dart:372, demoMode:true`).
6. Mission line — added under "STEP. RACE. WIN." (`start_screen.dart:258`).
7. Settings: milestone toggle (NOTIFICATIONS), SEND FEEDBACK (HELP & LEGAL), new COMMUNITY section; Admin: VERSIONS + RACES sections + suggestions list.
8. What's New bottom sheet — new, after home load in `main_shell.dart`.
9. REROLL·WATCH AD button — new, on `CaseOpeningScreen` post-reveal (flagged; hidden in demo).
10. Stealth rank shields "?" — solo planks + team column cells.
11. Multiplier chip — added to team live scoreboard cells (`_teamColumnCell`, `race_detail_screen.dart:6939`).
12. Privacy copy — onboarding health gate (`onboarding_flow.dart:149`) + settings `_ConnectHealthRow` (`settings_screen.dart:551`).

*Checklist*

**A. Real race detail — active solo race** (Get there: open any active solo race from Races tab; need ≥1 held powerup + 1 unopened box + stash item; staging)
1. Powerup sheet → DISCARD shows confirm dialog with rarity price; confirm → toast shows coins awarded, coin badge bumps. Box discard shows the "no coins for unopened boxes" wording.
2. Pocket-watch sheet discard path shows the same confirm dialog.
3. Spinners: tap stash USE → in-sheet spinner, sheet stays open; sheet USE/tier → spinner on the underlying screen's button; DISCARD, OPEN ALL ("OPENING…"), pocket-watch confirm — each shows a spinner, width doesn't jump, only the tapped button spins.
4. Chip row: the @name/dot row between race art and STANDINGS is gone; on-track avatars/name display otherwise intact; row not relocated elsewhere on the screen.
5. Tap outside powerup sheet dismisses it (item 15 verify).

**B. Real race detail — completed solo race** (Get there: open a COMPLETED race with ≥3 finishers; also one with exactly 2)
6. Podium (2nd-left / 1st-raised / 3rd-right) with avatars, name+steps+payout; the old single WINNER card is NOT also rendered. 2-finisher race → two platforms only.
7. Rank shields show 1/2/3 numbers (stealth unmasked after finish — no "?" anywhere on a completed race).
8. Chip row also absent on the completed layout.

**C. Real race detail — team race** (Get there: live team race where someone has an active multiplier and someone has Stealth active — seed on staging with 2 accounts)
9. Multiplier chip appears in the two-column team cells next to the name; stealthed/no-multiplier rows show no chip; solo races unchanged.
10. Stealthed team cells show "?" on the shield; visible cells show real ranks — no more 1-2-1-2. Solo standings same check (2 stealthed pinned top with "?", visible rows 1/2/3, viewer pin correct).
11. Completed team race still shows the team winner board, NOT the podium.

**D. Race results popup** (Get there: finish a race, then cold-launch → popup fires from `main_shell.dart:1488`; or seed an unseen completed race on staging)
12. Podium renders inside the popup for a solo race; team race popup unchanged; dismiss works.

**E. Demo race tutorial** (Get there: fresh account → onboarding → demo race)
13. Create beat: format card reads CLASSIC (not SOLO) and the per-mode description line renders without breaking the coach layout/spotlight on `tutorialDurationKey`/`tutorialCreateKey`.
14. Race-detail beats: chip row absent here too; **spotlights still ring correctly** — powerup tray (`tutorialPowerupsKey`, `race_detail_screen.dart:5096`) and clock chip (`tutorialClockKey`, `:3105`) sit near the removed row; layout shift must not mis-aim the ring.
15. Powerup sheet in demo: NO discard button (unchanged), and no confirm dialog reachable; USE taps still complete instantly with no stuck spinner (DemoRaceApiService resolves synchronously).
16. Demo box open: NO reroll button on `CaseOpeningScreen` (`demoMode:true`) — and no ad/network activity.
17. Final beat: `_WinCard` overlay renders as before (hand-forked — podium change must not propagate here), AND the completed race detail behind/after it: `demo_race_engine.dart:473` flips status to COMPLETED with a `winner` payload, so the real screen will try to render the podium from demo fixtures — verify it renders sensibly (not empty/one-legged/crashed).
18. What's New does NOT appear during or immediately after the onboarding/demo session (fresh install sees it on session two — verify by force-quitting and relaunching once onboarded).

**F. Tab tutorial previews** (Get there: Profile → admin → re-run tutorial)
19. Race-detail preview beat (`tutorial_real_screens.dart:138`, data `tutorial_preview_data.dart:486`): chip row absent; `raceDetail.powerups` spotlight still rings the tray; screen renders (no missing-field blowup from the removal or spinner refactor).
20. Races/Home preview beats render unchanged (spot-glance — no What's New sheet, no new dialogs leaking over the tutorial).

**G. Create race — real** (Get there: Races tab → +)
21. CLASSIC label on the format card, description line updates when switching Classic/Teams/Bracket; "SOLO" appears nowhere; layout below the card (duration etc.) not pushed off-screen on a small device.

**H. Start screen** (Get there: sign out, or fresh install)
22. Mission line sits under "STEP. RACE. WIN.", smaller; tagline itself unchanged; sign-in dock not displaced. Check after 21:00 or with dark forced (StartScreen pins a light palette — confirm still legible).

**I. Settings + Admin** (Get there: Profile → Settings; then Profile → admin)
23. NOTIFICATIONS: milestone-reminder toggle present under the daily-reward toggle (staging backend); against a backend without the field the toggle is hidden, section otherwise intact.
24. HELP & LEGAL: SEND FEEDBACK row above SUPPORT; opens the sheet; sheet dismisses clean.
25. COMMUNITY section between HELP & LEGAL and ACCOUNT: Instagram and X rows (TikTok deferred) with tinted glyphs. **Repeat in dark mode** (force in settings — ink flip trap): glyphs and row text legible.
26. Privacy copy under `_ConnectHealthRow` renders, row still tappable.
27. Admin screen: VERSIONS and RACES sections in `AdminStatsCard`; suggestions list below; against old backend the sections hide rather than render empty.

**J. Onboarding health gate** (Get there: fresh account, onboarding v3)
28. Expanded privacy copy on the connect-health page; CTA button not pushed below the fold on a small screen (iPhone SE-class).

**K. What's New** (Get there: install build over an existing signed-in install)
29. Sheet appears once on first launch after update; relaunch → does not reappear; sign out/in → does not reappear.
30. Session where a race-results popup fires: What's New does NOT stack on top (deferred to next launch).

**L. Box reroll — real** (Get there: staging with `ADS_BOX_REROLL_ENABLED` on, active race, open a box)
31. REROLL·WATCH AD button appears only after reveal; gone after one reroll; absent entirely when flag off.
32. NOT present on `MultiCaseOpeningScreen` (OPEN ALL flow) and NOT on the daily-reward spinner reel (`daily_reward_screen.dart:634` is a hand-forked copy of the case chrome — must not inherit the button).

*Surfaces confirmed unaffected:*
- Tab tutorial hand-copied `WoodenTabBar` — no tab reorder/rename in this batch.
- `races_tab.dart` `_buildEffectPlates`/`_buildInventoryRow` forks — discard/spinner changes live in the race-detail sheets and `PillButton`; verified no badge/inventory placement change (glance during checkpoint 20 anyway).
- Demo prologue invite screen (`race_invite_screen.dart`) — no items touch it.
- Team races in demo/tutorial fixtures — none exist (`tutorial_preview_data.dart` races are solo), so items 10/11 have no mirror there.
- `GoalTrack` is imported only by `race_detail_screen.dart` — legend removal cannot leak to other screens. `HomeCourseTrack` name tags are another story — see risks.
- Ranked results (`ranked_results_summary_screen.dart`) — sibling of the race results popup, podium not added there; confirm it still renders its own layout (glance if a ranked week settles).

*Risks found while planning (BINDING spec steps for implementation):*
1. **Demo completed-race podium**: `demo_race_engine.dart:473–499` serves `status:'COMPLETED'` + `winner` through the real `RaceDetailScreen`. The new podium will render from demo fixtures — implementation must add the fixture fields the podium reads (or gate podium off `demoMode`); checkpoint 17 is the catch.
2. **Spotlight keys near the removed chip row**: `tutorialClockKey` (`race_detail_screen.dart:3105`) and `tutorialPowerupsKey` (`:5096`) anchor by GlobalKey — deleting the chip row shifts layout with no compile error. Checkpoints 14/19.
3. **Item 16 widget identity**: if the removed element is `_RunnerNameTag` in `home_course_track.dart` rather than the `goal_track.dart` legend, the blast radius grows — `HomeCourseTrack` is embedded by `race_detail_screen.dart:3048` and imported by `ranked_tab.dart`/`leaderboard_tab.dart`/`start_screen.dart`. Pin the widget by screenshot-reproducing first; if it's the name tag, add ranked tab + leaderboard + start screen checkpoints.
4. **Daily-reward reel is a hand-forked `CaseOpeningScreen` copy** — reroll must be added only to the real screen; any shared refactor must not surface the button on the reel. Checkpoint 32.
5. **`DemoRaceApiService` must not advertise `boxReroll`** in its progress payload; same for `tutorial_preview_data.dart` powerup payloads.
6. **Synchronous demo services vs spinners**: per-action busy tracking (`_actingPowerupId`) must clear on the demo's instant responses or demo buttons freeze mid-tutorial (checkpoint 15).
7. **What's New sign-out exclusion**: `lastSeenWhatsNewVersion` must be excluded from `clearPersistedState()` or the sheet re-shows after every sign-out (checkpoint 29).
8. **COMMUNITY glyph tinting** must go through theme ink tokens — the 07-23 dark-mode flip trap (checkpoint 25).

## Revision log

- v1 (draft): initial 20-item consolidation from screenshots + Rohan's
  answers + 3 exploration reports + game-analyst verdict.
- Gap pass 1: added idempotency note on discard double-tap; auto-start
  "never fail the join" guard + invite-expiry backstop; milestone reminder
  bias-to-silence tz note; reroll bound at consume-time not grant-time;
  What's New modal-stacking rule + sign-out-wipe exclusion; brand-logo
  policy for social icons; stealth fix keeps backend masking (old-client
  behavior unchanged); explicit "leave analytics `solo` value" note.
- Phase 3 interview (2026-08-08): discard = 2/5/10 + 40/day cap, in-race
  only; team payouts = winner-only buff to 600 (analyst gates/split/throttle
  DECLINED — risk logged); podium = both surfaces; suggestion box =
  server-side form; mission line added under tagline; What's New = second
  session for fresh installs; socials = Instagram/TikTok/X (URLs pending).
- Architect review (2026-08-08, verdict REVISE — all 19 REQUIRED folded):
  discard CAS was fictional → conditional updateMany + ledger unique index;
  cap = partial award, pure-SQL day boundary, new ledger index, non-atomicity
  accepted; discardPrices as optional balance-config key, no SCHEMA_VERSION
  bump; auto-start hook moved out of the join advisory lock into callers,
  no bypassCreatorCheck (creatorId passed as the cron does), expired invites
  count as resolved, new model query for the unscheduled backstop,
  tournamentId excluded, >10-participant races defer to cron; milestone job
  gets its own user query (pref + device tokens), date-type cast, ±1-day
  claim suppression rule; team multiplier threaded through the shared pool
  formula and stamped at creation (teamPoolMultBps), guarded float env;
  tie behavior escalated to a blocking approval-gate decision; Suggestion
  cascade + deleteUserAccount inclusion + PII stance; lastSeenAt write
  bounded to daily + dedicated model method that skips /auth/me cache
  invalidation; version buckets get unknown bucket + since date; reroll grant
  gets its own customData prefix/kind (cross-consumption bug), kill switch
  defaults OFF read at call time, configVersion restamped,
  upgradeLevel>0 rejected, no invalidateRaceProgress, iOS-only reality
  amended into scope; Detour Sign all-null placement case specified;
  What's New allKeys structural test; podium ordered after Item 18;
  frozen-client contract tests + no-Redis suite run added.
- Gap pass 2: MYSTERY_BOX discard still allowed but pays 0 (was ambiguous);
  cap message in confirm dialog at 0 remaining; team payout throttle
  redistribution question flagged for architect; reroll requires
  `rarity != null` so stash-redeemed powerups can't reroll; podium
  fewer-than-3 finishers; demo/tutorial fixture-key risk called out for
  podium + chips removal; startup perf explicitly excludes `_persistSteps`
  reordering.
