# Event traffic efficiency — app release candidate

Status: **ready for a separately authorized backend-first production release**. Final independent review: **SHIP**, no blockers. No upload or production deployment has occurred.

App implementation commit: `5687c8f`. Candidate version: 2.3.13 (12), with matching Android versionCode 203142. Backend runtime candidate: `f264099`, on the production-derived `event-traffic-efficiency-release` branch. The backend's original local main is not the deployment base; the release branch preserves the already-deployed immediate-join and Shop changes.

## Behavior

After successful race-resolution polling, Home can request `view=sync-refresh-v1` through BackendApiService. It replaces the complete core Home response and retains equipment/friends only when both are the exact current-account snapshots from a successful full shell accepted within 60 seconds. Retention never renews their age. Mutations, account changes and independently loaded replacement snapshots invalidate eligibility.

Cold open, deliberate refresh and ordinary navigation retain the existing full-shell path. Race-list/profile refreshes and polling intervals remain unchanged. Cached presentation cannot overwrite a newer profile balance. Request generations prevent stale core responses from replacing newer results, while independent event-summary receipts remain available unless already consumed by this account.

Older servers and malformed representations fall back once to the existing full shell; unsupported negotiation is scoped to the authenticated account/backend origin. Network/server failures retain coherent existing data without another immediate load. Optional reward and invite metadata is parsed defensively. No dependency, runtime flag, widget placement, asset or styling change is included.

## Validation

- Final full Flutter suite: **3,247 passed**.
- Focused real MainShell and API transport tests: **163 passed**.
- `flutter analyze`: **No issues found**.
- Independent code review: **SHIP**, with no remaining runtime findings.
- Tests cover both platform branches, demo/fake service fallback, malformed data, balances, section age/provenance, reversed requests, new completion during a request, account changes and consumed event summaries.

Source hashes and the test manifest are in [frontend-validation.json](evidence/event-traffic-efficiency/frontend-validation.json); the corresponding full, focused and analysis logs are preserved compressed alongside it. The version/build metadata was advanced after the reviewed runtime checks; both actual release artifacts must independently verify the resulting version, configuration, signature and fresh compiled code.

No manual placement checklist is required because no screen elements were added, moved or removed. Automated real-screen checks cover the affected presentation behavior.

## Verified production artifacts

Both README-authoritative production builds passed from app implementation commit `5687c8f`: iOS 2.3.13 (12) and Android 2.3.13 (203142). Signature and compiled configuration checks passed. iOS has production push entitlements and all seven required ad units, RevenueCat and Google values. Android bundletool validation, billing metadata and trusted upload-certificate checks passed; all three packaged ABI libraries exactly match independently stripped fresh compiler output. Both contain the new Home contract marker.

Artifact hashes and configuration checks are in [artifact-verification.json](evidence/event-traffic-efficiency/artifact-verification.json). Build records are in [build-execution.json](evidence/event-traffic-efficiency/build-execution.json). Local artifacts are under `build/release-candidates/event-traffic-efficiency-2.3.13-12/`.

## Performance evidence and reviewed exceptions

The fixed 36-run backend comparison completed with identical durable outcomes, unchanged accepted throughput, no request errors, and passing time-to-visible-results tails in every trace. Isolated combined Home/races/profile SQL fell **22→17** in all three pairs. The additional whole-report diagnostic remains **failed**: shared-one-race request p99 missed its ceiling by 1 ms; shared-five-race request p95 exceeded its ceiling, and total session SQL increased by 0.57% despite lower HTTP-path SQL. A rotated nine-run isolation experiment did not reproduce a consistent latency penalty from sharing or increased writer stalls. Its candidate mean SQL was 1,821 versus production 1,836.67. The reviewer approved readiness under the actual spec gates while retaining the original failed diagnostic and its small observed differences. This is not proof that all latency effects are zero.

The eventual deployment order is backend first, then the paired app release. Older apps retain their existing API behavior; new apps also work if the backend is rolled back. Production deployment and store uploads require separate authorization. The user's managed-database CPU objective must be measured after an authorized deployment under comparable real traffic; local SQL counts cannot establish that result.
