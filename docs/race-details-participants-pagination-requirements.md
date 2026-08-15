# Race details participants pagination — requirements

> Cross-reference: this spec paginates `race.participants` on the
> details/bootstrap response. A separate, already-shipped spec,
> `docs/race-participants-pagination-requirements.md`, paginated the
> *different* `progress.participants` array (steps/leaderboard, polled
> periodically) plus added `/races/:raceId/powerups/use-context`. The two
> docs cover similarly-named but distinct arrays with **different
> carve-out rules** (that one excludes PENDING/team races from paging; this
> one deliberately does not — see Scope below) — don't conflate them.

## Summary & user story

As a player opening a race detail screen — especially a large seeded public
race (`Weekly Challenge`, `Daily Challenge`), which regularly has 100-477
participants in prod today — I want the screen to load quickly. Right now
`getRaceDetails` (`stepv2-backend/src/modules/races/queries/getRaceDetails.js:118`)
always serializes **every** participant's full profile (display name, photo,
animal + equipped accessories + each accessory's `shopItem.renderMetadata`)
into the `race.participants` array, on every call to `GET /races/:id`,
`GET /races/:id/bootstrap`, and `GET /races/:id/bootstrap?view=...`.

This was root-caused from live prod nginx logs (2026-08-15 sample, 300k lines):

| route | n | p50 | p95 | max | avg payload | max payload |
|---|---|---|---|---|---|---|
| `/races/:id/bootstrap` | 148 | 89ms | 1.0s | 1.7s | 10.3KB | 66.5KB |
| `/races/:id/bootstrap?view=...` | 120 | 105ms | 2.0s | **9.4s** | 11.2KB | 45.3KB |
| `/races/:id` (legacy) | 788 | 42ms | 990ms | 2.9s | 6.4KB | 40.2KB |

Cross-referenced against prod race sizes (`race_participants` grouped by
`race_id`, `status IN ('active','pending')`):

```
Weekly Challenge (active)  — 477 participants
Weekly Challenge (pending) — 473 participants
Daily Challenge (active)   — 247 participants
Daily Challenge (pending)  — 184 participants
```

### ⚠️ Architect-flagged: slicing the response alone does not fix the latency

The initial draft of this spec assumed trimming the *serialized* array would
fix the multi-second tail latency. **That's only true for payload size, not
for the dominant cost.** `Race.findById` (`race.js:178-191`) — the query
`getRaceDetails` runs — always uses the fat `participantInclude`
(`race.js:4-39`: every participant → `user` → `equippedAccessories` →
`shopItem` with full `renderMetadata`). That file's own comment
(`race.js:95-101`) states this cosmetic subtree is "four Prisma queries and
the dominant cost of the read." Slicing `result.participants` in the
serializer (`getRaceDetails.js:118-141`) happens **after** that full query
already ran — it cuts JSON bytes and serialization CPU, not database time.
Two aggravating details:
- On the bootstrap main branch, the details call already reuses
  `resolvedContext.race` as `preloadedRace` (`routes.js:1018-1021`, set by
  `getRaceProgress.js:1429-1431`) — so on that path the *only* thing
  pagination removes today is the map/serialize step, not any query.
- On the legacy `GET /:raceId` (`routes.js:1091`), there's no preload at
  all — the full fat 477-participant query runs regardless of pagination.

**This spec's implementation must therefore change the query plan, not just
the serializer**, for the win to be real (see API contract → "Query plan").
Payload-size reduction (the 66KB→~2-5KB win) is real and immediate from
serialization alone; the **latency** win requires the lean-query change
below. Acceptance criteria reflect both, separately.

The existing `progress` pagination (`view=participants-v1&offset&limit`,
`getRaceProgress.js:1341-1375`) does **not** fix any of this: it only slices
the separate `progress.participants` array (steps/leaderboard, polled
periodically), never `race.participants` (profiles, fetched once per race
open). Worse, that existing pagination has a documented gap that happens to
hit exactly the worst offenders: `pageableShape = status === 'ACTIVE' &&
!isTeamRace` (`getRaceProgress.js:1341-1348`) — **PENDING races are never
sliced**, and the two biggest races in prod (`Weekly Challenge` pending/473,
`Daily Challenge` pending/184) are PENDING. This spec's pagination must not
repeat that gap.

The frontend already sends the wire contract needed to opt in:
`fetchRaceBootstrap` (`stepv2-frontend/lib/services/backend_api_service.dart:2381-2405`)
already appends `?view=participants-v1&offset=0&limit=$participantsLimit`
whenever the caller passes `participantsLimit` — the backend already reads
this for `progress`, it simply never applies it to `race.participants`. No
new frontend query param is required for that path (though see the
capability-gating requirement below — the query param is necessary but not
sufficient for the new behavior to activate).

## Scope / non-goals

**In scope:**
- Change `getRaceDetails`'s **query plan** so a paginated request doesn't
  run the fat cosmetic join for all N participants — see API contract →
  "Query plan" for the exact design.
- Paginate `race.participants` in the response, honoring
  `view=participants-v1&offset&limit`, gated on a new capability token (see
  API contract).
- Add lightweight **summary fields** (`acceptedCount`,
  `teamAAcceptedCount`/`teamBAcceptedCount`, and — per the expanded
  consumer audit below — `myTeam`/`myTotalSteps` where not already present,
  and `participantUserIds`) so frontend consumers that currently derive
  counts/membership/ID-sets by scanning the full `participants` array can
  stop needing the full array at all.
- Cap the **pending-race hero render** (`goal_track.dart`'s
  `GoalTrackRunner` list, built unconditionally from every ACCEPTED
  participant in `race_detail_screen.dart:4212-4225`) — a *client-side
  rendering* cost independent of payload size; a 473-participant pending
  race builds 473 full sprite widgets today regardless of what the wire
  sends. **This part needs no backend change and no capability token** — it
  can ship as a standalone frontend fix ahead of (or independent of) the
  rest of this spec. Recommended as a fast-follow if you want a visible win
  sooner; not required to be split out, but flagged as an option.
- Cap the **PARTICIPANTS list section** (`race_detail_screen.dart:4380-4396`,
  non-team PENDING races only — found during UI review, not in the
  original draft's audit) the same way: show the page, plus a trailing "+N
  more" row computed from `acceptedCount − <rows shown>`, so the section
  header pill (already showing the true total) and the row list agree
  instead of silently disagreeing.
- Pin participant ordering to `(joinedAt ASC, id ASC)` — `joinedAt` alone
  has no stable tiebreak, and seeded races bulk-enroll participants in the
  same instant, so ties are common exactly on the two worst-offender races.
  Unstable order means a paging client can duplicate or skip rows across
  pages, or see page 0 reshuffle between polls.
- Guarantee the "my own data" contract: **the viewer's own participant row
  is not guaranteed to be present in any returned page.** Every `my*` value
  the frontend needs must come from top-level response fields, never from
  scanning `participants`. Existing top-level fields already cover most of
  this: `myStatus`, `myTeam`, `myForfeitedAt`, `myChatMuted`,
  `myPlacementAlertsMuted` (`getRaceDetails.js:112-117,150-151`). This spec
  adds the two more the expanded consumer audit found missing:
  `myTotalSteps` (nullable; sourced the same way `progress` already
  provides it) for the share-taunt copy, and confirms `myTeam` already
  covers `_myLobbyTeam()`'s need (no new field there, just a consumer fix).
- Update the 3 backend call sites of `getRaceDetails`
  (`stepv2-backend/src/modules/races/routes.js:989,1018,1091`) to pass
  through pagination params.
- Verify the fix in prod logs after rollout — payload-size improvement
  should be visible immediately per capability-bearing request; latency
  improvement requires the query-plan change to have shipped (see
  Acceptance criteria — these are now two separate checks, not one).
- Unlike the existing `progress` pagination, this pagination applies
  regardless of race status or team-race flag (PENDING and team races are
  paginated too) — because the worst offenders in prod are PENDING.
  `getRaceProgress.js:1339-1343`'s own comment explains why *it* carves
  those out: "their rosters render through paths with no load-more control
  ... so a page would silently hide members with no way to reveal them."
  That reasoning doesn't block us here specifically because this spec adds
  the summary fields above — the exact "way to reveal" the true total that
  `progress` lacks — so every header count and cap-check stays accurate
  even though the array itself is truncated. This is a deliberate,
  justified deviation from the `progress` precedent, not an oversight.

**Non-goals (this spec):**
- Redis caching of the (now-paginated) details/bootstrap response. The user
  explicitly asked for this as a **second** step after pagination lands and
  is verified — tracked as a follow-up, not part of this spec's
  implementation or acceptance criteria. Note for that follow-up (flagged
  by architect review): this payload is **viewer-specific** (`myStatus`,
  `myTeam`, `leaveAction`, now `myTotalSteps`) and **capability-variant**
  (`characters`, `remote_assets`, `race_leave`, `team_races`,
  `seeded_race_buckets`, and now `race_participants_paging`) — any future
  cache key must be viewer- and capability-variant, with viewer-specific
  fields excluded from whatever's actually shared/cached.
- Changing `progress`'s existing pagination gap (PENDING/team races) — out of
  scope; not regressed by this spec either.
- An infinite-scroll / "load more participants" UI. The PARTICIPANTS list
  section gets a static "+N more" row (in scope, above), not a load-more
  control — a full paged roster browsing UI is a separate future spec if
  wanted.
- Changing `race_payout_double`, team assignment, settlement, or any other
  backend flow — confirmed (`routes.js` grep) that only the 3 route handlers
  above call `getRaceDetails`; no game-logic path depends on the full array.

## Codebase findings (Phase 1 exploration + architect/UI review)

**Existing pagination precedent** — `getRaceProgress.js:1346-1375`:
```js
if (pageableShape) {
  result.participants = result.participants.slice(start, start + safeLimit);
  result.pagination = { offset, limit, total, hasMore, nextOffset };
}
```
`limit` clamped 1-50, default 10. `pageableShape = status === 'ACTIVE' &&
!isTeamRace`. This spec's participants pagination mirrors this response
shape (`participants` + sibling `participantsPagination` object — named
distinctly from `progress`'s `pagination` key so a client reading both
objects on the bootstrap response can't confuse the two paginations) but
**without** the ACTIVE/team-race carve-out.

**Backend callers of `getRaceDetails`** — exactly 3, all in
`stepv2-backend/src/modules/races/routes.js`:
- `:989` — bootstrap handler, `access.status !== 'ACTIVE'` branch (caller not
  yet an accepted participant; race+null progress).
- `:1018` — bootstrap handler, main branch (race+progress+inventory). This
  is the branch that reuses `resolvedContext.race` as `preloadedRace` — and
  it KEEPS that reuse when paging is active. See Query plan below (revised
  Pass 3) for why: that preload is the same `Race.findById` the unpaged path
  runs, so the lean plan would only add queries there.
- `:1091` — legacy `GET /:raceId` (frozen clients / bootstrap-unsupported
  fallback).

No settlement, invite, leave, or team-assignment code path calls
`getRaceDetails` — those all use dedicated narrow-`select` queries
(`findForResolution`, `findPowerupRepairContext`, etc. in `race.js`). Safe to
change this response shape without touching game logic.

**Frontend consumers of the DETAILS array** (`_race['participants']`, not
`_progress['participants']`, which is already paginated and unaffected by
this spec) — the original draft's audit found 5 in `race_detail_screen.dart`
and missed 6 more (in that file and 3 other files); architect + UI review
found the rest:

| location | what it does | breaks under pagination? | fix |
|---|---|---|---|
| `race_detail_screen.dart:1439 _bothSidesFull()` | counts ACCEPTED per team side (team-race cap check) | **yes** — undercounts once array is a page | read `teamAAcceptedCount`/`teamBAcceptedCount` |
| `race_detail_screen.dart:4196` `acceptedCount` (pending hero header) | count of ACCEPTED for the "everyone's here" header | **yes** | read `acceptedCount` |
| `race_detail_screen.dart:4212-4225` `GoalTrackRunner` list | one full sprite widget **per** ACCEPTED participant, unconditionally (`goal_track.dart:218`, no cap) | **yes, separately** — a client-render cost independent of the wire fix | cap render to page size |
| `race_detail_screen.dart:4380-4396` PARTICIPANTS list section | one row per participant, no cap, below the hero (found during UI review — the original draft's non-goals section incorrectly claimed no full-roster render existed on this screen) | **yes** — header pill (already `acceptedCount`-based) would disagree with a silently-truncated row list | render the page + a trailing "+N more" row (`acceptedCount − shown`) |
| `race_detail_screen.dart:5215` `_isSpectator` getter | full-array `.any(p => p.userId == myUserId)` scan | **yes** — false "spectator" classification for any participant outside the returned page | use existing `myStatus` |
| `race_detail_screen.dart:6365` `_stampedLeaveAction` | another full-array membership re-check before honoring `leaveAction` | **yes**, same landmine | use `myStatus`/existing derived boolean |
| `race_detail_screen.dart:7005` `_buildCompletedContent` | fallback to `_race['participants']` only when `_progress['participants']` is absent, feeds final standings | **no new regression** — COMPLETED races are already unpaginated in `progress` (same design gap), so this fallback is already full-roster; standings board already paginates its own display to 15/page client-side | no change |
| `race_detail_screen.dart:1453-1463 _myLobbyTeam()` | array scan for my own row's team | **yes** — returns null (unassigned) when my row is off-page | read existing `myTeam` field |
| `race_detail_screen.dart:1812-1820 _inviteMore()` | builds `existingParticipantIds` from the array to filter friends already in the race | **yes** — re-offers friends already in the race once the array is a page; also has a bare `p['userId'] as String` cast today | read new `participantUserIds` (below) instead of deriving from `participants` |
| `race_detail_screen.dart:4438-4454` start-lever gate | recomputes `teamACount`/`teamBCount`/`acceptedCount < 2` | **yes**, same bug as `_bothSidesFull` | read the summary count fields |
| `race_detail_screen.dart:6307-6313` share-taunt "my steps" copy | needs my own participant row's `totalSteps` | **yes** — degrades to generic copy once my row is off-page | read new `myTotalSteps` field |
| `race_detail_screen.dart:7285-7292 _acceptedFieldSize` | "of N" payout cut line | **yes** — under-reports | read `acceptedCount` |
| `edit_race_screen.dart:111-124` (via `EditRaceScreen(race: _race)`, constructed at `race_detail_screen.dart:1779-1783`) | derives `_acceptedCount`/`_teamACount`/`_teamBCount` to gate `maxParticipants`/`teamSize` edit validation | **yes** — creator could set a cap below the true field size | pass the summary counts into `EditRaceScreen` explicitly instead of letting it re-derive from the (possibly paginated) race map |
| `widgets/race_payout_scorecard.dart:41-45` (via `RacePayoutPresentation.fromRace(_race)` at `race_detail_screen.dart:3781`) | counts ACCEPTED from the array | **yes** | route through `acceptedCount` |
| `utils/team_race.dart:253-271 TeamRace.sideCounts` | falls back to counting the array when no `teams` block is present — **is** the case for the details payload | **yes** | either provide a `teams` block on the details response too, or route this call site through the new team-count fields explicitly; verify `showTeamSidePicker` callers (`main_shell.dart:850`, `discovery_join_coordinator.dart:64`) aren't also fed a details-payload race map with this same gap |

**Contract rule this table implies**: the viewer's own row is not
guaranteed to be in any page. Every `my*`-prefixed need must be served by a
top-level field, never by scanning `participants` — see Scope, above, for
the full enumeration of existing vs. new `my*` fields.

**`backend_api_service.dart`**: `fetchRaceBootstrap` (`:2381-2405`) already
sends `view=participants-v1&offset&limit` when `participantsLimit` is
passed. `fetchRaceDetails` (`:2366-2376`, legacy `GET /races/:id`) sends no
params today; this spec adds the same optional `participantsLimit`
parameter there, additive/opt-in only.

**Demo/tutorial mirrors** (checked per CLAUDE.md's mirroring rule):
- `lib/demo/demo_race_api_service.dart:28` and
  `lib/tutorial/tutorial_preview_data.dart:317` both override
  `fetchRaceDetails` and will **fail to compile** once this spec adds the
  `participantsLimit` parameter to that method's signature, unless updated.
  Both files already solved this exact problem for `fetchRaceBootstrap`
  (`demo_race_api_service.dart:40-51`, `tutorial_preview_data.dart:333-348`)
  with an "accept the param, ignore it" override — apply the identical
  pattern to their `fetchRaceDetails` overrides.
- Both fixtures already supply `myStatus`
  (`demo_race_engine.dart:490`, `tutorial_preview_data.dart:784`) — confirm
  this continues, since `_isSpectator`/`_stampedLeaveAction` now depend on
  it exclusively.
- `demo_race_engine.dart:485-529`'s `raceDetails()` is always `ACTIVE` or
  `COMPLETED`, never `PENDING`; `tutorial_preview_data.dart:778-809`'s fixture
  is hardcoded `ACTIVE` with 5 participants (≪ any page size). **Neither
  mirror can ever reach the pending-hero or PARTICIPANTS-list-cap code
  paths** — confirmed by the fixtures' own "fixture roster is far smaller
  than any page size" comment (`tutorial_preview_data.dart:332-348`). No
  manual UI-placement check needed in either mirror beyond the compile-fix
  above.

## API contract

### ⚠️ Must be capability-gated, not just query-param-gated

The **currently-shipped** app already sends `view=participants-v1&offset&limit`
on `GET /races/:id/bootstrap` (confirmed live in prod nginx logs — 120 hits
of `bootstrap?view=...` in the sampled window, from the build in TestFlight
right now) — but only intends this to page the `progress` payload, per
`fetchRaceBootstrap`'s current implementation. That same shipped build's
`_isSpectator`, `_stampedLeaveAction`, `_myLobbyTeam`, `_inviteMore`, and the
other consumers in the table above still scan the **full**
`race.participants` array.

If this spec's pagination were gated on the query param alone, the backend
deploy would — by itself, with no app update — start slicing
`race.participants` for every client already in the field, silently
breaking any of the consumers above for any user whose row falls outside
page 1. That's exactly the class of bug CLAUDE.md's compat rule exists to
prevent: a backend change breaking an already-installed build.

**Fix**: gate the actual slicing on a new `X-Client-Features` capability
token, `race_participants_paging`, following this exact route's own existing
pattern (`req.clientFeatures?.has("characters")`,
`req.clientFeatures?.has("team_races")`, `req.clientFeatures?.has("race_leave")`
— all read at `routes.js:989,1018,1091` today). Only an app build that has
also fixed every consumer in the table above sends this token. A client
that sends `view=participants-v1` **without** the capability token gets
today's full array, unchanged — the query param alone is necessary but not
sufficient. `participantsPagination` (below) is likewise only ever present
when the capability token was sent, even if `view=participants-v1` was
also sent without it — so a client can distinguish "server paged me" from
"server ignored my paging request" without inferring it from array length.

### Query plan (required — this is what makes the latency win real)

Add a new lean method to `race.js` used **only** when the capability token
+ `view=participants-v1` are both present (the unpaginated/no-capability
path keeps calling today's `findById` unchanged — zero risk to existing
behavior and existing tests):

1. A cheap query for the race's own scalar fields + `creator`/`winner`/
   `seed`/`tournament` — **no** `participants` include at all.
2. A cheap aggregate query for participant counts: total `ACCEPTED` count,
   and (for team races) counts split by `team`. `GROUP BY status` /
   `GROUP BY status, team` with no `user`/`equippedAccessories` join — this
   is what actually replaces the "scan all 477 rows for a count" cost, not
   just hides it from the response.
3. A **single page** of participants, ordered `(joinedAt ASC, id ASC)`,
   `LIMIT`/`OFFSET` applied in the query itself (not fetched-then-sliced in
   JS) — this is the query that keeps the cosmetic `equippedAccessories →
   shopItem` join, but only for the page's rows, not all N.
4. `myParticipant` (needed for `myStatus`/`myTeam`/etc.) is looked up
   separately by `(raceId, userId)` — cheap, indexed, single row — rather
   than found by scanning the (now possibly-not-fetched-in-full)
   participants list.

**Bootstrap ACTIVE branch — REVISED after measurement (see Revision log,
Pass 3). The instruction below replaces the original "skip the preload"
rule, which rested on a wrong premise.**

On the bootstrap main branch (`routes.js:1018`), **keep** reusing
`resolvedContext.race` as `preloadedRace`, paged or not. The original spec
assumed that object was "a different shape" from what `getRaceDetails`
needs. It is not: `getRaceProgress.js:1427` calls the **same**
`Race.findById` — same fat `participantInclude` — that `getRaceDetails`'s
unpaged path calls. On this branch the expensive cosmetic hydration has
therefore *already run* by the time `getRaceDetails` is invoked, and
running the lean plan on top of it avoids nothing while adding ~11 queries.
Measured on a 12-participant ACTIVE race: **52 queries with the lean plan
vs 41 for the unpaged baseline.**

So `getRaceDetails` branches on whether it received a preload:
- **Preload present** (bootstrap ACTIVE only): reuse it. Derive the summary
  counts (`acceptedCount`, `teamAAcceptedCount`/`teamBAcceptedCount`),
  `myTotalSteps`, `participantUserIds` and the page itself from
  `preloadedRace.participants` in JS. The page slice **must** be sorted
  `(joinedAt ASC, id ASC)` first — `participantInclude` orders by `joinedAt`
  alone with no tiebreak — so the JS path honours the identical ordering
  contract as the DB path. Sort a copy; never mutate the caller's array.
- **No preload** (legacy `GET /:raceId`, bootstrap non-ACTIVE branch): run
  the lean query plan above exactly as specified. These are the call sites
  where it delivers the real latency win, since no fat read has run.

The payload-size win lands on all three routes either way.

**Ordering**: `participantInclude`'s current `orderBy: { joinedAt: "asc" }`
(`race.js:37`) has no tiebreak. Seeded Daily/Weekly races bulk-enroll many
participants in the same instant, so ties are common on exactly the two
worst-offender races. Change the paginated query's order to
`[{ joinedAt: "asc" }, { id: "asc" }]` so page walks are stable and
duplicate/skip-free. (Leave the existing unpaginated `participantInclude`
ordering as-is for the non-paginated path — no behavior change there
either; only the new paginated query needs the stable tiebreak.)

### Response ordering rule (required — prevents wrong prize numbers)

`acceptedCount` (`getRaceDetails.js:58-60`), `buildRaceMoneyView({race,
acceptedCount})` (`:64`, which derives `potCoins`/`projectedPotCoins`/
`prizePool`/`payoutTiers`), `myParticipant`-derived fields (`myStatus`,
`myTeam`, `myForfeitedAt`, etc., `:112,150,151`), and `leaveAction`
(`getRaceLeaveAction`, `:164-171`) must all be computed from the **true
counts/full lookups** (query plan above — the aggregate + the separate
`myParticipant` lookup), never from the length or contents of the returned
`participants` page. Slicing to a page is the **very last** step, applied
only to the array that gets serialized into the response. Required test:
fetch the same race with and without paging and diff every field except
`participants`/`participantsPagination` — must be identical.

### `GET /races/:raceId` and `GET /races/:raceId/bootstrap`

Response envelopes differ (confirmed in `routes.js`): the legacy route
`res.json(result)`s the `getRaceDetails()` return value directly at the top
level; bootstrap nests it as `race` inside `{contract, race, progress,
progressError, globalPowerupInventory}`. Everything below describes fields
on the `getRaceDetails()` result itself — apply at the top level for the
legacy route, under `.race` for bootstrap.

**Implementation note on `getRaceDetails`'s signature**: it already takes 9
positional parameters (`userId, raceId, supportsCharacters, releaseChannel,
supportsRemoteAssets, supportsRaceLeave, supportsTeamRaces, supportsBuckets,
preloadedRace` — `getRaceDetails.js:13-27`). Do not extend that positional
list further for the new pagination inputs — bundle them into a single
trailing options object (e.g. `{ pagination: { enabled, offset, limit } }`)
instead, both to avoid a 13-positional-arg function and so a future
capability doesn't face the same choice again.

New **optional** query params, honored only when the request also carries
the `race_participants_paging` capability token (see above):

- `view=participants-v1` — opts into paginated `race.participants`. Missing
  the capability token, or `view` omitted/any-other-value ⇒ **full array,
  unchanged from today's response**, via today's unchanged `findById` query
  plan.
- `offset` — integer ≥ 0, default `0`.
- `limit` — integer, clamped `1..50`, default `10` — identical bounds to
  `getRaceProgress.js:1352-1367`'s clamping, but that logic is inline there
  today, not an exported helper. **Extract it into a small shared helper**
  in `src/shared/` (not `src/modules/races/services/` — it has no
  races-domain dependency), e.g. `src/shared/pagination/clampOffsetLimit.js`,
  exporting something like `clampOffsetLimit({ offset, limit, total,
  defaultLimit, maxLimit })` returning `{ start, safeLimit, hasMore,
  nextOffset }`, used by both `getRaceProgress.js` and `getRaceDetails.js`.
  Refactoring `getRaceProgress.js` to call the shared helper is in scope for
  this spec's backend work; its existing tests must keep passing unmodified
  (mechanical import change only, per CLAUDE.md), **and** its non-pageable
  branch (`getRaceProgress.js:1348-1356`, which emits `pagination` with
  `limit = total` for ACTIVE-team/non-ACTIVE races) must be preserved
  verbatim — the shared helper's job is the offset/limit math, not the
  pageable-shape decision, which stays local to each query.

**Response shape change** (additive fields only; every existing field keeps
its exact current value and type, computed per the ordering rule above):

```jsonc
{
  // ...all existing getRaceDetails fields, unchanged, computed from full
  // counts/lookups regardless of paging (see Response ordering rule)...

  // participants is now the requested PAGE when the capability token AND
  // view=participants-v1 were both sent; otherwise unchanged (full array,
  // exactly as today, via the unchanged query plan).
  "participants": [ /* ...same per-participant shape as today... */ ],

  // NEW. Present ONLY when the capability token was sent (even if `view`
  // was also sent without the token) — lets a client distinguish "server
  // paged me" from "server ignored my paging request."
  "participantsPagination": {
    "offset": 0,
    "limit": 10,
    "total": 477,
    "hasMore": true,
    // Always start + limit, exactly matching getRaceProgress.js:1367's
    // convention — including past the end of the array (e.g. offset=470,
    // limit=10, total=477 => nextOffset=480, hasMore=false). Never
    // null/absent; a paging client just stops once hasMore is false.
    "nextOffset": 10
  },

  // NEW, ALWAYS present regardless of capability token or view param
  // (additive; old clients ignore unknown fields). Replaces every
  // client-side full-array scan for a count.
  "acceptedCount": 477,
  // Only non-null for team races (race.isTeamRace === true); null otherwise.
  "teamAAcceptedCount": null,
  "teamBAcceptedCount": null,

  // NEW. Nullable — same "my own row's steps" value `progress` already
  // exposes for the caller; null if unavailable rather than omitted, so a
  // defensive Dart read never has to distinguish missing-key from null.
  "myTotalSteps": null,

  // NEW. Present ONLY when the capability token AND view=participants-v1
  // were both sent (i.e. exactly when `participants` is actually
  // truncated) — old/non-paging clients already have full IDs in
  // `participants` itself and don't need this duplicated. Cheap: an array
  // of bare user-id strings, not full profiles (~17KB worst case at 477
  // participants vs. the ~66KB the full profiles cost — still a large
  // majority reduction, and only sent to the clients that actually need
  // it).
  "participantUserIds": ["user-1", "user-2", "..."]
}
```

- `acceptedCount` = count of participants with `status === 'ACCEPTED'`
  (server already computes this internally today for money calculations —
  `getRaceDetails.js:58` — this spec exposes it, doesn't add new
  computation, though per the query-plan section it's now sourced from the
  cheap aggregate rather than `race.participants.filter(...).length`).
- `teamAAcceptedCount` / `teamBAcceptedCount` = same count, split by
  `participant.team` (`"TEAM_A"` / `"TEAM_B"` — confirmed enum values,
  `teamRaces.js:7-11`; NOT `'A'`/`'B'`), only computed/populated when
  `race.isTeamRace`.
- `myStatus`/`myTeam`/`myForfeitedAt`/`myChatMuted`/`myPlacementAlertsMuted`
  (existing fields, `getRaceDetails.js:112-117,150-151`) are **unchanged**
  in derivation — sourced from the separate `myParticipant` lookup (query
  plan above), so they stay correct regardless of which page (if any) is
  requested. These are the fields the frontend fixes above switch to
  instead of scanning the array.

**Backward compatibility (CLAUDE.md rule #1):**
- Any client that doesn't send the `race_participants_paging` capability
  token — every currently-shipped build, including the one in TestFlight
  right now that already sends `view=participants-v1` for `progress` —
  gets the exact same full unpaginated `participants` array it gets today,
  via the exact same unchanged query plan, regardless of query params. This
  is the load-bearing compat guarantee; the backend test plan must
  explicitly assert it (no such test exists today since this
  query-param/route combination is new).
- A frozen app build also ignores `participantsPagination`, `acceptedCount`,
  `teamAAcceptedCount`, `teamBAcceptedCount`, `myTotalSteps`,
  `participantUserIds` — all net-new keys, standard additive-field
  compatibility, no `testOnly` gating needed (data shape, not renderable
  content per CLAUDE.md's asset-gating rule).
- The new app build (once it ships with both the capability token and every
  consumer fix in the table above) requires `acceptedCount` for several
  counts. If it's ever absent (an app build newer than the backend deploy —
  shouldn't happen given backend-first rollout, but defensively), the
  client falls back to counting the returned `participants` array length,
  which under-counts once paginated but degrades to "shows fewer than the
  true total" rather than crashing — mirrors the existing
  `progressUnavailable` defensive-read pattern already used elsewhere on
  this screen.

## Frontend plan

Screens/widgets touched: `race_detail_screen.dart` (primary),
`edit_race_screen.dart`, `widgets/race_payout_scorecard.dart`,
`utils/team_race.dart` — all four confirmed via the expanded consumer audit
above (the original draft's "no other file reads `_race['participants']`"
claim was false; corrected here).

1. **Model**: extend whatever parses the bootstrap/details response to
   surface `acceptedCount`, `teamAAcceptedCount`/`teamBAcceptedCount`,
   `myTotalSteps` (`int?`, default-safe null), `participantUserIds`
   (`List<String>?`, default-safe null/empty), and `participantsPagination`
   (nullable object: `offset`/`limit`/`total`/`hasMore`/`nextOffset`)
   alongside the existing `participants` list — additive parse,
   missing/malformed fields default to `null`/absent rather than throwing
   (existing `tryParse`-style defensive pattern used elsewhere in this
   repo, e.g. `race_payout_double_offer.dart`).
2. **`_bothSidesFull()` (`:1439`)** and **start-lever gate (`:4438-4454`)**
   — read `teamAAcceptedCount`/`teamBAcceptedCount`/`acceptedCount` when
   non-null; fall back to the current full-array scan only if null
   (defensive compat, not an expected runtime path once this ships).
3. **Pending hero (`:4196`, `:4212-4225`)** — header count reads
   `acceptedCount ?? participants.length`. `GoalTrackRunner` list built
   from `participants.take(_kParticipantsPageSize)` instead of the full
   list. Can ship standalone, no backend dependency (see Scope).
4. **PARTICIPANTS list section (`:4380-4396`)** — render the (now
   paginated) page of rows, plus a trailing "+N more" row when
   `acceptedCount` exceeds the number of rows shown; hide the trailing row
   when it would be redundant (page already shows everyone).
5. **`_isSpectator` (`:5215`)** and **`_stampedLeaveAction` (`:6365`)** —
   replace the `.any(...)` array scans with a check against `myStatus`.
6. **`_myLobbyTeam()` (`:1453-1463`)** — replace the array scan with the
   existing `myTeam` field.
7. **`_inviteMore()` (`:1812-1820`)** — build the "already in this race"
   filter set from `participantUserIds` when present, falling back to
   scanning `participants` only when it's null (unpaginated/old-response
   case). Also fix the pre-existing bare `p['userId'] as String` cast to a
   defensive read while touching this code.
8. **Share-taunt "my steps" (`:6307-6313`)** — read `myTotalSteps` when
   non-null; keep the existing generic-copy fallback when null.
9. **`_acceptedFieldSize` (`:7285-7292`)** — read `acceptedCount`.
10. **`_buildCompletedContent` (`:7005`)** — no change (already effectively
    unpaginated for COMPLETED races via the existing `progress` gap, out of
    scope here).
11. **`EditRaceScreen`** (`edit_race_screen.dart:111-124`, constructed at
    `race_detail_screen.dart:1779-1783`) — pass `acceptedCount`/
    `teamAAcceptedCount`/`teamBAcceptedCount` in explicitly from the parent
    screen's already-parsed model, rather than having `EditRaceScreen`
    re-derive them from the (possibly paginated) race map it's handed.
12. **`RacePayoutPresentation.fromRace`** (`race_payout_scorecard.dart:41-45`,
    called at `race_detail_screen.dart:3781`) — route its ACCEPTED count
    through `acceptedCount` instead of counting the array.
13. **`TeamRace.sideCounts`** (`team_race.dart:253-271`) — its
    array-counting fallback (used when no `teams` block is present, which
    is the details-payload case) needs the same fix; audit `main_shell.dart:850`
    and `discovery_join_coordinator.dart:64` (the two `showTeamSidePicker`
    callers) to confirm neither is fed a paginated details-payload race map
    through this path — if one is, apply the same summary-count fix there.
14. **Request side** — `fetchRaceBootstrap` already sends the query params;
    add the same optional `participantsLimit` param to `fetchRaceDetails`
    (legacy path). Both calls already pass a page size for `progress`;
    reuse `_kParticipantsPageSize` for participants too. **Also add
    `race_participants_paging` to the `X-Client-Features` header** built in
    `backend_api_service.dart:241-243`, as a plain unconditional token (like
    `characters`/`team_races`) in **both** the `_adsSupported` and non-`ads`
    branches — `:238-240`'s comment explicitly requires additive tokens in
    both.
15. **Demo/tutorial fixture compile fix** — add "accept `participantsLimit`,
    ignore it" overrides to `fetchRaceDetails` in
    `demo_race_api_service.dart` and `tutorial_preview_data.dart`, mirroring
    their existing `fetchRaceBootstrap` overrides. Confirm both fixtures
    continue to supply `myStatus` (they already do). No visible-state
    checklist item needed for either mirror — neither can reach the
    pending-hero or PARTICIPANTS-cap code paths (confirmed: both are
    hardcoded ACTIVE/COMPLETED with small fixture rosters).

**States**: no new loading/empty/error state — this is a payload-shape
change to an existing successful response, not a new UI state. The existing
`AppRefreshIndicator`/`LoadErrorPanel` failed-load state (fixed earlier this
session) is unaffected.

**iOS + Android**: pure Dart change in a shared screen/model — both
platforms get the fix from one code change, per CLAUDE.md's lockstep rule.

## Backward-compat & rollout

Because the actual slicing is gated on the `race_participants_paging`
capability token (not the query params, which the field already sends
today), **rollout order is safe either way** — this is the point of the
capability gate:

1. **Backend first (standard order, still recommended).** Deploy the
   `getRaceDetails`/route/query-plan changes to prod. Nothing changes yet
   for any client in the field — no build sends the new capability token,
   so every response (including the already-in-flight
   `bootstrap?view=...` requests from the current TestFlight build) stays
   on the unchanged code path/query plan it hits today. Confirm via the
   same nginx-log method used for root-cause analysis that tail
   latency/payload size on `Weekly Challenge`/`Daily Challenge`-sized races
   is **unchanged** post-deploy (proves the gate is actually inert for
   today's traffic, not just untested).
   - **Log-visibility caveat** (architect-flagged): standard nginx
     `log_format` does not include `X-Client-Features`, so post-rollout you
     can't segment "capability-bearing" traffic from the access log alone.
     Either add the header (or at minimum `X-App-Version`) to
     `log_format` before the frontend ships, or plan to segment by request
     timing (before/after the app-version cutoff you know shipped the
     capability) instead of by request content.
2. **Then frontend.** Ship the app update that declares the capability
   token, adds `participantsLimit` to the legacy `fetchRaceDetails` call,
   and migrates every consumer in the table above off full-array
   dependence. Only once this build is live (and, per CLAUDE.md,
   phased-rolled-out over ~a week, with some users never updating) does the
   improvement land for those users.
   - The **pending-hero render cap** (Scope, above) has no backend
     dependency and can ship in an earlier frontend release than the rest
     of this list, if you want a visible client-side win sooner without
     waiting on the backend query-plan work.
3. No `testOnly` gating needed beyond the capability token itself.
4. No economy/game-balance feature flag needed (no odds, pricing, or payout
   surface touched) — the capability token is this feature's gate.

## Test plan (tests-first, both agents)

**Backend (`test:integration`, real Postgres, real HTTP, per CLAUDE.md)**:
- `GET /races/:id` and `GET /races/:id/bootstrap`, **without** the
  `race_participants_paging` capability token, on a race with >10
  participants, **with** `view=participants-v1&offset=0&limit=5` in the
  query string (simulating the current TestFlight build's existing
  bootstrap request) → `participants.length` equals the full participant
  count and every existing field on each participant object matches the
  pre-this-spec shape exactly (assert full field set, not a literal byte
  diff — IDs/timestamps vary per test run). Load-bearing: this is the exact
  request shape already happening in prod today and must not regress the
  instant the backend deploys.
- Same request, **with** the capability token this time, on a race with 12
  participants → `participants.length === 5`, `participantsPagination` =
  `{offset:0, limit:5, total:12, hasMore:true, nextOffset:5}`.
- `offset=10&limit=5` + capability token, same 12-participant race →
  `participants.length === 2`, `hasMore:false`, `nextOffset: 15` (always
  `offset + limit`, matches `getRaceProgress.js:1367`'s convention exactly).
- **Response-ordering rule**: fetch the same race with and without the
  capability token/paging — every field except `participants`/
  `participantsPagination` (in particular `potCoins`, `projectedPotCoins`,
  `prizePool`, `payoutTiers`, `leaveAction`, every `my*` field) must be
  byte-identical between the two responses.
- **Stable ordering**: a race with several participants sharing the same
  `joinedAt` timestamp (simulate a bulk-enroll) → walking pages via
  `offset`/`limit` in sequence yields no duplicate and no skipped
  participant IDs; re-fetching page 0 twice in a row yields the same order
  both times.
- **PENDING race** with >10 participants, capability token +
  `view=participants-v1` → **is** sliced (explicit test proving PENDING is
  not carved out, since that carve-out is exactly what let the two worst
  prod offenders slip through today).
- **Team race** with >10 participants, same → **is** sliced.
- **Query-plan assertion**: for a paginated request, assert (via query
  count/mock, however this codebase's existing tests observe Prisma call
  counts — check `race.js`/existing tests for the pattern) that the
  cosmetic `equippedAccessories` join is NOT executed for the full
  participant set, only for the page — this is the test that actually
  proves the latency fix, not just the payload-size fix.
- `acceptedCount`, `teamAAcceptedCount`, `teamBAcceptedCount`,
  `myTotalSteps`, `participantUserIds` (presence rules: always for the
  first three; only with capability+view for the last) correct on both
  routes, for: a non-team race, a team race, a race where the caller is not
  yet an accepted participant (`access.status !== 'ACTIVE'` branch,
  `routes.js:989`).
- `myStatus`/`myTeam`/etc. unchanged (still derived via the separate
  `myParticipant` lookup) when the caller's own participant row falls
  outside the requested page.
- `limit` clamping (`0`, negative, `51`, non-numeric) — unit tests against
  the new shared `clampOffsetLimit` helper directly (pure math, many cases
  — the CLAUDE.md carve-out for unit tests over integration), plus one
  integration assertion per route proving it's actually wired in.
- `getRaceProgress.js`'s existing test suite passes unmodified after its
  refactor to call the shared helper (mechanical only); its non-pageable
  branch (`limit = total` for ACTIVE-team/non-ACTIVE races) is unchanged.

**Frontend (integration/widget, pump the real screen, per CLAUDE.md)**:
- A race with a paginated `participants` response (page smaller than
  `acceptedCount`) still shows the correct total in the pending-hero header
  count, while rendering only the paginated number of `GoalTrackRunner`
  sprites (assert widget count, not just text).
- Same fixture: PARTICIPANTS list section shows the page plus a "+N more"
  row matching `acceptedCount − shown`.
- `_isSpectator`/leave-action/`_myLobbyTeam` correctness for a participant
  whose own row is **outside** the returned page — construct a fixture
  where `myStatus`/`myTeam` say ACCEPTED/assigned but the participant is
  absent from the (paginated) `participants` array; assert the screen does
  NOT show the "not a participant"/spectator state and the lobby shows the
  correct team.
- `_inviteMore()` does not re-offer a friend already in the race when that
  friend's row is off-page but present in `participantUserIds`.
- Team-race "both sides full" and start-lever gate read the new summary
  counts, verified against a fixture where the full roster isn't in the
  paginated array.
- `EditRaceScreen` validation uses the passed-in counts, not a re-derived
  scan, verified against an off-page-heavy fixture.
- Demo race tutorial and tab tutorial preview still compile and render
  after the `fetchRaceDetails` signature change (smoke test — no new
  behavior expected, per the mirror audit above).
- Existing `race_detail_screen_test.dart` / `race_detail_not_a_participant_test.dart`
  suites still pass unmodified (mechanical updates only, per CLAUDE.md — no
  weakened assertions).

## Acceptance criteria / definition of done

- [ ] `getRaceDetails.js` uses the new lean query plan (separate race
      fetch, aggregate counts, single paged participant query with the
      cosmetic join scoped to the page only) whenever the capability token
      + `view=participants-v1` are both present. Non-paginated path
      unchanged (`findById`, exactly as today).
- [ ] Participant ordering pinned to `(joinedAt ASC, id ASC)` for the
      paginated query.
- [ ] `acceptedCount`, `teamAAcceptedCount`, `teamBAcceptedCount`,
      `myTotalSteps` always present on both routes, computed from full
      counts/lookups regardless of paging (response-ordering rule test
      passes). `participantUserIds` present exactly when capability+view
      are both sent.
- [ ] All 3 backend call sites updated: the two with no preload (legacy
      `GET /:raceId`, bootstrap non-ACTIVE) run the lean paged plan; the
      bootstrap ACTIVE branch keeps its `preloadedRace` reuse and slices in
      JS with an explicit `(joinedAt ASC, id ASC)` sort. All new + existing
      backend integration tests pass, including the capability-less-request
      regression test, the query-plan assertion proving the cosmetic join is
      scoped to the page on the no-preload routes, and the assertion that a
      paged bootstrap ACTIVE read runs no MORE queries than an unpaged one.
- [ ] Shared `clampOffsetLimit` helper extracted to `src/shared/`, used by
      both `getRaceDetails` and `getRaceProgress`; `getRaceProgress`'s
      existing tests (including its non-pageable-branch behavior) pass
      unmodified.
- [ ] Every consumer in the Frontend plan's numbered list migrated off
      full-array dependence; pending-hero render capped; PARTICIPANTS list
      capped with a "+N more" row; capability token added to
      `X-Client-Features` (both branches); demo/tutorial fixtures updated
      to compile; all new + existing frontend tests pass; `flutter analyze`
      clean.
- [ ] Backend deployed to prod first; nginx-log spot-check confirms **no
      change** in payload size/latency immediately post-deploy (proves the
      gate is inert for today's traffic).
- [ ] After the frontend build ships and has had time to roll out: re-run
      the same nginx-log method and confirm measurable improvement in
      **both** payload size (immediate, from serialization) and tail
      latency (requires the query-plan change) on `Weekly
      Challenge`/`Daily Challenge`-sized races for capability-bearing
      requests specifically — segmented per the log-visibility caveat
      above.
- [ ] `code-reviewer` agent run on the combined diff; no unresolved
      blockers.
- [ ] Redis caching (explicitly out of scope above) revisited as a
      follow-up only after the above is verified in prod, with the
      viewer-specific/capability-variant cache-key note carried forward.

## Revision log

**Pass 1** (self-review) — found and fixed a serious compat bug in the
initial draft: the currently-shipped TestFlight build already sends
`view=participants-v1` on bootstrap (for `progress`), but its
`_isSpectator`/`_stampedLeaveAction` logic still full-array-scans for
membership. Gating the new `race.participants` slicing on the query param
alone would have broken those already-installed clients the instant the
backend deployed, with no app update. Fixed by adding a
`race_participants_paging` capability-token gate. Also fixed: imprecise
route-envelope description, `nextOffset` semantics pinned to
`getRaceProgress.js`'s actual convention, overreaching "byte-identical"
test language softened, unverified pre-existing-test claim removed, the
"why is it safe to not carve out PENDING/team races here" reasoning made
explicit, exact `TEAM_A`/`TEAM_B` enum values pinned, rollout section
rewritten around the capability gate, both `X-Client-Features` header
branches called out.

**Pass 2** (self-review) — found the spec implied a reusable "clamp helper"
that doesn't actually exist yet; changed to explicitly direct extracting a
shared helper. Flagged that `getRaceDetails`'s 9-positional-param signature
shouldn't grow further; bundle new inputs into an options object.

**Phase 4 — architect review (REVISE, 6 REQUIRED changes, all folded in)**:
1. **Core finding**: the original design didn't actually fix latency —
   slicing the serializer output happens after the expensive fat-join query
   already ran (`race.js:95-101`'s own comment confirms the cosmetic join
   is "the dominant cost"). Added the full "Query plan" section (lean
   race fetch + cheap aggregate counts + single paged/joined participant
   query), and split the latency win from the payload-size win throughout
   (Acceptance criteria, rollout verification) since only the query-plan
   change delivers the former.
2. Added the explicit "Response ordering rule" — money/prize/`my*` fields
   must derive from full counts/lookups, never from the returned page;
   added the required byte-diff-except-participants test.
3. Pinned participant ordering to `(joinedAt ASC, id ASC)` — `joinedAt`
   alone has no tiebreak and seeded races bulk-enroll, so ties are common
   exactly on the worst-offender races; unpinned order risks duplicate/
   skipped rows across a page walk.
4. Consumer audit expanded from 5 to 11 within `race_detail_screen.dart`
   (added `_myLobbyTeam`, `_inviteMore`, the start-lever gate, share-taunt
   "my steps", `_acceptedFieldSize`) plus the explicit "viewer's own row
   not guaranteed in any page" contract rule and the `myTotalSteps` /
   `participantUserIds` fields it requires.
5. Corrected the false "no other file reads `_race['participants']`"
   claim — added `EditRaceScreen`, `RacePayoutPresentation.fromRace`
   (`race_payout_scorecard.dart`), and `TeamRace.sideCounts`
   (`team_race.dart`) as required fixes, plus a `showTeamSidePicker`
   caller audit.
6. Added the demo/tutorial fixture compile-fix requirement
   (`fetchRaceDetails` signature change breaks two existing overrides) and
   confirmed via the mirror audit that neither fixture can reach the
   visually-changed code paths.

Suggestions also folded in: pending-hero cap called out as independently
shippable (no backend dependency); shared clamp helper relocated to
`src/shared/` with the non-pageable-branch preservation note; explicit
"`participantsPagination` present only with the capability token" rule;
Redis follow-up note on viewer-specific/capability-variant cache keys;
cross-link to the existing `progress`-pagination spec added at the top of
this document; nginx log-visibility caveat added to the rollout section.

**Phase 4 — UI-test-planner findings (folded in)**: found a second
previously-missed full-roster consumer, the PARTICIPANTS list section
(`race_detail_screen.dart:4380-4396`), which directly contradicted the
original non-goals section's claim that nothing on this screen renders a
scrollable full roster. Decided treatment: cap + "+N more" trailing row,
matching the hero's treatment, rather than leaving it silently truncated
with no affordance. Confirmed via code that the demo race tutorial and tab
tutorial preview can never reach either changed visual path (hardcoded
ACTIVE/COMPLETED status, fixture rosters far below any page size) — no
manual checklist items needed for those mirrors beyond the compile-fix.
Manual UI-placement checklist (6 items, covering: large-roster PENDING hero
cap, header count accuracy, the new PARTICIPANTS "+N more" row, small-race
no-regression check, team-race no-visible-change check, and
spectator/leave-action no-visible-change check) is reproduced below for
sign-off.

**Pass 3 (post-implementation, RESOLVED)** — the backend agent's report
flagged the "skip the `preloadedRace` reuse when paging is active" rule as
an open question, and measurement proved the rule wrong. Its premise was
that `resolvedContext.race` is "a different shape" produced by
`getRaceProgress`; in fact `getRaceProgress.js:1427` calls the very same
`Race.findById` (same fat `participantInclude`) that `getRaceDetails`'s
unpaged path calls. Skipping the reuse therefore avoided nothing — the fat
read had already run on that request — and merely stacked the lean plan's
~11 extra queries on top. A characterisation test in the diff pinned the
regression at **52 queries paged vs 41 unpaged** on a 12-participant ACTIVE
race.

Resolved by branching on the presence of a preload rather than on paging:
the bootstrap ACTIVE branch now reuses `preloadedRace` and derives the
counts, `myTotalSteps`, `participantUserIds` and the page from it in JS,
with an explicit `(joinedAt ASC, id ASC)` sort on a copy of the array
before the offset/limit slice (matching the DB plan's ordering guarantee —
`participantInclude` has no `id` tiebreak). The other two call sites
(legacy `GET /:raceId`, bootstrap non-ACTIVE) have no preload and keep the
lean DB-level query plan unchanged, which is where the latency win is real
(confirmed: those routes hydrate cosmetics for 3 of 12 participants).
Bootstrap ACTIVE is now 41 queries paged — parity with the unpaged
baseline, not fewer, since `getRaceProgress` still needs the fat read.
The Query plan section and the acceptance criteria were rewritten to match;
the "KNOWN GAP" characterisation test was replaced by one asserting paged
≤ unpaged query count on that route, plus a new bootstrap-ACTIVE tied-
`joinedAt` page-walk test covering the JS sort.

## Manual UI-placement test plan (from ui-test-planner, verbatim)

*Elements under test:*
- Pending-race "start line" hero (`GoalTrackRunner` sprites,
  `race_detail_screen.dart:4212-4225`, rendered via `lib/widgets/goal_track.dart`)
  — full-array render capped to `_kParticipantsPageSize` (15,
  `race_detail_screen.dart:375`).
- Pending-hero header "X racers ready" count (line ~4384's
  `Pill(label: '$acceptedCount')`) — switches from array-length to the new
  `acceptedCount` field.
- The non-team PENDING "PARTICIPANTS" section
  (`race_detail_screen.dart:4380-4396`, `for (final p in participants)
  _buildParticipantRow(p)`) — a *second*, separate full-roster render below
  the hero, not originally in the spec's consumer table. It will silently
  show only the paginated page (≤15 rows) once the app sends the
  capability token, with no "load more"/"and N more" affordance unless
  added (this spec adds one — verify it).
- Team-race "both sides full" gate (`_bothSidesFull()`, :1439) and
  spectator/leave-action checks (`_isSpectator` :5215,
  `_stampedLeaveAction` :6365) — logic-only per spec; confirmed no display
  change, included only as a negative/regression check.

*Checklist*

1. **Real race detail — PENDING race, roster larger than one page**
   - Get there: needs the *new* app build (capability token) talking to a
     backend that has already deployed the pagination change. Open the
     Races tab (or Home discover rail) shortly before a seeded reset and
     tap into **Weekly Challenge** or **Daily Challenge** while still
     `PENDING` — these are the prod races the spec's own data shows
     regularly sit at 184–473 pending participants, so no manual
     fixture-faking should be needed. If no seeded race is currently
     PENDING, any public race joinable with >15 accepted participants
     works.
   - Verify: hero course shows a capped, evenly-laid-out set of runner
     sprites (not one per participant) — count them, should be ≤15, not
     473. No crash, no visible "half-built" or overflowing track. Track
     legend under the hero (from `GoalTrack._buildLegend`, which iterates
     the *same* runner list) also shows only the capped set.
   - Verify (negative): the hero does **not** show a partial/truncated
     "..." sprite, dangling label, or obviously-cut-off row — reads as a
     clean capped scene, not a broken one.

2. **Pending-hero header count**
   - Get there: same PENDING large-roster race as #1.
   - Verify: the header text/pill near "AT THE START LINE" reads the true
     total (e.g. "473"), not the count of sprites rendered (15). Compare
     against the number of runner sprites on the course — count should
     legitimately differ; that's expected, not a bug.

3. **PARTICIPANTS list section (below the hero, non-team pending race
   only)**
   - Get there: same PENDING large-roster non-team race, scroll down past
     the hero/race-details card to the "PARTICIPANTS" section header.
   - Verify: the Pill next to "PARTICIPANTS" shows the true total (matches
     step 2's number). The row list directly below shows the paginated page
     (≤15 rows) **plus this spec's new "+N more" trailing row** — confirm
     that row's count matches `acceptedCount − shown` exactly, and that it
     does not appear at all for a race small enough that the page shows
     everyone.

4. **Small/normal race — no regression**
   - Get there: any PENDING race with ≤15 accepted participants (the
     common case).
   - Verify: hero shows one sprite per participant exactly as today, header
     count matches sprite count, PARTICIPANTS list shows every participant
     with no "+N more" row — identical to pre-change behavior. This is the
     negative check proving the cap only engages when it needs to.

5. **Team race — no visible change (regression check only)**
   - Get there: a PENDING team race, ideally one near/at the team cap.
   - Verify: "TEAM LOBBY" board (`TeamLobbyBoard`) looks unchanged — same
     slot layout, same "Both teams are full" banner behavior when both
     sides are full via `_bothSidesFull()`. No new gaps/misfires now that
     this reads `teamAAcceptedCount`/`teamBAcceptedCount` instead of
     scanning the array. (Team races aren't the large-roster case in prod
     today, so this is a sanity check, not a stress test.)

6. **Spectator / leave-action state — no visible change (regression check
   only)**
   - Get there: hardest to reach on-device without fixture control — best
     effort: join a large PENDING race (>1 page), then reopen the race
     detail screen after the join has propagated.
   - Verify: your own participant chrome (accept/decline, leave option,
     "you're in" state) is correct even though your own row may not be on
     page 1 of the (now paginated) array — this exercises the
     `myStatus`/`myTeam`-based fixes instead of the old array scans.

*Note on testability*: items 1-3 require the new app build actually sending
`race_participants_paging` in `X-Client-Features` (both header branches, per
the "must be in BOTH branches" requirement) talking to a backend that has
the capability check wired end-to-end — confirm this before concluding a
"no cap visible" result is a bug rather than a build/config issue.
