# Feature and bug batch — 2026-08-28

## Status

Approved and implemented across frontend and backend. Required architecture,
economy, UI-placement, and combined code reviews are complete; the final review
reported no blockers, issues, or nits. Frontend analysis, all Flutter tests,
both platform compilation checks, backend unit tests, feature/relevant HTTP
integration suites, Prisma validation, and runtime-control checks are green.
Production has not been deployed; that remains a separate in-the-moment
authorization.

## Summary and user stories

This batch removes misleading race-admission wording, replaces the remaining
funded-only membership ceiling with one understandable admin-configurable active
competition limit, repairs several small-screen UI defects, makes the Home step
count honest while HealthKit/Health Connect is still loading, adds a Decoy-trigger
notification, repairs mystery-box progress and Hitchhike credit, and shows a
requester's real name on friend requests.

As a racer:

1. I can join free or funded races until I reach one clear active-competition
   limit, and the rejection tells me the actual limit rather than mentioning
   funded exposure.
2. I can read and dismiss the Daily Reward popup comfortably on small phones.
3. The Home Daily Reward and Shop actions look like equal members of the same
   row, with readable text and matching depth.
4. I see a loading treatment instead of a false `0` while today's device steps
   are unresolved.
5. If my Decoy is consumed by an attack, I receive a notification whose tap
   opens the race.
6. Team-race activity sentences and the next-box progress sentence are fully
   readable.
7. Hitchhike copies the target's eligible in-window score change at the promised
   1:1 rate instead of lagging behind because only closed, uploaded sample
   buckets were counted.
8. A friend request shows the requester's first and last name as well as their
   handle, so the recipient can identify them.

## Current implementation evidence

### Race admission

- Backend `src/modules/races/services/fundedExposure.js:17` hard-codes
  `MAX_FUNDED_COMPETITION_MEMBERSHIPS = 5`.
- The same service counts only accepted, unfinished, non-forfeited,
  user-created funded races and tournaments (`:170-215`) and throws the old
  `FUNDED_EXPOSURE_LIMIT` code and “Finish or leave another funded competition”
  copy (`:140-167`, `:965-994`).
- `docs/remove-funded-exposure-cap-requirements.md` documents that aggregate
  coin exposure was removed, but its economy review required the later five-
  membership safeguard. The observed error is therefore the replacement guard,
  not the retired aggregate coin cap.
- Frontend join paths map that legacy code through
  `lib/utils/funded_exposure_error_copy.dart`; for example
  `lib/screens/main_shell.dart:3227-3247` uses it for featured public joins.

### Daily Reward and Home quick actions

- `lib/screens/daily_reward_screen.dart:719-751` lays out `DAILY REWARD`, Odds,
  Help, and Close in a wrapping row. On a narrow viewport the Close button wraps
  to an awkward second line. The claimed body can say “Today's reward has been
  claimed” (`:745-751`).
- The Home compact reward action is a bespoke 44 px `Ink` with its own shadow
  and a `FittedBox` (`lib/widgets/streak_chip.dart:388-459`), while Shop uses the
  shared `PillButton` (`lib/screens/tabs/home_tab.dart:1441-1493`). This creates
  visible depth/clipping differences despite the current outer-size test.
- `_quickActionFontSize` clamps to 11–12 px (`home_tab.dart:1441-1443`), which is
  too small, and both the bespoke control and shared button may scale text down
  to fit rather than reflow.

### Home step loading

- Home renders a skeleton only when `isLoading && stepData == null`; otherwise
  it falls back to `stepData?.steps ?? 0`
  (`lib/screens/tabs/home_tab.dart:1237-1321`). A lifecycle timing gap can
  therefore render a false zero before the initial local device read resolves.
- `MainShell._persistSteps` does not publish the truthful local `StepData` until
  after the v2 server request returns (`lib/screens/main_shell.dart:1981-2015`),
  extending the false/unresolved window on poor service even though the local
  health read has already completed.

### Decoy notifications and team-race sentences

- Decoy consumption is handled in multiple branches of
  `src/modules/powerups/commands/usePowerup.js`, including targeted attacks
  (`:2814-2873`) and AoE resolution (`:535-589`). Consumption expires the Decoy,
  but there is no durable Decoy-specific domain event.
- Durable `POWERUP_USED_V1` events notify only the final attack target and only
  for an allowlist of attack types
  (`src/modules/notifications/services/domainEventV1Projection.js:263-277`).
- `lib/widgets/feed_bubble.dart:128-140` limits activity descriptions to three
  lines with ellipsis. Team-race event sentences are often longer, so meaningful
  endings can be hidden.

### Mystery-box progress

- Backend progress only emits `stepsUntilNextPowerup` when the freshly re-read
  participant has `nextBoxAtSteps > 0`
  (`src/modules/races/queries/getRaceProgress.js:1276-1296`). A transient
  uninitialized/zero gate omits the field entirely.
- Frontend hides the helper unless both interval and remaining steps are
  positive, and forces the entire sentence to one ellipsized line
  (`lib/screens/race_detail_screen.dart:6348-6356`). This explains both the
  missing state and incomplete small-screen sentence.

### Hitchhike

- `src/modules/powerups/hitchhikeCopies.js:54-128` derives the copy from
  `StepSample.sumStepsInWindow` and excludes the in-progress hour. A target's
  visible race total may meanwhile incorporate fresher daily/local sync data.
- The reported incident (target rose from 115,253 to 119,382 in 56 minutes while
  Nathan gained only about 380) is consistent with that split: 4,129 visible
  steps were not all represented in eligible closed sample buckets at the time
  of observation.
- Existing live/settlement parity coverage is strong but uses fully seeded
  closed buckets, so it does not express this real partial-hour/sparse-sample
  path.

### Friend request identity

- `src/modules/social/queries/getFriendsSummary.js:4-15` intentionally projects
  pending users as only `id`, `displayName`, and `profilePhotoUrl`, although the
  User table already has nullable `firstName` and `lastName`.
- `lib/screens/tabs/friends_tab.dart:1137-1183` therefore renders only the handle
  in incoming rows. The current search UI already demonstrates the intended
  real-name-over-handle hierarchy (`:911-947`).

## Scope

### In scope

1. Replace the funded-only five-membership admission rule with one atomic,
   admin-configurable numeric limit over the product-approved active competition
   set.
2. Return a new machine-readable conflict code plus current/limit metadata and
   display accurate toast copy on every create/join/accept/share path.
3. Add an admin numeric editor with validation, save feedback, and a safe
   default.
4. Apply the specified Daily Reward popup and Home quick-action responsive
   changes.
5. Introduce an explicit initial-step-resolution state and pixel-styled loading
   indicator without confusing a legitimate resolved zero with loading.
6. Emit, project, deliver, audit, and route exactly one Decoy-consumed alert to
   the Decoy owner per consumed Decoy.
7. Let activity and box-progress text wrap to its full sentence.
8. Guarantee a valid next-box countdown for an eligible active participant and
   self-heal legacy/uninitialized gate state.
9. Make Hitchhike's live and final 1:1 copy agree with the target's eligible
    in-window race-score change, including partial current-hour and sparse upload
    cases.
10. Add nullable real-name fields to pending friend-request payloads and render
    them defensively.
11. Cover iOS and Android and the real demo/tutorial mirrors.

### Non-goals

- Reintroducing aggregate funded coin-exposure or daily exposure caps.
- Participant removal or reinvite UI/API changes. They require a separate spec
  covering active-race competitive and audit consequences.
- Changing race prize formulas, box odds, powerup prices, Decoy behavior, or the
  Hitchhike ratio/duration.
- Displaying legal names in general race standings, public search results, chat,
  or push copy. This batch exposes them only to the recipient of an existing
  pending friend request.
- Adding a release flag, rollout percentage, or kill switch. The numeric race
  limit is permanent product configuration, not a release control.
- Changing OS notification truncation controlled by iOS/Android. “Fully visible”
  applies to Bara's in-app race activity rows and related helper copy.
- Deploying, submitting to review, or releasing either platform as part of spec
  approval.

## Confirmed product decisions

The owner confirmed the following on 2026-08-28. There are no unresolved product
questions entering required review.

1. **Active-limit scope:** default to **20** and count accepted
   memberships in every PENDING or ACTIVE user-created race or tournament,
   regardless of public/private, solo/team, free/funded, or creator/joiner.
   Exempt system-created Daily/Weekly seeded races and tournament-generated
   matchup races so automatic enrollment and one bracket do not consume many
   slots.
2. **Economy-risk acceptance:** use one maximum of 20 with no separate funded or
   powerup-enabled cap and no payout/box redesign in this batch. The owner
   explicitly accepted the reviewed consequence that the same steps can earn
   value in up to 20 races, including the estimated payout and box inflation.
3. **Participant removal:** remove it entirely from this batch and tackle it in
   a later focused specification.
4. **Team notification surface:** “notifications fully visible” means the
   in-race Bara activity feed/system-event bubbles and the nearby next-box
   sentence, both of which currently ellipsize. The new Decoy item is separately
   both an OS push and an Inbox alert. OS banner length remains platform-
   controlled and is not part of the full-sentence guarantee.

## API contract

### 1. Active competition limit — player-facing admission

All existing create/join/accept/share endpoints retain their request and success
shapes. When the new count would exceed the configured limit, they return:

```http
409 Conflict
Content-Type: application/json
```

```json
{
  "error": "You can have up to 20 active competitions at a time.",
  "code": "ACTIVE_COMPETITION_LIMIT",
  "limit": 20,
  "current": 20
}
```

Rules:

- `limit` and `current` are integers. The server, not the client, owns the copy
  number and atomic decision.
- Lowering the admin value never ejects existing members or rewrites races. A
  user already above the new limit remains in those competitions but cannot add
  another until their count falls below the configured value. The error reports
  their actual `current`, even when it exceeds `limit`.
- Duplicate/idempotent joins that do not create a new accepted membership do not
  consume another slot and must resolve before the limit rejection.
- Invited/PENDING-invitation, DECLINED, removed, forfeited, finished, eliminated,
  COMPLETED, and CANCELLED rows do not count.
- Batched/automatic admissions reserve the whole requested cohort atomically and
  cannot partially admit above the limit.
- Existing race capacity, team capacity, authorization, feature-capability, and
  buy-in errors retain precedence where they are already checked before this
  cross-competition guard.
- The legacy `FUNDED_EXPOSURE_LIMIT` response remains understood by new clients
  for rolling-deploy/older-backend compatibility, but new backend code does not
  emit it for the replaced membership ceiling. Historical exposure stamps and
  their lock table remain intact.

Admission matrix:

- Enforce on race creation/quick-create, immediate public or share-link join,
  invite acceptance, creator acceptance of a join request, tournament creation,
  and tournament join/invite acceptance.
- Sending an invite and creating a join request do not count until acceptance.
- System Daily/Weekly enrollment and tournament-generated matchup creation are
  exempt; “automatic admissions” means only a non-exempt command that directly
  creates accepted user membership.
- Each applicable command acquires sorted `funded_exposure_guards`, reads the
  authoritative Postgres count, validates, and writes accepted membership in the
  same transaction. Membership counts are never cached. Route error handling
  preserves `code`, `limit`, and `current` metadata on every path.

### 2. Admin numeric configuration

Do not broaden the historical boolean-only `PATCH /admin/settings` request
contract. Add a dedicated resource:

```http
GET /admin/settings/active-competition-limit
```

```json
{
  "activeCompetitionLimit": 20,
  "minimum": 1,
  "maximum": 20,
  "updatedAt": "2026-08-28T12:00:00.000Z"
}
```

`updatedAt` is nullable when the response is serving the compiled default
because no valid persisted row exists. Frontend reads it defensively and does
not display it as required content.

```http
PATCH /admin/settings/active-competition-limit
Content-Type: application/json
```

```json
{ "activeCompetitionLimit": 20 }
```

Success is the same shape as GET. Validation failures are:

```json
{
  "error": "activeCompetitionLimit must be an integer from 1 to 20",
  "code": "INVALID_ACTIVE_COMPETITION_LIMIT"
}
```

with status 400. Unknown keys, arrays, floats, numeric strings, null, booleans,
and values outside the inclusive range are rejected. Missing/malformed/read-fail
configuration falls back server-side to 20. Saving 20 explicitly is allowed.
This permanent numeric setting may be changed by an administrator as a product
capacity rule; it is not a release flag. The route uses the existing admin auth
middleware. Postgres `app_settings` is authoritative. Reuse the environment-
prefixed Redis `v1:settings:app` key, the established catalog TTL, and the
existing maximum 30-second in-process cache bound. PATCH commits through the
shared settings command and re-reads Postgres for its response. A Redis
invalidation failure is logged and metriced but does not turn a committed save
into an error; the other production worker converges within the declared bound.
Put business logic in injected admin query/command modules behind thin routes.

### 3. Decoy-consumed notification

Append a durable domain event in the same transaction that consumes a Decoy:

```json
{
  "eventType": "DECOY_CONSUMED_V1",
  "schemaVersion": 1,
  "aggregateType": "POWERUP",
  "aggregateId": "<decoy powerup/effect id>",
  "payload": {
    "decoyEffectId": "...",
    "raceId": "...",
    "ownerUserId": "...",
    "attackerUserId": "...",
    "attackPowerupType": "LEG_CRAMP",
    "outcome": "REDIRECTED"
  },
  "audience": [
    { "recipientId": "<ownerUserId>", "facts": {} }
  ]
}
```

`outcome` is `REDIRECTED` or `BLOCKED`. AoE casts that consume multiple Decoys
append one event per consumed Decoy, each with a key derived from the immutable
Decoy effect ID, so retries and multiple workers cannot duplicate it.

Projection keeps the public type routable by frozen clients:

```json
{
  "type": "POWERUP_USED",
  "subtype": "DECOY_CONSUMED",
  "title": "Your Decoy was triggered!",
  "body": "Your Decoy protected you in <race name>. Tap to view the race.",
  "route": "race_detail",
  "params": { "raceId": "..." }
}
```

The event creates an Inbox alert even with no device token; APNs/FCM delivery is
best-effort from the durable intent. Tapping foreground, background, terminated,
or Inbox presentations routes to the existing race-detail destination. Missing
or deleted race at tap time falls back to Races with a non-blocking message.
Stealth never leaks the attacker's identity: the copy does not name the attacker.
Use the exact producer/projection idempotency key
`DECOY_CONSUMED_V1:<decoyEffectId>` and register the producer and projector.
This gameplay-impact alert is not covered by the existing per-race control that
mutes placement and chat; only OS/global notification permission can suppress
the external push, while the durable Inbox alert still exists.

### 4. Friend summary additive fields

`GET /friends/summary` (current `friends-summary-v1`) keeps its envelope and adds
nullable name fields only to each pending `user` object:

```json
{
  "friendshipId": "...",
  "user": {
    "id": "...",
    "displayName": "angleholics",
    "profilePhotoUrl": null,
    "firstName": "Anjali",
    "lastName": "Patel"
  }
}
```

Both fields are nullable and omitted-vs-null tolerant on the new frontend. Trim
and join non-empty parts for display; never render `null`, a doubled space, or an
empty name. If both are absent, render the handle exactly as today. Old clients
ignore the additive fields.

### 5. Mystery-box progress

No new endpoint. `GET /races/:id/progress` and compact/bootstrap equivalents keep
`powerupData.stepsUntilNextPowerup` additive. For every accepted participant
viewing an ACTIVE, powerup-enabled race with a positive interval, the value must
be an integer in `1..powerupStepInterval` after any due boxes are synchronized.
When the progress overlay sees null/zero/misaligned `nextBoxAtSteps`, it derives a
non-minting boundary as `(floor(effectiveSteps / interval) + 1) * interval` and
returns the truthful countdown immediately. It enqueues the existing race-keyed
C0 resolution worker to persist repair and mint any due boxes; the hot progress
read never writes `race_participants`. Viewer-specific countdown data stays out
of shared `v1:race:progress` snapshots. A spectator or disabled-powerup race
continues to omit the field.

### 6. Hitchhike scoring

No response shape change. Preserve the stamped `scoringVersion` model and add a
new immutable scoring version for newly cast Hitchhikes. Frozen-client-created
v1/v2 effects retain their existing interpretation; they must not be silently
reinterpreted mid-race.

The new version's authoritative term is:

```text
floor(eligible target in-window scoring contribution * stamped copyRatio)
```

Compute that contribution from immutable cast/end boundary checkpoints through
the same race-timezone and effect-window scorer as the target's leaderboard
contribution—not by subtracting two already-rounded final leaderboard totals and
not by including unrelated instant bonuses/penalties. Apply participant join,
finish, forfeit, and race-end clamps; global-event entitlements; and the current
v2 supported timed effects. It must include a partial current hour once the
target has uploaded enough truthful source data for the target's own score to
rise, using a monotonic boundary delta fallback when fine-grained samples are
sparse; it must never invent steps from wall-clock interpolation. Delayed data
whose device timestamps prove it predates the cast remains excluded. If only a
coarse daily-total delta exists, the cast checkpoint owns the unavoidable
post-cast delta so the user-visible 1:1 promise wins over silently crediting
almost nothing. The caster's copy remains additive, does not reduce the target,
does not earn boxes, is inserted before Leech, and may be negative under Wrong
Turn exactly as v2.

Persist an additive Postgres capture keyed uniquely by effect ID with cast-time
race-timezone daily/sample boundary, scoring-input version/fingerprint,
monotonic raw-source attribution/high-water, versioned signed effective
contribution, capture-through timestamp, and frozen-at boundary. Target sync
enqueues C0 resolution; the shared scorer CAS-replaces the signed value for a
newer scoring-input version and updates the
capture using the leaderboard's canonical source semantics. Coarse daily delta
is an alternative to exact samples, never additive, is capped by the target's
canonical eligible increase, and one source delta can belong to only one
sequential Hitchhike. Settlement reads the frozen signed value produced by the
shared scorer, never Redis, process memory, or a UI snapshot. Timestamped
delayed in-window uploads may
update until the earliest of effect end, target finish/forfeit, race end, or
settlement freeze; uploads after that freeze do not reopen the result.

## Data model and migrations

1. Reuse `app_settings` JSON storage for `activeCompetitionLimit`; no schema
   migration is needed. Add it to the known numeric settings registry with a
   default of 20 and bounded validator, but expose it only through the dedicated
   admin endpoint/card.
2. Keep `funded_exposure_guards` as the per-user admission lock. Rename service
   concepts in code toward active competition membership while retaining table
   and historical exposure columns for compatibility; no destructive rename.
3. `DECOY_CONSUMED_V1` uses existing domain-event, projection, Inbox, audit, and
   notification-intent tables. No notification schema migration is expected.
4. Pending friend identity needs only an expanded Prisma select; User name
   columns already exist and are nullable.
5. Mystery-box repair uses the existing `next_box_at_steps` column.
6. Hitchhike v3 uses the additive capture above with unique idempotency and no
   backfill. Deploy release A that reads/scores v3 everywhere but continues to
   stamp v2. Only after every production worker runs A may release B stamp v3
   server-side for all new casts, including casts from frozen clients. Existing
   v1/v2 Hitchhike remains active throughout. Release B, which begins stamping
   v3, requires the completed economy review and separate deployment
   authorization; A and B are code releases, not runtime controls.

## Backend implementation plan

Implementation order is contract first, then frontend against the locked
contract.

1. Write failing HTTP integration tests for all race and tournament admission
   paths at `limit - 1`, `limit`, duplicate admission, completion/forfeit release,
   concurrency, and a runtime admin change. Confirm the test `DATABASE_URL` is a
   dedicated `*_test` database before running.
2. Extract the active-membership counter/reservation from the funded-only helper.
   Count the approved competition set under the existing ordered per-user locks.
   Remove `enforceMembershipLimit`'s funded-only selection and apply the single
   maximum of 20 to the endpoint matrix above across every free and funded path;
   do not retain a second value-bearing cap and do not treat invite sending or
   join-request creation as accepted membership.
3. Add the dedicated admin GET/PATCH handlers and settings reader. Invalidate
   cross-worker settings cache on save; admission reads may use the existing
   short TTL, with the saved value taking effect immediately in the serving
   worker and converging across the other production worker within the declared
   cache window.
   A limit decrease is prospective only: never prune existing memberships.
4. Return `ACTIVE_COMPETITION_LIMIT` metadata everywhere. Keep the old error
   helper exported only for genuinely legacy exposure paths/tests until code
   review proves no caller remains.
5. Write failing Decoy integration tests through real powerup endpoints for
   targeted redirect, two-player block, and multi-Decoy AoE. Assert one durable
   event, one Inbox alert, one push intent, stealth-safe copy, and race routing.
6. Centralize Decoy consumption in a helper that expires the row and appends the
   event transactionally with key `DECOY_CONSUMED_V1:<decoyEffectId>`; migrate
   every consumption branch to it so none can forget notification delivery.
7. Write a failing active team-race progress test whose participant gate is
   null/zero at the first read. Derive and serialize a truthful non-minting
   countdown, enqueue C0 repair, and prove the read path never writes while
   preserving idempotent worker box minting. Exercise Redis enabled, Redis
   disabled, and `REDIS_URL` unset.
8. Write failing Hitchhike HTTP tests that reproduce Nathan's case: cast inside
   an hour, target uploads 4,129 eligible steps across sparse/current buckets,
   no powerups, and the caster gains 4,129 while the target loses nothing. Add
   cases for hour boundary, delayed upload, duplicate sync, effects, global 2x,
   target finish/forfeit, race end, Leech ordering, live/final parity, and mixed
   v1/v2/v3 effects.
9. Implement the immutable Hitchhike v3 attribution capture and route live
   resolution, queue resolution, finish/forfeit/race-end freeze, and settlement
   through one shared scorer. Exact and coarse sources are mutually exclusive;
   one source delta cannot credit sequential links twice. Ship the read-only v3
   compatibility release before any server stamps v3.
10. Write failing friend-summary integration tests proving incoming and outgoing
    pending users return nullable first/last names only to the two parties in the
    relationship. Extend the select additively.
11. Run backend unit tests and the relevant integration suites, never bare
    `npm test` and never against production.

## Frontend plan

### Race-limit copy and admin editor

- Add `activeCompetitionLimitErrorCopy(ApiException)` or generalize the current
  funded helper. Prefer `limit` from a well-typed positive integer; otherwise use
  “You've reached the active competition limit. Finish or leave an active
  competition, then try again.”
- Map both new and legacy codes safely during rolling deployment. Do not show
  “funded” for the new code.
- Apply the mapping to every operation in the accepted-membership admission
  matrix—not just MainShell. Team switching and invite/join-request creation do
  not create membership and must never emit this limit error.
- Add an Admin “Active race limit” numeric card. Loading keeps the current admin
  skeleton; error offers Retry; Save is disabled until a valid changed integer;
  success updates the field from the server response and shows one confirmation
  toast. Missing/404 endpoint on an older backend hides the card with a compact
  “Update backend to edit” state rather than crashing the admin screen.

### Daily Reward popup

- Remove Odds and Help affordances from the popup only. Do not change the Home
  box or backend odds data.
- Build the card as a `Stack`: reserve trailing title padding and pin a minimum
  44x44 Close hit target at the card's upper-right inside its frame. It must not
  participate in title wrapping.
- Claimed/no-extra-spin body copy is exactly `Come back tomorrow.` and the
  disabled bottom action is `COME BACK TOMORROW`. Preserve bonus-spin copy when
  a bonus spin is genuinely available.
- At 320, 360, 390, and 430 logical-pixel widths and text scales 1.0, 1.3, and
  2.0: no overlap, clipping, or off-screen close target; the card scrolls
  vertically if height is constrained.

### Home Daily Reward and Shop actions

- Use one shared quick-action component/style for both controls so outer height,
  border, shadow offset, baseline, icon size, pressed state, and disabled state
  match. Do not nest a 44 px shadowed child in a 44 px clip box.
- Raise the readable label size to 14 px at normal widths and never scale below
  13 px. On 320 px widths, reduce horizontal padding/icon gap before reducing
  text; allow the reward label to use a deliberate shorter state label if needed
  rather than silent `FittedBox` shrinkage.
- Both visual faces and shadows must occupy equal measured rectangles. Keep a
  minimum 44x44 semantic hit target.

### Home step loading

- Represent the MainShell boundary as `Loadable<StepData>` using the existing
  `initial/loading/success/error` convention and retained data for refresh.
  Publish `Loadable.success(localStepData)` immediately after the local health
  read returns, before awaiting network persistence.
- While unresolved/loading with no prior truthful same-day value, replace the
  numeric counter with a pixel-styled animated loader made from simple UI chrome
  blocks/dots and retain the `STEPS TODAY` label. Do not render literal `0`.
- A resolved device value of zero is legitimate and displays `0`. During later
  refreshes, keep the last truthful same-day number visible instead of reverting
  to loading. Clear a prior-day value at local midnight/account change.
- Respect reduced motion with a static pixel loading glyph and include
  `Semantics(label: 'Loading today’s steps')`.

### Team activity and box progress

- Remove the three-line ellipsis from system/activity `FeedBubble` descriptions;
  let the row grow to the full localized sentence. User chat behavior remains
  unchanged. Server-authored activity remains plain text; no unbounded user chat
  body is moved into this expanding surface.
- Change the next-box helper to wrap naturally to at least two lines with no
  ellipsis. Keep it above the inventory as in the real screen.
- If a capable new backend temporarily omits the remaining field, preserve the
  last valid countdown during refresh. On an older backend with no field and no
  prior value, omit the helper rather than inventing progress.

### Friend request identity

- Render joined first/last name as the primary line and `@displayName` as the
  secondary line in incoming request rows and the request-mode public profile
  sheet. Keep Accept/Decline reachable on 320 px screens by allowing identity and
  actions to reflow vertically rather than shrinking names/buttons.
- If either/both new fields are absent/null/invalid, use the available component
  or handle fallback. Clamp untrusted names with existing discoverable-name
  sanitization assumptions; never unchecked-cast server values.

### Platform and mirrors

- Shared Dart behavior ships on iOS and Android together.
- Exercise the real `RaceDetailScreen` inside demo/tutorial hosts; box helper and
  feed wrapping must render correctly in the mirrored screen.
- Update demo/tutorial fixtures so the onboarding demo has a positive next-box
  countdown and the Friends tutorial provides separate first/last/handle fields.
  Preserve Home Shop and step-count spotlight keys while their widgets change.
- Daily Reward and Home surfaces have no hand-forked native implementation, but
  both platform safe areas and Android font metrics require screenshots/tests.

## Backward compatibility and rollout

1. Deploy backend first, then the paired iOS/Android app build. Production deploy
   remains separately authorized and must keep exactly two PM2 workers.
2. During backend rolling reload, old workers may still enforce the five-funded
   rule and return `FUNDED_EXPOSURE_LIMIT`; the new frontend handles it. Existing
   app binaries treat the new 409 as a normal API error and show server `error`
   copy; therefore the backend message itself must be understandable.
3. Old clients ignore additive friend fields and the optional Decoy subtype. The
   public Decoy notification remains supported `POWERUP_USED`, so frozen apps
   route its existing race parameters correctly; no new client route is required.
4. New clients against an old backend hide the admin numeric editor on 404,
   understand the legacy funded error, omit unavailable friend names, and retain
   current box-helper fallback.
5. Hitchhike scoring behavior is stamped per effect. Release A reads/scores v3
   but stamps v2; only after every worker runs A and the economy review plus
   separate deployment authorization are complete does release B stamp v3 for
   all new casts. Existing v1/v2 Hitchhike remains active throughout. These are
   code releases, not runtime controls.
6. No new art/content gating is needed. No production data update is authorized
   by implementation approval.

## Tests-first plan

### Backend integration tests

- Active limit: race creation/quick-create; immediate public/share join; invite
  acceptance; creator join-request acceptance; tournament creation/join/invite
  acceptance; free/funded parity; exact count metadata; release after terminal
  state; seeded/matchup exemptions; no enforcement on invite sending or join-
  request creation; duplicate/concurrent joins; lowering below current; admin
  change/cache convergence; no partial rows.
- Decoy: targeted redirect, two-player block, AoE multiple holders, retry
  idempotency, transaction rollback, no attacker identity leak, Inbox without
  token, push intent with token, race destination.
- Box countdown: first active team read with uninitialized gate, repair/mint
  idempotency, refresh stability, timezone/effect immunity, compact/bootstrap
  contract parity.
- Hitchhike: Nathan sparse-current-hour reproduction plus delayed sync, boundary,
  effects, global events, exit/end clamps, Leech ordering, replay, live/final
  parity, and old scoring versions.
- Friend summary: full/partial/null names, incoming/outgoing privacy, unchanged
  accepted-friend contract, old client response tolerance.

### Frontend widget/integration tests

- Pump real Daily Reward states at 320x568, 360x640, 390x844, 430x932 and text
  scales through 2.0; assert Odds/Help absent, Close upper-right and tappable,
  exact claimed copy, and no overflow exceptions.
- Pump real Home at the same widths: equal quick-action painted bounds/shadows,
  font floors, readable labels, unresolved pixel loader, resolved zero, slow
  server after fast local read, refresh retaining prior value, reduced motion.
- Pump real public/team/tournament admission entry points and assert new plus
  legacy error mapping.
- Pump a team RaceDetail with long activity sentences and assert no ellipsis;
  assert next-box helper appears on first load and wraps fully at 320 px.
- Pump incoming requests with full, first-only, last-only, null, missing, and
  malformed name fields at narrow widths and high text scale.
- Route a synthetic `POWERUP_USED` payload with optional `DECOY_CONSUMED`
  subtype from cold/background/foreground and Inbox tap to the specified race
  using existing navigation test seams, including a frozen-client path that
  ignores the subtype.

Existing tests are protected: do not weaken, skip, or delete assertions. Update
mechanical expected copy/keys only where the approved behavior deliberately
changes.

## Acceptance criteria

- The old funded wording is never shown for the new limit; the toast contains the
  configured numeric maximum when supplied.
- Admin can read/save an integer limit, invalid values cannot persist, and the
  selected scope is enforced atomically for free and funded admissions.
- Daily Reward popup has no Odds/Help, has Close in the upper-right, and says
  `Come back tomorrow.` in the claimed/no-bonus state without affecting Home box
  copy.
- Home Reward and Shop have matching size/depth and readable responsive text on
  supported small phones.
- Home never presents an unresolved step count as zero; a resolved true zero is
  still displayed correctly.
- Every consumed Decoy creates exactly one owner Inbox alert/push intent, and tap
  opens the race without leaking a stealth attacker.
- Team activity and next-box text display complete sentences; an eligible active
  group racer sees a truthful next-box countdown on first load without manual
  refresh.
- In the 115,253→119,382 no-powerup reproduction, Nathan receives 4,129 copied
  steps (subject only to documented race-window clamps), the target loses none,
  and live/settled totals match.
- Incoming friend requests show available first/last name plus handle and safely
  fall back for old/null payloads.
- `flutter analyze` is clean, relevant Flutter tests pass, backend unit and
  dedicated-test-DB integration tests pass, both platforms are accounted for,
  required reviews run, and the manual UI-placement checklist is delivered.

## Definition of done

The batch is not done at spec approval. It is done only after backend contract
lands first; tests were observed failing for the intended reason before business
logic; frontend and backend implementation complete; code review finds no
required issues; Flutter analysis/tests and backend tests are green; iOS and
Android are both verified; version-skew reasoning is re-audited; and no production
deployment has occurred without separate in-the-moment authorization.

## Manual UI-placement test plan

**Manual UI-Placement Test Plan — 2026-08-28 feature and bug batch**

*Elements under test:*
Daily Reward Odds/Help removed; Close pinned inside the card’s upper-right corner.
Home Daily Reward and Shop actions resized into one equal two-button row.
Home step number replaced in place by a loading glyph while unresolved.
Race activity rows and next-box helper expanded vertically to show complete sentences.
Friend-request real name added above the existing handle in incoming rows and request-mode profile sheet.
Active race limit editor added to Admin settings.
Decoy alert added to Inbox; its tap destination remains the race-detail screen.

*Checklist*

1. **Daily Reward — real screen, iOS and Android**
   - **Get there:** Home → Daily Reward using an already-claimed account. Repeat on an iPhone SE/320-width equivalent and a 360-width Android device with maximum text size.
   - **Verify:** Close is inside the card at the upper-right and remains reachable below system insets; Odds and Help are absent from the header and are not duplicated on another line; claimed content and the bottom action remain below the header; the card scrolls instead of placing content or Close off-screen.

2. **Home quick actions and step HUD — real Home**
   - **Get there:** Launch Home once on a slow or unavailable connection before the initial device-step read resolves, then again with a resolved value. Use the same narrow iOS and Android devices.
   - **Verify:** The loading glyph occupies the step-number position with `STEPS TODAY` directly beneath it, and no `0` appears elsewhere during loading. Once resolved, the number replaces the glyph in the same position. Daily Reward is left and Shop is right in one row, with equal visible footprints and neither action duplicated above or below the row.

3. **Home — tab tutorial mirror**
   - **Get there:** Profile → Settings → View Tutorial → Home preview.
   - **Verify:** The real Home layout still shows Daily Reward left and Shop right in one equal row; the Shop spotlight rings the Shop action after resizing, and the steps spotlight rings the step count in its normal position. No action or HUD element appears twice.

4. **Race activity and next-box helper — real active team race**
   - **Get there:** Races → open an active team race with powerups enabled and a long system activity sentence → inspect POWERUPS and Activity.
   - **Verify:** The next-box sentence appears above the inventory slots, wraps downward without moving below or into the slots, and has no duplicate in its former single-line position. Activity rows grow vertically so each complete system sentence stays with its avatar and time without overlapping the next row.

5. **Race detail — onboarding demo race mirror**
   - **Get there:** Sign in with a fresh account → onboarding → start the demo race → advance through the powerup, attack, and activity beats.
   - **Verify:** The next-box helper appears above the inventory and the long scripted activity sentence expands in the activity panel. The coach ring and overlay still target the powerup area, and neither changed element is duplicated.

6. **Race detail — tab tutorial preview mirror**
   - **Get there:** Profile → Settings → View Tutorial → advance to the race-detail preview.
   - **Verify:** The seeded next-box helper appears above the inventory and wraps fully; activity rows remain contained in their panel; the powerups spotlight still rings the powerup area; no helper or activity row appears twice.

7. **Friend requests — real Friends and request-mode profile**
   - **Get there:** Friends → incoming requests using a requester with first and last name → tap the requester. Repeat at 320-width and maximum text size.
   - **Verify:** The real name is the first identity line and the handle is directly beneath it; Accept and Decline remain reachable without covering either line. In the opened request-mode profile sheet, the same name/handle hierarchy appears once near the profile identity, with actions below it and inside the bottom safe area.

8. **Friends — tab tutorial mirror**
   - **Get there:** Profile → Settings → View Tutorial → Friends preview containing Dana’s incoming request.
   - **Verify:** Dana’s fixture renders the same two-line real-name/handle placement as the production incoming row; the row does not fall back to the old handle-only layout, and the Friends spotlight remains aimed at its existing target.

9. **Admin active-race limit editor — real Admin**
   - **Get there:** Admin account → Profile → Settings → Admin → settings/configuration section.
   - **Verify:** One Active race limit card appears in the settings group in the intended order, with its field and Save action contained within the card at narrow width; it is not duplicated in another admin section. On an older-backend/404 state, the compact unavailable state occupies that same card position.

10. **Decoy alert — Inbox and race destination**
    - **Get there:** With a test account whose Decoy has been consumed, open Home → Inbox and tap the Decoy row. Repeat from an iOS and Android notification tap.
    - **Verify:** One Decoy alert appears in chronological Inbox order using the normal alert-row layout; tapping it opens the intended RaceDetailScreen at its normal top position, not a duplicate or modal copy. If the race is unavailable, navigation lands on Races rather than an empty race-detail surface.

*Surfaces confirmed unaffected:*
- Get Coins and session-triggered Daily Reward entries reuse `DailyRewardScreen`; they do not contain forked popup layouts.
- `RacesTab` effect plates and inventory are hand-forked, but this batch does not move their effect or inventory elements.
- Case-opening screens reuse race navigation but do not render the changed next-box helper or activity rows.
- Create Race, Race Invite, share-link, and tournament entry screens only consume changed admission messaging; no element placement changes there.
- Main and tutorial tab bars are unaffected because no tab is added, removed, renamed, or reordered.
- OS notification-banner placement remains controlled by iOS and Android; only Inbox placement and tap destination are app-owned.

*Risks found while planning:*
- `DemoRaceEngine` currently seeds `stepsUntilNextPowerup: 0`, so the helper is absent in the onboarding demo unless its fixture is updated.
- Tutorial race-detail data includes the countdown, but the activity fixture must contain a sufficiently long system sentence to exercise the expanded row.
- Tutorial Friends data currently puts “Dana Fox” entirely in `displayName` and supplies no separate first/last fields, so it cannot exercise the new two-line identity placement without a fixture update.
- The Home Shop spotlight key wraps the Shop subtree, and the steps key currently wraps the loaded number; resizing or replacing those widgets must preserve both spotlight anchors.
- `PublicProfileSheet` currently accepts only a fallback display name, so the request-mode sheet needs a safe way to receive or resolve the pending request’s real-name fields.

## Revision log

- 2026-08-28 — Initial draft: traced all requested changes across frontend and
  backend, distinguished the removed aggregate exposure cap from the later
  five-membership safeguard, and documented exact cross-repo contracts and
  tests-first implementation order.
- 2026-08-28 — Gap pass 1: specified prospective behavior when an administrator
  lowers the limit and admin authorization/cache-failure handling.
- 2026-08-28 — Gap pass 2: made the admin default timestamp nullable, specified
  that Decoy gameplay alerts bypass the placement/chat mute while respecting OS
  permission, bounded the full-sentence expansion to server-authored activity,
  and tightened Hitchhike v3 from an ambiguous total-score subtraction to an
  immutable in-window contribution with a coarse-delta fallback for sparse
  samples.
- 2026-08-28 — Owner interview: confirmed a default limit of 20 over all
  PENDING/ACTIVE user-created races and tournaments with automatic-competition
  exemptions and clarified the full-sentence request as Bara's in-app activity
  feed, while Decoy remains a separate push and Inbox notification.
- 2026-08-28 — Post-review owner decision: accepted the documented economy risk
  and required a single 20-competition maximum with no separate value-bearing
  cap or payout/box redesign. Removed participant removal/reinvite from this
  batch for a later focused specification.
- Architect review — **REVISE, then cleared by post-decision audit.** Required
  endpoint-matrix atomicity, authoritative settings/cache behavior, frozen-client
  Decoy routing, read-path-safe box repair, explicit Hitchhike capture/two-release
  rollout, and existing `Loadable` async state. Participant removal findings were
  retired when that feature left scope. The final audit's copy, signed-capture,
  and rollout corrections are folded above.
- Game-economy review — **UNSOUND; owner override recorded.** A universal
  20-competition limit permits up to 200 raw payout-EV coins/player/day, a
  controlled two-account winner-take-all payoff of 400 coins/day, and 58.86
  boxes/day for the median walker. The owner explicitly accepted this payout/box
  multiplication without a separate value-bearing cap or redesign. Participant
  removal left scope. Hitchhike v3's exclusive persisted attribution and
  review-before-v3-stamping safeguards are folded above. The admin ceiling is 20.
- UI-placement review — **complete.** The revised no-removal checklist is
  included verbatim above, with fixture and spotlight-anchor risks promoted into
  the implementation and test plans.
- 2026-08-28 — Post-review gap pass 1: removed every participant removal/reinvite
  API, data, implementation, test, acceptance, and checklist requirement while
  preserving only the explicit non-goal and historical decision record. Aligned
  the hard admin ceiling, validation response, and universal enforcement at 20.
- 2026-08-28 — Post-review gap pass 2: reconciled the exact admission endpoint
  matrix, competition-aware fallback copy, frozen-client `POWERUP_USED` Decoy
  routing, read-only progress overlay, signed Hitchhike capture, two-release
  scoring rollout, tutorial fixtures, and final UI checklist. No unresolved
  product or architecture question remains.
- 2026-08-28 — Implementation complete: backend release-A compatibility and two
  additive Hitchhike capture migrations landed locally; frontend and backend
  tests-first implementation completed; two combined review passes were fixed;
  the final review cleared every finding. Verified 2,805 Flutter tests, 2,698
  backend unit tests, the expanded feature/relevant HTTP suites, Flutter analyze,
  Prisma/runtime-control checks, Android app-bundle compilation, and iOS
  simulator compilation. No production deploy or store upload occurred.
