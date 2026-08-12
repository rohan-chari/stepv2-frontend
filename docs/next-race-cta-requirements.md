# Next-Race Discovery + Quick Create — Requirements

Status: **IMPLEMENTED — automated verification complete; manual staging/device validation pending**
Date: 2026-08-11

## 1. Product decision

Production users rarely create races, while a small group of TestFlight users
creates most of them. The product should make human-created races easier to
discover and make starting one nearly effortless.

The feature has four product parts; §9 defines the safe deployment and exposure
order:

1. **Open-race discovery** — people whose only live races are seeded challenges
   can see and deliberately join open, human-created public races.
2. **Quick create** — two solo presets create a free public race with no typing.
3. **Automatic start** — a quick-created race starts when its second participant
   joins; the creator does not have to return and press Start.
4. **Referral-aware sharing** — a shared race link also attributes a referral
   when it brings in a genuinely new user.

The race is the product. Referral credit is a useful result of sharing, not the
headline of the Home experience.

### Production baseline

As of 2026-08-11:

| Metric | Value |
| --- | --- |
| Users | 152 |
| Ever raced | 127 |
| Ever created a race | 22 |
| Raced but never created | 105 |
| User-created races, all time | 140 |
| Seeded-race joins vs user-race joins | 1,114 vs 340 |

Additional observations:

- 90 of the 105 non-creators race only in seeded challenges.
- Creators average 14.6 friends; joiner-only users average 3.2, and 34 have none.
- One-and-done creators averaged 2.9 joiners per race, compared with 8.5 for
  creators who made 2–3 races and 6.2 for creators who made 4+.

These are correlations, not proven causes. The staged rollout in §9 is designed
to test whether discovery and faster creation improve starts and repeat creation.

## 2. User stories

> As a walker whose only races are automatic seeded challenges, I can discover
> public races started by real people and choose one to join.

> As someone without a live human-created race, I can start a free public race
> in two taps without naming or configuring it.

> As a creator, I can share one race link. Existing users join the race; new
> users install the app, retain the race destination, and count as my referral.

> As a new user, I can finish onboarding without answering an invite-code
> question. If I have a code, Home SETUP keeps a dismissible entry point handy,
> and Settings remains the permanent place to enter one later.

## 3. Scope

### In scope

- Up to three open human-created races on Home.
- A primary Home CTA only for users with no live human-created race.
- A results CTA when the user has just finished their last live human-created
  race.
- Two solo quick-create presets: 2 days and 7 days.
- Public, free, power-up-enabled quick-created races.
- Automatic start when participant two joins.
- A referral-aware race link with deferred deep-link behavior.
- Removal of the blocking invite-code onboarding screen.
- A dismissible invite-code prompt in Home SETUP and a permanent Settings entry.
- Independent discovery and creation kill switches.
- Analytics for the complete creation-to-start funnel.

### Non-goals for V1

- A permanent secondary creation CTA for users already in a human-created race.
- Team-race presets.
- Auto-enrolling users into strangers' races.
- Bots or synthetic participants.
- Automatically sending invitations or notifications on a user's behalf.
- Hosting rewards or special quick-create rewards.
- Making referral coins the main Home CTA pitch.
- Changing seeded-race cadence or `autoJoinFeaturedRaces` semantics.
- Tournaments or brackets.

## 4. Eligibility and distribution

### 4.1 Shared eligibility predicate

`hasLiveUserCreatedRace(userId)` is true when the user has an accepted
participant row in a `PENDING` or `ACTIVE` race whose `creator_id` is non-null.
Seeded races do not satisfy this predicate. Only human-created tournament
matches count; seeded tournament matches have no creator and do not.

The user is `eligible` for discovery and quick creation when this predicate is
false.

This helper is not cached. It is an indexed existence query, and caching it
would require invalidation across every join, leave, create, start, completion,
and tournament path.

### 4.2 Why discovery is required

`GET /home/race-card` currently resolves to one main state. A user enrolled in a
seeded challenge resolves to `ACTIVE_RACES`, so the existing `PUBLIC_RACE` state
is never reached. This makes the largest pool of potential joiners structurally
blind to human-created public races.

Eligible users therefore receive open human-created races independently of the
main race-card state.

### 4.3 Joinable open races

Home returns at most three races satisfying all of the following:

- `status IN ('PENDING', 'ACTIVE')`
- `is_public = true`
- `creator_id IS NOT NULL`
- `buy_in_amount = 0`
- `is_team_race = false` — V1 has no team-side picker, so every team race is
  excluded even for team-capable clients
- a pending race has `start_policy = 'ON_MINIMUM_PARTICIPANTS'`; legacy/manual
  pending lobbies remain available through existing browse surfaces but are not
  promoted on Home
- the viewer is neither creator nor participant
- the race is not full; capacity and `participantCount` use accepted rows only
- an active race started no more than 24 hours ago and has a parseable
  `ends_at > now`; null, malformed, or expired `endsAt` is excluded
- the race passes the existing review-account and release-channel visibility
  filters
- at most one returned race per creator

Order automatic-start pending races before active races, then newest first.

Use a dedicated bounded query that selects only the public-race row fields and
an accepted-participant count. Do not use `findPublicPending()` on the Home hot
path because it loads all participant and cosmetic records.

The rail uses a compact `OpenRaceSummary` projection with canonical field names
from the existing public-race serializer: `id`, `name`, `status`, `startedAt`,
`endsAt`, `participantCount`, `maxParticipants`, and `isTeamRace`, and
the existing compact `creator` projection. Do not introduce aliases such as
`raceId` or widen the creator projection with cosmetics. This is intentionally
not the full public-race serializer; Home does not need its prize, payout, team,
or power-up detail. `isTeamRace` is always false in V1 and `teamSize` is not
needed in the projection.

## 5. Quick creation and starting

### 5.1 Presets

`QuickCreateRaceSheet` contains:

| Choice | Existing `POST /races` fields |
| --- | --- |
| **2-DAY RACE** | `maxDurationDays: 2`, `isPublic: true`, `buyInAmount: 0`, `payoutPreset: 'TOP3_70_20_10'`, `powerupsEnabled: true`, `powerupStepInterval: 2000`, `maxParticipants: 10` |
| **7-DAY RACE** | `maxDurationDays: 7`, with the same remaining fields |
| **CUSTOMIZE…** | Opens the existing `CreateRaceScreen` unchanged |

Quick-create additionally sends additive metadata:

```jsonc
{
  "creationSource": "QUICK_CREATE",
  "startPolicy": "ON_MINIMUM_PARTICIPANTS"
}
```

The backend must be deployed before the app version that depends on these
fields. Older backends may ignore the additive metadata; frozen app clients do
not send it and keep today's manual-start behavior.

Persist both values on the race as nullable fields. `null` means legacy/manual
creation. The migration must add nullable columns without rewriting existing
rows or changing their behavior.

### 5.2 Race names

Quick create uses a small client-side solo-race name pool owned by a new helper;
there is no existing solo-race name pool to reuse. Names must be non-empty and
valid under the current `POST /races` contract. Example names include `Weekend
Sprint`, `Step Showdown`, and `Trail Mix`.

Name selection is cosmetic and never blocks creation. Tests inject a deterministic
picker.

### 5.3 Automatic start

A quick-created race with `startPolicy: ON_MINIMUM_PARTICIPANTS` starts when its
second accepted participant joins.

Requirements:

- Persist the start policy on the race; do not infer it from public/free fields.
- Persist `creationSource` independently so limits and analytics can distinguish
  quick creation from the existing customized flow.
- The join and start transition is concurrency-safe and idempotent.
- Exactly one caller can move the race from `pending` to `active`.
- `startedAt`, `endsAt`, prize configuration, and notifications match the
  existing manual `startRace` path.
- If participant two and participant three join concurrently, all accepted
  participants remain in the same single race start.
- The creator receives the existing race-start notification, if permitted.
- Manually created races and frozen-client races retain manual start behavior.
- Turning `quickCreateRaceCtaEnabled` off prevents new quick creation but never
  disables auto-start for already-created races.

Do not hold the existing join advisory lock while starting a race. Extend and
generalize the existing post-lock `privateRaceAutoStart` pattern so public-ID and
share-token joins first commit/release their join lock, then call one
policy-aware `maybeAutoStartRace`. A `PENDING → ACTIVE` compare-and-set chooses
the sole winner; a second attempt is a no-op, not a second event.

Refactor the durable start phase into one database transaction containing the
status flip, participant baselines, buy-in transitions, and durable
`RACE_STARTED` system record. All commit or none commit. Push delivery and other
best-effort fan-out occur only after the transaction commits and may not make a
successful start appear failed.

That transaction participates in the existing C0 single-writer fence: acquire
`RaceResolutionJobV2.acquireForWrite` before participant writes and apply them
in ascending `userId` order. Baselines may be fetched before the short
transaction, but inside it reread the still-`PENDING` race and the complete set
of accepted participant IDs. If that set differs from the one used to fetch
baselines, leave the race pending and retry through the same idempotent command;
never activate with an incomplete participant snapshot.

An accepted join must not be reported as failed merely because a later
notification or automatic-start attempt failed. Log the failure with race and
user identifiers. Generalize `privateRaceAutoStart.js` into the shared policy
engine and retain its existing five-minute scheduler and
`BACKSTOP_SCAN_LIMIT = 500`. Change the backstop query to oldest eligible
`PENDING` race first. Rename the scheduling-time kill switch to
`RACE_POLICY_AUTOSTART_DISABLED`, while honoring the legacy
`PRIVATE_RACE_AUTOSTART_DISABLED` value as a compatibility alias. It invokes
the same post-lock idempotent command. Already-stamped races remain eligible
for inline and backstop start even while the creation CTA flag is off.

Until participant two arrives, race detail says:

> **WAITING FOR ANOTHER WALKER**
>
> Share your race, or wait for someone to find it. It starts automatically when
> one more person joins.

Do not say the race is “live” while it is still pending.

### 5.4 Authoritative eligibility and participation limit

The backend applies the same creation predicate as the UI: a normalized
quick-create request is rejected when the creator already participates in any
live human-created race. Use one shared `quick-membership:<userId>` advisory-lock
namespace for quick creation and both join endpoints. Creation holds that short
user lock around eligibility check → race create → creator participant create.
The lock covers no notification, baseline, or network work, so two simultaneous
requests cannot both create a race.

Separately, each user may be an accepted participant in at most three live
`QUICK_CREATE` races across creator and joiner roles. A quick join acquires the
user lock and then the existing race lock, always in that global order across
both public-ID and share-token joins. Membership count and participant insert
occur inside the protected transaction. This bounds reuse of the same walking
and mystery-box stream across quick races even when one user concurrently joins
two different races. Customized and frozen-client races retain existing limits
and behavior.

### 5.5 Prize and fairness guard

Quick-created races retain app-funded prizes; they do not introduce a separate
hosting reward. Add a narrow compatibility exception allowing
`TOP3_70_20_10` to start with two accepted participants only when the persisted
pair is exactly `QUICK_CREATE` + `ON_MINIMUM_PARTICIPANTS`. Every manual/legacy
non-WTA race keeps today's four-participant minimum.

At two qualifying walkers, an absent third-place share is not minted: the
2-day pool pays 56/16 (8 coins unminted), and the 7-day pool pays 112/32 (16
coins unminted). At settlement, only quick-race participants with
`rawSteps >= 2000` size the funded pool or receive placement payout. Fewer than
two qualifying walkers means zero quick-race prize mint. Missing raw-step data
fails closed. Existing/manual race settlement is unchanged.

Deploy the already-planned raw-step position fairness fix and its reviewed
balance configuration before enabling open-race discovery in production.
Widening race fields should not amplify the current leader-to-trailer mystery-box
advantage.

Settlement remains on the existing direct-Postgres, fenced
`raceExpiry → completeRace` path. After final resolution, read `rawSteps`, the
qualifying field, and every payout input from Postgres—not Redis—then perform
quick-payout participant writes under that settlement fence in ascending
`userId` order. The quick-only floor, zero-pool rule, and two-person TOP3
exception may not introduce a second settlement writer.

## 6. Referral-aware race sharing

### 6.1 One link, two destinations

Every authenticated participant who shares a race receives a link carrying:

- the race share token; and
- the current sharer's referral attribution.

The sharer, not necessarily the race creator, is the referrer.

Expected behavior:

```text
Existing app user → open app → preview/join the shared race
New user          → store/install → signup/onboarding → preview/join the race
                                                   └→ referral retained
```

Opening a link never joins a race without a deliberate Join tap.

### 6.2 Fallbacks

- If the race is still joinable, show its preview and Join action.
- If it is full, finished, cancelled, or otherwise unavailable, preserve valid
  referral attribution and show a useful race-discovery fallback.
- If referral attribution cannot be recovered, the race link must still work.
- If the race token is invalid but referral attribution is valid, continue into
  onboarding with the referral and show the standard Home destination.

### 6.3 Reward qualification and abuse controls

A link open, install, signup, or race join does not immediately mint coins.
Before referral-aware race links are enabled, tighten the global qualifying
rule: the referred finisher must have `rawSteps >= 2000`, and at least one other
distinct accepted participant in the same non-seeded race must also have
`rawSteps >= 2000`. Power-up-adjusted `totalSteps` never qualifies. Missing raw
data fails closed.

Referral qualification likewise reads the final accepted field and `rawSteps`
directly from Postgres after race resolution under the existing settlement
fence, never from Redis. Any referral reward writes touched in the same pass use
the fence's ascending-user order.

Also change and verify these protections before enabling the links:

- one referral payout per eligible provider identity;
- code-safe defaults and effective environment values of
  `REFERRAL_DAILY_CAP=5` and `REFERRAL_MONTHLY_CAP=25` (down from today's
  20/100); the sixth and twenty-sixth grants are held, never auto-paid;
- held-for-review behavior above the velocity limits; and
- monitoring for abnormal referral-mint volume.

The end-to-end deferred-link and attribution path must be tested on a real iOS
staging install because this handoff has previously failed silently.

### 6.4 Copy

Home does not advertise referral coins. Its job is to help the user start or
join a race.

The post-create share sheet may state the reward precisely:

> **INVITE A NEW WALKER**
>
> Share your race. If a new friend joins Step and completes their first
> qualifying race, you'll both earn coins.

Never say users earn coins merely when a friend installs or joins.

## 7. API contract

All next-race behavior is capability-gated by a new `next_race_cta`
`X-Client-Features` token. Add it to both header-construction branches in
`BackendApiService`. Without the token, the backend performs zero eligibility
or discovery queries, omits `nextRace`, and ignores quick-create metadata as
legacy input. Frozen clients therefore keep their existing response cost and
behavior.

### 7.1 `GET /home/race-card` — additive

Top-level field:

```jsonc
{
  "state": "ACTIVE_RACES",
  "data": {},
  "nextRace": {
    "resolved": true,
    "eligible": true,
    "discoveryEnabled": true,
    "createEnabled": false,
    "openRaces": [
      {
        "id": "race-id",
        "name": "Weekend Sprint",
        "status": "PENDING",
        "creator": {
          "id": "creator-id",
          "displayName": "Nathan",
        "profilePhotoUrl": null
        },
        "participantCount": 1,
        "maxParticipants": 10,
        "startedAt": null,
        "endsAt": null,
        "isTeamRace": false
      }
    ]
  }
}
```

`openRaces` uses the compact `OpenRaceSummary` from §4.3. Its field names and
semantics match the corresponding public-race fields, while omitting detail Home
does not render.

When ineligible, `openRaces` is empty. When discovery is disabled, it is also
empty. When creation is disabled, discovery may still be enabled and populated.

On builder failure, return:

```jsonc
{
  "resolved": false,
  "eligible": false,
  "discoveryEnabled": false,
  "createEnabled": false,
  "openRaces": []
}
```

The client commits a new value only when `resolved == true`; otherwise it keeps
its last resolved state. A missing or malformed `nextRace` hides all new UI.

### 7.2 `GET /races` — additive, eligibility only

The results modal does not consume discovery rows, so this endpoint must not run
the open-race query:

```jsonc
{
  "active": [],
  "pending": [],
  "completed": [],
  "nextRace": {
    "resolved": true,
    "eligible": true,
    "createEnabled": true
  }
}
```

Both endpoints use the same `hasLiveUserCreatedRace` helper, but only Home builds
the discovery rail.

### 7.3 `POST /races` — additive optional inputs

The quick-create request uses the existing endpoint and fields:

```jsonc
{
  "name": "Weekend Sprint",
  "maxDurationDays": 2,
  "buyInAmount": 0,
  "payoutPreset": "TOP3_70_20_10",
  "isPublic": true,
  "maxParticipants": 10,
  "powerupsEnabled": true,
  "powerupStepInterval": 2000,
  "creationSource": "QUICK_CREATE",
  "startPolicy": "ON_MINIMUM_PARTICIPANTS"
}
```

Success remains HTTP 201 with the existing `{ "race": { ... } }` envelope. The
race object additively includes:

```jsonc
{
  "creationSource": "QUICK_CREATE",
  "startPolicy": "ON_MINIMUM_PARTICIPANTS"
}
```

Accept both new inputs as optional. Their absence preserves today's behavior.
For a `next_race_cta` client, partial/unknown values or combinations that are
not solo, public, and free return:

```http
HTTP 400
```

```json
{
  "error": "This quick-race configuration is not supported.",
  "code": "INVALID_QUICK_CREATE_CONFIG"
}
```

For a client without the capability token, ignore the metadata and use the
legacy manual-start path. If the creator already participates in a live
human-created race, return:

```http
HTTP 409
```

```json
{
  "error": "Finish or leave your current race before starting another.",
  "code": "QUICK_RACE_ALREADY_LIVE"
}
```

All existing validation errors and their status codes remain unchanged.

When `quickCreateRaceCtaEnabled` is false, a request containing the exact
supported quick-create pair returns:

```http
HTTP 503
```

```json
{
  "error": "Quick create is temporarily unavailable.",
  "code": "QUICK_CREATE_DISABLED"
}
```

This gate applies only to normalized quick-create requests. Existing/frozen
manual creation remains available, and already-created quick races retain their
automatic-start policy.

If a token-capable app receives HTTP 201 but the response lacks the exact
persisted `creationSource`/`startPolicy` pair, it treats the race as a normal
manual-start race and never shows automatic-start copy.

Both existing join endpoints keep their request/success shapes. When joining a
quick-created race would exceed three live quick memberships, return HTTP 409:

```json
{
  "error": "Finish or leave a quick race before joining another.",
  "code": "QUICK_RACE_MEMBERSHIP_LIMIT"
}
```

### 7.4 `GET /races/:id` — additive

Race detail includes nullable `creationSource` and `startPolicy` so the client
can render the automatic-start pending state. Missing or unknown values use the
existing manual-start presentation.

### 7.5 Share-link endpoint

`POST /races/:raceId/share-link` keeps its existing request and response shape:

```jsonc
{
  "shareToken": "opaque-race-token",
  "url": "https://steptracker-api.org/r/opaque-race-token?ref=BARA-ABCD"
}
```

The path token remains the race token. The authenticated sharer's stable
referral code is appended as the URL-encoded `ref` query parameter. There is no
new required request field and no referral code is returned separately.

Existing participants may share as today; non-participants still receive 403,
missing races 404, and tournament-managed races
`400 { code: "TOURNAMENT_RACE_LOCKED" }`. If referral-code lookup fails, return
the existing bare race URL rather than failing race sharing.

The web landing route, app/universal-link parser, clipboard/deferred-install
handoff, and activation fallback must preserve both components. Frozen clients
continue reading the path race token and may ignore the query; the race link
still opens. New clients capture `ref` independently while retaining the race
token for the post-onboarding destination.

End-to-end rules:

- Validate and normalize `ref` with the existing referral-code helper; invalid
  or missing referral data never breaks race preview.
- Warm universal/app links atomically persist two independent pending values:
  race token and referral code. Draining either value never clears the other.
- The landing page's custom scheme is
  `bara://join/<race-token>?ref=<code>` and preserves both values.
- Android's Play URL carries one encoded Install Referrer payload containing
  both values; the first-launch parser restores both.
- iOS copies the complete HTTPS URL only behind the existing user gesture; the
  clipboard parser restores both values after install.
- Signup submits the referral code through the existing provision field while
  retaining the pending race token for the post-onboarding preview. A capable
  client also submits that token as additive optional
  `referralSourceRaceToken`; the new backend resolves it to race provenance and
  an older backend may ignore it.
- A combined landing writes two best-effort link-open rows:
  `kind='race_share'` with the race token for race analytics, and
  `kind='referral'` with the validated referral code for the existing
  exact/network IP attribution fallback. The referral row also stores nullable
  `sourceRaceId`, resolved from the path token, so IP fallback returns the code
  and provenance together. Failure of either row never blocks the redirect or
  the other row.
- The generated URL identifies the sharer's code but is not a signed security
  assertion; referral codes are already public and the backend's identity,
  qualification, uniqueness, and velocity controls remain authoritative.

## 7.6 Data model and migrations

Add two nullable columns to `races`:

```prisma
creationSource String? @map("creation_source")
startPolicy    String? @map("start_policy")
```

Existing rows remain null and require no backfill. Null always means legacy
manual-start behavior. Create predicate-specific indexes using raw SQL and
`CREATE INDEX CONCURRENTLY` outside a transaction, including:

- creator/live quick eligibility on `creator_id` where
  `creation_source='QUICK_CREATE' AND status IN ('pending','active')`; and
- public solo/free discovery ordered by creation/start time, restricted to
  human-created live rows and the supported pending start policy.

Prisma cannot represent partial indexes. Keep their raw migration plus a schema
comment documenting the intentional drift strategy. Do not remove the existing
`creatorId`, `[isPublic,status]`, or participant `[userId,status]` indexes in the
same migration. Confirm both discovery branches with
`EXPLAIN (ANALYZE, BUFFERS)` on production-like data before enabling discovery;
index cleanup is a later evidence-based change.

Add nullable `sourceRaceId`/`source_race_id` provenance scalars to `LinkOpen`
and `Referral` (no foreign key, so analytics survives later race deletion). The
referral value is set
only when attribution came from a validated referral-aware race link, remains
null for ordinary invite-code referrals, and retains the first valid source
without later overwrite. This lets delayed qualification emit a durable race ID
without relying on transient pending-link state. Older rows need no backfill,
and frozen clients never read the column. The sharer's existing stable referral
code is still composed into the race URL. Feature flags remain rows in the
existing `appSettings` mechanism. Add all new analytics names to both backend and client
allowlists before the carrying app emits them; an older backend must soft-drop
unknown events without failing the rest of a batch.

Postgres is the V1 source and initial read path for both eligibility and the
open-race projection. Add no Redis key: create/join eligibility needs immediate
truth and correct invalidation would span too many write seams. Run zero new
queries unless `next_race_cta` is present and the relevant flag is enabled.
`GET /races` never runs discovery. On Home, apply SQL predicates and a bounded
candidate limit before loading creator/count projections. Integration tests
assert query counts. Any later Redis design requires its own default-off,
versioned surface and explicit invalidation inventory.

## 8. Frontend behavior

### 8.1 Home section

The section renders only when:

- `nextRace.resolved == true`;
- `nextRace.eligible == true`;
- loading is complete;
- the user is not in a tutorial/demo preview; and
- either creation is enabled or at least one open race is available.

Authoritative Home order is `SETUP → promoted pending invite (when present) →
NEXT RACE → Today's Coins → RACES`. The expiring person-to-person invite keeps
its existing priority directly below SETUP; otherwise NEXT RACE occupies that
slot. SETUP collapses naturally when complete. Renumber every `StaggerIn` index
to remain in visual order, including both loaded/skeleton branches.

With both discovery and creation enabled:

```text
START YOUR OWN RACE
Pick a length. We'll help find other walkers.

[ START A RACE ]

— OR JOIN ONE —
Weekend Sprint                       2 in  [+]
Step Showdown                        4 in  [+]
```

With discovery enabled before creation:

```text
OPEN RACES
Join a public race started by another walker.

Weekend Sprint                       2 in  [+]
Step Showdown                        4 in  [+]
```

If `openRaces` is empty, omit `OR JOIN ONE`. If creation is disabled too, omit
the entire section.

Do not use “NO RACE RUNNING”: eligible users commonly have live seeded races,
so that statement would be false.

The existing RACES-section public discovery duplicate is suppressed only while
the new primary discovery section is visible. Social `friendRacing` content
remains. Tutorial Home receives an explicit `isTutorialPreview: true` flag and
uses it to suppress both this section and the invite-code SETUP row; do not rely
on absent fixture fields.

Each join row owns its loading state. Disable only the tapped row while its
existing join request runs. On success, refresh Home/races and open race detail;
on failure, restore the row and show the existing game error toast. A malformed
row or missing `id` renders disabled or is omitted—it never throws or sends an
empty identifier.

### 8.2 Quick-create transition

1. Tap `START A RACE`.
2. Choose `2-DAY RACE`, `7-DAY RACE`, or `CUSTOMIZE…`.
3. A preset creates the race, closes the sheet, and opens `RaceDetailScreen`.
4. Show a dismissible share prompt over the race detail screen.

The post-create prompt is caller-driven and appears below the race header so it
never covers Back or the existing header Share action. It is a one-time nudge;
dismissing it removes only the prompt. The persistent header Share and pending
state's inline Share remain available and route through the same link service.

On success, update or refetch both the Home race card and races list immediately.
Home must not continue showing `START YOUR OWN RACE` until the five-minute poll.

On failure, keep the sheet open, restore the enabled state, and show the backend
error. `QUICK_RACE_ALREADY_LIVE` uses the backend's exact message. Emit
`quick_create_failed`, never `quick_create_succeeded`.

### 8.3 Results modal

When `GET /races.nextRace` is resolved, eligible, and creation-enabled, the
results modal shows:

- Primary: `START YOUR NEXT RACE`
- Secondary text action: `NICE`

The primary action dismisses the results route first, then presents the same
`QuickCreateRaceSheet` from the still-mounted shell. It must not stack the sheet
under the translucent results route or acknowledge results twice.

Otherwise the existing single `NICE` button is unchanged. Missing fields default
to the unchanged behavior. The onboarding demo's hand-built win card never gets
this CTA.

### 8.4 Empty pending race detail

For a quick-created public pending race with only the creator, show the automatic
start message from §5.3 and an inline Share action. Require explicit
`isPublic == true` and `startPolicy == ON_MINIMUM_PARTICIPANTS`; missing fields
must not trigger this state in tutorial/demo fixtures.

### 8.5 Visual direction

Use the existing arcade language: `GameContainer`, `HomeText.display`, and
`PillButton`. The section should feel like a playable invitation, not an ad.
Use `AppColors.of(context)` exclusively and verify night-mode contrast. Keep one
dominant action and avoid competing permanent CTAs elsewhere on Home.

### 8.6 Invite-code onboarding relocation

Remove `OnboardingInviteCodeStep` from onboarding v3. It must no longer be an
early-return gate in `OnboardingFlow`, and loading invite-code prompt state must
never delay, flash, or block onboarding.

Automatic attribution is unchanged. A referral code captured from a deep link,
deferred install handoff, provision request, or backend fallback is still applied
without asking the user to type it. The existing referral welcome and
referral-aware race destination continue when automatic attribution succeeds.

For an unattributed user, Home SETUP gains this entry above the other setup
asks because manual redemption expires after the user's first completed
non-seeded race:

```text
HAVE AN INVITE CODE?
If a friend invited you, enter their code. You'll both earn coins after your
first qualifying race.

[ ENTER CODE ]  [ SKIP ]
```

The SETUP entry renders only when all are true:

- the authenticated user payload has resolved;
- `referredByCode` is absent/null;
- `setupInviteCodePromptEnabled == true`; and
- the existing device-local invite-code resolved flag is false.

Do not infer “unattributed” before the auth payload resolves; that would flash
the row for users whose automatic attribution is still loading. Existing users
who already answered or skipped the former onboarding step retain their local
resolved flag and are not prompted again.

`ENTER CODE` opens a shared `InviteCodeSheet` extracted from the existing
referral-screen implementation. Home SETUP, Settings, and `ReferralScreen` must
use the same validation, paste behavior, redeem request, terminal-reason mapping,
reward copy, error handling, and accessibility semantics.

Unlike today's `_EnterCodeSheet`, the shared sheet owns submission, loading,
and inline error placement. Invalid codes and transport errors do not close it;
success/terminal resolution closes it once and reports the outcome to the
originating surface. Keyboard insets and scrolling keep the field and actions
visible on the smallest supported device.

`SKIP` permanently dismisses the Home SETUP row on that device, then shows the
standard game info toast:

> **INVITE CODE SKIPPED**
>
> You can always enter an invite code in Settings.

The dismissal state and resolved auth state are owned above `HomeTab` by the
shell/service so a tab remount cannot flash the row back. Dismissal is
optimistic and the row must not reappear during the toast or after a tab switch.
Reuse the existing device-local
`inviteCodeStepDone` preference key so an app update does not resurrect a prompt
the user already answered. Rename its Dart-facing methods/comments to the more
general “invite-code prompt resolved” terminology without changing the stored
key.

On successful redemption:

- mark the prompt resolved;
- hide the SETUP row immediately;
- refresh the authenticated user and friend/setup state, because redemption may
  auto-create a friendship; and
- show the existing accurate success toast.

Invalid/unknown codes and transport failures keep the sheet open and the SETUP
row available. `already_attributed` and `already_raced` are terminal: show their
existing friendly explanation and resolve the SETUP row. A self-referral is not
terminal, so the user may correct the code.

Settings adds an always-visible `ENTER INVITE CODE` row under `PROFILE &
PRIVACY` whenever `BackendApiService` is available. It opens the same shared
sheet. “Always” describes access to code entry, not unlimited reward
eligibility: the backend's existing `already_raced` guard remains authoritative,
and Settings displays its existing “Invite codes only work before your first
race” explanation when applicable.

The legacy backend flag `onboardingInviteCodeEnabled` remains in `KNOWN_FLAGS`
while frozen clients exist, but is set to false so those clients also stop
showing the onboarding screen. New clients do not use it for Home. Add
`setupInviteCodePromptEnabled` as a separate default-off kill switch. Only
literal true shows the Home prompt; absent, null, malformed, or false hides it.
The permanent Settings entry remains available even when the Home prompt is
killed.

## 9. Flags and rollout

Use independent settings, both defaulting to false:

- `openUserRaceDiscoveryEnabled`
- `quickCreateRaceCtaEnabled`

The invite-code relocation additionally uses
`setupInviteCodePromptEnabled` as described in §8.6. It does not share either
race-feature flag and also defaults false. Add all three to `KNOWN_FLAGS` before
the app ships. The backend does no new next-race work unless the capability token
and relevant race flag are both present/true.

Referral-aware links may deploy independently, but coin copy remains hidden
until deferred attribution passes staging end to end.

Rollout order:

1. Deploy referral qualification/velocity protections, the raw-step position
   fairness fix, and automatic-start data support. Frozen clients remain on the
   manual path.
2. Deploy additive API responses, both race flags off, and the additive
   default-off `setupInviteCodePromptEnabled` flag. Keep the legacy onboarding
   invite flag on until the carrying app build is ready.
3. Deploy and verify referral-aware race links on staging, including a real iOS
   install.
4. Enable `openUserRaceDiscoveryEnabled` on staging, then production. Measure
   joins into existing active public races without the creation CTA.
5. Test the app build in TestFlight against the production backend. Verify
   onboarding proceeds without an invite-code screen, while eligible Home and
   Settings entry points work.
6. Set legacy `onboardingInviteCodeEnabled=false` when the carrying build begins
   rollout; enable `setupInviteCodePromptEnabled` for the carrying build. Frozen
   clients skip the old screen and new clients use Home SETUP.
7. Enable `quickCreateRaceCtaEnabled` for TestFlight, then the App Store build,
   only after the economy prerequisites below are live.
8. Keep creation/referral flags off if quick-race payouts exceed 900 coins/day,
   referral minting exceeds 1,000 coins/day, or flagged referrals rise
   materially. Monitor payout per qualifying walker, live quick memberships,
   boxes/user-day, discard coins, and referrer concentration.
9. Compare creation, start, fill, and repeat-creation metrics. Do not add the
   secondary always-on CTA or team preset until V1 earns that expansion.

Either flag can be disabled without affecting frozen clients or the other half
of the feature.

## 10. Backward compatibility

A frozen client against the new backend:

- ignores additive `nextRace` response fields;
- does not send `creationSource` or `startPolicy`;
- retains manual-start behavior;
- cannot create a normalized quick race because it sends no quick metadata, but
  is subject to the server-authoritative three-live-quick-membership safety cap
  when joining a persisted quick race; a legacy UI receives the existing
  friendly join-error path rather than silently exceeding the economy limit;
- can still join public races through existing surfaces; and
- may receive more organic participants in a race it intentionally made public.

For invite-code relocation:

- frozen clients retain their existing onboarding implementation until
  `onboardingInviteCodeEnabled` is flipped false, then skip that screen cleanly;
- new clients ignore the legacy onboarding flag for Home SETUP;
- an absent, null, malformed, or false `setupInviteCodePromptEnabled` on an
  older backend hides the Home prompt; and
- dismissal is local and additive, so no backend response required by a frozen
  client changes shape.

An app build against an older backend sees no `nextRace` and renders exactly the
current UI. Quick create is not released until its backend fields are live in
production.

Build-time `BACKEND_BASE_URL` remains unchanged and must be verified during the
release checklist.

## 11. Analytics and success criteria

### Events

| Event | Required properties |
| --- | --- |
| `open_race_discovery_shown` | race count |
| `open_race_join_succeeded` | race id, source |
| `next_race_cta_shown` | surface (`home` or `results`) |
| `next_race_cta_tapped` | surface |
| `quick_create_selected` | preset |
| `quick_create_succeeded` | preset, race id |
| `quick_create_failed` | preset, normalized error code |
| `race_share_prompt_shown` | race id |
| `race_share_completed` | race id, share target when available |
| `quick_race_auto_started` | race id, seconds from creation; server-durable |
| `race_share_referral_attributed` | source race id, deferred-install boolean; server-durable |
| `race_share_referral_qualified` | source race id, qualification latency; server-durable |
| `invite_code_setup_shown` | none |
| `invite_code_setup_dismissed` | none |
| `invite_code_setup_applied` | attributed boolean |
| `settings_invite_code_opened` | none |

### Primary success metric

Distinct first-time creators whose quick-created race reaches `active` with at
least one real opponent.

### Secondary metrics

- create CTA impression → successful creation
- creation → second participant
- creation → race start
- share prompt → completed share
- share → new attributed signup
- share → qualified referral
- share of user-created races reaching at least four participants
- creators who create another race within 7 and 30 days
- pending quick-created races still unstarted after 24 hours

Distinct creators alone is not sufficient: a feature that creates more abandoned
lobbies has failed.

## 12. Required tests

### Backend

All backend contract cases below run through real HTTP handlers against the test
Postgres database using `npm run test:integration`. Mock-only service tests do
not satisfy the contract. Native deferred-install checks remain manual staging
tests and are not represented as deterministic integration coverage.

1. A user in only seeded races is eligible while the main card remains
   `ACTIVE_RACES`.
2. Joining a human-created race makes the user ineligible.
3. Discovery and creation flags operate independently.
4. The rail excludes the viewer's races, joined races, full races, buy-in races,
   seeded races, manual-start pending races, old/expired/malformed active races,
   review accounts, and all team races.
5. The rail returns at most three rows, at most one per creator, in the required
   order and compact `OpenRaceSummary` shape.
6. `GET /races` does not execute the discovery query.
7. A forced builder failure leaves both endpoints at HTTP 200 with unresolved
   safe defaults.
8. Participant two joining a quick-created race starts it exactly once.
9. Concurrent joins cannot double-start, double-notify, or double-charge/mint.
10. A customized or frozen-client race remains pending until manually started.
11. Two concurrent quick-create requests from one eligible creator produce one
    race; the loser receives `QUICK_RACE_ALREADY_LIVE`, while customized and
    frozen-client creation paths are unaffected.
12. A user joining a fourth live quick-created race receives
    `QUICK_RACE_MEMBERSHIP_LIMIT`; customized/frozen-client races do not count.
    Concurrent joins by the same user into two different quick races acquire the
    shared user lock and exactly one succeeds when only one slot remains.
13. With quick create disabled, its request receives
     `QUICK_CREATE_DISABLED`; legacy creation still succeeds and an existing
     quick race still auto-starts.
14. A race share opened by an existing user retains the race destination.
15. Deterministic HTTP coverage of a combined landing proves both link-open rows,
    provision attribution with `sourceRaceId`, and the independently retained
    post-onboarding race destination.
16. Full/finished race fallback preserves valid referral attribution.
17. Referral payout requires `rawSteps >= 2000` for the referred finisher and a
    distinct accepted walker; missing raw data fails closed and both eligible
    sides are paid at most once.
18. Quick-race settlement counts only walkers with `rawSteps >= 2000`, mints no
    absent third-place share, and mints zero when fewer than two qualify.
19. Effective referral caps are 5/day and 25/month; grants 6 and 26 are held.
20. `setupInviteCodePromptEnabled` is emitted default false; only literal true
    shows Home. The redeem endpoint and permanent Settings path remain available.
21. A client without `next_race_cta` causes zero eligibility/discovery queries,
    sees no `nextRace`, and has quick metadata ignored. A capable client gets the
    documented validation, and query-count assertions protect both endpoints.
22. Start transaction fault injection proves status, baselines, buy-in changes,
    and the durable start record commit together or all roll back; the backstop
    later reconciles a committed join whose inline start attempt failed.
23. Participant-two/three concurrency proves the start fence and accepted-ID
    snapshot cannot activate a race with missing baselines; a changed set leaves
    the race pending for an idempotent retry, with participant updates ordered by
    ascending `userId`.
24. Quick settlement and referral qualification read final `rawSteps` and field
    membership from Postgres under the resolution fence, never Redis, and retain
    ascending-user participant write order.

### Frontend

1. Missing, null, unresolved, or malformed `nextRace` renders today's UI.
2. Discovery-only mode renders open races without a creation CTA.
3. Creation-only mode renders the CTA without an empty join header.
4. Combined mode renders one CTA and up to three rows below it.
5. Ineligible users see no new Home section and no results CTA.
6. The section follows a promoted pending invite when present; otherwise it sits
   directly below SETUP, and leaves no gap when hidden.
7. Tutorial/demo Home and the demo win card never render the feature.
8. Both presets send every documented field, including power-ups and additive
   creation metadata.
9. Preset success opens race detail, shows the share prompt, and refreshes cached
   eligibility immediately.
10. Preset failure stays recoverable and emits failure rather than success.
11. The pending quick-race detail state describes automatic start accurately.
12. Share copy describes qualification, never reward-on-install or reward-on-join.
13. Night mode and the smallest supported device preserve contrast and access to
    all actions.
14. Onboarding v3 never renders `OnboardingInviteCodeStep` and does not wait for
    its local state.
15. An unattributed user sees the invite-code entry first in SETUP; an
    automatically attributed or previously resolved user does not.
16. Dismissing the SETUP entry hides it across Home remounts and shows the exact
    Settings-fallback info toast once.
17. Home, Settings, and Referral use the same invite-code sheet and reason copy.
18. Settings keeps `ENTER INVITE CODE` available after Home dismissal; a user
    past the eligibility window receives the existing `already_raced` copy.
19. Successful Home redemption refreshes auth/friend state and removes the row;
    invalid, self, and transient failures remain retryable as documented.
20. Repurpose the existing onboarding invite-code widget suite to prove the
    screen is absent and the shared Home/Settings sheet retains its success,
    terminal, retryable, paste, and skip behaviors. Do not simply delete the
    protected coverage because its original host was removed.

## 13. Acceptance criteria

- [ ] Eligible seeded-race users can see and deliberately join human-created
      public races.
- [ ] Discovery can ship and be measured before quick-create is enabled.
- [ ] Quick creation takes two taps from Home and requires no keyboard.
- [ ] V1 contains only the 2-day and 7-day solo presets.
- [ ] Quick-created races are public, free, power-up-enabled, and use the
      documented payout preset.
- [ ] Participant two automatically starts a quick-created race exactly once.
- [ ] No user is joined or messaged without an explicit action.
- [ ] A shared race link works for existing users and survives a new install.
- [ ] A new user from that link is attributed to the sharer even if the race is
      no longer joinable.
- [ ] Onboarding contains no invite-code question or invite-code loading gate.
- [ ] Eligible unattributed users see a dismissible invite-code entry in Home
      SETUP until they apply a code or dismiss it.
- [ ] Dismissal shows “You can always enter an invite code in Settings,” and
      Settings provides that permanent entry point.
- [ ] Automatic/deferred referral attribution continues without manual entry.
- [ ] Referral coins are granted only after the qualifying race and step bar.
- [ ] Home does not make referral coins the main pitch or claim reward-on-join.
- [ ] Users already in a human-created race see no permanent secondary CTA.
- [ ] Frozen clients retain existing create and manual-start behavior.
- [ ] Both race kill switches work independently, and the invite-code SETUP
      kill switch does not remove the permanent Settings entry.
- [ ] Success is evaluated on races that start and repeat creators, not raw
      creation count alone.

## 14. Explicitly deferred follow-ups

Only consider these after V1 data is reviewed:

- a secondary CTA for users already racing;
- team quick-create presets;
- experiments emphasizing referral rewards;
- alternate automatic-start thresholds or scheduled starts;
- hosting incentives; and
- wider or personalized open-race recommendations.

## 15. Revision log

- **Initial direction (2026-08-11):** Reframed the feature around open-race
  distribution, two solo quick-create presets, automatic start at participant
  two, and referral-aware sharing. Removed the permanent secondary CTA and team
  preset from V1.
- **Invite-code amendment (2026-08-11):** Removed the blocking onboarding
  invite-code screen. Added a dismissible Home SETUP prompt, permanent Settings
  entry, shared sheet, legacy-flag transition, and exact dismissal toast.
- **Fresh-eyes gap pass 1:** Added the nullable race fields and indexes, exact
  quick-create request/success/limit contracts, exact combined race/referral
  URL, legacy bare-link fallback, and analytics allowlist ordering. Corrected
  the impossible pending-race example from two participants to one.
- **Fresh-eyes gap pass 2:** Added server-side kill-switch enforcement,
  automatic-start failure reconciliation, row-level join loading/error states,
  results-route navigation ordering, and protected-test migration requirements.
  Clarified that disabling creation never disables already-persisted auto-start.
- **Architect review — REVISE:** Added capability-token query gating,
  authoritative create/join concurrency rules, a post-lock auto-start command,
  atomic durable start transaction, exact two-value deep-link preservation,
  default-off flags, Postgres-first bounded queries, and raw partial-index
  deployment requirements.
- **Game-system review — SOUND WITH CHANGES:** Added the narrow two-person TOP3
  exception for quick races, unminted absent-place shares, raw-step payout and
  referral floors, safe 5/day and 25/month referral caps, live quick-membership
  limits, and rollout stop thresholds.
- **UI-placement review:** Preserved pending-invite precedence, moved prompt and
  results presentation state into the shell, required a truly shared invite-code
  sheet, guarded tutorial/demo mirrors, separated the three Share placements,
  and added the manual placement plan below.
- **Post-review gap pass 1:** Removed stale defaults and error names, reconciled
  creator eligibility with the join-membership cap, excluded all team races,
  and added capability/query-count, transaction-recovery, raw-step settlement,
  and referral-cap contract coverage.
- **Post-review gap pass 2:** Confirmed the three feature switches fail closed,
  the quick-specific payout exception does not change manual races, frozen
  clients perform no new work, and Settings code entry remains independent of
  Home eligibility.
- **Architect re-review — REVISE:** Unified quick-create/join membership locking,
  joined automatic start and settlement to the C0 resolution fence, pinned raw
  qualification to final Postgres state, made combined-link attribution use two
  link-open rows with durable race provenance, and separated deterministic HTTP
  coverage from manual native-install checks.
- **Post-review gap pass 3:** Added the exact lock ordering and concurrent
  cross-race join test, accepted-ID snapshot retry semantics, ascending-user
  write ordering, additive source-race provision handoff, and non-FK provenance
  retention. No unresolved product contradiction remains.
- **Final architect re-review — APPROVE:** No required changes or suggestions
  remain; the contract is ready for backend-first implementation after the
  explicit approval gate.
- **Combined code-review correction:** Made the three-live-quick-membership cap
  server-authoritative for every join client. Capability headers may gate new UI
  and query cost, but never an abuse control; this resolves the earlier frozen-
  client exception in favor of economy safety for newly introduced quick races.
- **Implementation review — APPROVE:** Repaired combined iOS/Android deferred
  attribution, provisioned race provenance, made referral velocity decisions
  concurrency-safe, added durable lifecycle analytics, refreshed authoritative
  raw steps at expiry, tightened quick-race UI identity, isolated row loading,
  and removed the obsolete onboarding widget. The targeted re-review found no
  remaining blocker or suggestion.

## 16. Manual UI-Placement Test Plan — Next-Race Discovery + Quick Create + Invite-Code Relocation

*Elements under test:*

- Remove the invite-code entry screen from onboarding; onboarding proceeds to the existing demo/inviter-race flow.
- Add `HAVE AN INVITE CODE?` as the first row inside Home’s existing SETUP board, with `ENTER CODE` and `SKIP`.
- Add `ENTER INVITE CODE` under Settings → `PROFILE & PRIVACY`; Home, Settings, and Referral open the same sheet.
- Add the NEXT RACE section after any promoted pending invite beneath SETUP, with creation-only, discovery-only, and combined layouts.
- Add `START YOUR NEXT RACE` to eligible real race-results modals.
- Add the shared quick-create sheet and a dismissible post-create share prompt over race detail.
- Replace the creator-only manual-start empty state for qualifying quick races with the automatic-start message and inline Share action.

*Checklist*

1. **Fresh-account onboarding — onboarding**
   - **Get there:** Clear app data or install fresh → create an unattributed account → complete the health gate.
   - **Verify:** No invite-code screen appears at any point; the existing demo-race step appears in its former place without a blank/loading screen. Back out and resume once to confirm the removed screen does not reappear.

2. **Automatically attributed onboarding — onboarding/deep-link path**
   - **Get there:** On staging, open a valid referral-aware race link as a fresh install → sign up.
   - **Verify:** No manual invite-code screen appears; any existing referral welcome stays in its current position, followed by the existing onboarding flow and shared-race destination. The removed screen is not duplicated before or after the welcome.

3. **Invite-code prompt — real Home SETUP**
   - **Get there:** Sign in as an unattributed user whose local invite-code prompt is unresolved and who also has at least one other setup ask, such as generated name, missing photo, or no friends.
   - **Verify:** `HAVE AN INVITE CODE?` is the first row inside the single SETUP board, above every name/photo/friend row. `ENTER CODE` and `SKIP` are inside that row; there is no separate invite-code card or second SETUP header.

4. **Invite-code dismissal — real Home and Settings**
   - **Get there:** From the state above, tap `SKIP`, wait for the toast, switch tabs, and return Home; then open Profile → `SETTINGS`.
   - **Verify:** The Home row disappears immediately and stays absent while the toast is visible and after the tab switch. The toast is not covered by the tab bar. `ENTER INVITE CODE` remains visible under `PROFILE & PRIVACY`; the old onboarding position remains absent.

5. **Shared invite-code sheet — Home, Settings, and Referral**
   - **Get there:** Open the sheet from Home SETUP; dismiss it. Open it from Profile → Settings → `ENTER INVITE CODE`; dismiss it. Open Friends → invite/referral screen → `Have an invite code?`.
   - **Verify:** All three entry points present the same sheet in the same position and only one sheet is visible. The keyboard lifts the complete field/action area above itself. Closing the sheet returns to the originating surface without an extra route or duplicate sheet.

6. **NEXT RACE combined state — real Home**
   - **Get there:** Use an eligible account with creation enabled and at least one discoverable public race; leave another SETUP ask visible.
   - **Verify:** The Home order is `SETUP → promoted pending invite when present → NEXT RACE → Today’s Coins → RACES`. The section appears once, with `START YOUR OWN RACE`, one dominant `START A RACE` button, then `OR JOIN ONE` and up to three join rows. Public discovery is not duplicated in Home’s existing RACES opportunity row; social/friend-racing content remains in its existing place.

7. **NEXT RACE discovery-only and creation-only states — real Home**
   - **Get there:** First disable quick creation while discovery has rows; then enable creation with no discovery rows; finally disable both.
   - **Verify:** Discovery-only shows `OPEN RACES` and join rows with no creation CTA or `OR JOIN ONE`. Creation-only shows the creation CTA with no join divider. With neither available, the entire section and its spacing disappear; SETUP or the promoted invite and the following Home content close the gap.

8. **NEXT RACE loading and surrounding Home states — real Home**
   - **Get there:** Open Home during its initial load, then with a seeded race active, and then with a live human-created race.
   - **Verify:** No NEXT RACE skeleton, header, or transient row flashes before eligibility resolves. It can appear alongside a seeded race without displacing SETUP or a promoted invite. It is absent for the live human-created-race account, and the ordinary Home RACES section remains in its established position.

9. **Quick-create sheet — real Home and real results modal**
   - **Get there:** Tap Home → `START A RACE`; dismiss it. Finish the user’s last human-created race, open the results modal, and tap `START YOUR NEXT RACE`.
   - **Verify:** Both paths present the same sheet with `2-DAY RACE`, `7-DAY RACE`, and `CUSTOMIZE…` in the same order. From results, the translucent results route disappears before the sheet appears; the sheet is not underneath it and the results card is not visible behind it.

10. **Post-create transition and share prompt — real race detail**
    - **Get there:** Create either preset.
    - **Verify:** The quick-create sheet closes, exactly one race-detail route opens, and a dismissible share prompt sits above that route without covering the back or header Share controls. Dismiss it and confirm race detail remains at the same scroll position. `CUSTOMIZE…` instead opens the existing full create screen and does not show a quick-create prompt before a race exists.

11. **Automatic-start pending state — real race detail**
    - **Get there:** Open a newly quick-created public race that still has only its creator; separately open a pending customized/manual race.
    - **Verify:** The quick race shows `WAITING FOR ANOTHER WALKER`, its explanatory text, and inline Share in the pending-actions area. The old “tap Start Race” card, `START RACE` lever, and “need at least 2” message are absent there. The customized/manual race retains those existing controls and does not receive the automatic-start card.

12. **Results CTA and negative result surfaces — real results/demo result**
    - **Get there:** Show an eligible real results modal, then an ineligible/legacy-payload real results modal; separately replay onboarding through the demo win card.
    - **Verify:** The eligible real modal places `START YOUR NEXT RACE` as the primary action with `NICE` as a secondary text action beneath it. The ineligible/legacy modal retains the single existing `NICE` button. The demo’s hand-built win card retains only its existing `CONTINUE` action and never shows the new CTA.

13. **Tutorial and demo mirrors — Settings tutorial replay and onboarding demo**
    - **Get there:** Profile → Settings → `VIEW TUTORIAL` → Home preview and race-detail preview; then run the onboarding demo race.
    - **Verify:** Tutorial Home shows neither the invite-code SETUP row nor any NEXT RACE section, and existing spotlight anchors still ring their original targets. Tutorial race detail does not show the new automatic-start empty state. The demo prologue’s real create/invite screens do not gain quick-create UI, its real race-detail screen does not gain the pending auto-start card/share prompt, and its win card does not gain the results CTA.

14. **Small-device, keyboard, and night-mode placement — all new surfaces**
    - **Get there:** Repeat Home SETUP/NEXT RACE, both bottom sheets, results, and pending race detail on the smallest supported phone with large text; force night mode and open the invite-code keyboard.
    - **Verify:** Rows and actions remain in the specified order without overlap or horizontal clipping; sheets remain scrollable above the keyboard; results remain dismissible; the Home tab bar and race-detail footer do not cover the final action.

15. **iOS/Android parity — both shipped apps**
    - **Get there:** Run the combined Home state, invite-code sheet, quick-create transition, and pending race detail once on iOS and once on Android.
    - **Verify:** The same elements appear in the same order on both platforms. Native keyboard/share-sheet presentation does not leave a second Flutter sheet, obscure the inline Share action, or return to a different route.

*Surfaces confirmed unaffected:*

- **Full Races tab/Public Races screen:** remains the dedicated browse surface; only Home’s duplicate public-discovery opportunity is conditionally suppressed.
- **Demo prologue CreateRaceScreen/RaceInviteScreen:** shared production screens remain unchanged because quick create is a separate sheet; `CUSTOMIZE…` is the only new route into CreateRaceScreen.
- **Tutorial tab bar:** no tab is added, removed, renamed, or reordered.
- **Races-tab effect plates/inventory and race-detail power-up trays:** the feature does not move or resize these forked elements.
- **Case-opening screens:** no entry point or artwork placement changes.
- **Ranked-results modal:** it is a separate sibling of `RaceResultsSummaryScreen` and keeps its existing actions.
- **Demo `_WinCard`:** hand-forked result chrome stays unchanged and must not adopt the real results CTA.

*Risks found while planning:*

- **REQUIRED — preserve Home precedence:** Implement the authoritative order as `SETUP → promoted pending invite when present → NEXT RACE → Today’s Coins → RACES`. The current promoted invite is deliberately urgent and must not be displaced by NEXT RACE.
- **REQUIRED — explicitly suppress both new Home asks in tutorial:** `TutorialRealScreens` renders the real `HomeTab`. Current suppression relies partly on fixture state. Add the specified `isTutorialPreview` input and use it for both NEXT RACE and the invite-code SETUP row; do not depend on absent fixture fields.
- **REQUIRED — keep invite prompt state above the tab widget:** Home is currently stateless while its SETUP board owns local UI state. Prompt resolution/dismissal must be shell/service-owned so the row cannot flash back during auth loading, a Home rebuild, or a tab switch.
- **REQUIRED — remove the complete old onboarding placement path:** The old UI is selected by `MainShell._showInviteCodeStep`, passed through `OnboardingFlow`, and implemented as `OnboardingInviteCodeStep`. Removing only the visible widget would leave the early-return gate or loading/analytics state capable of delaying onboarding.
- **REQUIRED — the existing referral sheet is not yet reusable as specified:** `_EnterCodeSheet` only collects text, closes before redemption, and leaves validation/toasts in `ReferralScreen`. The shared sheet must own the in-sheet loading/error placement so invalid and transport failures can keep all three entry points open consistently.
- **REQUIRED — Settings availability differs from Home eligibility:** The Settings row must stay in `PROFILE & PRIVACY` whenever an API service exists, including after attribution, dismissal, or `already_raced`; do not reuse Home’s visibility predicate around the Settings widget.
- **REQUIRED — results CTA needs shell-owned presentation:** `RaceResultsSummaryScreen` is currently stateless and the shell acknowledges results after the route pops. The quick-create callback must be hosted by the still-mounted shell so the sheet appears above the correct route and the added secondary `NICE` cannot cause double acknowledgement.
- **REQUIRED — avoid accidental multiple share layers:** A new quick race can expose the post-create share prompt, the requested inline pending-state Share action, and the existing header Share icon simultaneously. Define their non-overlapping placement and ensure “dismissible prompt” means dismissing only the overlay, not removing persistent Share access.
- **REQUIRED — guard shared race-detail mirrors:** `RaceDetailScreen` is reused by the onboarding demo and tutorial preview. The new pending card must require the exact public/start-policy state and the post-create prompt must be caller-driven; neither may infer quick creation from generic pending/free fixture data.
- **REQUIRED — preserve Home’s conditional duplicate behavior:** Suppress only the existing Home RACES-section public-discovery opportunity while the new primary discovery section is actually visible. Do not hide the full Races tab, social `friendRacing` content, or leave an empty RACES header.
- **REQUIRED — account for bottom overlays:** Home’s wooden tab bar and race detail/results ad/footer areas reserve different bottom space. New sheets, the results action pair, inline Share, and large-text layouts need scroll clearance rather than fixed-height placement.

### Native install-handoff addendum

The automated suite stops at deterministic HTTP and persistence boundaries.
Before referral-aware links are enabled, repeat checklist item 2 on a clean iOS
install and a clean Android install using the staging landing page. Verify the
store handoff, first launch, signup attribution, and post-onboarding race preview
retain the same combined link independently on both platforms.
