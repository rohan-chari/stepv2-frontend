# Rewarded-ad preloading requirements

## Summary and user story

Rewarded ads should usually be ready by the time a user deliberately asks to
watch one. Today, some placements begin their first AdMob request only after a
screen fetch or button tap, which puts the full network-load delay in front of
the user.

As a user who chooses a rewarded action, I want the ad to open promptly so the
reward flow feels responsive, while the backend remains the authority for
eligibility and every loaded ad remains bound to the correct user, reward kind,
local date, item, or immutable offer.

This feature changes scheduling and ownership of existing rewarded-ad loads. It
does not change eligibility, caps, payouts, SSV verification, ad units, visible
placement, or the backend contracts.

## Current behavior and code map

`AdService` owns one loaded `RewardedAd` at a time. A load is a no-op while the
controller is already loading or ready, and SSV `userId`/`customData` are baked
onto the loaded object before `isReady` becomes true
(`lib/services/ad_service.dart:401-477`). Showing consumes the cached object
before presentation (`lib/services/ad_service.dart:487-528`). That means a
controller must never be shared between different SSV contexts.

| Placement | Current first-load trigger | Current ownership |
| --- | --- | --- |
| Daily extra spin | Home's `StreakChip` preloads after the server advertises a live offer (`lib/widgets/streak_chip.dart:106-121`, `:204-221`). The reward sheet retries after its status fetch (`lib/screens/daily_reward_screen.dart:102-124`, `:185-217`). | One controller lives for the `StreakChip` lifetime and is injected into the reward sheet (`lib/widgets/streak_chip.dart:78-82`, `:224-233`). |
| Get Coins | The screen awaits `fetchGetCoinsStatus`, stores the response, then calls `_maybePrepareAd` (`lib/screens/get_coins_screen.dart:87-115`). | The screen normally creates and disposes its own controller (`lib/screens/get_coins_screen.dart:71-84`). |
| Powerup/cosmetic ad unlock | A new controller is created after the user taps; each loop iteration awaits `load` before `show` (`lib/screens/tabs/shop_tab.dart:1692-1768`, `:1785-1829`). | Ephemeral controller owned by that tap flow. |
| Mystery-box reroll / reroll all | First load occurs inside the tap handler; after a successful claim, the next ad is warmed (`lib/screens/race_detail_screen.dart:6478-6506`, `:6564-6597`). | Lazy controller lives for the race-detail screen and is namespaced `box_reroll` (`lib/screens/race_detail_screen.dart:6459-6467`). |
| Race payout bonus | The tap handler may first create the backend offer, then loads and shows the ad (`lib/screens/race_results_summary_screen.dart:120-187`). | Controller is created by `MainShell`, passed to the popup, and disposed by the popup (`lib/screens/main_shell.dart:2466-2487`; `lib/screens/race_results_summary_screen.dart:91-95`). |

## Goals

1. Move each safe ad request earlier than the user's final watch tap.
2. Keep all SSV identity and context binding exactly correct.
3. Never show an ad solely because it was preloaded; the existing user gesture
   and current backend eligibility checks remain mandatory.
4. Bound cache age, retry volume, memory, and wasted requests.
5. Preserve existing loading, retry, error, and pending-grant recovery paths.
6. Work identically on iOS and Android when that placement's build-time ad unit
   is configured, and remain hidden/unsupported otherwise.

## Non-goals

- No new rewarded placement, ad format, banner/native change, or app-open ad.
- No changes to reward amounts, odds, daily caps, eligibility, or coin economy.
- No backend endpoint, payload, database, migration, SSV callback, or AdMob
  configuration change.
- No feature flag, rollout percentage, kill switch, runtime toggle, or
  temporary environment control.
- No automatic ad presentation and no loading screen added to app startup.
- No change to ATT consent meaning, consent handling, or mediation policy. The
  first ATT prompt may intentionally move earlier—from the user's first ad
  interaction to the first authenticated, post-onboarding Home frame—but it
  must never occur during unauthenticated cold startup, onboarding, demo, or
  tutorial preview.
- No unbounded cache of ads or speculative preload for every catalog item.

## Product behavior by placement

### 1. Daily extra spin

Keep the current Home-ticket preload as the primary path. It already waits for
the backend to advertise `adExtraSpin`, binds the current user and local date,
and passes the same controller into `DailyRewardScreen`.

Changes are limited to shared cache-freshness handling and recovery:

- A cached ad older than the configured freshness window is disposed and
  reloaded before it is reported ready.
- On app resume, if the ticket is still available and the cached ad is stale or
  absent, request one bounded retry.
- A pending verified grant never causes another ad request.
- Date rollover disposes yesterday's ad before loading today's context.

### 2. Get Coins

This is the highest-priority latency improvement.

- Add one session-scoped, Get-Coins-only controller owner after authentication
  is restored. It may live in `MainShell` or a narrowly scoped coordinator
  owned by `MainShell`; it must not be a process-global singleton.
- After the authenticated Home shell has rendered its first frame, begin one
  background Get Coins load for `coins:<current-local-date>`. Do not block Home
  rendering.
- Inject that same controller into every `GetCoinsScreen` entry point, including
  Home and Shop. An injected controller remains owned by the session owner and
  must not be disposed by the screen.
- `GetCoinsScreen` starts `fetchGetCoinsStatus` immediately and observes the
  existing controller concurrently. The section remains hidden until the
  backend returns an `adCoinReward` block. A ready ad does not imply eligibility.
- If the response says `pendingGrant:true`, preserve the existing claim-without-
  another-ad behavior; a speculative cached ad may remain cached for a later
  watch while watches remain, otherwise dispose it.
- If the response omits the block, reports no remaining watches, or the account
  changes, dispose the speculative cached ad.
- After every completed or dismissed ad, start rearming only when the latest
  status still permits another watch. The action must retain its existing
  `TRY AGAIN` recovery behavior after a failed load.

This deliberately warms only after authenticated Home is active. Calling
`AdService.ensureInitialized` at process launch could surface the existing iOS
ATT request before identity/session restoration and is out of scope.

Implementation ownership is explicit:

- Add an optional Get Coins coordinator/factory dependency to `MainShell` for
  production ownership and test injection.
- Create one warm future per `(authGeneration, userId, localDate)` and inject
  its controller through `HomeTab`, `_openShop`, and every Home/Shop
  `GetCoinsScreen` route builder.
- The post-frame trigger captures token, user ID, auth generation, onboarding
  completion, and mounted state, then rechecks all of them before calling warm.
- The existing `MainShell` auth listener invalidates and disposes the old
  generation before any new identity warms; shell disposal owns final cleanup
  (`lib/screens/main_shell.dart:646`, `:776`).

### 3. Powerup and cosmetic unlocks

The SSV context contains a specific SKU, so the app must not cache a generic
shop-unlock ad or reuse one SKU's ad for another item.

- Maintain at most one speculative shop-unlock target at a time.
- Begin loading when a detail sheet is open and the currently displayed item is
  confirmed by the existing server payload to route to `watchAds`.
- Key the cached controller by `(rewardKind, userId, sku, localDate)`, with
  distinct `powerup_unlock` and `shop_unlock` contexts.
- If the sheet closes, the route changes, the catalog refresh changes
  eligibility, the account changes, or a different item becomes the target,
  dispose the old controller.
- On tap, consume the matching ready controller. If absent or stale, retain the
  current load-on-demand fallback and error copy.
- If more than one ad is required by a compatible backend payload, use a
  two-controller handoff: while ad N is fullscreen, preload ad N+1 with the
  identical context. Never hold more than one current ad plus one next ad.
- Stop and dispose the next controller when the user closes early, the route is
  disposed, or the backend mutation fails.

Only a present, valid server `adUnlock` block permits speculative Shop preload.
An older backend that omits the block retains the current legacy action and
load-on-tap behavior; omission must neither speculate nor remove that action.

### 4. Mystery-box reroll and reroll all

- Build the existing lazy `box_reroll` controller and start loading as soon as
  an opened-box or Open All overlay exposes a valid reroll action—not when the
  race-detail screen initially loads.
- Use the same `(userId, localDate)` namespaced context already used by both
  single and batch reroll.
- Keep one controller shared by single reroll and reroll-all because the backend
  intentionally uses one reward kind/context shape for these actions.
- Preserve the current load-on-tap fallback and post-success next-ad warmup.
- Dispose on local-date rollover, account change, race-detail disposal, or when
  the backend stops advertising the relevant reroll capability.
- Never preload in demo/tutorial mode or when the platform-specific dedicated
  reroll ad unit is absent.

### 5. Race payout bonus

An ad cannot be safely loaded until an immutable `offerId` exists because SSV
custom data is `race_payout_double:<userId>:<offerId>`.

- Create one popup-owned preparation future. After the first frame it performs
  the existing pending-offer recovery first, including the current bounded five
  `AD_NOT_VERIFIED` attempts. Only when recovery establishes that no verified
  grant is claimable does it create a missing offer and warm the exact ad.
- Both the post-frame trigger and button join this same preparation future; a
  tap cannot be dropped and cannot start a parallel create/load operation.
- When the results popup receives an eligible descriptor without an `offerId`,
  the preparation future creates the offer using the existing endpoint and
  inputs rather than waiting for the button tap.
- After a valid offer is returned, immediately load the dedicated payout ad in
  the background for that exact offer ID.
- If the popup already receives an `offerId`, begin preload directly after the
  existing pending-offer recovery check establishes that the offer is still
  claimable.
- The button still owns presentation. If preload is incomplete, tapping enters
  the existing loading state and awaits the in-flight request rather than
  starting a duplicate request.
- Recovery takes precedence: if the server reports an already verified pending
  offer, claim it without showing another ad.
- Backend payout offers have no time-based expiry. A stale cached ad reloads
  against the same immutable offer ID. Dispose on server rejection, popup
  dismissal, account change, acknowledgement forfeiture, or completion.
- Capture and recheck user/popup generation around every async completion.
  A production controller transferred into the popup becomes popup-owned;
  explicitly caller-owned injected test controllers are never double-disposed.

## Shared frontend design

### Context-bound controller metadata

Define one immutable `RewardedAdContext` and extend the frontend ad abstraction
or add a small wrapper so each cached ad has:

```text
placement
userId
customData
localDate (cache metadata where applicable)
loadedAt
loadFuture (while in flight)
```

The wrapper exposes these semantics:

- `warm(context)`: idempotently return the same in-flight future or keep a
  fresh matching ad; replace only an absent, stale, or context-mismatched ad.
- `isReadyFor(context)`: true only for a fresh ad with an exact context match.
- `showAndAwaitReward(context)`: refuse to show on mismatch, consume the ad
  once, and preserve the current earned/dismissed result contract.
- `disposeContext(context)` / `dispose()`: release native objects promptly.

Every preload-capable production path must use the context-taking readiness and
show methods. The existing unscoped interfaces may remain only as adapters for
legacy tests/non-preloaded call sites during migration; they must not provide a
route around context enforcement.

The exact SSV custom-data matrix is:

| Placement | SSV custom data | Cache-only identity |
| --- | --- | --- |
| Daily extra spin | `<localDate>` | placement, user ID, local date |
| Get Coins | `coins:<localDate>` | placement, user ID, local date |
| Powerup unlock | `powerup_unlock:<userId>:<sku>` | placement, user ID, SKU, local date |
| Cosmetic unlock | `shop_unlock:<userId>:<sku>` | placement, user ID, SKU, local date |
| Box reroll | `box_reroll:<userId>:<localDate>` | placement, user ID, local date |
| Race payout | `race_payout_double:<userId>:<offerId>` | placement, user ID, offer ID |

Shop's local date is cache metadata only and must not be appended to custom
data; the backend interprets everything after the user segment as the SKU.
Every placement rejects an empty user ID. Remove the Shop flow's current
`'user'` fallback rather than minting ambiguous SSV context.

`AdService` currently treats `load()` as a no-op whenever `_ad != null`; without
context metadata that can silently retain an ad loaded for an old date/SKU.
The implementation must make mismatch replacement explicit rather than rely on
callers to remember disposal.

### Freshness

Record the successful load time. Rewarded ads should be treated as stale before
Google's documented one-hour expiration; use a conservative 45-minute maximum
cache age. A stale ad is disposed and reloaded on the next warm/readiness check.
Do not install a periodic timer. Lifecycle resume, screen intent, and watch taps
are sufficient freshness checkpoints.

### Retry and concurrency

- One in-flight load per owner, not merely per exact context. Context changes
  use latest-target coalescing: at most one obsolete uncancellable native
  request plus one current/queued target may exist. Further replacements only
  replace the queued target.
- No immediate automatic retry from a failed-load callback.
- At most one bounded retry on a later user/lifecycle trigger; existing manual
  `TRY AGAIN` actions remain available.
- Never run an unbounded timer or reconnect loop.
- A late callback for a disposed/replaced context must dispose its native ad and
  must not become ready.
- App/account disposal invalidates all in-flight generations so a callback from
  the old user cannot populate the new user's cache.
- The Shop N/N+1 two-controller handoff is the sole exception to the one-load-
  per-owner bound and may hold only the fullscreen current ad plus one next ad.

### SDK initialization

Replace the completed-state-only initialization guard with a shared single-
flight future. Concurrent placement controllers join one initializer, yielding
at most one ATT request, mediation privacy setup, and Mobile Ads initialization.
Clear a failed future only after it settles so a later deliberate trigger can
retry. Missing real unit, unauthenticated, onboarding, demo, and tutorial paths
must return before SDK initialization.

Inject an SDK initializer, rewarded-ad loader, native-ad handle, clock, and
local-date provider at the service boundary for deterministic tests. Production
defaults continue to call the existing Google Mobile Ads SDK.

### Lifecycle and ownership

- Session-level Get Coins cache: owned and disposed by the authenticated shell.
- Daily extra spin: owned by `StreakChip` unless injected.
- Shop unlock: owned by the active shop detail/action flow.
- Box reroll: owned by race detail.
- Payout bonus: owned by the results popup unless explicitly injected with a
  caller-owned test seam.
- Logout/account switch disposes every cache before the new identity can warm.
- Resume revalidates date and freshness; backgrounding alone does not discard a
  fresh ad.

### Ad-unit support matrix

| Placement | Required/fallback policy for preload |
| --- | --- |
| Daily extra spin and Get Coins | Require the real platform extra-spin unit; gate on the same predicate used to advertise the `ads` client capability. Never initialize or warm against the Google test fallback merely because the OS is supported. |
| Powerup/cosmetic Shop unlock | Preserve the existing dedicated powerup-unit → real extra-spin-unit fallback. Add no new cross-placement fallback. |
| Mystery-box reroll | Require its dedicated platform unit; no fallback. |
| Race payout | Require its dedicated platform unit; no fallback. |

Debug/test builds may use explicitly injected fake/test controllers in tests;
the production speculative scheduler follows the matrix above.

## API contract

No API contract changes.

The frontend continues using the existing additive and defensive contracts:

- Get Coins eligibility comes only from `adCoinReward` in the current Get Coins
  status response.
- Extra spin comes only from `adExtraSpin`.
- Shop unlock comes only from existing `adUnlock` data and existing mutation
  endpoints.
- Box reroll comes only from the existing race-progress capability fields.
- Race payout uses the existing create/claim offer endpoints and opaque offer
  IDs.

Missing, null, malformed, 404, expired, or older-backend fields preserve the
current hidden/fallback behavior. A cached client-side ad never manufactures an
offer and never bypasses a backend check.

## Data model and migrations

None. Cache metadata is in-memory only and is discarded on process death,
logout, account switch, invalidation, or owner disposal.

## Backward compatibility and rollout

- Frontend-only release; no backend deploy is required.
- Frozen older app versions continue their existing on-demand/preload behavior.
- The current production backend remains compatible because requests and
  payloads do not change.
- There is no mixed-version server behavior and no new required field.
- Both iOS and Android ship together with unchanged backend URL, flavors, and
  ad-unit defines.
- Unsupported platforms and absent units follow the exact support matrix above;
  notably, Shop preserves its existing intentional real-unit fallback while no
  new or unsafe fallback is introduced.
- No release flag is introduced. The permanent behavior is safe because it
  changes request timing only, while presentation and reward authority remain
  unchanged.

## Analytics and observability

Do not count a preload as a rewarded watch or reward funnel completion.
Preserve existing offer-shown, ad-ready, earned, and verified/claimed events.
Debug logging may add placement-safe load timing and outcomes, but must not log
email, display name, ad identifiers, raw SSV custom data, or tokens.

Recommended local timing fields for tests/debug builds are placement, trigger
(`session`, `offer`, `sheet`, `overlay`, `tap_fallback`, `resume`), cache hit,
and elapsed milliseconds. No new backend analytics endpoint is required.

## Frontend implementation path

1. Write tests for context matching, in-flight deduplication, stale eviction,
   late-callback invalidation, initialization single-flight, exact SSV options,
   and disposal before changing `AdService`.
2. Add the smallest context-aware cache/wrapper in
   `lib/services/ad_service.dart` or a focused sibling service. Preserve the
   existing injectable controller interfaces used by widget tests.
3. Add session ownership for the Get Coins controller in `MainShell`; inject it
   through `HomeTab`, `_openShop`, and all Home/Shop Get Coins route builders.
   Begin warmup only after an authenticated, post-onboarding Home first frame.
4. Change `GetCoinsScreen` so status fetching and readiness observation run in
   parallel while backend eligibility still gates rendering and presentation.
5. Add one SKU-bound speculative controller to Shop detail flow and consume it
   in both powerup and cosmetic paths. Implement the bounded next-ad handoff for
   multi-ad payloads.
6. Trigger the existing box-reroll controller from the eligible opening overlay
   lifecycle and preserve tap fallback/post-success rearm.
7. Split race payout preparation from presentation: prepare/recover the offer,
   warm its exact ad, then let the existing button show or await it.
8. Add lifecycle invalidation for logout/account changes, local-date rollover,
   staleness, and route disposal.
9. Run formatting, `flutter analyze`, focused widget suites, then full
   `flutter test`. Account for both iOS and Android build configuration.

## Tests-first plan

### Shared service tests

- Same context + concurrent warm calls issue exactly one SDK load.
- Multiple placement controllers concurrently warming cause exactly one SDK
  initialization and at most one ATT request.
- Unit support follows the exact placement matrix; missing-unit, onboarding,
  unauthenticated, demo, and tutorial paths never initialize the SDK.
- The injected loader receives exact user ID and SSV options for every row in
  the SSV matrix, including Shop's SKU with no appended local date.
- Exact context mismatch (placement, user, custom data) disposes the old ad and
  cannot show it.
- A 44-minute ad remains ready; a 46-minute ad is stale and reloads using an
  injected clock.
- A late successful callback after context replacement/disposal is discarded.
- Show consumes readiness once; earned, dismissed, show-failed, and timeout
  results retain current behavior.
- Unsupported platform remains a no-op.

### Widget/integration-style frontend tests

- Pump authenticated Home with a Get Coins controller and verify warm begins
  after first frame without navigating.
- Open Get Coins while status is unresolved: preload runs concurrently, the ad
  section remains status-gated, then becomes ready without a second load.
- Missing/disabled/cap-reached status never exposes the watch action and
  disposes an unused speculative ad.
- Pending Get Coins grant claims without showing the preloaded ad.
- Logout/account switch prevents an old user's ready or late-loading ad from
  being shown by the new user.
- Rapid context churn coalesces to the latest target and respects the aggregate
  per-owner native-load bound.
- Daily ticket reuses its fresh controller, retries stale/failed loads, and
  never loads for pending grants or yesterday's date.
- Eligible Shop item detail starts exactly one SKU-bound preload; changing item
  or closing the sheet disposes it; the action falls back to on-demand load.
- An older backend with no `adUnlock` block retains the existing legacy action,
  performs no speculative load, and still loads on tap.
- A multi-ad Shop flow warms N+1 while N is fullscreen and aborts/disposes on
  early close.
- Eligible single and Open All box overlays preload; demo mode, absent unit,
  and disabled backend fields do not.
- Race payout offer preparation starts after popup render, binds the returned
  offer ID, and the tap uses the same ad. Expired/already-claimed offers never
  show a stale ad. Post-frame and tap paths join one preparation future;
  verified-pending recovery runs before warming.
- Missing, null, and malformed offer/status/capability blocks all preserve the
  defensive hidden or on-demand fallback behavior.
- `TutorialRealHost` receives an unsupported fake rewarded controller and
  `TutorialPreviewBackendApiService` supplies an offline Get Coins status path,
  proving tutorial previews never initialize ads or make live status calls.
- Demo race box overlays check `demoMode` before controller creation or warmup.
- Existing retry/error copy and all protected assertions remain unchanged.

Tests must pump real screens/widgets and assert the public behavior. Unit tests
are reserved for the structurally internal cache concurrency/clock properties
that cannot be expressed reliably through a widget path.

## Acceptance criteria

1. Get Coins begins one correctly bound preload after authenticated Home loads,
   and opening the page does not wait for status before starting that load.
2. Every rewarded placement has an earlier safe warm trigger plus its existing
   on-demand fallback.
3. No ad can be shown for a different user, local date, reward kind, SKU, or
   race-payout offer than the context used when it loaded.
4. Ads older than 45 minutes are never shown.
5. No placement automatically presents an ad or bypasses backend eligibility,
   SSV verification, daily caps, or pending-grant recovery.
6. Cache size and retries are bounded as specified.
7. Existing unsupported/missing-field behavior works on older backends and
   frozen clients remain unaffected.
8. Both iOS and Android are accounted for and the exact ad-unit support matrix
   is preserved; no new or unsafe cross-placement fallback is introduced.
9. Relevant tests pass, full `flutter test` passes, and `flutter analyze` is
   clean.

## Manual UI-placement test plan

No placement checklist is required because this feature adds, moves, resizes,
and removes no visible UI element. Mirror behavior still requires explicit
manual checks:

- Tutorial real-Home preview: no ATT prompt, live status call, or ad warmup.
- Demo race box overlay: no reroll controller creation or ad warmup.
- Real Home/Get Coins, Shop sheets, race box overlays, daily reward sheet, and
  results popup: existing loading/ready/error states transition without flicker
  and with unchanged layout on both iOS and Android.

## Definition of done

- Tests were written first and failed for the intended reason.
- Implementation follows the ownership/context rules above.
- `flutter analyze` is clean and relevant plus full tests pass.
- iOS and Android configuration is unchanged and both are accounted for.
- Version-skew reasoning is recorded in the handoff.
- The required architect and post-implementation code-reviewer reviews have
  completed with all required findings resolved.

## Revision log

- Draft: mapped all five rewarded placements and specified placement-specific
  warm triggers, ownership, SSV context boundaries, and fallbacks.
- Gap pass 1: rejected cold-start loading because it could advance the iOS ATT
  prompt; added authenticated-first-frame timing, logout/account invalidation,
  local-date rollover, and pending-grant handling.
- Gap pass 2: added 45-minute freshness, late-callback generation safety,
  in-flight deduplication, bounded cache/retry rules, SKU-specific Shop caching,
  immutable payout-offer binding, and explicit no-API/no-migration rollout.
- Architect review: revised the ad-unit support matrix; made ATT timing explicit;
  required single-flight SDK initialization and mandatory immutable contexts;
  added exact SSV formats, aggregate load bounds, concrete `MainShell` ownership,
  old-backend Shop fallback, payout preparation/recovery serialization, injected
  SDK seams, and demo/tutorial protections. Also adopted the suggested clock,
  malformed-payload coverage, and corrected payout ownership semantics.
