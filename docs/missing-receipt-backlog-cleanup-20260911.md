# Historical missing-receipt cleanup — September 11, 2026

The user authorized hard deletion of historical events with completely missing receipts and their related recovery entries. Existing receipts, including provisional receipts, were excluded.

## Scope and result

- Fixed cutoff: September 2, 2026, 17:47:57.654 UTC (1:47:57 PM EDT).
- Fixed manifest: 314,491 historical outbox events missing receipts by both event ID and event key; all were completed events.
- Deleted: 312,254 distinct outbox events, 313,147 audience rows, 313,147 notification projection rows, and 142,838 recovery queue entries.
- Preserved: 2,237 manifest candidates that no longer qualified when rechecked during cleanup.
- Final read-only scan at 19:44:17 UTC checked all 68,662 remaining outbox events through the cutoff: **zero completely missing receipts**.
- Queue check at 19:43:47 UTC: no queued/retry/processing LEGACY_MISSING entries; 68,462 successful historical missing-receipt jobs remain as history. LEGACY_PROVISIONAL has 223 queued and 30 successful entries, preserved because those events already have receipts.

## Execution and verification

The one-off CLI used a hashed fixed manifest, database identity checks, bounded transactions, row locks, a final missing-receipt recheck under a receipt-table write lock, and private backups flushed before deletion. Batch size increased from 200 to 500 at the user's request. Contended or timed-out transactions rolled back and retried. The final version allowed 15 seconds per pre-fence statement and 2 seconds per final statement; those are per-statement limits, not a total lock-duration guarantee.

Production delete triggers and foreign keys were inspected. Audience and projection rows were removed by existing cascades. All 9,757 manifest global-event entitlements were expired; no underlying entitlement, user, race, balance, purchase, or receipt records were deleted. No application code was deployed. The production revision remained 83940f9f341f5889e805c59e62693468c41c5dd7; both HTTP workers stayed online and staging stayed stopped. The public health endpoint returned OK during cleanup.

The real PostgreSQL cleanup CLI integration test passed on an isolated local test schema, covering scope, existing/provisional and concurrently-created receipts, newer events, cascades, backups, and reruns. A code reviewer reviewed the operational script. No production tests were run; no Flutter code changed.

Private backup directory on the production host: `missing-receipt-cleanup-20260911` under the root user's backup directory. It contains the manifest, backup JSONL, commit ledger, and final summary. Backup payload is 715,426,506 bytes with mode 0600. **Restoration must use committed event IDs from the ledger:** backup attempts may include rolled-back batches or preserved rows. Ledger contains 312,254 distinct deleted IDs with no duplicates.

This clears the completely-missing historical backlog. It does not remove the receipt/recovery system, provisional receipts, or successful queue history. No post-cleanup ten-minute CPU comparison was performed, so no CPU reduction is claimed.
