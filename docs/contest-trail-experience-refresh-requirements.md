# Contest Trail Experience Refresh — Requirements

Status: **APPROVED FOR IMPLEMENTATION**

This spec redesigns the customer-facing `BARA_ACCOUNT` contest experience. It
does not change contest eligibility, scoring, prizes, rules, lifecycle, or the
admin workflow. Historical `US_18` contests retain their existing customer
presentation for compatibility.

## 1. Summary and user story

The current global contest screen is a vertical stack of parchment cards. It is
clear, but it reads like an admin dashboard rather than Bara. Replace that
presentation with a playful, interactive pixel-world trail that feels related
to the onboarding scene shown in Bara's product identity.

As a Bara user, when I open a contest I should feel like I am stepping onto a
limited-time referral trail. Before joining, I can explore the route, read the
complete official rules, and understand exactly what makes a referral count.
After joining, the same trail becomes my progress map: my verified referral
count, provisional rank, leaderboard, and share action are visible without
turning the screen into a grid of cards.

The experience must remain transparent and accessible. Interaction adds
delight and hierarchy; it must never hide required rules, alter ranking, or
make the contest appear random.

## 2. Scope and non-goals

### In scope

- A new visual treatment for the global contest pre-entry route.
- A new visual treatment for the global contest joined/progress route.
- A shared pixel trail scene using existing Bara assets and palette tokens.
- Tappable trail landmarks that open explanatory panels or focus the relevant
  section of the same screen.
- A compact HUD for prize, contest status, verified referrals, and rank.
- A large, contextual share action that remains the primary joined-state CTA.
- Rules reading, rules acceptance, display-name recovery, loading, empty,
  error, verifying, and final-result states.
- iOS and Android behavior from the shared Flutter implementation.
- Regression/integration-style widget tests for the real `GiveawayScreen`.

### Non-goals

- No new contest endpoint, database column, migration, score formula, prize,
  eligibility rule, or lifecycle transition.
- No change to server-owned Official Rules or the acceptance request.
- No randomization, chance mechanic, gamification multiplier, or reward for
  tapping landmarks.
- No social follow requirement or scoring advantage.
- No new shippable artwork pipeline. Existing `HomeHeroScene` assets,
  `trail_sign_plank.png`, `coin.png`, and theme tokens are reused; any new
  shapes are UI chrome/custom-painted path geometry only.
- No redesign of the legacy US18 customer path, admin contest tools, Home
  banner, public web page, onboarding, or tutorial mirrors.

## 3. Existing seams and implementation ownership

- Customer contest routing and state switching are in
  `lib/screens/giveaway_screen.dart:209-214`.
- Global pre-entry and its sticky acceptance footer are in
  `lib/screens/giveaway_screen.dart:650-925`.
- Global joined/progress state is in
  `lib/screens/giveaway_screen.dart:1000-1145`.
- The reusable pixel-world backdrop is
  `lib/widgets/home_hero_scene.dart:17-220`; it already supplies the sky,
  clouds, tiled ground, motion, and reduced-motion behavior.
- Palette and typography tokens are in `lib/styles.dart`.
- Existing pixel assets include `assets/images/home_hero_sky.png`,
  `assets/images/home_hero_ground.png`,
  `assets/images/capybara_walk_right.png`,
  `assets/images/trail_sign_plank.png`, `assets/images/coin.png`, and
  `assets/images/title_feat_trophy.png`.
- The defensive contest DTO is `lib/models/giveaway.dart`; no new fields are
  required.
- The single HTTP surface is `lib/services/backend_api_service.dart:3681-3775`.
- Existing global experience coverage is in
  `test/referral_contest_global_frontend_test.dart` and legacy coverage is in
  `test/referral_giveaway_frontend_test.dart`.

## 4. Product and interaction design

### 4.1 Visual direction: “Referral Trail”

The screen is a continuous pixel scene, not a list of cards:

- A daytime sky/ground scene fills the route using `HomeHeroScene` and the
  same capybara/grass visual language as onboarding.
- A winding, high-contrast trail line crosses the scene from **START** to
  **SHARE**, **RACE**, and **WIN** landmarks. The trail is decorative UI
  geometry; it is not a scoring mechanic.
- Landmarks use compact wooden sign treatments, coin/trophy accents, and
  familiar checker/green/gold tokens. Avoid generic Material cards, gradients,
  or a dashboard grid.
- The current contest title and prize live in a small “mission HUD” over the
  scene. The full exact prize remains server-driven.
- The screen remains scrollable. On short devices, the scene compresses and
  the dock/controls remain reachable; no fixed pixel coordinates may clip text.

### 4.2 Pre-entry: mission briefing

For `ACTION_REQUIRED` global entrants:

1. The top scene introduces the contest with the title, coin prize, date/window,
   and status/countdown.
2. Four trail landmarks are visible. Tapping a landmark opens an inline
   briefing drawer or expands a focused section below the scene:
   - **START** — read and accept the rules;
   - **SHARE** — send the existing invite;
   - **RACE** — the friend must sign up and finish a qualifying race;
   - **WIN** — most verified completed referrals wins; ties use the published
     earliest-final-count rule.
3. The complete Official Rules remain in the same scrollable route beneath the
   scene. Landmark taps are shortcuts to content, not gates that can conceal
   required terms. A visible “OFFICIAL RULES” sign always opens/focuses the
   rules section.
4. A compact sticky “mission accepted?” dock contains the existing checkbox and
   **JOIN CONTEST** action. The action remains disabled until the user reaches
   the end of the rules and checks the box.
5. If a display name is missing, the dock becomes **SET DISPLAY NAME TO JOIN**
   and uses the existing recovery route. No new identity fields are added.
6. Scheduled, verifying, and malformed/unavailable states preserve their
   current safe behavior and never imply that an entrant joined when the server
   did not confirm it. `CANCELLED` contests are excluded from the current
   customer endpoint by the backend; if one is requested, the existing
   unavailable/retry state is correct. The canonical public rules page remains
   the historical cancellation destination outside this route.

### 4.3 Joined state: progress map

For an eligible, under-review, or otherwise joined global entrant:

- The scene becomes a progress map. The current entrant's verified referral
  count and provisional rank are shown in a small HUD or trail marker, not two
  unrelated cards.
- Completed/referral progress is represented by filled trail markers or coins.
  The visual is a direct display of the server count; it does not invent a cap
  or convert the count into a percentage.
- **SHARE YOUR INVITE** is the primary gold/checker action anchored near the
  active trail. It calls the existing share flow exactly once per user action.
- A **LEADERS** sign opens an accessible bottom sheet/drawer with the existing
  provisional leaderboard rows, current-user pinning, empty copy, and final
  copy. The same rows must remain available in a non-animated semantic tree.
- A **WHAT COUNTS?** sign opens the current plain-language explanation. It is
  an expansion/drawer, not a new scoring rule.
- **OFFICIAL RULES** opens the existing in-app rules screen or focuses the
  embedded rules content. Optional social links remain clearly optional and
  have no effect on score, eligibility, or odds.
- Verifying/final/no-winner/winner copy remains explicit. No confetti or winner
  animation may imply a final result before the backend reports `FINAL`.

### 4.4 Entry-status matrix

The visual redesign must make the existing parsed entry statuses explicit:

| Entry status | Visual state | Join/share behavior |
| --- | --- | --- |
| `ACTION_REQUIRED` | Mission briefing trail with rules and acceptance dock | Join is gated by read-to-end plus checkbox; no share before entry |
| `ELIGIBLE` | Joined progress map | Share is enabled only when the contest is `ACTIVE` and a valid share payload exists |
| `UNDER_REVIEW` | Joined progress map with review notice | Share follows the existing server-provided standing/share invariants; no claim that a reviewed fact is verified |
| `INELIGIBLE` | Read-only trail with clear ineligibility copy | No join and no share CTA |
| `WITHDRAWN` | Read-only trail with clear withdrawal copy | No join and no share CTA |

`SCHEDULED`, `VERIFYING`, and `FINAL` contest statuses overlay the applicable
entry state with their existing opening/review/final copy. `FINAL` winner and
no-winner states are tested for every entry status the DTO permits. A cancelled
contest is not a valid `/current/me` customer fixture: the backend excludes it,
so the route shows the existing unavailable state instead.

### 4.5 Rules-focus semantics

On pre-entry, START, SHARE, RACE, WIN, and OFFICIAL RULES landmarks all call a
local `Scrollable.ensureVisible`/focus callback for the corresponding embedded
briefing/rules section. They do not navigate away and they never set
`_readRulesToEnd` or `_rulesAccepted`. The user must still reach the actual end
of the embedded rules and check the existing acceptance checkbox before Join
enables. Returning from display-name recovery preserves both values.

On joined states, OFFICIAL RULES may open the existing `GiveawayRulesScreen`
using the same parsed rules object; it is a read-only destination and cannot
change entry state. WHAT COUNTS and LEADERS remain in-place drawers. No shortcut
may bypass or silently satisfy the pre-entry acceptance gate.

### 4.6 Motion and accessibility

- Landmark focus, drawer reveal, coin/path progress, and scene parallax use
  short, reversible animations. Honor `MediaQuery.disableAnimations` and keep
  tests deterministic.
- Every landmark has a `Semantics` label and a keyboard/screen-reader-reachable
  activation path. Important text is not conveyed by color or animation alone.
- Large text (at least 1.7x in existing tests), compact heights, dark mode, and
  reduced motion must remain readable and scrollable.
- Tapping a landmark should not cause the user to lose their scroll position or
  checkbox acceptance.
- Contrast must meet the existing palette's accessible pairings. Text on the
  green scene uses `textLight`; text on parchment uses `textDark`/`textMid`.

## 5. API contract and compatibility

There are **no API changes** in this refresh.

The screen continues to call the existing additive endpoints through
`BackendApiService`:

- `GET /giveaways/current/me` with the existing identity token and client
  feature header. The response remains `GiveawayCurrent` with contest, entry,
  leaderboard, standing, share, and winner data.
- `POST /giveaways/:slug/entries` for global entry with the existing body:
  `{rulesVersion, rulesAccepted: true}`. The server remains authoritative for
  display-name and lifecycle errors.
- Existing referral share-link flow for `GiveawayShare`.

The redesign must continue to fail closed if any required global response is
missing or malformed: render the existing unavailable/retry state and do not
show a stale rank, share link, or join action. Older app versions continue to
receive the same backend payload and keep their existing card-based global
experience. Legacy `US_18` payloads continue through their existing branch.
No release flag, capability gate, or new required server field is introduced.

## 6. Frontend implementation plan

1. Add a private, reusable trail-scene widget (prefer a new file under
   `lib/widgets/` so `giveaway_screen.dart` remains an orchestrator) that
   composes `HomeHeroScene`, scene geometry, landmark semantics, and focus
   callbacks.
2. Add a small mission HUD and landmark/drawer widgets that consume only
   already-parsed `GiveawayContest`, `GiveawayCurrent`, and existing palette
   tokens. Do not duplicate DTO parsing or HTTP calls.
3. Replace only the `BARA_ACCOUNT` branches `_globalPreEntry` and
   `_globalJoinedHub`; preserve the legacy branch and entry form unchanged.
4. Build the scene inside a finite `LayoutBuilder` constraint. For viewport
   height `h`, use `sceneHeight = clamp(280, h * 0.44, 420)` logical pixels,
   with a compact-height floor of 240 only when `h < 620`; for large text keep
   the scene at the compact bound and let the route scroll. `HomeHeroScene`
   must never receive unbounded height, and no `Expanded` may be placed inside
   the scroll view. The sticky footer remains outside the scroll view and uses
   the existing safe-area-aware padding.
5. Keep the existing rules-scroll controller, read-to-end progress, checkbox,
   `_joinGlobal`, display-name recovery, leaderboard data, and share function.
   Rewire their visual placement without changing request payloads or state
   semantics.
6. Keep `GiveawayRulesScreen` as the complete in-app rules destination. Any
   shortcut from the interactive trail must navigate to it with the same
   server-owned rules object.
7. Add defensive keys/semantics for landmarks, the mission HUD, share action,
   leaderboard drawer, and rules sign so real widget tests can exercise the
   public interaction path.

## 7. Test-first plan

Before implementation, add failing widget/integration-style tests that pump the
real `GiveawayScreen` with the existing fake service:

- global pre-entry renders the pixel trail landmarks and mission HUD without
  the old repeated card-stack labels;
- each landmark opens/focuses the correct explanatory content and retains the
  rules scroll/acceptance state;
- all official-rule text remains discoverable in the route and the join button
  stays disabled until read-to-end plus acceptance;
- joined state renders count/rank in the map HUD, opens leaderboard and
  “what counts” drawers, pins an out-of-list entrant, and shares through the
  existing callback;
- `ACTION_REQUIRED`, `ELIGIBLE`, `UNDER_REVIEW`, `INELIGIBLE`, and `WITHDRAWN`
  fixtures render the matrix above; final winner/no-winner, scheduled,
  verifying, loading, malformed, retry, and no-current/cancelled backend
  behavior fail safely;
- entry sends the unchanged `{rulesVersion, rulesAccepted: true}` body, share
  invokes the existing callback once, and rules shortcuts do not mutate the
  acceptance state;
- compact viewport, 1.7x text scale, dark palette, and reduced-motion paths do
  not overflow or lose semantics;
- legacy US18 tests remain unchanged and continue to pass.

Run `flutter test test/referral_contest_global_frontend_test.dart`,
`flutter test test/referral_giveaway_frontend_test.dart`, and
`flutter analyze`; full `flutter test` is required before completion. No backend
integration test or production deployment is needed because the API contract is
unchanged.

## 8. Acceptance criteria

- The global contest no longer presents as a vertical stack of generic cards.
- A user can understand and explore the contest as a Bara pixel trail before
  joining, while every material rule remains directly readable.
- A joined user can see verified count, rank, leaderboard, next action, and
  scoring explanation with at most one deliberate tap for secondary details.
- Existing join/share/rules/leaderboard semantics and payloads are unchanged.
- No new DTO field, capability token, endpoint, request field, cache, or
  persistence is introduced; the redesign reads only existing parsed fields.
- Old app versions and legacy contest payloads remain safe.
- iOS and Android render the same responsive Flutter experience.
- `flutter analyze` is clean, all relevant tests and the full suite pass, and
  the manual UI-placement checklist is completed on both platforms.

## 9. Revision log

- Draft 1: Converted the requested “fun and interactive” direction into a
  bounded pixel-trail experience using existing onboarding assets; explicitly
  preserved legal rules, server contracts, legacy contests, accessibility, and
  no-score-change constraints.
- Gap pass 1: Added landmark semantics/fallback content, reduced-motion and
  large-text requirements, direct rules discoverability, and explicit malformed
  response behavior.
- Gap pass 2: Added exact unchanged endpoint/body contracts, no-backend rollout
  reasoning, test-first coverage for every lifecycle state, and a non-goal
  against hidden rules or invented progress caps.
- Architect pass: Reconciled the backend's exclusion of `CANCELLED` from the
  current customer endpoint; added the full entry-status matrix, precise
  embedded-rules focus semantics, finite `HomeHeroScene` sizing, unchanged
  request/share assertions, and no-current/cancelled fail-closed tests.
- UI-placement pass: Added the 13-surface manual checklist covering Home,
  ReferralScreen, contest states, accessibility, both platforms, and legacy
  US18; recorded that no demo/tutorial mirror hosts `GiveawayScreen`.

## 10. Architect review

**REVIEWED — REQUIRED CHANGES FOLDED IN.** The architect found no API or
rollout blocker after the revisions above. Implementation must honor the status
matrix, finite scene constraints, and unchanged acceptance contract.

## 11. Manual UI-placement test plan

1. Home banner opens exactly one trail route; the banner remains in its single
   slot and tutorial Home suppresses it.
2. ReferralScreen keeps its existing contest summary and opens exactly one
   trail route; no duplicate trail is embedded there.
3. Pre-entry route shows one finite scene with mission HUD and START/SHARE/RACE/
   WIN landmarks; old repeated global cards are absent.
4. Each pre-entry landmark is touch- and screen-reader-activatable, focuses the
   correct embedded section once, and retains scroll/checkbox state.
5. Rules, progress marker, and sticky acceptance dock remain reachable above
   the safe area; Join stays gated until read-to-end plus acceptance.
6. Missing display name keeps the dock position and returns without duplicate
   routes or docks.
7. Joined state changes in place to the progress map; count/rank share one HUD
   and the old YOUR RUN cards are absent.
8. SHARE YOUR INVITE appears once as the primary active action and changes to a
   safe closed/verifying state when appropriate.
9. LEADERS opens an in-place accessible drawer with empty/final/current-user
   rows and restores map position on dismissal.
10. WHAT COUNTS and OFFICIAL RULES expose their content once; optional social
    links remain unscored.
11. Scheduled, verifying, final winner/no-winner, malformed, loading, retry,
    ineligible, withdrawn, and no-current states keep safe placement and do
    not expose misleading actions.
12. Repeat on iOS and Android at compact size, 1.7x text, dark mode, reduced
    motion, and with screen-reader activation; no clipping or lost semantics.
13. Historical US18 contests retain their existing card-based presentation.

Confirmed unaffected: demo race/tutorial/race-detail mirrors, onboarding,
races, boards, profile, admin giveaway tools, and other non-contest surfaces do
not host `GiveawayScreen`; verify Home/Referral entry points for duplication.
