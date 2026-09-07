# Home rewarded coins

## Summary and authorization
Add a compact optional rewarded-coins row directly below Home's Today's coins
milestone track and before Races. Keep the existing Get Coins offer. The user
approved this placement and explicitly requested implementation; no further
product approval is needed for this scope.

## Scope and contract
Frontend only, subject to confirming the existing API contract. Reuse
BackendApiService.fetchGetCoinsStatus and claimAdCoinReward, the getCoins
RewardedAdContext, existing SSV validation, and the SAME server daily allowance.
No new rewards, amounts, caps, endpoints, migrations, flags, or deployments.
Existing older clients continue unchanged. An older backend without adCoinReward
causes the new row to disappear safely. Do not assume malformed/null fields are
valid numbers; use defensive parsing and avoid advertising invented amounts.

## Frontend implementation
Relevant sources: lib/screens/get_coins_screen.dart (existing complete flow),
lib/screens/tabs/home_tab.dart (milestones followed by Races),
lib/widgets/step_milestones_section.dart (16px horizontal section inset), and
lib/screens/main_shell.dart (session-owned get-coins ad controller).

Extract/reuse the rewarded-coins flow so Home and Get Coins cannot diverge.
Prefer a shared controller/state abstraction and compact Home presentation,
preserving Get Coins layout and all existing behavior/assertions. Both surfaces
must observe refreshed allowance after either claims. Home must not require
navigating to Get Coins: WATCH AD starts the existing flow directly. Preserve
shared controller ownership; never dispose another mounted surface's ad on an
ordinary route transition. Deduplicate active reward actions and stale async
results across account/token changes, date rollover, route changes and disposal.

The Home row uses existing parchment/pixel typography and rewarded button style,
with Bonus coins, server reward range, remaining ads today, and WATCH AD. At
narrow widths/large text wrap or stack without overflow. Keep milestones first.
While preparing an ad use a disabled loading action; on no-fill allow retry.
Hide when unsupported, missing status, exhausted (unless an unclaimed verified
grant is available), onboarding, or tutorial/demo. A pending verified grant must
be claimable without another ad. Failure must recover safely; earned coins and
remaining allowance update immediately from authoritative claim/status data.
Home pull-to-refresh, resume/date rollover and return from Get Coins must refresh
eligibility without reload loops from auth coin-balance notifications. No forced
ads and no ad SDK requests from demo/tutorial mirrors.

## Data and compatibility
Use existing status and claim request/response shapes without changes. The backend
contract reviewer records exact relevant shapes and error behavior below before
implementation. No database work. Platform support comes from existing controller
and configured units on both iOS/Android; unsupported platforms hide the row.
No backend deploy needed if contract verification passes; app release only.

## Tests first
Before business logic changes add failing real-widget tests for Home placement,
direct watch/claim, range/count, balance update and exhausted collapse; continued
Get Coins availability and cross-surface shared allowance; pending grant recovery;
ad cancel/failure/no fill; missing/null/malformed status; unsupported platform;
auth/date stale completion; tutorial isolation and narrow/large-text layout.
Reuse public widget/API fake patterns from test/get_coins_screen_test.dart.
Never weaken existing assertions. Backend agent verifies contract read-only and
does not create backend tests/mutations when no backend change is necessary.

## Acceptance and release readiness
Both entry points work with the same entitlement and server verification.
flutter analyze clean, relevant tests and full flutter test pass, code-reviewer
review completed, and manual placement checklist delivered. Both platforms
accounted for; consult DEPLOYMENT.md for any artifact checks required to claim
ready for deployment. No upload, store submission or customer release requested.

## Revision log
- Gap pass 1: explicit cross-surface state sharing and ad ownership; exhausted
  pending grants remain recoverable; no allowance changes.
- Gap pass 2: exclude demo/onboarding requests, refresh on return/date rollover,
  avoid auth notification loops, malformed fields and accessible narrow layouts.
- Economy review from prior discussion: unchanged reward per watch and maximum
  allowance; uptake may increase actual issuance. Do not introduce placement caps.
- Architect re-review: APPROVED after session ownership and contract revisions;
  test stale pre-claim status completion cannot restore spent allowance.
- Backend implementation role: no backend changes necessary; contract locked.
- Code review: fixed unsupported-device hub status loading, kept shared business
  state alive through token/SDK refreshes, and added a cancellable next-midnight
  refresh. Re-review approved with no remaining findings.
- Tests-first evidence: initial Home widget tests failed on the four missing
  placement/action/recovery behaviors before implementation; midnight regression
  also failed before its fix. Existing Get Coins assertions preserved.
- Full-suite review caught that awaiting ad status delayed Home refresh. Home now
  starts supported reward refresh independently and returns its existing health
  refresh future; original cooldown tests remain unchanged and pass.

## Verification record
- Full Flutter suite: 2,995 tests passed after the refresh fix.
- Final focused Home suite: 25 tests passed, including direct claims, shared
  navigation allowance, pending grants, no-fill/cancel/recovery, unsupported and
  malformed status, stale replies, account/date boundaries, disposal, foreground
  midnight, and narrow/large-text placement.
- Existing Get Coins and Main Shell tests retained; new token-refresh regression
  exercises the open Get Coins screen through Main Shell.
- Final code review approved with no outstanding findings.
- Android production AAB builds successfully and its release signature verifies.
- Final flutter analyze: no issues. Final iOS archive and App Store IPA export
  succeed. Xcode reports the existing placeholder launch-image warning; this
  feature does not change launch assets. Archive signature validation passes.
- Release validation uses existing app version 2.3.13. No version bump, backend
  deployment, store upload, or customer release performed. Android retains the
  existing deployment configuration (rewarded offer hidden if its unit is absent).
- Physical-device placement and live rewarded-ad checks remain manual; the
  checklist below is provided for that release review.

## Contract review
Existing frontend contract: GET /daily-reward/status?view=get-coins-v1&localDate=YYYY-MM-DD,
POST /coins/claim-ad-reward with JSON {"localDate":"YYYY-MM-DD"}. Existing
adCoinReward fields include available, pendingGrant, remainingToday, dailyCap,
coinAmount, coinRewardMin, coinRewardMax. Claim returns coinAmount, coins,
remainingToday. Preserve bounded five-attempt/two-second retry ONLY on 409
"no verified ad reward"; other failures refresh and offer recovery.
Backend-role review locked this existing contract: supported clients already send
ads,ad_coin_random capabilities. Reward range fields are conditional on the
latter. SSV context remains coins:YYYY-MM-DD. Grant consumption and balance credit
are transactional and idempotent by grant ID. No new placement parameter.
400 covers invalid/skewed dates, 409 AD_NOT_VERIFIED allows bounded retry,
409 DAILY_CAP_REACHED is terminal, 503 is disabled and 500 is unexpected failure.
Current backend counts consumed grants; a final pending grant has remainingToday=1.
At zero it emits pendingGrant=false and rejects claims. No beyond-cap claim is
promised. Legacy coinAmount alone is not a guaranteed future payout; use generic
Home wording if valid range fields are absent. This is source contract verification,
not a live production deployment audit. Existing Get Coins uses this same contract.

Architect required revisions: use one session-owned shared business-state
controller (not just shared SDK controller), passed through Home AND both Shop
Get Coins entry points. It owns status, serialized actions, and generation/token
guards. Screens subscribe/detach; shell owns lifetime. Standalone screen injection
remains supported. Refresh independently of health-sync success, coalesce requests,
and avoid periodic polling. Preserve legacy Get Coins confirmed defaults if tests
require its current contract; Home must omit unknown reward amounts or hide the
offer rather than advertise invented figures. Preserve the bounded SSV retry.

## Manual UI-placement test plan
**Manual UI-Placement Test Plan — Home rewarded coins**

*Elements under test:*  
Add one compact Bonus coins row beneath Today’s Coins milestones and above Races.  
Keep the existing rewarded-ad card on Get Coins in its current position.

*Checklist*

1. **Surface:** Real Home — repeat on iOS and Android.  
   **Get there:** Sign in with onboarding complete and rewarded coins available → Home → Today’s Coins.  
   **Verify:** Exactly one Bonus coins row appears directly below the milestone track and before Races, aligned with the section inset. It does not appear above the milestones, inside a race card, or as a duplicate elsewhere on Home.

2. **Surface:** Existing Get Coins.  
   **Get there:** Home → coin badge **+**.  
   **Verify:** The existing watch-ad card remains above Invite Friends and the daily reward card. There is no second compact Home row on this page. Return to Home and confirm only one compact row remains there.

3. **Surface:** Real Home with no available offer.  
   **Get there:** Use a test account whose daily allowance is exhausted and has no pending reward → Home.  
   **Verify:** The Bonus coins row is absent, with no empty card or reserved gap between milestones and Races.

4. **Surface:** Narrow Home and Get Coins.  
   **Get there:** Use a small-screen phone; increase system text size → Home → Today’s Coins, then coin badge **+**.  
   **Verify:** The row’s details and button remain fully visible without overlap or horizontal clipping. Races stays below the complete row; the existing Get Coins card remains reachable without duplicated controls.

5. **Surface:** Tab tutorial — shared real Home screen.  
   **Get there:** Profile → Settings → Help & Legal → View Tutorial → Home preview.  
   **Verify:** No Bonus coins row appears. Milestones and Races retain their tutorial order, and the Home steps spotlight still surrounds the step display.

6. **Surface:** Onboarding and playable demo tutorial.  
   **Get there:** Fresh test account → onboarding → demo race → remaining onboarding steps.  
   **Verify:** No Home Bonus coins row appears in onboarding panels, demo race screens, or demo results. It can appear only after reaching the real Home screen.

*Surfaces confirmed unaffected:*  
Other tab previews: they render their own tab widgets; only the tutorial Home preview shares `HomeTab`.  
Demo race detail and box-opening mirrors: they do not render `HomeTab` or Get Coins.  
Tutorial tab-bar chrome: no tab changes are required.

*Risks found while planning:*  
Tutorial Home reuses the production widget; preserve `isTutorialPreview` exclusion and the unsupported tutorial ad controller.  
The milestones section carries `tutorialMilestonesKey`; keep the new row outside that keyed section so its anchor does not expand to include the offer.  
Get Coins must retain its original card while Home adds a separate compact presentation; extracting shared behavior must not duplicate either presentation.
