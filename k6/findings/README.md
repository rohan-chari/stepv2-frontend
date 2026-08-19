# Capacity findings

Keep one dated document per decision-worthy optimization-1 campaign. Routine
one-command runs save their complete private output under
`~/.local/share/stepv2-capacity/runs/`; copy only aggregate, secret-free results
into this directory when they change a decision.

| Date | Campaign | Result |
|---|---|---|
| 2026-08-18 | [Optimization 1 matched aggressive comparison](2026-08-18-experiment1-aggressive-result.md) | **HOLD/default-off:** the corrected 160-RPS pair made HTTP p95 85% slower and critical-write p95 219% slower, with no backlog/drain improvement. Earlier wins and breakpoint claims were invalid. |

Use [TEMPLATE.md](TEMPLATE.md) for any future retained finding. Never include
tokens, connection strings, raw production identifiers, `.env` contents or
unsanitized database material.
