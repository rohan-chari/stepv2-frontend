---
name: k6-operator
description: Run or manage the production-shaped k6 capacity workflow when the user says "do a k6 run", asks for a capacity/load test, or asks to resume, inspect, or clean up such a run. Do not use for ordinary app tests or production traffic generation.
---

# K6 operator

Use the named `k6-operator` project agent for this workflow. It must read
`docs/k6-operator-workflow-requirements.md` and use only the public CLI:

```text
k6/operator.zsh run|status|resume|cleanup
```

For a new run, invoke `run` in an interactive PTY. The CLI performs read-only discovery and displays
the freshly resolved droplet, database, worker/pool, backend commit, rolling
seven-day route mix, data, safety, and cleanup plan. Leave its mandatory
interactive `RUN` confirmation to the user; do not answer it for them or reuse
an approval from an earlier run.

After approval, let the operator own provisioning, production input acquisition,
restore, sanitization, inflation, load, drain, reporting, and targeted cleanup.
Do not reconstruct phases with manual SSH/Lima/PostgreSQL/k6 commands and do not
use the private legacy compatibility runner.

If interrupted, use `status`, then `resume`. Use `cleanup` only for the active
run recorded by the host state machine. Report the retained redacted report and
cleanup receipt paths. Never expose protected state, environment contents,
database credentials, backups, tokens, production host addresses, or raw access
logs in conversation.
