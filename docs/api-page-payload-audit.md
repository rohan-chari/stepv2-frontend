# API calls and payload audit

Date: 2026-08-13

## Scope and method

This is a source-level, read-only audit of the production Flutter screens, the
shared services they delegate network work to, and the matching Node/Express
handlers, queries, and serializers. It covers:

- which requests each screen starts on entry, refresh, polling, and mutation;
- the important fields or collections returned by the backend;
- what the current Flutter build actually consumes;
- duplicate requests, avoidable sequencing, payload overfetch, and expensive
  backend work hidden behind a small response;
- a compatibility-safe way to make each hot path lighter.

The original pass was not a production latency benchmark. A later disposable-
DB tournament probe and the in-progress 2026-08-13 production monitor are
called out explicitly below; neither is silently generalized beyond the metric
it measured. Before any optimization is declared successful, staging or
production-safe telemetry must measure request count, SQL count, response
bytes, and p50/p95 latency.

Existing endpoints must remain compatible with frozen app versions. The safe
pattern is an additive endpoint, an optional `view=compact`/capability opt-in,
or an additive bootstrap payload. Do not remove or repurpose fields from an
existing response just because the current build does not read them.

## Executive result

The APIs are not uniformly overweight. Race lists, race discovery summary,
Home's race-card batch, user search, notification settings, and referral
details are generally shaped around what their screens render.

The main opportunities are concentrated in a few hot paths:

| Priority | Surface | Finding | Compatibility-safe direction |
| --- | --- | --- | --- |
| P0 | Active race detail | About 32 GETs/minute can run while the screen is open. Hidden Chat and visible Activity account for about 28; every message read performs a deep `Race.findById` participant/cosmetic load even when message rows hit Redis. | Add a lean race-access projection; load Activity plus a separately cached body-free Chat watermark on entry; lazy-load USER messages only after the first Chat tap; combine streams thereafter; remove progress-triggered duplicates while keeping five-second freshness. The first tap may briefly show the existing loading UI. |
| P0 | Race details/progress | Opening starts details and progress together, but both independently hydrate the full race and every participant's cosmetic relations. Progress repeats that hydration every 30 seconds. | Keep the old endpoints; add a new bootstrap or lean progress capability whose participant presentation is bulk/cached and whose static detail data is not repeated. |
| P0 | Live race resolution | The four-hour production monitor saw 8,056 full resolution passes across 52 races while only two races completed. A pure 15-second progress-snapshot rebuild intentionally enqueues a second full worker pass; step syncs mark every active race dirty; two 353/346-member seeded races consumed 62% of logged worker elapsed time. | Preserve the display generation/side effects but reuse its validated first-pass artifact so the worker does not score twice; classify/expand dirty scope with full-safe fallback; coalesce sync bursts without starvation; lock then bulk-write changed participants; move ordered/idempotent post-commit work to bounded durable phases. |
| P0 | Tournament detail | One request blocks first paint, but its deep graph loads tournament-participant cosmetics and then every matchup participant's user/cosmetics again. The serializer never reads matchup users, and the current bracket renders only names/photos from the top-level participant directory. | Add an opt-in lean complete snapshot; keep the legacy endpoint for frozen clients; consume mutation-returned tournament/wallet state rather than immediately re-fetching. |
| P0 | Home/friend data | `/friends/steps` loads friend cosmetics and daily steps, then may ask every friend to sync. The current app uses none of the returned steps or cosmetics; it needs identity, photo, and team-race eligibility. | Add a compact invite/friend-summary view with no step reads and no step-sync fanout. Use it as shell-owned friend state. |
| P1 | Home/shop | Home downloads the full shop catalog just to get the user's coins/equipped character and cape metadata. Opening Shop downloads that catalog again and then starts two more powerup calls. | Add a lean own-presentation/wallet payload; seed Shop from the shell cache; fetch any missing catalogs in parallel. |
| P1 | Get Coins | The screen calls full daily-reward status, which builds box odds plus accessory/powerup prize pools, but reads only `claimedToday` and `adCoinReward`. It calls full referral status but reads only the two configured reward amounts. | Add a small Get-Coins status payload, or compact views on the two existing endpoints. |
| P1 | Public races | The page starts four reads. One is the entire personal `/races` payload solely to extract the `tournaments` summary bucket. | Add one public-discovery bootstrap, or include the user's relevant tournament summaries/IDs in an existing compact discovery response. |
| P1 | Shop mutations | A cosmetic purchase returns the new coin balance, then the client reloads the cosmetics catalog and, sequentially afterward, both powerup endpoints. | Return authoritative changed ownership/equipment/inventory data, or invalidate and refresh only the affected catalog. Parallelize independent reads. |
| P2 | Ranked V2 | The backend joins and serializes every cohort member's equipped cosmetics. The V2 UI renders photo/name/rank/steps/zone only. | Add a V2 compact capability and omit cosmetic joins there. Leave legacy `/ranked` unchanged because its ladder does render capybaras. |
| P2 | Auth/bootstrap | Cold start fetches a full user in `/auth/session`, then fetches a second full user via `/auth/me`. Own-user envelopes also expose many stored scalars the current app never reads. | Make the new session/bootstrap response sufficient for the current shell, or add a compact explicit own-user serializer. Preserve the legacy envelopes. |
| P2 | Friends tab | Revealing Friends starts shell `/friends/steps` and the tab's `/friends`. `/friends` also joins cosmetics that this page does not render. Mutations reload both families. | Share one compact friends/pending payload between shell and tab; invalidate it once per mutation. |
| P2 | Profile stats | The response is small, but the server reads all historical daily rows and aggregates in JavaScript. It also performs a ranked lookup for fields the current Profile does not use. | Use SQL aggregates/date predicates and a compact current-profile view that skips legacy ranked fields. |
| P3 | Global static reads | Version policy and powerup copy are fetched on launch and every foreground. Their server work is small/cached, but the network requests are unconditional. | Add ETag/If-None-Match or a short client TTL while preserving resume-time force-update behavior. |

## Active race request budget

An active `RaceDetailScreen` currently has the following approximate steady
state while foregrounded:

| Request | Cadence | Approx. per minute | Notes |
| --- | --- | ---: | --- |
| `GET /races/:id/progress` | every 30s | 2 | Starts with full `Race.findById`; returns live standings, cosmetics, teams, effects, box/inventory state, and odds. |
| `GET /powerups/inventory` | after every successful progress read | 2 | Global inventory usually does not change unless the user buys/redeems; no screen-local TTL/in-flight guard. |
| `GET /races/:id/messages?kind=USER` | every 5s | 12 | Default page of 50; message rows may be cached, but race access is still deep-hydrated. |
| `GET /races/:id/messages?kind=SYSTEM` | every 5s | 12 | Same access load; may additionally read active effects for stealth redaction. |
| USER + SYSTEM refresh from progress | every 30s | 4 | Duplicates the independent 5s pollers around the same boundary. |
| **Total** |  | **about 32 GETs/min** | Excludes user actions such as opening boxes, casting, chat sends, or pulls. |

Screen entry also starts details, progress, hidden USER messages, visible
SYSTEM events, and global inventory, so one open is approximately five GETs
before any action.
Details and progress are parallel, which helps wall-clock time, but both load
the same deep participant/cosmetic graph independently.

The safest first optimization does not change visible freshness:

1. authorize message reads with `raceId/status/tournamentId` and participant
   membership scalars, not `Race.findById`;
2. initialize Activity only, track new hidden Chat activity through a cheap
   separately cached, body-free latest-message watermark, and fetch USER bodies
   only after the first Chat tap; use one combined endpoint thereafter;
3. stop calling both message refreshes from the 30-second progress callback;
4. load global inventory once, then update it from purchase/redeem responses;
5. give progress a projection containing only scoring fields plus the
   presentation fields the leaderboard renders.

## Page-by-page inventory

### App launch and authenticated shell

| Surface | Calls | Backend response | Current frontend use | Audit |
| --- | --- | --- | --- | --- |
| Global version gate | `GET /app-version/policy` on launch/resume | supported/latest versions, derived update flags, platform URLs | Recomputes gate from versions; uses URL for update action | Small and DB-free. Candidate for HTTP validation/TTL, but force-update freshness constrains the TTL. |
| Global powerup copy | `GET /powerups/catalog` on launch/resume | version plus all displayable powerup names/descriptions/tier labels | Replaces persisted/bundled copy | Small (~28 rows) and Redis-cacheable. Use ETag to avoid retransmitting unchanged copy. |
| Session restore | `GET /auth/session` | new session token plus a broad own-user envelope and held coins | Applies token and complete auth state | Immediately followed by `/auth/me` during Home load. Consolidate for current clients. |
| Home cold start | `POST /steps/sync-v2` (legacy fallback only under defined support/failure rules), `GET /home/suggested-races`, `/home/race-card`, `/races`, `/shop/catalog`, `/friends/steps`, `/auth/me`; conditional `/ranked/v2` and resolution-job polling | Step acknowledgement; suggestion cards; batched Home state; personal race summaries; full shop; friend step rows; full own user | All major Home/race state is used, but Shop and Friends payloads are much wider than their Home use | Requests are parallel/coalesced where safe. Biggest wins are replacing shop/friends payloads and eliminating the second own-user envelope. |
| Home pull-to-refresh | step sync, then race-card + suggestions; background me, friends/steps, cached shop, optional resolution polling | Same families as cold start | Refreshes all Home state | Correct sequencing around authoritative sync. Compact friend/me payloads would make the background tail cheaper. |

`/home/race-card` is a good batching example: its top-level `state/data`,
`nextRace`, `globalEvent`, `stepMilestones`, and lean `dailyReward` blocks are
all consumed. The embedded daily-reward block avoids constructing the full
daily box pool on normal Home loads.

### Home tab

The tab itself consumes shell state. It does not start another full page load.
It uses:

- race-card state and active-race cards;
- `nextRace`, `globalEvent`, `stepMilestones`, and `dailyReward`;
- friend list only for empty/count/setup and downstream invite flows;
- equipped character/accessories and coins from the shop catalog.

It does not use friend daily steps, friend step goals, or friend cosmetics.
The full shop catalog is used only for `coins`, `equipped`, and a scan for the
cape's render metadata.

### Races tab

| Calls | Backend response | Current frontend use | Audit |
| --- | --- | --- | --- |
| `GET /races` | Personal race summaries, result summaries, tournament summaries | Cards, pending decisions, results, tournament entries | Already uses `findSummariesForUser` with lean participants and bulk presentation/effect/inventory reads. Keep. |
| `GET /races/discovery-summary` in background | Compact counts/featured discovery state | Public/featured affordances | Already replaces several independent background calls. Keep. |
| stale friend refresh | Current `/friends/steps` payload | Invite/create flows | Replace with compact friend summary as above. |

### Public races screen

| Calls | Backend response | Current frontend use | Audit |
| --- | --- | --- | --- |
| `GET /races/public` | Public race card summaries | Public race list | Payload is reasonably aligned. |
| `GET /tournaments/public` | Featured and public tournament summaries | Public/featured brackets | Payload is reasonably aligned. |
| `GET /races/featured` | Featured race summaries | Featured section | Payload is aligned, but could join the page bootstrap. |
| `GET /races` | All of the user's race/list/result data plus `tournaments` | Only the `tournaments` bucket | Clear request-level overfetch. Return the needed owned/joined tournament summaries in a compact discovery payload. |

### Race detail

| Calls | Backend response | Current frontend use | Audit |
| --- | --- | --- | --- |
| `GET /races/:id` | Full race metadata, creator/winner, all participants and character presentation, money/team/tournament context, mute state | Static header/rules/lifecycle, participant identity, actions | Most categories are used, but it duplicates the deep participant load done by progress on open. |
| `GET /races/:id/progress` | Live participants with presentation/totals/multipliers, teams, effects, box progress/inventory/config/odds, event/tournament context | Leaderboard, powerups, teams, odds, effects, event | Rich data is justified, but its initial `Race.findById` and repeated presentation hydration are too broad for a 30s poll. |
| USER and SYSTEM message reads | Up to 50 records plus cursor; sender/event metadata | Activity is default-visible; Chat is hidden until tapped | USER fields are aligned once Chat is used, but loading/polling them before that is unnecessary. Both kinds also use an excessively deep authorization lookup. |
| `GET /powerups/inventory` | Global `{powerupType, quantity}` rows | Builds redeemable global stash | Payload is lean; cadence is not. Load once and patch/invalidate on mutations. |
| Starter reward, Sneaky targets, box open/reroll/batch, cast/discard/redeem, invite/team/lifecycle/share/mute actions | Action-specific results | Used by the initiating UI, followed by progress/details refresh as needed | Prior powerup optimization work made core casts/rolls leaner. Audit each follow-up refresh so one action does not cause progress + inventory + two message reads unnecessarily. |

### Create, edit, invite, and race-result screens

| Screen | Calls and response | Current use | Audit |
| --- | --- | --- | --- |
| Create race/tournament | Optional team-name suggestion; create returns created race/tournament; optional invite; then `/auth/me` | Navigation needs ID/object; `/auth/me` is read only for coins/held coins | Funded races/brackets are free now. Skip wallet refresh for funded creation, or include an authoritative wallet delta when money can change. |
| Edit race | Update returns updated race | Returned race drives navigation/state | Aligned. |
| Friend picker | None; uses passed friend rows | ID/name, and some callers need eligibility/photo | Passing compact friend summaries is sufficient. |
| Race invite screen | None directly; parent owns accept/decline/invite calls | Passed race/friend state | No page-local overfetch. |
| Case opening / multi-case opening | No transport directly; parent supplies roll/reroll callbacks and result data | Animation consumes roll result | No independent API issue. Keep server payload action-specific. |
| Race results summary | Conditional payout-double offer and claim; `/auth/me` only if claim response omitted `coins` | Offer/result and balance | Current backend claim normally returns coins, so fallback is appropriate and not a normal duplicate. |
| Ranked results summary | No direct read; consumes ranked result already loaded by shell/tab | Result presentation | No page-local API issue. |

### Tournament detail

| Calls | Backend response | Current frontend use | Audit |
| --- | --- | --- | --- |
| `GET /tournaments/:id` on entry and every 60s while live | Summary/money/status fields, tournament participants with cosmetics, every matchup race and its participants with the same user/cosmetic graph, active effects | Header, actions, roster, bracket, current matchup, countdown; current widgets use participant names/photos but no tournament cosmetic fields | Serious graph overfetch. Matchup user objects are never read by the serializer; creator/champion relations are also loaded but not serialized. Use one top-level identity/photo directory plus scalar matchup refs/effects. Keep complete 60-second snapshots; a delta protocol is unnecessary initially. |
| start/leave/cancel/join/respond/forfeit/invite/share | Usually returns a full tournament or action result | UI then often calls `_load`; money-related actions also call `/auth/me` | Consume a valid returned tournament directly and add an optional direct-Postgres post-commit wallet. A projection/wallet read failure after commit must still report mutation success and trigger only the affected fallback. Commands should use lean access and post-commit detail projections instead of repeated deep `findById`. |

A disposable local 16-player, eight-first-round-race probe with equipped items
measured the current public GET at 15 SQL statements and 18.8 KB. The lean
relation graph used 9 statements and materialized about 12.2 KB before compact
serialization. Its aggregate query-event duration was 8.5 ms versus 39.4 ms
for the full public request's SQL events. This is directional local evidence,
not a production p95 claim; it proves the unused graph is material and motivates
real-HTTP parity/query-count gates at both first-round and full 15-race history.

### Friends tab and friend sheets

| Calls | Backend response | Current frontend use | Audit |
| --- | --- | --- | --- |
| `GET /friends` | Accepted friends with cosmetics/animal, photo, friendship ID, eligibility; incoming/outgoing request identity | The page renders name/photo and needs IDs; it does not render character cosmetics | Drop cosmetic joins only in a new compact view. Pending request shapes are already lean. |
| `POST /friends/search` | Up to 20 IDs, display/discoverable names, photos | Renders exactly those fields | Well aligned and bounded. |
| friend mutations | Relationship result, followed by tab reload and shell `onFriendsChanged` refreshes | Updates lists/badge/invite data | One mutation can refresh `/friends`, `/auth/me`, and `/friends/steps`. Invalidate one shared compact friends snapshot instead. |
| friend request sheet | Calls `/friends` again for request context | Uses name/photo/IDs | Reuse shell/tab state where available. |

`/friends/steps` is especially mismatched for this build. The server:

- joins every friend's equipped accessory/shop-item presentation;
- reads today's steps for every friend (Redis bulk with database fallback);
- appends legacy `stepGoal`;
- may enqueue silent step-sync pushes to the full friend set.

The app uses only `id`, `displayName`, `profilePhotoUrl`, and
`teamRaceEligible`, plus list empty/count checks. No current consumer reads the
returned `steps`, `stepGoal`, `accessories`, or `animal`.

### Leaderboard and Ranked

| Screen | Backend response | Current frontend use | Audit |
| --- | --- | --- | --- |
| Leaderboard | `top10`, `top100`, and `currentUser`, with presentation for top rows | Current build reads `top100` and `currentUser`; it renders character presentation | `top10` duplicates the first ten rows for frozen 1.1.4 clients. Keep legacy response; compact opt-in can omit the alias. Cosmetics are genuinely used here. |
| Ranked V2 | Week, current user, cohort metadata, all members, rewards, tiers, last result; member cosmetic joins | V2 rows use rank, ID, name, photo, weekly steps, and zone | Omit cosmetic relations only for V2 compact clients. Reward/tier/last-week fields are used. |
| Legacy Ranked fallback | Legacy ladder with cosmetic presentation | Legacy UI renders capybaras and accessories | Do not apply the V2 cosmetic optimization here. |

### Profile

| Calls | Backend response | Current frontend use | Audit |
| --- | --- | --- | --- |
| `GET /steps/stats` | week/month/year/all-time totals, per-day averages, streak, legacy/new ranked fields, legacy step goal | Uses totals, averages, all-time, and streak only | Response overfetch is small, but the backend scans all history and performs a ranked lookup whose result this screen ignores. Optimize computation and add a compact view. |
| `GET /steps/calendar?month=YYYY-MM` | One row per calendar day with date, steps, future/today, stepGoal, goalMet; top-level stepGoal | Uses ordered rows' steps/future/today/goalMet | At most 31 rows, so low priority. Current build does not use returned dates or either stepGoal field. |

Stats and calendar load independently through their widgets, so they can run in
parallel. That is preferable to serializing them.

### Shop

| Calls | Backend response | Current frontend use | Audit |
| --- | --- | --- | --- |
| `GET /shop/catalog` | coins, owned IDs, equipped map, all visible cosmetic/character items and render metadata, ad-unlock policy | Shop uses the catalog broadly | Appropriate on Shop itself, not on Home. Seed from the shell cache rather than immediately refetching. |
| `GET /shop/powerups` + `GET /powerups/inventory` | Full powerup catalog/ad policy plus owned quantities | Store and inventory sections | Both are used. They currently start only after the cosmetics request completes; start all independent reads together or expose one shop bootstrap. |
| purchase/equip/ad unlock | Action result, then one or more full catalog reloads | Needs authoritative coins/ownership/equipment | Return/consume authoritative deltas or refreshed affected catalog; do not reload unrelated powerup data after a cosmetic-only change. |

### Daily reward, Get Coins, and referrals

| Screen | Calls | Backend response vs use | Audit |
| --- | --- | --- | --- |
| Daily reward | Full `/daily-reward/status`, then claim/extra-claim as initiated | Uses ladder or box mode, exact odds, prize pools, and ad-extra state | Full status is justified on this screen. |
| Home streak chip | Usually consumes lean `dailyReward` embedded in race-card; full status only as fallback | Uses `claimedToday` and `adExtraSpin` | Current batching is good. A compact fallback would prevent full pool construction against an older/partial Home response. |
| Get Coins | Full daily status plus full `/referrals/me` | Uses daily `claimedToday`/`adCoinReward` and referral `referrerCoins`/`refereeCoins` only | High-confidence overfetch and backend-work mismatch. Add one lean status. |
| Referral screen | `/referrals/me` | Uses code, URL, counts, earned coins, reward values, and referred-friend rows | Response is well aligned here. |
| Referral rules | None | Static/server-configured values passed from prior response | No page-local issue. |

The daily status handler is not merely a large JSON response: it loads balance
config, the user's unowned accessory pool, the eligible powerup pool, odds, and
serialized prize previews. Avoiding that work on Get Coins is more valuable
than trimming its bytes after the fact.

### Settings and identity flows

| Screen | Calls and response | Current use | Audit |
| --- | --- | --- | --- |
| Settings | One shared `GET /notifications/preferences`; narrow PATCHes; account/profile/visibility/autojoin mutations; feedback/referral actions on demand | Both notification fields and mutation results | Notification preference read is already coalesced. Payloads are narrow. |
| Display-name and discoverable-identity flows | Availability check and identity update responses | Applies returned user/identity state | Narrow and action-driven. |
| Start/sign-in | Apple/Google/reviewer provision returns session plus own-user envelope | Establishes session and auth state | Appropriate at sign-in. Explicit own-user serialization would still prevent unrelated stored columns leaking onto the wire. |
| Onboarding | Mostly shell-injected conditional calls: inviter-race lookup, featured race lookup/join, referral preview/redeem, tutorial reward, seen acknowledgements | Uses each action result | Conditional, not baseline page load. Existing fallbacks protect old backends. |
| Update-required screen | None | Uses version policy already loaded | No page-local issue. |

### Admin screens

Admin routes are not normal-user hot paths, so they are lower operational
priority even when their payloads are broad.

| Screen | Calls | Audit |
| --- | --- | --- |
| Admin home/sections/onboarding funnel | settings, broad admin stats, paged suggestions | Stats are intentionally broad and consumed across sections. Keep pagination for suggestions; instrument stats separately because aggregate SQL can still be expensive. |
| Accessory tuner | full admin shop items; single-item updates | Fields support editing/preview. Appropriate for admin. |
| Powerup shop admin | full powerup admin list; single-item updates | Appropriate for admin. |
| Balance config admin | current config + version history; save/rollback | Appropriate for admin; history should remain bounded/paged as it grows. |

## Own-user envelope mismatch

`/auth/me` and `/auth/session` serialize almost the complete Prisma user row,
minus only a few explicitly private bookkeeping fields, then add flags and
derived values. The current app needs a meaningful subset:

- ID and email;
- display/discoverable name state;
- profile photo/prompt and rename-chip state;
- admin, coin, and held-coin values;
- onboarding, visibility, autojoin, and referral-attribution state;
- runtime feature flags.

It does not read several persisted fields currently riding in the broad row,
including provider IDs, raw provider name, step-sync timestamps, daily streak
bookkeeping, raw client feature arrays/timestamps, timezone, notification
columns, referral-code ownership, and ranked settlement columns. Some may have
historical consumers, so the old response cannot be narrowed in place.

A new explicit serializer also prevents future Prisma columns from becoming API
fields automatically. The ideal current-client bootstrap is one response that
rotates the session and supplies the complete compact user state, eliminating
the immediate second `/auth/me` read.

## Recommended implementation order

1. **Race message/read cadence:** lean authorization query, eliminate the
   progress-triggered duplicates, initialize Activity plus a Chat watermark,
   cache that body-free watermark separately, then load/combine USER only after
   the first Chat tap.
2. **Race progress projection:** avoid deep static/cosmetic hydration on every
   progress poll; add a one-call screen bootstrap if it reduces duplicate
   details/progress work without delaying first paint.
3. **Race resolution:** remove the display-recompute → full-worker double pass,
   use reason-aware affected scopes with canonical-math/full fallback, coalesce
   hot-race sync generations, bulk persist under the existing fence, and drain
   post-commit tasks outside the core lane.
4. **Tournament detail:** lean complete snapshot, mutation-response reuse, and
   no polling while covered by any pushed route or modal.
5. **Compact friend summary:** no steps, cosmetics, or silent-push fanout; make
   shell and Friends tab share it.
6. **Lean Home presentation:** wallet + equipped presentation only; pass the
   cached full catalog into Shop and fetch independent Shop data in parallel.
7. **Lean Get Coins status:** daily claim/ad block plus configured referral
   reward amounts.
8. **Public discovery bootstrap:** eliminate the full personal `/races` request
   and combine the public listing reads where practical.
9. **Ranked V2 compact members and compact auth/session bootstrap.**
10. **Shop mutation deltas and Profile SQL aggregation.**
11. **HTTP validation/client TTL for static version/copy reads.**

Each phase should first add real HTTP integration coverage for the compact
contract and parity against the legacy path. Then capture, for small and large
fixtures, SQL statement count, response bytes, and p50/p95. Existing legacy
handlers remain available for frozen clients throughout rollout.

## Suggested acceptance budgets

These are targets for a future implementation spec, not measurements claimed by
this audit:

- active race idle traffic: at most one message/activity request per polling
  interval, no duplicate refresh at the progress boundary, and no USER body or
  sender read before Chat is opened; the body-free watermark cache prevents a
  new five-second Postgres hot read;
- cached message poll: no deep participant cosmetic/shop-item query;
- tournament detail: no matchup-user/cosmetic/shop-item query, bounded SQL from
  first-round to full history, and no redundant detail GET after a valid action;
- progress query count should not grow with participant count outside bounded
  bulk reads;
- Home friend summary: constant/bounded SQL, no daily-step reads, no silent push;
- Home presentation: no full catalog item list;
- Get Coins status: no accessory/powerup pool queries;
- Ranked V2: no equipped-accessory/shop-item relation query;
- Public races: no full `/races` request;
- every compact response must preserve the same rendered state and action
  eligibility as its legacy source.
