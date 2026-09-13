# Race fingerprint/proof investigation — September 11, 2026

Read-only investigation of production revision `83940f9f341f5889e805c59e62693468c41c5dd7`, using the 20:07–20:17 UTC capture and a bounded proof sample at 20:24:03 UTC. No application or production data changes.

## Finding

The cache deliberately rejects event-order ambiguity, which is common in the sampled recent races. The full event SQL orders only by event start and event ID. Multiple participants can have local entitlement rows for the same event/start; those rows tie. The cache refuses to choose a different order because fingerprints digest ordered event arrays. This protects correctness but frequently makes the planning path compute the proof and then run the full event query anyway.

Live sample: distinct race IDs drawn from the 200 most recently updated race-resolution job rows, capped at 50 races. Of 50, 38 had ambiguous eligible ordering, two failed timestamp-precision safety, none exceeded the 8,192-impact bound, and none lacked the catalog revision. Conditions can overlap. This is a current, bounded sample, not a request-weighted cache-miss measurement for the earlier watch. No process-local cache-hit counters were obtained.

## Measured workload

| Query | Ten-minute calls | Execution s | Mean ms | Buffer hits | Disk blocks read |
|---|---:|---:|---:|---:|---:|
| Full event fingerprint | 821 | 14.60 | 17.78 | 748,975 | 148 |
| Race/roster plus event proof | 461 | 14.14 | 30.67 | 313,559 | 246 |
| Cache fill | 18 | 0.095 | 5.28 | 915 | 0 |
| Local cache refresh | 24 | 0.068 | 2.82 | 742 | 0 |

Proof-query time includes the entire race/roster read; it is not incremental proof-only cost. In the plugin's nine complete minute buckets, all 775 full-event reads and all 435 proof/roster reads belonged to `steps-resolution-0`; no other application caller for these two query IDs was observed. The worker is the measured priority, although the code also has HTTP fingerprint paths.

## Execution path

Source references are relative to deployed `src/modules/races/`.

- `services/raceResolutionInputFingerprint.js:8`: one fingerprint ordinarily loads race/roster, input generations, effects, and events: four SQL reads. Cache-admitted planning combines a proof with the roster read and may skip the event query on a hit.
- `jobs/raceResolutionQueueV2.js:1510`: closure planning admits the event cache. `:1701` also admits it for source-input work without a reusable closure plan; `:1760` validates display artifacts.
- `jobs/raceResolutionQueueV2.js:2142`, `:2169`, `:2256`: final transactional checks intentionally read PostgreSQL authoritatively. They prevent changes during computation from being committed as current results. Closure/source fingerprint reuse is already present; those cases should not be counted as unconditional duplicate reads.
- `services/raceFingerprintEventProof.js:16`: detects ambiguous `(event_id, starts_at)` ordering; `proofFromRow` returns null when ambiguity is true.
- `services/readRaceFingerprintEvents.js`: a null proof immediately falls back to FULL_EVENT_SQL before Redis lookup. Fill/refresh paths separately reject ties and unsafe precision.
- `services/raceFingerprintEventSql.js`: full event ordering is only `starts_at, id`.
- `queries/getRaceProgress.js:2413` and `:2425`: eligible legacy request-side rebuilds fingerprint before/after compute. This is not the observed caller in the sampled plugin buckets; modern worker-owned refresh can bypass that rebuild branch.

## Recommended next change

Make event ordering deterministic across the authoritative query, cache fill, local refresh and cached materialization, using stable per-entitlement/impact tie-breakers. Change the internal fingerprint/cache version so old artifacts safely miss during mixed-version deployment. Only remove the ambiguity bypass after cached and authoritative digests are proven equal for multiple participants sharing an event window. Preserve final transactional validation, time boundaries, negative-result invalidation, precision guards and fresh-read fallback.

For a simple initial-plus-final fingerprint pair, a successful planning cache hit changes approximately eight fingerprint SQL reads to seven; it does not eliminate the other worker queries or the final fence. Benefits depend on hit rate and proof cost, and no total CPU savings percentage is established. Index changes do not address the explicit ambiguity rejection.

Integration coverage should exercise real race-progress and worker settlement behavior on an isolated test database, including same-event/same-start participants, concurrent event/entitlement changes, event boundaries, Redis misses/failures, old artifacts and unchanged old-client responses. Query-count assertions should distinguish planning reads from final fences. No tests or implementation were performed for this read-only analysis.
