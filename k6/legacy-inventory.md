# K6 workflow inventory

This inventory is the deletion gate required by
`docs/k6-operator-workflow-requirements.md`. The supported public surface is
only `k6/operator.zsh` plus the `k6-operator` skill and agent.

| Item | Classification | Replacement or retention reason |
| --- | --- | --- |
| `k6/operator.zsh` | Retained public entry point | `run`, `status`, `resume`, and `cleanup` |
| `k6/README.md` | Retained operations documentation | Documents only the public operator and recovery commands |
| `docs/k6-operator-workflow-requirements.md` | Retained current requirements | Approved authoritative workflow contract |
| `.agents/skills/k6-operator/SKILL.md` | Retained routing skill | Routes natural-language requests to the named agent and public CLI |
| `.codex/agents/k6-operator.toml` | Retained named operator | Executes and monitors the stateful workflow without conversational memory |
| `k6/internal/operator.mjs` | Retained private module | Atomic lifecycle, safety gates, adaptive ramp, report, cleanup |
| `k6/internal/operator-load.js` | Retained private module | Dynamic rolling-week route mix executor |
| `k6/internal/request-builders.js` | Retained private module | Registry-owned canonical request construction without legacy fixture coupling |
| `k6/internal/traffic.mjs` | Retained private module | Privacy-preserving seven-day nginx derivation |
| `k6/internal/route-registry.v1.json` | Retained private contract | Versioned replayable route registry |
| `k6/internal/state.mjs` | Retained private module | Atomic run and phase state |
| `k6/internal/self-validate.mjs` | Retained private safety module | Non-test proof of monotonic step values across the conservative full eight-hour envelope |
| `k6/internal/child-watchdog.mjs` | Retained private safety module | Applies remaining-deadline TERM/KILL bounds to synchronous child commands |
| `k6/capacity-contract.mjs` | Private compatibility support | Imported by the protected capacity contract test only |
| `k6/capacity-test.js` | Private compatibility support | Read by the protected capacity contract test |
| `k6/prepare-fixture.mjs` | Private compatibility support | Imported/executed by the protected capacity contract test |
| `k6/queue-observer.mjs` | Private compatibility support | Imported/executed by the protected capacity contract test |
| `k6/run-capacity.zsh` | Private compatibility support | Executed by the protected capacity contract test; unsupported for operators |
| `k6/fixture.example.json` | Private compatibility support | Read by the protected capacity contract test |
| `k6/test/capacity-contract.test.mjs` | Protected, untouched | Explicitly outside cleanup scope |
| `k6/fixture.json`, `k6/users.json`, `k6/results/` | Deleted after successful rehearsal | Legacy generated artifacts are no longer consumed by the operator |
| `docs/simple-capacity-load-test-requirements.md` | Deleted after successful rehearsal | Superseded by the approved operator requirements |
| `docs/capacity-bottleneck-optimization-requirements.md` | Retained historical decision record | Product/backend optimization history, not an operator workbook |
| `docs/scaling-capacity-plan.md`, `docs/scaling-capacity-plan-v2.md` | Retained historical decision records | Scaling rationale, not competing entry points |
| `~/.stepv2-k6-operator/runs/<run-id>/public/` | Generated retained artifacts | Redacted manifest, summaries, observations, report, and cleanup receipt remain for comparison |
| `~/.stepv2-k6-operator/runs/<run-id>/protected/` | Generated destroy-after-report artifacts | Environment evidence, effective environment, backup, identity credentials, and protected context are removed by targeted cleanup |
| `/opt/stepv2-capacity/` and capacity nginx/PM2/Redis/PostgreSQL data inside the two run VMs | Generated destroy-after-report artifacts | Covered by exact run-marker verification and deletion of both disposable VMs |

## Backend repository

`BACKEND_REPO/` below means the machine-specific backend path configured in
`CLAUDE.local.md`; no absolute developer path is committed.

| Item | Classification | Replacement or retention reason |
| --- | --- | --- |
| `BACKEND_REPO/scripts/perf/capacity-runtime.js` | Retained private operator support | Single guarded JSON helper for inspect, sanitize, inflation, canary, barrier, observation, and report operations |
| `BACKEND_REPO/scripts/perf/capacity-server.js` | Retained private operator support | Fail-closed PM2 entrypoint for the two-worker capacity backend |
| `BACKEND_REPO/scripts/perf/capacity-effective-env.js` | Retained private operator support | Loads only the protected mode-600 effective environment before application imports |
| `BACKEND_REPO/src/localCapacitySafety.js` | Retained private safety contract | Exact run/database/host/auth/outbound marker validation and notification sink |
| `BACKEND_REPO/src/db.js`, `BACKEND_REPO/src/shared/config/performanceFlags.js` | Retained production modules with capacity guards | Preserve the pool-20 production contract and narrowly validated capacity behavior |
| `BACKEND_REPO/scripts/perf/start-local-capacity-cluster.js`, `BACKEND_REPO/src/capacityLocal.js` | Deleted after successful rehearsal | Superseded by PM2 plus `capacity-server.js` |
| `BACKEND_REPO/scripts/perf/clone-active-races-for-capacity.js` | Deleted after successful rehearsal | Superseded by deterministic run-bound `inflate` |
| `BACKEND_REPO/scripts/perf/benchmark.js`, `BACKEND_REPO/scripts/perf/generateFixtures.js` | Retained independent benchmark tooling | Query-optimization benchmark, not a public k6 workflow |
| `BACKEND_REPO/docs/capacity-bottleneck-optimization-plan-2026-08-17.md`, `BACKEND_REPO/docs/capacity-phase-metrics-v1.md` | Retained historical/runtime documentation | Backend optimization and telemetry contracts, not competing operator workbooks |
| `BACKEND_REPO/scripts/extract-capacity-telemetry-evidence.js`, `BACKEND_REPO/src/shared/observability/capacityPhaseMetrics.js`, `BACKEND_REPO/src/shared/observability/capacityTelemetryEvidence.js` | Retained production observability | Runtime instrumentation remains independent of the disposable operator |
| Other tracked `BACKEND_REPO/docs/*performance*`, `src/shared/config/performanceFlags.js`, and `test/**/*{capacity,performance,perfoot}*` items | Retained independent product evidence/config or protected tests | They are not k6 entry points; every automated test remains untouched and outside cleanup scope |

The disposable end-to-end rehearsal completed successfully on 2026-08-20. The
obsolete documentation, pre-operator ignored artifacts, and superseded backend
helpers listed above were removed in the gated cleanup pass.
