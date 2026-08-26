# Feature and bug-fix batch — 2026-08-25

Status: **PHASE 4 REVIEW REVISION — product decisions complete; implementation
still requires owner approval.**

## Summary and user stories

This batch makes rewarded-ad calls to action visually consistent, enforces the
zero-step floor, makes every race payout visible, improves reward language and
reminders, restores and previews shop content, promotes staff feedback replies,
adds timestamps, combines race chat with activity without unbounded payloads,
supports timezone-driven theme changes, hardens tracking-permission denial,
adds a branded website 404, repairs August 25 cohort enrollment, compacts public
race cards, and fixes tournament powerups/activity.

The private-race sharing item extends sharing beyond the creator: a member may
propose another user, while the race creator remains the authority who accepts
or declines that addition.

## Scope and non-goals

### In scope

1. Yellow rewarded-ad buttons everywhere; reroll video icon after “WATCH AD”.
2. No displayed or persisted race score below zero, including Pinecone Toss.
3. Every race detail response/UI has a payout representation.
4. Remove user-facing “flat” jargon from the post-race +50 coin offer.
5. Empty About Us section and a Buy Us a Coffee donation action in Settings.
6. Make staff feedback replies the most prominent inbox content.
7. Restore Hitchhike to the shop.
8. Rename the home CTA to “CLAIM REWARD” and periodically shake it until claimed.
9. Member sharing of private races, mediated by creator accept/decline.
10. At most one daily unclaimed-reward reminder across mystery box and daily reward.
11. Inbox timestamps.
12. Live character preview inside the Bara shop.
13. Chat messages interleaved into race activity with bounded pagination/cache use.
14. Automatic dark mode from 20:00 through 06:59 in the user’s timezone.
15. Tracking-permission denial must never crash the app.
16. Branded catch-all website 404.
17. Audit/repair users created on 2026-08-25 into daily and weekly cohorts.
18. Compact suggested-public-race card layout from screenshot 4.
19. Restore powerups and activity in eight-person tournament matchups.

### Non-goals

- No production deployment in this batch; deployment requires a separate final
  approval after all implementation and verification is complete.
- No content is written for About Us yet.
- No redesign of ad eligibility, ad rewards, payout amounts, powerup balance, or
  tournament bracket rules.
- No direct production data writes from tests. The cohort repair is a reviewed,
  idempotent operational script with dry-run output before any authorized run.
- Redis never becomes a source of truth, queue, settlement input, or coin input.
- No release flag is introduced merely for rollout comfort. Existing capability
  negotiation remains in place where frozen clients already depend on it.

## Current-state evidence and root-cause targets

- Single-box reroll UI is in `lib/screens/case_opening_screen.dart` around
  `_canReroll` and `case-reroll-button`; batch reroll is in
  `lib/screens/multi_case_opening_screen.dart`.
- Daily extra-spin UI is in `lib/screens/daily_reward_screen.dart` and its home
  entry state is in `lib/widgets/streak_chip.dart`.
- The post-race “flat” copy is isolated in
  `lib/screens/race_results_summary_screen.dart` (`isFlat50` branches).
- Pinecone mutation paths live in
  `src/modules/powerups/commands/usePowerup.js`. They clamp individual deltas,
  but all final assemblers and response projections must also enforce the
  invariant; `src/modules/races/services/computeRaceState.js` and
  `effectiveStepScoring.js` are relevant shared seams.
- Race payout creation/presentation spans `src/modules/races/racePayoutPresets.js`,
  race creation/seed flows, `getRaceDetails.js`, `getRaceProgress.js`, and
  `lib/screens/race_detail_screen.dart`.
- Feedback already has staff reply support in
  `src/modules/feedback/commands/sendStaffReply.js`; inbox storage/routes are in
  `src/modules/inbox/`, with Flutter rendering in `lib/screens/inbox_screen.dart`.
- Hitchhike is already implemented and capability-gated; catalog eligibility is
  in `src/modules/powerups/queries/getPowerupShopCatalog.js` and seeded catalog
  state, while UI is in `lib/screens/tabs/shop_tab.dart`.
- Reminder infrastructure exists in
  `src/modules/notifications/dailyRewardReminder.js`; scheduling must stay under
  the existing single-PM2-worker cron guard in `src/index.js`.
- Race chat uses `lib/services/race_chat_service.dart`; backend messages/cache
  live under `src/modules/social/`, while activity is returned by
  `src/modules/races/queries/getRaceFeed.js`.
- Automatic theme state is owned by `lib/theme_controller.dart`.
- App Tracking Transparency is already a dependency; its callers and lifecycle
  handling must be audited rather than adding another permission package.
- Website route composition begins at `src/app.js`; race-link-specific friendly
  not-found behavior already exists in `src/modules/web/raceLandingPage.js`.
- New-user seeded-race enrollment is in
  `src/modules/races/commands/autoEnrollNewUser.js`.
- Suggested race cards are in `lib/screens/tabs/home_tab.dart`; screenshot 4
  shows the existing centered PUBLIC pill and excess vertical whitespace.
- Tournament race payloads and projections must be checked across tournament
  query assembly, race progress capability filtering, demo fixtures, and the
  real race-detail screen rather than patched only in Flutter.

## API contracts

All response parsing in Flutter is defensive: missing/null additive fields use
safe defaults; no unchecked cast or `!` is permitted. Existing endpoint request
parameters remain optional so frozen clients continue to work.

### A. Race score floor (existing race endpoints, stricter invariant)

Every existing race response that exposes a participant score returns:

```json
{ "totalSteps": 0, "bonusSteps": -750 }
```

`totalSteps` is an integer `>= 0`. `rawSteps` remains internal and is never added
to a public response. Existing component fields may remain signed
for compatible diagnostics, but no persisted aggregate and no user-visible
score is negative. Powerup success responses keep their current shape and
report the actually applied loss, not a nominal loss larger than the target’s
available score. Existing error status/code behavior is unchanged.

Add one shared atomic participant-row penalty command that locks/updates the row,
computes `actualPenalty = min(nominalPenalty, max(0, currentTotalSteps))`, floors
the stored total at zero, and returns `actualPenalty`. Persist exactly:
`totalSteps' = currentTotalSteps - actualPenalty` and
`bonusSteps' = currentBonusSteps - actualPenalty`. The unapplied nominal
remainder is discarded forever and cannot punish future walking. Route direct Pinecone,
Mystery Potion Pinecone, reflected attacks, and every other immediate negative
bonus mutation through it; event copy/metadata records the actual penalty. A
stale pre-read must not allow two concurrent penalties to cross below zero. Bulk
recalculation remains on the C0 race-keyed resolution queue. Final race scoring,
settlement, list/detail/progress responses,
team totals, tournament projections, activity metadata, and Redis snapshots all
derive from the same clamped value. Settlement reads Postgres, never Redis.
For a legacy negative row, repair atomically with
`overkill = max(0, -totalSteps)`, `totalSteps'=0`, and
`bonusSteps'=bonusSteps+overkill`; this removes the previously persisted unapplied
remainder. Event/result metadata always records the same `actualPenalty`.

### B. Payout presence (existing race responses, additive/default-safe)

`GET /races/:raceId`, `GET /races/:raceId/progress`, and every existing race-card
projection continue returning the established fields and normalize the already
shipped `prizePool` contract (do not introduce a parallel payout object):

```json
{
  "prizePool": { "funded": true, "coins": 90, "projected": true },
  "projectedPotCoins": 90,
  "payouts": { "first": 90, "second": 0, "third": 0 },
  "payoutTiers": [{ "placement": 1, "amount": 90 }]
}
```

The evidenced bug is active team-race projection: `racePrizePool.js` deliberately
suppresses the block even when the race has a stamped funded pool. Remove that
suppression and calculate the projected team pool with the same accepted-team
counts, stamped `prizeCoinUnit`, stamped team multiplier, cap, eligibility, and
rounding helpers settlement already uses. Enumerate and keep equal the detail,
list/home-card, active tournament matchup, and new additive progress projection.
`GET /progress` receives the same `prizePool`, `payouts`, and `payoutTiers` shape
from Postgres-owned race/participant inputs; settlement never reads its cache.

Do not reinterpret or backfill `fundedPrize=false`: legacy buy-in races and
tournament matchups whose champion is paid at the tournament level are legitimate
non-funded rows. No payout repair writes a coin ledger or creates a second prize
liability. A forming funded race may truthfully return `coins: 0`, but its
`prizePool` remains present with `funded: true`; the UI renders the funded prize
board instead of hiding the region. Existing `payouts` and `payoutTiers` remain
for frozen and current clients respectively.

### C. Feedback priority and timestamps (existing inbox endpoint, additive)

Inbox items retain their current keys and add/default-normalize:

```json
{
  "createdAt": "2026-08-25T15:04:05.000Z",
  "lastMessageAt": "2026-08-25T15:04:05.000Z",
  "lastStaffReplyAt": "2026-08-25T15:04:05.000Z",
  "hasUnreadStaffReply": true
}
```

Alerts and feedback remain separate APIs. Extend `GET /feedback/threads` with
additive `createdAt`, `lastStaffReplyAt`, `hasUnreadStaffReply`, and stable
single cursor fields `priority` (`1` unread staff, otherwise `0`) and `sortAt`
(`lastStaffReplyAt` for priority 1, otherwise `lastMessageAt`). Order/cursor is
`(priority DESC, sortAt DESC, id DESC)`,
backed by the aligned partial/indexed query. Flutter fetches that priority page
and renders unread staff threads above ordinary `/inbox` alerts without
duplication. Opening the feedback thread detail marks that thread read; merely
opening Inbox or the legacy read-all operation must not clear capable-client
staff-reply prominence. Frozen clients retain existing read-all behavior.
Missing timestamps render no time, not an invented time.

Add nullable `feedback_threads.last_staff_reply_at` and
`last_staff_reply_message_id`; existing rows backfill from the newest STAFF
message, or remain null. `sendStaffReply` writes both in the same transaction as
the message. `hasUnreadStaffReply = lastStaffReplyAt != null &&
(userReadAt == null || userReadAt < lastStaffReplyAt)`, so a newly submitted user
thread is never misclassified. Add index
`(user_id, last_staff_reply_at DESC, id DESC)` and query unread staff threads by
that predicate/cursor; ordinary threads follow `(last_message_at DESC, id DESC)`.
Add `POST /inbox/read-alerts` (`204`, no body), which marks only ordinary Inbox
alerts read. Capable Inbox uses it; on an old backend `404` is ignored and the app
must **not** fall back to legacy `/inbox/read-all`, which would clear staff reply
prominence. Legacy `/inbox/read-all` remains unchanged.

### D. Private-race shared-link join approval (new additive contract)

Sharing itself is immediate: any accepted participant may invoke the existing
share sheet and send a text/notification/link. Approval begins only when the
recipient opens that share and taps JOIN. New clients request an attributable,
single-race share link through the existing share-link route while advertising
the additive `privateJoinApproval` capability. The returned opaque token is
persistently associated with the sharing participant; no user id is trusted from
an editable URL query string.

Add `race_share_links`: `id`, unique SHA-256 `tokenHash` (raw token never stored),
`raceId`, `sharedByUserId`, `createdAt`, nullable `revokedAt`, and nullable
`expiresAt` (default 30 days). Index `(raceId, sharedByUserId, revokedAt)`.
Every share action mints a fresh raw token (there is nothing recoverable to return
from a hash-only row); a revoked/expired token is `410 SHARE_LINK_EXPIRED`. Race deletion
cascades; user deletion preserves a nullable attribution snapshot/display name
for pending-notice copy.

Capable `POST /races/:raceId/share-link` preserves existing `201` and `shareToken`,
and adds fields:

```json
{"shareToken":"opaque","url":"https://barastep.com/r/opaque","approvalRequired":true,"expiresAt":"..."}
```

Legacy clients receive the byte-compatible legacy response/token behavior. A new
app receiving a response without `approvalRequired:true` refuses to share that
private legacy token and shows “Update required to share this private race”; it
never knowingly sends a direct-join link.

Recipient preview addendum: `GET /races/share/:token` preserves its existing
`{"race":{...}}` fields. Only a token backed by `race_share_links` adds top-level
`"approvalRequired":true` and `"expiresAt":"<ISO-or-null>"`. Legacy lifetime-token
previews omit both fields byte-for-byte. Unknown remains 404; revoked/expired
capable token returns `410 {"error":"Share link expired","code":"SHARE_LINK_EXPIRED"}`.
Flutter routes only strict `approvalRequired == true` to join-request creation;
missing/null/false retains the legacy direct-join path.

`POST /races/share/:token/join-requests`

```json
{ "team": null }
```

The authenticated recipient is the requested joiner. Success is `202`; replay
returns the same pending request:

```json
{
  "joinRequest": {
    "id": "join-request-id",
    "raceId": "race-id",
    "sharedByUserId": "nathan-id",
    "requesterUserId": "rohan-id",
    "creatorUserId": "creator-id",
    "status": "PENDING",
    "createdAt": "2026-08-25T15:04:05.000Z"
  }
}
```

Reject an unknown/revoked token, requester already participating/invited, full/
started/finished/cancelled race, blocked relationship, ineligible team choice, or
invalid auth with the standard `{ "error", "code" }` envelope. A duplicate
pending request is idempotent. Merely opening the link never creates the request.

Create-request errors: `401 AUTH_REQUIRED`; `404 RACE_NOT_FOUND`; `410
SHARE_LINK_EXPIRED`; `409 ALREADY_PARTICIPATING`, `RACE_FULL`,
`JOIN_REQUEST_COOLDOWN`; `400 RACE_NOT_JOINABLE`, `INVALID_TEAM`; and existing
funded-exposure/block codes/statuses from `joinRaceCore`.

`POST /races/:raceId/join-requests/:requestId/respond`

```json
{ "action": "ACCEPT" }
```

Creator-only. `ACCEPT` revalidates lifecycle, capacity, team, funded exposure,
and membership under the existing race join lock, then runs `joinRaceCore` for
the requester. `DECLINE` closes the request without creating an invite or
participant. Replay is idempotent and returns the terminal state. The creator
receives a prominent in-app notice: “Nathan invited Rohan to wyd STEP bro,” with
ACCEPT and DECLINE. The requester receives an ordinary accepted/declined inbox
notification and opens the race after acceptance.

Respond success JSON is
`{"joinRequest":{"id":"...","status":"ACCEPTED|DECLINED","respondedAt":"...","failureCode":null}}`.

Data: an expand-only `race_join_requests` table with UUID id, race/share-token/
sharer/requester/creator foreign keys, nullable team, status, timestamps,
terminal actor, and a partial unique constraint for one pending
`(race_id, requester_user_id)`. Postgres is authoritative; Redis only invalidates
and rebuilds affected inbox/race-list views after commit.

Indexes are exact: partial unique pending `(race_id, requester_user_id) WHERE
status='PENDING'`; creator page `(race_id, status, created_at DESC, id DESC)`; and
cooldown lookup `(race_id, requester_user_id, created_at DESC)`.

Exact terminal behavior: pending duplicate returns `202`; after DECLINED a new
JOIN creates a new request only after 24 hours (`409 JOIN_REQUEST_COOLDOWN` before
then); after ACCEPTED, ordinary already-participating behavior applies. Creator
respond success is `200`; wrong creator `403 NOT_RACE_CREATOR`; missing request
`404 JOIN_REQUEST_NOT_FOUND`; terminal replay returns `200` with its unchanged
terminal state; stale lifecycle/capacity/team/exposure failures return the
existing `joinRaceCore` status/code and mark the request `EXPIRED`, never accepted.

Add `GET /races/:raceId/join-requests?status=PENDING&cursor=<opaque>&limit=20`
(limit clamps 1–50; `(createdAt DESC,id DESC)` cursor) for creator recovery and
`GET /race-join-requests/:requestId` for the requester. Both return the exact
`joinRequest` object above plus nullable `respondedAt`/`failureCode`. Creator and
requester notices are durable Inbox destinations with deep links to the decision
card and race/request status respectively.

Creator intent:
`{"type":"PRIVATE_RACE_JOIN_APPROVAL","destination":"RACE_JOIN_REQUEST","raceId":"...","requestId":"..."}`.
Requester terminal intent:
`{"type":"PRIVATE_RACE_JOIN_RESULT","destination":"RACE","raceId":"...","requestId":"...","status":"ACCEPTED|DECLINED"}`.

Frozen-client compatibility: the legacy token/join route and its response remain
unchanged for legacy share tokens, because changing a successful participant
response to `202` can break a shipped parser. Approval-at-join applies to links
minted by capable clients. The new backend must never issue an approval token to
a client that cannot render pending/decision states. The carrying app release
therefore closes the forward path; removal or conversion of legacy private tokens
is explicitly out of scope because it would break installed binaries.

Add `privateJoinApproval` to **both** duplicated `X-Client-Features` header
branches in `lib/services/backend_api_service.dart`.

### E. One-per-day reward reminder (existing preferences + new scheduler policy)

No new preference is introduced: `dailyRewardRemindersEnabled` remains the
umbrella, so anyone who opted out stays opted out and old PATCH behavior remains
authoritative. A single scheduler selects at most one reminder
per user/local calendar date. Replace the existing 17:00 and 21:00 daily-box slots
with one 17:00 local slot: an unclaimed race mystery box takes priority, otherwise
an unclaimed daily reward qualifies. Delivery uses
a deterministic key `UNCLAIMED_REWARD:<userId>:<localDate>` in the durable
notification/job table so two PM2 workers or retries cannot duplicate it.

Eligibility is one bounded PostgreSQL query over opted-in non-review users in the
due timezone: select an unopened `MYSTERY_BOX` in an ACTIVE accepted race (earliest
race `endsAt`, then box id), otherwise a free daily reward whose server-local claim
date is not today. Preserve the existing conservative `claimSuppresses`: today
or either adjacent client-wall-clock claim date suppresses the reminder. Mystery
eligibility is exactly `race_powerups.user_id=user`, `status='MYSTERY_BOX'`,
`type IS NULL`, joined participant `status='ACCEPTED'`, and race `status='ACTIVE'`
with `endsAt > now`; add Prisma index `@@index([userId, status, raceId])` on
`RacePowerup` (migration columns `user_id,status,race_id`). Append
one `UNCLAIMED_REWARD_REMINDER_V1` domain event with deterministic event key;
outbox projection creates the Inbox intent and retry-safe push. Failures leave the
zone/day fanout resumable; successful deterministic appends are safe to replay.

Payloads retain existing deep-link conventions:

```json
{"type":"UNCLAIMED_REWARD","rewardType":"MYSTERY_BOX","destination":"RACE","raceId":"race-id"}
```

Daily fallback uses `destination:"DAILY_REWARD"` with no race id. Projection maps
both to existing app destinations for current/frozen clients; unknown types fall
back to Inbox. Null/invalid timezone uses `America/New_York`, matching the current
job.

Old apps fall back to the normal notifications destination. Scheduling runs only
inside the existing `startCrons()` worker-0 guard. No Redis queue or durable lock.

### F. Combined race timeline (extend existing messages endpoint)

Do not add `/timeline`: `GET /races/:raceId/messages` already merges USER chat and
SYSTEM activity with a stable cross-kind cursor. Add optional `view=timeline-v1`
and return an additive contract marker:

```json
{
  "messages": [
    { "kind": "SYSTEM", "id": "evt_id", "createdAt": "...", "body": "..." },
    { "kind": "USER", "id": "message-id", "createdAt": "...", "body": "..." }
  ],
  "nextCursor": "opaque-or-null",
  "timelineVersion": 1
}
```

Omitted `view` stays byte-compatible. `view=timeline-v1` defaults to 30 and clamps
to 50, retaining existing cursor ordering. Authorization is the existing strict
messages read policy (direct accepted participant or authorized tournament
spectator), never a union with a broader feed policy. Mutations remain unchanged.

Reuse `redisCacheMessagesEnabled` and the existing versioned
`v1:race:{id}:msgs:{kind}` USER/SYSTEM keys and invalidation seams. The merged
first page reads both bounded kind caches then performs the existing merge; cursor
pages use Postgres. Redis errors/unset URL fall back to Postgres. Viewer-specific
mute/read state stays outside shared keys. Flutter uses the combined surface only
when `timelineVersion == 1`; absent marker means older backend and preserves the
legacy Activity/Chat tabs (a 404 is not required).

### G. Cohort audit/repair (operational, no public API)

An idempotent script accepts `--date=2026-08-25 --dry-run` and queries users by
UTC creation bounds. It does **not** call `autoEnrollNewUser`, which selects races
active today and also changes preferences/boxes/exposure. For each exact user
`createdAt`, resolve the DAILY and WEEKLY seed timezone/window and the concrete
seeded bucket race that was active at that instant. It reports counts and IDs for
missing daily, weekly, both, ineligible, already-enrolled, and errors. The apply
mode inserts only missing historical participant rows with the enrollment side
effects explicitly limited to participant membership and the funded-exposure
reservation that would have existed then. Do not change auto-join preference,
grant welcome boxes, replay global-event enrollment, reopen completed races, alter
placements, resettle races, or write coin ledgers. Completed/settled races are
reported separately for owner review and remain unchanged unless a later explicit
remediation is approved. Before any execution, verify the target database;
tests use a dedicated test DB only. Production execution requires explicit
in-the-moment authorization and captured dry-run review.

Apply mode never writes participant rows directly. It enqueues one durable
`HISTORICAL_COHORT_ENROLLMENT` resolution command per race with payload
`{raceId,userIds:[sorted...],sourceDate:"2026-08-25"}` and deterministic key
`cohort-repair:<raceId>:2026-08-25`. The C0 worker claims it with the existing
lease/fence token, locks users in ascending id order, rechecks missing membership,
inserts in one transaction, and records completion only after commit. Retry skips
existing `(raceId,userId)` rows and cannot repeat exposure reservations.

### H. Existing-contract-only items

Ad styling/copy, Settings/About/donation, Hitchhike visibility, reward CTA motion,
shop character preview, automatic theme, ATT crash hardening, compact suggested
race cards, and tournament rendering should require no breaking API change.
Tournament investigation may identify an omitted additive field/capability; if
so, this spec must be revised with its exact JSON before implementation.

## Data model and migrations

1. Add `race_share_links` and `race_join_requests` exactly as contract D defines,
   with expand-only foreign keys, token hash uniqueness, pending uniqueness,
   recovery indexes, and nullable snapshots safe under user deletion.
2. Reuse DomainEvent/outbox/Inbox and existing notification preference storage;
   no new user preference column.
3. Payout work is projection-only. Do not backfill or reinterpret funded stamps,
   and assert zero new coin-ledger rows.
4. No new persistence for combined timeline or theme. Chat and activity remain
   separate durable tables combined at query time.
5. No new persistence for a score floor: the shared atomic command updates the
   existing participant aggregate. Repair negative stored totals through a
   separately reviewed idempotent correction to zero, without coin/placement
   settlement replay.
6. Add non-null `PowerupShopItem.dailyRewardEligible Boolean @default(true)`
   mapped to `daily_reward_eligible`. Migration backfills every existing row true,
   then sets `POWERUP_HITCHHIKE=false`; fresh seed explicitly supplies false for
   Hitchhike and true for all other currently eligible items. The shop model
   selects it and `getEligiblePowerupPool` requires both normal visibility and
   `dailyRewardEligible=true`; parity tests prove activating Hitchhike changes the
   shop only and leaves the RARE daily pool byte-identical. Catalog activation and
   tournament-seed corrections ship as idempotent production data migrations as
   well as source seed corrections.
7. Add `race_admin_commands`: UUID id, `raceId`, string `commandType`, unique
   `dedupeKey`, JSONB `payload`, status `PENDING|RUNNING|COMPLETED|FAILED`, nullable
   lease token/expiry, attempts default 0, available/created/updated/completed
   timestamps, and last error. Index `(status, available_at, created_at)` and
   `(race_id, status)`. This table is a durable envelope feeding the existing
   race-keyed C0 single-writer; it never competes with or overloads
   `race_resolution_jobs_v2` dirty-reason envelopes. A claimant CASes PENDING (or
   expired RUNNING) to its lease token, hands payload to the C0 fenced transaction,
   and marks COMPLETED only after commit. Failures retain payload, increment
   attempts, and retry with bounded backoff; unique `dedupeKey` coalesces replay
   of the same operation, while ordinary resolution enqueue remains independent.

## Frontend plan

### Rewarded-ad buttons and copy

- Add/reuse one semantic rewarded-ad button style using `AppColors.of(context)`
  yellow/gold tokens. Apply it to single reroll, batch reroll, daily extra spin,
  get-coins ad CTA, and post-race payout-double/flat-50 CTA after auditing every
  user-visible rewarded-ad entry point.
- Single reroll reads `REROLL · WATCH AD` followed by the video icon. Preserve
  loading/disabled states, contrast, semantics order, and minimum tap target.
- Remove “flat” from every user-facing `isFlat50` branch. Use natural copy such
  as “Watch an ad to earn 50 bonus coins” and “50 bonus coins awarded.” Internal
  field names may remain for wire compatibility.

### Settings and shop

- Add an About Us section placeholder with no body copy. It must not look broken
  when empty. Add Buy Us a Coffee immediately below. Until the owner supplies a
  destination, tapping it shows a normal “Donation link coming soon” message and
  performs no browser/network action; the URL is intentionally not invented.
- Restore Hitchhike through an idempotent production catalog data migration/update
  **and** correct the seed for fresh databases; production does not rerun seeds.
  Keep `powerups3` capability filtering and the 150-coin configured price.
  Introduce one authoritative `dailyRewardEligible=false` rule/field consumed by
  the daily RARE pool so shop activation cannot accidentally make Hitchhike a
  free daily-spin prize; it remains excluded from mystery boxes too.
- Add a character preview above or within the shop catalog using the existing
  equipped-character renderer and current draft selection. Selecting cosmetics
  previews immediately; purchase/equip semantics remain unchanged. Include
  loading/error/unsupported-character fallbacks and both themes/screen sizes.

### Home reward and suggested races

- Rename only the actionable home CTA from DAILY REWARD to CLAIM REWARD. Claimed
  and extra-spin states retain truthful labels. While claimable and the app is
  foregrounded, run a short accessible rattle every few seconds; stop immediately
  on claim, navigation, background, disposal, or reduced-motion preference.
- Suggested race card: place PUBLIC inline after the race name, left-align the
  two-line text block, remove the old badge row and excess gap above/below JOIN,
  preserve prize and capacity information, truncation, and horizontal carousel
  sizing. The element must not remain in its old centered location.

### Inbox and private share

- Render unread staff replies in a dedicated pinned “REPLIES FROM BARA” region
  above normal alerts, with stronger unread treatment and direct thread opening.
  Do not duplicate the same record in the lower list.
- Render relative time for recent items and an absolute localized date for older
  items: relative through 23h59m, then localized `MMM d · h:mm a` (include year
  when not the current year); semantic label contains the full localized timestamp. Missing/invalid
  timestamps omit the time safely.
- All accepted race participants get the existing Share action and can send the
  resulting link through the platform share sheet (including text). On a private
  link, the recipient preview explains that tapping JOIN requests creator
  approval. Creators get an actionable modal/inbox card with accept/decline and
  clear terminal/loading/error states; requesters see pending and terminal states.

### Combined timeline, payout, theme, ATT, tournament

- Replace race detail’s Activity/Chat split with one TIMELINE surface rendering
  compact chat rows among activity rows. Visually distinguish chat without
  overwhelming the feed; paginate incrementally and preserve send/read/mute.
  When `/messages?view=timeline-v1` lacks `timelineVersion:1`, retain current
  separate tabs for mixed deployment safety.
- Payout header always renders from normalized `prizePool`; missing fields use the
  legacy prize fields, then a safe “PAYOUT UNAVAILABLE” error state that is
  observable rather than silently absent.
- Add Auto to theme settings if not already present. Auto derives local hour from
  the device timezone: dark at `[20:00, 07:00)`, light otherwise. Re-evaluate on
  resume, timezone change/app restart, and the next 07:00/20:00 boundary. Manual
  light/dark always wins. Persist the mode, not a stale resolved brightness.
- Preserve the existing platform guard and exception boundary in
  `AdService._initializeProductionSdk`; first add a regression seam proving
  denied/restricted/exceptional ATT outcomes cannot fail SDK initialization or
  app startup. Audit the native Meta channel and the caller awaiting
  `ensureInitialized()` for the reported crash. Make only the smallest evidenced
  fix. ATT, Meta channel, Unity privacy, and Mobile Ads initialization each become
  independently injectable/non-fatal. Denied/restricted continues with limited
  ads; exceptions collapse ad widgets/CTAs safely while the app remains usable.
- Production read-only evidence on 2026-08-26 identified the tournament cause:
  `seed-tournament-weekly-showdown`, its two active eight-player tournaments, and
  all eight current matchup races have `powerupsEnabled=false`; the seed file also
  pins false. Their activity counts are zero (one matchup has one chat), so the
  “broken” activity appearance is empty data caused by disabled powerups, not a
  failed authorization request. Correct the seed and an idempotent production
  data migration to `powerupsEnabled=true`. For PENDING/ACTIVE tournament parents,
  enable future rounds. For currently ACTIVE matchup races, activate from the
  migration instant: set each accepted participant’s `baselineSteps` to their
  then-current raw race-window steps, set `nextBoxAtSteps` to baseline + 2,000,
  and enable the race without retroactive boxes. Run this through the race-keyed
  single-writer queue/ascending race order, then invalidate race/tournament caches.
  The existing merged messages endpoint renders chat immediately and new powerup
  activity prospectively. No historical fake activity rows are created.

Tournament activation likewise enqueues one durable
`TOURNAMENT_POWERUPS_ACTIVATE` resolution command per matchup, ordered by race id,
with `{raceId,activatedAt,interval:2000}` and deterministic tournament/race key.
Under the C0 lease/fence it locks accepted users ascending, calculates all
baselines from one Postgres snapshot, updates race/participants in one transaction,
and publishes invalidation only after commit. Retry compares the stamped
activation instant and is a no-op once applied; scripts/migrations never bulk
update participant rows directly.

### Website 404

- Enumerate top-level API prefixes from `src/app.js` (`/auth`, `/races`,
  `/tournaments`, `/powerups`, `/shop`, `/notifications`, `/inbox`, `/feedback`,
  and every other mounted router) and keep unknown paths under them on the standard
  JSON `{error, code}` 404 for all methods. After known website/share routes, a
  GET/HEAD request with HTML-accepting browser semantics returns HTTP 404 with a
  small responsive branded
  HTML page, cute existing capybara artwork, “This page couldn’t be found,” Home
  action, correct content type, accessible alt text, and no stack/path leakage.
  Missing static assets remain hard 404s and never receive the branded document.

## Backward compatibility and rollout

1. Backend first: expand-only migrations, score/payout fixes, proposal/reminder/
   timeline contracts, tournament projection, website 404, and catalog correction.
2. Verify old-client contracts: existing endpoints/fields/errors unchanged; new
   notification types route through generic fallback; unknown timeline/proposal
   metadata is ignorable; unsupported Hitchhike remains filtered.
3. Frontend second for both iOS and Android with identical version/build/backend
   URL. New app handles missing/null fields; timeline falls back on an absent
   version marker, while definite-404 fallback is reserved for genuinely new
   routes such as join-request reads.
4. Do not use temporary rollout controls. Any newly discovered need for an
   exceptional flag stops implementation for explicit approval under AGENTS.md.
5. Production cohort repair and deployment are separate, explicitly authorized
   operations after implementation is ready.

## Tests-first plan

### Backend integration tests (real HTTP + dedicated test Postgres)

1. Pinecone on a target below every upgrade penalty returns/persists/displays 0;
   concurrent penalties cannot cross below 0; race list/detail/progress/team/
   tournament/settlement agree; legacy negative fixture is clamped/repaired.
2. Create ordinary/public/private/team/tournament/seeded races and assert every
   funded response contains payout; active funded team projection matches
   settlement formula; legitimate legacy buy-in and tournament matchups remain
   non-funded; zero-payout funded formation still has a representation; zero new
   coin-ledger rows and no backfill.
3. Staff reply appears first, timestamp round-trips, compound pagination is stable,
   and ordinary alerts remain readable.
4. Private share: attributed capable-client link mint, requester JOIN creates no
   participant before creator acceptance, creator accept/decline, join-lock
   revalidation, idempotent replay, capacity/state/auth/block/team failures,
   requester outcome notice, and unchanged legacy-token behavior.
5. Reminder: mystery-only, daily-only, both (one winner), neither, preference off,
   timezone date boundary, concurrent workers/retry dedup, no Redis, and deep link.
6. Combined timeline: interleaving/ties/cursors/limits/auth/spectator/mute/read,
   bounded query count, cache hit/miss/invalidation/error fallback/viewer isolation.
7. Hitchhike is returned only to capable clients and remains excluded from box/
   daily pools; purchase behavior unchanged.
8. Eight-person tournament HTTP path includes powerups and activity/timeline for
   authorized participants and spectators as specified.
9. Unknown browser GET/HEAD paths get branded HTML 404; unknown mounted API-prefix
   paths such as `/races/...` and `/auth/...` keep JSON; missing assets stay hard 404.
10. Cohort script dry-run classifications and idempotent apply cover timezone/seed
    boundaries without importing an internal helper as the integration oracle.

Write each test first and observe the intended failure before business logic.

### Frontend widget/integration tests (pump real screens)

1. Every rewarded-ad CTA uses semantic yellow style; reroll icon follows text;
   loading/disabled/semantics remain correct in light/dark themes.
2. Post-race +50 UI contains no case-insensitive user-facing “flat”.
3. Settings order is About Us then Buy Us a Coffee; empty section is intentional;
   launch failure is visible.
4. Claim CTA label and periodic motion start/stop/reduced-motion behavior.
5. Staff replies render pinned once; timestamps format and missing data degrades.
6. Shop renders equipped/draft character with catalog and handles unsupported data.
7. Private-link preview, JOIN-request pending state, and creator decision states,
   including missing `approvalRequired` refusal and legacy-link behavior.
8. Timeline interleaves bounded pages and falls back to legacy tabs when
   `timelineVersion` is absent.
9. Payout renders for normalized, legacy, zero, and missing/error payloads.
10. Auto theme boundary tests at 06:59/07:00/19:59/20:00 plus resume/timezone;
    manual choices do not switch.
11. ATT denied/restricted/exception/unavailable paths reach a usable shell without
    uncaught errors on iOS and do not invoke ATT on Android.
12. Suggested race card matches new order/alignment without overflow at narrow and
    large text widths.
13. Eight-person tournament renders powerups and activity/timeline.
14. Demo race and tutorial preview fixtures make no live calls and every touched
    shared screen remains renderable.

## Acceptance criteria / definition of done

- All 19 items above satisfy their user-visible outcome and edge cases.
- No race score or presented score can be negative; tests cover concurrency and
  every public response/settlement path.
- All races have an explicit payout response and visible payout state.
- Combined timeline transfers only a bounded page and Redis remains optional,
  derived, viewer-safe, and invalidated correctly if used.
- `flutter analyze` and full `flutter test` are clean; relevant backend unit and
  integration suites pass against confirmed test infrastructure; never `npm test`.
- Both iOS and Android builds are accounted for and no platform-only crash remains.
- Architect, game analyst, UI-placement planner, implementation agents, and final
  code reviewer have completed the required workflow.
- Final handoff contains one sentence per feature/bugfix and asks for one explicit
  approval before deploying everything; nothing is deployed beforehand.

## Product decisions (Phase 3 — resolved)

Buy Us a Coffee ships as a visible placeholder with no URL yet. Private sharing
sends the link immediately by the platform share sheet/text; after the recipient
taps JOIN, the creator must approve before membership exists. Staff replies stay
pinned until read. Hitchhike returns permanently at its existing price.

The remaining decisions follow directly from the owner’s wording and existing
behavior: mystery boxes win the single 17:00 reminder;
About Us is heading-only because its content must remain empty; “August 25” is
2026-08-25 UTC because account creation is a server timestamp; every existing
Auto user receives the requested 20:00–07:00 schedule; staff replies pin until
read; and Hitchhike is permanently returned at its unchanged configured price for
clients that already advertise support.

## Manual UI-placement test plan

**Manual UI-Placement Test Plan — 2026-08-25 feature and bug-fix batch**

*Elements under test:* Single-box reroll video icon moves from before the label to after “WATCH AD”.

*Elements under test:* About Us heading-only section is added in Settings, with Buy Us a Coffee immediately below it.

*Elements under test:* Unread staff replies move into a pinned REPLIES FROM BARA region above ordinary Inbox alerts; timestamps are added to Inbox rows.

*Elements under test:* Hitchhike reappears in the Bara shop catalog.

*Elements under test:* A live character preview is added above or within the Bara shop catalog.

*Elements under test:* PUBLIC moves from its centered badge row to immediately after the suggested race name; the old row and excess gaps around JOIN are removed.

*Elements under test:* The race-detail Share action becomes visible to every accepted participant; private-join approval adds requester pending/terminal UI and a creator decision modal/Inbox card.

*Elements under test:* Separate Activity and Chat tabs are replaced by one Timeline containing activity and chat rows; the legacy split remains only on backend fallback.

*Elements under test:* A payout region is always present at the top of race detail, including zero or unavailable payout states.

*Elements under test:* Powerup inventory and activity/timeline regions reappear in eight-person tournament matchups.

*Elements under test:* The website catch-all 404 adds capybara artwork, not-found message, and Home action.

*Checklist*

1. **Single-box opening — real race screen**
   - **Get there:** Open an active powerup-enabled race → earn/open one mystery box → reach a result eligible for ad reroll.
   - **Verify:** The reroll control contains the text first and video icon at the trailing end. Confirm no duplicate icon remains before the text.
2. **Settings — real screen**
   - **Get there:** Profile → gear icon → scroll through Settings.
   - **Verify:** About Us appears as an intentional heading-only section, followed immediately by Buy Us a Coffee. Confirm neither item appears elsewhere in the Settings order or is duplicated.
3. **Inbox — standalone real screen**
   - **Get there:** Use an account with one unread staff feedback reply and ordinary alerts → Home → Inbox bell.
   - **Verify:** REPLIES FROM BARA is the first content region below the Inbox header, its unread reply appears there once, and ordinary alerts begin below it. Confirm the reply is not duplicated in the ordinary list. Verify each dated row shows its timestamp in the row without displacing the title/body.
4. **Bara shop — real screen**
   - **Get there:** Home → Shop; test Store and Inventory with an account that supports Hitchhike and owns at least one cosmetic.
   - **Verify:** The character preview appears above or within the catalog and is not duplicated among the item tiles. Hitchhike appears in its normal powerup catalog position and nowhere else. Switch a cosmetic draft selection and confirm the preview remains in the same fixed shop location.
5. **Home suggested races — real Home tab**
   - **Get there:** Sign in with at least one suggested public race → Home → suggested-races carousel.
   - **Verify:** PUBLIC is inline immediately after the race name in the left-aligned two-line text block. Confirm the old centered PUBLIC row is gone, there is no leftover blank band above it or below JOIN, and prize/capacity information remains in the card.
6. **Home suggested races — tab tutorial preview**
   - **Get there:** Profile → Admin → re-run tutorial, or use a fresh account → tab tutorial → Home preview containing seeded suggested races.
   - **Verify:** The shared Home card shows PUBLIC inline after the seeded race name and not in the old centered row. Confirm the fixture still produces a populated card rather than hiding the changed layout.
7. **Race sharing and private approval — real race surfaces**
   - **Get there:** Join a private race as a non-creator accepted participant → open race detail; share its link to a second test account → open link → tap JOIN; then view the creator account.
   - **Verify:** The non-creator sees Share in the fixed race-detail header. The requester sees the approval explanation and pending state in the join flow, not a second Share control or premature race membership UI. The creator sees the actionable approval modal/Inbox card prominently, with ACCEPT and DECLINE together; confirm it is not duplicated in ordinary Inbox content. After a terminal response, verify the pending presentation is replaced rather than left behind.
8. **Race Timeline and payout — ordinary real race**
   - **Get there:** Open any active ordinary race containing both chat and activity; scroll from the top through race detail.
   - **Verify:** The payout region is present near the top of the race content. Lower down, one Timeline occupies the former Activity/Chat area and shows both row types in one ordered surface. Confirm the old ACTIVITY and CHAT tab selector is absent and neither feed is duplicated below the Timeline.
9. **Legacy-backend race fallback — ordinary real race**
   - **Get there:** Run the app against a compatible backend/test fixture whose `GET /messages?view=timeline-v1` response lacks `timelineVersion` → open a race.
   - **Verify:** The old ACTIVITY/CHAT split appears in its original location, and the new Timeline is absent. The payout region still occupies its normal top position.
10. **Race detail — onboarding demo race**
    - **Get there:** Sign in with a fresh account → onboarding → demo race; advance through the race-detail beats and box-opening beats.
    - **Verify:** The shared real race-detail screen shows the payout region near the top and one combined Timeline in the former tab area, with seeded demo chat/activity rows present. Confirm the old Activity/Chat selector is gone. During box opening, confirm no ad-reroll control leaks into demo mode.
11. **Race detail — tab tutorial preview**
    - **Get there:** Profile → Admin → re-run tutorial → race-detail preview beat.
    - **Verify:** The seeded preview shows its payout near the top and combined Timeline in the expected lower position, with no old Activity/Chat selector. Confirm the powerup spotlight still rings the powerup tray rather than the new payout or Timeline region.
12. **Eight-person tournament matchup — real race detail**
    - **Get there:** Open an active eight-person tournament → enter one matchup as a participant, then repeat as an authorized spectator if available.
    - **Verify:** The powerup inventory/tray appears in the same relative position as an equivalent ordinary race, and activity/chat content appears in the Timeline below standings. Confirm neither region remains absent or appears twice. Verify payout placement matches ordinary race detail if the matchup carries a payout.
13. **Payout edge-state placement — real race detail**
    - **Get there:** Open test races representing funded-zero payout and malformed/missing legacy payout data.
    - **Verify:** The funded-zero race still shows its payout board in the normal top region. The malformed legacy case shows PAYOUT UNAVAILABLE in that same region. Confirm neither state leaves the old blank gap or silently removes the region.
14. **Website branded 404**
    - **Get there:** In a mobile browser, open an unknown non-API path on the backend website.
    - **Verify:** The 404 page contains the capybara artwork, not-found message, and Home action as one responsive composition. Confirm no duplicate browser/server error page appears above or below it and known pages retain their existing layout.

*Surfaces confirmed unaffected:* Batch reroll uses `MultiCaseOpeningScreen`, but this batch moves only the single-reroll icon; its placement should remain unchanged.

*Surfaces confirmed unaffected:* Daily Reward, Get Coins, and post-race rewarded-ad surfaces receive styling/copy changes only; no element is added, moved, or removed.

*Surfaces confirmed unaffected:* The Home CLAIM REWARD change alters label and motion only; `StreakChip` stays in its existing Home position, including the shared Home tutorial preview.

*Surfaces confirmed unaffected:* Appearance already exposes AUTO, LIGHT, and DARK in `SettingsScreen`; this batch changes Auto timing behavior, not control placement.

*Surfaces confirmed unaffected:* `ProfileTab` is reused by the tab tutorial, but Settings is a separately pushed route and is not composed into the Profile preview.

*Surfaces confirmed unaffected:* `RacesTab` hand-forks effect badges and inventory slots, but this batch does not move or reorder those elements; tournament verification is on the shared race-detail matchup surface.

*Surfaces confirmed unaffected:* Race creation and invite screens are reused in the demo prologue, but this batch does not alter their placement.

*Surfaces confirmed unaffected:* Post-race results use separate real and demo coach/result chrome, but the requested “flat” change is copy-only.

*Risks found while planning:* `RaceDetailScreen` is shared by live races, the onboarding demo, and the tab tutorial preview, so payout and Timeline fixtures must exist in both `DemoRaceEngine` and `tutorial_preview_data.dart`; an absent fixture field can hide the new region without a compile failure.

*Risks found while planning:* The tutorial race-detail spotlight anchors `tutorialPowerupsKey` to `raceDetail.powerups`; inserting payout or Timeline content must not move the key onto the wrong widget or obscure the spotlight target.

*Risks found while planning:* Demo box opens push the real case-opening screens, but ad reroll is intentionally suppressed in demo mode; absence of the reroll button there is expected, not a failed mirror.

*Risks found while planning:* Inbox has standalone and embedded host modes in `InboxScreen`; the pinned staff region and timestamp placement must come from the shared body rather than header-specific code.

*Risks found while planning:* Private approval introduces both a modal and an Inbox presentation; the same pending request must not render twice on one surface.

*Risks found while planning:* The Home tutorial preview already fabricates suggested public races, so its fixture must retain the fields needed for the compact two-line card and must not fall into an empty/loading state.

*Risks found while planning:* Timeline fallback deliberately restores the old two-tab layout when `GET /messages?view=timeline-v1` lacks `timelineVersion`; seeing both Timeline and the legacy tabs simultaneously is a placement failure.

## Revision log

### Gap pass 1 — requirements and compatibility

- Split new contracts from UI-only corrections and preserved all existing endpoint
  shapes for frozen clients.
- Added atomic/concurrent score-floor coverage rather than relying on display-only
  clamping.
- Defined payout presence for legitimate zero-payout races and legacy rows.
- Changed private sharing from unauthorized direct invites to creator-mediated,
  durable, idempotent proposals.
- Added one-per-local-day durable reminder dedup under the PM2 worker guard.
- Preserved API JSON 404 behavior while adding only a web catch-all.
- Made production cohort repair dry-run-first and separately authorized.

### Gap pass 2 — scale, mirrors, and edge cases

- Replaced “merge two full arrays” with a bounded cursor timeline contract and
  explicit authorization intersection/tie ordering.
- Constrained Redis to an optional derived cache with viewer-neutral payloads,
  invalidation inventory, and Postgres fallback.
- Added reduced-motion/lifecycle stops for the claim rattle and timezone boundary
  rescheduling for Auto theme.
- Added tutorial/demo fixture checks, narrow/large-text layout coverage, and
  explicit old-backend fallbacks.
- Required tournament fixes at the data/authorization projection rather than a
  Flutter-only override.
- Resolved all product decisions. The approved donation behavior is a visible
  local “coming soon” placeholder with no URL or network action; it is not an
  implementation blocker. Implementation still waits for the spec approval gate.

### Investigation pass — current-state corrections

- Corrected the payout proposal to strengthen the existing `prizePool`, `payouts`,
  and `payoutTiers` contract instead of inventing a parallel response shape.
- Found that daily reminders already run at 17:00 and 21:00 local; pinned the
  requested cap to one 17:00 reminder and one deterministic daily delivery key.
- Confirmed ATT denial is already inside a catch boundary. Reframed the item as a
  regression-first native/caller audit and prohibited speculative code changes.
- Confirmed tournament matchup races copy `tournament.powerupsEnabled`; the
  eight-player report may be authoritative configuration rather than a Flutter
  toggle. Reproduce the affected tournament/seed and distinguish configuration
  from projection failure before changing behavior.

### Post-interview gap pass 1 — join lifecycle and compatibility

- Moved creator approval from share time to the recipient’s JOIN action and made
  clear that opening a link alone has no side effect.
- Required acceptance to re-run capacity/team/exposure/lifecycle checks under the
  existing join lock; approval cannot rely on stale state from request creation.
- Replaced the speculative proposal table with durable join requests and explicit
  requester outcome notifications.
- Preserved legacy share-token join behavior for frozen binaries and scoped the
  approval invariant to newly minted capable-client links.

### Post-interview gap pass 2 — attribution and UI states

- Bound the sharer identity to an opaque server-minted token rather than trusting
  editable query parameters, enabling accurate “Nathan invited Rohan” copy.
- Added idempotency for repeat JOIN taps and creator decisions, plus pending/
  accepted/declined states for both creator and requester.
- Defined the URL-less donation row as a deliberate placeholder with local feedback
  and no invented external destination.
- Confirmed unread staff replies remain pinned only until read and Hitchhike keeps
  its configured price.

### Architect review — REQUIRED changes incorporated (2026-08-26)

- Replaced public `rawSteps` and scattered clamps with one atomic applied-penalty
  command, actual-loss event copy, and C0 preservation.
- Scoped payout work to the evidenced active-team projection and explicitly
  prohibited funded-stamp reinterpretation, tournament double funding, and ledger
  writes; added the exact existing payout fields to `/progress` from Postgres.
- Fully specified attributable share-link and join-request persistence, token
  lifecycle, status recovery, idempotency, errors, notices, and dual header edit.
- Reused the existing merged `/messages` endpoint/cursor/cache rather than adding
  a parallel timeline endpoint; authorization remains the strict messages policy.
- Corrected feedback priority around separate APIs and made thread opening—not
  Inbox read-all—the capable-client read boundary.
- Reused the existing reminder preference and durable DomainEvent/outbox path,
  with exact PostgreSQL eligibility, destination, date key, and fallback timezone.
- Replaced current-time cohort reenrollment with historical seed-window resolution
  and prohibited boxes/preferences/settlement/coin side effects.
- Expanded ATT coverage to Meta, Unity, Mobile Ads, callers, and collapsing widgets.
- Reproduced production tournament state read-only: seed/parents/matchups are
  configured false, activity is empty, and the correction now defines prospective
  mid-match activation without retroactive boxes.
- Enumerated browser/API 404 classification and added idempotent production data
  updates for Hitchhike and tournament seed state.

### Post-architect gap pass 1 — invariants and replay

- Checked every mutation for transaction/idempotency boundaries: penalty rows,
  creator decisions, reminder events, historical cohort inserts, and catalog/seed
  corrections are replay-safe and never use Redis as authority.
- Checked settlement/coin isolation: payout is presentation-only, negative-score
  repair does not resettle, tournament activation mints no historical boxes, and
  Hitchhike supply remains a paid sink.
- Added requester/creator recovery reads so a killed app does not strand join
  requests in an unknowable state.

### Post-architect gap pass 2 — mixed versions and hot paths

- Confirmed legacy share tokens and omitted timeline view remain byte-compatible;
  new behavior is selected only by capable token mint/view markers.
- Kept reminder opt-outs, legacy Inbox read-all, payout legacy fields, and unknown
  notification fallbacks intact for frozen clients.
- Reused bounded messages caches and cursor pages; no unbounded feed transfer or
  new Redis surface is introduced.
- Added the game-analyst requirement that Hitchhike shop activation cannot leak it
  into daily reward or mystery-box pools.

### Game analyst review (2026-08-26)

Verdict: **SOUND WITH CHANGES**, all incorporated. Pinecone uses atomic actual
loss; payout changes create zero new liability/ledger rows; and Hitchhike has one
authoritative daily/mystery eligibility exclusion while retaining its 150-coin
price. Verified economy figures were added to `docs/economy.md`.

### Phase 5 locked-contract addendum

- Frontend tests exposed that the recipient preview lacked a discriminator between
  approval tokens and legacy direct-join tokens. Added the top-level
  `approvalRequired`/`expiresAt` preview fields above; this is additive for new
  tokens and byte-compatible for legacy previews, with strict-true routing.
