# Local production-shaped k6 runbook

This is the supported local capacity workflow. It compares only optimization 1,
queued-generation merging, with the flag OFF and ON on the same backend source.
The default is a direct matched 160-RPS test—no staircase and no repeated manual
startup/teardown commands.

## Normal run: one command

From the frontend repository:

```bash
k6/local-prod-sim/run-optimization1-comparison.zsh
```

Optional 260-RPS breakpoint probe:

```bash
RPS=260 k6/local-prod-sim/run-optimization1-comparison.zsh
```

The command automatically:

1. packages only Git-visible runtime source (`src`, Prisma schema/migrations and
   package manifests); ignored/local/key/env files cannot enter the artifact;
2. installs it at a source-hash-specific path inside the private Lima VM;
3. starts the dedicated PostgreSQL cluster and the 2-vCPU/2-GiB VM;
4. restores and validates the sanitized corpus before each variant;
5. runs two Node workers behind PgBouncer pool 25;
6. starts only HTTP plus the race-resolution workers (all unrelated scheduled
   jobs are disabled), fixes one logical timestamp for both halves, then runs
   optimization 1 OFF and ON at the requested rate;
7. checks exact worker executable paths, restarts, failures, drops and queue drain;
8. writes a dated comparison under
   `~/.local/share/stepv2-capacity/runs/`; and
9. stops PM2, Lima, PgBouncer and the dedicated PostgreSQL cluster through an
   exit trap, including when a command fails.

Expected elapsed time is approximately five minutes when the private environment
already exists. The first run after a dependency-lock change may take longer for
`npm ci`.

## One-time private setup

Install host tools:

```bash
brew install lima k6 postgresql@18 pgbouncer jq
```

Create a private root and PostgreSQL cluster:

```bash
export CAPACITY_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/stepv2-capacity"
export CAPACITY_PG_BIN="$(brew --prefix postgresql@18)/bin"
umask 077
mkdir -p "$CAPACITY_ROOT"
chmod 700 "$CAPACITY_ROOT"
test -f "$CAPACITY_ROOT/postgres18/PG_VERSION" || \
  "$CAPACITY_PG_BIN/initdb" -D "$CAPACITY_ROOT/postgres18"
```

The Lima instance must be named `stepv2-prod-sim` and configured with:

```yaml
arch: aarch64
vmType: vz
cpus: 2
memory: 2GiB
disk: 20GiB
mounts: null
containerd:
  user: false
  system: false
portForwards:
  - guestPort: 8080
    hostPort: 3302
    static: true
```

The VM needs Node 24.13.0, PM2 6.0.14, nginx, Redis and PostgreSQL client tools.
The runner supplies only local dummy/runtime values directly to PM2. It neither
copies nor reads a backend `.env`, service-account file, signing key or token.

PgBouncer configuration remains private at
`$CAPACITY_ROOT/pgbouncer.ini`, listening only on `127.0.0.1:56432` with a
transaction pool of 25 and connecting to the dedicated host PostgreSQL port
55432. The backend's private local `DATABASE_URL` uses
`host.lima.internal:56432`.

## Corpus and fixture

The normal command never connects to production. It requires these private,
sanitized inputs:

```text
$CAPACITY_ROOT/sanitized-benchmark-20260818-v2.dump
$CAPACITY_ROOT/users-20260818-v2.json
```

Current expected revisions:

- corpus SHA-256:
  `efb60729d60dd72ec8532156b1cc8e1ae041147f290d68ab5f5c087e025a4d3e`
- fixture revision: `capacity-fixture-v1:a75bcee0`

Refreshing from production is intentionally not part of the one-command test.
It requires separate, in-the-moment authorization and read-only credentials.
Export the dump directly into `$CAPACITY_ROOT`, restore it only into the
dedicated local database, run `sanitize.sql`, then run
`validate-sanitization.sql`. Never place a dump, token, connection string or
`.env` in either repository. Re-mint fixture tokens only against the sanitized
local database using `STAGING_DATABASE_URL`; never reuse production tokens.

## Reading the result

Each dated run directory contains `result.md`, the OFF/ON summary JSON, raw k6
samples, logs, worker provenance, post-k6 backlog and drain time. The summary
excludes the first five seconds' worth of deterministically tagged offered
arrivals as warm-up and always labels the pair
`DIAGNOSTIC ONLY`. It never auto-approves an optimization. Missing metrics,
endpoint mismatches or mismatched inputs make summarization fail closed.

A local result is diagnostic, not a production deployment approval or a
certified DAU ceiling. The separate resolution-lag threshold may still make k6
exit 99; the result and logs keep that visible instead of hiding it.

## Verify teardown

The runner does this automatically. If interrupted by a machine failure, verify:

```bash
limactl list stepv2-prod-sim
! lsof -nP -iTCP:3302 -iTCP:56432 -iTCP:55432 -sTCP:LISTEN
! "$(brew --prefix postgresql@18)/bin/pg_ctl" \
  -D "${XDG_DATA_HOME:-$HOME/.local/share}/stepv2-capacity/postgres18" status
```

Lima must say `Stopped`; all three ports and the dedicated PostgreSQL cluster
must be stopped.
