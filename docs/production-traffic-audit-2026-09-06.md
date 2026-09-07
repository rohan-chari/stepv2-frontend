# Production traffic audit — September 6, 2026

Observation window: **7:36–8:36 p.m. EDT**, September 6 (23:36 UTC September 6 to 00:36 UTC September 7).

Status: **complete — coverage verified**. Production backend revision inspected: `bf3a85621eae6b4479458345c98b5dd1d76270d8`.

The application telemetry records **19,637 requests**, with **0 server errors** and **633 client-error responses**. The busiest observed complete minute contained **629 requests**. Counts come from the two production HTTP workers.

Traffic and request time by endpoint are in [the complete endpoint CSV](production-traffic-audit-2026-09-06-endpoints.csv). Minute-level traffic and worker measurements are in [the minute CSV](production-traffic-audit-2026-09-06-minutes.csv).

## Findings to act on

- Average traffic was **327.3 requests/minute** (5.45/second). Host CPU and memory samples show spare capacity during this hour; they do not establish capacity at a larger future peak.
- **Step sync, the race list, and the home race card dominate request time:** `/steps/sync-v2`, `/races`, and `/home/race-card` account for approximately 55.5% of matched upstream time. These are the clearest starting points for request-performance work. `/assets/manifest` leads request volume but consumes only 7.5 seconds of cumulative upstream time.
- **Step admission was not an observed bottleneck.** The downstream queue had short bursts that drained, but request-to-start delay reached 37.0 seconds (p95 9.0 seconds). Some of that interval is intended deferral; retain the distinction from claimable backlog when investigating delayed race updates.
- **All 460 observed double-payout claim requests returned 409.** Verify expected preconditions and client retry behavior in a separate investigation; these codes alone do not establish a bug.
- **Cron database-pool contention deserves attention:** 9,434 queued checkouts, with a maximum queued wait of 952.2 ms and no checkout timeouts. This is a separate source of waiting from step admission.

## Busiest endpoints

Application counts are authoritative for the monitored app workers. Latencies and response-body sizes use nginx records with matching normalized endpoint paths; see attribution limits below. p95 means 95% of matching requests finished within that duration.

| Endpoint | App requests | Share | Mean ms | p95 ms | p99 ms | Upstream total s | Response MiB |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `GET /assets/manifest` | 1,859 | 9.5% | 4.0 | 9.0 | 24.0 | 7.5 | 0.33 |
| `GET /races/:id/messages` | 1,657 | 8.4% | 65.5 | 179.0 | 338.0 | 108.5 | 3.65 |
| `POST /steps/sync-v2` | 1,522 | 7.8% | 236.0 | 735.0 | 1,493.0 | 359.0 | 0.66 |
| `GET /races` | 1,179 | 6.0% | 303.1 | 787.0 | 1,192.0 | 357.4 | 5.72 |
| `POST /analytics/activation-events` | 1,120 | 5.7% | 24.4 | 64.0 | 110.0 | 27.2 | 0.03 |
| `GET /home/race-card` | 1,102 | 5.6% | 278.6 | 790.0 | 1,292.0 | 307.1 | 1.81 |
| `GET /powerups/inventory` | 1,080 | 5.5% | 6.8 | 18.0 | 34.0 | 7.3 | 0.04 |
| `GET /steps/race-resolution/:id` | 1,073 | 5.5% | 22.9 | 62.0 | 121.0 | 24.5 | 0.19 |
| `GET /races/:id/progress` | 809 | 4.1% | 206.5 | 563.0 | 977.0 | 167.0 | 2.59 |
| `GET /auth/me` | 808 | 4.1% | 32.6 | 90.0 | 146.0 | 26.3 | 0.51 |
| `GET /races/invite-preflight` | 736 | 3.7% | 32.5 | 83.0 | 147.0 | 23.9 | 0.04 |
| `GET /races/:id/private-impact-feed` | 536 | 2.7% | 38.1 | 97.0 | 160.0 | 20.4 | 0.62 |
| `GET /inbox/alerts` | 529 | 2.7% | 42.0 | 116.0 | 229.0 | 22.2 | 0.20 |
| `GET /app-version/policy` | 475 | 2.4% | 3.0 | 7.0 | 13.0 | 1.4 | 0.00 |
| `POST /races/results/double-payout/:id/claim` | 460 | 2.3% | 104.1 | 295.0 | 503.0 | 47.9 | 0.03 |

## Endpoints consuming the most cumulative request time

Cumulative upstream time includes application processing and waits, including database/network waits. Concurrent request durations add together; these totals are **not CPU seconds**. Background work after the response is measured separately and cannot be attributed fully to an individual endpoint from existing telemetry.

| Endpoint | Upstream total s | Matching nginx requests | Maximum request ms |
| --- | --- | --- | --- |
| `POST /steps/sync-v2` | 359.0 | 1,522 | 3,411.0 |
| `GET /races` | 357.4 | 1,179 | 2,850.0 |
| `GET /home/race-card` | 307.1 | 1,102 | 2,364.0 |
| `GET /races/:id/progress` | 167.0 | 809 | 1,781.0 |
| `GET /races/:id/messages` | 108.5 | 1,657 | 599.0 |
| `GET /races/:id/bootstrap` | 66.2 | 339 | 1,563.0 |
| `POST /races/:id/powerups/:id/use` | 58.2 | 162 | 1,735.0 |
| `GET /races/discovery-summary` | 56.9 | 356 | 1,080.0 |
| `POST /races/results/double-payout/:id/claim` | 47.9 | 460 | 898.0 |
| `GET /home/suggested-races` | 39.6 | 452 | 366.0 |

## Client errors and probe traffic

| Endpoint | Matching nginx 4xx |
| --- | --- |
| `POST /races/results/double-payout/:id/claim` | 460 |
| `POST /` | 34 |
| `POST /index.php` | 10 |
| `POST /dashboard` | 10 |
| `POST /signup` | 9 |
| `POST /races/:id/powerups/:id/use` | 6 |
| `POST /admin` | 6 |
| `POST //wp-json/batch/v1` | 4 |
| `POST /blog/wp-json/batch/v1` | 4 |
| `POST /wordpress/wp-json/batch/v1` | 4 |
 
Client-error counts are separate from 5xx failures. Requests to WordPress/PHP paths appear to be automated probing; worker totals include those requests as well as normal app traffic. A 409 is a conflict/business-precondition response, not proof of a server fault. No request bodies were collected, so response-code counts do not establish every underlying cause.

## Step sync and downstream resolution

Step admission recorded **1,528 admissions**, **0 rejections**, and **0 responses classified as server failures**. The highest reported queue depth was **0 per HTTP worker**, with a highest reported active count of **4 per worker**. The worst minute-level p99 admission wait was **0.150 ms**.

Admission peaks are values observed at acquire/release/rejection events, so very brief waits can be missed. The admission “succeeded” counter includes non-5xx responses; it does not by itself prove a successful business outcome.

The resolution-worker logs contain outcomes {"commit": 2719, "superseded_commit": 40, "superseded_discard": 4}. These are background resolution attempts across all triggers, not one job per incoming step sync. Superseded outcomes describe concurrent newer work, not necessarily failures.

| Resolution measurement | Observed value |
| --- | --- |
| Core processing, median / p95 / p99 ms | 441.0 / 1,332.0 / 2,251.0 |
| Core processing maximum ms | 5,038.0 |
| Request-to-start, median / p95 / p99 ms | 5,034.0 / 9,023.0 / 28,274.0 |
| Request-to-start maximum ms | 37,044.0 |
| Maximum claimable backlog at service probes | 8 |
| Maximum age of claimable work at service probes, ms | 6,353.0 |
| Queue service alarms | 0 |
| Maximum queued / running / failed rows at DB samples | 22 / 4 / 0 |

Request-to-start time includes intentional coalescing/debounce and deferral; the deployed model has a default five-second debounce. Claimable age is the more direct measure of eligible work waiting to start. Neither metric measures end-to-end phone-to-visible-race-update time. Database snapshots exclude terminal `succeeded` rows from backlog calculations.

## Server and database-pool load

Observed host: four logical CPU cores, approximately 8 GB RAM, and 4 GB swap. Application topology was two HTTP workers, one resolution worker, and one cron worker; staging was stopped.

Host CPU samples averaged **11.1% of total four-core capacity**, with a maximum sampled interval of **30.2%**. Minimum available memory was **5,731.9 MiB**; maximum observed swap use was **36.0 MiB**.

Worker CPU percentages below are relative to one CPU core. HTTP values combine both workers for each minute; memory is their summed RSS, not unique physical memory.

| Role | Mean CPU % of one core | Max minute CPU % | Max sampled RSS MiB | Queued DB checkouts | Checkout timeouts | Max queued checkout wait ms |
| --- | --- | --- | --- | --- | --- | --- |
| http | 12.5 | 21.4 | 881.4 | 13 | 0 | 45.9 |
| resolution | 19.0 | 35.7 | 328.9 | 1,956 | 0 | 160.6 |
| cron | 5.3 | 23.4 | 323.3 | 9,434 | 0 | 952.2 |

Queued DB checkouts indicate contention for a worker’s connection pool; they are distinct from the step-admission queue and the durable resolution queue. A momentary pool-waiting snapshot of zero does not mean there were no waits during that minute.

## Step processing phases

These phase measurements come from HTTP step-ingestion telemetry. Phases may nest or run multiple times per request; do not sum them as independent costs. `transaction_total` contains work represented by several other rows.

| Phase | Observations | Total ms | Mean per observation ms | Max ms |
| --- | --- | --- | --- | --- |
| transaction_total | 1,526 | 340,951.4 | 223.4 | 3,402.1 |
| sample | 3,020 | 109,154.1 | 36.1 | 2,371.8 |
| durable_enqueue | 1,061 | 56,171.9 | 52.9 | 2,393.9 |
| summary_finalization | 4,530 | 51,320.8 | 11.3 | 167.5 |
| scoring_state | 1,516 | 30,806.6 | 20.3 | 1,542.7 |
| daily | 1,513 | 23,674.8 | 15.6 | 157.5 |
| active_race | 1,061 | 11,655.7 | 11.0 | 148.7 |
| scoring_generation | 1,516 | 9,904.8 | 6.5 | 113.5 |
| authentication | 1,528 | 9,731.6 | 6.4 | 487.8 |
| post_commit | 1,513 | 2,964.2 | 2.0 | 19.2 |

## Coverage and limits

- HTTP telemetry covers {"0": 60, "1": 60} distinct minute boundaries by worker instance. Both require 60 boundaries for full-hour coverage.
- Collected 59 read-only database queue snapshots and 57 resolution service probes. Database queue sampling began at 7:37:11 p.m.; service-log streaming began later. Timestamped resolution outcomes were recovered retrospectively to the window start.
- One initially unparsed nginx record was reconciled against the source log: a malformed single-field request received 400 without an upstream connection. It is excluded from application endpoint timing totals.
- nginx shares its timed access log across several virtual hosts and does not log the hostname. Matching-path timing/byte statistics cannot be attributed exclusively to this application with certainty. The CSV includes both app and matching-nginx counts so discrepancies remain visible. App counts exclude requests blocked before reaching the app, other virtual hosts, and traffic served entirely by an edge cache.
- UUIDs and numeric IDs are normalized; query strings are excluded. Some app telemetry paths truncate at 96 characters. Truncated impact-notice/receipt identifiers are grouped using their declared acknowledgement routes. Other truncated paths are expanded only when one normalized nginx path matches the prefix; the CSV includes the grouped telemetry endpoint and match method.
- Response bytes are nginx response-body bytes; request-body bytes, response headers, and total network bandwidth are unavailable. Endpoint-specific CPU, SQL counts, and full downstream cost attribution are unavailable from the existing request log.
- Request histograms use individual nginx observations. Admission wait p99 is the worst minute-level p99, not a combined-hour percentile. Host samples are approximately 15 seconds apart; worker and queue samples are approximately one minute apart. Peaks between samples can be missed.
- Telemetry boundaries can fire a few milliseconds early; records are assigned to their nearest minute boundary. nginx uses second-resolution completion timestamps, so sub-second boundary differences are possible.
- No application code, configuration, worker count, or production data was changed. Monitoring used existing logs and explicitly read-only SQL transactions, with statement/lock timeouts and rollback. No staging service was started. No deployment or app build/test was needed for this observational audit.
