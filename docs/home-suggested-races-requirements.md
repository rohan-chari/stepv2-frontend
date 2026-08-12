# Home Suggested Races requirements

**Status:** Approved by user — implementation in progress.

## 1. Summary and user story

Replace Home's current `RACES` rail of races the viewer already joined with a
discovery-first `SUGGESTED RACES` carousel. The carousel helps a user enter a
new competition from Home in this strict category order:

1. current Daily challenge, then current Weekly challenge, but only when the
   viewer is not already participating in that challenge;
2. joinable public user-created races, when any exist;
3. joinable tournaments.

The Races tab remains the authoritative place to view races the user already
joined. Pending invitations remain in Home's separate promoted invite block and
in the newly approved Races-entry decision gate; they are never suggestions.

User story: as a walker on Home, I see the best new races I can actually join,
in a predictable horizontal rail, instead of spending that space on races I
already know about.

## 2. Current behavior and code map

- `HomeTab._buildRaceSection` in `lib/screens/tabs/home_tab.dart` renders a
  `RACES` header, `ACTIVE_RACES` tickets when joined races exist, or one legacy
  opportunity/empty row. `_buildActiveRacesRow` appends a browse-public card.
- `MainShell._fetchRaceCard` calls `GET /home/race-card` with
  `homeActiveRaces=1`; the backend returns at most five joined active races.
  That response also batches milestones, reward, global-event, and next-race
  data, so this feature must not remove the request or repurpose its shape.
- `GET /races/featured` already returns current seeded Daily/Weekly races with
  `myStatus`, capacity, prize, and an additive upcoming race.
- `GET /races/public` returns joinable public races and excludes the viewer,
  full races, matchup races, review races, and unsupported team races.
- `GET /tournaments/public` returns featured and user-created public brackets,
  including an exact additive `joinable` signal.
- `GET /races/discovery-summary` currently supplies featured races, featured
  tournaments, and a public count for the Races page. A backend that supports
  this older summary can still lack full Home suggestions, so absence of a new
  field cannot be confused with an empty suggestion list.
- Home and Races discovery are mirrored in demo/tutorial data. Existing tests
  anchor section order to `RACES`, and the Home tutorial can shift when this
  rail changes height.

## 3. Scope

### In scope

- Replace only the Home race rail/header with a horizontal Suggested Races
  carousel.
- Combine eligible Daily, Weekly, public race, and tournament cards in the
  strict category order approved above.
- Join/open actions use the existing race and tournament commands and screens.
- Refresh suggestions on initial Home load, pull-to-refresh, app resume, and
  after a successful join/opt-in.
- Preserve existing pending-invite and Next Race/quick-create sections above it.
- Add a version-skew-safe backend contract and fallback.
- Update the real Home screen, tutorial/demo fixtures, placement tests, and
  activation analytics.

### Non-goals

- No recommendation algorithm, personalization score, sponsored placement, or
  geographic matching.
- No change to race/tournament rules, payouts, capacity, join validation, seed
  renewal, or auto-join settings.
- No removal of active races from the Races tab.
- No change to the separate pending-invite block or Races-entry invite gate.
- No production flag flip or deploy without separate approval.

## 4. Eligibility and deterministic ordering

The backend is authoritative. It must build suggestions from the same queries
and joinability rules used by public/featured surfaces; the client must not
infer capacity or membership from partial payloads.

### 4.1 Featured Daily and Weekly

- Consider only the live `ACTIVE` seeded `DAILY_10K` and `WEEKLY_50K` races
  whose `endsAt` is in the future.
- Hide a featured race when the viewer's participant status for that exact live
  race is `ACCEPTED` or `INVITED`; it is not a new race for them to join.
- Full races are not suggestions. Review/demo seeds are not suggestions to prod
  users under existing release-channel rules.
- Order Daily before Weekly, regardless of timestamps.
- If the viewer is already `ACCEPTED` or `INVITED` in the live seed, hide that
  seed entirely. Do not substitute its upcoming pre-registration race; it can
  become eligible after the live race ends and the next one becomes current.

### 4.2 Public user-created races

- Reuse `getPublicRaces` visibility exactly: public, joinable under current race
  status/team rules, not full, not a tournament matchup, not review-created,
  and no viewer participant row under today's contract.
- Extend the internal public query with a default-false `excludeSeeded` option
  and a separate suggestion mode whose complete eligibility predicate precedes
  its four-row limit. Home passes `excludeSeeded:true`, applying `seedId:null`
  in Postgres before serialization. Existing `/races/public` omits both options
  and remains byte-compatible. Exclusion must remain correct even if the
  featured branch fails.
- Order candidates by `createdAt DESC, id ASC` before filtering/capping.
- Take at most four eligible public races.

### 4.3 Tournaments

- Combine featured tournament brackets and user-created public tournaments
  whose server `joinable` value is literal true.
- A bracket the viewer already joined, a full bracket, or another bracket of a
  featured seed in which the viewer is still alive is not suggested.
- Featured tournaments precede user-created tournaments. Each group orders by
  `createdAt DESC, id ASC` before the combined four-card cap.
- Clients without the `tournaments` feature continue to receive no tournament
  suggestions.
- Take at most four tournaments after merging featured and user-created
  brackets under the ordering above. Tournaments remain a first-class category;
  the cap never replaces them with extra public races.

### 4.4 Total order

The response is already ordered:

`Daily → Weekly → up to 4 public races → up to 4 tournaments`.

The maximum response is ten cards: one Daily, one Weekly, four public races,
and four tournaments. Empty earlier categories do not increase another
category's cap.

The Flutter client preserves response order, filters only malformed entries,
and never reranks valid entries locally.

## 5. API contract

### 5.1 New `GET /home/suggested-races`

This separate additive endpoint gives version-skew an unambiguous 404 and keeps
the existing Home batch and Races discovery-summary contracts unchanged.

Request: authenticated GET; no required query parameters. Existing
`X-Client-Features` continues to advertise `team_races` and `tournaments`; add
`home_suggested_races` in both Flutter header-construction paths for rollout
visibility, but never require it for authentication.

Success `200`:

```jsonc
{
  "suggestions": [
    {
      "kind": "FEATURED_RACE",
      "id": "race-daily-id",
      "seedKind": "DAILY_10K",
      "name": "Daily 10K",
      "status": "ACTIVE",
      "endsAt": "2026-08-12T04:00:00.000Z",
      "participantCount": 42,
      "maxParticipants": 100,
      "isFull": false,
      "powerupsEnabled": true,
      "prizePool": null,
      "finishReward": null,
      "joinAction": "JOIN"
    },
    {
      "kind": "PUBLIC_RACE",
      "id": "public-race-id",
      "name": "Lunch Break Sprint",
      "status": "PENDING",
      "maxDurationDays": 1,
      "endsAt": null,
      "startedAt": null,
      "participantCount": 3,
      "maxParticipants": 10,
      "buyInAmount": 0,
      "payoutPreset": "TOP_HALF_GRADED",
      "powerupsEnabled": true,
      "prizePool": null,
      "isTeamRace": false,
      "teamSize": null,
      "teamAName": null,
      "teamBName": null,
      "teams": null,
      "joinAction": "JOIN"
    },
    {
      "kind": "TOURNAMENT",
      "id": "tournament-id",
      "seedKind": "DAILY_DASH",
      "name": "Daily Dash",
      "status": "PENDING",
      "bracketSize": 8,
      "matchupDurationDays": 1,
      "acceptedCount": 5,
      "buyInAmount": 0,
      "potCoins": 800,
      "prizePool": null,
      "powerupsEnabled": true,
      "powerupStepInterval": 2000,
      "createdAt": "2026-08-11T20:00:00.000Z",
      "joinAction": "JOIN"
    }
  ],
  "resolved": {
    "featuredRaces": true,
    "publicRaces": true,
    "tournaments": true
  }
}
```

All three `resolved` keys are required literal Booleans on every 200. Without
the `tournaments` client feature, `resolved.tournaments` is true and there are
zero `TOURNAMENT` entries: the category is known unsupported/empty, not failed.

The exact discriminated entry contracts are:

- `FEATURED_RACE`: required `kind:"FEATURED_RACE"`, nonempty `id` mapped from
  canonical `raceId`, `seedKind` equal to `DAILY_10K` or `WEEKLY_50K`, nonempty
  `name`, `status:"ACTIVE"`, ISO-string `endsAt`, nonnegative integer
  `participantCount`, positive integer `maxParticipants` (the existing featured
  serializer's unlimited compatibility value is 100), Boolean `isFull`, Boolean
  `powerupsEnabled`, `prizePool` object-or-null, `finishReward` object-or-null,
  and `joinAction:"JOIN"`.
- `PUBLIC_RACE`: required `kind:"PUBLIC_RACE"`, nonempty string `id`, nonempty
  `name`, `status` equal to `PENDING` or `ACTIVE`, positive integer
  `maxDurationDays`, `endsAt` and `startedAt` ISO-string-or-null, nonnegative
  integer `participantCount`, positive integer-or-null `maxParticipants`,
  nonnegative integer `buyInAmount`, string-or-null `payoutPreset`, Boolean
  `powerupsEnabled`, `prizePool` object-or-null, Boolean `isTeamRace`, positive
  integer-or-null `teamSize`, string-or-null `teamAName`/`teamBName`, canonical
  `teams` object-or-null, and `joinAction:"JOIN"`.
- `TOURNAMENT`: required `kind:"TOURNAMENT"`, nonempty string `id`/`name`,
  `status:"PENDING"`, positive integer `bracketSize` and
  `matchupDurationDays`, nonnegative integer `acceptedCount`, `seedKind`
  string-or-null, nonnegative integer `buyInAmount`/`potCoins`, `prizePool`
  object-or-null, Boolean `powerupsEnabled`, positive integer-or-null
  `powerupStepInterval`, ISO-string `createdAt`, and `joinAction:"JOIN"`.

No other keys are part of this Home contract. The backend adapts from the
existing canonical money/team/tournament serializers rather than recomputing
them, explicitly maps `raceId → id`, adds fixed `status:"ACTIVE"` for featured
races, and never invents tournament `scheduledStartAt`, which the canonical
summary does not expose.

Errors use the existing authenticated error envelope. Optional branch failure
does not turn a known-empty category into stale content: the endpoint uses
`Promise.allSettled` and returns additive exact resolution bits:

```json
{
  "suggestions": [],
  "resolved": {
    "featuredRaces": true,
    "publicRaces": false,
    "tournaments": true
  }
}
```

The service merges only resolved categories. The Flutter state retains the
last-known entries for an unresolved category and replaces entries for a
resolved category, including replacing them with an empty list. Each entry
therefore needs an internal category tag before the final ordered merge.
The response's `suggestions` array contains entries only from branches that
resolved successfully; it never repeats cached server-side data for a failed
branch. `resolved.featuredRaces` owns `FEATURED_RACE`,
`resolved.publicRaces` owns `PUBLIC_RACE`, and `resolved.tournaments` owns every
`TOURNAMENT` entry, making the client merge unambiguous.

### 5.2 New app + old backend fallback

- A definite endpoint 404 marks `/home/suggested-races` unsupported for the
  session and runs existing featured-race, public-race, and public-tournament
  calls concurrently.
- Fallback runs all three legacy calls under `Promise.allSettled`, owns the same
  three categories independently, and never converts one branch's failure into
  a known empty list. A successful legacy response is resolved; a definite 404
  means that category is unsupported and therefore resolved-empty; any other
  HTTP/transport/malformed failure is unresolved and retains its cached category.
- Legacy tournaments are included only when their additive `joinable` value is
  literal true; missing/null/false is safely excluded.
- Legacy public-race entries lack a seed discriminator. When featured legacy
  discovery succeeds, deduplicate public entries by every successfully returned
  featured `raceId` before applying public ordering/cap. Featured fallback is
  proof-capable only when its response is a list and every raw entry has a
  nonempty `raceId` plus `seedKind` equal to `DAILY_10K` or `WEEKLY_50K`; a
  malformed mixed list makes that branch unresolved. If featured discovery is
  unresolved or resolved only through 404, a nonempty public response cannot
  prove seeded exclusion and the public category is marked unresolved instead
  of risking duplicate/misclassified seeds. A truly empty public response is
  safely resolved-empty.
- 400/401/429/500, transport failure, or malformed 200 never mark unsupported
  and never fan out into duplicate requests; retain last-known suggestions and
  show retry only when no prior data exists.
- Old app + new backend never calls this endpoint, continues receiving the
  existing `ACTIVE_RACES` Home state, and ignores the new feature token.

## 6. Flutter presentation

### 6.1 Section and carousel

- Replace `_HomeRaceHeader` text `RACES` with `SUGGESTED RACES` on Home only.
- `VIEW ALL` opens the existing combined Public Races discovery screen; it does
  not open the user's joined-races tab or a joined active race.
- Use one horizontal `ListView` with partially visible next card, snap-like
  physics, stable keys `home-suggestion-<kind>-<id>`, and no auto-advance.
- Cards reuse the visual language and compact information hierarchy of
  `FeaturedRaceCard` and `TournamentGameCard`, adapted to one consistent Home
  footprint. They are parchment tickets over the green Home board, with one
  category eyebrow, race name, time/duration, population/capacity, optional
  prize chip, and one clear `JOIN` action. Do not recreate full detail cards.
- Daily and Weekly use distinct existing seed labels; public race uses
  `PUBLIC`; tournament uses `TOURNAMENT`. Team public races keep a compact team
  badge/slots line when supported.
- Joining must reuse one extracted coordinator from `PublicRacesScreen`, not a
  simplified parallel flow: legacy paid races/tournaments retain balance checks
  and buy-in confirmation; funded entries remain one tap; team races show the
  existing side picker and call the team-aware join endpoint; all existing
  coded error copy and post-join coin/held-coin refresh remains intact.
- Joining disables only that card and shows in-card progress. On success remove
  the exact suggestion ID immediately from visible state using the successful
  join response as authority, add it to a session/user-scoped tombstone set,
  preserve scroll position where possible, refresh core races/Home batch and
  suggestions, and immediately route to the joined race or tournament detail.
  An unresolved or stale refresh may never reinsert a tombstoned ID. Clear
  tombstones only on authenticated-user change or once a later fully resolved
  category confirms the ID absent. On failure create no tombstone, restore the
  action, and show the existing concise error mapping.

### 6.2 Loading, empty, error, and accessibility

- First load: three fixed-height horizontal skeleton tickets so lower Home
  content does not jump.
- Empty after every category resolves: keep the section and show one compact
  `NO RACES TO SUGGEST` ticket with a `BROWSE ALL` action that opens Public
  Races. Never remove the discovery entry point from Home.
- Total initial failure with no cached data: same-height retry ticket. Partial
  failure renders known categories and no alarming global error.
- Semantics announce category, name, availability, prize when present, and
  `Join <name>`. Horizontal scrolling remains reachable under VoiceOver and
  TalkBack. Support 1.3 text scale and narrow devices without card overflow.

## 7. State, refresh, analytics, and mirrors

- `MainShell` owns a category-aware `Loadable` suggestions state and monotonic
  generation so stale refreshes cannot overwrite a successful join refresh.
- Initial load and resume may run suggestions beside existing Home work, but
  suggestions must not gate result/What's New modals. Pull-to-refresh awaits the
  suggestions refresh so the rail is truthful when the indicator stops.
- Home no longer invokes `_refreshRacesDiscovery()` during initial/resume/pull
  loading, and `_fetchRaces()` is split so its core-list refresh does not
  implicitly trigger discovery. Home loads core races plus suggestions only.
  Races-tab entry invokes `_refreshRacesDiscovery()` authoritatively after the
  invite gate resolves, so no Home refresh duplicates featured/public/tournament
  fan-out.
- After join/opt-in, refresh suggestions, Home batch, and core race/tournament
  state. Do not optimistically invent membership.
- Analytics: a Home impression epoch begins when the shell transitions from a
  non-Home tab to Home, and on app resume while Home is visible. Emit
  `home_suggested_races_shown` once when that epoch first reaches any resolved
  visible/empty state, with counts by category. Retry, partial merge, rebuild,
  and join refresh do not reset the epoch or double-fire. Emit
  `home_suggested_race_tapped` with kind/id/position; existing join success/
  failure events remain authoritative and must not double-fire.
- Tutorial Home fixture receives a deterministic Daily, public, and tournament
  sequence so placement and horizontal clipping are exercised without network.
  Re-measure the first Home spotlight and everything below the rail.

## 8. Backend implementation path

1. Add integration tests against real HTTP/DB for endpoint shape, ordering,
   eligibility, partial resolution, and feature-token behavior.
2. Add `src/modules/home/queries/getSuggestedRaces.js`, exporting
   `buildGetSuggestedRaces(dependencies = {})` and its production instance. It
   injects the featured/public/tournament queries and logger, calls them under
   `Promise.allSettled`, and adapts their canonical serializers. Export the
   query from `src/modules/home/index.js` before routes.
3. Inject `getSuggestedRaces` through `createHomeRouter`. Add a thin
   parse/call/respond-only authenticated handler through `asyncHandler`; no raw
   Prisma, hard-imported collaborator calls, or business error mapping in the
   handler, and no changed legacy endpoints.
4. Add the feature token to recognized capability parsing only; no runtime flag
   is required because only new clients call the additive endpoint.
5. Verify query count/bounds and ensure no per-card N+1.

### 8.1 Storage and bounded reads

- Launch Postgres-only: no Redis result cache, cache key, invalidation contract,
  or rollout flag. This is a user-triggered Home/resume read rather than polling;
  measure production latency/query volume before adding cache complexity.
- Eligibility is applied in Postgres **before** `LIMIT`; the service may not take
  a newest candidate window and then filter it in memory. Public SQL enforces
  seed/review/team/tournament/status rules, `NOT EXISTS` viewer membership, and
  accepted-count capacity before `ORDER BY created_at DESC, id ASC LIMIT 4`.
  Where Prisma cannot compare an accepted aggregate to nullable capacity, use a
  parameterized model-level CTE/raw query rather than weakening eligibility.
- Tournament SQL likewise applies viewer membership, accepted-count capacity,
  featured-seed alive-in-another-bracket exclusion, seed/public grouping, and
  literal joinability before ordering and the combined four-row limit. Featured
  precedes user-created, with `createdAt DESC, id ASC` inside each group.
- Daily/Weekly eligibility is applied before the one-per-seed selection and
  Daily-before-Weekly merge. The database returns aggregate accepted/team counts
  and only fields needed by canonical money/team serializers; it does not load
  arbitrary participant collections merely to discard candidates.
- At most three category reads run in parallel (featured races, public races,
  tournaments), with no per-card query and at most ten suggestion rows returned.
  Internal SQL subqueries/CTEs remain one database round-trip per category.
  Growth in newer full, viewer-owned, seeded, review, or otherwise ineligible
  rows cannot hide an older eligible suggestion or increase result rows loaded.
- Optional internal `excludeSeeded`/suggestion-query inputs default false so
  legacy route behavior remains unchanged. `VIEW ALL` remains the exhaustive
  discovery path beyond the 1+1+4+4 eligible result limit.

## 9. Frontend implementation path

1. Add service/model tests for supported 200, partial-resolution merge, definite
   404 legacy fallback, transient error retention, malformed entries, and
   generation ordering.
2. Add widget tests for strict card order, joined-featured exclusion, empty/
   loading/error, join in-flight/success/failure, text scale, and semantics.
3. Add `home_suggested_races` to both feature-header paths and a defensive
   `HomeRaceSuggestion` parser with no unchecked casts/non-null assertions.
4. Add the shell state/refresh/join coordination without removing the still-
   required Home batch.
5. Replace only the Home race rail. Reuse/refactor existing card primitives
   without changing the Races/public screens, and extract their existing paid,
   funded, team-side, tournament, error, and balance join coordination for reuse.
   The extracted coordinator returns a typed success/handoff result; `MainShell`
   owns tombstoning, refresh, and navigation so it is not coupled to
   `PublicRacesScreen` dismissal behavior.
6. Update tutorial/demo fixtures, protected section-order assertions, and manual
   coach-anchor checks.

## 10. Backward compatibility and rollout

- Backend deploys first. The new endpoint is additive and old clients never call
  it. Existing `/home/race-card`, `/races/featured`, `/races/public`, and
  `/tournaments/public` behavior remains unchanged.
- New app against old backend uses only a definite 404 to select legacy parallel
  discovery. Missing/null fields safely omit one malformed card, never crash the
  whole rail.
- iOS and Android ship together with the same feature token and UI.
- No schema migration, content seed, economy change, or asset is required.

## 11. Tests and definition of done

### Backend integration tests first

- Exact Daily → Weekly → public → featured tournament → public tournament order.
- Joined/invited Daily or Weekly hidden independently; full/expired seeds hidden.
- Public seeded duplication prevented; viewer/full/review/unsupported-team rows
  hidden using existing rules.
- Tournament `joinable` exact true only; clients without token receive none.
- Partial branch failure sets only its resolution bit false and keeps HTTP 200.
- Every 200 has the exact discriminated fields and all three Boolean resolution
  keys; tokenless tournament category is resolved-empty.
- Public `excludeSeeded:true` remains correct when featured throws. Legacy
  fallback covers every success/404/transient combination and never duplicates
  an unprovable seed.
- Category reads remain at three or fewer and returned suggestion rows at ten or
  fewer as hundreds of newer irrelevant rows are added. Add explicit fixtures
  with more than 32 ineligible public races and more than 16 ineligible
  tournaments ahead of an eligible row; the eligible row must still appear.
- Old endpoints remain byte-compatible for frozen clients.

### Flutter widget/integration tests first

- Real Home screen replaces joined active tickets with suggestions and preserves
  pending-invite/Next Race/milestones/feedback order.
- Strict mixed-category order and empty-category omission.
- 404 fallback makes legacy calls once; other errors do not downgrade.
- Initial/partial/empty/error states, retry, stale generation, and cached refresh.
- Join button in-flight, success removal/refresh/navigation, and mapped failure.
- Successful join tombstones immediately; stale/unresolved refresh cannot
  resurrect the ID. Failed join never tombstones.
- Home emits no Races discovery request; Races entry still refreshes discovery.
- Impression analytics fires once per visibility epoch across retries/merges.
- Tutorial fixture, 1.3 text scale, narrow viewport, VoiceOver/TalkBack semantics.

### Done

- New focused tests pass; protected existing assertions are not weakened.
- `flutter analyze` and full `flutter test` are clean apart from separately
  documented pre-existing failures.
- Backend unit/integration verification runs only against a verified local
  `*_test` database; never bare `npm test`.
- iOS and Android are accounted for, architect/code review pass, and the manual
  UI-placement checklist is handed to the user.

## 12. Interview decisions

Decided by the user on 2026-08-11:

1. Hide a Daily/Weekly seed entirely when the viewer is already in its current
   live race; do not substitute the upcoming instance.
2. Cap the rail at one Daily, one Weekly, four public races, and four tournaments.
   Tournaments must remain present as their own capped category.
3. A successful join immediately opens the race/tournament detail.
4. A fully empty rail remains visible with the recommended compact Browse All
   ticket.
5. `VIEW ALL` and the empty ticket open the existing Public Races discovery
   screen.

## 13. Manual UI-placement test plan

**Manual UI-Placement Test Plan — Home Suggested Races**

*Elements under test:* Home’s joined-race `RACES` rail is replaced in the same section slot by a `SUGGESTED RACES` horizontal carousel.

*Elements under test:* Suggested cards appear in the fixed order Daily, Weekly, public races, then tournaments, with a partially visible next card.

*Elements under test:* The former trailing `PUBLIC / Find a race` tile is removed; `VIEW ALL` in the section header becomes the persistent Public Races entry point.

*Elements under test:* Loading uses three fixed-height skeleton tickets; fully empty and initial-error states each use one compact ticket in the carousel slot.

*Elements under test:* A joined suggestion disappears from the carousel and the corresponding race or tournament detail opens.

*Checklist*

1. **Home — mixed suggested-race carousel**
   - **Get there:** Sign in with a staging account eligible for a Daily, Weekly, at least one public race, and at least one tournament; scroll below Today’s Coins.
   - **Verify:** `SUGGESTED RACES` occupies the old Home `RACES` section position. Cards run left-to-right as Daily, Weekly, public race(s), then tournament(s). The first card is fully visible and part of the next card is visible at the right edge. Swipe horizontally and verify all cards share one height, remain inside the Home gutters, and do not clip vertically. Joined-race standings tickets and the old trailing `PUBLIC / Find a race` tile are absent from this section.

2. **Home — section order with pending invite and Next Race**
   - **Get there:** Use an account with an incomplete SETUP item, a promoted pending invite, a visible Next Race prompt, and suggestions; scroll through Home.
   - **Verify:** The vertical order is SETUP → pending invite → Next Race → Today’s Coins/milestones → Suggested Races → feedback. Suggested Races is not duplicated above Today’s Coins or inside the pending-invite/Next Race blocks, and the pending invite never appears as a suggestion card.

3. **Home — narrow device and 1.3 text scale**
   - **Get there:** Open the mixed carousel on the smallest supported iPhone and Android device; set system text size to approximately 1.3×.
   - **Verify:** Every category card keeps its title, compact facts, optional prize area, and JOIN action inside the common ticket bounds. Long race/tournament names do not increase one card’s height, overlap the card below, or hide the partial-next-card cue. Horizontal swiping does not cause the overall Home page to move sideways.

4. **Home — initial loading**
   - **Get there:** Cold-launch Home on a throttled connection with no cached suggestions.
   - **Verify:** `SUGGESTED RACES` appears in its normal section position with three fixed-height horizontal skeleton tickets beneath it. The old joined-race skeleton/active tickets do not also render. When content replaces the skeletons, the feedback card remains below the section and does not make a large vertical jump.

5. **Home — fully empty state**
   - **Get there:** Use a staging fixture where all suggestion categories resolve successfully with no eligible entries.
   - **Verify:** The `SUGGESTED RACES` header remains visible and one compact `NO RACES TO SUGGEST` ticket occupies the carousel slot with `BROWSE ALL`. The entire section is not removed, there is no blank rail-height gap, and no legacy `Race your friends`, `BROWSE`, `INVITE`, or trailing public tile remains in the old location.

6. **Home — initial error and cached/partial refresh**
   - **Get there:** First load with suggestion requests failing and no cache; then repeat with cached suggestions while one category refresh fails.
   - **Verify:** With no cache, one retry ticket occupies the same footprint as the empty/content card area beneath `SUGGESTED RACES`; no separate full-width error panel appears elsewhere on Home. With cached or partially resolved content, known cards stay in the carousel and no global error card is inserted above or below it.

7. **Public Races navigation**
   - **Get there:** From a populated Suggested Races section, tap `VIEW ALL`; return Home, load the empty state, and tap `BROWSE ALL`.
   - **Verify:** Both controls push the existing `PUBLIC RACES` screen with its header and discovery filters. Neither switches to the personal Races tab, opens a joined race, nor leaves a second Suggested Races rail beneath the destination.

8. **Join-to-detail placement**
   - **Get there:** Join one race suggestion, then one tournament suggestion.
   - **Verify:** Only the tapped card shows progress in its existing JOIN-control position; neighboring cards remain in place. After refresh, the joined card is absent from its former carousel position and the appropriate race/tournament detail screen is frontmost. Returning Home shows the remaining cards closed up in category order without an empty hole or duplicated joined card.

9. **Home tab tutorial mirror**
   - **Get there:** Profile → Settings/Admin → re-run the tutorial; inspect the opening Home step and the final Home/shop step.
   - **Verify:** The real Home preview contains a deterministic Daily → public → tournament Suggested Races carousel, with a partially visible next card and no old active-race ticket. On the opening step, the spotlight still rings the step total. On the final Home step, it still rings SHOP rather than the carousel or an offset location. Suggested Races remains below the tutorial’s Today’s Coins area and above feedback.

10. **Real Home coach-tip placement**
    - **Get there:** Use an onboarding-v3 account with a claimable milestone and an unseen milestone coach tip; open Home and scroll to Today’s Coins.
    - **Verify:** The milestone coach tip remains attached to the milestone section above Suggested Races. It is not pushed into, covered by, or anchored to the carousel after the rail height changes. Dismissing it leaves the carousel in the same section position.

*Surfaces confirmed unaffected:* The personal Races tab continues to show joined active/waiting/completed races; Home’s removal of joined-race tickets does not remove or relocate those rows.

*Surfaces confirmed unaffected:* The existing Public Races screen remains the full discovery destination; its featured/tournament/race filters and card placement are reused rather than mirrored on Home.

*Surfaces confirmed unaffected:* The promoted Home pending-invite block remains above Today’s Coins and is not part of the suggestion carousel.

*Surfaces confirmed unaffected:* The Home Next Race/quick-create section remains above Today’s Coins and Suggested Races.

*Surfaces confirmed unaffected:* `DemoRaceHost` has no Home surface and does not instantiate `HomeTab`, so there is no demo-race carousel mirror to test.

*Surfaces confirmed unaffected:* The Races-tab and race-detail tutorial previews do not render Home’s carousel; only the tutorial’s two Home beats share this screen.

*Risks found while planning:*

- `tutorialPreviewHomeRaceCard()` is currently hard-coded to `ACTIVE_RACES`. It must be replaced or supplemented with deterministic Daily, public, and tournament suggestions or the tutorial will keep exercising the removed rail.
- `tutorial_real_screens.dart` constructs the real `HomeTab` directly. Any new suggestion state/callback omitted there can produce loading/empty UI instead of the required tutorial sequence.
- The Home tutorial’s first and last steps anchor `home.steps` and `home.shop`. The spotlight keys will still compile if the carousel changes vertical geometry, so both positions must be manually remeasured.
- The milestone coach anchor sits above the changed rail, but Home section-order tests explicitly pin pending invite, Next Race, milestones, race section, and feedback. Updating only the header/card widgets can leave stagger indices or loading-state order inconsistent.
- Current Home navigation wiring uses `onOpenRacesTab` for the `RACES` header, while the old trailing public tile pushes `PublicRacesScreen` itself. The new header and empty ticket need one shared Public Races route or one may still open the personal Races tab.
- The current race rail and skeleton reserve a 240px section with 222px tickets. A new card height applied only to loaded content will move feedback when loading resolves; loaded, loading, empty, and error footprints need to match.
- A horizontal list without deliberate viewport/card width can fully fit the next card on wide devices or hide it entirely on narrow devices, removing the intended scroll cue.
- Home’s existing feedback card is always the last block, including in the tutorial. A taller carousel or unbounded error/empty card can push it excessively far down or overlap it.
- Card removal after joining can reset the horizontal offset or leave an empty keyed slot. This is most visible when joining a middle public/tournament card rather than the first card.

## 14. Revision log

- Initial draft: mapped the existing active-race Home rail, four discovery data
  sources, and current summary compatibility behavior; proposed an additive
  endpoint with definite-404 fallback and category-aware partial resolution.
- Gap pass 1: separated pending invites/Next Race from suggestions, prevented
  seeded duplication, specified client capability gating and joined/invited/full
  eligibility, and preserved the existing multi-purpose Home batch.
- Gap pass 2: added category-aware stale-data merging, monotonic refresh/join
  behavior, bounded-query requirement, tutorial/coach risks, accessibility,
  analytics deduplication, and explicit empty/error behavior.
- User interview: locked current-seed hiding, the 1+1+4+4 category cap, required
  tournament inclusion, immediate detail navigation, persistent empty discovery
  entry point, and Public Races routing.
- Post-interview gap pass 1: made partial-resolution category ownership exact and
  prohibited stale server entries from leaking into unresolved branches.
- Post-interview gap pass 2: preserved paid/funded/team/tournament join safety by
  requiring reuse of the existing coordinator, and prohibited duplicate Home
  discovery fan-out for the same featured/public/tournament queries.
- Architect revision: made every discriminated response field and resolution bit
  exact; added query-level seeded exclusion and total ordering; locked safe
  legacy fallback, join tombstones, Races-entry-only discovery, bounded
  Postgres-only reads, and the injected Home module contract.
- UI placement review: added the verbatim real/tutorial Home checklist and made
  rail footprint, Public Races routing, coach anchors, and card-removal offset
  risks explicit implementation requirements.
- Post-architect gap pass 1: required proof-capable legacy featured payloads
  before using their IDs to classify public fallback entries.
- Post-architect gap pass 2: rechecked exact field sources, session/user-scoped
  tombstones, the 1+1+4+4 bounded sample, and fixed-footprint tutorial/loading/
  empty/error mirrors; no additional product questions remained.
- Final architect correction: moved every membership/capacity/seed/review/team/
  tournament eligibility predicate ahead of SQL `LIMIT`, replacing the flawed
  pre-filter candidate windows while retaining three bounded category reads and
  the exact 1+1+4+4 eligible result cap.
- Final architect re-review: APPROVE with no remaining required issues or
  suggestions.
