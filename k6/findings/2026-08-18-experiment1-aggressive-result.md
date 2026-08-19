# 2026-08-18 — Optimization 1 queued-generation diagnostic

## Decision

**HOLD; default OFF.** Queued-generation merging has not shown a capacity or
queue-drain benefit and is not approved for deployment.

The first apparent wins were invalid because OFF and ON selected different
random requests and crossed different cron activity. A later deterministic
pair still included the first seconds of process/cache warm-up. Review of its
raw samples found:

- reported whole-run HTTP p95: 37.1 ms OFF / 47.7 ms ON;
- after excluding the first five seconds: approximately 27.5 / 28.4 ms;
- after excluding the first five seconds, critical-write p95: approximately
  66.5 / 67.4 ms;
- post-k6 backlog (after k6 teardown): 105 / 105 jobs;
- global drain: 36 / 35 seconds.

After the runner was made local-secret-independent and the flag was propagated
to all three step-upload paths, a new 160-RPS pair strongly reinforced the
negative result:

| Steady-state metric | OFF | ON |
|---|---:|---:|
| HTTP p95 / p99 | 48.4 / 103.9 ms | 89.7 / 297.8 ms |
| Critical-write p95 / p99 | 108.7 / 187.1 ms | 346.7 / 768.1 ms |
| `steps_sync_v2` p95 | 135.0 ms | 464.4 ms |
| Post-k6 backlog (after k6 teardown) | 82 | 84 |
| Global drain | 25 s | 26 s |

Both halves had zero hard/capacity/429/dropped/fallback failures, and both k6
processes exited 99 because the strict resolution-lag threshold failed. ON was
slower and did not improve backlog or drain.

The flag still takes the same conflict-row lock and performs the same JSON work;
the existing one-row-per-race queue already coalesces pre-claim generation bumps
into one worker execution. There is therefore no demonstrated DAU improvement.

## Provenance and limitations

- Corpus SHA-256:
  `efb60729d60dd72ec8532156b1cc8e1ae041147f290d68ab5f5c087e025a4d3e`
- Fixture: `capacity-fixture-v1:a75bcee0`
- Topology: 2 vCPU, 2 GiB, two Node workers, PgBouncer pool 25
- Latest private retained pair:
  `~/.local/share/stepv2-capacity/runs/optimization1-20260818T231028Z-160rps`
- This was one fixed-order diagnostic, not a counterbalanced cohort or DAU
  certification.
- Its response-time warm-up cutoff produced one unequal steady endpoint sample
  (183 OFF / 182 ON for sync-v2). The current runner instead tags warm-up by
  offered-arrival number and rejects unequal steady counts, so this retained
  pair is directional evidence rather than a final matched artifact.
- Historical 90/160/260 numbers produced before deterministic pairing are
  invalid for optimization or breakpoint attribution and are intentionally not
  repeated here.

The current one-command runner fixes request randomness and logical timestamps,
tags the first five seconds' worth of offered arrivals as warm-up, isolates
HTTP/race-resolution scheduling, and always reports diagnostic-only. No deploy,
staging mutation or production mutation was performed.
