# Automatic seeded-bucket auto-join — requirements

## Summary and user story

Starting with app version 2.3.3, a user who has already enabled **Auto-join
featured challenges** must be enrolled automatically in the private Daily and
Weekly bucket stream. They must not need to tap the Featured-card Join button.

> As a 2.3.3+ user with auto-join enabled, I am automatically placed in the
> next Daily/Weekly matching pool. I see my assigned private bucket after the
> pre-boundary matching job completes.

## Scope

- Applies only to `DAILY_10K` and `WEEKLY_50K`. The
  `seededRaceBucketsEnabled` flag selects only newly created windows; a
  stamped BUCKET window continues through completion if the flag later changes.
- A user is bucket-capable when the server has observed the
  `seeded_race_buckets` client-feature token from a 2.3.3+ authenticated app.
  `User.clientFeatures` is already a sticky, additive capability record
  (`src/middleware/requireAuth.js:60-97`; `prisma/schema.prisma:107-111`).
- At creation of an upcoming seeded window, the server durably stamps that
  window as `LEGACY` or `BUCKET`. The runtime flag selects only a *new* window;
  it can never change an already-stamped window. In BUCKET mode, bucket-capable
  auto-join users are elected into `SeededRaceWindowMembership` with
  `stream=BUCKET`; other auto-join users retain the legacy public-race flow.
- A bucket-capable user who upgrades after a PENDING legacy race was created is
  reconciled on their next capable `GET /races/featured`: before the bucket
  finalization cutoff, their PENDING legacy participant/membership is moved
  atomically to the BUCKET candidate stream. This route remains idempotent;
  its response shape is unchanged.
- No change to manual Join: it remains available for auto-join-off users and
  still uses `POST /races/seeded/:seedKind/assign`.

## Non-goals

- Do not modify, split, or transfer an ACTIVE or already-finalized race.
- Do not alter targets, economics, matching weights, capacity (15), privacy,
  or any non-seeded race type.
- Do not auto-enable the existing `autoJoinFeaturedRaces` setting for a user
  who has turned it off.
- An account's durable stream selection wins over a later app downgrade. An
  old/tokenless request for an account selected into BUCKET does not receive a
  joinable legacy Daily/Weekly row for that same window; it receives the
  legacy-compatible list with that seeded row omitted. It can continue using
  every unrelated legacy API. This prevents a visible Join action that the
  membership ledger must reject.

## Backend plan and API contract

1. Add an additive `SeededRaceWindowMode` Postgres table keyed by
   `(seedId, windowStart)`, with `mode LEGACY|BUCKET`, `windowEnd`, timestamps,
   and an index on `(windowStart, mode)`. It is written exactly once, under the
   shared window transaction, when renewal creates the next window. The table,
   membership ledger, assignments, participants, matching snapshots and
   finalization remain Postgres-only; Redis is never read by this flow.
2. Extend `src/modules/races/services/seededRaceBuckets.js` with a shared
   transaction helper that takes the PostgreSQL advisory window lock *before*
   any race lock, then re-reads the mode and membership under that lock. Every
   LEGACY claim, BUCKET election, automatic bulk election, and LEGACY-to-BUCKET
   transfer must use it. It creates/upserts only BUCKET ledger rows; it does not
   create races or buckets. Bulk selection filters
   `User.autoJoinFeaturedRaces=true` and `User.clientFeatures has
   'seeded_race_buckets'`, applies the existing inactivity filter before any
   capacity/selection operation, and orders user IDs deterministically.
   Add an expand-only partial/GIN index for this query.
3. Update `src/modules/races/commands/autoJoinFeaturedRaces.js` so legacy
   auto-enrollment explicitly excludes those bucket-capable users when bucket
   mode is stamped BUCKET. The remaining legacy selection still applies the
   same inactivity filtering and claims the LEGACY ledger through the shared
   window helper before creating participants. In LEGACY mode, it retains the
   current behavior for every user.
4. Update `src/modules/races/jobs/seededRaceRenewal.js` to stamp a mode and
   elect compatible auto-join users before legacy auto-enrollment whenever it
   creates the next PENDING Daily/Weekly race. The existing finalizer must read
   the durable mode rather than the live flag; it finalizes BUCKET windows only.
   The existing finalizer remains the sole creator of private bucket races in
   its pre-boundary window.
5. Pin every bucket-facing read/mutation path to the applicable stamped window
   mode: `GET /races/featured`, `/races/public`, `/races/discovery-summary`,
   Home race/discovery serialization, and
   `POST /races/seeded/:seedKind/assign`, and
   `PUT /auth/me/featured-auto-join`. The preference mutation resolves the
   upcoming stamped mode using the same shared window helper, not the live flag
   or request token alone: enabling in a BUCKET window elects an account into
   BUCKET only when its stored capability includes `seeded_race_buckets`, even
   if that enabling request is tokenless; a never-capable/tokenless account or
   any LEGACY window retains the legacy flow. The live flag is consulted only
   when creating an unstamped future window. Thus a later flag flip cannot hide
   an assigned BUCKET card, reject a valid manual election, or choose the wrong
   stream when auto-join is enabled.
6. In `GET /races/featured`, for a request carrying the bucket token and an
   `autoJoinFeaturedRaces=true` user, reconcile their upcoming PENDING stream
   under the same advisory lock. If they only have an unfinalized LEGACY
   participant, delete that pending participant, update its membership to
   BUCKET with `raceId:null`, and elect them. If a BUCKET/FINAL assignment or a
   boundary/final plan exists, do not move them. This is the one documented
   `GET` mutation: successful, cutoff, finalized, already-BUCKET, and
   no-legacy cases return the unchanged `200 {races}` shape; an infrastructure
   failure rolls back completely and returns `500 {error, code}`. A tokenless
   request for an account with a BUCKET membership filters out the matching
   legacy seeded row from Featured/Public discovery rather than exposing an
   unusable join action. Audit the full tokenless response matrix: `/races`,
   Featured, Public, discovery summary, Home suggestions/cards, and race detail
   must never expose an unrenderable private-bucket affordance or a legacy Join
   that the same account cannot use. Capable requests continue to receive their
   private bucket. A tokenless `GET /races/:id` for a private bucket race must
   return the existing-compatible non-revealing
   `404 {error: 'Race not found', code: 'RACE_NOT_FOUND'}` even for its
   participant; a capable participant retains the normal detail response.

The endpoint remains additive to older clients: requests without the token
skip reconciliation. They retain usable legacy enrollment unless the same
account has already durably selected BUCKET for that window, in which case the
seeded row is omitted as described above. The existing
`POST /races/seeded/:seedKind/assign` request/202 response is unchanged.

## Data model and safety

The additive window-mode migration and the existing membership ledger's unique
`(seedId, windowStart, userId)` constraint are the cross-stream authorities.
All transfer/election operations share the current window advisory lock and
are rejected/no-op once finalization begins, so a user cannot occupy a legacy
race and a bucket in the same window. The feature flag must not be changed for
an already-stamped window; operational rollback affects the next window only.
The migration supplies safe deployment behavior: it creates the table/indexes,
then transactionally classifies every existing PENDING/ACTIVE Daily/Weekly
window: a window that has a bucket race or a BUCKET ledger membership is
stamped `BUCKET`; a legacy-only window is stamped `LEGACY`. During the brief
schema-present/code-old phase and if an operational backfill must be retried, a
missing mode is read as `LEGACY`; only a new window created by new code may be
stamped `BUCKET`.

Safe default: empty/missing `clientFeatures` means legacy eligibility. This
protects pre-2.3.3 users and dormant accounts. A capability is only recorded
after an authenticated 2.3.3+ request, so a newly installed app becomes
eligible without a settings interaction.

## Frontend plan

No Flutter UI or API contract change is required for 2.3.3. It already sends
the capability token in `lib/services/backend_api_service.dart:164-166`, fetches
Featured races, renders `ELECTED`, and has the manual fallback in
`lib/screens/public_races_screen.dart:215-246`.

Both iOS and Android therefore use the same existing 2.3.3 behavior. Missing
bucket fields continue to render as the legacy featured card.

## Backward compatibility and rollout

1. Deploy the backward-compatible backend migration/code first, with the
   feature flag initially off in staging and production. Confirm all existing
   PENDING/ACTIVE seeded windows have been classified and stamped before
   enabling it.
2. Verify staging with a simulated 2.3.3 token and a tokenless client against
   the same auto-join-enabled users.
3. Enable the existing production flag only after confirming 2.3.3 is available
   on both iOS and Android. Do not flip the flag through a stamped Daily or
   Weekly window. Existing PENDING/ACTIVE legacy races are never migrated by
   the batch job; only a capable user's future, unfinalized PENDING membership
   may transfer on their request.
4. Monitor durable window mode and ledger counts by stream, candidate
   finalization, bucket sizes, and
   duplicate-membership errors for at least one Daily and one Weekly boundary.

## Tests-first plan

Backend integration tests (test database only):

- Creation of the next Daily/Weekly elects auto-join users with the stored
  bucket token and enrolls tokenless auto-join users in legacy, with no user in
  both streams.
- An enabled/disabled runtime flag transition after a window is stamped cannot
  strand candidates: finalization, all reads, legacy exclusion, and manual
  assignment use the stamped mode.
- Migration/backfill stamps currently-existing PENDING/ACTIVE windows BUCKET
  if they already contain a bucket race/ledger membership, otherwise LEGACY;
  missing mode during a mixed deploy reads as LEGACY and is never bucketed.
- A capable, auto-join user with a PENDING legacy membership is atomically
  transferred by Featured retrieval before finalization; repeat calls are
  idempotent.
- Concurrent capable Featured reconciliation and tokenless public
  join/auto-enrollment cannot create two memberships or a dangling participant.
- A selected BUCKET account using a tokenless client sees no joinable legacy
  seeded row; a tokenless LEGACY account retains that row.
- After a flag flip, capable Featured/Public/Discovery/Home reads still show
  the bucket selected by a stamped BUCKET window, and manual bucket assignment
  remains available to an auto-join-off capable user.
- A tokenless `PUT /auth/me/featured-auto-join` after a BUCKET window is
  stamped elects BUCKET only for an account with stored bucket capability; a
  never-capable tokenless account stays LEGACY.
- Tokenless `/races`, Featured, Public, discovery summary, Home, and detail
  paths do not expose an unrenderable bucket or an unusable legacy action for
  a BUCKET-selected account.
- A tokenless request to a private bucket's race-detail ID receives the exact
  non-revealing 404 contract; capable participants retain details.
- Auto-join-off capable users are not elected until they use manual Join.
- ACTIVE, finalized, and boundary-raced legacy memberships never transfer.
- Missing `clientFeatures`, a disabled flag, and older/tokenless requests
  preserve legacy behavior.
- Finalization creates only private buckets of at most 15 from the elected
  auto-join/manual candidate union.
- Automatic election/finalization works with `REDIS_URL` unset and does not
  introduce a request-path bulk `race_participants` write.

Frontend regression tests:

- Existing 2.3.3 featured-card tests continue to render an `ELECTED` card and
  assigned private bucket without a manual Join action being required.
- The client-feature header retains `seeded_race_buckets` on iOS and Android
  builds.

## Acceptance criteria

- A 2.3.3+ user with auto-join already enabled is automatically a BUCKET
  candidate for a future Daily/Weekly once their capable app has contacted the
  backend; a user upgrading after a PENDING legacy row is reconciled at their
  next capable Featured fetch before the finalization cutoff.
- A pre-2.3.3/tokenless auto-join user remains in the legacy race.
- No current/active or finalized race is moved, and no account is assigned to
  both streams for a window.
- `flutter analyze`, relevant Flutter tests, and backend unit/integration tests
  pass; iOS and Android release compatibility is explicitly checked.

## Revision log

- Gap pass 1: added the PENDING legacy-to-bucket reconciliation path; without
  it, users who upgraded after the next legacy row was created would remain
  legacy indefinitely.
- Gap pass 2: constrained reconciliation to capable requests and unfinalized
  future windows, preserving old-client behavior and preventing a late move
  during deterministic matching.
- Architect review: added durable window mode, a unified locking/lock-order
  requirement, matching inactivity filtering and indexing, atomic GET error
  semantics, Postgres-only placement, and a defined same-account downgrade
  response.
- Architect re-review: pinned every response/mutation path to durable window
  mode, added mixed-deploy LEGACY backfill semantics, and required the complete
  capable/tokenless endpoint matrix.
- Architect final revision: made backfill preserve pre-existing BUCKET windows
  and specified the tokenless bucket-detail 404 contract.
- Architect final compatibility pass: added the auto-join preference mutation
  to stamped-mode stream selection and its tokenless regression case.
- Architect predicate pass: narrowed tokenless preference election to accounts
  whose stored capability confirms 2.3.3+ bucket support.
