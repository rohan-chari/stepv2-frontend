# Per-page admin snapshots calculated in memory

## Summary and authorization

The user originally authorized batched reads and application-memory processing with15-minute admin caching. After the shipped implementation returned unavailable sections, the user clarified the required unit of work: opening Admin computes only its visible content; Ads and Retention compute and cache their own content only when visited. This revision replaces the over-broad shared artifact and heavy aggregate paths for updated clients. Prior implementation authorization covers this correction; production deployment and another TestFlight upload still require their applicable release authorization.

Current implementation evidence: `lib/screens/admin_dashboard_overview.dart` requests summary/growth/DAU; `admin_dashboard_detail.dart` maps pages to overlapping sections. Backend `getAdminStats.js` executes13 base queries before its3 economy/ads queries even when Shop needs onlySKU/count or Ads needs onlyusersAtCap. `adminMetricsQueries.js` loads61 days ofDAU for comparisons not displayed by either Overview or Activity. Production original and compactedDAUSQL both reached57014 under the five-second limit. SQLcompaction alone is not the solution.

## Product behavior

- One completed snapshot per page and selected data window, fresh for15minutes. Page visits and visible-page refreshes are the only triggers. Nocron, no universal first-load computation, no work for unopened pages.
- Fetch only narrow source fields needed to reproduce the visible metrics and their truthful coverage. Stream bounded batches into a DB-free worker that calculates exact counts/sets/cohorts in memory. PostgreSQL performs source filtering/joins needed to exclude invalid records, not large analytics joins/grouping/sorts.
- Cached hits authenticate and verify configuration, then return the completed result without analytics source reads.
- Expired same-generation snapshots return immediately while one refresh runs. A page failure cannot block anotherpage. Globallyserialize builds so simultaneous admins do not overloadPostgres.
- Retain the existing user interface and metric meanings, including unavailable/coverage states. No game economy, purchase fulfillment, or chart definitions change.
- Purchase history remains a separate bounded cursor-paginated read. Its username/status/funding semantics and current contract stay intact. Do not bulk-read purchase history merely to calculate popularity.

## Exact page-to-result map

The companion `docs/admin-page-memory-field-map.md` is normative for exact JSON leaf paths, conditional selected-range projections, coverage leaves, source references and renderer behavior. In particular Overview7d does not load30d merely to fill unusedMAU; Growth7d does need30d because it displaysMAU.

Sections below are projected existing section payloads; no unlisted metrics are calculated merely to populate an old shape.

| view | result section keys | visible requirements |
|---|---|---|
| overview | dashboard-summary, dashboard-growth, dashboard-dau-engagement | totalaccounts; signup totals; foregroundDAU/WAU/MAU; current race-user count; selected-window signup/foreground/action users; today's action-user count |
| growth | dashboard-growth | dailydate/signups/observedForegroundUsers;WAU/MAU |
| activity | dashboard-dau-engagement | todayDAU;selected-window dailyDAU;todayusers/events and dailyusers forboxes,powerups,dailyrewards,leaderboardviews |
| retention | dashboard-summary,dashboard-retention,dashboard-retention-mature | pooledD1/D7/D30;selected-window signupcohorts;fixed90-day repeat-race ratios |
| races | dashboard-summary,dashboard-engagement,dashboard-activation | threecurrentracecounts;daily liveparticipants;public/private ratios;featured/rankedparticipants;friend buckets |
| invites | dashboard-funnels | invitecounts/conversions only |
| onboarding | dashboard-funnels | cohortdays,stagecounts/conversions only |
| ads | dashboard-revenue,ads | daily uniqueviewers/grants;reward-typegrants;adRevenue.capUtilization.usersAtCap only |
| shop | economy | coinEconomy.purchasesBySku sku/count only;separatepurchasepaginationunchanged |

Allnine existing qualifying action sources remain necessary for exactDAUunion even though onlyfourfeaturebreakdowns are shown. A30-day data window is still needed where visibleWAU/MAU requires it. Retention preserves historical first-race semantics; do not truncate away an earlier qualifying race merely because its second race lies in the90-day window. Pooled retention uses the latest30 mature eligible signup dates for each horizon (D1 end−2, D7 end−8, D30 end−31), regardless of the selected7/30day chart window. Source eligibility, review-account exclusion, retained-account behavior, ET boundaries, epoch eligibility, denominators and coverage must match existing displayed definitions. LegacyAds' cap definition remains its latest recorded grant day within30days, not an invented current-day cap count.

## API contract

Add permanent optional `view` routing to GET `/admin/stats`. Existing requests withoutview keep their exact existing contracts and cached compatibility path. Never redirect old clients to a projected shape.

New requests: `/admin/stats?view=overview&window=7d&sections=dashboard-summary`.
`view` must be one ofthe nine values above. `window` is7d or30d; Shop uses its existing fixed trailing30-day definition; use90d internally only for the explicitly displayed mature-retention block. Today requests7d and displays one bucket anchored to envelope.window.end, matching the current frontend. `sections` is a compatibility hint: use the first real existing section for thatview (mature alias never sent). New routing selects the page byview, not bysections. Validate suppliedsections against that page's compatible existing section names; unknownview/window/section is400.

Response (illustrative metric values; exact inner fields preserve current renderer contracts):

```json
{"stats":{"view":"overview","generatedAt":"2026-09-13T21:00:00.000Z","snapshot":{"generatedAt":"2026-09-13T21:00:00.000Z","freshUntil":"2026-09-13T21:15:00.000Z","status":"fresh","refreshIntervalSeconds":900},"sections":{"dashboard-summary":{"generatedAt":"2026-09-13T21:00:00.000Z","metricsDashboard":{"schemaVersion":2,"status":"available","window":{"days":7,"start":"2026-09-07","end":"2026-09-13","timeZone":"America/New_York"},"sources":{},"coverage":{},"summary":{}}},"dashboard-growth":{"generatedAt":"2026-09-13T21:00:00.000Z","metricsDashboard":{}},"dashboard-dau-engagement":{"generatedAt":"2026-09-13T21:00:00.000Z","metricsDashboard":{}}}}}
```

`sections` contains the exact page result keys in the table. Every innerpayload includes the parentgeneratedAt/snapshot metadata, plus the existing payload envelope and onlyrequired metrics. The mature-retention alias contains an envelope stampedwith90-daywindow. Disabledconfiguration returns projecteddisabled envelopes; it must evict cached enabledpage data. Malformed/missingrows/metrics remain safelyunavailable in theclient. No new field is mandatory foroldrequests.

401/403 precedecacheaccess. Cold page builds still running after10seconds return HTTP503 with `{error:"Admin analytics are being calculated",code:"ADMIN_ANALYTICS_PENDING"}` and Retry-After15. A failed/backed-off/Redis-unavailable page returns503 with `{error:"Admin analytics are temporarily unavailable",code:"ADMIN_ANALYTICS_UNAVAILABLE"}` and Retry-After15. Invalidview/compatibilityhint returns400/INVALID_ADMIN_VIEW; invalidwindow returns400/INVALID_WINDOW. Existing no-view503 retains ADMIN_ANALYTICS_UNAVAILABLE. Keep cold waits10seconds on both paths, below the existing client15second timeout; do not return a pending code to old no-view clients; clients retain bounded50secondfollow-ups and showloading/checking text for expected cold503, rather than suggesting missing historicaldata. Genuinefailedbuild remainsretryable; no infinitepolls. Redis outage policy deliberately retains the previously approved/shipped fail-closed design: availability of new expensive calculations never bypasses cross-process deduplication. Redis unavailable serves a usable localcompletedpage only; coldfailsclosed withoutanalyticsreads.

Old backend ignoresview and returns normalstats withoutstats.view/sections. Newfrontend detects absence ofthe page contract and fallsback once to the existing sectionrequests; reuse the compatible firstreply if practical. Do not interpret a malformed advertisedpage response as permission to repeatedlyfallback. Backend deploy precedes building/uploading the new client.

## Batched extraction and worker design

Use one borrowed existingpool connection per build, one readonly repeatablereadtransaction, transaction-owned NO SCROLL cursors over narrow sourceSELECTs, FETCH2000 batches, and worker acknowledgement before the nextbatch. No WITHHOLD cursor, no extra connection/pool/process, and no raw events in Redis. One sourcecursor scans its bounded inputonce; avoid keyset paging byunindexed occurred_at which could rescan/sort eachpage. Closecursors/commit after sourceextraction, then finalizeworkeroutput. Cancellation must drain/cancelcurrentwork safely beforeconnectionrelease.

Plannerdeclares sources/columns/timebounds byview beforeDBreads. Skip universalcoverage/retention precomputation. Reuse a source withinonepage whenmultiplevisiblemetrics needit (e.g. signupusers and foregroundactivity, Ads counts andcaps). Do not streamJSONcontext orwhole rows ifa narrower scalarprojection suffices. Ifan existingcoverage definition needs a small dedicated source probe, include onlythatprobe and test its necessity.

Worker incrementally consumes batches; retain compact maps/sets/bitsets/counters, not allrawrows. DAU: perday/action distinctusers + eventcounts, unionbits acrossnineactions; ETday boundaries computed once andtimestamps classified correctly acrossDST. Retention: retain onlycohort/eligibility/history state neededfor displayedpooled/signup/repeatrace metrics. Joineligibleuser IDs in thedatabase orworker as appropriate, preserving deletion/review semantics. Ads: groupuniqueviewers byday, grants byrewardkind, and latest-daycapusers. Shop: preserve the existing popularity population exactly: successful powerup purchase requests plus user_shop_items acquisition rows, grouped bySKU. Do not substitute receipt-history semantics or add unrelated coin-ledger/base-stat reads. Purchase-history rows remain separately provenance-based as already shipped.

Initial safeguards: FETCH2000, one outstandingbatch,5000ms perstatement,45000ms totalbuild,10000ms coldHTTPwait, workeroldgen256MiB, compactliveworkerstate64MiB, pageoutput16MiB, up to2million streamedrows/256MiB serializedinputperpage (bytescumulative, notretained). Enforce live-state budget explicitly: charge typed-array/ArrayBuffer byteLength plus bounded conservative per-entry costs for Maps/Sets/strings and serialized ordinary state; track totals on allocation/insertion, rejecting before crossing64MiB. Worker maxOldGenerationSizeMb alone does not bound external allocations. Every workerACK/message wait races the shared45000ms AbortSignal, as do extraction/finalization/publication; no missingACK may hang a connection. On failure terminate the worker, stop schedulingFETCH, drain currentstatement, CLOSE/ROLLBACK and release exactlyonce, and conditionallyrelease only the ownedlease. These are explicit work ceilings, nottruncation: exceedingone fails thepage andreturns a previoususablecompletedresult ifavailable. Validate actualmemory/coldtime against representativecardinalities beforeaccepting theseceilings. No globaltimeoutincrease tohide costlyqueries. Use the SAME existing admin:analytics:v1:lease key for BOTH legacy and new page builds, through the existing Redis environment-prefix wrapper; never create a second concurrently runnable lease. Page failures use view+window+configuration-scoped60-secondbackoff; sharedDB/leasefailures preserveglobalcontainment. Lease60s/renew15s/conditionalpublish; exactly2productionHTTPworkers andpoolbudget32 retained.

Cacheidentity: `admin:analytics:views:v1:<authoritativeconfig>:<ETdate>:<view>:<window>`. Fresh900s; retain previoussameidentity up to24h. Configuration/epoch/coveragechanges preventreusingoldgenerationdata. Viewidentity belongs in everyclient/servercachekey. A projectedOverview summary must never satisfyRetention orRaces.

Compatibility correction: the existing unqualified dashboard-dau-engagement route must also stop using the timed-out aggregate SQL. Reuse the streamed action accumulator over its full61-day legacy history, then preserve every existing comparison/average/union field and coverage contract. Old clients may require more work than new view-qualified requests, but must not remain broken until they update. Other legacy full-shape paths keep their cached compatibility implementation and the verified section-failure isolation.

No migration is presumed. InspectplainEXPLAIN for cursor sourcequeries and measuretheirboundedFETCHbehavior. Add an additiveindex onlywhenactualsourceplans showitnecessary; documentbefore/afterreadcost andwriteoverhead, test migration locally, andinclude inprodapproval. The abandoned SQL-onlycompaction experiment isnot the acceptance target.

## Implementation steps

1. Architectreview this revisedcontract/extraction plan; resolve requiredgaps. Existingauthorizedgoal remainsactive.
2. Backenddeveloper: failing realHTTP tests forviewrequest/sourceisolation/metricparity andstreambackpressure; implementviewclassifier/router, pagecachecoordinator, sourceplanner/cursorextractor, DB-free incrementalworker andprojectedformatters. Keeplegacycontract andpurchasespaths.
3. Oncecontractlocked, frontenddeveloper: failingrealwidget+API tests; fetchonepagepayload pervisit/refresh, distributeprojectedsectionpayloads intoexistingrenderer state withview-scopedkeys, preservevisibility/lifecycle behavior andboundedfollowups, implementoldbackendfallback. Bothplatforms shareDart; noposition/designchange.
4. Replace unpublishedquery-specificexperimental assertions with tests fornewstreamingcontract, preservingall existingreleasedassertions and exactDAUcounts. Record explicitlywhythe abandonednewindex-onlyexpectation is superseded, notsilentlyskipped.
5. Benchmark cold/warm eachpage, sourcequery/batchcounts, transferredbytes, workerpeakmemory/time, andprove no sources belongingonlytounopenedpages aretouched. Comparepublicresponse values, includinglarge repeated-eventfixtures.
6. Independentcode-reviewer, cleananalyzer/relevanttests. Preparecommittedbackendrelease andrequest freshproductionapproval onlyafterconcreteverification. VerifycoldOverview/Activity/Ads/Retention inproduction afterauthorizeddeploy, beforecarryingappupload. No stagingstartup orprodtestfixtures.

## Acceptance tests

- OpeningOverview doesnotqueryretentioncohorts, friendtables, shop/coinledger, invitation/onboarding sources orunusedcoverage; needednineDAUsources remainallowed.
- Ads andShop do notexecutelegacybasequeries; RetentiondoesnotcalculateGrowth/Ads/Shop metrics. Eachotherpage touches onlyits declaredplan.
- Warmrequests zeroanalyticsreads, stablegeneratedAt; view/window/generationcacheisolation, crossworkeronebuild, staleandRedisfault behavior, failureisolation.
- Exactdisplayedparity: signup/foreground counts, nineactionunion andfourbreakdowns, review/deletedusers, ET/DSTdates, D1/7/30maturity, historicalfirst/secondrace, invites/onboarding, caps/rewardtypes, SKUcounts.
- Largeeventfixture exceeds old200000totalrow extraction limit but uses bounded live memory and onebatchoutstanding, finisheswithouttruncation. Forceworkerfailure/deadline/lease-loss andverifyconnection/cursorcleanup andnopublish.
- Frontendoneviewrequest, dormantpageszeroqueries, pagecachecannotcontaminateotherpage, rangeandrapidnavigationraceguards, hidden/backgroundstop,503boundedfollowup, oldbackendfallback, retainedpurchaseusernames.

## Revision log

- Gap pass1: existingsectionnames cannotstrictlyidentifyvisiblepage; explicitviewidentity andprojectedsectionmap preserve oldclientcontracts. LegacyAds/Shop basequeries bypassedonlyforviewrequests. AllnineDAUactions retained;61-dayunusedcomparisons removed.
- Gap pass2: naivekeysetpagination couldrepeatunindexedscans; transaction-ownedcursors/FETCHwithworkerACK enforceboundedmemory andsinglepass. Distinguishcumulativeinput budgetfromliveworkerstate. Retentionhistoricalsemantics, truthfulcoverage, oldbackendfallback, cacheidentity andconditionaldeployment verificationexplicit.

- Architect pass: corrected available/schemaVersion/timeZone, locked normative leaf map and pending/failure codes, preserved Shop acquisition counts, shared the exact legacy/view lease, and specified external-memory accounting plus ACK cancellation. Coldwait shortened below existing15s clienttimeout. Previously approved Redis fail-closed policy is retained explicitly; no unbounded SQL fallback.


## Manual UI placement checklist

Run on iOS and Android with an admin account, including an uncached page whose calculation is pending.

1. Overview: status remains below range controls and above cards; freshness stays below the chart and above Explore. No duplicate banner or overlap.
2. Growth and Activity: status remains above metrics and freshness below. Activity's four feature rows stay on Activity. Today/7 days/30 days switching does not duplicate controls or charts.
3. Retention and Races & friends: existing metric groups keep their order. Overview cards never replace page content; status and freshness do not overlap groups.
4. Invites and Onboarding: tabs remain above status. Switching tabs shows only the selected tab's groups, with no duplicate status or leftover content.
5. Ads and Shop: Ads keeps its chart and reward groups. Shop keeps Most-purchased items followed by Recent purchases, filters, rows and Load more. Pending analytics never covers or replaces purchase history.
6. Freshness information sheets: content fits or scrolls, Close remains reachable, and dismissing leaves no overlay or duplicate footer.

Check long pending text on a narrow screen. Demo race tutorial, tab tutorial profile previews and onboarding previews contain no separate admin renderer. System health and Admin Tools configuration remain separate surfaces. This checklist is supplied by the required UI placement review; manual device execution remains pending.


## Frontend verification

The final frontend revision passes 77 focused tests: 20 page snapshot widget tests, 15 existing snapshot/purchase tests and 42 API wire-contract tests. `flutter analyze --no-pub` and `git diff --check` are clean. Independent code review concluded SHIP after tests-first corrections for queued requests after navigation/backgrounding, revisiting canceled pages and duplicate pending banners.

Both platforms use the same changed Dart code. No native build, version bump, configuration change or upload has been performed for this revision. Backend deployment precedes the next carrying app build. The manual device checklist above has not been executed.
