# Race retention, inventory, identity, tutorial, and UI fixes — requirements

**Status:** implemented and production-ready as of 2026-09-06; owner-approved; architect/economy/UI/code reviews complete
**Implementation:** explicitly not authorized

## 1. Summary and user stories

This batch contains twenty-two changes: prevent visible clues from identifying an
active Stealth racer; let any accepted participant create unlimited sequential
custom-race rematches with the former roster invited; remove the viewer avatar
from personal tournament cards; update community handles; expose the existing
one-time ad reroll from eligible held powerups; label daily item rewards; teach
Shop on every account's first real visit with Settings replay; reject profane
display names and force existing offenders to rename; repair referral-contest
contrast; render sharing ideas as non-interactive bullets; add blocking Shop
purchase progress; add opt-in recurring custom races; restore the Home service
banner; restore Daily Reward prize help; add own/friend race statistics; suppress
same-team opponent nudges; reject stacked Rally Flags; unify solo activity/chat;
enforce admin-only giveaway creation; add private team chat; move Decoy from Shop
to mystery-box rolls; and replace Hitchhike's icon.

## 2. Scope and non-goals

### In scope

- iOS and Android Flutter behavior, real reused demo/tutorial surfaces, additive
  backend contracts/migrations, durable events/cache invalidation, accessibility,
  and tests written before logic.
- Defensive behavior across older/newer app and backend versions.

### Non-goals

- Preserve the shipped 2026-08-28b Stealth contract: active unfinished
  opponents hide name, steps, and track position, but authenticated API IDs are
  not anonymized and finished/expired racers unmask.
- No changes to odds, duration, reroll value/odds, prices, payout math, scoring,
  buy-ins, brackets, or the reveal-time reroll.
- No rematch confirmation editor and no copied lifecycle, progress, inventory,
  messages, settlement, or notification history.
- No broad redesign, release flag, staging/prod operation, deployment, or code
  implementation during this planning phase.

## 3. Current-state findings (2026-09-06)

- Backend Stealth projection already returns `stealthed:true`, `???`, and hides
  presentation/steps/placement for active unfinished opponents. Flutter already
  suppresses the standings effect tray at
  `lib/screens/race_detail_screen.dart:10977-11009`, with coverage in
  `test/race_detail_team_effect_rail_test.dart`. The screenshot is therefore a
  regression/alternate-renderer audit, not a new anonymity model.
- There is no rematch endpoint. Since the previous review, the race-resolution
  worker has become a specialized scoring/projection queue: race-keyed rows,
  dirty-reason envelopes, generation fencing, append-only large-race intake,
  bounded planning inputs, and one shared process-wide work budget. Rematch
  invitation fan-out must not be inserted into that queue. A rematch instead
  creates the new PENDING race, creator membership, ordinary INVITED rows, and
  durable `RACE_INVITE_SENT_V1` outbox events atomically in its own command.
- Race-list reads now combine a membership cache with a versioned completed-race
  summary cache, while race detail/progress share a request-owned bootstrap read
  context and bounded participant summary. Viewer-specific rematch eligibility
  must be overlaid after shared cached fragments and must not expand bootstrap
  reads into a full scoring roster.
- Personal tournament cards build a leading `RacerAvatar` in
  `lib/screens/tabs/races_tab.dart:1627-1639`; tutorial previews reuse `RacesTab`.
  Old handles are in `lib/screens/settings_screen.dart:467-490`.
- `RacePowerup.rerolledAt` exists. `AdService` now supports dedicated iOS and
  Android box-reroll defines. The current reroll command consumes the grant and
  later conditionally updates the powerup in separate DB statements, so a race
  can consume a watch without a replacement under concurrency.
- Daily Reward distinguishes defensive `rewardType` payloads but lacks the
  requested labels/copy. The general five-step tutorial points out Shop from
  Home but does not teach the real Shop; Shop already has stable keys for all
  four requested targets.
- Display-name profanity filtering exists in route validation via `bad-words`,
  but `setDisplayName` does not validate its input and the matcher does not cover
  common separator/leetspeak evasions. Full/compact auth serialization is now
  centralized in `serializeAuthenticatedUser`, `serializeAuthShellUser`, and
  `authMeCache`.
- Contest contrast failures originate in
  `referral_contest_joined_dashboard.dart` and `giveaway_rules_screen.dart`.
- Concurrent, uncommitted race-detail work now removes forfeited racers from
  visible active/completed rosters while retaining their frozen steps in team
  totals. Stealth work must preserve that behavior and must not reintroduce a
  forfeited row merely to mask it as `???`.

## 4. Detailed requirements

### R1. Active-Stealth presentation regression

- Preserve 2026-08-28b exactly. Only literal server `stealthed:true` hides a row;
  the viewer's own row and finished racers stay visible.
- Every active race-detail renderer must hide effect icons/ownership, photo,
  animal, accessories, multiplier, profile/friend action, steps, track position,
  and hidden numeric placement for a hidden opponent. Audit individual/team
  standings, team effect rails, course, leader chrome, and real demo/tutorial
  fixtures.
- Apply Stealth masking after excluding `forfeitedAt != null` participants from
  visible rosters. Preserve their frozen-step contribution to authoritative team
  totals and preserve the current page cursor/count behavior; a forfeited racer
  is absent, not a visible anonymous Stealth row.
- Do not add completed-race masking, remove IDs, or alter masked ordering and
  viewer-relative display-placement rules.

### R2. Custom-race rematch

- Source must be COMPLETED, non-seeded, non-tournament custom race; caller must
  have been ACCEPTED. Any former accepted participant may initiate and becomes
  creator/ACCEPTED in the new race.
- Add `POST /races/:raceId/rematch`. Require UUID `Idempotency-Key`; accept
  `body.idempotencyKey` for parity with current idempotent shop commands, with
  the header winning. First creation returns 201; an exact replay returns 200.
  Reuse on another source/request digest is `409 IDEMPOTENCY_KEY_REUSED`.
- Response:

```json
{
  "race": { "id": "new-race-id", "status": "PENDING" },
  "sourceRaceId": "completed-race-id",
  "invitedUserIds": ["former-accepted-user-id"],
  "skipped": [{ "userId": "id", "reason": "ACCOUNT_UNAVAILABLE|CLIENT_UPDATE_REQUIRED" }]
}
```

- Stable errors: `SOURCE_NOT_FOUND` (404), `NOT_PARTICIPANT` (403),
  `SOURCE_NOT_COMPLETED`/`SOURCE_NOT_REMATCHABLE`/`REMATCH_ALREADY_LIVE` (409),
  `REMATCH_COHORT_TOO_LARGE` (409), and invalid/missing key (400).
  Every error uses `{"error":"human-readable message","code":"STABLE_CODE"}`;
  an exact idempotent replay returns the same canonical success data.
- The synchronous cohort ceiling is 100 accepted source racers, matching the
  current largest finite custom-race cap. A `maxParticipants:null` source stays
  eligible only while its accepted roster is at most 100; above that, return
  `REMATCH_COHORT_TOO_LARGE` and create nothing. This bounds response size,
  participant/event writes, and transaction duration without limiting how many
  sequential rematches a supported cohort may complete.
- Perform bounded preflight reads for source configuration, caller membership,
  at most 101 accepted-roster IDs, account availability, and team-client
  capability. Then
  execute one PostgreSQL transaction that insert-first reserves the idempotency
  receipt, locks the canonical lineage and creator exposure in existing lock
  order, revalidates the source/current policy, creates the PENDING race,
  establishes its generation-zero `SUCCEEDED`/inert `RaceResolutionJobV2` C0
  fence before any participant write, creates the creator ACCEPTED membership,
  bulk-creates ordinary 72-hour INVITED rows, adds
  one `RACE_INVITE_SENT_V1` outbox event per created invite, and records the
  immutable response on the receipt. Any failure rolls back the race, invites,
  events, holds, and receipt together.
- Do not enqueue runnable rematch work in `RaceResolutionJobV2`, bump its
  generation, add a rematch dirty reason, add a new worker family, or wait for
  notification delivery. The required inert C0 row exists only to preserve the
  race membership/lifecycle single-writer fence; the queue owns
  scoring/projection work;
  notification delivery continues from the existing post-commit domain-event
  projector. A retry after a lost response replays the committed receipt and
  never creates another race or event.
- Recover concurrent idempotency conflicts outside the aborted transaction:
  after the competing transaction commits, reload `(requesterId,
  idempotencyKey)`, compare canonical digest and source, return the stored
  canonical success response for an exact match, and otherwise return
  `IDEMPOTENCY_KEY_REUSED`. Store canonical response data and compare semantic
  equality; do not depend on JSON key order or literal wire bytes.
- Former cohort membership is the narrow exception to today's friends-only
  precheck. It does not bypass unavailable-account checks,
  capacity/team/client-capability rules, or normal acceptance/affordability.
  Skip individual unavailable or team-incompatible accounts with the stable
  reasons shown above; do not fail the whole rematch because one former racer
  can no longer be invited.
- Refactor the canonical create/invite policy and persistence helpers just
  enough to accept a caller-supplied transaction. Do not call one HTTP route
  from another, nest independent transactions, or duplicate economy math.
- Copy/revalidate creator input: name, target/duration, requested buy-in,
  payout preset, powerup settings, public/capacity/time/team settings and team
  names. Reset IDs, creator/status/absolute schedule timestamps, winner/share/seed/
  tournament fields, progress, outcomes, inventory/effects, messages,
  favorites, join requests, payouts, settlement, and notifications.
- Derive a fresh duration/window under current rules, use requester's current
  timezone, preserve initiator's former team when valid, and let invitees choose
  or accept teams through ordinary rules.
- Recompute current funded-prize/pool, payout/version/rounding, exit, creation/
  start, and team multiplier/payout stamps. Fresh creator holds and ordinary
  invite-acceptance holds apply; historical policy never wins.
- Unlimited means sequential across the canonical lineage root. A partial
  unique DB index permits at most one PENDING/ACTIVE rematch descendant per
  root, preventing forks; completion/cancellation permits the next descendant.
- Add viewer-specific `rematchEligible` only. It is true exactly when source/
  caller rules pass and no live lineage descendant exists. Attach it with one
  bounded batch after the shared membership/completed-summary cache fragments;
  for detail/bootstrap, derive it from the already loaded core race plus a
  narrow caller/lineage lookup. Never place it inside viewer-neutral completed
  summary cache payloads or trigger a full participant/scoring preload. Only
  literal true shows UI.
- Do not add product-level rematch throttles: the owner explicitly chose
  unlimited sequential rematches, and the one-live-lineage constraint plus
  idempotency prevents duplicate creation. Instead, prevent cancellation-loop
  push spam durably: for the same recipient plus canonical lineage, repeated
  create/cancel cycles before any descendant completes are one notification
  episode, and the latest race replaces the prior navigation target. A
  completed descendant ends that episode, so the next legitimate sequential
  rematch may notify again. This is delivery coalescing, not a creation limit.
- PostgreSQL owns that episode as one row per recipient + canonical lineage +
  episode generation. Rematch creation transactionally updates `latestRaceId`
  and monotonically increments `revision`; its outbox payload carries episode
  ID/revision and uses a deterministic episode delivery identity. The projector
  ignores stale revisions, updates the existing inbox item's navigation target
  to the latest race, and sends at most one provider push after that episode has
  been provider-accepted. A provider-accepted push cannot be recalled; later
  cancellations update the in-app target but do not send another push. The
  canonical race-completion transaction closes the current episode so the next
  descendant creates the next generation. Extend the existing producer matrix,
  projector, completion seam, and Redis-unset path; do not use Redis as episode
  authority.
- Creator and accepting invitees always pass current `activeCompetitionLimit`
  and current economy stamps. Tag rematch lineage/source in telemetry and repair
  the monitor's hardcoded cap-5 comparison to the live configured cap before
  relying on rematch cohort monitoring.
- After commit, invalidate race-list membership for creator plus every invited
  user through the current invalidation seam. Do not invalidate the immutable
  source completed-summary artifact merely because a descendant was created.
  Redis failure never rolls back PostgreSQL truth; bounded cache TTL remains the
  fallback across HTTP processes.
- Result popup: REMATCH with circular redo icon directly above the existing ad
  CTA and bound per race in a batch. Completed detail: after completion/payout
  summary, before standings. Disable duplicate taps; navigate on success; keep
  context and show actionable error on failure.

### R3–R4. Tournament card and community links

- Remove only the personal tournament card's leading viewer avatar/semantics;
  reflow remaining content without changing tap, state, inventory, placement,
  prize, pin, chevron, or fallbacks. Public tournament cards are unaffected.
- Instagram text `@Bara.steps.app`, URL
  `https://instagram.com/Bara.steps.app`; X text `@BaraStepsApp`, URL
  `https://x.com/BaraStepsApp`. Preserve launch/error behavior.

### R5. Deferred stash reroll

- Add REROLL beneath USE and DISCARD only for active-race rows with nonempty ID,
  HELD/unused state, box rarity, upgrade level zero, null `rerolledAt`, literal
  backend capability, and a configured platform-specific reroll ad unit.
  Missing/malformed data fails closed.
- Reuse existing rewarded-ad context, SSV, bounded retry, lifecycle/account
  binding, endpoint, and result presentation. Refresh progress on success so
  USE/DISCARD targets the replacement. Reveal-time single/batch reroll is
  unchanged.
- In canonical lifecycle/C0 lock order, use one DB transaction to re-read and
  lock race, participant, powerup, and grant; CAS owner/race, HELD, unused,
  rarity-present, level-zero, and null-rerolled state; consume the grant; write
  replacement/config stamp; and insert `POWERUP_REROLLED` through a transaction-
  aware model. Any eligibility, CAS, or audit failure rolls back all writes.
- Keep current-position/config-snapshot behavior and test intentional P1→P6
  delayed-reroll timing; `rerolledAt` remains the one-shot authority.

### R6. Daily reward labels

- Valid powerup: `POWERUP`, with no equip instruction. Valid accessory:
  `ACCESSORY` plus exact copy `Go to your inventory to equip this item`.
- Coins and malformed/fallback rewards show neither. Support themes/text scale.

### R7. First-visit Shop tutorial

- Every authenticated account receives `shop_v1` once on first real Shop visit
  after layout. Never trigger from a preview/test build, general onboarding/
  tutorial, or beneath another overlay.
- If Shop mounts before an authoritative auth payload has been applied, defer
  the automatic decision without consuming the first visit. Reevaluate while
  the same-account Shop remains mounted when AuthService later supplies
  explicit null/timestamp support state; the existing same-identity listener
  shortcut must not suppress this transition.
- Four real-Shop beats: STORE/INVENTORY; category pills; dressing-room stage;
  product grid/card. Scroll before measuring off-screen targets. Use established
  spotlight visuals and accessible NEXT/BACK/close; close/skip completes it.
- Settings adds `VIEW SHOP TUTORIAL`; replay ignores completion for that one
  navigation and does not clear/duplicate state.
- Add nullable `User.shopTutorialCompletedAt` and idempotent empty-body
  `POST /shop/tutorial/complete`, returning
  `{"tutorialKey":"shop_v1","completedAt":"ISO-8601"}` and stamping only once.
- Thread the field through full and compact auth serializers,
  `AUTH_SHELL_FIELDS`, provisioning/session responses, local AuthService state,
  sign-out/account switching, and the documented auth-me invalidation seam.
- Do not introduce another auth-cache version solely for this nullable field.
  Backend-first deployment occurs long before a carrying app reaches users, the
  existing auth cache is bounded to 10 seconds, and completion invalidates it.
- Persist `hasShopTutorialServerState` separately from the nullable timestamp so
  cold start preserves absent-vs-null; clear both on sign-out/account switch.
  Key absent means old backend/unsupported: do not auto-launch. Explicit null
  means supported/incomplete; timestamp means complete. No row backfill.
- Implement rematch and tutorial endpoints as thin module routes using
  `asyncHandler`, injected commands/models, and standard `AppError` subclasses;
  do not put business logic in routes or add new legacy `src/routes/` code.

### R8. Profanity-safe display names

- Extend the existing backend validator and validate within `setDisplayName`
  before uniqueness/update. Preserve charset/length rules; compare a
  NFKC/case-folded form with separators removed and conservative common
  leetspeak mapped. Use reviewed English token/boundary rules plus explicit
  allowlist/clean-near-match tests; never broad fuzzy substring matching.
- Generated/suggested display names use the same validator. Discoverable
  first/last names retain their separate policy unless combined into a proposed
  public display-name suggestion.
- Writes return `400 {"error":"Choose a name without profanity.","code":"DISPLAY_NAME_PROFANE"}`.
  Availability preserves HTTP 200 and returns the same message/code with
  `available:false`. Never expose matched terms/filter internals.
- Define a separate profanity-only predicate for stored-name remediation;
  `validateDisplayName` also rejects legacy formatting and must not force those
  accounts to rename. Compute `displayNameRequiresRename:true` from only that
  predicate in full/compact auth serializers. Add the field to allowlists and
  mutation responses, invalidate through the existing auth seam after rename,
  and recompute from the stored display name. The bounded auth cache does not
  require a new key version for this computed additive field.
- Route every public-user presentation and cold/warm presentation-cache value
  through a safe helper that substitutes
  `Name unavailable` for profane stored names. Audit race/progress/
  lists, chat, friends/search, leaderboards, referrals/contest, tournaments,
  notifications, persisted giveaway snapshots, race-share names, queued actor
  names, and cached race-list creator/winner fragments; version or invalidate
  affected caches. Owner auth
  payload may retain raw value for editing beside the boolean.
- Capable Flutter places an inescapable rename gate above the authenticated
  root before deep links/shell tabs. Successful server rename removes it.
  Missing/malformed flag is false. Frozen clients ignore the flag but receive
  safe public placeholders and cannot submit new profane names.
- Cover Apple, Google, review-account, provisioning, legacy `/auth/me`, compact
  `/auth/me`, session, and display-name mutation responses. Clear tutorial and
  forced-rename local state on sign-out/account switch.

### R9–R10. Contest readability and sharing ideas

- Use existing surface-aware theme tokens for joined-page OFFICIAL RULES,
  rules title, all section headings, and enabled/pressed/disabled states across
  pre-join/joined entry paths. Exact foreground/background pairs meet WCAG AA
  4.5:1 in both themes and have deterministic tests. No parallel theme or
  one-theme hardcoding.
- Replace suggestion mini-cards with a vertical non-interactive icon-bullet
  list: `Drop it in the group chat`; `Get the family involved`;
  `Show your coworkers you’re better than them`. Remove `Post it on Instagram`.
  Keep heading, encouragement, and actual SHARE YOUR INVITE button. No Ink,
  borders/bubbles, button semantics, or row tap targets; wrap at large text.

### R11. Blocking Shop purchase progress

- While a coin purchase request is unresolved, place one non-dismissible modal
  barrier above the real Shop for accessory, character, and powerup purchases.
  Reuse the visual language of `_PowerupProcessingOverlay`: item/powerup art,
  `PURCHASING`, item name, and `PillButtonSpinner`; announce `Purchasing <name>`
  as an accessibility live region.
- Start only after confirmation and before the HTTP call. Keep it visible through
  authoritative response patch/refresh and balance update, then remove it before
  success/error feedback. Prevent duplicate taps and back dismissal. Ad-unlock
  watching keeps its existing ad UI; show this overlay only for its final unlock
  API call. Clear safely on disposal/account switch/error.

### R12. Recurring custom races

- Add a `RECURRING` toggle to custom race creation, default off. It is unavailable
  for team, seeded, tournament, quick-create, rematch-created, legacy buy-in,
  `NO LIMIT`, scheduled-start, or custom-window races. Recurring races are
  individual, app-funded, zero-buy-in only. Creating with it starts a durable
  series whose first race uses submitted duration/manual-start settings and a
  finite cap of at most 100.
- Auth responses add permanent literal capabilities
  `capabilities.recurringRacesV1:true` and `capabilities.teamChatV1:true`.
  Flutter advertises `recurring_races_v1` and `team_chat_v1` in both duplicated
  `X-Client-Features` header branches and renders each UI only when the matching
  server capability is literal true. A new app against an old backend therefore
  cannot silently create a one-off race or send a private message as public.
- A capable client accepting an invite to a recurring race sends optional
  `subscribeToSeries:true` only after confirmation copy explains future automatic
  enrollment. Missing/false (every frozen client) joins the current occurrence
  only. True without `recurring_races_v1` returns 400 `UPDATE_REQUIRED` and writes
  nothing. A capable acceptance atomically activates the series subscription.
- An account may have at most one active recurring-series subscription across
  creator/member roles, enforced by a locked user-scoped guard and partial unique
  index. Acceptance/creation otherwise returns 409
  `RECURRING_SUBSCRIPTION_LIMIT`. Recurring enrollment never debits or holds user
  coins.
- After each race reaches durable settlement completion, the dedicated
  race-resolution process claims a PostgreSQL `RaceSeriesRenewalJob` and creates
  exactly one next PENDING race with fresh current
  economy/config stamps and automatically enrolls all active subscribers as
  ACCEPTED, subject to current account availability, active
  competition limit, and capacity. No invitation acceptance is
  needed for later occurrences.
- Recurring funded payout eligibility additionally requires at least the
  occurrence's immutable `recurringPayoutMinRawSteps` stamp (2,000 for this
  release), interpreted under its immutable `recurringPayoutPolicyVersion`.
  Below-threshold members remain valid
  participants but receive zero; the funded pool/payout plan uses only qualified
  recipients. This occurrence-stamped rule does not alter non-recurring races.
- `Race.settlementCompletedAt` is stamped only in the final transaction after
  payouts/refunds/reconciliation are durable; that same transaction insert-first
  enqueues the renewal job. Jobs use `QUEUED|RUNNING|SUCCEEDED|FAILED_RETRYABLE|
  FAILED_TERMINAL`, lease token/generation, attempts, retryAt and last error. The
  existing resolution-process scheduler claims this bounded job family through
  its shared work budget after core settlement work; crashes/expired leases leave
  retryable work, never a half-created successor.
- A subscriber skipped for a transient admission reason stays subscribed and is
  reconsidered on the next occurrence; no debt or deferred hold is created.
- Race detail shows `AUTO-JOIN NEXT RACE` for accepted non-creators. Turning it
  off ends future participation only and never removes the user from the current
  race. Turning it back on is not offered directly: the creator may invite that
  user to the current/next occurrence, and accepting reactivates subscription.
- Admission order is creator first, then active subscribers by `subscribedAt,
  userId`, capped by the series' finite capacity. In one target transaction the
  worker locks the series/predecessor/job, establishes target C0, locks sorted
  users/exposure, creates memberships/events, advances the series pointer,
  and terminalizes the job. If the creator fails current admission, no successor
  is created and the series ends with `CREATOR_INELIGIBLE`; other ineligible
  subscribers are skipped for that occurrence but stay subscribed.
- Descendants copy duration and gameplay settings but reset absolute timestamps;
  each is PENDING/manual-start in the creator's current stored timezone. Recurring
  creation rejects scheduled/custom-window inputs with
  `RECURRING_SCHEDULE_UNSUPPORTED` rather than inventing cadence.
- The creator sees `RECURRING SERIES` with `END AFTER THIS RACE`; disabling it
  prevents creation after the current race but does not cancel the current race.
  A series with no active creator subscription also ends after the current race.
  Every stop/terminal path (creator stop, creator ineligible, or current policy no
  longer permitting app-funded zero-buy-in recurrence) atomically closes all
  active series subscriptions so the user-scoped one-active-series fence is
  released for every member.
- New endpoints:
  - `PUT /race-series/:seriesId/subscription` body `{"active":false}` → 200
    `{"seriesId":"id","active":false,"effectiveAfterRaceId":"id"}`.
    Only an accepted subscriber may deactivate; `active:true` is rejected with
  `409 REINVITE_REQUIRED`. Malformed bodies return 400 `INVALID_REQUEST`, an
  unknown/deleted series returns 404 `RACE_SERIES_NOT_FOUND`, and a caller who
  is not that series' accepted subscriber returns 403 `SERIES_ACCESS_DENIED`.
  - `PUT /race-series/:seriesId` body `{"enabled":false}` → 200
    `{"seriesId":"id","enabled":false,"effectiveAfterRaceId":"id"}`.
    Creator only; replays are idempotent. Malformed bodies return 400
    `INVALID_REQUEST`, an unknown/deleted series returns 404
    `RACE_SERIES_NOT_FOUND`, and non-creators receive 403
    `SERIES_ACCESS_DENIED`.
- Add `recurringSeries` to create request as optional boolean, default false for
  frozen clients. When true, a valid UUID `Idempotency-Key` is required; one-off
  legacy creates remain key-optional. Exact replay returns the same race/series;
  conflicting reuse returns 409 `IDEMPOTENCY_KEY_REUSED`. Add defensive response:
  `{"series":{"id":"id","enabled":true,"subscribed":true,"canManage":true}}`
  for successful creator creation. Later viewer-specific reads set `subscribed`
  from that viewer's active subscription and `canManage:true` only for the
  creator; missing/malformed means non-recurring and hides UI. Invalid create
  bodies return 400 `INVALID_REQUEST`; capability absence returns 400
  `UPDATE_REQUIRED`; missing referenced resources return their existing 404;
  the named eligibility/idempotency conflicts above remain stable 409 codes.
- Renewal is idempotent and race-keyed: a unique predecessor link prevents two
  descendants. Establish target C0 before memberships, lock affected funded
  exposure in canonical order, append ordinary membership events, invalidate
  race-list/auth caches after commit, and leave retryable durable work queued.
- Enabled recurring occurrences are not manually rematchable: R2
  `rematchEligible` is false and the endpoint returns 409
  `SOURCE_RECURRING`. A stopped/terminal series occurrence becomes rematchable
  only after no successor exists.
- Overlay viewer-specific `series.subscribed/canManage` after viewer-neutral
  race-list and completed-summary fragments; detail uses narrow viewer/series
  reads. Invalidate affected users' race membership plus viewer overlay state on
  accept, unsubscribe, series stop, renewal, creator terminal failure, and account
  deletion; never place viewer state in shared cached payloads.

### R13. Home service-banner regression

- A valid enabled manual `homeServiceBanner` must render on Home after an admin
  saves it. An active automatic giveaway banner must not suppress it; render the
  service banner first and the giveaway banner second, each once. Tutorial
  previews still suppress the service banner.
- Fix the authoritative cache invalidation/read path after
  `PATCH /admin/settings/home-service-banner`: both update branches invalidate
  the existing versioned shared app-settings cache after commit. Home banner
  assembly bypasses the 30-second process-local map and reads that shared cache,
  with direct PostgreSQL fallback for Redis unset/error. Do not add a parallel
  banner cache or rely on pub/sub convergence across the two HTTP workers.
  Preserve the existing additive response fields, contest-linked capability
  validation, and malformed-data fail-closed behavior.

### R14. Daily Reward prize help and labels

- Restore the existing `?` affordance in the Daily Reward header using the
  retained `_InfoButton`/brand treatment. It opens a readable modal describing
  `COINS`, `ACCESSORY`, and `POWERUP`, including that accessories are equipped
  from inventory and powerups are used in races. It does not expose odds unless
  the existing exact-odds affordance is independently supported.
- Reel tiles and final rewards use explicit `ACCESSORY`/`POWERUP` labels, not the
  ambiguous `ITEM`; coin tiles keep their amount. Preserve R6's accessory-only
  inventory instruction and malformed reward fallback.

### R15. Own and friend race statistics

- Add a `RACE STATS` card to the real Profile tab and public friend profile sheet:
  races competed in, first-place wins, podium finishes (placements 1–3), and
  win rate. Count distinct COMPLETED, non-seeded race memberships with status
  ACCEPTED and `rawSteps > 0`; zero-activity automatic/recurring memberships do
  not pad stats. Forfeited races count as competed only when rawSteps > 0, but
  never as wins/podiums. Wins/podiums additionally require at least two accepted
  competitors and a non-forfeited participant. Team races count placement from
  the participant's persisted semantics.
- Extend existing `GET /steps/stats?view=profile-v1` and
  `GET /friends/:userId/profile` only; preserve `racePodiums`,
  `avgStepsPerDay`, and all legacy meanings. Add to each existing `stats` object:
  `racesCompeted`, `firstPlaceWins`, `podiumFinishes`, and `winRate`.
  `winRate` is a 0.0–1.0 ratio `firstPlaceWins/racesCompeted`, rounded to four
  decimal places; a true zero-race aggregate returns integer zero counts and
  `winRate:0.0`. Missing/null/malformed new fields render unavailable, not zero.
- Public stats follow the existing display-name/review-account discoverability
  policy; the route is not viewer-aware and this feature does not invent block
  authorization. Use the existing indexed PostgreSQL profile aggregate with one
  additional grouped participant query and no new Redis cache/flag initially.
  Do not hydrate races per row. A future cache is out of scope.
- Stats are informational only and never unlock rewards, coins, achievements, or
  admission, preventing recurring-series stat farming from gaining value.

### R16. Enemy-only multiplier nudge notifications

- For team races, the notification resembling `<name> has a 4x step multiplier,
  slow them down!` may target only accepted, non-forfeited participants on the
  opposite team from the boosted participant. Same-team recipients are excluded
  before durable event audience creation. Solo-race behavior is unchanged.
- Missing/malformed team data fails closed for the nudge; never send it broadly.
  Persist actor and recipient team facts in the durable event audience for
  auditability. Test audience facts and projected/provider deliveries, including
  retries.

### R17. Rally Flag stacking error

- If any live `RALLY_FLAG` effect already benefits the caster's team, a new Rally
  Flag use fails atomically with 409
  `{"error":"Your team already has an active Rally Flag.","code":"RALLY_FLAG_ACTIVE"}`.
  Do not consume the held powerup, extend any expiry, add events, or notify.
- Check under C0 inside the use transaction so concurrent casts yield one success
  and one stable error. Update the stacking guide from `EXTENDS` to `BLOCKED`.
  Live means the same race/team with `status=ACTIVE` and
  `startsAt <= now < expiresAt`; the losing attempt writes and consumes nothing.

### R18. Unified activity and chat in regular races

- Use the existing team-race combined `ACTIVITY & CHAT` presentation for regular
  individual races in PENDING, ACTIVE, and COMPLETED states. One chronological
  feed interleaves system activity and user messages with the existing composer,
  paging, retry, delete-own-message, moderation, unread, and cache behavior.
- Do not create a forked solo widget or change backend stream semantics. Demo and
  tutorial race detail reuse the production surface with fake services.
  COMPLETED races show combined history with no enabled composer, matching the
  backend's closed-chat rule.

### R19. Admin-only giveaway creation

- Backend authoritatively applies the existing shared `buildRequireAdmin`
  middleware, backed by `isAdminUser` and configured admin identities, to every
  giveaway draft-creation entry point before validation or writes. A
  non-admin receives 403 `{"error":"Admin access required","code":"ADMIN_REQUIRED"}`;
  unauthenticated remains 401. No contest/audit/banner row may be written.
- Other giveaway read/join/share endpoints remain available according to their
  existing policy. Frontend visibility is not a security boundary.

### R20. Team-only chat

- In team races, add an `ALL` / `TEAM` segmented choice beside the composer and
  feed filter. Default `ALL`; remember selection per race for the mounted screen.
  Regular races show no selector.
- Extend `POST /races/:raceId/messages` with optional `audience:"ALL"|"TEAM"`,
  default `ALL` for frozen clients. `TEAM` requires literal server capability,
  `team_chat_v1`, an ACTIVE team race, and an accepted, non-forfeited team
  participant. A TEAM request without the literal server/client capability
  contract returns 400 `UPDATE_REQUIRED`; a capable request that fails race,
  lifecycle, membership, forfeit, or team eligibility returns 403
  `TEAM_CHAT_UNAVAILABLE`.
  Store the sender's team snapshot on the message. PENDING team chat remains ALL
  only, avoiding history exposure while teams may still change.
- `GET /races/:raceId/messages` and the compact streams endpoint accept optional
  query `audience=ALL|TEAM`; omitted returns ALL only for frozen clients. TEAM
  requires current accepted membership on that team. Responses add `audience`
  and nullable `team`; compact `requested/resolved/streams/chatWatermark/errors`
  are computed for exactly the requested channel and never merge private IDs
  into the ALL watermark.
- Extend message reads additively with `audience` and `team`; TEAM messages are
  returned only to accepted members of that snapshotted team. There is no admin
  or moderation private-read exception. They never enter the opposing team's
  response, cache fragment, notification audience, watermark, or unread count.
  ACTIVE teams are locked; historical team snapshots never rewrite.
- Acquire race C0 inside TEAM send before re-reading race/membership/team and
  writing the message/audience. Make `switchRaceTeam` acquire the same C0 before
  its PENDING mutation. Race creators may delete ALL messages under existing
  policy but may delete a TEAM message only if they are its sender; no admin
  private-read exception is introduced.
- Use versioned cache/watermark identities `USER:ALL`, `USER:TEAM_A`, and
  `USER:TEAM_B` with the existing message-cache TTL and environment prefix.
  PostgreSQL is authoritative on every Redis unset/error. Send/delete invalidate
  only the affected channel plus shared moderation metadata; membership removal,
  forfeit, account deletion, and team switch invalidate both team access
  contexts. Rate limiting counts all USER messages across ALL+TEAM.

### R21. Decoy becomes a rolled powerup

- Remove Decoy from coin/ad Shop catalogs and purchasing eligibility for new
  clients while leaving old purchase endpoints compatible: an old-client Decoy
  purchase with a new idempotency key returns 409 `POWERUP_NOT_FOR_SALE` before
  receipt, coin, or ad-grant mutation and never charges coins. A replay of a
  previously successful purchase remains a successful replay. Apply this to both
  coin and ad-unlock endpoints; grandfather the one currently verified,
  unconsumed Decoy ad grant so it can complete once without accepting new grants.
- Add Decoy to the RARE mystery-box pool with `typeWeight:0.5` and
  `trailingDownweight:0.5`, respecting existing solo eligibility and config
  snapshot rules. Expected six-slot solo probabilities are approximately
  1.7308%, 1.6452%, 1.8387%, 1.0800%, 1.1829%, and 1.4516% (mean 1.4882%).
  Existing held/stash Decoys remain usable; mechanics and 24-hour duration do
  not change. Daily Reward explicitly excludes Decoy.
- Backend-first rollout performs an idempotent active balance-config transition:
  remove Decoy from persisted/default `storeOnlyTypes`, add it to the RARE pool
  with the pinned weights, preserve every historical race/config snapshot, mark
  its Shop catalog row inactive/not-for-sale, and invalidate existing catalog and
  balance-config caches after commit. Do not rely on changing code defaults while
  a persisted config still excludes it.

### R22. Hitchhike icon replacement

- Replace both `assets/images/powerups/hitchhike.png` and
  `hitchhike_thumb.png` with one newly generated, clearly readable right-facing
  pixel-art hitchhiking symbol that matches the established bold-outline powerup
  set. Preserve asset keys and dimensions/usage so no API or old-client contract
  changes.
- Follow the `accessory-art` imagegen/chroma-key pipeline, critique on white,
  verify transparent corners/fringe, and inspect at full icon, thumbnail, stash,
  target picker, activity/chat, and active-effect sizes. No hand-drawn SVG or
  CustomPainter artwork.

## 5. Data model and migrations

- Add `RaceRematchReceipt`: id, requester/source/newRaceId, UUID key, request
  digest, immutable response JSON, and created/completed timestamps. Define
  requester `onDelete:Cascade` and source/new-race `onDelete:Restrict`, unique
  requester+key and newRaceId, and index source. It has no
  worker state, lease, generation, retry schedule, or cancellation workflow:
  receipt, race, participants, outbox events, and response commit together.
- Add nullable indexed `Race.rematchSourceRaceId` and `rematchRootRaceId` self
  references; root is source.root ?? source.id. Add raw partial unique index on
  root where status is PENDING/ACTIVE; completed/cancelled descendants coexist.
  Both lineage self-relations use `onDelete:Restrict`; cleanup deletes
  descendants/receipts before an ancestor and never silently severs a lineage.
- Add `RaceRematchNotificationEpisode`: recipient/root/generation identity,
  latestRaceId, monotonic revision, provider-accepted timestamp, closedAt, and
  created/updated timestamps. Uniqueness is recipient+root+generation; define
  `recipient onDelete:Cascade`, `rootRace onDelete:Restrict`, and
  `latestRace onDelete:SetNull`, so deleting one descendant cannot erase lineage
  spam protection. Add a partial unique index on recipient+root where
  `closedAt IS NULL` to enforce one open episode. Race completion closes current
  open episodes transactionally; projector updates are revision-CAS writes.
- Add nullable `User.shopTutorialCompletedAt`; no backfill. Serializers emit
  explicit null after migration.
- Add `RaceSeries` (creator, enabled, canonical settings snapshot, current race,
  generation, timestamps), nullable `Race.seriesId` + `seriesGeneration` +
  `seriesPredecessorRaceId` + `settlementCompletedAt`, and
  immutable nullable `recurringPayoutMinRawSteps` and
  `recurringPayoutPolicyVersion` occurrence stamps, and
  `RaceSeriesSubscription` (series/user, active, subscribed/unsubscribed
  timestamps). Unique series+generation, predecessor, and series+user constraints
  make renewal/subscription idempotent. A raw partial unique index on `userId`
  where `active=true` enforces the account-wide one-active-series invariant.
- Add `RaceSeriesCreateReceipt` keyed by creator+UUID with request digest and
  immutable race/series result. Add `RaceSeriesRenewalJob` keyed by predecessor
  with state, attempt, lease token/generation/expiry, retry/error and terminal
  timestamps. All are additive with explicit FK cleanup and bounded indexes.
- Add `RaceMessageAudience` (`ALL|TEAM`) plus nullable snapshotted
  `RaceMessage.team`; existing rows backfill/default to ALL. Index
  race+audience+team+createdAt for bounded channel reads.
- Race statistics require no counter columns: derive from authoritative completed
  participant rows with a covering user/status/placement/race index. This release
  reads PostgreSQL directly and adds no stats cache or invalidation path.
- No name/reroll migration. Rename status uses profanity-only policy and
  `rerolledAt` exists. Version auth/presentation/race-fragment caches as needed.

## 6. Tests-first plan

### Backend integration tests (confirmed local/test Postgres only)

1. Real HTTP rematch proves copied/reset/recomputed fields, accepted creator,
   cohort invites, durable events, transaction rollback, idempotent/concurrent
   replay, any-participant auth, one-live descendant, unlimited sequential use,
   eligibility errors, cohort safety, team capability, current holds/economy,
   expiry, lineage-fork prevention, cache invalidation, no completed-summary
   invalidation, an inert generation-zero C0 row but no runnable job/reason,
   100-racer boundary and 101-racer rejection, concurrent receipt conflict
   recovery, cancellation-loop notification coalescing/reset-after-completion,
   out-of-order projector retry rejection, already-provider-accepted behavior,
   Redis-unset operation, and frozen-client invite acceptance. Extend the
   structural C0/writer inventory guard to include the rematch command.
2. Real display-name endpoints reject direct/case/separator/leetspeak cases and
   allow reviewed near-matches. Prove domain-command enforcement, clean
   suggestions, profanity-only remediation versus legacy formatting, compact/
   full flags, cold/warm caches/snapshots, placeholders, and rename clearing.
3. Shop completion is idempotent and proves missing/null/timestamp semantics
   across full/compact/provisioning/auth cache paths.
4. Reroll after reveal works once; concurrency with use/discard/race end proves
   grant, row/config update, and audit event commit together or none.
5. Existing 2026-08-28b Stealth tests remain unchanged and pass, including IDs
   and finished-racer unmasking. Current forfeit tests also pass: forfeited rows
   remain absent while their frozen steps continue contributing to team totals.
6. Recurring-race HTTP/lifecycle tests cover create off/on, invite acceptance
   subscription, exactly-once renewal under concurrent/retried completion,
   opt-out/current-race preservation, creator series stop, reinvite/reactivation,
   team/paid/unlimited/scheduled rejection with zero writes, concurrent
   one-subscription enforcement and release on every terminal path, unavailable/
   limit/capability skips, 1,999-vs-2,000 raw-step payout eligibility, no hold or
   debit, policy drift away from app-funded zero-buy-in producing no successor
   and a terminal outcome, fresh economy stamps, C0 ordering, cache invalidation,
   and old-client defaults.
7. Home integration tests save the service banner through the admin endpoint and
   immediately read it through both cache modes/HTTP processes, with and without
   an active giveaway; both valid banners appear in the response.
8. Public/self profile HTTP tests prove exact aggregate definitions, privacy,
   index-bounded direct-PostgreSQL query behavior, and missing-field compatibility.
9. Notification integration tests prove team multiplier nudges exclude allies;
   Rally Flag concurrency proves one success/one 409 and zero losing-side writes.
10. Giveaway creation tests use real auth for unauthenticated/non-admin/admin and
    assert zero unauthorized database/audit/banner mutations.
11. Team-chat integration tests prove write/read/push/cache/watermark/unread
    isolation, snapshotted team history, shared rate limiting, denial of private
    TEAM reads to admins/nonmembers, and frozen-client ALL defaults.
12. Decoy roll/purchase tests prove exact 0.5 type weight/0.5 trailing
    downweight and position probabilities, canonical snapshot parity, Daily
    Reward exclusion, new-key no-sale/no-charge, successful receipt replay, the
    single grandfathered verified grant, and continued use of existing inventory.

### Frontend widget/integration tests

1. Real individual/team detail plus demo/tutorial fixture: hidden opponent has
   no effect/identity clue; own and finished rows remain visible.
2. Result popup/completed detail: eligible/ineligible/partial/loading/error/
   multi-result rematch placement, binding, lock, navigation, fail-close.
3. Personal tournament cards in all states and tutorial `RacesTab`: no avatar/
   indent; public cards unchanged. Settings exact handles/URLs.
4. Held sheet eligibility matrix and both configured/omitted platform ad units;
   reveal-time reroll unchanged. Daily reward item/coin/malformed matrix.
5. Shop absent/null/timestamp states, completion/no replay, Settings replay,
   scrolling/overlay collision, account switch/sign-out, preview suppression,
   and delayed same-account auth payload delivery while Shop stays mounted.
6. Root/deep-link rename gate for true/false/missing/malformed flags and server
   results. Contest themes/states/text scale/contrast/bullets/semantics.
7. Never weaken, skip, or delete protected tests.
8. Shop tests hold each accessory/character/powerup API future and verify one
   blocking branded overlay, dismissal prevention, success/error/disposal/account
   switch cleanup, and ad-unlock final-call placement.
9. Creation/detail tests cover recurring toggle states and participant/creator
   controls; Home tests render service+giveaway in order; Daily Reward tests
   restore `?`, modal copy, and explicit tile/reveal labels.
10. Profile/public-profile tests cover loading/data/unavailable stats at narrow
    width and large text. Race detail tests prove solo combined feed parity and
    team ALL/TEAM filtering/composer state without leaking messages.
11. Hitchhike asset tests retain keys and transparent readable rendering at all
    production sizes; manually inspect both platforms per the UI plan.

## 7. Backward compatibility and rollout

- Additive migration/backend first, then verify/build iOS and Android. Hide new
  UI when capability/eligibility/support is absent. Frozen clients ignore new
  fields/endpoints and accept ordinary invites; backend protects name writes
  and public presentation for all clients.
- Keep shared race cache fragments viewer-neutral; overlay rematch eligibility
  afterward. Keep the new completed-summary cache immutable for descendant
  creation, use documented membership invalidation, and test Redis on and unset.
- Preserve exactly two production HTTP workers plus the current dedicated
  resolution and cron roles; no process-topology or database-pool capacity
  change is authorized. Any production deploy/write requires explicit,
  in-the-moment confirmation.
- Preserve the resolution process's current shared work budget and queue reason
  registry; rematch adds neither a resolution reason nor a worker concurrency
  setting.
- Do not start/reload staging without explicit in-the-moment authorization; shut
  it down after authorized use. Hitchhike is the only new art asset.
- New Hitchhike art ships in both app binaries under an existing asset key, so no
  catalog activation or production data write is needed. All backend migrations
  and additive contracts deploy before the app; recurring/team-chat UI fails
  closed against an older backend. Frozen apps treat recurring races/messages as
  ordinary races/ALL chat and cannot bypass backend giveaway/Rally/Decoy rules.

## 8. Acceptance criteria / definition of done

- R1–R22 pass on both platforms with version-skew coverage; tests were written
  first; Flutter analyze and relevant frontend/backend suites are green on a
  confirmed test DB; configured and omitted ad units are covered.
- Required architect, game-economy, UI-placement, and later code reviews occur.
- No implementation starts until explicit owner approval.

## 9. Owner decisions (locked)

1. Any former accepted participant may initiate; sequential rematches unlimited.
2. Rematch immediately creates the equivalent race and invites former roster.
3. Equip instruction is accessory-only.
4. Shop tutorial covers every incomplete account and has Settings replay.
5. Existing profane names force rename next capable-app open.
6. Instagram destination is `instagram.com/Bara.steps.app`.
7. Recurring invitation acceptance opts the participant into future occurrences;
   participant opt-out affects only future races, and creator stop ends renewal
   after the current race.
8. Manual service and automatic giveaway banners may coexist, service first.
9. Race stats exclude seeded races and expose competed/wins/podiums/win rate.
10. Team chat defaults to ALL and TEAM messages remain private to the sender's
    snapshotted team.
11. Rally Flags reject stacking; Decoy leaves Shop and joins mystery-box rolls.

## 10. Revision log

- **Original workflow (2026-09-01):** two gap passes, owner interview, and
  architect/economy/UI reviews completed.
- **Current-code exploration (2026-09-03):** corrected Stealth to the shipped
  contract; remapped rematch to current C0/durable domain-event seams; added
  projection/cache rules; recognized Android
  reroll support and the atomicity repair; routed tutorial/name fields through
  current auth serializers/caches.
- **Fresh-eyes pass 1 (2026-09-03):** reconciled missing-vs-null Shop support,
  overlay/account switching, source/new-race/idempotency locks, cohort invite
  exceptions, and removed contradictory completed Stealth masking.
- **Fresh-eyes pass 2 (2026-09-03):** added frozen-client public-name safety,
  separated discoverable/display-name policy, moved viewer eligibility outside
  shared cache, covered both-platform ad configurations, and aligned operations
  with current HTTP/resolution/cron topology. Zero product questions remain.
- **Refreshed architect review (2026-09-03):** verdict `REVISE`. Moved invite
  fan-out to durable existing C0 work; defined pending/terminal receipt states,
  lineage-wide partial uniqueness and scheduling/team semantics; removed an
  ambiguous auth capability; required bounded eligibility queries, thin module
  routes, cache contract versioning/cold-start state, profanity-only remediation,
  snapshot sanitization, and atomic reroll audit writes. All REQUIRED findings
  are incorporated.
- **Refreshed economy review (2026-09-03):** verdict `SOUND WITH CHANGES`.
  Required lineage-wide fork prevention, durable creation/invite admission,
  current active-limit/economy enforcement and monitoring, canonical C0 reroll
  lock/CAS/audit atomicity, and explicit delayed-position coverage. All five
  requirements are incorporated; `docs/economy.md` was refreshed by the reviewer.
- **Post-review gap pass 1 (2026-09-03):** reconciled the async C0 worker with
  the owner's immediate-create intent: HTTP commits and returns the new race at
  202 while durable fan-out proceeds, with immutable planned versus terminal
  invite results. Rechecked retry, rollback, queue ownership, and navigation.
- **Post-review gap pass 2 (2026-09-03):** checked lineage uniqueness against
  sequential reuse, ensured rate admission occurs before creation, separated
  stored-name profanity remediation from full write validation, required warm
  snapshot/cache sanitation, and verified all manual-plan risks are reflected.
  Zero unresolved product questions remain.
- **Architect compliance recheck (2026-09-03):** defined retryable versus
  terminal worker failures, canonical cancellation/refund and immutable replay,
  plus post-commit membership-cache invalidation whose Redis failure cannot
  roll back PostgreSQL. No architect-required issue remains after this fold-in.
- **Economy compliance recheck (2026-09-03):** verdict upgraded to `SOUND`; no
  required economy issue remains.
- **Current-code exploration (2026-09-06):** reconciled the spec with the
  specialized generation-fenced resolution queue, append-only large-race
  intake, bounded race-bootstrap summaries, the new versioned completed-race
  summary cache, and concurrent forfeited-participant presentation work.
- **Fresh-eyes pass 1 (2026-09-06):** removed the now-inappropriate use of
  `RaceResolutionJobV2` for invitation fan-out and replaced the receipt state
  machine/worker workflow with one idempotent PostgreSQL transaction plus the
  existing domain-event outbox. Removed invented rematch rate limits that
  conflicted with the owner's unlimited-sequential decision.
- **Fresh-eyes pass 2 (2026-09-06):** separated membership invalidation from
  immutable completed-summary caching, prevented rematch eligibility from
  expanding bounded bootstrap reads, preserved forfeited-row hiding and frozen
  team totals, removed an unnecessary auth-cache version bump, and tightened
  exact replay/error/skip contracts. Zero product questions remain.
- **Refreshed economy review (2026-09-06):** verdict `SOUND WITH CHANGES`.
  Confirmed current hold/admission/payout stamps and deferred-reroll atomicity;
  replaced an unsupported assumption about global request limiting with durable
  recipient+lineage notification-episode coalescing across cancellation loops.
- **Refreshed architect review (2026-09-06):** verdict `REVISE`. Required the
  target race's inert generation-zero C0 row, a hard synchronous cohort bound,
  a concrete durable notification-episode/projector contract, outer recovery
  from concurrent receipt uniqueness conflicts, and delayed same-account auth
  reevaluation for an already-mounted Shop. All REQUIRED findings were folded
  into the API, data, frontend, and tests-first plans for compliance recheck.
- **Refreshed UI-placement review (2026-09-06):** confirmed all prior mirrors
  and insertion points remain current; added forfeited-row checks across active,
  completed, team, individual, and paged detail without changing the remaining
  checklist.
- **Architect compliance recheck (2026-09-06):** verdict `APPROVE`; no REQUIRED
  findings remain. Exact referential actions and the one-open-episode partial
  uniqueness invariant were pinned after the recheck suggestions.
- **Economy compliance recheck (2026-09-06):** verdict upgraded to `SOUND`; the
  durable notification episode closes cancellation/recreation spam without
  limiting legitimate sequential rematches, and no required economy issue
  remains.
- **Additional-request exploration (2026-09-06):** mapped Shop purchase calls to
  the existing powerup-processing overlay treatment; found service/giveaway
  coexistence and cache seams; located retained but unwired Daily Reward info
  widgets; mapped profile, durable message streams/caches, Rally/Decoy/Hitchhike
  mechanics, notification audiences, and giveaway administration paths.
- **Additional fresh-eyes pass 1 (2026-09-06):** made recurring acceptance an
  explicit durable subscription, separated participant opt-out from creator
  series shutdown, defined current-race preservation/reinvite behavior, added
  exactly-once lifecycle/C0/economy rules, and specified old-client behavior.
- **Additional fresh-eyes pass 2 (2026-09-06):** bounded stats and chat reads,
  snapshotted team-message privacy, shared channel rate limiting, immediate
  cross-worker service-banner visibility, Rally concurrency rollback, Decoy
  purchase compatibility, purchase-overlay lifecycle cleanup, and Hitchhike
  asset verification. Owner pre-approved recommendations; zero open product
  questions remain before specialist review.
- **Expanded architect review and compliance recheck (2026-09-06):** corrected
  creator/viewer series response semantics and stable errors; pinned immutable
  recurring payout stamps and the account-wide active-subscription index;
  removed the stats-cache contradiction and every admin TEAM-read exception.
  Final verdict `APPROVE`; no REQUIRED or suggested issue remains.
- **Expanded economy compliance recheck (2026-09-06):** final verdict `SOUND`;
  exact recurring anti-farm bounds, Decoy balance behavior, replay, and
  grandfather handling have no remaining required changes.
- **Expanded UI-placement review (2026-09-06):** extended the manual plan across
  all R1–R22 real, tutorial/demo, theme, platform, text-scale, privacy, catalog,
  overlay, and icon surfaces; implementation risks are recorded below.
- **Implementation and post-fix review (2026-09-06):** backend-first contract
  lock, backend/frontend implementation, protected test updates, concurrency and
  privacy hardening, and release-gate cleanup completed. Final code-review verdict
  `APPROVE`; backend unit 3,353/3,353, affected backend integration suites green,
  frontend 2,937/2,937, `flutter analyze` clean, and both platform builds succeed.

## 11. Manual UI-placement test plan

**Manual UI-Placement Test Plan — 2026-09-06 feature batch refresh**

*Elements under test:* Stealthed opponents lose all identity-revealing effect badges on active race-detail surfaces.

*Elements under test:* Forfeited participants are removed from active and completed race-detail presentation without leaving stale rows, gaps, or effect badges.

*Elements under test:* REMATCH is added to each eligible finished-race result and to completed race detail between the result/payout area and final standings.

*Elements under test:* The leading racer avatar and its reserved space are removed only from personal tournament cards.

*Elements under test:* Existing Instagram and X rows remain in COMMUNITY with updated handles.

*Elements under test:* REROLL is added below USE and DISCARD in an eligible held-powerup action sheet.

*Elements under test:* Daily powerup/accessory reveals gain type labels; only accessories gain the inventory instruction.

*Elements under test:* A four-beat spotlight tutorial is added over the real Shop, plus VIEW SHOP TUTORIAL in Settings.

*Elements under test:* A mandatory rename gate is added above every authenticated destination for affected accounts.

*Elements under test:* Referral contest rule links/headings remain in place and readable without moving or disappearing in either theme.

*Elements under test:* Two button-like share-idea cards are replaced by three stacked, non-interactive icon bullets above SHARE YOUR INVITE.

*Checklist*

1. **Active individual race detail — real screen**
   - **Get there:** On iOS and Android, open an active individual race containing one opponent with active Stealth and visible effects on other racers.
   - **Verify:** The hidden opponent remains in standings as `???`, with no effect badge, avatar/accessory clue, or duplicate clue elsewhere in the row; ordinary racers retain their effect badges in the existing position. Check both themes, then repeat at large text scale and narrow-phone width.

2. **Active team race detail — real screen**
   - **Get there:** Open an active team race containing a stealthed opponent, active team/participant effects, and a forfeited participant whose frozen steps still contribute to the team total.
   - **Verify:** No effect icon or rail identifies the hidden opponent. The forfeited participant is absent from the course, team leader cards, two-column team roster, grouped standings, and effect rails, with no blank row or avatar-sized gap left behind. Visible teammates and opponents retain their existing elements and ordering, and each team summary remains in its existing position.

3. **Forfeited rows — individual, completed, and paged detail**
   - **Get there:** Open an active individual race, completed individual race, and completed team race whose payload includes a forfeited participant. Where available, use a paged standings response whose current page contains that participant.
   - **Verify:** The forfeited participant appears nowhere in the course, podium/winner presentation, team winner board, or standings, and leaves no blank plank, separator, effect badge, or unexplained vertical gap. Remaining racers close up in display order. On paged standings, the pager remains once below the visible rows and does not overlap or jump into the removed row’s space.

4. **Race-detail tutorial mirrors**
   - **Get there:** Fresh account → onboarding demo race; then Settings → VIEW TUTORIAL → reach the race-detail powerups beat.
   - **Verify:** The demo and tab-tutorial previews still render the production race-detail layout. The tab tutorial’s seeded stealthed row has no identifying effect badge. The powerups spotlight still rings the inventory area, and neither preview gains an extra badge or an empty badge-sized gap.

5. **Finished-race popup — one result**
   - **Get there:** Launch with one unseen, eligible completed custom race and a 50-coin rewarded-ad offer.
   - **Verify:** REMATCH appears in the result action area above the ad CTA; it is below the race placement/payout content and appears only once. START YOUR NEXT RACE/CONTINUE and NICE remain below the result/ad area in their prior order.

6. **Finished-race popup — multiple results**
   - **Get there:** Launch with two or more unseen completed races, mixing eligible custom races with an ineligible seeded or tournament race.
   - **Verify:** Each REMATCH control is visually attached to its own eligible race rather than presented as one ambiguous batch action; ineligible cards have neither a button nor a blank reserved gap. The shared ad panel remains after the result-card list, and no rematch control is duplicated there. Scroll the full popup at large text scale.

7. **Completed race detail**
   - **Get there:** Races → COMPLETED → open an eligible custom individual race, then an eligible team race; also open one ineligible completed race.
   - **Verify:** REMATCH appears after the winner/podium and payout summary and immediately before FINAL STANDINGS. It does not appear in the hero, activity/chat, or old share-action position. A forfeited participant is absent from the hero, winner/podium or team-winner presentation, and final standings without leaving a stale gap above or below REMATCH. The ineligible race has no button or unexplained gap. Repeat on narrow iOS and Android screens.

8. **Personal tournament cards**
   - **Get there:** Races → view pending, active/live, eliminated, and champion personal tournament cards.
   - **Verify:** No capybara/racer avatar appears at the leading edge and no 48px avatar indentation remains; tournament name, bracket/status chip, countdown, inventory rail, favorite control, placement/prize, and chevron reflow into the available width. Confirm the public/featured tournament cards elsewhere retain their existing composition.

9. **Tournament card — tab tutorial preview**
   - **Get there:** Settings → VIEW TUTORIAL → reach the Races preview and scroll to TOURNAMENTS if needed.
   - **Verify:** The reused `RacesTab` tournament card also has no leading avatar or stale gap; the race-card and mystery-box spotlights still target their intended race elements, not the reflowed tournament card.

10. **Settings community and tutorial rows**
   - **Get there:** Profile → Settings on both platforms.
   - **Verify:** COMMUNITY remains between HELP & LEGAL and ABOUT US; Instagram and X remain two separate rows in the same order with their updated handles. VIEW SHOP TUTORIAL appears alongside the existing VIEW TUTORIAL help action, not inside COMMUNITY or ACCOUNT. Check narrow width and large text for wrapping without row overlap or duplication.

11. **Held-powerup action sheet — eligible**
    - **Get there:** Open an active race with an eligible, base-level, box-origin held powerup; tap its inventory slot on builds with the platform’s reroll ad unit configured.
    - **Verify:** The sheet orders actions USE, DISCARD, then REROLL, with consistent full-width alignment and spacing. REROLL is not placed in YOUR STASH, the inventory rail, or the reveal screen. Repeat for a non-upgradeable powerup and an upgradeable powerup whose USE area contains tier choices.

12. **Held-powerup action sheet — absent states and mirrors**
    - **Get there:** Repeat with an already-rerolled/ineligible item and with the reroll ad unit omitted on both iOS and Android; also inspect the onboarding demo race and tab-tutorial race-detail preview.
    - **Verify:** REROLL is absent without leaving a blank action-sized gap; USE/DISCARD retain their former placement. Demo/tutorial fixtures do not expose a live REROLL control, and the powerups spotlight remains aligned. Existing reveal-time single- and multi-box reroll controls remain in their original locations.

13. **Daily reward reveal**
    - **Get there:** Open Daily Reward with controlled outcomes for a valid powerup, valid accessory, coins, and fallback/malformed reward.
    - **Verify:** POWERUP appears with the powerup name/art and no equip instruction. ACCESSORY appears with the accessory name/art and `Go to your inventory to equip this item` directly beneath it. Coin/fallback states contain neither label nor instruction. Existing extra-spin and dismissal actions remain below the reward content. Repeat in both themes, narrow width, and large text.

14. **Automatic Shop tutorial**
    - **Get there:** Use an authenticated account with Shop tutorial supported but incomplete; tap Shop for the first real visit after launch.
    - **Verify:** The tutorial overlays the real Shop only after its layout is visible. In order, the spotlight rings STORE/INVENTORY, category pills, dressing-room stage, and product grid/card. Each target is scrolled fully onscreen before the ring is measured; NEXT/BACK/close chrome stays inside safe areas and does not cover the highlighted control at narrow width or large text.

15. **Shop tutorial suppression and replay**
    - **Get there:** Run the general onboarding/tab tutorial, then visit Shop with a completed account; finally use Settings → VIEW SHOP TUTORIAL.
    - **Verify:** The Shop walkthrough does not launch inside either preview/tutorial or automatically for the completed account. Settings replay navigates to the real Shop and shows exactly one overlay above it. Closing or completing replay returns to a usable Shop with no duplicate overlay. Check both themes and both platforms.

16. **Mandatory rename gate**
    - **Get there:** Sign in with an account marked for rename and launch normally; repeat from a race/referral deep link and when an unseen-results popup would otherwise open.
    - **Verify:** The rename gate is the topmost authenticated surface before shell tabs, deep-linked content, results modals, tutorials, or Shop overlays. No underlying action is exposed around its edges or duplicated behind it. After a successful rename, the intended destination appears normally and the gate is gone. A clean account has no reserved gate space.

17. **Referral contest dashboard**
    - **Get there:** Referral contest → joined dashboard in each app theme; test open and sharing-closed states.
    - **Verify:** OFFICIAL RULES remains at the bottom of the dashboard content and is not clipped, hidden behind bottom chrome, or moved into the share list. The three sharing ideas appear as a vertical icon-bullet list in this order: group chat, family, coworkers. The old two bubble/card shapes and Instagram suggestion are absent. SHARE YOUR INVITE remains the only button immediately below the ideas area.

18. **Official rules page**
    - **Get there:** Open rules from both pre-join contest overview and joined dashboard, in both themes.
    - **Verify:** The OFFICIAL RULES title and every section heading remain directly above their matching body section; none disappear, overlap icons/body copy, or move into the previous section. Scroll through the complete page at large text scale and narrow width.

19. **Referral surfaces at large text and wider layout**
    - **Get there:** Repeat the joined dashboard and rules page at the largest supported text scale, then on a wide device/tablet.
   - **Verify:** All three idea bullets wrap vertically without becoming bubble-like tap targets; the encouragement and SHARE YOUR INVITE remain below them. Rules headings stay attached to their content and all bottom actions remain reachable.

20. **Blocking Shop purchase overlay**
    - **Get there:** Confirm delayed coin purchases for an accessory, character, and powerup, then delay the final API call after an eligible ad unlock.
    - **Verify:** One non-dismissible modal barrier covers the full Shop above sheets, cards, navigation, and tabs, showing the correct art, PURCHASING, item name, and spinner. It appears only during the authoritative purchase/unlock call, never stacks with the tutorial, and clears before success/error feedback and on disposal/account switch.

21. **Recurring toggle — creation and exclusions**
    - **Get there:** Open normal custom CLASSIC creation, then team, bracket, seeded, quick-create, rematch-created, scheduled/custom-window, NO LIMIT, and demo creation variants.
    - **Verify:** RECURRING is one default-off customization toggle only on eligible individual, app-funded, zero-buy-in, finite custom creation. Excluded variants leave no blank card and existing spotlight anchors/order remain intact.

22. **Recurring participant and creator controls**
    - **Get there:** Open pending, active, and completed recurring occurrences as a non-creator subscriber and as creator; compare non-recurring and tutorial/demo detail.
    - **Verify:** A non-creator sees AUTO-JOIN NEXT RACE once and opt-out changes only future participation. The creator instead sees RECURRING SERIES with END AFTER THIS RACE. Controls remain outside current-race leave/cancel, payout, standings, and feed sections; non-recurring and preview screens have no section or gap.

23. **Dual Home banners**
    - **Get there:** Render Home with service-only, giveaway-only, both, neither, and malformed configurations, then open the Home tutorial preview.
    - **Verify:** Valid banners coexist exactly once in service-then-giveaway order, retain distinct taps, and collapse without placeholders when absent. Tutorial preview suppresses both without shifting home.steps or home.shop spotlight targets.

24. **Daily Reward header and prize help**
    - **Get there:** Open Daily Reward before and after claiming, tap the restored header `?`, and exercise powerup, accessory, coin, malformed, and reel `???` outcomes.
    - **Verify:** The header remains aligned and the help modal explains COINS, ACCESSORY, and POWERUP vertically within safe areas. Reel/final rewards use explicit type labels; accessory alone shows the inventory instruction; coin and `???` states are not mislabeled.

25. **Own Profile race statistics**
    - **Get there:** Open Profile with valid, unavailable/malformed, loading, and error stats, then the Profile tutorial preview.
    - **Verify:** One RACE STATS card shows the four values without replacing STEP CALENDAR, STATS, or RACE PODIUMS. Missing data does not fabricate zeroes, and the preview uses a fixture or compact unavailable state without a live request.

26. **Friend/public Profile race statistics**
    - **Get there:** Open the shared public-profile sheet from Friends, search/request, leaderboard, race standings, and tournament/ranked standings.
    - **Verify:** One RACE STATS card appears after existing identity/stat content and before relationship actions. The sheet remains scrollable/dismissible and missing data renders the intended unavailable state rather than a gap.

27. **Unified individual activity/chat**
    - **Get there:** Open pending, active, and completed regular individual races with mixed events/messages, plus onboarding demo and tab-tutorial detail.
    - **Verify:** One chronological combined timeline replaces separate ACTIVITY/CHAT tabs. Older loading and the composer retain their existing edges; completed history is read-only. Demo/preview use fake data and never restore the old tabs or call live services.

28. **Team ALL/TEAM selector and privacy placement**
    - **Get there:** Open pending, active, and completed team races as Team A and Team B accepted members; compare individual, spectator/nonparticipant, forfeited, and admin views.
    - **Verify:** One fixed ALL/TEAM selector controls both feed and composer audience, defaults ALL, and never overlaps feed/composer/unread/load-more. Individual races have no gap; unauthorized viewers have no usable TEAM composer; TEAM messages appear only to the matching accepted team.

29. **Decoy removed from Shop**
    - **Get there:** Inspect all Shop powerup catalog/detail/filter and coin/ad-unlock views.
    - **Verify:** No Decoy tile, sheet, action, or blank grid cell remains; other items reflow. Existing held Decoys remain visible and usable in inventory/stash.

30. **Decoy roll/reward surfaces**
    - **Get there:** Produce Decoy through single-box, multi-box, and demo box flows; inspect Daily Reward.
    - **Verify:** Decoy appears as an ordinary mystery-box result with its real icon/name and no Shop affordance, remains distinct from filler `???`, and stays excluded from Daily Reward. Existing attack/effect/history layouts remain unchanged.

31. **Hitchhike art — full and thumbnail**
    - **Get there:** Inspect full reveal/detail and compact mystery-box thumbnail presentations.
    - **Verify:** The same right-facing symbol is recognizable, centered, transparent at corners, unclipped, and free of the old artwork at both sizes.

32. **Hitchhike art — inventory, targeting, effects, and timeline**
    - **Get there:** Hold/use Hitchhike, open its target picker, activate it, and inspect stash, solo/team effect trays, participant status, combined feeds, and completed history including demo fixtures.
    - **Verify:** Full/thumb assets remain readable without changing row, tray, target, or message geometry and never fall back to a missing image.

33. **Cross-platform, theme, and accessibility sweep**
    - **Get there:** Exercise every changed real screen on iOS and Android, in both themes, narrow width, and largest supported text scale.
    - **Verify:** All new controls, cards, labels, banners, overlays, selectors, and icons remain reachable, ordered, within safe areas, and non-overlapping; spotlight targets are fully onscreen before measurement.

*Surfaces confirmed unaffected:* Public/featured tournament cards use separate builders; their avatars and layout should remain unchanged.

*Surfaces confirmed unaffected:* `RacesTab` reimplements compact inventory/effect rails, but deferred REROLL belongs only to the race-detail held-item sheet, so race-list cards should not gain an action.

*Surfaces confirmed unaffected:* Box-opening screens retain the existing reveal-time reroll and are not hosts for the new deferred action.

*Surfaces confirmed unaffected:* The daily onboarding intro is separate from `DailyRewardScreen`; it should not gain reward-type labels.

*Surfaces confirmed unaffected:* Referral contest overview does not render joined-dashboard sharing ideas; only its route into the shared rules page is relevant.

*Surfaces confirmed unaffected:* Demo race and tab tutorial use active race data, so completed-detail and finished-results REMATCH controls should not appear there.

*Surfaces confirmed unaffected:* Current demo-race and tab-tutorial fixtures do not set `forfeitedAt`; they remain useful Stealth/powerup mirrors but do not exercise forfeited-row removal.

*Risks found while planning:* The results popup currently has one batch-wide ad panel after all `_ResultCard`s, while REMATCH must be bound to an individual race. “Above the ad CTA” is ambiguous for multiple results; the implementation needs per-card visual ownership without making one rematch look applicable to the whole batch.

*Risks found while planning:* Completed detail currently moves directly from winner/podium to FINAL STANDINGS. The new button needs an explicit insertion point between those sections and must not accidentally land inside the standings visibility key.

*Risks found while planning:* Shop targets currently have local constant `Key`s, not externally supplied `GlobalKey` anchors like the existing tutorial previews. The Shop-owned overlay must obtain measurable contexts and scroll before measuring, especially for the product grid.

*Risks found while planning:* The general tutorial already spotlights the Home Shop entry. The dedicated walkthrough must be suppressed in preview/demo navigation and must not stack with the existing spotlight overlay.

*Risks found while planning:* The tab-tutorial fixture now includes a stealthed participant, making it a useful regression surface; removing or simplifying that fixture would hide the original identity-leak class.

*Risks found while planning:* `demoMode` currently removes DISCARD from the held-powerup sheet. The new REROLL must also stay absent in demo/tutorial fixtures so a fake tutorial cannot expose a real ad/mutation action.

*Risks found while planning:* A root-level forced-rename gate can collide with results, deep links, onboarding, and Shop tutorial overlays unless it wins presentation order before those routes are opened.

*Risks found while planning:* The current forfeited-row change filters several race-detail renderers independently. Active course, team cards, team columns, completed hero, podium/winner board, grouped standings, and the shared standings list must remain visually consistent; a missed renderer could expose a forfeited racer or leave a stale gap. Paged standings intentionally preserve the server-loaded count for navigation even when a row is hidden, so pages containing forfeited racers may show fewer visible planks and deserve a device check.

*Expanded-plan risks:* Shop now has three mutually exclusive top layers (tutorial, confirmation sheet, purchase overlay); accessory/character sheets and powerup purchase paths must mount the barrier at the same navigator level. Recurring participant opt-out and creator shutdown must never render together or imply mutation of a completed occurrence. Home currently suppresses service when giveaway exists and must remove both suppression points. Profile tutorial fixtures need explicit race-stat handling. The combined-feed selector must be singular and must bind both read and send audience. Removing Decoy must filter only Shop eligibility, not shared render/behavior registries. Hitchhike's separately sized full/thumb assets must depict the same symbol without naive blurry scaling.
