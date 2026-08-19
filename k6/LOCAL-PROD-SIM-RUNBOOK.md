# Daily local production-shaped k6 runbook

This is the supported capacity workflow. It runs one adaptive checkpoint
against a sanitized local environment using pinned fetched-main source and a
single validated snapshot of production-effective flags. It never sends load,
writes, migrations, flag changes, or deploys to production or staging.

## Daily command

From the frontend repository:

```bash
k6/local-prod-sim/run-daily-capacity-diagnostic.zsh
```

The command tests `150,250,350,…,950` RPS over successive invocations. A pass
advances on the next invocation; a breaking or invalid result retries the same
rung. `RPS_OVERRIDE` accepts only those standard values, labels the invocation
nonstandard, and cannot change the standard ladder.

Private machine configuration supplies the production read target:

```bash
export PROD_SSH_TARGET=your-verified-ssh-alias
export PROD_BACKEND_DIR=/absolute/deployed/backend/path
```

The SSH target may be an alias or `user@host` containing only letters, digits,
dots, underscores, and hyphens. The backend path must be an absolute POSIX path
with no `..` segment. Values are positional arguments to a fixed helper; they
are never evaluated as shell text. SSH uses batch mode, strict host-key
checking, connection/command timeouts, and stdin delivery.

The remote helper proves before and after the DB read that:

- the deployed `.env` is a regular non-symlink whose in-memory hash and mtime
  did not change;
- `HEAD` and the allowlisted runtime tree are clean and unchanged;
- exactly two `steps-tracker` workers, instances 0 and 1, are online with the
  expected cwd and executable;
- PM2 revision metadata matches `HEAD`, or worker uptime is strictly newer than
  both the HEAD reflog and every tracked runtime mtime; and
- both workers resolve the same required five boolean and two bounded integer
  v1 mappings after PM2-over-dotenv precedence; later deployed-only mappings
  are retained as provenance and never inserted into fetched-main locally.

It reads DB-backed flags inside a Prisma interactive transaction whose first
statement is `SET TRANSACTION READ ONLY`. Exactly one redacted versioned JSON
line crosses SSH. Raw stderr, `.env`, the DB URL, full PM2 env, raw settings
rows, and tokens are never copied or stored.

## One-time local setup

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

The VM needs the pinned Node/PM2 versions, nginx, Redis, and PostgreSQL client
tools. PgBouncer configuration remains private at
`$CAPACITY_ROOT/pgbouncer.ini`, listens only on `127.0.0.1:56432`, uses a
transaction pool of 25, and connects to dedicated PostgreSQL port 55432.

## Corpus and fixture

The daily command requires these private sanitized inputs:

```text
$CAPACITY_ROOT/sanitized-benchmark-20260818-v2.dump
$CAPACITY_ROOT/users-20260818-v2.json
```

Pinned identities:

- corpus SHA-256:
  `efb60729d60dd72ec8532156b1cc8e1ae041147f290d68ab5f5c087e025a4d3e`
- fixture revision: `capacity-fixture-v1:a75bcee0`

Refreshing the corpus is intentionally outside the daily command and requires
separate, in-the-moment authorization. Never place a dump, credential, token,
connection string, or `.env` in either repository.

## What each invocation does

1. Creates the private run directory, acquires an identity-bearing shared lock,
   writes atomic preliminary/recovery results, parses the bounded README log,
   and stores a bounded fallback selection so pre-measurement failures can
   still produce an invalid daily row and private Markdown recovery row.
2. Starts Lima, measures and rejects drift in CPU, memory, guest architecture,
   host forwarding, every effective nginx 8080 route, and the effective
   PgBouncer database mapping. It fingerprints those observations and replaces
   the fallback with the actual adaptive selection before source/SSH/DB work.
3. Runs `git fetch origin main`, resolves `FETCH_HEAD^{commit}` once, and
   archives only `package.json`, `package-lock.json`, `prisma.config.ts`,
   `src`, and `prisma` directly from that object. Dirty worktree files and
   `origin/main` are not inputs.
4. Captures one production snapshot, extracts fetched-main defaults from the
   artifact, reconciles registry drift, and stores the private canonical
   snapshot hash.
5. Freshly restores the corpus, applies fetched-main migrations using only the
   constructed local DB URL, replaces local settings through parameterized
   Prisma calls, writes the observability override separately, and remints and
   verifies local sessions against the same artifact.
6. Starts PgBouncer pool 25, live-verifies the dedicated database/server
   address/server port, starts empty Redis and exactly two PM2 workers, then
   proves host-forwarded, nginx, and direct-worker health are identical. A real
   authenticated `/auth/me` preflight must pass before traffic.
7. Runs one 35-second checkpoint and records raw k6 data, traffic-only HTTP
   samples tagged `warmup`/`steady`, normalized explicit-zero counters,
   host/k6 health, guest memory, deadlocks, run-owned logs, PM2 pre/post
   identity, resolution evidence, and a monotonic 90-second global drain.
8. Classifies only after evidence validation, attempts and verifies every
   cleanup independently, persists final private JSON and Markdown recovery
   state, atomically appends the README row using its selection hash, then
   releases the identity-bearing lock last. A post-append release failure
   atomically corrects the row to invalid where the README remains writable.

Private artifacts live under `~/.local/share/stepv2-capacity/runs/` with atomic
`preliminary-result-v1.json` and `recovery-result-v1.json` records even when
setup fails. Backend artifacts are rebuilt from the pinned archive on both host
and VM for every invocation; no writable cache marker is trusted.

## Interrupted-run and stale-lock recovery

SIGINT and SIGTERM enter the normal two-phase finalizer. SIGKILL or machine
loss cannot. The daily and historical runners share one
`capacity-workflow.lock`; they can never operate the VM/database concurrently.
If that lock remains, first inspect its owner:

```bash
CAPACITY_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/stepv2-capacity"
cat "$CAPACITY_ROOT/capacity-workflow.lock/owner"
ps -p "$(sed -n 's/^pid=//p' "$CAPACITY_ROOT/capacity-workflow.lock/owner")" \
  -o pid= -o lstart= -o command=
```

Do not signal or delete anything if the PID and recorded start identity still
match, or if identity is indeterminate. Once the recorded process is proven
gone, repeat the same owned-process and shutdown checks:

```bash
limactl stop stepv2-prod-sim
! lsof -nP -iTCP:3302 -iTCP:56432 -iTCP:55432 -sTCP:LISTEN
! "$(brew --prefix postgresql@18)/bin/pg_ctl" \
  -D "$CAPACITY_ROOT/postgres18" status
```

Inspect `pgbouncer.owner` and verify both its recorded start time and command
before signaling that PID. Remove the stale lock only after Lima is stopped,
the owned PgBouncer process is absent, PostgreSQL is stopped, and all three
ports have no listener.

Normal finalization atomically moves the entire lock directory into the private
run as `released-capacity-lock`, preserving its owner identity while removing
the live lock path. A release failure leaves the owner file in place and
corrects an appended row to invalid when safe.

## Historical tooling

`run-optimization1-comparison.zsh` and its finding remain for provenance only.
They are not the supported daily command, do not append to the daily machine
log, and never seed adaptive state.
