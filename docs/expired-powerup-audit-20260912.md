# Expired powerup scoring audit

September 12, 2026. Research-only code review of backend b20ad0b and SELECT-only production aggregates around20:09–20:10UTC. No scoring/config/data changes. User-authorized next work is Leech expiry correction and historical caching, but user requested other-powerup findings first.

## Confirmed Leech defect against clarified intent

leechTransfers.js clips earned transfer to the source effect window, but applies actual drain to the victim’s current whole-race pre-Leech balance on each replay. Later steps can therefore increase an expired effect’s actual transfer. User clarified that unused capacity is lost at expiry.41 expired Leech rows exist in current active races, all metadata ratio2; this count is not a count of demonstrated incorrect scores. Need durable finalized actual transfers and careful active-to-expired transition, deterministic multi-Leech ordering, retries and settlement parity. Historical repair policy requires a separate decision because past actual drain at expiry cannot be inferred merely from today’s balance.

## Hitchhike differs

hitchhikeCopies.js clamps input windows to effect expiry. Version3 reads an existing frozen effective contribution before replaying source data; hitchhike_attribution_captures.frozen_at is terminal. Production active races contain99 expired Hitchhike rows, all version3, all99 frozen. No evidence of the Leech-style growing copied amount from future target steps. Older versions may change for legitimate late in-window data; do not conflate this with copying post-expiry steps.

Signed Hitchhike contributions can be negative. The final max(0,ownTotal+fixedCopy) means a fixed negative historical contribution can absorb later own points; the copied amount remains fixed. This is a cumulative score-floor policy question, not the same expiry-window bug. Do not silently change it as part of Leech repair.

## Conditional no-sample fallback risk

effectiveStepScoring.js uses current rawTotal when an EXPIRED timed modifier lacks metadata.stepsAtExpiry. Reachable fallback branches include Leg Cramp/Quicksand, Runner’s High, Campfire’s rest phase, Rainstorm, Uprising, Rally Flag and Coin Flip. Precise sample scoring uses timestamped windows and clips effects at expiry instead. Need independently verify malformed/legacy metadata and fallback entry before treating a record as impacted.

Active-race production counts: Leg Cramp1084 expired /6 missing expiry snapshot; Runner’s High590/0; Rainstorm97/0; Rally Flag253/0; no retained expired rows for the other queried types. All six missing-snapshot Leg Cramp rows have timestamped step samples within the current race/join window, so the audit does not demonstrate current fallback scoring corruption for them. Existence of samples is a coverage probe, not proof of full scoring equivalence.

## Scope and next steps

Fix Leech’s finalized actual transfer semantics first with integration coverage for victim steps after expiry, source steps after expiry, late in-window data, concurrent expiry/sync, multiple ordered leeches, crashes/retries and settlement. Preserve older clients and zero-sum accounting; no new economy numbers. Decide whether late pre-expiry corrections may change a finalized transfer and how to handle existing expired rows before release. Audit fallback missing-expiry handling as a distinct hardening concern. Do not redesign signed floors or other powerups merely to simplify caching.

Historical cache work follows the scoring fix. Frozen Leech/Hitchhike contributions reduce cross-day replay needs but do not by themselves solve sample rounding, daily-total corrections, fallback mode transitions, event versions or settlement chronology. No deployment or cache implementation is included in this report.
