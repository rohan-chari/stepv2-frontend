# YYYY-MM-DD — campaign name

## Authorization and question

- Owner approval:
- Question being answered:
- Explicitly out of scope:

## Immutable inputs

- Environment/base URL:
- Backend commit:
- Frontend/harness commit:
- Released client cohort:
- Flags/config:
- CPU/RAM/architecture:
- PM2 workers and cron owner:
- Node/PM2 versions:
- PostgreSQL/PgBouncer mode and pool:
- Redis topology/state:
- Fixture revision and counts:
- Sanitized corpus SHA-256:
- DAU evidence window/coefficient, if used:

## Protocol

- Cold/warm process and Redis state:
- Cron cohort/timestamps:
- Rungs/repeats:
- Telemetry/profilers enabled:
- Differences from the runbook:

## Results

| Run ID | Rung | Iterations | Drops | Failures / 429s | p95 / p99 | Persistence p95 / p99 / max | Resolution max/outstanding | Worker peak RSS | Minimum available RAM | Verdict |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| | | | | | | | | | | |

Endpoint tails/hot paths:

Server/query/pool/Redis/cron evidence:

## Incidents and recovery

Record every abort, OOM, restart, health failure, queue backlog or manual recovery.
Write `none` when there was no incident.

## Conclusions and limitations

- What the evidence supports:
- What it does not support:
- Bottlenecks/hypotheses:
- Next decision:

## Artifacts

Private artifact paths and SHA-256 values (never commit tokens/raw streams):

## Teardown

- Shutdown timestamp:
- Lima status:
- HTTP/PgBouncer/PostgreSQL listeners absent:
- Matching background processes absent:
