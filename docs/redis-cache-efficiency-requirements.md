# Redis cache efficiency requirements

Status: ready for user review; architect review passed. Application implementation has not started. Production Redis memory increase to 200mb is complete. Implementation approval and production deployment approval are separate stages.

## Summary and user story

Reduce PostgreSQL work on Home, race-list, progress and bootstrap refreshes by reusing existing caches and retaining safely reusable data longer. A user sees the same screens and response contracts, including immediately updated state after their own action. No change to scoring, rewards, prices, eligibility rules or authorization.

## Proposed work, mapped to the agreed list

1. **Race-list caching:** refresh expired fragments independently; pending 60s, membership/active metadata 120s, completed-list fragments 900s. Fix mutation invalidation before extending retention.
2. **Home equipment:** reuse the existing presentation cache for equipped items; keep authenticated balances outside it.
3. **Home friendships:** reuse relationship and profile caches for Home prompts and the shared Friends-tab preload; preserve full existing response fields.
4. **Empty impact summaries:** cache an explicit empty result for 15s, invalidated on publication/acknowledgment and protected against stale in-flight fills.
5. **Pending invites:** cache candidate IDs/timestamps for 60s; assemble current inviter presentation and participant counts separately. Exclude unrendered legacy friend-racing/finished recommendations and the separate suggested-races rail.
6. **Milestone display:** cache daily steps and claimed thresholds by user/local date for 30s; invalidate on ingestion, corrections and claims. Claims remain database-validated.
7. **Shared race details:** cache descriptive race metadata and membership counts for 300s, and reuse existing worker-published standings. Monetary/settlement aggregates remain authoritative.
8. **Viewer race slots and queued boxes:** cache a user/race-specific display fragment for 30s; invalidate on every relevant committed inventory mutation. Do not cache consumable box notices.
9. **Event display:** cache viewer/race eligibility display data for at most 30s, bounded by event transitions and invalidated on entitlement changes. Scoring does not consume this cache.
10. **Standings freshness:** increase the shared display freshness window from 15s to 30s across its readers, preserving stricter validity checks. Keep five-minute shared snapshot retention and fifteen-minute paged-projection retention. Paged calls already reusing a valid projection are not counted as newly avoided SQL fallbacks.
11. **Measurement:** record bounded per-path hit/miss reasons, age windows, actual PostgreSQL fallback counts and total query/Redis/worker work. Report measured savings after each implementation slice.

### TTL summary

TTL is a retention backstop. A relevant committed mutation invalidates or replaces the entry before its normal expiry; absolute event/invitation/race boundaries can make it unusable sooner.

| Data | Current | Proposed |
|---|---:|---:|
| Race-list pending fragment | 15s | 60s |
| Race-list membership/active stable fragment | 30s | 120s |
| Race-list completed fragment | 300s | 900s |
| Shared completed-result summary | 30 days, result-versioned | Unchanged |
| Home equipment/friend topology cache | Existing 3600s caches not consistently reused by Home | Reuse existing 3600s caches |
| Empty impact summary | Not cached | 15s |
| Home pending-invite candidates | Not retained across requests | 60s |
| Milestone display | Batched SQL | 30s |
| Shared descriptive race metadata/membership counts | SQL/request-local reuse | 300s |
| Viewer in-race slots/queued count | SQL | 30s |
| Race-scoped event display | SQL | At most 30s, bounded by transitions |
| Shared standings freshness | 15s | 30s |
| Shared standings physical retention | 300s | Unchanged |
| Paged standings physical retention | 900s | Unchanged |

### Delivery order

- Establish repeatable baseline measurements and implement/test writer invalidation support first.
- Implement list fragments, Home equipment/friend reuse and empty-result caching; measure each slice independently.
- Implement pending invites, milestones, shared race fragments, viewer slots and event display using the contracts below.
- Apply 30s freshness only after all affected read-path and time-boundary tests pass; retain before/after age-window measurements.
- Prepare two reviewable backend release artifacts: **A adds compatible writer invalidation**, then **B adds readers and longer TTLs** after A is fully running. This sequencing protects mixed workers without a feature flag. Each production deployment requires separate authorization.

## Evidence and scope

Backend audit baseline: production/local backend commit 3292872a31fb270773ab729ee00aeedfeb1e5875. Rebase findings against the implementation checkout before editing. Existing work in both repositories belongs to other tasks and must be preserved.

Production Redis maxmemory was raised from 100mb to 200mb on September 9 at 20:16:49 UTC; runtime and persistent configuration verified, no restart. Redis had approximately 18 MB used and zero evictions, so increasing capacity alone is not a demonstrated performance improvement.

Two-week Nginx data: 5.02M app-route requests, 73.9% GET/HEAD. GET progress/bootstrap total 338,817 (~24,201/day), but most solo calls use pages already retained past the 15-second freshness boundary. HTTP methods and elapsed request time are not SQL counts or CPU measurements. No predicted percentage saving is an acceptance criterion.

This is backend caching work. No new screen, layout change, application release requirement, rollout flag or runtime toggle. No production deployment or further infrastructure change is authorized by this document.

## Home usage clarification

Current Flutter `lib/screens/tabs/home_tab.dart:325` displays pending invites and setup prompts. `:389` conditionally displays next-race UI, and `:643` builds a separate suggested-races rail. `_buildRaceOpportunityRow` is invoked only by the pending-invite section; its friend-racing/friend-finished branches are not reachable from current Home rendering.

`lib/screens/main_shell.dart:3757` consumes the Home shell's full friendship summary, updates friend counts/pending request state and seeds the shared Friends repository. Home uses friendship counts for the add-first-friend prompt and share-first behavior; the full summary also serves the Friends tab. It is not an on-Home friend roster.

Backend `src/modules/home/getHomeRaceCard.js:1870` still evaluates legacy friend-racing/finished/public fallback states. This plan does NOT add a new cache for those unrendered recommendation states or remove old-client response states. A separate compatibility audit must establish the exact shipped-client cutoff before eliminating that work. Item 5 is narrowed to pending-invite data; the independent suggested-races and next-race systems remain outside this change.

## API contract and compatibility

Existing requests, responses, status codes and capability filters remain unchanged for:
- GET /home/race-card (legacy and shell-v1)
- GET /races (legacy and compact-v1)
- GET /races/:id/progress (legacy/unpaged, team, paged and compact)
- GET /races/:id/bootstrap (legacy and compact)
- Existing friend, inventory, milestone and event reads that share the selected caches.

No new endpoint, request parameter or response field. Implementations must retain the real baseline JSON fixtures and compare responses through HTTP: legacy headers, absent optional capabilities, modern headers, both release channels. Personalized data cannot enter viewer-neutral snapshots. Shared caches store domain fragments and serializers keep applying viewer, client capability, release-channel and timezone rules. Preserve missing/null response behavior and standalone endpoint fallbacks.

Cache misses/errors fall back to bounded PostgreSQL reads or existing persisted-score fallback. A cache write error cannot fail a successful business action. New cache keys use additive internal schema versions; no global cache flush. Do not silently change existing immutable key contracts for mixed-version workers.

## Implementation sequence and cache contracts

### 1. Establish measurement

Add low-overhead aggregate counters to existing observability: by fixed endpoint/read-path labels, hits, missing keys, expired snapshot ages (0–15s, >15–30s, >30–60s, >60s), generation mismatch, timezone mismatch, effect/event/race boundary invalidation and Redis errors. Count actual PostgreSQL fallback invocations and relevant SQL operations separately. Do not log user/race IDs, raw keys, request bodies or query values. Bounded labels, coalesced telemetry publication, no Redis/SQL write per hit. Use existing telemetry infrastructure; no new metrics endpoint or flag. For 30-second counterfactuals count only >15–30s snapshots passing EVERY other validity check.

Files: backend `src/shared/observability/`, `src/modules/races/queries/getRaceProgress.js`, `src/modules/races/services/raceListCache.js`, Home cache consumers. Record cold/warm/mutation workloads on dedicated test DB and test Redis before/after each slice.

### 2. Race-list fragments and longer retention

Proposed hard TTLs: membership/active stable fragment 120s (was 30); pending 60s (was 15); completed-list fragment 900s (was 300). The separate shared completed-result cache remains versioned with its existing 30-day retention.

Source: authoritative race and participant rows. Keys: user-scoped fragment kind, cache schema and client/channel variant where required, plus generation. Each fragment loads only its missing status set; an absent pending fragment must not reload existing completed or active fragments. Maintain status partition consistency: one coherent generation across fragments, no duplicate races, no race disappearing at a start/completion boundary. Recheck generation before installing/serving loads. Introduce additive schema-v2 fragment keys including user, variant and generation; do not reuse the unversioned legacy membership payload. A partially refreshed aggregate is source=mixed, never source=postgres: `findSqlSummariesForUser` must retain authoritative membership/status/result-version validation for every cached contribution. Carry requested extraCompletedRaceIds separately and reconcile them on every warm read; they are not implied by a cached membership list. Concurrent mutation invalidation must win over an older in-flight fill, using the existing bounded generation/CAS machinery (extend where necessary). Cached data never authorizes membership. Atomically install each fill only if its captured generation still matches; reject a mixed assembly if its generation changes or any status-boundary source validation fails. Targeted refresh must not make a completed race appear twice or disappear between partitions.

Update `raceListCache.js`, targeted loaders in `models/race.js`, `queries/getRaces.js`, key builders and existing event invalidation. Preserve existing mutation events (create/invite/accept/decline/join/leave/kick/forfeit/team-switch/edit/buy-in/start/complete/cancel/results-seen), authoritative result-version repair checks, extra completed IDs needed by payout offers, visibility and maximum payload bounds. Time-derived invite/availability fields must be recomputed or validated against absolute deadlines on every hit. Audit all actual mutators and repair/admin paths before increasing TTL; a missed hook cannot be assumed safe because the current list names events. Existing eventBus.emit ignores handler promises, and race-list listeners launch invalidation and participant fan-out without awaiting them. These events are notifications, not a consistency guarantee. Relevant mutation endpoints must await a bounded post-commit generation advance/invalidation before returning, or affected readers must validate an authoritative source version. Reuse already-loaded affected identities and bounded batches; do not await thousands of per-user Redis calls. A cross-worker immediate GET after the mutation response must observe the committed change without test sleeps.

### 3. Home equipment and friendship reuse

Home equipment source: equipped accessories/shop records. Reuse/extend `userPresentationCache.js` through `getHomeShellPresentation.js`; cache the domain data required to recreate the exact existing Home payload, keep authenticated coins outside the cache. Preserve test-only, remote-asset and character filters. Invalidate on equip/unequip, relevant identity/presentation and catalog changes. Keep the existing cached cape lookup unless evidence justifies replacing it.

Friends source: accepted/incoming/outgoing relationships plus required public user presentation. Reuse `friendsTopologyCache.js` and `userPresentationCache.js` in `getFriendsSummary.js`; also reuse accepted IDs where the Home core needs them. Retain discoverable name, feature-based team eligibility, pending-row field restrictions, sorting and request counts. Existing caches may need additive payload schemas and missing fields. Do not join and reload all profiles to rebuild a supposedly warm cache. Existing one-hour payload and generation guards remain; new field invalidation must include identity/profile/capability changes and friendship accept/reject/cancel/remove. No new friend-list UI.

### 4. Empty impact-summary results

Source: eligible unacknowledged summary query. Add an explicit negative envelope for no eligible summary, with a proposed 15s TTL. Never confuse it with an absent Redis key or cache a loader error as empty. Existing positive results retain expiry-bounded lifetimes and decreasing validForMs. Invalidate on summary publication, acknowledgment, repair/replacement and expiry-related state changes, preserving generation fencing against in-flight fills. Use `globalEventSummaryCache.js`, existing Home summary producer/acknowledgment seams, additive keys and existing batching fallback.

### 5. Pending invites only

Audit/cache the Home pending-invite candidate fragment, user-scoped with proposed 60s retention. Its pinned fields are invitation/participant ID, race ID, inviter ID, creation timestamp and absolute invitation expiry only, in existing source order. Filter against current race access/status and client capabilities before selecting the first eligible candidate. Hydrate inviter equipment/profile through the existing presentation cache and participant count through the separately versioned membership-count fragment; do not put those mutable fields inside the candidate cache. Preserve source ordering and validation of invitation expiry, race status, membership and capability visibility on hits. Invalidate both involved users on invite creation/response/cancel and affected recipients on race start/completion/cancel/edit or membership changes. Empty results may be cached under the same generation rules. Do not cache legacy friend-racing/finished/public recommendations in this scope. Do not suppress a new invitation until the TTL expires after a committed mutation. Apply the same awaited post-commit version/invalidation requirement as §2; the current fire-and-forget event listeners are insufficient.

### 6. Milestone display data

Source: daily step total and claimed thresholds. Cache a user+localDate domain fragment with proposed 30s retention. Reuse daily-steps cache only when its source/date semantics exactly match; otherwise use a dedicated schema. Invalidate after every committed step mutation for affected dates, milestone claim, corrections and relevant admin repair. Serialize reward amounts from the authoritative configuration, not a stale cached pricing payload. Midnight selects a new date key. Claims still validate against PostgreSQL in their existing transaction, never trust cached claimability. Preserve successful-claim immediate refresh and Redis outage behavior.

Files: `steps/queries/getStepMilestonesToday.js`, `home/services/homeLaunchAuxiliaryBatch.js`, daily cache/read and mutation seams found by audit.

### 7. Race metadata and participant summaries

Source: race row and participant aggregate query. Reuse versioned stable race metadata and publish eligible shared summaries with the authoritative worker result generation for progress/bootstrap. Current `raceParticipantReadSummary.js` mixes membership counts, money/settlement-related aggregates and legacy participant ID arrays; separate fragments according to actual invalidation dependencies rather than label the whole result static. No cached metadata or array authorizes access. Avoid duplicating growing all-member arrays on every page; retain legacy wire arrays only where required, with existing bounded read fallback.

Use `raceBootstrapReadContext.js`, `getRaceDetails.js`, `getRaceProgress.js`, `raceParticipantReadSummary.js` and worker post-commit publishers. On generation mismatch, absent/malformed fragments, or Redis failure, preserve existing query path. Immutable completed fragments are versioned by repair/result version. Pending/active membership metadata invalidates at membership/status/edit changes. Shared derived totals refresh on worker publication. Do not make every step sync invalidate all metadata or create N additional per-participant Redis operations.

### 8. Viewer race inventory and queued boxes

Source: in-race slots and queue rows (distinct from global inventory). Add bounded user+race/participant fragments, proposed 30s retention, with atomic generation checking against relevant mutations. Audit redeem/use/open/reroll/discard/upgrade, worker mint/promotion, race transitions and admin grants/repairs. Keep access checks, mutation validation and claim/consumption side effects authoritative. Recent-box notifications remain consumable per-user/per-race state and must not be replayed by caching the full response. No change to drops, odds, prices or scoring.

### 9. Display event eligibility

Source: event schedule, viewer entitlement and race eligibility. Reuse existing global schedule cache where semantically equivalent and introduce only the missing viewer+race display fragment, proposed maximum retention 30s, capped by next start/end/eligibility boundary. Include or validate relevant timezone/date and entitlement generation. Invalidate at entitlement admission, timezone refresh, event start/end/cancellation and race eligibility changes; bound fan-out and reuse existing transition batches. Do not use Home's user-only eligibility key for a race-scoped lookup. Scoring/settlement continue using authoritative sources.

### 10. Standings freshness

Raise shared display freshness from 15s to 30s after boundary/read-path tests. Preserve shared snapshot 300s physical retention and paged projection 900s cleanup retention. Audit every `isFresh` caller: normal unpaged/team reads, Home legacy reuse, paged projection classification, preview and worker pathways. Do not weaken generation, timezone, mutation, effect or race/event boundary rules. Paged readers already reuse older valid generations; do not claim their request volume is a new saved SQL query.

The shared freshness helper currently checks effect expiry; audit event/race transitions independently before widening age eligibility. Worker ownership and publication behavior stay permanent. No new scoring-on-read behavior or DISPLAY_REFRESH jobs. No additional queue work solely to support this TTL increase. New publications replace old snapshots promptly; 30s is a maximum accepted display age, not a scheduled update interval.

## Exact additional cache contracts

Logical keys below receive the existing environment prefix. `ce:v1` denotes a new internal cache-efficiency schema, not an app capability. Payloads are allowlisted; no coins, eligibility decisions or settlement inputs are admitted unless explicitly listed as display-only below. Each cache test must assert the allowlist and cross-user isolation.

Generation protocol: compatibility release A installs all writer hooks before release B introduces these readers. New domains use `ce:v1:g:<domain>:<identity>` opaque random tokens; atomic SET replaces a token on mutation, with TTL at least twice the domain's longest payload TTL. Random tokens avoid ABA after eviction. On missing marker, a reader establishes a new token with SET NX, reads it, loads from PostgreSQL, and uses atomic compare-and-set to install only against that token. A payload without a matching live marker is a miss. Validate markers after the bounded payload read too. Cache error opens the existing local/peer bypass and retries invalidation; cache mutation failure does not roll back committed business data. Release A and B use identical marker identities and hooks. Existing cache domains retain their proven generation protocol and A extends every relevant writer to it.

| Surface | Logical identity; retention | Pinned cached data | Generation and awaited post-commit writer seams | Bounded behavior/fallback |
|---|---|---|---|---|
| List fragments | `ce:v1:list:<user>:<variant>:<kind>:<token>`; 120/60/900s | Existing race-list stable allowlist, excluding embedded presentation; preserve serialized fields via existing presentation hydration | User list token advanced for direct membership/invite changes; race token for status/edit changes; A updates existing legacy list invalidation too. Events listed in §2 identify the commands, but actual command/worker post-commit code awaits advancement. | Payload caps 128 races/512KB; batched MGET race tokens plus authoritative existing membership/result checks. A race edit advances one race token, not thousands of new per-user jobs. Mixed partial loads retain source checks. |
| Home equipment | Existing presentation identity with additive payload version; 3600s | Required equipped accessory/item domain fields, identity/presentation fields already supported; no coins | Existing presentation generation; `cosmetics/equipAccessory.js`, profile/character updates and catalog mutations update it through existing or A-added hooks | Bulk get and bounded DB load; channel/capability filters per response; existing cape local cache unchanged |
| Home friends | Existing topology identity/version; 3600s | Existing accepted/incoming/outgoing relationship IDs; names/photos/discoverable identity/clientFeatures supplied by presentation cache | Existing topology and presentation generations; social send/respond/cancel/remove commands and user identity/capability updates, including shared-user changes | Bulk presentation lookup, no per-friend SQL loop; old summary contract and pending field restrictions preserved |
| Empty/positive impact summary | `ce:v1:summary:<user>`; empty 15s, positive original remaining expiry | `kind=empty` or immutable existing summary response fields, excluding recomputed validForMs | User summary token; `steps/jobs/globalEventSummary.js`, `steps/services/globalEventSummaryLifecycle.js`, Home acknowledgment and repair paths | No failure cached as empty; compute expiry using authoritative loaded timestamp and Redis remaining TTL; single user marker, existing batch load on miss |
| Pending invite candidates | `ce:v1:invites:<user>`; 60s | Candidate fields defined in §5 only | User invitation token for create/response/cancel/revocation; current race context/metadata tokens independently validate status. Race membership token supplies counts; existing presentation token supplies inviter appearance. | Existing candidate bound/order; re-filter expired/incompatible candidates before selecting; no inviter-profile or count fan-out to all invitees |
| Milestone display | `ce:v1:milestones:<user>:<localDate>`; 30s | Current daily step total and array of claimed thresholds only | User/date milestone token; `steps/models/steps.js` committed update APIs, every step-intake transaction/correction using those writes, `steps/commands/claimStepMilestone.js`, relevant repair/admin paths | Coalesce affected user/date keys in each existing intake batch; not one operation per raw sample. Missing/error uses current batched steps+claims query. Reward amounts remain current config; transaction validates claims. |
| Descriptive race metadata | `ce:v1:race-meta:<race>`; 300s | id, name, creatorId, startedAt, endsAt, scheduledStartAt, scheduledEndAt, timezone, isTeamRace, teamSize, team names, tournament identifiers; omit money, viewer fields and current authorization status | Race metadata token on create/edit/start/end/cancel/team naming/repair; current access/status still loaded authoritatively | One race token per change, not per participant; validated metadata merged only into matching current race context; DB core loader fallback |
| Participant membership counts | `ce:v1:race-members:<race>`; 300s | totalCount, acceptedCount, teamACount, teamBCount only | Race membership token on create/invite/accept/decline/join/leave/kick/team switch and membership repair | One race token; no participantUserIds arrays copied into cache, no step-driven invalidation. Existing aggregate query fallback where current serializers need additional fields |
| Score-derived shared presentation | Existing worker projection generation/keys; existing 900s page cleanup TTL | Existing standings plus only already-derived participant count/team presentation aggregates proved equivalent to current display | Existing resolution generation, atomic post-commit publication/invalidation | Keep step-dependent qualifiers, recipient counts, held pot, settlement counts and payout arrays outside this new cache. No second race-wide SQL aggregate merely to populate it; reuse already-loaded worker results. |
| Viewer slots/queued boxes | `ce:v1:slots:<race>:<participant>`; 30s | Slot id/type/rarity/status and queued count, no consumable recent-mint notices | Participant inventory token at `powerups/commands/{redeemPowerupToRace,usePowerup,openMysteryBox,openMysteryBoxBatch,rerollMysteryBox,rerollMysteryBoxBatch,discardPowerup}.js`, race powerup state sync/repair, upgrade and admin mutation paths found in direct model-write census | Use shared model/post-commit invalidation helper to cover all row mutations; one token per affected participant per transaction, pipelined bounded batch; authoritative action validation and existing slot/count reads on miss |
| Race display event eligibility | `ce:v1:event:<race>:<user>:<timezone>`; max 30s and earlier next time boundary | eventId, multiplier, startsAt, endsAt or explicit empty; no admission decision | User entitlement token + race/event token read in bounded MGET. Entitlement service admissions/timezone changes, boundary/end drain jobs and cancellation/repair advance tokens in existing batches. | A token affects all variants; no enumerating timezone keys. Empty result lifetime capped at next known start; if that boundary cannot be established, do not cache empty. Existing entitlement/global-event read fallback; scoring ignores this cache. |

A direct model-write census per domain is a required implementation artifact: list every source writer, its transaction boundary and shared awaited hook. A domain cannot be enabled by release B until all writers in release A are covered by integration tests. Any newly discovered source outside this contract triggers a design amendment, not a guessed invalidation hook.

## Data model and rollout

No database migration or backfill expected. If generation durability cannot be met with existing infrastructure, stop that slice and amend this design before implementing a migration. Redis stores only reconstructible data, under additive/versioned keys with bounded retention. Mixed-worker protocol is TWO additive backend releases, without a flag: A installs awaited post-commit invalidation/generation hooks while old readers remain unchanged; only after every HTTP/cron/resolution process runs A and old in-flight jobs have drained may B introduce the new cache readers and longer TTLs. B supports writers from either A or B, so its rolling deployment is compatible. A-to-pre-A overlap cannot expose new payloads because no new readers exist yet. Roll back B to A, not directly to a pre-A writer while new readers exist. Test A-writer/B-reader and invalidation failure/recovery explicitly. Both production releases require their own explicit in-the-moment deployment approval; neither is authorized now. Source version checks still protect race-list status/result repair and existing authorization.

Backend first after explicit in-the-moment production deployment approval, preserving exactly two HTTP workers and stopped staging. No new Flutter binary is required for these backend-compatible changes. Redis capacity is already 200mb; future memory/worker changes are outside approval. No production cache warm-up writes or synthetic user mutations during verification.

## Frontend plan

No UI/layout or Dart product changes planned. Frontend implementation agent owns compatibility verification against real Home, race detail, Friends and tutorial/demo screens for both platforms, extending meaningful widget tests only if existing coverage cannot express a changed backend contract risk. Missing optional shell data must retain standalone fetch/fallback behavior. No manual UI-placement checklist required because placement is unchanged. Verify existing mirrors through relevant widget suites; do not redesign them.

## Tests-first plan

Use real HTTP, dedicated local/test PostgreSQL and isolated Redis. Confirm test DB names before starting. Existing assertions are protected; surface any incompatible pre-existing TTL assertion rather than silently weakening it.

- List: warm mixed-status fragments, expire one only and assert targeted SQL work; empty pending; mutations while fill in flight; status movement; extra completed payout IDs; result repair; old/modern response parity; Redis errors; bounded large list.
- Home: repeat equipment/friend reads without reloading rows; update equipment/name/capabilities/relationships and immediately fetch exact new response; channel/capability isolation; pending invite negative-to-positive and time expiry; summary absence/creation/acknowledgment/expiry; pending invitation continues to render.
- Milestones: warm display, step ingest, late correction, claim and immediate refresh, local-date rollover, two users, fallback during Redis failure; existing rewards unchanged.
- Race fragments: progress/bootstrap share the same generation, membership revoke/privacy, worker publication during a read, repaired completed results, team mutations, paged/unpaged legacy compatibility, viewer slots/queued boxes and recent-mint one-time delivery.
- Freshness: injected timestamps at 14/16/29/31 seconds through public request paths; effect boundary sooner than TTL, race finish, event start/end, timezone mismatch, missing/corrupt Redis and generation replacement; no request scoring/jobs.
- Measurement: warmed HTTP endpoints issue fewer actual SQL operations in relevant paths than baseline; annotate exact query counts, Redis operations, fallback counts and payload sizes. Include worker/invalidation work, not only handler savings. Thousands of concurrent step syncs must not turn invalidation into unbounded fan-out; bounded burst test on isolated local infra.

Representative existing suites: backend `test/integration/race-list-cache.test.js`, `completed-race-summary-cache.test.js`, `home-screen.test.js`, `home-race-card-modern-standings-bypass.test.js`, `active-impact-home-summary-cache.test.js`, `redis-cache-c3-standings.test.js`, `race-effect-expiry-cache.test.js`, `race-bootstrap-performance.test.js`, `race-bootstrap-persisted-standings.test.js`, `redis-cache-c4-user-bits.test.js`. New public-path integration suites cover uncovered seams. Run relevant unit tests only for pure boundary math/structural guards; never bare npm test.

## Acceptance and execution ownership

Backend agent implements one tested slice at a time, first pinning the unchanged API contract. Frontend agent verifies both-platform consumers once the contract is pinned. All code remains local/reviewable until deployment approval. Required code-reviewer reviews combined implementation, including concurrency/invalidation and tests. Flutter analyze must be clean; relevant tests pass; report skipped/failed tests plainly. No price/scoring rule edits and no UI-placement changes, so game-balance/UI-placement agents are not needed for this design.

Every implemented cache documents source, key identity, retention, mutation/time invalidation, miss/error fallback and race-condition handling. Measurement establishes actual reductions; no assertion of 50% savings from doubling TTL. No complete personalized response cache. Old-client and mixed-worker compatibility are requirements, not optional follow-up.

## Revision log

- Gap pass 1: distinguished modern Home count/shared Friends preloading from unrendered legacy friend-racing/finished cards; narrowed item 5 to pending invites and excluded speculative recommendation caches. Preserved old-client states and separate suggested-races rail.
- Gap pass 2: added coherent fragment-generation requirements, time-bound pending validation, result repair version checks, additive mixed-worker cache schemas, mutation-versus-fill races, 30s counterfactual metrics and workload accounting for invalidation/worker costs. Distinguished global inventory from viewer race slots and display caches from authorization/claim/settlement.
- Architect review pass 1: incorporated all five required changes: awaited mutation fencing, mixed-fragment provenance and additive keys, explicit invalidation-first A/B release protocol, isolated pending candidate data/presentation/counts, and per-surface key/allowlist/TTL/generation/hook/fallback contracts. Excluded monetary/settlement/step-qualifier aggregates from new shared cache. Follow-up architect review: APPROVE, no required changes; retained cross-worker failure/recovery tests and per-slice total-work measurement.

- Final editorial pass: added the original eleven-item scope mapping, consolidated TTL table and delivery-order summary; no changes to the architect-approved contracts.
