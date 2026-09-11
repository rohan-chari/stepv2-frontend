# Simple event recap and complete worker retirement

Status: approved for implementation on 2026-09-11; architect required changes addressed and game-analyst verdict SOUND. Production deployment, production cleanup and app uploads require separate authorization. This replaces the proposed overload-controller work for the recap; it does not add a queue or coordinator.

## 1. Product contract

After the first eligible app open/resume following the user's daily 30-minute 2× event, complete normal step sync, read the platform's raw step aggregate for that exact event window, save one simple recap, and display:

**“X extra steps gained across all races.”**

For 2×, `X = raw event-window steps × counted races`. Do not multiply by two: that would include the ordinary steps as well as the extra steps. Example: 1,000 steps and three races gives 3,000 extra steps.

This is an intentionally simplified recap, ignoring all powerups, dependencies on other users, race-specific scoring windows, and counterfactual calculations. It does not claim equality with the actual credited score when those factors differ. Actual race scores, event multipliers, leaderboards, coins, boxes, and payouts do not change. The user explicitly chose the copy above rather than an “estimated” label.

User-confirmed rules:

- Count the distinct eligible races at the user's event start, using server-owned event enrollment evidence. A later join does not increase this recap; a later leave or finish does not decrease it. No partial-race arithmetic. Store this scalar alongside the existing activation, using the already-selected eligible cohort; do not add a recap job or a per-race snapshot table.
- Offer only the latest completed eligible event on its calendar day, expiring at the next midnight in the entitlement's captured timezone. No next-day recap or backlog of popups. Selecting a newer event permanently supersedes older unseen candidates for this user. Retain the existing same-calendar-day expiry semantics, including DST-safe midnight calculation.
- A valid zero raw count or zero race count creates a saved suppressed result, with no popup. Missing/failed health input is not zero and creates no result.
- Freeze the first committed result. Later uploads/corrections and additional devices cannot rewrite it. Acknowledgment is shared across devices. Never promise exactly-once physical display across a crash or two simultaneously open devices; preserve existing best-effort local consumption plus server acknowledgment.

## 2. Existing evidence and why cleanup matters

The old worker is `src/modules/steps/jobs/globalEventSummary.js` in the backend. It performs V1/V2 recovery, claims, capture draining, readiness checks, retries, race handoffs, and retention. `src/index.js` starts it in normal and capacity startup paths.

`durable_capture_steps_source` and `durable_capture_samples_source` also journal meaningful writes to `steps` and `step_samples`, including users without pending recaps. Removing only the cron would leave this write amplification installed.

Recent completed minute buckets contained 182 summary claims returning 28 rows in total: at least 154 empty claims. A later two-minute observation had only two, then zero lease-release UPDATE calls while managed DB CPU remained elevated. A persistent summary retry loop is therefore not established as the main CPU cause. This project guarantees removal of the retired work paths, not a specific whole-database CPU percentage.

The currently deployed backend was observed at `5f67302`; the ordinary local checkout was `2fad3ce` with unrelated edits. Implementation must start from a freshly verified production-descendant checkout and incorporate the newer durable-capture batching/step-correction fixes in its removal audit. Do not deploy the stale local checkout or overwrite concurrent race-cache/tournament edits.

Implementation baseline reverified read-only on 2026-09-11: production and the local backend both at `9b08e5f9b50250cae431177e67e73e24dd6b2b34`, including the intervening Races-tab cache change. Frontend baseline is `587d8cb`; unrelated documentation edits remain preserved.

## 3. Minimal new flow

1. The existing event-start processing records `recapRaceCount` and the event-window/revision identity with the user's entitlement. No recap work row is created.
2. The app uses its existing coalesced cold-open/resume sequence to await a successful normal step sync. No polling for summary work remains.
3. Authenticated `GET /home/event-recap` returns either an existing saved positive recap, no candidate, or one eligible event window needing raw input.
4. For a pending candidate, expose a thin public wrapper around `HealthService._stepsInInterval(start,end)` and read precisely those UTC instants. This avoids hourly-upload interpolation and historical whole-day resync. It reuses existing HealthKit/Health Connect source deduplication and manual-step exclusion.
5. Authenticated `POST /home/event-recap` validates the candidate and saves `rawSteps × serverRaceCount` once. This count is display-only and never enters step/scoring/coin tables.
6. Show the existing Home dialog in its existing overlay order. Use the existing acknowledgment URL. Subsequent opens read the saved result or its consumed/suppressed state.

No recurring recap timer, backend job, durable capture, event-wide scan, or recap-driven race recalculation is involved. The ordinary event scheduler, step sync, and race workers continue their actual product responsibilities.

### Health and sync edge cases

- Normal step persistence currently reads today's samples only (`main_shell.dart:2276–2390`). The explicit event-window health aggregate isolates the 30-minute window without approximating it from hourly uploads, including when device and entitlement timezones differ. Next-day opens are ineligible. Do not use `getStepsForDateRange` (normalizes dates) or `getStepSamples` (buckets and conflates omitted zero/null samples).
- Home currently reloads even after an unsuccessful sync. The new finalize flow must require success; failed/ambiguous/cooldown-skipped sync defers until a later eligible open or explicit refresh. It must not block ordinary Home rendering.
- Android revoked/unknown permissions: defer. Null/exception from either platform: defer. iOS cannot distinguish all denied reads from genuine zero accessible steps; a successful OS zero aggregate is treated as zero under the chosen simple-recap policy. Never fabricate a positive count or call zero proof that a user physically did not walk.
- The native platform aggregate is the input contract, not a promise of exact individual footstep timing; recording chunks may overlap boundaries. No new sample reconstruction algorithm.
- Coalesce cold-load/resume/refresh requests in the existing MainShell lifecycle. Check auth/session identity after every await, and discard results after account change/disposal. Ordinary background five-minute sync does not trigger a new recap health read on a capable app.

## 4. API contract and old binaries

New capabilities advertise `simple_event_recap_v1`; this is a truthful client interaction capability, not a rollout switch. The backend owns eligibility and race count. No new required fields on any existing endpoint.

Update both branches of `clientFeaturesHeader` and `clientFeaturesHeaderForPlatform` in `backend_api_service.dart:353–405`; iOS and Android must both advertise the implemented interaction.

`GET /home/event-recap` (authenticated, no body):

```json
{"state":"pending","event":{"id":"event-id","revision":3,"startsAt":"2026-09-11T22:00:00.000Z","endsAt":"2026-09-11T22:30:00.000Z","expiresAt":"2026-09-12T04:00:00.000Z","raceCount":3}}
```

```json
{"state":"ready","globalEventSummary":{"id":"recap-id","eventId":"event-id","extraRaceSteps":3000,"raceCount":3,"settledAt":"2026-09-11T22:40:00.000Z","expiresAt":"2026-09-12T04:00:00.000Z","validForMs":19200000}}
```

```json
{"state":"none"}
```

`POST /home/event-recap`:

```json
{"eventId":"event-id","revision":3,"rawSteps":1000}
```

Returns HTTP 200 with the same ready/none envelope; repeated requests return the first saved result, including suppressed or acknowledged results as `none`. Validate integer nonnegative rawSteps and overflow against the existing signed-32-bit `extraRaceSteps` wire contract; reject invalid input instead of clamping. Never accept raceCount, multiplier, userId, or arbitrary time bounds from the client. This endpoint is not an economic authority: tampering can only falsify the caller's own recap.

Replay precedence: an owned saved result that has expired or been superseded returns `none`; expired/superseded input with no committed result returns the documented 410. Apply the same latest-event predicate to GET, POST and both Home readers.

Errors: existing authentication 401; malformed body 400 `INVALID_INPUT`; unknown/not-owned event 404 `NOT_FOUND`; not-ended or changed candidate 409 `EVENT_NOT_READY` / `EVENT_CHANGED`; expired/superseded candidate 410 `EVENT_EXPIRED`; transient failure existing generic 500. Unknown/malformed new response and 404 on an older backend cause silent deferral, not a crash or fallback into removed worker polling. Recompute expiry/ownership/server race-count checks at the committing transaction. Do not accept a count supplied for a changed window.

Keep both existing Home response shapes' optional `globalEventSummary` envelope exactly compatible. Existing `/home/global-event-summaries/:id/acknowledge` retains 200 `{ "acknowledged": true }`, 409 `ALREADY_ACKNOWLEDGED`, and owner-safe 404 behavior, backed by the new saved-result table.

Old clients cannot perform the new window-read interaction. On their existing successful post-event sync, call the same small save-once calculator using the existing raw sample overlap/proration helper only when accepted stored sample intervals form a contiguous union covering the entire event window (one bounded user/window read shared by validation and summation). Do not require summary workers, powerups, or race completion. Do not finalize from a daily-total-only or failed sample upload. `canonicalCoverageThrough` is only a maximum endpoint: neither it nor accepted-sync status proves full coverage. Existing mobile uploads omit zero buckets, so a gap is ambiguous and must defer, not be filled with zero. Bound sample rows; an over-limit input defers rather than finalizing a truncated sum. This legacy path is a thin input adapter, not a second summary engine. Old clients still receive compatible saved recaps through Home and can acknowledge them; an unprovable new recap is omitted. Capable clients use only explicit POST finalization, so an earlier coarse upload cannot win before their exact-window aggregate.

Old `/home/global-event-summary-work/:id` remains a tiny authenticated terminal shim: preserve capability/UUID validation; for a valid retired work ID shape return HTTP 200 `{ "state":"EXPIRED_UNDELIVERED", "expiresAt":"<server-now-UTC>" }`, uniformly without revealing existence/ownership or querying a deleted table. No new sync generates an old work receipt. Preserve immutable historical step-sync response JSON; replayed old receipts terminate through this shim rather than requiring old worker storage. The new client removes all receipt parsing/polling.

Legacy adapter entry points are successfully accepted sample writes from `/steps/sync-v2` and `/steps/samples`, never daily-total responses. Validate closed intervals and reject unresolved overlaps or an open/partial final bucket before applying the existing proration helper. Zero/missing gaps remain ambiguous. Neither entry point introduces retries or a new background task.

## 5. Data and concurrency

Create `event_recaps`: id, event_id, user_id, calculation_version (`SIMPLE_RAW_V1` or migrated `LEGACY_SAVED`), raw_steps nullable only for migrated results, race_count, extra_race_steps, settled_at, expires_at, acknowledged_at, suppressed. Unique `(event_id,user_id)`; indexed `(user_id,settled_at DESC,id)` and expiry. User deletion cascades through the established deletion flow. Preserve required event linkage/deletion behavior.

Add entitlement columns `recap_race_count INT NULL CHECK (recap_race_count >= 0)`, `recap_count_policy_version SMALLINT NULL` (1 = START_COHORT_V1), and `recap_window_revision INT NULL`, with an all-null/all-present constraint. Existing `schedule_revision` is the API `revision`; existing start/end/timezone fields remain authoritative. GET requires a complete stamp matching that revision. No duplicate window columns or separate revision generator.

Stamp atomically with start processing, only while the stamp is null: single activation in `globalStepEventEntitlement.js:795`; batch activation near :1168 uses set-based entitlement-ID/count values, including a proven empty cohort as zero. Reuse the loaded cohort only when it establishes eligibility at the actual event start. Delayed processing currently filters out already-finished/forfeited races, so its current cohort alone is not historical proof. Use bounded existing join/finish/leave timestamp evidence only where it establishes the full start cohort; otherwise leave all stamp columns null and omit that candidate. `SKIPPED_STALE` and historical rows are not automatically zero. No historical scoring reconstruction or mandatory population backfill.

The late-join path in `globalEventEnrollment.js:190` preserves any existing stamp, including zero; it must not initialize a missing stamp from newly joined races. Timezone reconciliation permits relocation of future unprocessed events, not changing an already processed start snapshot. Never restamp a saved count; changed window/revision invalidates stale uncommitted input. Saved results remain frozen.

The first successful INSERT wins; conflicting POSTs read the existing committed row. Do not overwrite number/ack state on retries. A saved zero result prevents repeat calculation. New data retention uses the existing bounded event/account-retention path, not a new recap cleanup cron. Keep records until the event is no longer eligible so deletion cannot resurrect popups. At most one latest candidate per user; older saved results must not reappear after newer acknowledgment. Event FK/deletion ordering must account for these rows.

Migrated `LEGACY_SAVED` rows retain their original numeric value and acknowledgment evidence. Mark nonpositive migrated rows suppressed; never render a negative or zero result with the new positive-gain copy. Positive saved legacy rows remain frozen, not recalculated. Suppression applies to both Home compatibility responses and the new endpoint.

Select the latest completed daily-2× entitlement for the user first (end time descending, deterministic ID tie-break), before filtering expiry, null count, saved/acknowledged/suppressed state. If that selected event cannot display, return none; never fall back to an older event. Preserve this selection evidence until all older candidates have expired. Use a bounded indexed user/end-time LIMIT 1 lookup checked by EXPLAIN. Saved read requires no raw sample query. POST uses fixed-count metadata reads, one INSERT/conflict read, and multiplication. No reads scale with race history, powerup history, or another user's steps. Reuse existing API admission/rate limits; do not create a new queue for this feature.

Bump the saved-recap cache key namespace on deployment so old zero/negative entries and cached empty responses cannot survive the policy change. Invalidate both Home reader paths on save, suppression, acknowledgment, supersession and retention using existing cache infrastructure, retaining Postgres fallback when Redis is unavailable. Recheck expiry and session/route guards immediately before display, including a result delayed past midnight; no new runtime flag.

## 6. Complete cleanup inventory

Delete recap-only backend files after replacement callers land:

- `src/modules/steps/jobs/globalEventSummary.js`.
- Under `src/modules/steps/services/`: `globalEventSummaryCapture.js`, `globalEventSummaryLifecycle.js`, `durableGlobalEventCapture.js`, `durableCaptureCleanup.js`, `durableCaptureScoringPlan.js`, `durableCaptureStageScoring.js`, `durableCaptureIntervalProjection.js`, `durableCaptureSnapshot.js`, `durableCaptureFacts.js`, `durablePreparedScoringInputs.js`, `durableScoringMethod.js`, `globalEventCaptureFactCache.js`, `capturedHitchhikeInputs.js`.
- Remove recap imports/exports/startup hooks from `src/index.js` and `src/modules/steps/index.js`, including capacity/test startup variants.
- Remove capture-closure reads/locks/retries, summary receipts/wakes and capture phase from `recordStepSyncV2.js` and legacy step writers. Preserve actual step-source serialization, idempotency, race enqueueing, and corrected step/high-water behavior.
- Remove event-end recap-work creation, recap-only history repair locks, recap-driven race enqueueing, captured recap settlement and readiness from `globalStepEventEntitlement.js`, `raceResolutionQueueV2.js`, `raceExpiry.js`, and `globalEventEnrollment.js` where exclusively recap-related.
- Rewrite `globalStepEventRetention.js`, `globalStepEventObservability.js`, `deleteUserAccount.js`, Home readers/batching/cache helpers, and capability/config registries to remove old work dependencies. Shared event membership must not remain blocked from retention because its obsolete recap state stays PENDING.
- Rewrite `globalEventTimezoneReconciliation.js:233` to use replacement saved-result semantics before the old summary table is dropped.
- Retire recap-only settings, operational switches, prepared-query annotations, telemetry counters, capacity SQL maps, seed fixtures, runnable diagnostics/benchmarks and job-run fences. Keep frozen response/config compatibility fields as small constant/adapter logic when needed by old binaries; no retained runtime toggle or dormant old engine.

Database retirement, explicit names/signatures resolved in implementation migration manifest:

- Drop source triggers `durable_capture_steps_source`, `durable_capture_samples_source` before their dependent objects.
- Drop `global_event_summary_impact_vector_fence` / `fence_global_event_summary_impact_vector()`; owner/terminal pin-release triggers and functions `durable_capture_deleted_owner`, `durable_capture_terminal_pin_release`, `durable_capture_release_deleted_owner()`, `queue_durable_capture_pin_release()`.
- Drop `global_event_summary_work`, `global_event_capture_artifacts`, `durable_global_event_capture_requests`, and old `global_event_user_summaries` after copying saved rows to `event_recaps` with original IDs, numbers, expiry and acknowledgment. No recalculation of historical saved rows; duplicate event/user copy is verified before removal.
- Drop recap-only `durable_capture_` tables: `fact_heads`, `fact_journal`, `fact_roots`, `fact_pins`, `fact_identities`, `fact_pages`, `prepared_inputs`, `method_progress`, `interval_projections`, `score_progress`, `score_plans`, `score_points`, `score_transfers`, `score_owners`, `pin_releases`, `compaction_schedule`, `root_sweep`.
- Drop all overloaded signatures of recap functions: `durable_capture_fact_days`, `durable_capture_journal_source`, `durable_capture_pin_roots`, `durable_capture_prepare_root`, `durable_capture_materialize_root`, `durable_capture_append_fact_page`, `durable_capture_evict_roots`, `durable_capture_evict_roots_internal`, `durable_capture_compact`, `durable_capture_compact_internal`, `durable_capture_compact_if_due`; add any newer production descendants to the manifest.
- Rewrite shared `global_event_recovery_*` functions and triggers to remove SUMMARY_V1/SUMMARY_V2 sources, completion hooks, seeding and revalidation; delete only those candidate kinds. Keep ENTITLEMENT_EVENT recovery and its shared storage.
- Remove obsolete counterfactual-attribution columns/indexes/Prisma relations from event/impact records only after every scoring/fingerprint/notification reader is rewritten to membership-only semantics. Remove only `job_runs` keys with the exact retired summary prefix in bounded audited batches.

Preserve explicitly:

- `global_event_race_impacts` membership responsibility, event/entitlement creation/start/end, actual multiplier application, notification eligibility and delivery. It is not a recap-only table.
- Ordinary race-resolution queues, score fingerprints/fences, display proofs and artifacts, active-effect impact popups, `hitchhike_attribution_captures`, step samples, sample retention, `user_scoring_input_versions`, and accepted step-sync records.
- General wake coordinator, Redis cache/invalidation/pubsub, Home batching, unrelated race/friend/tournament “summary” helpers.
- Applied migration history and historical evidence. Label old documents superseded and remove runnable operational instructions from active runbooks; do not edit migration checksums or erase provenance.

Frontend cleanup:

- Remove `_ActiveGlobalEventSummaryWork`, summary poll timers/tokens/reset hooks, summary receipt handling, `_refetchHomeForCreatedGlobalEventSummary`, summary-only delayed Home reloads, and summary fields from `_StepPersistOutcome` in `main_shell.dart`.
- Remove `GlobalEventSummaryWorkState`, status/receipt models and parsers in `step_sync_v2_result.dart`, and old status-fetch API in `backend_api_service.dart`.
- Keep ordinary race-resolution polling, stale Home response guards, saved recap presentation/acknowledgment, auth guards, and result → recap → invite overlay ordering. Rename internal saved-recap types where useful without changing legacy JSON fields.
- Replace old mixed-zero/loss copy with the selected positive recap copy; no popup for zero. Reuse existing dialog layout/title/button. No new screen, spinner, or persistent banner.

## 7. Implementation and migration sequence

1. Freeze an isolated baseline matching current production runtime and enumerate code + catalog SQL dependencies. Record every removal/rewrite/preservation with reason. No broad name-based deletion or `DROP ... CASCADE`.
2. Write failing integration/widget tests first. Backend pins the exact API and capability contracts; frontend work then proceeds against that contract. Game analyst confirms no scoring/economy change.
3. Prepare additive migration A (`event_recaps`, entitlement scalar/indexes). Build replacement runtime with the simple input adapters and zero old worker producers/consumers. A remains compatible with the currently running backend.
4. On a separately authorized production deployment, apply A; stop/drain all old HTTP/cron/resolution writers through the existing guarded deployment procedure; preserve two HTTP workers and keep staging stopped. No blind rolling overlap with the retirement migration.
5. With old writers proven absent and before allowing new recap traffic, migrate saved recap rows, replace shared recovery SQL and detach all recap triggers. Disable all old runtime producers/consumers permanently in the replacement code. Keep only inert old database objects during the expand/contract verification interval: no application reads/writes or attached journaling triggers. Passive parent-deletion cascades are the sole exception, preserving account deletion and personal-data cleanup; convert only the ten audited retired-storage FKs, including scratch-owner descendants, and remove already-detached scratch owners in bounded pages. Use bounded lock timeouts; migration failure keeps traffic held until a compatible state is established.
6. Start replacement runtime, verify both old/new HTTP paths, actual event scoring, notification delivery, and zero old recap work. Upload/release the matching iOS and Android clients only after separately authorized build/release work.
7. At least one week after the replacement backend deployment, in a separate authorized release, apply migration B to drop every inventoried retired function/table/column. Audit all FKs/views/functions through catalogs, including SQL-string dependencies catalogs may not fully track; no broad CASCADE. Backend owner must track this explicit removal milestone; the feature's cleanup is not complete until B is verified. No app-version adoption threshold is needed because compatibility endpoints already use the replacement.
8. Document the rollback boundary: even before B, the old runtime must not be restarted against detached triggers/new-only saved results without a coordinated recovery plan; after B, an old-code-only rollback is impossible. Prepare a compatible replacement rollback artifact. Snapshot/backup and restore rehearsal are prerequisites to separately authorizing B.

No old worker is kept “temporarily” as a rollback flag. Minimal legacy endpoints and saved-result wire fields are permanent compatibility adapters, not retained recap infrastructure.

## 8. Tests and measurable acceptance

Backend real HTTP + dedicated local `_test` Postgres, tests before business logic:

- Event ended/not-ended, correct UTC window/revision/ownership, event-start race scalar, later joins/leaves/finishes, timezone change, overflow/invalid raw count.
- 1,000 raw steps × three races = 3,000; different powerups and scores cannot affect this number; unchanged actual scoring/coin/public race goldens.
- First POST, retry, concurrent devices (including across midnight), acknowledged/expired replay, suppressed zero, no candidate, latest-only behavior, midnight expiry, DST and differing device/entitlement timezones.
- Old sync adapters with contiguous coverage vs internal gaps, maximum-end-only evidence, sample limit, daily-only/missing samples; old Home/ack/retired-status contracts; immutable idempotency-response replay; new client capability on older server.
- Full fresh migration chain and upgrade from populated old schema; preserve saved IDs/acknowledgments; event notification recovery works after summary branches disappear; account/event retention has no dangling functions or permanently blocked rows.
- Step insert/update/delete after retirement produces zero capture journal/head writes; old recap function/table/trigger/scheduler references absent outside explicit historical/compatibility allowlists. Exercise actual SQL mutation paths, not only source-text checks.
- Ordinary step sync, race resolution, final settlement and notifications with no summary scheduler installed all complete correctly. No summary-driven FULL race jobs, status polling, root compaction or capture work remains.

Frontend real MainShell tests:

- Successful sync → exact-window aggregate → finalize → popup; failure/null defers; valid zero suppresses; no daily/hourly bucket shortcut.
- Cold/resume/refresh coalescing, account switch/disposal during every await, no popup on first open next day, missing optional fields, older backend 404, acknowledgment failure, offline behavior and existing overlay order.
- Preserve ordinary race-status polling tests; prove zero calls to summary-work status endpoints and no recap polling timers.

Protected test disposition is explicit: old worker-poll assertions in `main_shell_nav_order_test.dart:3280–3710`, old mixed-zero text at :3034, status API assertion in `backend_api_service_sync_v2_test.dart:885`, and backend worker/counterfactual suites describe the feature being retired. Spec approval must include their intentional replacement with the new behavior tests; do not silently weaken them to get green. Retain every still-relevant scoring, durability, notification, ownership and overlay assertion. Provide a test-by-test disposition manifest before removing entire suites.

Performance proof: run identical synthetic user/event arrivals on unchanged baseline and replacement, including all downstream work to completion, through real HTTP and workers. Compare repeated runs with identical topology and data. Report DB CPU, commands, writes/WAL, completed recaps, score completion latency and backlog. Required structural results: zero idle recap polling, zero old capture journaling, zero recap worker jobs, zero recap-induced scoring jobs; one bounded caller-only calculation per event/user, no repeat calculation after saved result. Reject a result that merely defers work or changes actual scores. Whole-host production CPU benefit is verified separately after deployment; no 100% prediction.

Run clean Flutter analysis, relevant Flutter tests, backend integrations (never production; never bare npm test), and required code-reviewer review. Both mobile platforms are in scope. No runtime flag, new infrastructure service, or production change in the planning task.

## 9. Revision log

- Gap pass 1: expanded cleanup beyond cron deletion to source journaling triggers, shared recovery branches, retention/account deletion, capacity tools and old persisted receipt replay; protected event membership and real scoring.
- Gap pass 2: added exact event-window OS aggregate because current sync uploads today/hourly data; separated null/zero, added immutable first-result behavior and latest-only selection, specified legacy coverage adapter, and made old-test replacement and destructive migration boundary explicit.
- User interview: same-event-calendar-day only, expiry at entitlement-local midnight; race count fixed at event start. No seven-day history or next-day recap.
- Formula review: simple recap has no economic effect; migrated nonpositive counterfactual results are explicitly suppressed while their original numeric evidence is retained.
- UI review: checklist below; real Home fixtures and delayed-result route/tutorial guards are required implementation steps.
- Architect review: tightened legacy coverage to contiguous accepted intervals, made start-count stamps and late-join behavior explicit, covered all capability-header paths and recap-cache invalidations, prevented older-candidate resurrection, and separated inert schema retirement from immediate worker/trigger removal with a minimum one-week expand/contract interval.
- Final gap pass and architect reread: all required changes addressed; added timezone-reconciliation cleanup, explicit legacy sample-write entry points, replay/expiry precedence and midnight concurrency coverage. Planning complete; implementation and tests have not run.
- Implementation review: retired-storage RESTRICT/SET NULL relationships would block deletion or leave scratch payload after GC removal. Architect approved scoped integrity cascades and required populated deletion verification. Nullable legacy expiry is preserved and suppressed, never invented; only new simple results require nonnull expiry.

## 10. Manual UI-placement test plan

**Manual UI-Placement Test Plan — Simple Event Recap**

*Elements under test:* Existing Home recap body changes; dialog position, title, and Continue button stay in place. No additional popup is added.

*Checklist* — run on iOS and Android with prepared eligible accounts.

1. **Home:** Cold-open, then separately resume after a completed event. Verify one centered recap, body below title, Continue below body; no duplicate or loading popup.
2. **Popup order:** Open Home with race results, recap, and invites pending. Verify results → recap → invites, with no stacking.
3. **Other routes/auth:** Resume on Races, open race detail, then return Home; separately sign out with a pending recap. Verify it appears only on Home, never over another screen or sign-in.
4. **No recap:** Open Home with a zero-result account, then an eligible account offline. Verify no empty recap or new loading/error popup.
5. **Large text:** Enlarge system text on a small device and open the recap. Verify all content fits and Continue remains visible and reachable.
6. **Tutorial mirrors:** Settings → tutorial replay → Home preview; fresh account → onboarding → demo race. Verify no recap covers previews, spotlights, or coach overlays; no duplicate appears upon returning Home.

*Surfaces confirmed unaffected:* Tutorial `HomeTab` and demo/tutorial `RaceDetailScreen` do not contain the `MainShell` recap. Existing event banners and tutorial anchors retain their placement.

*Risks found while planning:* Test the recap on real Home accounts because tutorial fixtures cannot render it. Delayed responses must not place it over another route or tutorial.
