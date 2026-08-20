# Production-shaped k6 operator

The supported workflow is one guided command:

```sh
k6/operator.zsh run
```

It performs current read-only discovery, including the latest backend
`origin/main`, live production topology/configuration metadata, and the exact
rolling seven-day production nginx mix. It then prints the full proposed run
and requires the operator to type `RUN`. No previous approval or remembered VM
configuration bypasses this gate.

After approval it creates separate production-shaped Lima application and
database VMs, captures the production `.env` byte-for-byte as protected
evidence, immediately rechecks material production drift (and forces discovery
plus confirmation again if it changed), builds a separate isolation environment,
takes a read-only production backup while polling and aborting on source load,
restores production PostgreSQL settings and PgBouncer telemetry where available,
and removes notification identities/delivery/queue
state, inflates 10,000 capacity-only identities with one-to-five active races,
starts nginx and two PM2 backend workers with database pools of 20, and ramps
the newly derived route mix from 50 RPS by 10 RPS per passing level. Each level
has a 30-second warm-up and three-minute measurement. A failed level repeats
once; there is no RPS cap, but the complete workflow has an eight-hour deadline.
The deadline starts when the run is created. The deployed rolling-week client
version/platform/capability manifest must be present in the privacy-safe nginx
log; local source is never substituted. Those observed values are used
identically by the canary and k6, and a
static full-envelope check proves step totals remain monotonic and integer-safe.

The operator observes HTTP, per-route latency/errors, achieved rate, VU
saturation, queue state/drain, database pressure, and workers. It retains a
redacted diagnosis and cleanup receipt, then destroys both VMs and every
run-scoped backup, environment, token, and credential.

## Recovery commands

```sh
k6/operator.zsh status
k6/operator.zsh resume
k6/operator.zsh cleanup
```

`resume` revalidates permanent device/push invariants but never clears queue
evidence after traffic has begun. It also restores and hashes the effective
environment and identity file, revalidates the archived commit marker, and
repeats inspect/canary/two-worker checks. `cleanup` targets only the
active run's exact VM names and in-VM markers and refuses to destroy the only
diagnostic evidence unless `K6_FORCE_CLEANUP=1` accompanies an explicit cleanup
command.

Run state is stored outside the repository under
`~/.stepv2-k6-operator` by default. `K6_OPERATOR_STATE_ROOT` may select another
protected host directory. Machine-specific discovery normally comes from
`CLAUDE.local.md`; `K6_BACKEND_REPO`, `K6_PROD_SSH`, and `K6_PG_BIN_DIR` are
session-only recovery overrides. Never commit those values.

The older fixture runner and its modules remain only because a protected test
suite imports them. They are not a supported workflow. See
`k6/legacy-inventory.md` for the exact retention/deletion classification and
`docs/k6-operator-workflow-requirements.md` for the authoritative contract.
