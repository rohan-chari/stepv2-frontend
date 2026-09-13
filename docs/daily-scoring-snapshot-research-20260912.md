# Daily scoring snapshot feasibility

Research date: September 12, 2026. Source: backend worktree at b20ad0b. Read-only code research; no schema, scoring, runtime, or production changes. This is a feasibility report, not an approved implementation specification. No performance savings are claimed without a prototype and measurements.

## Finding

Reuse of unchanged historical calculations is feasible in principle, but storing one final point total per participant/day and summing those totals is not equivalent to current scoring. Earlier conversational examples of Monday=3000 as a final independent row were oversimplified. Store reusable components and effect-window calculations, then preserve the canonical race-wide combination rules. A full general checkpoint that resumes all scoring from midnight requires more state than a daily total.

## Current behavior and dependencies

- Base steps already have daily structure: raceSteps.js:19,33,49 uses participant/scoring timezone boundaries and takes max(sample sum,daily total) per covered day. raceStateResolution.js:162 treats partial joining/start days and end cutoffs specially. UTC 24-hour buckets alone would change local-day/DST semantics.
- raceStateResolution.js:198 selects precise-sample versus fallback effect scoring based on sample presence across the entire race. A newly received first sample can invalidate interpretations beyond its own day.
- raceStateResolution.js:222 clamps the combined pre-Leech race total at zero. Daily clamping is not equivalent: signed contributions +100 Monday and -150 Tuesday yield max(0,-50)=0, whereas independently clamped daily totals sum to 100. BonusSteps is a separate race-level input and must not be inserted into every day.
- leechTransfers.js:32,79,119 computes earned transfer per effect, then caps actual transfer by the victim’s cumulative race balance in deterministic effect order. Example using already-computed earnedTransfer=500: victim balance Monday=100 permits transfer100; adding1000 on Tuesday permits transfer500 even with unchanged Monday source inputs. Updating one day can therefore change another participant’s current result. Splitting per-effect floor rounding across midnight also changes results.
- hitchhikeCopies.js:164–206 includes target step windows, target modifiers and global events. Versioned behavior and v3 durable attribution capture must be preserved; powerups/models/hitchhikeAttributionCapture.js:140 treats frozen capture as terminal. Daily caches must not reopen that capture.
- effectiveStepScoring.js has per-window rounding and whole-score floors; independent day rounding is unsafe. Preserve unrounded intermediate contributions/whole-effect accumulators and existing final rounding locations. Exact floating-point ordering requires parity tests, not an assumption of mathematical additivity.
- raceExpiry.js:571 reconstructs reachedSnapshot from chronological samples and powerup events for settlement tie-breaking. End-of-day totals do not retain within-day timing. First implementation should retain canonical settlement replay and raw history until settlement is complete.

## Invalidation gap

stepSample.js:327–396 compares stored/replacement intervals and detects scoring changes; scoringInputVersion.js:202–239 advances a user-wide generation. It does not persist a per-day/per-interval change version. Reusing that global version for daily snapshot keys would invalidate Monday on every Friday update and defeat the proposal.

Introduce bounded interval/day invalidation atomically with authoritative writes, covering BOTH old and new intervals (including overlap deletions and samples spanning midnight). Daily totals, deletions, join/forfeit/finish boundaries, timezone changes, effect metadata/status, global-event revisions, and cross-user dependency inputs also matter. Changes that cannot be localized safely must invalidate the broader result and use canonical replay. Metadata-only changes should not unnecessarily invalidate scoring. Existing source-generation/commit fences remain mandatory.

## Recommended scope

1. Persist reusable local scoring components for completed day windows, with explicit UTC bounds, timezone, scoring schema/version, input revisions, coverage, and sufficient precision/mode provenance. Do not label these rows independent final race scores.
2. Recompute only dirty local windows where the scoring algorithm supports it. Store reusable per-effect window contributions separately where necessary to preserve rounding boundaries and target dependencies. Continue using the canonical whole-race Leech/Hitchhike/bonus/clamp combination.
3. Keep current-day work incremental and batch snapshot reads/writes. Mark dirty versions as part of sync, then let race workers rebuild; avoid writing a snapshot for every race/day on every HTTP request. Coalesce repeated dirty work. A Friday correction may rebuild Monday local components and also update dependent participants; do not promise strictly one-row repair.
4. Keep PostgreSQL authoritative. Missing/stale/unsupported snapshot falls back to canonical calculation. Redis or memory can cache the durable derived rows but is optional. Rebuilds must use revision fences so an older calculation cannot overwrite a newer snapshot.
5. Keep canonical settlement replay in the first scope. This preserves time-based tie-breaking and avoids requiring a full resumable scoring-state design immediately. No API change is needed for old iOS/Android clients.

## Retention

completeRace.js:240 sets status COMPLETED before all payout/referral/artifact work is done. finalizeSettlement():95 stamps settlementCompletedAt later. Cleanup must require this durable marker plus confirmation that dependent jobs cannot still need the snapshots, and must prevent stale workers from recreating deleted rows. Batch deletion by race under existing ownership rules. Retain final results, payout facts, durable attribution captures and any still-needed raw records. Snapshot deletion alone does not authorize deleting these other records. The exact job-terminal predicate remains a design task.

## Validation before implementation

Use the existing scorer as the oracle. Verify cold/warm daily components and fresh replay produce identical API scores and settlement outcomes for: unchanged resync; previous-day correction; old/new overlapping windows; cross-midnight boosts; DST/timezone changes; partial race starts/ends; negative scores and cumulative floors; per-effect rounding; multiple ordered Leech transfers; Hitchhike versions/frozen captures; first precise sample arriving late; concurrent sync during rebuild; no-op sync; day rollover; settlement retries; cleanup versus in-flight rebuild. Performance cases should cover thousands of simultaneous syncs and count downstream reads/writes, not just request latency.

## Relation to current database hotspots

The twenty-minute watch measured event fingerprint queries56.5s, sample writes33.4s and sample reads21.4s. Daily calculation reuse does not automatically remove fingerprint freshness checks or sample ingestion writes. It may reduce sample loading and repeated calculation; improvement to the largest fingerprint category requires a separate safe proof/cache optimization. Durable snapshots add writes/storage and invalidation work, so compare total cost before committing to this larger change.

## Decision

Proceed to a detailed specification only for reusable daily components plus preserved canonical final combination, not summed daily final totals. Determine enough per-effect state and invalidation coverage before choosing columns or promising that historical work disappears. Alternative smaller path remains correcting shared fingerprint-cache coverage and measuring misses; that is independently useful and substantially narrower.

## Independent scoring review

Game-analyst review: sound with changes, not as independent daily final scores. Additional exact constraints: stepSample.js:605 rounds overlapping sample contributions at the original requested-window boundary. One step split evenly over midnight can become round(0.5)+round(0.5)=2 instead of1. Retaining unrounded day totals alone is insufficient; preserve original sample/window rounding boundaries or retain boundary-spanning records for canonical evaluation. Leech floors once per whole effect (two single-step day pieces at ratio2 yield1 together but0 if separately floored). These examples demonstrate semantic errors, not proposed game-balance changes.

Hitchhike v3 already returns frozen durable contributions via hitchhikeCopies.js:143; reuse that existing state. Time advancing across closed-hour/sample/effect boundaries can invalidate results without any data write, so revisions need validity horizons. Existing incremental Leech transfer state can re-evaluate a victim’s ordered list without recomputing all sample windows. Intended economy/score impact is exactly zero; incorrect daily floors or midnight rounding can alter standings and payouts.
