# Inbox redesign and primary navigation

## Status

Approved for implementation by product direction in the requesting thread.

## Summary & user story

Inbox is a focused, durable place for things that need the player's attention,
not a general notification archive. A player should be able to open Inbox and
quickly understand what requires a response, action, or meaningful follow-up.

The primary shell navigation has five destinations: Home, Races, Leaderboard,
Friends, and Inbox. Profile remains available from the Home/profile entry point
and is removed from the bottom navigation so the bar does not become cramped.

## Scope / non-goals

In scope:

- Replace the current Alerts/Support segmented presentation with one unified
  Inbox feed.
- Classify existing alert rows into actionable/important Inbox content and
  suppress low-value informational events from the visible feed.
- Give rows a clear category, unread treatment, timestamp, and destination CTA.
- Add a useful caught-up state and error/retry state in the existing Bara visual
  system.
- Restore Leaderboard as a bottom-nav destination and move Profile access to the
  Home/profile chrome without reducing touch-target sizes.
- Update the hand-copied tutorial tab bar to match the production tab bar.
- Preserve iOS and Android behavior through the shared Dart implementation.

Out of scope:

- Removing or changing backend alert creation, retention, push delivery, or API
  fields in this release.
- Changing support thread behavior or adding player-to-player messaging.
- Adding a release flag or rollout control.
- Changing the meaning of existing alert destinations.

## Product policy

Visible Inbox content is limited to:

- Support replies and open feedback threads.
- Invitations or requests requiring a response.
- Important race/tournament state changes: cancellation, completion, start,
  team-lead changes, or similarly consequential participation updates.
- Reward/account outcomes that require attention.
- A small allowlist of genuinely important announcements.

Routine placement changes, step milestones, reminders, powerup activity, and
other contextual events remain accessible through their contextual screens or
push notifications but do not render as durable Inbox rows. Unknown alert types
are suppressed safely rather than treated as important.

The initial classification is frontend-only, based on the existing `type` field.
Rows are still marked read and navigated using the existing APIs and validated
destination allowlist.

The exact initial allowlist is `FRIEND_REQUEST_SENT`,
`FRIEND_REQUEST_ACCEPTED`, `RACE_INVITE_SENT`, `RACE_INVITE_ACCEPTED`,
`RACE_BUYIN_CHANGED`, `TEAM_RACE_SCHEDULED_UNEVEN`, `RACE_STARTED`,
`RACE_COMPLETED`, `TEAM_LEAD_CHANGE`, `RACE_CANCELLED`, `REFERRAL_REWARDED`,
`GLOBAL_EVENT_STARTED`, `TOURNAMENT_INVITE_SENT`, `TOURNAMENT_STARTED`,
`TOURNAMENT_ROUND_STARTED`, `TOURNAMENT_MATCHUP_WON`,
`TOURNAMENT_ELIMINATED`, `TOURNAMENT_CHAMPION`, `TOURNAMENT_COMPLETED`,
`TOURNAMENT_CANCELLED`, and `HIGH_MULTIPLIER_ALERT`. Other current and future
types, including milestone, placement, reminder, powerup, mover, and race
message events, are suppressed.

Alerts and support threads have separate endpoints and cursors. The client
normalizes them with a source kind and stable ID, merges valid `createdAt`
values newest-first, places malformed timestamps last, and advances each
source cursor independently. A source failure makes the initial load retryable;
the client does not pretend the feed is complete. “You’re caught up” means no
visible normalized rows; hidden legacy rows remain server-owned unread state and
are never locally subtracted or marked read.

## API contract

No endpoint or response shape changes are required. The frontend continues to
use `GET /inbox/alerts`, `POST /inbox/alerts/:id/read`, and the existing feedback
thread endpoints. Missing/null `type`, title, body, timestamps, and
destinations are handled defensively. Malformed or unsupported rows are omitted
from the visible feed; they must not crash the page.

The existing combined unread count remains the shell badge source. Suppressed
legacy rows may still contribute to the backend unread count in this release;
the shell badge must therefore continue to reflect the server count and no
client-side subtraction policy may be introduced.

## Frontend plan

Primary files:

- `lib/screens/inbox_screen.dart`: unified feed, classification, card layout,
  empty/error/loading states, support-thread entry, and alert destinations.
- `lib/screens/main_shell.dart`: five-tab order, Leaderboard tab handling, and
  Profile access from Home/header chrome.
- `lib/widgets/wooden_tab_bar.dart`: preserve accessible hit targets and support
  the five-tab visual hierarchy if needed.
- `lib/tutorial/tutorial_real_screens.dart`: update the hand-copied tab bar and
  hardcoded indices.
- Relevant Home header/profile entry widget files discovered during
  implementation.

Inbox card categories use `AppColors.of(context)`, `PixelText.*`, and existing
arcade primitives. No raw theme-blind palette constants or generic Material
`ListTile` styling should be introduced. The visual direction is forest green,
parchment, gold unread/action accents, and compact dispatch-style cards.

States:

- Loading: existing app-appropriate loading treatment.
- Ready with rows: unified list ordered newest first, with unread accent and a
  direct action label where the destination is valid.
- Ready empty: `YOU'RE CAUGHT UP` and explanatory copy.
- Error: concise message and retry action.
- Signed out: existing safe signed-out behavior.

Old backend behavior is safe: a missing list, missing type, missing optional
fields, or unknown alert type produces an empty/suppressed row rather than a
crash. Older backend support-thread responses remain supported.

Navigation:

- Production order is Home, Races, Leaderboard, Friends, Inbox.
- Leaderboard is a real PageView child; the existing standalone route remains
  available for Home deep links.
- Profile is opened as a pushed `ProfileTab` route from a 44x44 Home hero
  control with key `home-profile-button` and semantics label `Open profile`.
  Tutorial Home supplies a no-op callback and renders the same control.
- Tutorial chrome mirrors the same order and remains non-interactive as before.

## Backward compatibility & rollout

This is a frontend-only presentation/navigation change. No backend deploy is
needed and no existing endpoint is repurposed. Frozen older clients continue
to see the current Inbox and five-tab layout. The new client tolerates older
responses and unknown alert types. Both platforms use the same Dart code and
must be verified before release.

## Test plan

Tests are written before implementation changes:

- Widget tests pump the real Inbox and verify actionable classification,
  suppression of routine/unknown types, defensive malformed-row handling,
  unread state, support row behavior, empty state, error state, and destination
  navigation.
- Widget tests verify the production shell exposes Home, Races, Leaderboard,
  Friends, Inbox in order, opens the existing leaderboard screen, retains the
  Inbox badge, and keeps Profile reachable from Home.
- Widget tests cover merged ordering, independent cursors, malformed rows,
  source-load failure, suppressed types, and profile access from Home.
- Tutorial/widget tests verify the hand-copied tab bar uses the same order and
  does not retain Profile as a bottom-tab item.
- Existing assertions remain intact unless a mechanical index/label update is
  required by the approved navigation change.

## Acceptance criteria / definition of done

- Inbox is a unified attention feed; Alerts/Support tabs are gone.
- Routine and unknown notifications do not clutter the visible Inbox.
- Support replies and important actionable events remain reachable and usable.
- Inbox visually matches the Bara arcade palette and card language.
- Leaderboard is a primary bottom-nav destination without cramped hit targets.
- Profile remains reachable and functional.
- Production and tutorial tab bars agree.
- `flutter analyze` is clean and relevant tests pass.
- iOS and Android implications are accounted for.
- Manual UI-placement checklist is completed by the requester before release.
- Code review has run and no unresolved required findings remain.

## Manual UI-placement test plan

**Manual UI-Placement Test Plan — Inbox redesign and primary navigation**

*Elements under test:*

- Unified Inbox feed replaces the separate Alerts/Support segmented presentation.
- Production bottom navigation changes to Home → Races → Leaderboard → Friends → Inbox.
- Profile moves out of bottom navigation and remains accessible from Home/profile chrome.
- Tutorial’s hand-copied tab bar matches the five production destinations and order.

*Checklist*

1. **Production Inbox screen** — Sign in with unread/actionable alerts → tap Inbox. Verify one unified feed, no selector tabs, correct ordering, unread treatment, action placement, and no duplicates.
2. **Production Inbox empty state** — Use an account with no visible actionable items. Verify `YOU’RE CAUGHT UP`; old alert/support empty states and selectors are absent.
3. **Production Inbox support entry** — Open an account with a support thread. Verify it appears in the unified feed and opens the thread from its row.
4. **Production shell navigation and badge** — Finish onboarding → verify exactly Home, Races, Leaderboard, Friends, Inbox left-to-right; Profile is absent; Inbox badge remains on Inbox; tapping Leaderboard opens the board and returning preserves the shell.
5. **Production Home profile access** — Home → tap the profile entry in the hero/header. Verify Profile opens and is not duplicated in bottom navigation.
6. **Tutorial hand-copied tab bar** — Re-run tutorial → inspect Home/Races/Friends/Profile preview beats. Verify the same five-item order, selected state, and no Profile tab.
7. **Tutorial Home/profile access** — Inspect tutorial Home preview. Verify the profile entry is in the same location and does not escape the tutorial.

*Surfaces confirmed unaffected:*

- Races, Friends, Leaderboard, and Profile tab content remains unchanged; only shell placement/access changes.
- Demo race, demo box-opening, and admin Inbox surfaces do not render the player primary Inbox bar.

*Risks found while planning:*

- The production and tutorial bars are separate implementations and must be checked independently.
- Tutorial has no Inbox content preview, so the copied Inbox tab does not validate Inbox rendering.
- Profile access must be checked after removing the old tab.

## Revision log

- Initial draft: narrowed Inbox from a catch-all notification archive to an
  attention queue; retained existing API surfaces for compatibility.
- Gap pass 1: added unknown-type suppression, malformed-row safety, preserved
  server unread semantics, and explicit tutorial tab-bar mirroring.
- Gap pass 2: added Profile reachability, five-tab order, platform parity, and
  no-flag/no-backend-change constraints.
