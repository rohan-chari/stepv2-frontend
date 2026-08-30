# Production pool telemetry admin requirements

**Status:** Owner-approved and implemented; code-review fixes in progress.

## Summary and user story

As an authenticated administrator, I can open `SYSTEM HEALTH` in the existing
Admin Tools screen and see whether either HTTP worker, the resolution process, or
the cron process is waiting for PostgreSQL connections, plus aggregate step-sync
pressure over the last 60 minutes. I can also see request-failure percentages for
rolling 60-minute, 24-hour, and 7-day windows, with honest collection coverage. The
same privacy-safe aggregates are emitted to production logs for later analysis.

This is telemetry only. It does not change pool maximums, connection/transaction
timeouts, queries, step semantics, PM2 topology, or user-visible non-admin behavior.
The owner will use the collected evidence to decide later whether any pool or
transaction change should be separately approved.

The motivating 2026-08-29 incident produced `pg-pool` 3.13.0 pending-checkout
timeouts during a brief legacy `/steps` burst while host CPU/memory remained
healthy. Existing logs identify the error but cannot reconstruct per-process pool
occupancy or phase duration.

## Scope and non-goals

### In scope

- Exact per-process pg-pool acquisition/connection counters and bounded histograms.
- Aggregate step-ingestion phase timing across auth, legacy intake, and sync-v2.
- One structured log heartbeat/minute/process plus rate-limited pressure warnings.
- Short-lived sanitized Redis snapshots for cross-process admin presentation.
- Restart-safe, bounded Redis hourly aggregates supporting rolling 24-hour/7-day
  failure-rate views without PostgreSQL storage.
- Read-only admin API and a lazy `SYSTEM HEALTH` section in both Admin layouts.
- Production-safe privacy, version-skew, Redis-down, and malformed-data behavior.

### Non-goals

- No change to `max:20`, `connectionTimeoutMillis:5000`, or
  `idleTimeoutMillis:30000`.
- No new `DB_POOL_*` production variables or pool-policy validation in this slice.
- No step transaction optimization, request coalescing, admission queue, `429`,
  retry change, or response change.
- No PostgreSQL table/migration, query logging, SQL capture, or telemetry query.
- No editable admin controls, alerts, restart/deploy action, or raw-log viewer.
- No feature flag, rollout switch, production deployment, environment edit, PM2
  restart, or production data operation under spec approval.
- No capacity claim. The broader future decision remains documented in
  `docs/production-step-sync-pool-resilience-requirements.md`.

## Architecture and aggregation

Production runs exactly four database-using identities:

```text
http:0  http:1  resolution:0  cron:0
```

Each process owns its own `pg.Pool` and in-memory telemetry accumulator. Metrics
must distinguish:

- pending queued-checkout entries, waits, and timeouts;
- physical connection attempts, establishment duration, timeout, and other error;
- successful acquisitions and releases;
- exact checked-out count from acquire/release events;
- pool `total`, `idle`, `nonIdle`, `waiting`, and configured `max`;
- process RSS, one-core-normalized CPU, and event-loop p99.

`total-idle` is labeled `nonIdle`, never `checkedOut`, because connecting clients
already contribute to `total`. Fixed wait buckets are
`1,5,10,25,50,100,250,500,1000,2500,5000ms,+Inf`. Counters are never sampled;
optional detailed step phase observations may be sampled before minute aggregation.
All accumulators are bounded and use monotonic clocks.

For step traffic, aggregate by endpoint (`steps`, `samples`, `sync-v2`) and outcome:

- request/success/failure count and privacy-safe failure stage;
- whole request and authentication duration;
- pending checkout wait;
- each legacy transaction attempt;
- each sync-v2 outer transaction attempt, including its up-to-three closure retries;
- scoring-state, daily, sample, scoring-generation, active-race, durable-enqueue,
  summary-capture/finalization, transaction-total, and post-commit phases where
  applicable.

An endpoint `failure` is classified, never stored as an unbounded/raw error:
`validation_4xx`, `auth_4xx`, `pool_checkout_timeout`, `transaction_error`, or
`server_5xx`. Client validation/auth failures remain visible as traffic outcomes but
do not by themselves classify system health as degraded. Histogram bucket counts,
sample count, sum, and max are retained in each minute bucket; p95 values are
calculated only after merging bucket counts across the requested window. Percentiles
are never averaged from precomputed minute percentiles.

Required zero-delta fields are always present and truthful: pool gauges plus
acquisitions, releases, queued checkouts/timeouts, physical attempts,
`physicalTimeouts`, and `physicalErrors` (non-timeout errors). Only percentile/max
fields with no observations may be omitted. A missing required counter makes the
snapshot malformed. If detailed phase observations are sampled, each phase carries
its observation count and configured sampling rate in logs, snapshots, and the
admin envelope so a sampled percentile cannot appear population-complete.

`recordStepSyncV2` owns the outer transaction and passes its client into
`stepInputIntake`; nested telemetry must not claim a second acquisition.

Failure percentages use two explicitly labeled numerators over all accepted route
attempts in the window:

- **Request failure rate:** every non-success outcome divided by requests.
- **Server failure rate:** `pool_checkout_timeout`, `transaction_error`, and
  `server_5xx` divided by requests. Validation/auth 4xx outcomes are excluded from
  this numerator but remain included in request failures.

When the denominator is zero, the rate is `null`/`NO REQUESTS`, never `0%`.
Percentages are derived from integer counts and rounded to one decimal only for UI.

## Log contract

Each process emits one single-line JSON event every 60 seconds, including a
zero-delta heartbeat:

```json
{
  "event": "database_pool_telemetry_v1",
  "schema": "database-pool-telemetry-v1",
  "role": "http",
  "instance": "0",
  "bootId": "opaque-random-boot-id",
  "bootStartedAtMs": 1788030000000,
  "bootStartedAt": "2026-08-29T19:00:00.000Z",
  "capturedAtMs": 1788031780000,
  "capturedAt": "2026-08-29T19:29:40.000Z",
  "pool": {
    "max": 20,
    "total": 12,
    "idle": 7,
    "nonIdle": 5,
    "checkedOut": 5,
    "waiting": 0
  },
  "interval": {
    "acquisitions": 80,
    "releases": 80,
    "queuedCheckouts": 2,
    "queuedTimeouts": 0,
    "queuedWaitP95Ms": 12,
    "queuedWaitMaxMs": 44,
    "physicalAttempts": 1,
    "physicalTimeouts": 0,
    "physicalErrors": 0
  },
  "process": {
    "rssBytes": 410000000,
    "cpuOneCorePercent": 18.2,
    "eventLoopP99Ms": 8.4
  }
}
```

HTTP processes include an additional bounded `stepIngestion` aggregate with the
fields above. Missing measurements are omitted, not encoded as zero.

Emit `database_pool_pressure_v1` immediately, rate-limited to once/minute/process/
reason, when waiting becomes nonzero, queued wait exceeds one second, checkout
times out, or physical connection establishment fails. Logging failure is swallowed.
Telemetry emits no database query and the timer is unref'd/stopped on graceful
shutdown so tests and PM2 drain are unaffected.

The production runbook must verify before any observation window that PM2 log
rotation/retention preserves at least 48 hours and that these JSON lines are present
for all four identities. At the current topology this is 5,760 routine heartbeat
lines/day plus bounded warnings. Snapshot-write failures use a rate-limited generic
telemetry error and must not recursively amplify logs.

Never log/store user IDs, usernames, emails, IPs, tokens, request/session IDs,
step values, sample/request bodies, race IDs, SQL/query text, database URLs,
credentials, device/app identity, or raw errors that may contain them.

## Redis snapshot contract

Once/minute each process best-effort writes its sanitized current state and at most
60 minute buckets to one existing-prefix-namespaced key:

```text
v1:ops:db-pool:http:0
v1:ops:db-pool:http:1
v1:ops:db-pool:resolution:0
v1:ops:db-pool:cron:0
```

Snapshot schema `database-pool-telemetry-snapshot-v1` has exactly these required
top-level members: `schema`, `role`, `instance`, `bootId`, `bootStartedAtMs`,
`bootStartedAt`, `capturedAtMs`, `capturedAt`, `oldestBucketAt`, `newestBucketAt`,
`coverageMinutes`, `pool`, `process`, and `buckets`. `pool` has required `max`,
`total`, `idle`, `nonIdle`, `checkedOut`, and `waiting`. `process` has the current
required `rssBytes`, `cpuOneCorePercent`, and `eventLoopP99Ms` sample. Each bucket has required integer
`minuteStartedAtMs`; ISO `minuteStartedAt`; `interval` with acquisitions, releases,
queuedCheckouts, queuedTimeouts, physicalAttempts, physicalTimeouts, and
physicalErrors; and named `queuedWaitHistogram` and
`physicalConnectionDurationHistogram`. Mergeable histogram objects are shaped as
`{"observations":0,"sumMs":0,"maxMs":null,"counts":[0,0,0,0,0,0,0,0,0,0,0,0]}`;
and, for HTTP roles only, `stepIngestion`. Each histogram has exactly 12 cumulative
bucket counts matching the fixed boundaries; `maxMs` is null only at zero
observations. Step aggregates have required request/success/failure/queued-timeout
counters; required `requestDurationHistogram`, `authenticationDurationHistogram`,
`checkoutWaitHistogram`, and `transactionDurationHistogram`; three ordered endpoint
aggregates with the same required counters and four named histograms; and a `phases`
array. Each snapshot phase record has required allowlisted `phase`, `observations`,
`samplingRate`, and a mergeable `histogram` object—never a precomputed p95. The API
derives its phase `p95Ms`/`maxMs` only after merging those counts. Additive fields
are allowed; missing required fields invalidate the snapshot.

- TTL: 150 seconds on every write.
- Serialized cap: 512 KiB; discard oldest buckets first. A deterministic
  representative 60-bucket HTTP snapshot with populated counters/histograms must
  remain at least 20% below the cap (no more than 419,430 bytes), retain every
  bucket, and report `coverageMinutes:60`. If it exceeds that gate, raise the fixed
  code constant explicitly before release; never silently ship perpetual collection.
- Fixed ceiling: four Redis writes/minute across steady production topology.
- Records include schema, role, instance, boot ID/time, and capture time.
- Logical keys are built in `shared/cache/cacheKeys.js` as
  `v1:ops:db-pool:http:0`, `v1:ops:db-pool:http:1`,
  `v1:ops:db-pool:resolution:0`, and `v1:ops:db-pool:cron:0`; the existing cache
  wrapper adds `p:`/`s:`/`t:` environment prefixes.
- Minute buckets carry mergeable histogram counts rather than precomputed-only
  percentiles. The API merges the selected buckets, then derives p95/max.
- Redis is derived presentation only; logs are the durable evidence.
- Redis down/unset/malformed is swallowed and never falls back to PostgreSQL.
- Add a narrowly scoped cache helper that atomically orders writes by
  `(bootStartedAtMs, capturedAtMs)` using one Redis Lua operation and renews TTL on
  an accepted write. A later boot always wins; capture time decides only within the
  same boot. A malformed existing payload may be replaced. Thus a draining old PM2
  process cannot overwrite its replacement even if the old process captures later.
  Test that exact race. This surface is not deployment attestation.

Each payload exposes the oldest/newest retained bucket minute and
`coverageMinutes`. A restart may reset history and the size cap may drop old
buckets; neither condition is hidden. Historical buckets are not copied across
boots because Redis remains derived telemetry rather than durable state.

No app-setting/release flag is added. This is a permanent operational telemetry
transport, not a product read-through cache: writes are fail-open and off the
request path; the sole read is an explicit admin-only observation request and also
fails open. This is the documented exception to earlier per-surface cache-flag
practice and follows both repositories' current rule that release flags are
prohibited by default. Owner approval of this spec explicitly approves that
classification; it does not authorize deployment.

### Seven-day failure-rate history

The two HTTP workers additionally write their drained minute outcome deltas as
compact per-minute payloads inside one versioned Redis hash per UTC hour:

```text
v1:ops:step-ingestion-hour:2026-08-29T19
v1:ops:step-ingestion-history-start
```

The existing cache wrapper adds the environment prefix. `cacheKeys.js` owns builders
for both logical keys; step commands and Admin code never access Redis directly.
Injected history-writer and history-reader adapters sit behind `redisCache.js`.

Each hour hash has `schema = step-ingestion-hour-v1` and only these field forms:

```text
schema
c:<minuteEpochMs>:http:<instance>
o:<minuteEpochMs>:http:<instance>
m:<minuteEpochMs>:http:<instance>:<bootId>
```

`c:` is an integer accepted-emission count. `o:` is literal `1` only after overflow.
Each `m:` value is exact compact JSON:

```json
{
  "schema": "step-ingestion-minute-v1",
  "minuteStartedAtMs": 1788031740000,
  "role": "http",
  "instance": "0",
  "bootId": "opaque-random-boot-id",
  "endpoints": {
    "steps": [10, 9, 1, 0, 0, 0, 0],
    "samples": [4, 4, 0, 0, 0, 0, 0],
    "sync-v2": [3, 3, 0, 0, 0, 0, 0]
  }
}
```

Endpoint array order is exactly `requests`, `successes`, `validation4xx`, `auth4xx`,
`poolCheckoutTimeouts`, `transactionErrors`, `server5xx`. All are required safe
nonnegative integers and their outcome sum equals requests. The field coordinates
must exactly match the payload. Unknown field names, duplicate logical payloads,
bad schema/JSON, or invariant failures mark that hour malformed; they are not
ignored.

A single Lua operation takes the hour key, history-start key, schema, emission field,
counter field, overflow field, payload, collection-start JSON, and TTL. It:

1. rejects an existing nonmatching hour schema as `schema_error`;
2. returns `duplicate` without mutation if the exact `m:` field exists;
3. if `c:` is already 2, sets `o:` to `1`, renews TTL, and returns `overflow` without
   storing/counting the third emission;
4. otherwise stores the payload, increments `c:`, creates the sentinel with `SET NX`,
   renews both TTLs, and returns `accepted`.

The sentinel value is exact JSON
`{"schema":"step-ingestion-history-start-v1","collectionStartedMinuteMs":<UTC-minute>}`.
The writer validates inputs before Lua; `schema_error`, `overflow`, Redis failure,
and invalid output are rate-limited telemetry warnings and never affect a request.
Ambiguous retries reuse the same emission field. Two emissions per logical worker/
minute support the expected old/new PM2 overlap; any third marks that worker-minute
overflow/incomplete rather than silently accepting unbounded data.

- TTL is eight days. At most 169 current/prior hourly keys are read for a seven-day
  boundary. Each hash permits at most 240 minute payloads, 120 count fields, 120
  overflow fields, and one schema field, with a 128 KiB read ceiling; the whole
  history batch has a 24 MiB ceiling. Exceeding either makes affected history
  partial, never a route failure.
- Steady topology adds two Redis writes/minute, for six total telemetry writes/minute
  including snapshots. Redis failure is swallowed and does not recursively retry.
- A minute has full **emission coverage** only when both logical HTTP identities
  have one or two accepted payloads and neither overflow marker is set. One identity
  is partial; overflow is incomplete. Counts from valid partial minutes contribute
  to observed rates. Because an unexpected process crash can lose an unflushed
  minute before Redis knows that boot existed, neither API nor UI calls this complete
  request capture; labels say `TELEMETRY COMPLETE` or `TELEMETRY COLLECTING` and all
  rates are explicitly based on observed telemetry.
- The Admin reader performs one bounded pipelined `HGETALL` batch, never PostgreSQL.
  Each window ends at the start of the current UTC minute and selects the preceding
  60, 1,440, or 10,080 complete minute payloads exactly, including only selected
  boundary-hour minutes. The short snapshot remains the source for pool/latency;
  long history stores outcome counts only.

## API contract

### `GET /admin/system-health?window=60m`

Add beneath the existing `/admin` router, inheriting `requireAuth` and
`requireAdmin`. `window` defaults to `60m`; any other value returns HTTP `400`:

```json
{ "error": "Unsupported system-health window", "code": "INVALID_WINDOW" }
```

The query service throws the standard `ValidationError` with `INVALID_WINDOW`;
unexpected errors flow through shared error middleware.

The route performs exactly one bounded Redis `MGET` for the four snapshot keys and
one bounded pipelined history read (start sentinel plus at most 169 hourly hashes),
with no route-owned PostgreSQL query. It validates fields, rejects duplicates/stale
records, orders processes `http:0`, `http:1`, `resolution:0`, `cron:0`, and combines
valid aggregates.

HTTP `200` envelope:

```json
{
  "schema": "admin-system-health-v1",
  "status": "available",
  "overall": "healthy",
  "historyStatus": "available",
  "generatedAt": "2026-08-29T19:30:00.000Z",
  "windowMinutes": 60,
  "windowCoverageMinutes": 60,
  "expectedProcesses": 4,
  "freshProcesses": 4,
  "missingProcesses": [],
  "processes": [
    {
      "role": "http",
      "instance": "0",
      "status": "healthy",
      "capturedAt": "2026-08-29T19:29:40.000Z",
      "coverageMinutes": 60,
      "oldestBucketAt": "2026-08-29T18:30:00.000Z",
      "newestBucketAt": "2026-08-29T19:29:00.000Z",
      "pool": {
        "max": 20,
        "total": 12,
        "idle": 7,
        "nonIdle": 5,
        "checkedOut": 5,
        "waiting": 0
      },
      "last60m": {
        "acquisitions": 4100,
        "releases": 4100,
        "queuedCheckouts": 3,
        "queuedTimeouts": 0,
        "queuedWaitP95Ms": 12,
        "queuedWaitMaxMs": 44,
        "physicalAttempts": 2,
        "physicalTimeouts": 0,
        "physicalErrors": 0
      },
      "process": {
        "rssBytes": 410000000,
        "cpuOneCorePercent": 18.2,
        "eventLoopP99Ms": 8.4
      }
    }
  ],
  "stepIngestion": {
    "contributingHttpProcesses": 2,
    "requests": 920,
    "successes": 920,
    "failures": 0,
    "queuedTimeouts": 0,
    "latencyP95Ms": 640,
    "transactionP95Ms": 310,
    "phases": [
      {
        "phase": "transaction_total",
        "observations": 920,
        "samplingRate": 1.0,
        "p95Ms": 310,
        "maxMs": 910
      }
    ],
    "endpoints": [
      {
        "endpoint": "steps",
        "requests": 330,
        "successes": 330,
        "failures": 0,
        "queuedTimeouts": 0,
        "latencyP95Ms": 710,
        "transactionP95Ms": 340
      }
    ]
  },
  "failureWindows": [
    {
      "window": "60m",
      "windowMinutes": 60,
      "collectionStatus": "complete",
      "completeCoverageMinutes": 60,
      "partialCoverageMinutes": 0,
      "requests": 920,
      "successes": 900,
      "requestFailures": 20,
      "serverFailures": 3,
      "endpoints": [
        {
          "endpoint": "steps",
          "requests": 330,
          "successes": 315,
          "requestFailures": 15,
          "serverFailures": 2
        },
        {
          "endpoint": "samples",
          "requests": 300,
          "successes": 297,
          "requestFailures": 3,
          "serverFailures": 1
        },
        {
          "endpoint": "sync-v2",
          "requests": 290,
          "successes": 288,
          "requestFailures": 2,
          "serverFailures": 0
        }
      ]
    },
    {
      "window": "24h",
      "windowMinutes": 1440,
      "collectionStatus": "collecting",
      "completeCoverageMinutes": 377,
      "partialCoverageMinutes": 2,
      "requests": 6100,
      "successes": 6030,
      "requestFailures": 70,
      "serverFailures": 8,
      "endpoints": [
        { "endpoint": "steps", "requests": 2200, "successes": 2160, "requestFailures": 40, "serverFailures": 5 },
        { "endpoint": "samples", "requests": 2000, "successes": 1980, "requestFailures": 20, "serverFailures": 2 },
        { "endpoint": "sync-v2", "requests": 1900, "successes": 1890, "requestFailures": 10, "serverFailures": 1 }
      ]
    },
    {
      "window": "7d",
      "windowMinutes": 10080,
      "collectionStatus": "collecting",
      "completeCoverageMinutes": 377,
      "partialCoverageMinutes": 2,
      "requests": 6100,
      "successes": 6030,
      "requestFailures": 70,
      "serverFailures": 8,
      "endpoints": [
        { "endpoint": "steps", "requests": 2200, "successes": 2160, "requestFailures": 40, "serverFailures": 5 },
        { "endpoint": "samples", "requests": 2000, "successes": 1980, "requestFailures": 20, "serverFailures": 2 },
        { "endpoint": "sync-v2", "requests": 1900, "successes": 1890, "requestFailures": 10, "serverFailures": 1 }
      ]
    }
  ]
}
```

The variant discriminator fields below use the exact common process-row and
step-aggregate schemas from the complete envelope above; fields not repeated in
these two abbreviated discriminator examples are unchanged, not optional:

```json
{
  "schema": "admin-system-health-v1",
  "status": "available",
  "overall": "unknown",
  "historyStatus": "available",
  "generatedAt": "2026-08-29T19:30:00.000Z",
  "windowMinutes": 60,
  "windowCoverageMinutes": 7,
  "expectedProcesses": 4,
  "freshProcesses": 4,
  "missingProcesses": []
}
```

```json
{
  "schema": "admin-system-health-v1",
  "status": "partial",
  "overall": "degraded",
  "historyStatus": "partial",
  "generatedAt": "2026-08-29T19:30:00.000Z",
  "windowMinutes": 60,
  "windowCoverageMinutes": 42,
  "expectedProcesses": 4,
  "freshProcesses": 3,
  "missingProcesses": [
    { "role": "resolution", "instance": "0", "reason": "stale" }
  ]
}
```

```json
{
  "schema": "admin-system-health-v1",
  "status": "unavailable",
  "overall": "unknown",
  "historyStatus": "unavailable",
  "generatedAt": "2026-08-29T19:30:00.000Z",
  "windowMinutes": 60,
  "windowCoverageMinutes": 0,
  "expectedProcesses": 4,
  "freshProcesses": 0,
  "missingProcesses": [
    { "role": "http", "instance": "0", "reason": "unavailable" },
    { "role": "http", "instance": "1", "reason": "unavailable" },
    { "role": "resolution", "instance": "0", "reason": "unavailable" },
    { "role": "cron", "instance": "0", "reason": "unavailable" }
  ],
  "processes": [],
  "stepIngestion": null,
  "failureWindows": null
}
```

`missingProcesses[].reason` is exactly `missing|stale|malformed|unavailable`.
`windowCoverageMinutes` is the minimum retained coverage among valid process rows,
or zero when none are valid. `stepIngestion` is null when no valid HTTP process
contributes; otherwise `contributingHttpProcesses` is required. A phase object uses
an allowlisted name (`authentication`, `checkout_wait`, `transaction_total`,
`scoring_state`, `daily`, `sample`, `scoring_generation`, `active_race`,
`durable_enqueue`, `summary_finalization`, or `post_commit`), required
`observations` and `samplingRate`, and optional p95/max only when observations are
nonzero. Endpoint rows are ordered `steps`, `samples`, `sync-v2`; all three appear
when `stepIngestion` is non-null, including truthful required zero counters.
`processes` contains exactly `freshProcesses` rows with the complete row shape shown
above; collecting has four rows, partial has only valid rows, and unavailable has
none. Per-process status is exactly `healthy|pressure|degraded|unknown`: current or
retained degraded signals win first, current pressure signals next, then fewer than
60 retained buckets yields `unknown`, otherwise it is `healthy`. Thus each process
has deterministic collecting semantics and `overall` applies the same precedence
across all expected identities.

A valid process row with `coverageMinutes:0` has null/absent oldest and newest bucket
timestamps; positive coverage requires both timestamps and consistent bounds.

`historyStatus` is independently `available|partial|unavailable`: all required hour
hashes that fall after telemetry collection began are valid, one or more expected
hash/minute emissions are absent/malformed, or no valid history exists. When any
history exists, `failureWindows` contains exactly ordered `60m`, `24h`, and `7d`
rows. Each contains exactly the fields shown above and exactly three ordered endpoint
rows. `collectionStatus` is `complete` only when `completeCoverageMinutes` equals
`windowMinutes` and partial coverage is zero; otherwise it is `collecting`.
`requestFailures = requests - successes`; `serverFailures <= requestFailures`; sums
of endpoint counts equal the window counts. The API returns integer counts rather
than floating rates. Flutter calculates numerator/requests and rounds only rendered
percent text to one decimal. With zero requests it renders `NO REQUESTS`.

Shared backend/Flutter validation bounds are exact:

- counts/timestamps/bytes are JSON integers from 0 through
  `9,007,199,254,740,991`; pool gauges are 0 through 1,000,000 and configured max is
  an integer from 1 through 1,000,000;
- durations are finite numbers from 0 through 86,400,000 ms; sampling rate is
  finite `0..1`; CPU is finite `0..100`; per-snapshot coverage is integer `0..60`;
  failure-window complete/partial coverage is integer `0..windowMinutes` where
  `windowMinutes` is exactly `60|1440|10080`;
- In logs/snapshots, ISO timestamps and their integer millisecond companions must
  agree within 1 ms; the Admin API exposes the validated ISO form only;
  `generatedAt`/`capturedAt` may be at most five minutes in the future relative to
  the validator clock. With `captureMinuteMs = floor(capturedAtMs / 60000) * 60000`,
  every completed bucket must satisfy
  `captureMinuteMs - 60*60000 <= minuteStartedAtMs < captureMinuteMs`; buckets remain
  minute-aligned, unique, and strictly ordered. `bootStartedAt` must not exceed
  capture time by more than five minutes;
- required pool/interval fields and step counters are present even when zero.
  Percentile/max fields, `stepIngestion`, and phase timing values are the only
  measurement fields omitted/null under the rules above. Non-finite, fractional
  integer fields, unknown enum values, duplicate identities, and invariant failures
  make the owning snapshot/row malformed rather than being clamped.

`status`: `available|partial|unavailable`. `overall`:
`healthy|pressure|degraded|unknown`. Missing/malformed numeric fields are omitted,
never coerced to zero. Freshness limit is 150 seconds.

- All four fresh: `available`.
- One or more valid but missing/stale/malformed: `partial`; missing identities are
  listed separately and never represented by zero-valued process rows.
- Redis disabled/down or no valid records: HTTP `200`, `unavailable`, `unknown`,
  empty processes, `freshProcesses:0`.
- `partial` always produces `degraded` because an expected production identity is
  not observable. `unavailable` produces `unknown`.
- With all identities available, any 60-minute queued checkout timeout, physical
  connection timeout/error, transaction/server-5xx step failure, or impossible pool
  invariant produces `degraded`. Otherwise current `waiting > 0`, queued-wait p95
  at least 100 ms, or queued-wait max at least 1000 ms produces `pressure`; all
  other complete data produces `healthy`.
- Full-window `healthy` requires 60 retained minute buckets for every expected
  process. When all identities are fresh but any has shorter history, `status`
  remains `available`, `overall` is `unknown`, and the response includes the minimum
  `windowCoverageMinutes`; the UI labels this `COLLECTING — LAST N MINUTES` and does
  not claim a 60-minute result. Degraded current/observed failures still outrank
  collecting, so an incomplete window cannot conceal a present incident.
- Impossible invariants are: any negative gauge/counter; `idle > total`;
  `nonIdle != total - idle`; `checkedOut > nonIdle`; `total > max`; or waiting,
  duration, timestamp, histogram, and coverage values outside documented bounds.
  Also invalid: success plus failure not equaling requests; endpoint totals exceeding
  their parent aggregate; non-monotonic cumulative histogram counts; a final
  histogram count not equaling observations; duplicate/non-minute bucket times; or
  coverage not equaling the number of distinct retained minute buckets.
- Unexpected route failure: existing coded admin `500` envelope.
- Older backend route absence: plain `404`; the client isolates this to the section.

Existing `/admin/stats` shape/query cost is unchanged. Existing clients never call
the new route.

## Data model and migrations

No PostgreSQL schema/data migration. Redis contains four 150-second process snapshot
keys, one renewable eight-day collection-start sentinel, and at most 169 eight-day
UTC-hour history hashes, all namespaced and bounded as specified above. PostgreSQL
remains authoritative for all product data and step/resolution correctness.

## Frontend plan

Add a collapsed-by-default `SYSTEM HEALTH` `AdminSection` immediately before
`CONFIG` in both branches of `AdminScreen`: iOS metrics dashboard and Android/
legacy dashboard. It fetches only on first expand. The screen refresh includes it
only after it has been opened; an inner `REFRESH` action is also provided. No timer
polling.

In the iOS branch it is outside the conditional that swaps the existing metrics
dashboard for unavailable/disabled/server-update messaging, immediately before
`_buildMetricsConfig`. In Android/legacy it is directly between `REVENUE` and
`CONFIG`. Render exactly one section per branch because `AdminSection` keys derive
from the title.

Use the current trail-sign/pixel operational aesthetic:

- textual status plate: `HEALTHY`, `PRESSURE`, `DEGRADED`, or `UNKNOWN`, with
  semantic color but never color alone;
- `POOL NOW`: four fixed process rows showing role/instance, checked-out/max,
  waiting, and freshness; absent row reads `MISSING`;
- `LAST 60 MIN` (or honest `LAST N MINUTES` while collecting): queued timeouts,
  wait p95/max, physical timeouts/non-timeout errors, step failures, step latency
  p95, transaction p95, and compact per-endpoint rows;
- `REQUEST FAILURE RATE` cards for `60 MIN`, `24 HOURS`, and `7 DAYS`. Each shows
  request-failure percent and fraction, server-failure percent and fraction, three
  compact endpoint rows, and `TELEMETRY COMPLETE` or
  `TELEMETRY COLLECTING — X OF Y MINUTES`, where X is complete-emission minutes only.
  Partial minutes are shown separately (for example `+2 PARTIAL`) and never inflate
  X. Percentages remain visible but are always labeled `OBSERVED TELEMETRY`;
- `Updated <relative time>` metadata;
- omit unavailable values or show `UNAVAILABLE`; never invent zero.

When fresh process data covers less than 60 minutes, replace `UNKNOWN` with the
more useful textual presentation `COLLECTING — LAST N MINUTES`; do not label the
summary `LAST 60 MIN` until full coverage exists.

Loading, partial, unavailable, old-backend, malformed, transport/5xx, and stale-
after-refresh-failure states have distinct text and retry behavior. Previously good
data remains visible but marked stale after refresh failure.
Pool-snapshot availability and failure-history availability render independently:
one may remain useful while the other says `UNAVAILABLE` or `COLLECTING`.

Add `lib/models/admin_system_health.dart` with defensive `Object?` parsing,
allowlisted roles/statuses, bounded nonnegative counts/durations, duplicate identity
rejection, and missing/additive-safe reads. Add
`BackendApiService.fetchAdminSystemHealth`; distinguish plain route-absence `404`
from other failures.

The UI supports light/night palettes, narrow phones, large text, iOS, and Android
without horizontal scrolling. It reuses `AdminSection`, `PixelText`, existing
spinners/state panels, and palette tokens; no new font/dependency or generic
Material monitoring package.

The API returns aggregates only—never raw minute buckets—and is bounded to four
process rows and three endpoint rows. Screen-level refresh fetches system health
only if the section was opened, after the existing dashboard refresh sequence; its
failure does not fail or clear the other Admin sections. Relative update text is
recomputed on a render/refresh only; no hidden timer is introduced.

## Backward compatibility and rollout

- Backend first, then app.
- Old apps ignore the new route/snapshots.
- New app against old backend shows `Requires server update` only in this section.
- Missing/null/malformed/additive fields never crash the admin screen.
- Non-admin app users never see Admin Tools and receive existing `403` from API.
- Redis failure changes only telemetry availability, never application health or
  step behavior.
- Both platforms ship from the same Dart section and both existing Admin branches
  include it.
- No feature flag. The telemetry is permanent, fail-open observability.
- Production deployment/reload requires separate explicit in-the-moment approval.

## Test-first plan

Backend tests, before logic:

1. Focused pool instrumentation tests distinguish queued checkout timeout from
   physical establishment timeout/non-timeout error, preserve required zero fields,
   reject enumerated impossible invariants, and maintain exact acquire/release state.
2. Histogram boundary, reset/rollup, memory bound, zero heartbeat, warning rate
   limit, logging-failure, timer shutdown, and forbidden-field tests.
3. Real HTTP/test-PostgreSQL step tests cover legacy and sync-v2 outer/nested
   transaction attribution without response/persistence changes or extra queries.
4. Redis writer tests cover four identities, TTL, prefix, 60 buckets, 512 KiB cap,
   the populated 60-bucket/20%-headroom/no-eviction gate,
   atomic boot-then-capture newer-write-wins reload races, malformed replacement,
   restart/size-cap coverage reporting, disabled/down/
   malformed behavior, merged-histogram percentile correctness, and no PostgreSQL
   fallback.
5. Hour-history tests cover atomic dedupe and ambiguous retry, PM2 overlap, exact
   third-emission overflow, exact compact field/payload/schema validation, outcome
   classification, start sentinel, eight-day expiry, UTC-hour/minute boundaries,
   169-key and size bounds, partial/full emission coverage, Redis gaps/malformed/
   oversize hashes, zero-request rates, exact rolling-minute clipping, and no
   PostgreSQL fallback.
6. Real HTTP admin integration tests cover auth/admin gate, exact full envelope,
   one snapshot `MGET` plus one bounded history pipeline, ordering, aggregation,
   partial/stale/missing/duplicate/malformed,
   three ordered failure windows, collecting/complete coverage, independent history
   availability, Redis disabled/down, invalid window, and no route-owned DB query.
7. Existing step-sync/idempotency/resolution integration suites remain unchanged and
   green. Tests run only against a dedicated `*_test` database and local test Redis
   DB 15; also run relevant suites with `REDIS_URL` unset.

Frontend tests, before logic:

1. Exact service request and old-backend-versus-other-error classification.
2. Defensive parser matrix: full/partial/unavailable, missing/null/malformed,
   duplicate/unknown role, unknown status, negative/overflow, additive fields.
3. Real `AdminScreen` widget tests for both layout branches: correct placement,
   collapsed/no-fetch, first expand, inner/screen refresh, retry, stale retention.
4. All named visual/data states and four process/missing rows.
5. Exact 60m/24h/7d failure fractions and one-decimal percentages, endpoint rows,
   zero-request, collecting/complete, partial-history, and independent history/pool
   failure states.
6. Narrow width, large text, light/night, iOS/Android, no overflow.
7. Existing Admin dashboard sections and refresh ordering remain green.

Required commands: backend `npm run test:unit` and `npm run test:integration`
(never bare `npm test`); frontend `flutter analyze` and `flutter test`.

## Acceptance criteria and definition of done

- Four process heartbeats/minute and pressure warnings contain accurate bounded
  metrics and none of the forbidden data.
- Metrics add zero PostgreSQL queries, do not change pool settings, and cannot fail
  an application request.
- Admin API is admin-only, two bounded Redis batches, defensive, and exact-contract.
- Admin failure rates cover rolling 60-minute/24-hour/7-day windows, survive process
  restarts, deduplicate retries, and never claim complete coverage while collecting.
- `SYSTEM HEALTH` works in both Admin layouts with every loading/error/freshness
  state and does not fetch while collapsed.
- Frozen/current step API responses and persisted outcomes are unchanged.
- Tests-first suites and required commands are green; no existing assertion is
  weakened.
- iOS and Android, version skew, Redis-down, PM2 shutdown, and privacy are reviewed.
- Architect, UI test planner, implementation agents, and code reviewer complete the
  repository workflow.
- The owner receives the manual UI-placement checklist.
- No production deployment is implied or performed.

## Exact implementation seams

Backend:

- `src/db.js`
- `src/shared/observability/databasePoolMetrics.js` (new)
- privacy-safe request context/step command seams, including
  `recordStepSyncV2.js` and `stepInputIntake.js`
- Redis snapshot adapter plus injected step-history writer/reader adapters using
  `shared/cache/redisCache.js`; `shared/cache/cacheKeys.js` owns builders for all
  four snapshot keys, the history-start key, and UTC-hour history keys
- injected `buildGetSystemHealth(dependencies = {})` query/service, exported through
  `src/modules/admin/index.js`; `src/modules/admin/routes.js` only parses, calls it,
  and sends `res.json` under `asyncHandler`
- focused tests and real HTTP integration tests

Frontend:

- `lib/services/backend_api_service.dart`
- `lib/models/admin_system_health.dart` (new)
- `lib/screens/admin_screen.dart` and focused reusable system-health body
- existing Admin/service tests plus new real-screen tests

## Manual UI-placement test plan

1. **Admin Tools — iOS metrics layout**
   - **Get there:** Sign in with an admin account on iPhone → Profile → Settings →
     ADMIN → ADMIN TOOLS.
   - **Verify:** `SYSTEM HEALTH` appears exactly once, collapsed, immediately before
     `CONFIG`. It is not below `CONFIG` or duplicated elsewhere. Expand it and verify
     its body opens beneath its own header without moving content into `CONFIG`.
2. **Admin Tools — Android/legacy layout**
   - **Get there:** Sign in with an admin account on Android → Profile → Settings →
     ADMIN → ADMIN TOOLS.
   - **Verify:** `SYSTEM HEALTH` appears exactly once between `REVENUE` and `CONFIG`,
     initially collapsed. It is not still present after `CONFIG` or duplicated
     elsewhere. Expand it and verify the body remains inside the section.
3. **Expanded healthy/pressure/degraded/partial states**
   - **Get there:** On each platform, use controlled backend responses for healthy,
     pressure, degraded, and partial snapshots → open Admin Tools → expand
     `SYSTEM HEALTH`.
   - **Verify:** The textual status plate appears first inside `SYSTEM HEALTH`;
     `POOL NOW` follows it; `LAST 60 MIN`/`LAST N MINUTES`, endpoint rows, update metadata, and the
     inner refresh action remain inside the same section. Four fixed process
     positions remain visible, with any absent process represented as `MISSING` in
     its expected row rather than removing or reordering the row. No system-health
     content appears inside `CONFIG`.
4. **Loading, unavailable, old-backend, malformed, and first-load error states**
   - **Get there:** Use controlled delayed, unavailable, route-404, malformed, and
     transport/5xx responses → reopen Admin Tools for each state → expand
     `SYSTEM HEALTH`.
   - **Verify:** Each state panel or retry action replaces the normal body inside the
     expanded section. The header stays between the same neighboring sections, and
     loading/error content does not cover, replace, or move `CONFIG`. Collapsing the
     section hides its state body without removing the header.
5. **Stale-after-refresh-failure state**
   - **Get there:** Load valid system-health data → expand `SYSTEM HEALTH` → make the
     next request fail → use the inner refresh action, then repeat with the app-bar
     refresh.
   - **Verify:** Previously loaded rows remain in their original positions inside
     `SYSTEM HEALTH`, with stale/error metadata and retry affordance contained in
     that section. No duplicate status plate, process rows, or second
     `SYSTEM HEALTH` section appears.
6. **Narrow and large-text placement**
   - **Get there:** On the narrowest supported iPhone and Android phone, enable the
     largest supported accessibility text size → Admin Tools → expand
     `SYSTEM HEALTH`.
   - **Verify:** Process rows and endpoint rows wrap vertically within the board;
     nothing requires horizontal scrolling, clips outside the board, overlaps the
     section header, or spills into `CONFIG`.
7. **Complete failure-history placement — iOS and Android**
   - **Get there:** On each platform, expand `SYSTEM HEALTH` using a controlled
     response with complete history.
   - **Verify:** `REQUEST FAILURE RATE` appears exactly once after `POOL NOW` and the
     60-minute health summary. Cards remain ordered `60 MIN`, `24 HOURS`, `7 DAYS`.
     Each card contains its request/server failure rows, three endpoint rows, and
     `TELEMETRY COMPLETE`; nothing escapes into `CONFIG`.
8. **Collecting coverage placement**
   - **Get there:** Use incomplete 60-minute, 24-hour, and 7-day history.
   - **Verify:** Each card says `TELEMETRY COLLECTING — X OF Y MINUTES`, where X is
     complete-emission minutes only; partial minutes appear separately and rates say
     `OBSERVED TELEMETRY`. Values never shift into a neighboring card.
9. **Independent pool/history availability**
   - **Get there:** Test valid pool/unavailable history and unavailable pool/valid
     history responses.
   - **Verify:** Only the unavailable subsection changes. Valid content keeps its
     position; the `SYSTEM HEALTH` header and `CONFIG` placement do not move.
10. **No-request and partial-history cards**
    - **Get there:** Use zero-request and partial-history windows.
    - **Verify:** `NO REQUESTS` stays in the affected rate position. Cards remain in
      fixed order and retain endpoint positions despite missing traffic/coverage.
11. **Tall content on narrow phones**
    - **Get there:** Use the narrowest supported iPhone/Android and largest text with
      all three cards populated.
    - **Verify:** Cards stack vertically, rows wrap without horizontal scrolling or
      overlap, and the page scroll reaches `CONFIG` immediately after the complete
      `SYSTEM HEALTH` section.

Surfaces confirmed unaffected: demo race tutorial, tab tutorial previews,
onboarding, and non-admin Settings do not render Admin Tools. The Settings ADMIN
section remains only the navigation entry.

History-specific placement risks: card order must be fixed independently of API
order; pool/history errors must not replace the whole section; top-level and
per-window collecting labels must remain distinct; zero-request cards must not be
removed; and the materially taller content must use the existing vertical page
scroll rather than nested horizontal layouts.

## Revision log

- **2026-08-29 — Draft 1:** Split owner-approved telemetry/admin work from deferred
  pool sizing and transaction optimization; defined exact metrics, privacy, bounded
  Redis transport, admin API, both Admin layouts, failure states, tests, and rollout.
- **2026-08-29 — Gap pass 1:** Corrected cross-minute percentile aggregation and
  made reload-overlap snapshot writes atomic/newer-wins; defined bounded failure
  classifications and logging-retention expectations.
- **2026-08-29 — Gap pass 2:** Defined deterministic health thresholds, bounded the
  API response, fixed screen-refresh isolation/order, and clarified stale/partial
  collection and Redis failure behavior.
- **2026-08-29 — UI-placement review:** Locked both branch insertion points, kept
  iOS system health independent of existing metrics availability, and added the
  manual placement/state/accessibility checklist verbatim.
- **2026-08-29 — Architect revision:** Adopted versioned cache keys, boot-aware
  atomic ordering, honest history coverage/collecting state, required-zero and
  physical-timeout fields, explicit invariant validation, sampled-phase disclosure,
  and the injected post-refactor Admin query-module contract. Documented why this
  permanent operational transport has no release flag.
- **2026-08-29 — Architect approval:** Final focused telemetry/Admin design approved
  with no required changes or suggestions after contract-precision revisions.
- **2026-08-29 — Owner history revision:** Added restart-safe/deduplicated hourly
  Redis outcome aggregates and rolling 60-minute, 24-hour, and 7-day request/server
  failure percentages. Incomplete windows remain visible as observed data and are
  explicitly labeled `COLLECTING` with exact coverage.
- **2026-08-29 — History gap pass 1:** Replaced restart-local history with atomic
  emission-deduplicated UTC-hour hashes, bounded retention/reads, and a renewable
  first-collection sentinel; defined PM2 overlap and Redis-outage behavior.
- **2026-08-29 — History gap pass 2:** Separated request versus server failure
  numerators, defined zero-denominator and exact coverage semantics, made pool and
  history availability independent, and added exact API/UI/test contracts.
- **2026-08-29 — History specialist reviews:** UI placement checklist expanded for
  all three windows and independent error states. Architect approved the per-minute,
  restart-safe bounded design with no remaining changes or suggestions.
- **2026-08-29 — Implementation size correction:** Raised the permanent snapshot
  bound from 64 KiB to 512 KiB after the original bound retained only ~22 minutes
  and a fully populated 60-bucket fixture measured 270,258 bytes. Kept schema v1
  unchanged for rolling compatibility and required a deterministic 419,430-byte
  maximum gate, no eviction, and 60-minute coverage. Four snapshots/Admin `MGET`
  remain bounded to approximately 2 MiB.
