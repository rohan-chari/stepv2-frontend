# Feature Batch — 2026-08-17

**Status:** Implementation is in progress. The round-to-5 payout item completed
independent economy and architecture review on 2026-08-18. The owner explicitly
accepted the disclosed subsidy/inflation risk, confirmed that new player-funded
buy-in races no longer exist, selected default-on creation stamping, and required
the full double-payout offer for every eligible rounded payout. This batch spans
the Flutter app, the separate backend repository, native ad-mediation dependencies,
and external AdMob/network-console setup.

## 1. Summary and user stories

1. As a Home user, I see the Home CTA as **DAILY REWARD**, with a restrained
   attention pulse while a free reward or an earned extra spin is available.
2. As a user eligible for an extra daily spin, I am never left on a permanent
   “LOADING AD…” button; I get an actionable retry/fallback state.
3. As a race participant, I can see precisely why my score changed from a
   completed timed effect, both in Activity and once in a race-detail reveal.
4. As a participant in the global 2× event, I see the total *extra race steps*
   I earned after it finishes, once on my first subsequent Home refresh.
5. As a satisfied, engaged user, I may receive the native store review prompt
   at a respectful, configurable moment—not repeatedly or during frustration.
6. As an ad-supported user, I can move directly from the daily-box result to a
   clear “watch an ad for one more spin” offer, rather than dismissing and
   reopening the reward sheet.
7. As the operator, I can add selected third-party demand through **AdMob
   Mediation** without changing reward entitlement logic or exposing accounts.
8. As a completed-race viewer, I always see the final standings rather than an
   empty board below the heading.
9. As a private-race creator/invitee, a race reliably starts once every live
   invite is resolved and at least two participants have accepted.
10. As an accepted participant in a manual pending race, I see a clean lobby
    rather than a redundant “Waiting for the creator” status card.
11. As a referred player, I understand that a qualifying race needs another
    player and that Daily and Weekly challenges are excluded.
12. As a Profile user, I can see my accumulated first-, second-, and
    third-place finishes without a punitive loss counter.
13. As a user, I have one private Inbox for recent app alerts and a replyable
    support conversation about feedback I submitted—never player-to-player
    direct messages.
14. As an operator, I can turn on a text-only service-status banner at the top
    of Home during a degradation and turn it off when service recovers.
15. As a participant in the daily 2× event, I receive its start notification
    within roughly one minute of the selected start time, rather than up to five.
16. As a race winner, every final coin payout I see ends in 0 or 5, including
    an ad-earned payout double, and the displayed total always equals what the
    winners actually receive.

## 2. Scope and non-goals

### In scope

- Rename the Home reward CTA from `CLAIM` / `EXTRA SPIN` to `DAILY REWARD`.
- A small, accessibility-respecting CTA jitter/pulse and equivalent attention
  treatment for the rewarded-ad CTA/copy.
- Repair rewarded-ad load-state recovery for daily extra spin.
- Completed timed-effect attribution in race Activity and a once-only
  race-detail modal, using the existing `PowerupRevealModal` visual language
  and the appropriate existing `PowerupIcon`.
- A once-only post-event Home modal for a completed global 2× event.
- Server-enforced ownership/participant checks and integration tests proving a
  user cannot read, acknowledge, or infer another user’s impact data.
- A controlled native-app review eligibility/attempt ledger and native prompt.
- Daily-reward reveal CTA for the available/pending extra spin.
- A selected set of AdMob Mediation adapters on **both iOS and Android**, with
  release checks and console configuration steps.
- Restore the final-standings participant board for every completed race.
- Verify and regression-lock private-race auto-start in its supported states;
  diagnose any production configuration/worker issue before changing policy.
- Simplify manual pending-race chrome: use `PENDING` in the unscheduled hero
  status chip and remove the non-creator waiting card at the bottom.
- Make the existing referral qualification copy explicit on every user-facing
  referral surface.
- Add a Profile podium-record summary for eligible non-forfeited finishes.
- Add a private Inbox containing alert history and per-feedback user/support
  threads, including the matching admin reply tooling.
- Add an admin-configured, text-only Home service-status banner.
- Tighten the daily 2× event scheduler cadence from five minutes to one minute.
- Round every newly created race/tournament payout up to a 5-coin increment,
  with a 5-coin minimum for a positive recipient payout; transparently show the
  resulting total even when it exceeds the underlying pot/formula.

### Explicit non-goals

- Changing powerup odds, prices, durations, multipliers, transfer ratios, or
  global-event frequency/duration. Attribution explains the existing settled
  scoring result; it must not be a second scorer.
- Trusting a client-supplied step count, effect amount, user ID, reward, or ad
  completion signal.
- Replacing AdMob, changing its server-side verification (SSV), or rewarding
  users from a mediation callback. All rewarded placements continue to use the
  existing AdMob load/show + server-verified claim contract.
- Forcing users to leave a rating, presenting a custom star-rating screen, or
  guaranteeing that iOS/Android displays the native review dialog.
- Showing live/interim effect totals as final. A notice is issued only once the
  relevant effect/event window is complete and its amount is settled.
- Player-to-player DMs, group conversations, attachments, links, read
  receipts, user search, and notification-preference redesign. Inbox v1 is
  deliberately system alerts plus staff-only feedback replies.
- Daily login/box rewards, referrals, refunds, buy-in holds, shop purchases,
  powerup rewards, and any non-race coin source are not payout-rounded.
- Repricing or modifying any race already PENDING, ACTIVE, or COMPLETED at the
  time this payout rule rolls out. Those competitions retain their stamped
  historical settlement behavior.

## 3. Current evidence

- Home renders `StreakChip`, which owns the `CLAIM`/`EXTRA SPIN` label and opens
  `DailyRewardScreen`: `lib/widgets/streak_chip.dart:203-246`,
  `lib/screens/tabs/home_tab.dart`.
- `DailyRewardScreen` begins preloading immediately, but represents a failed or
  timed-out load as a disabled `LOADING AD...` button. `AdService.load` has a
  30-second timeout, while `_maybePrepareExtraSpin` has no retryable terminal
  state: `lib/screens/daily_reward_screen.dart:144-185,650-680`,
  `lib/services/ad_service.dart:383-439`.
- The current extra-spin claim already performs bounded SSV-lag retry against
  `POST /daily-reward/claim-extra-box`; that security model is retained.
- `RacePowerupEvent` already backs Activity and `getRaceFeed` performs a real
  participant/tournament-spectator authorization check. It currently returns
  action/expiry messages, not settled numeric impact:
  `src/modules/races/queries/getRaceFeed.js:8-31,54-109` (backend).
- The global scheduler creates one deterministic, 30-minute 2× event and emits
  `GLOBAL_EVENT_STARTED`; the frontend already routes its notification to Home.
  Current start jitter follows its five-minute schedule:
  `src/modules/steps/jobs/globalStepEventScheduler.js:9-67`,
  `src/modules/steps/globalStepEvent.js:36-66` (backend),
  `lib/services/notification_service.dart:502-505`.
- The app already has `in_app_review`, and existing native mediation adapters
  for Meta and AppLovin on iOS. The Android counterpart/adapters must be
  audited rather than assumed: `pubspec.yaml`, `ios/Podfile`.
- **Final standings diagnosis:** completed races currently skip `_loadProgress`
  in `RaceDetailScreen._loadDetails` (`lib/screens/race_detail_screen.dart:976-
  1006`), while `_buildCompletedContent` rejects the paged details roster as a
  safety fallback (`:7313-7323`). Consequently `participants` is empty and the
  heading/card render with no rows. This matches the screenshot.
- **Auto-start verification:** this is already implemented for eligible private
  races. The post-accept/share/public-join hooks call the shared predicate;
  `privateRaceAutoStart.js:66-106` requires PENDING, all live invites resolved,
  at least two ACCEPTED racers, no future schedule, and team balance where
  relevant. It has an unscheduled five-minute backstop (`:173-201`) and a real
  HTTP integration suite at
  `stepv2-backend/test/integration/batch-0808-private-race-autostart.test.js`.
- **Referral:** the current qualification gate already excludes seeded
  Daily/Weekly races and requires two real finishers; the remaining work is
  explicit client/web/push copy. `docs/feature-batch-2026-08-09-requirements.md`
  documents the deployed rule and its integration coverage.
- **Ad pods:** the Flutter extra-spin flow makes one `RewardedAd.show()` call.
  Two consecutive rewarded videos are an AdMob rewarded **ad pod**, enabled by
  the ad unit's Ad-pods ad type. Disable that ad type in the AdMob console; do
  not remove either in-app banner and do not add a second client-side guard.
- **Profile:** the existing `GET /steps/stats?view=profile-v1` is own-user
  step-only statistics. It has no placement record, so podium totals require
  an additive server-owned read.
- **Inbox:** visible pushes are persisted in `Notification`, but retained only
  seven days and have no client list API. Feedback is one-way `Suggestion`
  storage with an admin list endpoint. Neither is a conversation model today.
- **Service banner:** authenticated responses already carry a defensively-read
  `featureFlags` envelope sourced from the admin settings store; it is the
  correct live-config path, but the current admin PATCH accepts booleans only
  and needs an explicitly validated message value.

## 4. Product behavior

### 4.1 Daily Reward attention treatment

- Home button label is always **DAILY REWARD**. Its icon/state—not a label
  change—communicates a free box versus an earned extra spin.
- When a free box is available, the label uses a very small horizontal jitter
  (maximum 1 logical pixel, short 2–3 beat sequence, then long idle interval)
  plus a subtle coin-color pulse. When an ad extra-spin is available/pending,
  the same treatment is applied to its dedicated message/CTA.
- Respect `MediaQuery.disableAnimations` and reduced-motion platform settings:
  static high-contrast emphasis, no perpetual animation. Never jitter an
  already-disabled/loading/error button.
- Draft copy:
  - Free: `DAILY REWARD` / `TODAY'S BOX IS READY`.
  - Ready ad: `WATCH A SHORT AD · +1 SPIN` / `ONE MORE SPIN IS READY`.
  - Pending SSV grant: `CLAIM YOUR EXTRA SPIN`.
  - Ad unavailable: `AD NOT READY — TRY AGAIN`.

### 4.2 Extra-spin recovery and reveal shortcut

- Loading is tri-state: `loading`, `ready`, `unavailable`. A failed/expired
  load resolves to **AD NOT READY — TRY AGAIN**, which actively starts a fresh
  load. It may not remain disabled as `LOADING AD...` beyond the load timeout.
- The screen must also recover if the advertised `adExtraSpin` payload is
  absent, false, used, unsupported, or rejected by SSV. Pending verified grants
  remain claimable without another ad.
- Once the free-box reel settles, its result reveal includes the optional
  extra-spin CTA in the same overlay when (and only when) the server-provided
  offer is available and this platform has a supported controller. The existing
  result remains visible. Selecting the CTA enters the same guarded ad/SSV
  flow; dismissing it leaves the reward intact and does not consume the offer.
- Extra-spin uses the existing one-per-local-day backend rule. This batch adds
  no client-side reward authority.

### 4.3 Settled timed-effect activity and race modal

- A **settled impact** is an immutable, server-calculated component of a
  participant's **final frozen race score**—not a total calculated when an
  effect expires. It is written only after finish, forfeit, or race settlement,
  when late HealthKit/Health Connect samples can no longer change that score.
  Zero components create no player notice.
- **V1 covers every existing lingering effect that changes the affected
  participant’s settled race score**: LEG_CRAMP, QUICKSAND, RUNNERS_HIGH,
  WRONG_TURN, CAMPFIRE_REST, RAINSTORM, LEECH (victim and beneficiary),
  UPRISING, RALLY_FLAG, COIN_FLIP, GHOST_PEPPER, signed HITCHHIKE caster impact,
  Umbrella when it avoids an actual score loss, and failed Drill Sergeant.
  Inventory/control-only effects (Power Outage, Fanny Pack, Stealth, shields)
  and survived/void Drill Sergeant are excluded.
- The canonical race-resolution artifact emits one versioned **additive
  attribution vector** using the same samples, instant bonuses, score floor,
  cancellation, Leech/Hitchhike ordering and clamps. Effects are exactly
  `score(covered effects,no event) − score(no covered effects,no event)`;
  global is exactly `score(covered effects,event) − score(covered effects,no
  event)`, so both vectors sum exactly to final score minus unmodified score.
  Failed Drill Sergeant also
  removes its written `bonusSteps` decrement. Deterministic remainder allocation
  and `attributionVersion` are persisted. Independent per-effect
  “what if this one were absent?” calculations are prohibited because stacked
  effects would double-count.
- Activity gets one readable, **recipient-private** line per affected
  participant, e.g.
  `You gained 426 steps from Runner’s High.` / `You lost 180 steps to a Leech.`
  It is synthesized from the caller’s impact ledger while fetching their own
  Activity view—not stored as a shared numeric `RacePowerupEvent`. Actor names
  obey existing Stealth redaction. A user sees only their own numeric impact;
  other racers’ Activity lines do not disclose that amount.
- On the first eligible race-detail open after settlement, the affected user
  sees the existing powerup reveal shell: source icon, `RUNNER'S HIGH` (or
  effect title), signed step delta, race name, and `Continue`. Dismissing marks
  only that user’s notice consumed. Multiple notices are sequenced one at a
  time in settled order; cap a single opening at three and leave the remainder
  for later opens.
- An effect can have only one settled impact notice per user/race/effect. The
  arithmetic comes from the existing canonical final-settlement artifact—not
  separate display math or the device clock.

### 4.4 Completed global-event Home summary

- A 2× summary becomes eligible only once every event-overlapping race for that
  user has a frozen final score. Its per-race contribution is the canonical
  counterfactual `score(with event) − score(with that event removed)`, including
  downstream Leech/Hitchhike consequences—not the raw global-boost field.
- On the next Home refresh, show one summary when any race contribution is
  nonzero: positive aggregate
  `2× STEPS COMPLETE — You earned +X extra race steps across N races`; negative
  `2× STEPS COMPLETE — The event changed your race score by −X across N races`;
  mixed net-zero copy is `Gains and losses balanced across N races; net 0`.
- “Across races” is the sum of the race-score increments, not distinct walking
  steps. Thus the same physical steps can legitimately contribute an increment
  in each eligible race. The modal must say **extra race steps** to prevent a
  misleading health-total implication.
  It is based on the event’s exact `[startsAt, endsAt)` window. A Home refresh
  after a missed notification still receives it; a notification is not required
  for eligibility.
- One user/event ledger row controls delivery. It is not marked shown until the
  modal is dismissed. A failed/old backend response simply omits the optional
  summary and leaves Home unchanged.

### 4.5 Store-review prompt

- Replace the generic engagement threshold with a clearly positive moment:
  after the user **finishes first place** in a completed race, show the native
  review request only when the backend says they remain eligible. It appears
  after the victory/result interaction is complete, never over a prize/extra-
  spin/ad flow.
- First place is the sole v1 eligibility trigger. The backend records attempts
  and suppresses another request for 180 days; native iOS/Android may decline
  to display the system dialog, and the app must not infer that a review was
  written.

### 4.6 Final standings repair

- A completed race must load or retain a complete authoritative participant
  list before rendering the final board. The fix must not re-enable a truncated
  paged details fallback—doing so could silently lie about final placement.
- Commit to the existing `GET /races/:id/progress?view=participants-v1` request
  once in `_loadDetails`: its backend contract returns a full, ordered completed
  roster with placement fields even when active-race paging is enabled. Use it
  in `_buildCompletedContent`; against an older backend that omits this
  guarantee, show a retryable board error/loading state, never a truncated or
  empty final board.

### 4.7 Private-race auto-start verification

- The existing feature is correct only for private races (or quick-created
  races with the explicit `ON_MINIMUM_PARTICIPANTS` policy): PENDING; two or
  more accepted racers; no live outstanding invite; no future scheduled start;
  not seeded/tournament-managed; and balanced teams when applicable.
- Before changing code, verify in staging that both an invite acceptance and a
  share-link join transition the race to ACTIVE immediately; verify the
  five-minute backstop catches an expired final invite. Confirm production does
  not set `RACE_POLICY_AUTOSTART_DISABLED=true` or
  `PRIVATE_RACE_AUTOSTART_DISABLED=true`.

### 4.8 AdMob Mediation expansion

- Keep Google Mobile Ads as the Flutter surface. Add only networks that support
  the required formats on **both** platforms: rewarded (daily extra spin,
  reroll, payout double), banner/box banner, and native when configured.
- Add **ironSource Ads** and **Mintegral** first, behind AdMob
  bidding/mediation configuration; keep existing AppLovin and Meta. This is the
  final rollout workstream because it requires owner-managed network accounts,
  placement IDs, app-ads.txt review, consent-partner additions, and adapter
  versions verified against the shipping Google Mobile Ads SDK. Do not ship an
  adapter with no active console source.
- App code retains one ad request per existing placement. SSV custom data and
  backend claims remain unchanged, so a mediated creative cannot mint the wrong
  entitlement.

### 4.9 Pending-race presentation cleanup

- In `RaceDetailScreen._buildPendingContent`
  (`lib/screens/race_detail_screen.dart:4367-4390`), rename the unscheduled
  hero chip from `AT THE START LINE` to `PENDING`. A future scheduled race
  retains its `STARTS IN` countdown: it is more specific and must not be
  overwritten by the generic label.
- In `_buildPendingActions` (`:4830-4865`), remove the accepted non-creator
  `Waiting for the creator to start the race` card entirely. This must not
  remove creator controls, invite decision controls, schedule/uneven-team
  notices, or the quick-race `WAITING FOR ANOTHER WALKER` share CTA—they convey
  distinct actionable states.

### 4.10 Referral qualification copy

- Every referral surface uses this approved wording, with normal responsive
  line wrapping but no change of meaning: **“Finish any race with at least one
  other player to earn your referral reward. Daily and Weekly challenges don’t
  count.”**
- Apply it to the referral screen/rules, referral share copy, referred-user
  welcome, Get Coins surface, and the corresponding web/push copy. The server
  qualification rule, rewards, limits, and referral economics do not change.

### 4.11 Profile podium record

- Profile adds a compact **RACE PODIUMS** section using the existing podium
  visual language: first, second, and third counts with their small podium
  icons. It is a positive record, not a win/loss display. Place it directly
  **below STATS** (and therefore below STEP CALENDAR), as a separate profile
  card; tutorial Profile uses this same order when a fixture renders it.
- Count a participant only when `race.status = COMPLETED`, their `forfeitedAt`
  is null, and their stored placement is 1, 2, or 3. Team races use their final
  team placement, so every non-forfeiting member of the team named by
  `race.winnerTeam` contributes one first-place finish. A team race with
  `winnerTeam IS NULL` is a tie and contributes no podium finish, even though
  legacy settlement may have persisted placement 1 on its participants. Seeded
  challenges and tournaments remain included
  unless the existing placement policy omits a placement; this is a historical
  record, not a new eligibility/reward gate.

### 4.12 Inbox: alerts and staff feedback replies

- Inbox v1 is a single top-level screen reached from a Home unread badge. The
  badge is the single mail icon in the currently unused upper-right Home Hero
  HUD position, clear of system chrome; it is suppressed in tutorial preview.
  It
  has **ALERTS** and **SUPPORT** tabs. It contains no player discovery, player
  profile messaging, or player-to-player conversation capability.
- Alerts are a recipient-private history of app-visible notifications with the
  same tap destination as the original push. Retain 30 days, newest first;
  opening an alert marks only that recipient's row read. A push failure does
  not prevent the alert from appearing in Inbox.
- Each feedback submission starts (or appends to) a private support thread.
  Users can send a follow-up and staff can reply from the existing admin
  feedback area. Staff appears as **BARA SUPPORT**; never expose an
  administrator's private profile or contact details. Text only, 2,000
  characters per message, no links/attachments, pagination, rate limits, and
  server-side abuse logging.
- A support reply creates an Inbox alert and normal push when permitted. A
  user reply creates an admin-side unread state but never a player-facing push.
  Users can only list/read/write their own threads; admins require the existing
  admin authorization and may access only through the staff tooling.
- Alerts expire after 30 days. Support threads, including all messages, expire
  30 days after their most recent user or staff message; a new permitted reply
  before expiry resets that inactivity clock. Expiry is a backend job with an
  idempotent, audited deletion path. Account deletion removes any remaining
  thread immediately through the existing account-deletion path.

### 4.13 Home service-status banner

- Add a slim, persistent, text-only banner directly below Home's existing top
  chrome and above its scroll content. It is not dismissible: when enabled it
  stays visible on every Home refresh until the operator disables it.
- Admin Settings exposes an enabled toggle and a required 1–240-character
  message. Empty/whitespace-only messages are rejected. Text is rendered as
  plain text (no markdown, URL action, or rich content); long copy wraps and
  remains accessible at large text sizes.
- The Home payload is additive: missing, malformed, disabled, or empty banner
  data renders nothing. A cached prior enabled message must not outlive a newer
  disabled response after the normal auth/config refresh.

### 4.14 Timely daily 2× event start

- The global 2× scheduler runs once per minute instead of once per five
  minutes. The deterministic daily ET-selected start time, once-daily limit,
  30-minute event duration, multiplier, scoring, and participant fan-out stay
  unchanged.
- Reduce the late-start catch window to two minutes. A scheduler restart or
  outage longer than that skips the stale event for the day rather than starting
  a “30-minute” event noticeably late and sending a misleading delayed push.
  Normal timer/runtime drift may still make a notification arrive up to roughly
  one minute after the selected start.
- Normal non-start ticks perform only the existing lightweight “events in the
  last 24h” lookup. The active-racer query and notification fan-out still run
  once only when an event is actually created; no race scoring or step scans
  are added to the one-minute tick.

### 4.15 Round race payouts up to 0 or 5

- **Rule:** apply this only to a positive, final, per-recipient race payout:
  `roundUpToFive(amount) = max(5, ceil(amount / 5) × 5)`. Zero remains zero.
  It is applied exactly once, after the existing canonical payout split has
  selected the recipient and computed their whole-coin amount.
- **Included payout sources:** every currently creatable app-funded individual
  and team-race prize, seeded Daily/Weekly finish reward, app-funded tournament
  champion prize, and featured tournament champion prize. Player-funded buy-in
  races are no longer creatable and all historical/in-flight buy-in rows remain
  version 0 forever. The rule does not change refunds, holds, referral rewards,
  daily-login rewards, mystery boxes, or any other non-race reward.
- **Minted rounding difference:** a per-recipient round-up can exceed the
  original pot or pool (for example `7 / 2 / 1` becomes `10 / 5 / 5`). Bara
  deliberately mints that difference; it may never reduce another winner's
  payout, redistribute an already-rounded tier, or debit a participant.
- **Subsidy observability:** the canonical payout plan records the unrounded
  award, rounded award, and `roundingSubsidyCoins` per recipient and in the
  settlement aggregate. This is accounting metadata on the existing payout
  credit, not a second credit. Emit aggregate metrics for subsidy coins,
  recipient count, small-award frequency, repeated provider identity, and
  race-creation concentration. The owner has explicitly accepted default-on,
  uncapped v1 subsidy after review; the operational kill switch stops stamping
  new v1 rows but never changes an existing row's promised settlement.
- **Displayed total:** all new-race projections, payout tiers, result cards,
  completed history, and tournament prize presentation show the sum of the
  rounded recipient awards, not the underlying pre-rounding formula/pot. Thus
  the displayed total always equals the visible tiers and ledger credits. The
  historical buy-in accounting amount remains internal to its version-0 row.
- **Rewarded double:** every otherwise eligible rounded payout receives the
  double-payout offer. A verified successful ad awards one full additional copy
  of the authoritative already-rounded base payout. It is never recomputed from
  an unrounded value, rounded a second time, suppressed by a coin ceiling, or
  partially clipped. A base `7 → 10` therefore offers and awards `+10`, for a
  total of `20`. Existing exactly-once offer/claim receipts, SSV verification,
  provider-identity velocity/anti-fraud controls, and exclusion of historical
  buy-in transfers/refunds remain in force; those controls may reject fraud or
  duplicate claims but may not turn an approved claim into a partial award.
  “Otherwise eligible” preserves the existing completed-race-results boundary;
  tournament champion prizes are rounded by this feature but do not gain a new
  tournament rewarded-ad flow.
- **Canonical payout plan:** one versioned backend planner accepts the immutable
  canonical raw split and returns the raw accounting inputs, final per-recipient
  awards, subsidy metadata, and final rounded award total. Every projection,
  settlement, serializer, participant payout field, and double-payout lookup
  consumes that plan. Never round a pool before splitting and never round an
  already-rounded award.
- **Team projection:** before the winning team and its eligible recipient count
  are known, no single projected rounded total is presented as authoritative.
  Team projections return/display the available per-team outcome arrays where
  supported; otherwise the existing single projected-total field is omitted.
  Completed results always expose the actual rounded award sum and
  `myPayoutCoins`.
- **Pre-submit creation preview:** Create/Edit Race and Tournament currently
  compute raw pool previews in Flutter before a server row exists. Because no
  authoritative versioned payout plan exists yet and Flutter must not reproduce
  settlement math, v1-capable creation flows omit that pre-submit payout/prize
  total without leaving a blank layout gap. They retain every input,
  explanatory label, and submit action. After creation, detail/result/history
  surfaces show only the server-owned rounded plan values. Legacy fixture flows
  may retain their explicitly version-0 preview.
- **Tournament presentation:** pending app-funded tournaments display the
  rounded full-bracket/champion projection from the versioned plan; active and
  completed app-funded tournaments display the rounded champion award; pending
  and completed featured tournaments derive presentation from the versioned
  `championPrizeCoinsSnapshot`. Internal committed/snapshot inputs remain
  unchanged and completed presentation equals the credited award.
- **Rollout/version safety:** add an immutable, creation-time race and
  tournament payout-rounding discriminator. Its migration default is legacy
  version 0, while the post-deploy creation policy defaults on and stamps
  version 1 for every currently creatable eligible race/tournament. Every existing
  PENDING, ACTIVE, and COMPLETED row keeps the old split and display forever;
  no backfill changes earned/presented coins. Old app binaries continue to read
  the additive payout fields they already use and simply render backend-owned
  rounded amounts.
- **Creation writers and kill switch:** `payoutRoundingV1Enabled` is a known
  server flag whose configured/default production value is `true`. User race
  creation, seeded renewal/bucket creation, user tournament creation, and
  featured-tournament lobby renewal read it only while creating a row. Turning
  it off stamps future rows version 0; it never changes an existing row.
- **Exactly-once recovery:** retain existing deterministic payout ledger
  reference IDs and reason namespaces. Settlement must durably reconcile the
  ledger credit, `RaceParticipant.payoutCoins`, subsidy metadata, and completed
  display total after a retry or crash between writes; `COMPLETED` alone is not
  a retry fence.
- **Rollback:** disable new version-1 stamping first. The deployed backend must
  retain v1 read/settlement support until every v1 race/tournament is terminal;
  never roll back to a pre-v1 binary while a v1 row can still settle.
- **No new client endpoint:** existing race/tournament and result payloads keep
  their shapes (`payouts`, `payoutTiers`, `prizePoolCoins`/`projectedPotCoins`,
  `myPayoutCoins`, and payout-double offer values), but their values reflect the
  stamped rounding version. Missing discriminator/fields are interpreted as
  legacy unrounded behavior by the backend.

## 5. Backend API contract and data

All additions are capability-gated and additive. Old clients continue to use
their current endpoints and ignore unknown response keys.

### 5.1 Impact ledgers (migration)

Add these server-owned Postgres tables. All FK deletes are `RESTRICT` until the
existing race/user retention job removes the parent; no cascade may erase a
final-score explanation.

`race_effect_impacts`

| field | notes |
|---|---|
| `id` | UUID |
| `raceId`, `userId`, `effectId` | foreign keys; `userId` is the affected user |
| `powerupType` | canonical type |
| `deltaSteps` | immutable signed integer |
| `attributionVersion` | non-null integer, default 1 |
| `settledAt` | server timestamp |
| `acknowledgedAt` | nullable; only the matching `userId` can set it |

Unique `(raceId, userId, effectId)` prevents duplicate jobs/retries. Leech may
produce one row for each affected user. No backfill of old effects is required;
new rows start from rollout. Index `(raceId,userId,acknowledgedAt,settledAt
DESC)` supports notices; `(userId,settledAt DESC)` supports the private feed.

`global_event_user_summaries`

| field | notes |
|---|---|
| `eventId`, `userId` | unique pair, foreign keys |
| `extraRaceSteps`, `raceCount`, `attributionVersion` | immutable non-null totals |
| `settledAt`, `acknowledgedAt` | server timestamps |

Only a row’s `userId` may read or acknowledge it. Affected-race IDs and other
users’ totals are never exposed. Unique `(eventId,userId)` plus
`(userId,acknowledgedAt,settledAt DESC)` index controls Home delivery.

`global_event_race_impacts`

| field | notes |
|---|---|
| `eventId`, `raceId`, `userId` | non-null foreign keys |
| `status`, `deltaSteps`, `attributionVersion`, `settledAt` | PENDING then FINAL signed contribution/version/time |

Unique `(eventId,raceId,userId)` prevents partial/replayed aggregation; indexes
`(eventId,userId,settledAt)` and `(userId,eventId)` let the summary worker prove
every overlapping race is final. Event overlap enrollment (including a join or
race start during the event) creates one PENDING row per accepted participant/
race; settlement writes its delta including 0 and marks it FINAL inside C0.
Absent rows are therefore not treated as finality. The summary worker reads only
this lifecycle table and aggregates only when every enrollment is FINAL.

`app_review_prompt_attempts`

| field | notes |
|---|---|
| `userId`, `raceId`, `opportunityId` | opaque, race-scoped winner opportunity |
| `expiresAt`, `claimedAt`, `attemptedAt` | server timestamps; nullable until claimed |
| `policyVersion` | permits a safe future policy change |

Unique `(userId,raceId)` prevents duplicates; `(userId,expiresAt,claimedAt)`
indexes lookup. Do not store `lastDismissedAt`: native review APIs cannot
reliably report whether their dialog was displayed or dismissed.

#### Payout-rounding stamp (migration)

Add non-null `payoutRoundingVersion Int @default(0)` to both `Race` and
`Tournament`. Version `0` means historical calculation; version `1` means the
round-up-to-five algorithm in §4.15. The migration is additive and defaults
every existing row to `0`; it performs no payout or display backfill. New
creation commands explicitly stamp `1` after the backend deploy because the
creation policy defaults enabled; the kill switch can stamp future rows `0`.
Optionally constrain both columns to `{0,1}`. Settlement and all read projections
select behavior from the row, never a live flag, so an in-flight competition
cannot change its promised economy.

The settlement artifact also persists the canonical unrounded award, rounded
award, and `roundingSubsidyCoins` in its existing durable payout/result metadata
for each recipient, plus the aggregate rounded-award total. This metadata never
causes a second coin ledger credit and is not client-authoritative.

`prizePoolCoins`/`potCoins` for a version-1 completed funded competition stamp
the **rounded award total** that the result UI displays. The original calculated
pool remains a transient internal input to the canonical split and is not
written as a contradictory public total. Historical player-funded buy-in rows
remain version 0 and keep their legacy accounting/presentation. All version-1
user-facing payout/pool fields report the sum of final awards without creating a
second client-only calculation.

### 5.2 Additive endpoints/fields

`inbox_alerts` is the Inbox's separate source of truth; it never reuses the
seven-day push-debug `notifications` table. Fields: `id`, `userId`, `type`,
allowlisted JSON `destination` (`route` plus existing opaque route params only),
`title`, `body`, `sourceKey`, `readAt`, `createdAt`, and `expiresAt`. Unique
`(userId, sourceKey)` makes repeated domain events/outbox attempts create one
alert. Index `(userId,readAt,createdAt DESC,id DESC)` supports unread/listing;
`(expiresAt)` supports expiry. The domain command writes alert plus an
`inbox_delivery_outbox` row in the same transaction; a single dispatcher claims
the outbox row and attempts push separately. Thus a failed/no-device push leaves
the Inbox alert intact. Existing `Notification` and its seven-day cleanup stay
unchanged.

`createInboxAlert` is the only alert-creation seam. Every app-visible alert
writer calls it **before** delivery—including race lifecycle, friend/social,
reward, reminder, and support-reply writers—so no-device/push failure still
creates an Inbox row. It accepts only a fixed type-to-destination allowlist:
race types map to `{route:"raceDetail",raceId}`, tournament types to
`{route:"tournamentDetail",tournamentId}`, and other supported types to the
existing Home/Friends/Daily Reward routes and opaque parameters. It derives a
deterministic domain-event/user/type `sourceKey`; unknown types are logged and
produce no Inbox row. Writes and delivery dispatch are gated by
`apiInboxV1Enabled` during rollout.

`inbox_delivery_outbox`: `id`, `alertId` FK, immutable `{title,body,destination}`
payload, unique `(alertId,kind)`, `status` (`PENDING|LEASED|DELIVERED|RETRY`),
`attemptCount`, `availableAt`, `leaseUntil`, `deliveredAt`, timestamps. Index
`(status,availableAt,leaseUntil)` supports PostgreSQL `SKIP LOCKED` claims.
`buildInboxDelivery`/`scheduleInboxDelivery` register in `startCrons()` only
under `NODE_APP_INSTANCE === "0"` with `INBOX_DELIVERY_DISABLED`. A claim
transaction leases one row; success marks DELIVERED and transient failure
increments/backoffs RETRY. Unique alert/kind plus durable state makes repeated
dispatch idempotent and prevents a duplicate support push.

`feedback_threads`: `id`, unique `suggestionId` FK, `userId` FK,
`lastMessageAt`, `expiresAt`, `userReadAt`, `staffReadAt`, timestamps; indexes
`(userId,expiresAt,lastMessageAt DESC,id DESC)` and `(expiresAt)`. `feedback_messages`:
`id`, `threadId` FK, `senderKind` (`USER|STAFF`), `text`, `idempotencyKey`, and
`createdAt`; unique `(threadId,idempotencyKey)` and index
`(threadId,createdAt,id)`. Every new Suggestion creates one thread and its
initial USER message in the same transaction; it never appends to a different
feedback item. Every permitted new message updates `lastMessageAt`/`expiresAt`
to now/+30d and the counterpart unread marker. `Suggestion → thread → messages`
is cascade-delete; `User → suggestions/threads/inbox_alerts/outbox` is deleted
in the existing account-delete transaction (with dependent message/outbox
cascades), so no FK can leave an account undeletable.

`GET /races/:raceId/impact-notices` — only with `impact_notices` capability and
default-off `apiImpactNoticesEnabled` flag.

```json
{
  "notices": [{
    "id": "rei_...",
    "powerupType": "RUNNERS_HIGH",
    "deltaSteps": 426,
    "settledAt": "2026-08-17T18:30:00.000Z"
  }]
}
```

- `403` unless caller is entitled to view that race **and** notices always
  filter `userId = req.user.id`; tournament spectators receive `[]`.
- `404` for an unknown race. Missing endpoint/field is treated as no notices by
  the new app.

`POST /races/:raceId/impact-notices/:noticeId/acknowledge` — empty body,
idempotent `200` with `{ "acknowledged": true }`.

- SQL predicate includes `id`, `raceId`, and `userId = req.user.id`; a guessed
  ID must not disclose existence (`404`/generic result) or alter another user.

`GET /races/:raceId/private-impact-feed` — owner-only, capability-gated. It is
deliberately distinct from `GET /races/:raceId/messages?kind=SYSTEM` and its
shared Redis cache:

```json
{
  "events": [{
    "id": "impact:rei_...",
    "eventType": "EFFECT_IMPACT",
    "powerupType": "RUNNERS_HIGH",
    "description": "You gained 426 steps from Runner’s High.",
    "createdAt": "2026-08-17T18:30:00.000Z"
  }]
}
```

- Query predicate always includes `userId = req.user.id`; cursor is
  `(settledAt,id)`, limit is 50, newest first. It is uncached by default and
  always falls back to Postgres with `REDIS_URL` unset. The app merges/de-dupes
  `impact:` IDs without modifying shared-message cursor semantics.
- It uses `impact_notices`/`apiImpactNoticesEnabled` and `{error,code}`:
  accepted participant reads own rows; non-member is 403; tournament spectator
  gets `{events:[]}`; unknown/guessed IDs never reveal another user's rows.
- This is presentation only: acknowledgement remains the separate notice API,
  and an acknowledged modal does not erase the Activity explanation.

`GET /home/race-card` adds `globalEventSummary` only for `impact_summaries`
capability and default-off `apiImpactSummariesEnabled`:

```json
{
  "globalEventSummary": {
    "id": "ges_...",
    "eventId": "gse_...",
    "extraRaceSteps": 840,
    "raceCount": 2,
    "settledAt": "2026-08-17T18:30:00.000Z"
  }
}
```

The key is optional. Acknowledge through
`POST /home/global-event-summaries/:id/acknowledge`: 200
`{"acknowledged":true}`, 404 absent/foreign, 409 already acknowledged, all
standard `{error,code}` otherwise. `GET /races` supplies an opaque
`reviewOpportunity` only on the matching winner's `completed[]` entry with
`review_prompt` capability and `apiReviewPromptEnabled`. After all result/payout
UI is dismissed, `POST /races/:raceId/review-opportunities/:id/claim` atomically
sets `claimedAt`/`attemptedAt` then returns 200 to permit one native request;
404 is absent/foreign and 409 is expired/already claimed. No rating/text is
accepted and no review value appears on Home.

`globalEventSummary` uses a viewer-specific cache gated by default-off
`redisCacheHomeImpactSummaryEnabled`; the wrapper generates the environment
prefixed `p:`/`s:` + `v1:home:impact-summary:<userId>` key (TTL 60 seconds;
allowlist contains only this user's summary). Upsert/acknowledgement invalidates
it; Redis errors or unset `REDIS_URL` fall back to Postgres. Tests cover
Redis-on upsert/ack invalidation and Redis-unset fallback; Postgres is
authoritative.

`reviewOpportunity` is returned by the existing race-results summary as
`{"id":"rop_...","raceId":"...","expiresAt":"..."}`. Its opaque ID is
primary/unique with a winner/race FK. Claim uses `{error,code}` for disabled
capability/flag, malformed ID, foreign/absent (404), expired (409), and already
claimed/cooldown (409); a user-indexed atomic 180-day attempted-at check
enforces the cooldown.

`GET /steps/stats?view=profile-v1` adds an optional additive record:

```json
{ "racePodiums": { "first": 12, "second": 5, "third": 3 } }
```

It is calculated for `req.user.id` only, from final participant placement with
`forfeitedAt IS NULL`; all three counts are non-negative integers. A missing or
malformed field is omitted by the backend/new app rather than rendered as a
false zero.

Inbox is available only with `inbox_v1` capability and default-off
`apiInboxV1Enabled`; absent capability/flag returns 404, which the carrying app
treats as a hidden badge/no Inbox downgrade. Both client-feature header
branches include `inbox_v1`. All IDs are opaque UUIDs and all pagination uses a
base64url cursor encoding the immutable `(createdAt,id)` tuple, newest first,
with `limit` 1–50 (default 25).

- `GET /inbox/alerts?cursor=&limit=` returns
  `{ "alerts":[{"id","type","title","body","destination","createdAt","readAt"}], "nextCursor":null, "unreadCount":0 }`.
  Its SQL predicate includes `userId=req.user.id AND expiresAt>now()`. `POST
  /inbox/alerts/:id/read` is idempotent `200 {"read":true}` with that same
  predicate; foreign/expired/guessed IDs return indistinguishable 404.
- `GET /feedback/threads?cursor=&limit=` returns only the caller's non-expired
  summaries `{ "threads":[{"id","preview","lastMessageAt","unread"}],
  "nextCursor":null }`. `GET /feedback/threads/:id?before=&limit=` returns
  `{ "thread":{"id","expiresAt"}, "messages":[{"id","senderKind","text","createdAt"}],
  "nextBefore":null }`; the cursor is the oldest `(createdAt,id)` returned,
  while messages are sorted ascending for display, and it marks staff messages
  read.
  `POST /feedback/threads/:id/messages` accepts
  `{"text":"...","idempotencyKey":"uuid"}` (trimmed 1–2,000 chars);
  it is idempotent 201/200 and rate-limited to 10 messages/user/hour. Foreign,
  expired, or guessed threads are 404; invalid payload is 400; rate limit 429.
- `GET /admin/feedback/threads?cursor=&limit=` returns
  `{ "threads":[{"id","suggestionId","preview","lastMessageAt","userUnread"}],
  "nextCursor":null }`; it omits email, device, and profile/contact data.
  `GET /admin/feedback/threads/:id?before=&limit=` has the same thread/message
  shape as user detail without identity expansion. Both are admin-only. `POST
  /admin/feedback/threads/:id/messages` accepts the same text/idempotency shape,
  is rate-limited to 60 staff replies/hour, and creates the STAFF message plus
  recipient `inbox_alert` and `inbox_delivery_outbox` row in one transaction.
  It returns 201/200. No request accepts a sender role or recipient user ID.
  Non-admin is 403; foreign/expired/guessed staff thread is 404.

Every Inbox endpoint returns `{error,code}`: unsupported capability/flag 404,
malformed cursor/ID/body 400, owner-hidden/expired ID 404, unauthenticated 401,
staff authorization 403, and rate limit 429. No list/detail response exposes a
raw user ID, device token, email, or staff ID.

The `inbox_expiry` worker follows the project cron contract: expose
`buildInboxExpiry`/`scheduleInboxExpiry`, register in `startCrons()` only under
`NODE_APP_INSTANCE === "0"`, and guard with `INBOX_EXPIRY_DISABLED`. A durable
Postgres `job_runs` daily claim plus idempotent `DELETE ... WHERE expires_at <=
now()` deletes expired alerts and expired threads/messages; retries resume
safely. Account deletion first deletes Inbox alerts/outbox rows, then feedback
threads/messages (or relies on the corresponding cascades), before its existing
user row transaction completes. After each committed expiry batch it invalidates
the viewer-specific unread-cache key for every affected user; integration tests
cover this invalidation with Redis enabled and the authoritative Postgres path
with `REDIS_URL` unset.

`GET /home/race-card` adds optional `homeServiceBanner`:

```json
{ "homeServiceBanner": { "enabled": true, "message": "Step syncs may be delayed." } }
```

Declare `homeServiceBannerEnabled: false` and
`homeServiceBannerMessage: ""` in `KNOWN_FLAGS`. The server reads both values
from the existing admin settings store on the Home read path; enabling/disabling
or changing the message invalidates the existing `v1:settings:app` app-settings
cache after the write transaction commits, so the next Home refresh observes it.
Add an atomic `PATCH /admin/settings/home-service-banner` command
accepting the complete pair: boolean `enabled` and a plain 1–240-character
`message` when enabled (empty only when disabled). It validates the final pair
and writes both setting rows in one transaction; the generic boolean-only
`PATCH /admin/settings` cannot mutate either banner key.

With the same `inbox_v1` capability/flag, `GET /home/race-card` also adds
`"inboxUnreadCount": 0`. It is a recipient-bound count from `inbox_alerts`
plus unread staff messages in that user's non-expired threads, never a global
counter. Its absence means the Home mail icon is not rendered; malformed/negative
values are ignored rather than shown as zero.
It uses default-off `redisCacheHomeInboxUnreadEnabled` with viewer-specific
environment-prefixed `p:`/`s:` + `v1:home:inbox-unread:<userId>` keys, a 60s
TTL, and Postgres fallback when Redis is unavailable/unset. Alert creation/read,
support-reply write, and thread-message read invalidate the affected user's key;
the cache stores only that user's count.

### 5.3 Settlement/job order

1. Extend the canonical race-resolution artifact to emit versioned attribution
   components and event counterfactuals at score finality; no notification job
   may replay multiplier/Leech/global-event math.
2. In the same Postgres settlement ownership/fence that freezes a race score,
   transactionally upsert `race_effect_impacts` and per-race event contributions.
   Never write numeric data to `race_powerup_events` or a shared cached message.
3. `buildGlobalEventSummaryTick` is registered in `startCrons()` under
   `NODE_APP_INSTANCE === "0"`, runs behind `GLOBAL_EVENT_SUMMARY_DISABLED`,
   and uses durable Postgres `job_runs` claims plus idempotent summary unique
   keys. It resumes partial work after failure; Redis is never the queue.
   It only reads final race artifacts and does not bulk-write participants on a
   request path.
4. Register `impact_notices`, `impact_summaries`, `review_prompt`, and
   `inbox_v1` in `KNOWN_FLAGS` and add all four tokens to both client-feature
   header branches
   in `BackendApiService`. Every new frontend request treats 404/absent field as
   an old-backend downgrade; all flags default off.
5. Deploy migration → canonical settlement writer → owner-only readers/acks and
   flags → monitor → frontend. New UI ships only after production endpoints are
   live.

## 6. Frontend plan

- `lib/widgets/streak_chip.dart`, `lib/screens/tabs/home_tab.dart`: permanent
  Daily Reward label, availability states, reduced-motion animation, analytics.
- `lib/screens/daily_reward_screen.dart`, `lib/services/ad_service.dart`:
  explicit retryable loading state; keep the existing SSV claim/retry; extend
  `_RewardReveal` with the optional extra-spin CTA without bypassing it.
- `lib/services/race_impact_notice_service.dart` (new) and
  `lib/services/backend_api_service.dart`: defensive parsing/API calls. No
  unchecked server casts or `!` for new fields.
- `lib/screens/race_detail_screen.dart`: fetch eligible notices after its
  authorized progress/detail load; render at most three with
  `showPowerupRevealModal`; acknowledge only after dismissal.
- `lib/widgets/feed_bubble.dart` and `RaceFeedService`: fetch/render the
  owner-only private-impact stream with existing icon/accent/copy, preserve
  Stealth replacement behavior, and merge stable IDs without shared cursors.
- `lib/screens/main_shell.dart` / Home refresh owner: consume optional
  `globalEventSummary`, show the acknowledgment-gated completion modal, then
  invoke the native review flow only when a separate eligible opportunity
  occurs. Never stack both dialogs in one frame.
- iOS and Android native mediation changes are made and built in lockstep.
  Consult each adapter’s current vendor/Google instructions before pinning;
  adapter setup belongs in `ios/Podfile`/lockfile and Android Gradle, not Dart
  reward business logic.
- `lib/screens/race_detail_screen.dart`: request completed progress once, model
  its loading/error state, and prevent an empty final-standings shell. Backend
  tests must establish whether the completion progress response is guaranteed
  complete under participant paging.
- `lib/demo/demo_race_api_service.dart`, `lib/demo/demo_race_engine.dart`, and
  tutorial preview fixtures: explicitly suppress impact/global/review overlays
  and override new API calls with no-network values in demo/tutorial mode;
  preserve `tutorialPowerupsKey` and the hand-copied tutorial tab bar.
- `lib/screens/referral_screen.dart`, `referral_rules_screen.dart`,
  `onboarding_flow.dart`, `get_coins_screen.dart`, and referral share helpers:
  use the approved qualifying-race copy from one shared constant. Mirror its
  plain-language meaning in backend web/push copy.
- `lib/screens/tabs/profile_tab.dart`: render optional podium counts in the
  profile's existing stats/pixel-card language with stable loading/error
  behavior; do not show it as a loss metric or manufacture zeros from a
  missing old-backend field.
- New Inbox screen/service and a Home unread affordance: defensive endpoints,
  plain-text composer, retry/error/empty/read states, proper alert deep links,
  and no user-search or player-message affordance. Extend the existing admin
  feedback screen with the staff thread/reply controls.
- `lib/screens/tabs/home_tab.dart` and Admin Settings: render the remote
  text-only status banner in its dedicated top-of-scroll slot; read malformed
  config as absent and validate message entry before PATCH.
- Race creation/detail, payout sheet, result summary, tournament detail, and
  payout-double offer UI: render only server-owned tier/total/bonus values. Do
  not add Dart rounding. For version-1 responses, the displayed total must be
  the server-provided rounded-award total and equal the visible tier sum; absent
  additive fields retain legacy presentation without a fabricated total.
- Create/Edit Race and Tournament: suppress the locally calculated pre-submit
  payout/prize total for v1-capable flows, collapse its space, and preserve all
  other inputs/copy/CTAs. Do not use `computePrizePool` as an authoritative v1
  preview; authoritative amounts begin with the server creation response.

## 7. Compatibility, privacy, and rollout

- Existing endpoints remain unchanged; every new response field is optional.
  A current app against an old backend shows no impact/global summary and keeps
  its existing reward flow. An old app against the new backend ignores fields.
- Backend deploy order: migration → canonical settlement/ledger writer →
  private API readers/acks + flags → monitor → Flutter iOS/Android release.
  Enable remote/capability gates gradually after App Store phased rollout.
- Every notice/summaries query and acknowledgement binds the authenticated user
  in the database predicate. Do not authorize by client-supplied `userId`, a
  race membership lookup alone, a display name, or an opaque ID alone.
- Log only opaque IDs and counts; do not place another player’s step delta in
  push payloads, Home payloads, error responses, or analytics contexts.
- Mediation is not an excuse to relax ATT/consent, Google UMP/privacy partner
  configuration, test-device usage, app-ads.txt, or SSV validation.
- Disable Ad pods in the production and staging **rewarded ad unit** settings;
  keep both in-app banner placements. Confirm in Ad Inspector/physical-device
  testing that one opt-in request produces one rewarded creative and that SSV
  still grants exactly one extra spin. This is console configuration, not a
  Flutter ad-flow change.
- Inbox authorization is stricter than UI hiding: every user query/mutation is
  scoped by the authenticated recipient/thread owner, staff endpoints require
  admin authorization, and feedback text is treated as private user content.

## 8. Tests first and acceptance criteria

### Backend integration tests

- A completed Runner’s High, Leech victim, and Leech beneficiary each emit the
  correct signed private Activity text and notice from the public HTTP path.
- Every declared V1 effect type is covered, including Umbrella cancellation,
  signed Hitchhike, failed Drill Sergeant, overlapping multipliers, score-floor
  clipping, and deterministic integer-remainder conservation.
- Replayed worker/event attempts create exactly one impact row/event.
- Two users in one race: User A cannot list/acknowledge User B’s impact by
  changing `noticeId`, `raceId`, query parameters, or guessed IDs. Non-member
  and tournament spectator variants are covered.
- Global 2× fixture verifies exact event-window totals, multi-race aggregation,
  neutral/positive/negative signed totals, Leech/Hitchhike downstream effects,
  late-sample replay, idempotent retry, and cross-user isolation.
- Review eligibility threshold/cooldown remains server-authoritative; attempt
  cannot be spoofed for another user; only the settled first-place opportunity
  can be atomically claimed, including duplicate/crash/expiry cases.
- Private race: invite acceptance and share-link join both start eligible
  races; future schedules, live outstanding invites, uneven teams, disabled
  flags, seeded/tournament races, and concurrent accepts remain safe.
- Podium record query excludes forfeit rows, returns exact individual/team
  placement counts, and cannot be requested for another user's profile.
- Inbox HTTP tests prove guessed alert/thread/message IDs cannot be read,
  marked read, or replied to by another user; non-admins cannot list/reply as
  staff; admin replies create exactly one user alert despite retries; expiry
  exactly 30 days after the last message and account deletion meet the selected
  retention policy.
- Admin settings validates service-banner enable/message combinations and
  auth/Home response exposes only valid active text.
- Global-event scheduler tests pin a one-minute interval, start within the
  two-minute catch window, skip a stale >2-minute anchor, retain exactly one
  event/day under restart/concurrent-tick conditions, and verify ordinary ticks
  do not issue participant or scoring reads.
- Write pure rounding-vector tests first: zero stays zero; 1–5 becomes 5;
  6–10 becomes 10; values already ending in 0/5 do not change; the rounded
  total equals the sum of every recipient award and is never less than the
  canonical base total. Test the complete plan, including immutable raw inputs,
  final award arrays, per-recipient/aggregate subsidy metadata, and protection
  against rounding an already-rounded plan.
- HTTP/settlement tests cover every currently creatable included path: fixed,
  graded, funded, team split/tie, Daily/Weekly finish reward, app-funded and
  featured tournament champion, full payout-double base/bonus, and payout-cutoff
  projections. A canonical `7 / 2 / 1` plan must credit and render `10 / 5 / 5`.
  Verify exactly-once retries do not mint the rounding difference twice.
- A legacy PENDING/ACTIVE/COMPLETED race and tournament keep version 0 amounts
  on read and settlement; a newly stamped version-1 row renders every payout
  tier/pool/result total ending in 0 or 5. Old-client response shapes remain
  unchanged and their fields equal the actual final awards.
- Real HTTP/DB coverage exercises race detail/list/public/share/Home/completed
  result and tournament summaries, including `payouts`, `payoutTiers`, pool
  aliases, `myPayoutCoins`, and state-specific tournament presentation.
- Team integration covers a one-recipient winner, multi-recipient winning team,
  and funded tie without publishing a false single pre-result total.
- Payout-double integration proves every otherwise eligible rounded payout gets
  a full-base offer; verified claims award the full rounded base, never a partial
  cap remainder; duplicate/fraud claims remain rejected exactly once. Tournament
  rounding tests do not manufacture a new tournament payout-double endpoint.
- Failure-injection and concurrent settlement tests cover a crash between ledger
  credit and participant/result persistence, reconciling one exact credit,
  `payoutCoins`, subsidy metadata, and displayed total.
- Creation integration covers every writer, default-enabled version-1 stamping,
  kill-switch version-0 stamping, migration default/no-backfill, and the rollback
  sequence. Historical player-funded buy-in rows remain byte-for-byte v0.

### Flutter widget/integration tests

- `DAILY REWARD` label and static reduced-motion variant; animation is bounded
  and never runs while disabled.
- Failed/timeout ad load transitions to retry; retry/readiness/dismissal/SSV
  lag paths never wedge; no entitlement call occurs without a verified grant.
- Reward reveal includes CTA only when the server offer and platform support
  are both present; close/CTA/pending-grant/error paths retain correct state.
- Race notice parsing is safe for absent/malformed old-backend fields; modal
  ordering/cap/ack semantics are correct and uses the source icon.
- Private impact Activity events merge/de-dupe without changing shared feed
  pagination, and do not appear for a different participant or spectator;
  verify with Redis enabled and with `REDIS_URL` unset.
- Global summary is once-only after acknowledgement, has accurate plural copy,
  and does not block Home on absent data. Review prompt is not attempted in a
  negative/error/ad flow and honors backend eligibility.
- Completed race with paging enabled shows every final participant, not an
  empty card; progress loading/error is visible and retryable.
- Manual accepted pending race renders `PENDING` and no bottom waiting card;
  creator, invited, scheduled, uneven-team, quick-auto-start, and demo variants
  retain their appropriate controls/copy.
- Referral surfaces all use the approved wording. Profile renders podium totals
  only when its additive record is present; a legacy payload remains honest.
- Inbox alerts/support tabs cover loading, empty, pagination, unread/read,
  sender/recipient retry, and staff-only controls; there is no player-DM route
  or user-search result. Home banner correctly wraps/clears when admin config
  toggles.
- Create/Edit Race and Tournament v1-capable screens omit the local pre-submit
  payout total with no empty gap and retain all inputs/submit actions; a created
  fixture then renders the server-provided rounded total. Legacy v0 fixtures
  retain their historical preview where explicitly applicable.

### Manual release checks

- iOS and Android: free reward, ad ready, ad fail/retry, ad dismissed, and SSV
  lag; inspect AdMob response info/ad inspector for every configured network.
- iOS and Android: consent/ATT variants, test ads only, app-ads.txt verified,
  and each selected network’s console test mode disabled before production.
- Verify a participant sees only their own impact amount in Activity/modal;
  a rival and a spectator do not see or infer it.
- Verify the rewarded ad unit has **Ad pods** disabled in both environments;
  one successful extra-spin tap shows one rewarded creative while the existing
  top and bottom display banners remain.

## 9. Resolved owner decisions

1. **Global summary semantics:** “+X extra race steps across N races” is
   desired; one walked step may correctly contribute an increment in multiple
   simultaneously active races.
2. **Review policy:** first place is the sole positive v1 trigger, with a
   server-owned 180-day attempt cooldown.
3. **Referral wording:** “Finish any race with at least one other player to
   earn your referral reward. Daily and Weekly challenges don’t count.”
4. **Profile record:** show first-, second-, and third-place totals, exclude
   forfeits, and count a team win as first place; do not show losses.
5. **Inbox boundary:** alerts plus replyable staff-only feedback conversations;
   no player-to-player messaging in v1. Alerts expire after 30 days; support
   threads expire 30 days after their last message.
6. **Home status banner:** admin-toggleable, editable, persistent text-only
   Home banner; no external link or dismissal.
7. **Rewarded ad pods:** retain both display-banner placements; disable Ad pods
   in AdMob so one extra-spin opt-in produces one rewarded creative.
8. **2× timing:** run the scheduler every minute; permit at most two minutes of
   late catch-up, then skip rather than starting a visibly stale event.
9. **Payout rounding:** new currently creatable app-funded races/tournaments use
   version-1 per-recipient round-up to 0/5, minimum 5. Historical player-funded
   buy-in rows remain version 0. Bara mints the rounding difference, records it
   as subsidy metadata, and defaults new-row stamping on with an emergency kill
   switch. All payout surfaces show the actual award total. Every otherwise
   eligible rounded payout receives an offer for one full additional copy after
   verified ad completion; no coin ceiling suppresses or clips that bonus.
   Existing eligibility remains completed race results; tournament champions do
   not gain a new rewarded-ad surface in this batch.

## 10. Manual UI-placement test plan

1. **Real Home:** free-box and extra-spin accounts show `DAILY REWARD` beside
   SHOP; attention appears only while actionable, never in unavailable/loading/
   error state.
2. **Daily Reward/reveal:** ready/pending/retry CTA occupies its intended action
   slot; the reveal CTA never hides the reward and no disabled permanent
   `LOADING AD...` remains.
3. **Tutorial Home:** retains the real quick-action placement and no live
   network escape, duplicate label, or old `CLAIM` label.
4. **Real Race Activity:** positive and negative owner impact lines appear in
   Activity—not Chat/standings/another player's row—and effect modals sequence
   in the same overlay position after Race Detail loads.
5. **Demo/tutorial Race Detail:** no new live impact modal can cover scripted
   beats or displace the `raceDetail.powerups` spotlight unless a controlled
   fixture explicitly exercises it.
6. **Real Home recap:** the 2× completion modal appears only after Home loads,
   disappears after dismissal, and never overlays Daily Reward/Race Detail.
7. **Tutorial/demo Home:** global recap remains suppressed unless a controlled
   fixture is added; Home spotlight targets remain visible.
8. **Winner review:** native prompt, if the OS elects to show it, appears only
   after first-place result and payout/ad UI finishes; it never appears for a
   non-winner.
9. **Completed Race Detail:** individual large roster and team roster both show
   the populated final board in its existing location; forced progress failure
   shows loading/error/retry, never an empty card.
10. **Manual pending accepted non-creator:** hero says `PENDING`; bottom waiting
    card and its reserved gap are absent.
11. **Protected pending variants:** scheduled preserves `STARTS IN`; creator,
    invited, uneven-team, quick-auto-start, and demo controls remain in place.
12. **Ad mediation release:** iOS and Android test every configured source in
   Ad Inspector, consent/ATT variants, test ads, app-ads.txt, then disable
   network test mode before production.
13. **Referral copy:** Referral, rules, Get Coins, onboarding welcome, share,
    web, and notification wording say a race needs another player and exclude
    Daily/Weekly challenges without clipping at large text.
14. **Profile podiums:** small and large counts, no-history/legacy payload,
    individual first/second/third, team first, and forfeited row exclusions
    render in the existing Profile stats location on both platforms.
15. **Inbox:** a user sees only their own alerts/support threads; staff reply
    appears as BARA SUPPORT, produces one unread alert/deep link, and an
    ordinary user can never reach a player-DM surface or staff composer.
16. **Service banner:** enabled/disabled/long localized-size text presents
    below Home chrome without obscuring quick actions, Daily Reward, refresh,
    demo/tutorial fixtures, or safe-area content.
17. **Payout rounding:** new individual/team/Daily/Weekly/tournament fixtures
    show only amounts ending in 0/5, with the race/result/payout-sheet total
    equal to the visible awards; legacy in-flight fixtures retain their original
    values. The payout-double result shows a second copy of the rounded base,
    never a separately rounded or clipped value.

### Payout-rounding pre-submit preview removal

*Elements under test:*
- Remove the locally computed prize/payout-total plaque from v1-capable Create
  Race, Edit Race, and Create Tournament flows.
- Preserve authoritative server-rounded payout totals on created race/tournament
  detail, results, and history surfaces.
- Preserve legacy/version-0 fixture presentation where that fixture intentionally
  carries an existing server/fixture total.

1. **Surface:** Create Race — individual race, iOS and Android  
   **Get there:** Open Races → Create Race; select several duration and runner-cap
   combinations.  
   **Verify:** No local prize-pool/payout-total plaque appears below the timeline
   or elsewhere before submission. The next surviving section/control moves up
   cleanly with no blank card-sized gap; duration, runner-cap, customize controls,
   and Create CTA remain in their existing order and positions.

2. **Surface:** Create Race — team race, iOS and Android  
   **Get there:** Open Races → Create Race → choose a team format and change team
   size/duration.  
   **Verify:** No single local payout/prize total is shown for an indeterminate
   team outcome. No empty preview slot remains; team controls, timeline,
   powerups, and Create CTA retain their normal placement.

3. **Surface:** Create Tournament, iOS and Android  
   **Get there:** Open Races → Create Race → switch to Tournament; change bracket
   size and matchup duration.  
   **Verify:** The locally calculated tournament prize-pool plaque is absent from
   the tournament setup flow. The explanatory text, bracket/duration controls,
   and tournament Create CTA remain contiguous, with no blank gap or displaced
   action.

4. **Surface:** Edit pending race, iOS and Android  
   **Get there:** Open a v1-capable pending race as its creator → overflow menu →
   Edit Race; change duration and allowed participant settings.  
   **Verify:** No locally recomputed prize/payout-total plaque appears under the
   timeline. The following Powerups/team sections move up without a gap, and all
   editable inputs plus Save CTA remain visible and in their previous relative
   order.

5. **Surface:** Newly created v1 race — detail and completed results  
   **Get there:** Create a staging v1 individual race/tournament, then open its
   detail; complete a test race and open its result/history entry.  
   **Verify:** Server-provided rounded totals/tiers appear only after creation on
   their existing detail, result, and history surfaces. The visible total agrees
   with the displayed tiers; no old pre-submit-derived total is carried into
   these screens or duplicated beside the authoritative value.

6. **Surface:** Team and tournament authoritative presentations  
   **Get there:** Open a created v1 team race and a created v1 tournament in
   pending/active/completed states as available.  
   **Verify:** Team detail does not invent a single authoritative projected total
   while recipient count is indeterminate. Tournament detail and completed
   presentation retain their existing server-total locations; no blank
   placeholder is left where a total is unavailable.

7. **Surface:** Demo create-race tutorial  
   **Get there:** Start/replay the demo race → reach the Create Race beat.  
   **Verify:** The real Create Race screen omits the pre-submit local prize
   preview without leaving a hole between the timeline and the next control. The
   demo coach's duration and Create spotlight targets still ring the correct
   controls and are not shifted beneath its coach chrome.

8. **Surface:** Demo race detail and tutorial race-detail preview  
   **Get there:** Continue the demo after creation; separately open the
   tutorial's Powerups & boxes race-detail preview.  
   **Verify:** Existing fixture-backed/server-style payout presentation remains
   in its current Race Detail location when supplied. It is not removed merely
   because Create/Edit previews were removed, and no new locally computed
   preview appears.

9. **Surface:** Legacy/version-0 race and tournament fixtures  
   **Get there:** Open an existing legacy pending/active/completed race and
   tournament fixture on staging or the tutorial/demo fixture path.  
   **Verify:** Existing fixture/server-provided payout/pool presentation remains
   where it already appears. Only the v1-capable pre-submit local calculation is
   absent; legacy detail/result/history surfaces do not gain a blank gap or lose
   their established totals.

*Surfaces confirmed unaffected:*
- **Tutorial hand-copied tab bar:** no tab order, label, or index changes.
- **Race Results payout-double panel:** it uses an authoritative settled payout
  and remains in its existing result-summary location.
- **Daily Reward, case-opening, and Home surfaces:** they do not host create/edit
  payout previews.
- **Race Detail payout breakdown sheet:** it remains authoritative post-create
  presentation, not a pre-submit projection.

*Risks found while planning:*
- Remove adjacent `SizedBox`/section spacing with the plaques; otherwise each
  affected form can retain a conspicuous blank gap.
- The demo Create Race beat uses the real Create Race screen and coach anchors,
  so its fixture/test must confirm the removed plaque does not push tutorial
  targets into coach chrome.
- Mark demo/tutorial payout fixtures explicitly version 0 or server-authoritative;
  they must not silently continue exercising the removed local projection path.

Implementation must add controlled tutorial/demo fixtures or explicit
suppression for all new overlays, a testable native-review eligibility seam,
and a completed large-roster/failure fixture. Races-tab effect trays,
hand-copied tutorial tab bar, create/invite demo prologue, and race box-opening
screens remain unaffected except for the explicit tutorial checks above.

## 11. Revision log

- **2026-08-17 — Draft:** converted the owner notes into seven scoped features,
  retained server-side reward authority, and made user-level privacy an API and
  test requirement rather than a UI-only check.
- **2026-08-17 — Gap pass 1:** made race Activity recipient-private instead of
  persisting a numeric shared-feed line.
- **2026-08-17 — Gap pass 2:** pinned acknowledgement to post-dismissal,
  preserved verified-but-unclaimed ad grants, specified reduced-motion behavior,
  and added cross-user guessed-ID tests so the privacy requirement is enforced
  below the UI layer.
- **2026-08-17 — Owner decisions:** expanded effect attribution to all
  score-changing lingering effects, approved tap-to-retry ad recovery, approved
  ironSource Ads + Mintegral, and sequenced mediation last because its account,
  consent, and app-ads.txt work is external to the codebase.
- **2026-08-17 — Added findings:** diagnosed completed-race standings as a
  progress-load/paging interaction, added a repair with no truncated-roster
  fallback, recorded the owner’s first-place review direction, and verified
  that private auto-start is already implemented with both inline and cron
  paths; production configuration/staging behavior still need verification.
- **2026-08-17 — Added pending-race cleanup:** replace the generic start-line
  label with `PENDING` and remove only the redundant accepted non-creator
  waiting card, preserving actionable pending-state variants.
- **2026-08-17 — Owner decision:** confirmed race-score (not physical-step)
  global-event totals and selected first-place finish as the sole v1 native
  review trigger, with a 180-day server-side attempt cooldown.
- **2026-08-17 — Post-expansion gap pass 1:** made the recipient-private
  Activity transport explicit and cursor-safe rather than relying on an
  unspecified mutation of the shared feed stream.
- **2026-08-17 — Post-expansion gap pass 2:** rechecked all new UI states
  against reduced-motion/old-backend behavior and completed-race paging; no
  additional product behavior changed before review.
- **2026-08-17 — Architect/economy required revisions:** moved all score-impact
  finality to canonical race settlement; required additive versioned attribution
  and event counterfactuals; separated owner-only Activity transport from shared
  cache; defined durable ledgers, flags, winner-only review opportunities,
  scheduler ownership, completed-roster contract, and tutorial/demo safeguards.
- **2026-08-17 — Review closeout amendments:** added durable per-race event
  impacts, non-overlapping effect/global attribution, signed/net-zero recap
  copy, exact private-stream authorization, winner-opportunity errors, and the
  viewer-specific Home-summary cache contract.
- **2026-08-17 — Scope reopened by owner:** added approved referral copy,
  profile podium record, staff-only feedback Inbox, editable Home service
  banner, and an AdMob-console-only Ad-pod disablement. These are material new
  API/data/UI surfaces, so prior architecture/economy/UI review approval must
  be repeated before implementation.
- **2026-08-17 — Inbox retention decision:** alerts expire after 30 days;
  support threads and their messages delete 30 days after the last reply, not
  only on account deletion.
- **2026-08-17 — Reopened review closeout:** architecture approved the explicit
  Inbox source-of-truth/outbox/cache/expiry contracts and atomic service-banner
  settings write; UI placement plan fixed podiums below Stats and the unread
  mail icon in the Home Hero's upper-right position. Economy review found no
  reward/EV change; the owner retained the already-approved concise referral
  copy unchanged.
- **2026-08-17 — 2× start timing:** owner approved a one-minute global-event
  scheduler and a two-minute late-start ceiling; stale starts are skipped,
  while daily selection, duration, multiplier, and scoring remain unchanged.
- **2026-08-17 — Payout-rounding scope opened:** owner selected all final race
  payout paths, per-recipient round-up to 0/5 with a 5-coin minimum, explicit
  minting of any rounded difference, actual-award-total display, ad double of
  the already-rounded base, and new competitions only. This alters payout
  curves and coin issuance; economy and architecture review must repeat before
  implementation.
- **2026-08-17 — Payout-rounding gap pass 1:** clarified that zero/non-recipient
  amounts are never promoted to five, no recipient can lose a coin to fund
  rounding, and payout-double eligibility itself is not widened to buy-in
  transfers or refunds.
- **2026-08-17 — Payout-rounding gap pass 2:** separated the internal held-pot
  accounting value from its version-1 public rounded-total alias, required a
  row-stamped version rather than a live switch, and added settlement retry,
  legacy-row, capped-ad-bonus, and full-path test coverage.
- **2026-08-18 — Payout architecture re-review:** required one immutable
  versioned payout plan, complete creation-writer stamping, honest team and
  state-specific tournament projections, durable crash reconciliation, safe
  rollback, and a full HTTP/DB compatibility matrix.
- **2026-08-18 — Payout economy review and owner override:** review identified
  uncapped per-recipient subsidy and ad-double issuance as inflation/farming
  risks. The owner clarified that new player-funded buy-ins no longer exist,
  accepted rounding for all current app-funded paths, selected default-on v1
  stamping with subsidy observability and a kill switch, and required every
  eligible payout-double offer to award one full rounded-base copy without a
  suppressing or partial coin cap. Existing anti-fraud, SSV, and exactly-once
  controls remain mandatory.
- **2026-08-18 — Payout creation-preview contract:** the locked additive API has
  no preflight payout-plan field, so v1-capable Create/Edit Race and Tournament
  screens omit their locally computed pre-submit pool total instead of showing a
  value that can contradict settlement. Server-owned totals begin after creation;
  no Dart rounding was introduced.
