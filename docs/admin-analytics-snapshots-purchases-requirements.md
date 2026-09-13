# Admin analytics snapshots and purchase usernames

Status: approved for local implementation. User explicitly said “ok lets do it” to the researched optimization and requested purchase usernames, then confirmed all three purchase categories. That implementation authorization is retained; architect final verdict APPROVE, with no remaining required changes. Production deployment is a separate approval.

## Summary and user story

An admin should open analytics without triggering repeated heavy PostgreSQL calculations, see when the displayed numbers were calculated, and identify the username associated with each recorded purchase. Preserve the redesigned admin visual language on iOS and Android.

## Scope

- Shared 15-minute analytics snapshots, controlled refresh and failure behavior for dashboard and legacy statistics paths used by admin.
- Bounded shared extraction and in-memory calculation of small relational analytics inputs, especially coverage, foreground activity and retention. Correct DAU aggregate fan-out and reduce repeated event processing.
- Paginated purchase history for coin packs, subscription/Bara+ receipts and successful in-game purchase records, with current public username and honest missing data.
- No price, reward, eligibility, billing fulfillment, or game scoring changes. No release flags, additional PM2 processes, production deployment, new provider polling or historical cash-price reconstruction in this scope.

## Existing sources and implementation entry points

Backend paths are relative to the separate backend repo:

- `src/modules/admin/routes.js:547` calls `getAdminStats` directly. `getAdminStats.js:428` classifies dashboard/legacy sections.
- `adminMetricsQueries.js:56` coverage scans/ranks relational data; `:277` foreground counts; `:315` retention; `:840` DAU; `:1094` repeats coverage for every section.
- `src/shared/cache/redisCache.js` has Redis primitives; `derivedCache.js` falls through to PostgreSQL on cache failure and must not wrap expensive analytics unchanged.
- `ecosystem.config.js` and database pool config preserve two HTTP processes and the current total connection budget. A CPU worker must not import `src/db.js` and instantiate another database pool.
- `prisma/schema.prisma:3980` BillingPurchase links via BillingIdentity to User; cash price/currency are not stored. `:1246` ShopPurchaseRequest and `:1343` PowerupPurchaseRequest store actual `coinsSpent`. User public username is `displayName`, not legal/profile `name` or email.
- Frontend `lib/screens/admin_dashboard_controller.dart:39`, `admin_dashboard_overview.dart:7`, `admin_dashboard_detail.dart:774`, `lib/widgets/admin_metric_widgets.dart:621`, and `lib/services/backend_api_service.dart` own requests, placement and freshness.
- Backend research: `docs/admin-analytics-memory-research-20260913.md`. Current overview estimate is 7–9 analytics queries, including three repeated coverage calculations; this is code-derived, not measured CPU.

## Backend snapshot design

1. Add an admin-specific snapshot coordinator around statistics reads after authentication/authorization and request classification. Cache keys include immutable calculation version, normalized section(s), window, ET date and collection epoch/config generation. Unknown sections retain existing normalization behavior; no new required parameters.
2. Freshness is 900 seconds. A completed snapshot can be served stale for up to 24 hours, clearly marked; ET date changes must not present yesterday as today's results. A cold miss shares one build with a bounded 20-second wait; if no matching snapshot becomes available, return 503 with `Retry-After: 15`. Failed builds never replace a completed snapshot.
3. One global analytics extraction/build lease across HTTP workers and section keys. Lease 60 seconds, token-checked renewal every 15 seconds, release and conditional publication prevent an owner that loses its lease from overwriting results. Entire-build deadline 45 seconds; terminate CPU worker and stop scheduling DB queries on cancellation, not merely Promise.race. An already-running statement may drain for its remaining five-second timeout. Coordinator deduplicates a finite known set of sections/windows. Shared failure backoff 60 seconds, bypassed only by new config generation; no unbounded request queue or rebuild on every retry.
4. Publish one compact shared relational-summary artifact per generation in Redis, containing coverage/foreground/retention calculations for all three supported windows. Lazy section builds on either HTTP worker consume this artifact and run only section-specific SQL. Do not rely on process-local raw-input reuse or rebuild all detailed sections eagerly. Discard raw user maps after aggregation. CPU work runs in a DB-free worker thread; database extraction uses one connection from the owner process's existing pool, serial queries, read-only repeatable-read extraction and a bounded transaction deadline. Release the transaction before CPU work. Worker count is bounded to one active analytics computation globally, with local defense too.
5. Read only required columns from users, races, participants, user/day activity and capability records. Initial protective limits: 2,000 rows/page, 200,000 total extracted rows, 32 MiB projected serialized data; five-second statement timeout, 15-second extraction transaction timeout, worker 256 MiB old-generation limit. Local completed snapshots capped at 64 entries/16 MiB with eviction. Validate these ceilings with local benchmarks; they are not measured capacity claims or runtime flags. Exceeding budgets returns unavailable/stale rather than truncated counts. Preserve historical first-race semantics; never arbitrarily cut history to visible date range.
6. Replace repeated coverage and foreground/retention joins with exact sets/maps over shared inputs. Keep cheap SQL sums or compact user/day/action aggregates for large event/ledger sources; no full JSON event export. Correct DAU by independently computing daily action aggregates and distinct union users before combining them. Preserve nine-action denominators and exact distinct counts.
7. Requests and refresh taps only request the current snapshot; they never bypass the 15-minute freshness policy. While a visible admin analytics screen is active, foreground refresh checks at 15 minutes request updated snapshots. Hidden/disposed/background screens stop polling; resume checks age. First reads of detailed sections remain lazy. No periodic background work when admin is inactive.
8. Redis or coordination failure must not trigger uncached analytics queries. A bounded process-local last completed snapshot may be served within stale limits only if matching configuration identity is established; otherwise 503. Generation invalidation explicitly covers dashboard-enabled, telemetry-enabled, collection-epoch, and coverage-operational changes. Both individual and atomic settings writes (`appSettings.js` epoch paths) invalidate after commit and evict local copies. Do not serve previously enabled/old-epoch snapshots when identity freshness cannot be established. Existing mutable configuration reads remain authoritative. Preserve original outer and source timestamps. Add only required invalidation hooks; do not modify global cache semantics.
9. Record snapshot build duration, extraction rows/bytes, cache hit/stale status and failure counts without user identifiers. Benchmark current SQL, corrected/shared SQL, and hybrid memory processing on local representative data. The implementation must demonstrate reduced rebuild database work, not only warm-cache wins.

## API contract

### Existing GET /admin/stats

Existing request parameters and all existing response blocks remain. Add optional snapshot metadata inside `stats`; preserve original calculation `generatedAt`:

```json
{
  "stats": {
    "generatedAt": "2026-09-13T12:00:00.000Z",
    "snapshot": {
      "generatedAt": "2026-09-13T12:00:00.000Z",
      "freshUntil": "2026-09-13T12:15:00.000Z",
      "status": "fresh",
      "refreshIntervalSeconds": 900
    },
    "metricsDashboard": { "schemaVersion": 2, "status": "available" }
  }
}
```

The example elides existing metric blocks; they remain unchanged. `snapshot.status` is `fresh` or `stale`; do not imply a job is running unless observed. Existing disabled dashboard envelopes remain disabled and cannot be resurrected from a cached available envelope. Existing legacy shape stays intact with additive metadata. No-data is not zero. Cold/failure response: `503 {"error":"Admin analytics are temporarily unavailable","code":"ADMIN_ANALYTICS_UNAVAILABLE"}`. Preserve 400 request validation, 401 and 403 handling.

### New GET /admin/purchases

Query: `kind=all|coin_pack|subscription|in_game` (default all), `environment=production|sandbox` (default production; applies to billing receipts), `limit=20` (1–50), optional opaque `cursor`. Fixed trailing 30-day window, labeled in UI. Cursor binds kind/environment/window anchor and last `(occurredAt, source, id)`; invalid or mismatched cursor returns 400. Window anchor is fixed across pages. Sort descending timestamp then stable source/id tie break, retrieve at most limit+1 eligible rows per source and merge, no OFFSET or unbounded total count.

```json
{
  "generatedAt": "2026-09-13T12:00:00.000Z",
  "window": {"days":30,"start":"2026-08-14T12:00:00.000Z","end":"2026-09-13T12:00:00.000Z"},
  "items": [
    {
      "id": "shop:request-id",
      "kind": "in_game",
      "username": "RiverBara",
      "productId": "item-sku",
      "productName": "Item name",
      "occurredAt": "2026-09-13T11:40:00.000Z",
      "status": "purchased",
      "funding": "coins",
      "coinsSpent": 250,
      "cashAmount": null,
      "currency": null,
      "environment": null,
      "store": null
    }
  ],
  "nextCursor": null
}
```

- `username` is nullable current public `displayName`; absent/deleted identity renders “Username unavailable.” Do not substitute email or personal name. Expose no provider customer ID or payment details.
- `productName` nullable; retain source product ID fallback. Billing classification uses backend receipt/product metadata and includes Bara+ permanent purchases in subscription/membership category. Unknown historical product classification must remain visible in All with `kind: "other"`; no frontend SKU allowlist.
- `status`: `purchased|refunded|pending|trial|unpaid|free|unknown`; `funding`: `coins|coins_and_ads|ads|cash|trial|free|unknown`. Refund/reversed state takes precedence over fulfillment. Trial/unpaid/free labels must never appear as paid purchases. All metadata describes records, not a new authorization policy. Null coin/cash fields mean unrecorded; explicit zero is preserved. Cash amount/currency are null for current billing history because no verified amount is retained. Never use today's catalog price to invent a historical charge. Credit-funded rerolls are outside coin-purchase history (no fabricated coin amount); the list documents this limit.
- Billing receipts, including renewals/refunds/trials, are one row per durable receipt, clearly labeled; subscription state rows must not duplicate receipts. Production/sandbox never mix silently. Current UI initially requests production; label production billing records explicitly. Sandbox is supported for testing without making another required UI filter.
- In-game list derives from successful durable requests. Exclude successful already-owned no-op retries; identify ad-assisted unlocks honestly from recorded results. Normal provenance is the recorded `resultJson.purchase` and ad provenance `resultJson.adsWatched`; unknown historical shapes show unknown funding, never assumed paid. A genuine zero-cost acquisition remains visible as such, distinct from a paid purchase. Do not call ownership/grants purchases. Include distinct paid upgrade and reroll operations via negative coin ledger entries with reasons `powerup_upgrade` and `billing_reroll`, using recorded amounts and safe product labels. Never union ledger counterparts for shop, powerup, ad-unlock or billing receipt sources. Deleted in-game request history cannot be reconstructed from current ownership; say “Available recorded transactions · current usernames” in the list information sheet.
- Add nullable `userStatus` (`active|deleted|unknown`), `benefitKind`, and `refundedAt` to each purchase row. For tombstoned billing identities/deleted user, return username null and userStatus deleted (render “Deleted account”); an active unnamed account renders “Username unavailable.” Billing receipts classified trial/unpaid remain visibly distinct activity and never contribute to paid-purchase totals; no new financial totals are introduced. Permanent Bara+ original receipt is membership activity; recurring benefit grants are excluded. Refund reversals update the same receipt row, not a new sale.
- Implement bounded joined reads, never a user query per row. Add only source timestamp/id indexes supported by query plans. Purchase pagination is an inexpensive bounded read on demand, independent of expensive analytics generation; no third-party API calls. Current usernames are read at page fetch, not cached for 24 hours.
- Existing stats popularity totals retain their current contract; the new list does not restate historical totals. Fix obsolete “NO_IAP_PRODUCT” descriptive state without inventing revenue amounts; report purchase history availability separately from cash-revenue availability.

## Data model and migration plan

No new financial fields or analytics write per step sync. New snapshot data is derived and disposable. Candidate additive indexes on purchase source `(created_at,id)` and billing `(environment,purchased_at,id)` must be justified by bounded pagination plans. Backend locks exact migration SQL before implementation. No price backfill. No destructive migration or changed purchase fulfillment semantics.

## Frontend implementation and states

- Extend defensive models/API service for snapshot metadata and purchase page response. Backend fields are optional on stats; use server generatedAt when valid, otherwise label client fetchedAt as “Fetched,” never “Calculated.”
- Update shared AdminFreshness and information sheets plus the overview's redundant fetched label so one freshness area remains below the chart. Detail freshness stays in its existing footer. Show “Calculated … · updates every 15 min”; stale/error states retain visible old data with clear age. Keep System health separate.
- Add Recent purchases after Most-purchased items in Ads & shop → Shop. Local window/environment caption. Four wrapping type filters: All, Coin packs, Subscriptions, In-game purchases. Compact rows keep username, product, date, status and recorded amount together; no item art needed. Use existing admin typography/cards/colors.
- First load spinner/placeholder, explicit empty state, retry on error, inline load-more error retaining rows, Load more beneath list. Filter switches reset cursor and cancel/ignore late previous responses; deduplicate appended IDs. 404 on old backend shows unavailable, preserving other analytics. Do not crash on malformed rows or labels; do not render malformed amounts as zero.
- Stop refresh timers on disposal/background and avoid multiplying timers across stacked detail routes. When a visible section receives stale-while-revalidate data or cold-cache 503, schedule a bounded follow-up after the 45-second build window (50 seconds, at most two attempts per 15-minute cycle) so completed data replaces stale/error data without waiting another 15 minutes. Follow-ups request only affected analytics sections, respect the 15-second Retry-After, and use normal cache reads; no 401/403/404 retries. Cancel on hide/background/disposal; failures cannot create an indefinite retry loop. Purchase list loads only when Shop visible. Refresh resets list safely; it cannot bypass analytics freshness.
- Shared Dart supports iOS/Android. No new native dependencies, artwork, app version or build configuration changes.

## Compatibility and rollout

Backend deploy precedes app release. Old binaries continue to request existing stats sections and ignore additive metadata. New binary on old backend keeps existing statistics and shows purchase history unavailable. Authentication is required even for cached hits. This work does not authorize production deployment, staging startup, store upload or release. No flags introduced.

## Tests first and acceptance

Backend real HTTP + local test DB: preserve old section contracts, disabled state, exact counts including distinct overlap and DAU fan-out correction; use real Redis for cross-worker stampede tests, token-loss publish rejection, stale/expiry/error/Redis outage, generation rollover, and no analytics SQL on warm hits. Use test clocks through dependency injection, no production runtime switches. Exercise paging ties, max size, cursor tampering/filter mismatch, all sources, rename/deleted usernames, ad-assisted unlocks, no-op requests, trials/refunds, null cash amounts and current-price independence. Verify 401/403 for cached/new paths. Integration tests must fail before business logic is written; existing assertions protected.

Frontend real widgets: all purchase types/username association, long names and text scaling, missing username/amount/unknown kind, empty/error/404, pagination/filter races, stale calculated-vs-fetched labels, lifecycle/timer behavior. Update existing fixtures additively. Run flutter analyze clean and relevant suites. No native dependency/config changes, both platforms use same tested Dart; native build requirements assessed before release.

Benchmark report must compare full refresh cost (DB work, source rows, bytes, CPU worker memory/time) and cold/warm HTTP latency. Avoid promising an unmeasured percentage. Tests and independent code-reviewer must pass before claiming implementation complete. Hand over the manual placement checklist below.

## Implementation order

1. Architect and UI/economy-semantics review; fold required changes and lock API/migration contract.
2. Backend developer writes failing HTTP tests, locks contract, then implements coordinator/extraction/CPU worker and query corrections, followed by paginated purchase reads.
3. Once backend contract is locked, frontend developer writes failing real-widget tests, then API/model/controller/freshness/purchase UI work. Preserve unrelated working-tree changes in both repos.
4. Benchmark candidate against baseline on local test DB, fix regressions, run focused tests and analyzer, independent combined code review, document remaining manual checks.

## Revision log

- Gap pass 1: corrected initial SQL query count to 7–9 and alias diagnosis; specified accurate DAU fan-out correction; protected historical first-race and distinct-user semantics.
- Gap pass 2: identified missing historical cash prices, current public displayName semantics, ad-assisted unlock/no-op ambiguity, worker-thread accidental pool growth, token-loss publication risk, immutable cursor window, null/zero handling and Redis outage behavior.
- Architect investigation and formal required revisions folded in: DB-free CPU worker, unchanged pool budget, shared cross-worker relational artifact, concrete memory/query/time limits, ownership-aware cancellation/publication and failure backoff, individual/atomic config generation invalidation, free/refund classification and paid operation sources. Final rereview APPROVE; no required changes or suggestions remain.
- Purchase semantics review: SOUND WITH CHANGES; folded ad-assisted provenance, no-op/free distinctions, paid/permanent versus trial/unpaid, receipt refunds/reversals, current public username/deletion, missing monetary amounts and history limits into contract. No economy mutation; player EV and coin flows unchanged.
- Implementation review: added bounded visible stale-snapshot follow-up to fetch the completed refresh without a second 15-minute wait; same cache policy, no bypass.

## Manual UI-placement test plan

**Manual UI-Placement Test Plan — Admin snapshots and purchase usernames**

*Elements under test:*\
Recent purchases added below Most-purchased items in Ads & shop → Shop.\
Purchase-type filters above the new list; username, item, date, status and amount inside each row; Load more below the rows.\
Snapshot age and refresh state shown in the existing analytics freshness locations and their information sheets.

*Checklist*

1. **Surface:** Real admin overview, on iOS and Android.
   - **Get there:** Sign in as an admin → Profile → Settings → ADMIN TOOLS.
   - **Verify:** Freshness information appears below the trend chart and above Explore. Tap its information icon and confirm the details remain visible in the sheet. No duplicate freshness block appears above the chart.

2. **Surface:** Real analytics detail pages.
   - **Get there:** From Explore, visit Growth, Activity, Retention, Races & friends, both Invites & onboarding tabs, and both Ads & shop tabs.
   - **Verify:** Each page retains its freshness information after its metrics. Refresh/stale indicators, when present, stay within that area without covering metrics or adding duplicate rows. Check the information sheet on one detail page.

3. **Surface:** Real Shop purchase list.
   - **Get there:** Admin → Ads & shop → Shop; use an account/environment with examples of all three purchase types.
   - **Verify:** Most-purchased items remains first, with Recent purchases below it. Filters sit above the purchase rows. Each row keeps its username visibly associated with that purchase’s item, date, status and amount. The new list appears once and does not also appear under Ads.

4. **Surface:** Purchase list filters and pagination.
   - **Get there:** In Recent purchases, select All, Coin packs, Subscriptions and In-game purchases; scroll to Load more.
   - **Verify:** All four filters are reachable on a narrow phone. Long usernames/item names and missing-value labels stay within their own rows. Load more appears below the rows; after loading, additional rows appear before the control without repeating the section heading or filters.

*Surfaces confirmed unaffected:*\
Demo race tutorial — no admin dashboard, detail or freshness widgets are instantiated.\
Tab tutorial — reuses ProfileTab, but contains no separate admin analytics screen or purchase list.\
Onboarding/tutorial preview fixtures — no admin analytics mirror requires purchase fixtures.\
Admin Tools configuration screens — separate from the analytics detail renderer; purchase rows do not belong there.\
System health — has its own freshness display and should retain that separate placement.

*Risks found while planning:*\
Shop currently hides the dashboard date selector; any purchase-window label needs a local placement beside the new list heading.\
The shared freshness widget renders on both overview and detail pages; its information sheet also needs the updated snapshot presentation.\
Four purchase filters and multi-field rows need narrow-screen checks, especially with long usernames.\
Manual purchase checks need representative records; demo/tutorial fixtures cannot supply this surface.
