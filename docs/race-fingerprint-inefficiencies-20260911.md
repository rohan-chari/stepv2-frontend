# Fingerprint inefficiency follow-up

Evidence: twenty-minute watch 22:59:49–23:19:49 UTC on b20ad0b. Investigation only; no implementation or deployment.

| Query | Calls | Execution seconds |
|---|---:|---:|
| Fresh proof plus race/participant roster | 1195 | 26.13 |
| Local cache refresh | 593 | 14.06 |
| Full event SQL | 1147 | 12.83 |
| Full cache fill | 101 | 3.47 |

Total 3036 calls / 56.49 seconds. The proof query also returns race/participant fields, so its full time cannot be attributed solely to proof hashing. Final transaction reads deliberately bypass Redis; full-event calls are not a cache-miss count. Plugin CPU across the four query IDs in 19 complete buckets totals about 10.99 seconds; elapsed totals include waits.

Confirmed code properties:
- raceFingerprintEventCache.js global key includes database epoch, catalog revision, and cursor digest, but omits race start. write() stores coversFrom=proof.startedAt; valid() rejects a later coversFrom for an earlier race. Filling for a newer race can replace broader coverage at the same shared key. This is safe (rejected hit), but a concrete avoidable cross-race miss mechanism. Actual share of observed misses unknown.
- Both local and global entries have maximum TTL 30 seconds and expire earlier at the next event boundary. Horizon is now+10 minutes, fills cover the rounded horizon plus one minute; increasing TTL alone therefore does not guarantee longer reuse.
- Every planning call builds EVENT_PROOF_CTE over up to 8193 impact/entitlement witnesses, including historical/pending/missing records, hashes revision/incarnation identities, and returns the proof with each roster row. Local refresh and full fill execute EVENT_PROOF_CTE again before loading/stamping event rows. The second proof is necessary in the current design to bind rows and proof to one MVCC snapshot. 694 refresh/fill statements repeat that witness work. It cannot simply be deleted or reuse a stale first stamp.
- A local refresh independently reads impact/entitlement candidates after its proof reads those tables. Reusing a bounded same-statement candidate source may reduce repeated joins if it preserves distinct unfiltered witness and filtered event semantics.
- Final fingerprint assembly re-reads source inputs inside the commit transaction. Preserve that fence. Cache TTL or an unchanged Redis key is not a correctness substitute.

Candidate order: fix shared-global coverage key/value mismatch (race-start coverage bucket or truly shared bounded coverage, with explicit horizon design); assess longer immutable local-cache retention together with horizon coverage and boundary handling; then optimize duplicate same-snapshot proof/candidate reads using measured query plans. A per-race revision aggregate is a larger alternative with added trigger/write/lock cost and is not justified merely by these totals. Measure miss reasons before claiming savings. Existing ordering fix remains intact.
