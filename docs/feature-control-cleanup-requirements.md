# Runtime feature-control cleanup — requirements

Status: **OWNER APPROVED — backend-first implementation in progress**

Authoritative production snapshot: 2026-08-20 04:23 UTC, backend revision
`2ba5dfb`. This plan preserves the owner's flag-by-flag decisions and supersedes
the earlier idea of adding a broader admin feature-flag page.

## 1. Summary and user story

The backend accumulated database settings and environment kill switches for
rollouts that are now established product behavior. The desired end state is:

- established behavior is ordinary code, not a remotely reversible branch;
- retired behavior cannot come back because a row or environment variable is
  missing;
- frozen App Store and Play Store clients keep receiving every compatibility
  field and endpoint shape they require;
- capability tokens remain compatibility gates and are not mistaken for
  runtime feature flags;
- product rollout flags are removed, while a small explicit operational-safety
  set remains for destructive jobs, whole-user fan-outs, durable queues,
  privacy response, sampled capacity metrics, the Home service banner, and
  Prisma query-event diagnostics outside production;
- dependency-closure controls remain temporarily because their 100% rollout is
  too new to graduate safely; and
- app-funded prizes remain, but issuance is retuned and a global funded-race
  exposure limit is enforced before the funded-pool switch is retired.

User story: as the operator, I want one production behavior per established
feature so stale kill switches cannot silently reactivate retired code or leave
the live system in an untested combination.

## 2. Scope and non-goals

### In scope

- Backend DB-backed settings in `src/shared/config/appSettings.js`, backend
  environment flags, the frontend's persisted copies of server feature flags,
  and the small admin settings UI that exposes retired controls.
- Permanent behavior decisions in §3.
- Compatibility serializers and no-op/tombstone endpoints required by frozen
  clients.
- Tests-first conversion from two-path flag tests to public-path permanent-
  behavior tests.
- Removal of retired AppSetting rows and stale production environment entries
  only after all production workers run code that no longer reads them.
- The funded-race exposure limit and issuance retune in §5.
- One-time Imposter inventory retirement and compensation in §6.

### Non-goals

- Removing client capability tokens such as `inbox_v1`, `race_preview`, or the
  old-version gate for five-minute samples. Those describe what a frozen binary
  can render and remain necessary after rollout flags disappear.
- Dropping historical race, tournament, buy-in, powerup, onboarding, or impact
  columns/enums in this release. Row-stamped history and frozen clients still
  need defensive reads.
- Replacing the Home service banner with a feature-flag admin page.
- Enabling Prisma query events in production.
- Deleting dependency-closure controls before the graduation gate in §8.
- Overwriting the existing uncommitted resolved-impact v2 changeset. The work
  in `docs/active-impact-event-materialization-cleanup-requirements.md` lands as
  its own reviewed prerequisite and this cleanup rebases around it.

## 3. Normative decision ledger

“Delete control” means remove the runtime branch and mutability, not blindly
remove a response key. Compatibility fields are listed in §4.

### 3.1 Permanently retain operational controls

| Control | Permanent rule |
| --- | --- |
| `capacityPhaseMetricsV1Enabled` | Keep DB toggle; expensive sampled instrumentation must remain instantly disableable. |
| `homeServiceBannerEnabled` + `homeServiceBannerMessage` | Keep DB operational messaging controls and existing admin UI. |
| `PRISMA_QUERY_EVENTS_ENABLED` | Keep for local/test/staging query-count tools. Production startup must force it off or fail fast if it is `true`. |
| `PLACEMENT_BASELINE_WRITE_CONCURRENCY` | Keep as a bounded numeric performance parameter, default 4, range 1–8. It is configuration, not a product flag. |
| `STEP_SYNC_PUSH_CONCURRENCY` | Keep as a bounded numeric performance parameter, default 8, range 1–16. |
| `racePreviewEnabled` | Keep an immediate server-side privacy/read-cost cutoff. A frozen `race_preview` capability cannot be withdrawn if financial redaction is found incomplete. |

Existing job/worker kill switches are consolidated, not deleted without an
equivalent brake. Replacements are server-only and absent from product admin UI:

| Consolidated operational control | Owns |
| --- | --- |
| `OPS_USER_FANOUTS_DISABLED` | live placement, daily mover, daily reward, step milestone, high-multiplier, race-ending, and inbox-delivery fan-outs |
| `OPS_DESTRUCTIVE_CLEANUPS_DISABLED` | activation-event, admin-metrics, notification, inbox-expiry, step-sample-retention, and resolution post-task cleanup jobs |
| `OPS_RACE_RESOLUTION_INTAKE_DISABLED` | sync-v2 intake only; when disabled it returns the existing pre-write 503 so capable clients downgrade |
| `OPS_RACE_RESOLUTION_WORKER_DISABLED` | core durable resolution claims; queued rows remain queued and leases drain safely |
| `OPS_RACE_RESOLUTION_POST_TASK_WORKER_DISABLED` | post-task claims independently of core scoring claims |
| `OPS_AD_VALUE_ISSUANCE_DISABLED` | one global emergency brake for rewarded-ad coin, spin, reroll/item, and payout-double value claims; SSV, allowlists, idempotency, and provider limits remain mandatory |

Polarity-normalized compatibility mappings are explicit:

- user fan-outs stop when `OPS_USER_FANOUTS_DISABLED === "true"` or any owned
  legacy negative switch equals `"true"`;
- destructive cleanups stop when `OPS_DESTRUCTIVE_CLEANUPS_DISABLED ===
  "true"` or the corresponding legacy `*_DISABLED` switch equals `"true"`;
- core/post workers stop when their new switch is true or respectively
  `ASYNC_RACE_RESOLUTION_WORKER_DISABLED` /
  `RACE_RESOLUTION_POST_TASK_WORKER_DISABLED` equals `"true"`;
- during the compatibility deploy, sync-v2 intake stops when either
  `OPS_RACE_RESOLUTION_INTAKE_DISABLED === "true"` or
  `ASYNC_RACE_RESOLUTION_DISABLED === "true"`. Neither switch affects frozen
  `/steps` or `/steps/samples`, which always persist uploads and retain inline
  freshness. Legacy enqueue/reconciliation remains governed solely by
  `raceQueueV2ClaimingDisabled` plus `inlineRaceResolutionFallback` until that
  reverse-handoff target is separately retired; and
- `OPS_AD_VALUE_ISSUANCE_DISABLED === "true"` is a master brake. During the
  compatibility deploy, old ad switches retain their own exact polarity:
  extra-spin/get-coins are disabled only by literal `"false"`; box reroll and
  payout prepare/claim/reconcile are enabled only by literal `"true"`.

Old names leave only after the new controls are proven and the rollback window
expires. Rollout percentages graduate, but consolidated safety brakes remain.

### 3.2 Graduate established production behavior

After a minimum 72-hour uninterrupted production soak at the chosen value and
the family-specific checks in §9, bake these live paths into code and delete
their runtime controls.

**Request projection and API contracts**

- `raceProgressLeanProjectionV1Enabled`
- `legacyUploaderStepSamplePrefetchV1Enabled`
- `raceMessageLeanAccessV1Enabled`
- `raceListSqlSummaryV1Enabled`
- `apiRaceListCompactV1Enabled`
- `apiRaceBootstrapCompactV1Enabled`
- `homeRaceCardLeanLiveV1Enabled`
- `homeRaceCardParallelOptionalV1Enabled`
- `homeRaceCardSnapshotReuseV1Enabled`
- `publicRaceCountSqlV1Enabled`
- `apiRaceMessageConditionalV1Enabled`
- `apiRacePowerupTargetContextV1Enabled`
- `racePowerupLeanUseContextV1Enabled`
- `apiLeaderboardCompactV1Enabled`
- `apiRaceBootstrapV1Enabled`
- `apiRaceProgressCompactV1Enabled`
- `apiRaceMessageStreamsV1Enabled`
- `apiFriendsSummaryV1Enabled`
- `apiAuthShellV1Enabled`
- `apiHomeShellV1Enabled`
- `apiGetCoinsV1Enabled`
- `apiPublicRaceBrowserV1Enabled`
- `apiRankedV2CompactV1Enabled`
- `apiProfileStatsV1Enabled`
- `apiImpactNoticesEnabled`
- `apiImpactSummariesEnabled`
- `apiReviewPromptEnabled`
- `apiInboxV1Enabled`
- `apiShopBootstrapV1Enabled`
- `apiStaticEtagsV1Enabled`
- `apiTournamentDetailV1Enabled`
- `apiRaceChatWatermarkCacheV1Enabled`

The endpoint remains available only to a carrying client capability where a
capability already exists. Old clients keep their legacy endpoint path. The
setting lookup disappears.

**Redis and derived-data behavior**

- `redisCacheCatalogsEnabled`
- `redisCacheMessagesEnabled`
- `redisStandingsEnabled`
- `redisCacheUserBitsEnabled`
- `redisCacheAuthMeEnabled`
- `redisCacheDiscardCapEnabled`
- `redisPresentationGenerationGuardEnabled`
- `redisCacheLeaderboardEnabled`
- `redisCacheFriendsEnabled`
- `redisFriendSearchRateLimitEnabled`
- `redisCacheHomeActiveGlobalEventEnabled`
- `redisCacheHomeImpactSummaryEnabled`
- `redisCacheHomeInboxUnreadEnabled`

Redis remains fail-open to the current PostgreSQL path. Removing a rollout
switch must not turn Redis availability into a correctness dependency.

**Race-resolution and worker behavior**

- `raceResolutionDisplayArtifactReuseV1Enabled`
- `raceResolutionReasonAwareV1Enabled`
- `raceResolutionBurstCoalescingV1Enabled`
- `raceResolutionQueuedGenerationMergeV1Enabled`
- `raceResolutionBulkWriteV1Enabled`
- `raceResolutionPostTasksV1Enabled`
- `raceResolutionNudgeBatchV1Enabled`
- `raceResolutionAdaptiveDrainV1Enabled`
- `raceResolutionPostTaskAdaptiveDrainV1Enabled`
- `raceResolutionPendingImpactOnlyV1Enabled`
- `raceResolutionNarrowDefenseQueryV1Enabled`
- `raceResolutionActiveImpactBulkPersistV1Enabled`, only if still applicable
  after resolved-impact v2 lands
- `PLACEMENT_DISTRIBUTED_CLAIM_ENABLED`
- `PLACEMENT_LEAN_BASELINE_WRITES_ENABLED`
- `PLACEMENT_INERT_PUSH_SUPPRESSION_ENABLED`
- `STEP_SYNC_BULK_ENABLED`
- `APNS_SESSION_REUSE_ENABLED`
- `SYNC_V2_INLINE_UPLOADER_RECONCILIATION=false`: permanently return the
  existing `DEFERRED` shape from sync v2 and let the durable race-keyed worker
  reconcile. Legacy `/steps` and `/steps/samples` retain inline uploader
  reconciliation for frozen-client box freshness.

The queue handoff safety levers `raceQueueV2ClaimingDisabled` and
`inlineRaceResolutionFallback` are not ordinary product flags. Remove them only
in a later deploy after the old queue implementation and all downgrade targets
that need reverse handoff are gone; until then classify them as deployment
protocol controls and hide them from product/admin flag counts.

**Established product behavior**

- team races permanently available; delete `teamRacesEnabled` as a mutable
  setting;
- tournaments permanently available; delete `tournamentsEnabled`;
- quick-create permanently available; delete `quickCreateRaceCtaEnabled`;
- custom race windows permanently available; delete
  `customRaceWindowEnabled`;
- discoverable-identity enrollment, invite decision gate, quick-share automatic
  friendship, seeded race buckets, banner ads, dual box banners,
  seeded geometric payouts, and seeded inactivity pruning retain their live
  production behavior and lose their runtime settings;
- rewarded race-payout doubling remains at 100%; delete
  `racePayoutDoubleRolloutPercent` while retaining server eligibility,
  idempotency, prepare/claim/reconcile, and client ad-unit capability checks;
- payout rounding version 1 is stamped on every new eligible competition;
  historical rows keep their stamped version;
- leave/forfeit is stamped available on every new ordinary race; historical
  rows keep their stamped value;
- five-minute step sampling is hardcoded for compatible clients while builds
  below 1.7.1 retain the existing hourly compatibility gate;
- the v3 first-run onboarding is the sole current onboarding path and its
  tutorial is mandatory, while the existing local three-abandon escape circuit
  remains; V1/V2 creation branches and their settings are retired;
- old onboarding invite-code UI is removed and its flag is retired;
- referral exact-IP attribution remains; network-prefix attribution and
  `REFERRAL_IP_FALLBACK_NET_ENABLED` are deleted permanently.
- local-time global step events, their retention worker, and the Home active-
  event cache retain the production behavior selected on 2026-08-19. Because
  that rollout is not yet three days old, graduate these controls only after the
  same minimum 72-hour soak and entitlement/cleanup checks as other recent
  rollouts;
- admin metrics v2 dashboard and telemetry retain their production behavior.
  Graduate their two product-rollout settings after a 72-hour soak, while the
  independently retained `capacityPhaseMetricsV1Enabled` continues to control
  expensive capacity instrumentation.

### 3.2a Environment-control ledger

For environment controls not otherwise called out, “permanent” means the exact
production behavior observed at 04:23 UTC is baked into code. Positive flags
that were unset stay unavailable; negative `*_DISABLED` flags that were unset
stay enabled. Numeric tuning controls listed in §3.1 remain configurable.

| Permanent behavior | Retired environment controls |
| --- | --- |
| Cleanup/retention jobs run behind the consolidated destructive-job brake | `ACTIVATION_EVENT_CLEANUP_DISABLED`, `ADMIN_METRICS_V2_CLEANUP_DISABLED`, `NOTIFICATION_CLEANUP_DISABLED`, `STEP_SAMPLE_RETENTION_DISABLED`, `RACE_RESOLUTION_POST_TASK_CLEANUP_DISABLED`, `INBOX_EXPIRY_DISABLED` |
| Core async workers/fan-outs run behind consolidated brakes | `ASYNC_RACE_RESOLUTION_DISABLED`, `ASYNC_RACE_RESOLUTION_WORKER_DISABLED`, `DAILY_MOVER_DISABLED`, `INBOX_DELIVERY_DISABLED`, `LIVE_PLACEMENT_DISABLED`, `RACE_RESOLUTION_POST_TASK_WORKER_DISABLED` |
| Other established scheduled jobs remain live | `GLOBAL_EVENT_SUMMARY_DISABLED`, `LOCAL_GLOBAL_STEP_EVENTS_DISABLED`, `PRIVATE_RACE_AUTOSTART_DISABLED`, `RACE_POLICY_AUTOSTART_DISABLED`, `RACE_SCORING_INPUT_BASELINE_DISABLED` |
| Existing notifications remain live behind the fan-out brake | `DAILY_REWARD_REMINDERS_DISABLED=false`; `HIGH_MULTIPLIER_PUSH_DISABLED` and `RACE_ENDING_REMINDER_DISABLED=false` retain live behavior; milestone reminders follow §3.3 and then join the consolidated fan-out brake |
| Box reroll remains available | `ADS_BOX_REROLL_ENABLED=true` |
| Server-side extra-spin and get-coins ad paths remain available behind the global ad-value brake | `ADS_EXTRA_SPIN_ENABLED` and `ADS_COIN_REWARD_ENABLED` are default-on (`!== "false"`) and were unset in production; bake the live-on behavior. Client ad-unit/capability gates still determine whether a placement is renderable. |
| Race payout double remains available at 100% behind the global ad-value brake | `ADS_RACE_PAYOUT_DOUBLE_PREPARE_ENABLED`, `ADS_RACE_PAYOUT_DOUBLE_CLAIM_ENABLED`, `RACE_PAYOUT_DOUBLE_RECONCILE_ENABLED`; retain the hard 100/provider/24h cap |
| Rainstorm multiplicative scoring remains live | `RAINSTORM_MULTIPLICATIVE_ENABLED=true` |
| Bulk step-sync push, APNs reuse, and placement optimizations remain live | the five positive performance flags listed in §3.2 |
| Sync v2 permanently defers uploader reconciliation | `SYNC_V2_INLINE_UPLOADER_RECONCILIATION=false` |
| Character/Zoomies/Imposter/network-referral behavior follows the explicit retirement rules | `CHARACTER_POWERS_ENABLED`, `TURTLE_SHELL_DISABLED`, `ZOOMIES_PUSH_DISABLED`, `IMPOSTER_ENABLED`, `REFERRAL_IP_FALLBACK_NET_ENABLED` |

Before implementation, a structural inventory test must enumerate every
boolean environment read in `src/` and fail if a name is neither in this
retirement ledger nor the retained-control allowlist. This prevents a missed
negative-polarity switch from silently changing behavior.

Generate `docs/runtime-control-disposition.yaml` from the final post-resolved-
impact codebase. It contains every `KNOWN_FLAGS` key, numeric/string setting,
boolean environment read, admin exposure, and compatibility response field,
with disposition, permanent value, polarity/default, rollout-evidence timestamp,
deploy family, rollback value, and compatibility consumers. CI regenerates and
diffs it and fails on missing or duplicate controls. This manifest—not prose
counts—is the authoritative completion ledger.

### 3.3 Launch already-carried behavior, then graduate it

These are present in shipped clients or are server-only, but were dark in the
04:23 UTC production snapshot. Enable them first, verify their acceptance
criteria, then make them permanent and delete the controls in a later deploy:

| Behavior | Required launch rule |
| --- | --- |
| Accessory compatibility enforcement | Clean/backfill incompatible equipped loadouts, then enforce conflicts permanently. Preserve character slot/assets. |
| Open-user race discovery | Serve permanently to capable builds. Frozen builds ignore the additive field and do not gain the UI. |
| One-time setup invite prompt | Serve permanently to eligible capable builds. |
| Home invite modal | Serve permanently to capable builds; old clients retain inline invite behavior. |
| Seeded inactivity auto-enroll-off | Run only inside the already-live inactivity prune hooks; pruned and boxless users stop future auto-enrollment. |
| Step milestone reminders | Launch the 7 PM local unclaimed-milestone reminder, validate delivery and opt-out behavior, then delete `STEP_MILESTONE_REMINDERS_DISABLED`. |
| Resolved-impact events v2 | Land the separately reviewed v2 changeset, deploy dark, validate old clients plus performance/storage, enable, then graduate after soak. |

### 3.4 Permanently remove retired behavior

- Character race abilities are already disabled/removed. Delete stale
  `CHARACTER_POWERS_ENABLED`, `TURTLE_SHELL_DISABLED`, and
  `ZOOMIES_PUSH_DISABLED` residue; keep the hardcoded false compatibility field
  and all character cosmetics/assets. Remove the stale Capybara shop sentence
  that promises daily bonus steps.
- Retire Imposter from catalog, purchase, daily-spin eligibility, redeem, use,
  and illusion reads before deleting `IMPOSTER_ENABLED`; details are in §6.
- Remove the legacy completed-impact popup and
  `apiCompletedImpactPopupEnabled`. Coordinate with the active resolved-impact
  changeset; do not remove private completed Activity.
- Remove the v1 active-impact scanner/work pipeline and its flag according to
  `active-impact-event-materialization-cleanup-requirements.md`.
- Remove dependency-closure shadow mode and
  `raceResolutionDependencyClosureShadowV1Enabled`.
- Remove the unused post-task fast-handoff optimization and
  `raceResolutionPostTaskFastHandoffV1Enabled`; retain the tested ordinary
  handoff.
- Remove no-op input suppression and
  `raceResolutionNoopInputSuppressionV1Enabled`; retain full resolution when
  correctness is uncertain and remove supporting state only with compatible
  migrations.
- Remove buy-in editing and `buyInEditEnabled` after §7 proves no live hold
  needs reconciliation. Keep legacy settlement/refund serialization.
- Remove environment kill switches for jobs and established behavior by baking
  the currently live behavior. For negative-polarity flags, code is changed
  first; deleting an environment line must never be allowed to select a
  default-on retired path.

## 4. API and frozen-client compatibility contract

No existing endpoint, request parameter, or response field becomes required,
removed, renamed, or repurposed in this cleanup.

### 4.1 `/auth/me` and settings compatibility envelope

The backend continues returning a compatibility `featureFlags` object even
when its values are no longer mutable. At minimum, shipped clients continue to
receive:

```json
{
  "featureFlags": {
    "characterPowersEnabled": false,
    "teamRacesEnabled": true,
    "customRaceWindowEnabled": true,
    "onboardingV2Enabled": true,
    "onboardingV3Enabled": true,
    "onboardingInviteCodeEnabled": false,
    "openUserRaceDiscoveryEnabled": true,
    "quickCreateRaceCtaEnabled": true,
    "setupInviteCodePromptEnabled": true,
    "homeInviteModalEnabled": true,
    "tutorialMandatoryEnabled": true,
    "stepSampleBucketMinutes": 5
  }
}
```

Fields used by shipped builds remain at their compatibility value. A value can
leave only after telemetry proves no supported/in-the-wild build reads it.
Every behavior in the downgrade table below retains its fail-closed field,
capability, or definite-404 gate in new frontend code. Only unrelated fields
proven locally safe against an older backend may lose client branching, and all
server payload parsing remains defensive.

`onboardingV2Enabled` remains true in the compatibility envelope because frozen
pre-v3 binaries ignore the v3 key and need their best supported v2 flow. New
code selects v3 first; only new binaries remove local V1/V2 implementation.

New app → old backend behavior remains explicit and fail-safe:

| Behavior | Missing/false field from an older backend |
| --- | --- |
| custom windows | hide CUSTOM and never send scheduled-end fields |
| quick-create | use the existing full-create fallback |
| open-race discovery | hide additive Home rows |
| setup prompt / Home invite modal | keep legacy onboarding/invite behavior without calling absent contracts |
| onboarding v3 | use the best supported v2/v1 flow |
| mandatory tutorial | remain skippable; never infer a hard block |
| five-minute samples | use the existing version-aware 60-minute fallback |
| compact/additive APIs | capability/404 downgrade to the legacy endpoint |

Frontend compatibility consumers therefore remain even when the new backend
value is constant.

### 4.2 Retired endpoints and actions

- Imposter direct purchase/redeem/use returns a stable retired response (HTTP
  410 with `{ "error": "This powerup has been retired.", "code":
  "POWERUP_RETIRED", "powerupType": "IMPOSTER" }`) and
  consumes no inventory or coins. Catalog and inventory omit it.
- Old character-ability action routes, if any shipped client can still call
  them, return a stable disabled/no-op response and never mutate scoring.
- Removed onboarding mutation endpoints remain safe no-ops where old clients
  still call them.
- Legacy buy-in fields and buy-in races remain readable and settle/refund from
  row-stamped state. New create/edit requests may still send buy-in parameters;
  the backend accepts and ignores them for new funded competitions, as it does
  today.
- Capability-gated compact/additive API endpoints stay additive. A frozen
  client without the capability keeps using its legacy endpoint; a carrying
  client no longer depends on a DB rollout row.

### 4.3 New funded-exposure contract

Join, accept, quick-create, public-create, share-link join, auto-enrollment, and
tournament enrollment all use one server-side exposure reservation service.
If adding a funded membership would exceed the global limit, return:

```json
{
  "error": "Finish or leave another funded race before joining this one.",
  "code": "FUNDED_EXPOSURE_LIMIT",
  "limitCoins": 300,
  "dailyRateLimitCoins": 40,
  "currentCoins": 280,
  "requestedCoins": 40,
  "currentDailyRateCoins": 34,
  "requestedDailyRateCoins": 7
}
```

HTTP status is 409 through the standard `ConflictError`/`AppError` middleware
shape, with numeric values in validated metadata. Old clients already render server errors generically and
remain safe. New clients map this code to concise explanatory copy. A race
creator is subject to the same rule as a joiner. Ordinary non-funded legacy
races and featured tournaments with their own champion prize are excluded.

The same status/body contract applies to `POST /races` (full and quick-create),
`POST /races/:raceId/join`, `POST /races/share/:token/join`,
`PUT /races/:raceId/respond`, seeded assignment/auto-enrollment commands, and
the tournament `POST /`, `POST /share/:token/join`, `POST /:id/join`, and
`PUT /:id/respond` routes under `/tournaments`. Imposter's retired contract
applies to `POST /shop/powerups/purchase`,
`POST /races/:raceId/powerups/redeem`, and
`POST /races/:raceId/powerups/:powerupId/use`; catalog, daily-reward selection,
and ad unlock omit it rather than returning it as a possible reward.

## 5. Funded-race exposure cap and issuance retune

### 5.1 Goals

- Bound the expected payout available from joining many free races while
  reusing the same walking effort.
- Reduce funded-pool issuance materially before the switch is removed.
- Keep app-funded entry free and keep projected/settled pools compatible.
- Apply one rule across every race creation/join source, including quick,
  public, share link, invitation, seeded auto-enrollment, and user tournaments.

### 5.2 Normative economy values

- Change `PRIZE_COIN_UNIT` from 20 to **10** for newly created competitions.
- Stamp the version-2 ordinary-race pool maximum at **8,000** and the user-
  created tournament champion maximum at **500**. Featured fixed champion
  prizes remain unchanged.
- Set global concurrent symmetric funded exposure to **300 coins per user**.
- Add a concurrent expected-issuance-rate limit of **40 coins per priced day**.
- Raw exposure for a membership is its uncapped symmetric expected value:
  `durationPoints * coinUnit * teamPoolMultiplierBps / 10000`, or stamped user-
  tournament pool divided by bracket size. Rate exposure is raw exposure
  divided by priced duration days. Store both in millicoins and round each
  admission charge up to the next millicoin. They are independent of current participant count, so
  joining cannot lower another member's reservation and races cannot game the
  guard by temporarily having a small field.
- Count `PENDING` and `ACTIVE` accepted memberships. Exclude completed,
  cancelled, declined, left, kicked, and forfeited memberships.
- Existing memberships are grandfathered. A user already above the limit may
  finish/leave them but cannot create or accept another funded membership.
- Add `funded_exposure_guards(user_id text primary key, updated_at)` with a user
  cascade FK. Every funded-membership mutation upserts and locks guard rows in
  ascending `userId` order **before** locking competition rows. If more than one
  competition is touched, lock `(kind, id)` lexically after all user guards.
  Exposure read and participant mutation run in the same transaction; Redis and
  settlement never participate in admission.
- Store `funded_exposure_millicoins integer` and
  `funded_exposure_rate_millicoins_per_day integer` on race and tournament participant
  rows so fractional tournament EV such as 62.5 is exact (`62500`). The
  300-coin limit compares as 300,000 millicoins and the daily-rate limit as
  40,000; API presentation
  rounds upward only for copy. The value is stamped on ACCEPT and retained for
  history. Sum only ACCEPTED memberships in PENDING/ACTIVE funded competitions
  whose participant remains live under that domain's leave/forfeit/elimination
  rules.
- All create, quick-create, public/share join, invite accept/reaccept, seeded
  enrollment/renewal, inactivity transition, leave, kick, forfeit, cancel,
  complete, tournament join/start/elimination/cancel, and account-delete seams
  route through the guard service. Every multi-participant mutation enters the
  race-keyed C0 fence-first lease-token protocol, then locks affected user guard
  rows in ascending user ID order and competition rows in declared order. No
  per-user cross-race bulk transaction, independent participant `createMany`,
  or writer outside C0 is permitted.
- Stamp coin unit, pool/champion maximum, team multiplier, and calculation
  version on each new race/tournament. Reads and settlement use stamped values,
  never the current environment, so a retune cannot change an advertised in-
  flight pool.
- Once validated, remove `fundedPrizePoolsEnabled` and make every new ordinary
  competition funded. Keep `funded_prize` and all legacy paths for history.

These caps **bound** “join every free race”; they cannot eliminate weak
dominance while entry is free and the same steps score in every race. The raw
300 ceiling sits above the fresh unit-10/team-aware p95 exposure of 220 while
blocking the p99/max tail of 603.6/962.5. The 40/day rate cap closes the short-race churn hole that otherwise lets
thirty one-day races produce 300 expected coins/day from reused steps.

The 30-day exact replay in `docs/economy.md` found unit 10 + max 8,000 reduces
funded payouts from 103,900 to 57,550 (-44.6%) before cap effects. Current
sources are 10,953.7/day, sinks 4,619.3/day, net +6,334.4/day; the retune still
leaves roughly +4,700/day before cap effects. Permanent v1 rounding
intentionally subsidizes geometric pools by roughly 10% and remains an explicit
owner decision.

### 5.3 Data model

Use stamped, additive columns on races/tournaments:

- `prize_coin_unit integer null`
- `prize_pool_max_coins integer null`
- `tournament_champion_max_coins integer null`
- `prize_calculation_version integer not null default 1`

Version 1/null reads retain the current live formula/20-unit behavior. Version
2 writes the game-review-approved unit. Add nullable
`funded_exposure_millicoins integer` and
`funded_exposure_rate_millicoins_per_day integer` to participant rows only. The
separate guard table contains only `user_id` and `updated_at`. Backfill live
accepted funded memberships using their immutable competition version; null on
historical inactive rows is safe. All migrations are additive and safe for the
currently deployed backend.

Rolling activation is dual-write first: enforcement remains off while every new
worker stamps both exposure values. Old workers may create null stamps during
the rolling window, so after all workers are new, run a guarded catch-up
backfill and prove zero null stamps among live accepted funded memberships
immediately before activation. During enforcement, encountering a live null
must derive-and-stamp inside the same locked transaction or fail closed; it may
never omit that membership from the sum. Integration coverage includes mixed
old/new workers plus concurrent backfill and activation.

## 6. Imposter retirement and compensation

Production evidence on 2026-08-19 found five global units across four owners,
no HELD units, no live effects, and three USED rows only in completed races.

Required order:

1. Backend tombstones catalog, purchase, spin, redeem, use, and illusion reads
   while the production environment remains `IMPOSTER_ENABLED=false`.
2. Integration tests prove direct/crafted calls return `POWERUP_RETIRED`
   without coins or inventory changing. In particular, redeem must not decrement
   global inventory into a dead race-scoped HELD row.
3. Deploy and verify the tombstone.
4. In one idempotent production transaction, compensate **800 coins total**
   through the only permitted balance seam,
   `awardCoins({ tx, reason: "imposter_retirement", refId })`:
   repay 575 actually paid for outstanding units plus 75 replacement value for
   each of three free units. Use a unique retirement refId per owner/unit so a
   rerun cannot double-pay. Zero the five inventory units atomically.
5. Re-audit for HELD inventory/live effects and verify exact ledger totals.
6. Delete the environment entry in a later restart.

Keep the Postgres enum, copy/icon parsing, and historical rows for compatibility.
Inventory zeroing and compensation ledger/balance writes occur in that same
Postgres transaction. A test reruns the script and proves balances, ledger row
counts, and inventory remain unchanged.

## 7. Legacy buy-in drain gate

The 2026-08-19 snapshot found one pending legacy race with two HELD participants
and 300 coins. Before buy-in editing/reconciliation is deleted, run a read-only
production query proving:

- zero PENDING/ACTIVE race or tournament participant rows with `HELD` buy-ins;
- zero unresolved refund/reconciliation work; and
- all legacy competitions are completed, cancelled, or otherwise settleable
  through immutable row state.

A fresh 2026-08-20 ledger audit proved the exact correction:

- Eight completed pre-funded races contain 40 stale `HELD` markers / 1,155
  nominal coins. Thirty-six rows have exact unrefunded debit ledger entries
  totaling **830 coins**; refund exactly those 830 through the existing
  `race_buy_in_refund` reason/refIds and mark those participants `REFUNDED`.
  Clear the other four uncharged markers to `NONE` with zero coin issuance.
- The pending May lobby has two `HELD` markers / 300 nominal coins but **zero**
  matching debit ledger entries. Cancel/retire that stale lobby and clear the
  markers to `NONE` with no refund. A normal cancel must not mint 300 coins that
  were never debited.

The correction script is idempotent, uses the canonical award/refund seam in
one Postgres transaction, and proves a rerun changes neither balances, ledger,
nor statuses. Never blanket-refund 1,155 or the pending 300 from marker values.
Together with Imposter retirement, approved one-time issuance is **1,630
coins**. After remediation and a zero-live-HELD re-audit, remove edit-time buy-
in mutation while retaining settlement/refund/history code.

## 8. Dependency-closure graduation gate

Production was observed false/0 at 04:01 UTC and true/100 at 04:16 UTC on
2026-08-20. The owner confirmed that the 100% change was intentional. It is
still not a multi-day validated rollout. Keep
`raceResolutionDependencyClosureV1Enabled` and
`raceResolutionDependencyClosureV1Percent` through the first cleanup releases.

Delete them only after all of the following are recorded for at least 72
uninterrupted hours at 100%:

- no rollback or unexplained setting mutation;
- parity tests cover every dependency reason and are green;
- no increase in resolution errors, retries, stale standings, duplicate or
  missing impacts, or settlement mismatches;
- queue lag, resolution duration, database load, memory, and worker restarts
  remain within the documented capacity envelope; and
- a production aggregate proves closure is actually selected for eligible
  work, rather than the flag being nominally on while every plan falls back to
  `FULL`.

After the gate, hardcode dependency-closure planning on, retain correctness
fallback to full resolution for an ineligible/failed plan, and delete only the
rollout controls—not the safe algorithmic fallback.

## 9. Tests-first implementation plan

### 9.1 Backend integration tests written before business changes

1. A compatibility-envelope suite calls real `/auth/me` and asserts permanent
   values for all shipped client fields, including missing/old client-feature
   headers.
2. Each capability API family calls the public HTTP route with and without the
   capability and proves the permanent path plus legacy fallback/404 behavior.
3. Redis suites run with Redis available and unavailable and assert byte-equal
   HTTP responses and PostgreSQL fail-open behavior.
4. Race-resolution parity fixtures run the permanent path and compare persisted
   participant totals, effects, boxes, impacts, jobs, and public responses to
   the pre-cleanup established path.
5. Sync v2 asserts `DEFERRED` without an environment flag; legacy step endpoints
   assert same-request freshness.
6. Product creation suites assert team/tournament/custom/quick/leave/payout-
   rounding permanent behavior and historical stamped behavior.
7. Onboarding HTTP/widget suites assert v3-only creation, mandatory first run,
   the three-abandon escape, no invite-code step, and frozen-client compatibility
   fields.
8. Funded-exposure integration tests exercise every creation/join source against
   a real test Postgres, concurrent boundary joins, leave/forfeit release,
   grandfathered users, tournaments, legacy non-funded rows, and immutable
   versioned settlement.
9. Imposter integration tests exercise catalog, purchase, daily spin, redeem,
   use, and illusion reads through public routes and prove no consumption.
10. Admin/settings/startup tests prove removed keys are rejected and every
    retained DB, env, diagnostic, privacy, queue, fan-out, cleanup, ad-value,
    deployment-protocol, and numeric control in the manifest still works.
    Consolidated env tests cover unset, old-name true/false, new-name
    true/false, and conflicting old/new values.
11. A structural guard fails if a retired key/env name is reintroduced outside
    an explicit compatibility allowlist.

Integration tests run only against a verified `*_test` database. Never use bare
`npm test`; run `npm run test:unit` and `npm run test:integration`.

### 9.2 Frontend widget/integration tests written before UI changes

- Pump the real onboarding, Home, create/edit race, public races, race detail,
  shop item sheet, admin settings, and tutorial/demo mirrors.
- Assert permanent behavior when the backend compatibility field is present,
  missing, null, malformed, or from an older backend.
- Assert new funded-exposure error copy and generic fallback for unknown errors.
- Remove flag-focused tests only by replacing their assertions with permanent-
  behavior public-screen assertions; never weaken an existing behavioral
  expectation.

Run `flutter analyze`, focused suites while iterating, then full `flutter test`.
Build both iOS and Android in lockstep before release work is called complete.

## 10. Implementation and deploy order

This is deliberately multiple deploys. Combining flag-code removal, row
deletion, environment deletion, compensation, and economy changes into one
restart creates default-polarity and rolling-worker hazards.

1. **Prerequisite changeset:** finish/review/test the existing resolved-impact
   v2 work without mixing unrelated cleanup into its dirty files. Deploy dark,
   validate, then enable separately.
2. **Compatibility + tombstone deploy:** add permanent compatibility
   serialization, Imposter tombstones, production Prisma guard, funded exposure
   schema/service dark or additive, and tests. Begin exposure dual-write with
   enforcement off. Do not delete rows/env yet.
   The production Prisma guard is fail-fast inside `src/db.js` before Prisma
   construction: `NODE_ENV=production && PRISMA_QUERY_EVENTS_ENABLED=true`
   throws before any query listener/client exists, with a startup test.
3. **Launch deploy:** after every worker dual-writes, run the guarded catch-up,
   prove zero null live stamps, then atomically enable exposure enforcement and
   version-2 prize issuance. Enable/verify already-carried dark behaviors in
   §3.3 and preserve all old-client fallbacks.
4. **Stable-family graduation deploys:** one family per deploy (request/API,
   Redis, race resolution/workers, product/onboarding). Replace settings reads
   with permanent code. Do not remove compatibility response fields.
5. **Data cleanup deploy:** only after every worker is on flag-independent code,
   at least **seven days** have elapsed, no old worker remains, and a tested
   restore drill succeeds, delete retired
   AppSetting rows with an idempotent audited script or a second migration.
   Remove retired controls from the admin endpoint/UI. Keep an audited export of
   key/value/update timestamps in the deploy record, never in committed source.
6. **Environment cleanup restart:** remove stale env entries only after code no
   longer reads them and the old binary rollback window has expired.
   Negative/default-on controls require tombstone-first verification. The
   rollback runbook must name the exact old values to restore before rolling
   back to an older artifact.
7. **One-time Imposter retirement:** run the idempotent 800-coin compensation
   and inventory-zero transaction, then audit.
8. **Deferred gates:** after buy-in drain, remove editing; after the 72-hour
   closure gate, graduate closure and delete its two controls.

The resolved-impact v2 prerequisite must be committed, reviewed, deployed dark,
and leave a clean baseline before cleanup edits any overlapping AppSettings,
queue, routes, or powerup-command files.

Every production deploy follows backend `DEPLOY_RUNBOOK.md`: migration status,
tests, commit/push, explicit in-the-moment approval, backend-first restart,
health/PM2/log checks, then any mobile release. Production data scripts require
their own explicit approval at execution time.

## 11. Acceptance criteria / definition of done

- Every decision in §3 is reflected in code and in a machine-checked retired-
  control allowlist.
- Only the explicit operational controls in §3.1 plus temporarily gated
  dependency-closure remain mutable; no stale false/default-on env deletion can
  resurrect code.
- The funded exposure cap covers every membership source atomically and new
  competitions stamp the retuned issuance version.
- Imposter owners receive exactly 800 coins total, five units are removed, and
  no HELD/live effect exists.
- Legacy buy-in money is not stranded and historical payloads remain readable.
- Frozen client contract tests pass.
- Backend unit/integration suites, frontend full tests/analyze, and both mobile
  builds pass.
- Required architecture, economy, UI-placement, and final code reviews report
  no unresolved required changes.
- Each deploy is healthy in production with migrations applied, both PM2
  workers online without restart loops, `/health` green, and targeted public
  smoke tests passing.
- Dependency-closure is not called graduated until its independent 72-hour gate
  is proven.

## 12. Manual UI-placement test plan

The following checklist is the ui-test-planner's required handoff and must be
run on staging before mobile release.

### Elements under test

- Capybara item sheet loses the bonus-steps promise; the Capybara character tile
  and cosmetics remain.
- Imposter disappears from Shop, race inventories, reward reveals, and usable-
  powerup surfaces; historical Activity entries remain readable.
- First-run onboarding uses only V3, omits the invite-code step, and makes the
  demo tutorial mandatory; Settings replay remains skippable.
- Team-race creation, quick-create, custom race windows, Home open-race
  discovery, the one-time Home invite-code SETUP row, and the Home invite
  overlay become permanently visible when their normal eligibility state
  applies.
- Retired feature switches disappear from Admin → CONFIG; the Home service-
  banner controls remain.
- Funded-exposure errors appear in the correct inline panel or toast for every
  create/join surface.
- The completed-impact popup disappears; recipient-private Activity remains on
  race detail.

### Checklist

1. **Shop — Capybara and Imposter**

   - **Get there:** Shop → Inventory → CHARACTERS → tap Capybara; then inspect Store and Inventory → POWERUPS.
   - **Verify:** The Capybara tile remains first in CHARACTERS and its sheet remains in place, but no bonus-steps promise appears. No Imposter tile appears in either POWERUPS list, and no blank gap or duplicate replaces it.

2. **Races tab — forked race inventory**

   - **Get there:** Races → inspect an active race card with held powerups/effects.
   - **Verify:** The compact inventory rail remains in its existing position and contains no Imposter. There is no empty extra slot or duplicated neighboring powerup where Imposter was removed.

3. **Race detail — real screen**

   - **Get there:** Open an active race with held powerups, then open a completed race with historical powerup Activity.
   - **Verify:** The active race’s powerup tray and global-stash area contain no Imposter and retain their existing position. Opening or refreshing the completed race does not show a completed-impact popup; Activity remains in its tab, and any historical Imposter entry remains visible there rather than disappearing.

4. **First-run V3 onboarding and mandatory demo**

   - **Get there:** Sign in on staging with a fresh account → complete the health gate → continue to the tutorial introduction and playable demo.
   - **Verify:** No V1/V2 onboarding screen and no “GOT AN INVITE CODE?” screen appears. The V3 demo-tutorial introduction occupies the normal onboarding stage with no “Skip for now” control; device Back does not reveal a hidden skip or leave the flow. Inside the demo, the coach card/ring never overlaps its highlighted control.

5. **Optional tutorial replay**

   - **Get there:** Complete onboarding → Profile → Settings → VIEW TUTORIAL.
   - **Verify:** The replay opens the spotlight tutorial and still shows its optional SKIP affordance in the established overlay position. It does not open the mandatory first-run demo or show an onboarding invite-code step.

6. **Permanent team and custom creation controls**

   - **Get there:** Races → create race → expand customization; then Edit an eligible pending ordinary race.
   - **Verify:** Create shows the team format control in its established customization position and the timeline always offers CUSTOM beside the preset windows. Edit also offers CUSTOM in the timeline card. Neither control is duplicated elsewhere, and no obsolete flag-disabled gap remains.

7. **Permanent quick-create and Home discovery**

   - **Get there:** Use an eligible account with no current next-race commitment → Home; use seeded open races if needed.
   - **Verify:** CREATE A RACE appears in its established Home order, with START A RACE/CREATE & SHARE above any “OR JOIN ONE” rows. Eligible open races appear beneath it, not as a second detached section. Tap the create CTA and verify the quick-create sheet is centered above the bottom safe area with its presets and CUSTOMIZE action; it does not also open the full create screen underneath.

8. **Quick-create after results**

   - **Get there:** Finish a race so the results summary appears.
   - **Verify:** START YOUR NEXT RACE remains the primary bottom action with NICE beneath it. Tapping it dismisses the results surface before the quick-create sheet appears; the two surfaces are not stacked or duplicated.

9. **One-time Home invite-code SETUP row**

   - **Get there:** Use a capable, unattributed account that has completed onboarding and has not answered the setup invite prompt → Home.
   - **Verify:** SETUP is the first content section below Home’s top actions, and “Have an invite code?” is one row inside the shared SETUP board. It is not a separate card and does not appear in the old onboarding position. After ENTER CODE or SKIP resolves it, the row disappears without leaving an empty SETUP header or gap.

10. **Home invite overlay**

    - **Get there:** Use an account with a pending race invite → return to Home with no other modal open.
    - **Verify:** One centered Home invite overlay appears above Home, with close at the upper right and ACCEPT/DECLINE at the bottom. The same invite is not simultaneously shown in the underlying Home list. Repeat with a tournament invite and verify the overlay occupies the same position.

11. **Funded-exposure error placement**

    - **Get there:** On staging, use an account seeded at the funded-exposure limit and try: Home quick-create, full create, Home open-race join, Public Races join, pending-invite accept, Home invite-overlay accept, and tournament join.
    - **Verify:** Quick-create shows the exposure message inline inside its still-open sheet; Home invite shows it inline above the overlay actions; full create, Home/Public/Races joins, and tournament join show one toast over the current surface. No failed action navigates forward, closes its current sheet/overlay, leaves a spinner covering controls, or shows the same error twice.

12. **Admin CONFIG cleanup**

    - **Get there:** Profile → Settings → ADMIN TOOLS → CONFIG.
    - **Verify:** Banner ads, Dual box banners, Team races, Onboarding v2, Onboarding v3, Onboarding invite code, and Mandatory tutorial switches are absent, with no separators or cache-note gap left behind. HOME SERVICE BANNER remains in the section with its Enabled switch, message field, and save button in their existing order.

13. **Demo and tutorial mirrors**

    - **Get there:** Run the fresh-account playable demo through create, invite, race detail, and a mystery-box open; then use Profile → Settings → VIEW TUTORIAL and advance through Home, Races, and race-detail preview beats.
    - **Verify:** Demo create still presents the scripted duration/create controls without team or CUSTOM controls displacing the coach targets; invite chrome remains above the coach card; demo and preview race inventories contain no Imposter; box opening never reveals Imposter; no completed-impact popup interrupts either flow. Tutorial Home contains neither the one-time SETUP invite row nor the quick/open-race section, and every spotlight still rings its intended element rather than the space where new production-only UI would sit.

### Surfaces confirmed unaffected

- Demo `RaceInviteScreen` has no feature-flag-controlled element; it remains a checkpoint only because its bottom action shares space with hand-forked coach chrome.
- Demo `CreateRaceScreen` intentionally suppresses team format through `demoMode` and CUSTOM through `DemoAuthService`; permanent production availability must not change that scripted surface.
- Tutorial Home intentionally forces `nextRace` to null and suppresses the invite-code SETUP row with `isTutorialPreview`; production Home additions should not appear there.
- Tutorial race detail and the playable demo reuse the real `RaceDetailScreen`, but their fake APIs supply no private impact notices and no Imposter inventory.
- Case-opening screens are shared with the demo; no layout change is expected when the retired reward is omitted.
- Character cosmetics, historical Imposter Activity rendering, active-impact reveals, and the Home service-banner UI remain intentionally present.

### Risks found while planning

- `DemoAuthService.customRaceWindowEnabled` is explicitly false and `demoMode` hides team format. Baking production getters to true must preserve both demo overrides or the duration/create coach rings will shift.
- The Home tutorial’s SETUP suppression and forced-null next-race state are load-bearing; removing those guards would add untaught UI and could allow navigation out of the tutorial.
- Races-tab inventory/effect rows are hand-forked from race detail, so Imposter filtering must be verified independently on both surfaces.
- Completed-impact removal must not remove the Activity row or suppress legitimate active-impact reveals; both occupy race detail but are different surfaces.
- Funded-exposure presentation is currently split between inline quick-create/Home-invite errors and toasts on other routes; each host must map the new error without moving or closing its parent surface.
- `AdminSettingsCardBody` hardcodes the retired switches and its cache note; deleting only backend keys would leave dead controls and misleading empty chrome.
- Mandatory first-run behavior and optional Settings replay use different tutorial hosts. Making all tutorial entry points mandatory would regress the replay placement.

## 13. Revision log

- Draft 1 (2026-08-20): consolidated the complete interview decision ledger;
  separated permanent behavior from compatibility fields; added tombstone-first
  ordering, multi-deploy row/env cleanup, funded exposure/version stamping,
  Imposter compensation, buy-in drain, and closure graduation gates.
- Gap pass 1 (2026-08-20): found missing live controls and ambiguous
  environment polarity. Added local-event and admin-metrics graduation,
  enumerated the production environment behavior family by family, required a
  structural inventory guard, and recorded the owner's intentional 100%
  dependency-closure rollout without weakening its soak gate.
- Gap pass 2 (2026-08-20): independently traced default-on ad-reward polarity
  and corrected the ledger (unset means live, not dark). Found that deleting DB
  rows/env immediately after a new-worker restart would break binary rollback;
  added a rollback-window delay, an audited settings snapshot, and explicit old
  env restoration requirements.
- Production audit addendum (2026-08-20): found a completed-race `HELD` status
  tail that the earlier live-race aggregate did not expose. Added a ledger-level
  reconciliation gate and prohibited status-only blanket compensation.
- UI-placement review (2026-08-20): added the complete staging checklist and
  promoted demo/tutorial overrides, forked inventories, popup-vs-Activity
  separation, host-specific exposure errors, Admin chrome cleanup, and optional
  replay behavior to implementation requirements.
- Architecture review (2026-08-20): `REVISE`. Required operational brakes or
  consolidated replacements, an exhaustive generated manifest, frozen pre-v3
  onboarding compatibility, new-app/old-backend downgrade rules, standard
  error shapes, a concrete Postgres exposure guard/lock order with millicoin
  storage, mandated `awardCoins` compensation, pre-Prisma fail-fast diagnostics,
  a seven-day destructive-cleanup delay, and a clean resolved-impact baseline.
- Economy review (2026-08-20): `SOUND WITH CHANGES`. Stamped unit 10, race max
  8,000, user-tournament max 500, team-aware raw exposure 300, and a second
  40/day rate cap; retained one global ad-value fraud brake; documented that
  caps bound rather than eliminate join-all dominance; and replaced marker-
  based legacy refunds with exact 830-coin debit-ledger remediation.
- Architecture follow-up (2026-08-20): removed the contradictory race-preview
  graduation, normalized every consolidated env polarity, separated sync-v2
  intake from frozen legacy uploads/reverse handoff, made client downgrade gates
  mandatory, routed all multi-participant writes through race-keyed C0, and
  added dual-write/catch-up/zero-null enforcement activation plus mixed-worker
  coverage.
- Final review (2026-08-20): architecture `APPROVE`, economy `APPROVE`, and the
  complete UI-placement checklist is included verbatim. No required review
  changes remain.
