# Inbox and public-profile theme alignment — requirements

## Status

Approved by the user on 2026-08-24. This document is the normative,
tests-first implementation runbook; developers must follow the ordered steps
below and may not substitute a narrower surface set or a second profile path.
Final read-only architect and UI-placement reviews: **APPROVE**. Implementation
is in progress; focused dossier, launcher-coverage, and offline tutorial/demo
checks pass. Full release gates remain pending and this document must not be
treated as a production-readiness sign-off until they are green.

## Summary & user story

Bara's Inbox and public-player profile were added after the app's forest-arcade
visual system had already matured, so both currently feel detached from Home,
Races, Leaderboard, and the user's own Profile. The Inbox repeats large
independent cards with too much vertical chrome, while another player's profile
opens as a generic Material page only after a separate friendship menu.

As a player, I want Inbox to scan like the compact Races menu and I want one
consistent racer dossier whenever I tap another visible player, so social
identity, stats, and friendship actions feel native and predictable everywhere.

The design direction is **compact trail ledger + racer dossier**: forest-green
checker headers, parchment game-piece surfaces, gold attention marks, hard
pixel shadows, and the app's existing pixel typography. It is a refinement of
the established Bara language, not a new visual vocabulary.

## Scope / non-goals

### In scope

- Rebrand the existing `PublicProfileScreen` experience as a reusable modal
  bottom-sheet dossier that loads the existing public-profile contract.
- Make a tap on another identifiable, non-stealthed player open that dossier
  directly from accepted/pending/search Friends rows, global/friends
  Leaderboard podium and list rows, every Ranked row/podium, and every in-scope
  Race Detail pending/lobby/course/chat/live/final/podium/winner identity
  presentation. Existing player taps that currently open
  `showFriendRequestSheet` migrate to the same dossier.
- Keep friendship actions in the dossier: add, accept, pending, friends, and
  remove/cancel actions where the existing APIs and identifiers support them.
- Restyle Inbox into a compact continuous dispatch list patterned after the
  Races screen: branded header, dense rows, restrained separators, unread
  accent, direct destination affordance, and compact loading/empty/error/load-
  more states.
- Preserve standalone and embedded/tutorial Inbox hosting, iOS/Android parity,
  light/night palettes, semantics, text scaling, safe areas, and keyboard-free
  bottom-sheet behavior.

### Explicit surface boundary

"Anywhere" means every shipped surface where a player's identity row/avatar is
presented for inspection and a stable user ID is available without changing the
surface's primary job. It includes Friends (accepted, incoming, outgoing, and
search results), Leaderboard (podium and list), Ranked (weekly and legacy
ladder/podium), and every Race Detail identity presentation: pending solo rows,
team-lobby occupied slots, course runners, solo/team live standings, completed
standings/podiums/winner displays, and race-chat sender identity. It does not
steal taps from selection screens (race invite/member pickers), from cards whose
primary tap navigates to a race/tournament, or from anonymous/stealthed rows.
Tournament matchup cards therefore remain race-navigation targets.

### Non-goals

- No new artwork or sprite generation; this work reuses the real equipped
  character/accessory renderer and code-native UI chrome.
- No change to public-profile statistics, friendship semantics, Inbox alert
  classification, notification creation/retention, or destination routing.
- No player-to-player messaging, new profile fields, own-profile editing, new
  navigation tab, release flag, rollout percentage, or runtime kill switch.
- No production deployment or production data write in this change. The final
  handoff may state that the code is ready to deploy; an actual production
  deployment still requires explicit in-the-moment authorization.

## Current-state evidence

- `lib/screens/public_profile_screen.dart` uses a stock `AppBar`, generic
  `Scaffold`, large blank `ListView`, emoji trophies, and a full-screen push.
- `lib/widgets/friend_request_sheet.dart` is the current player-tap entry point
  and adds a second `VIEW PROFILE` step before the public profile.
- Existing player-tap integrations are in
  `lib/screens/tabs/leaderboard_tab.dart`,
  `lib/screens/tabs/ranked_tab.dart`, and
  `lib/screens/race_detail_screen.dart`; accepted Friends rows instead open a
  separate remove-only menu in `lib/screens/tabs/friends_tab.dart`.
- `lib/screens/inbox_screen.dart` renders each item as a `RetroCard` with nested
  padding and its own hard shadow, producing the reported oversized/cramped
  stack.
- `lib/screens/tabs/races_tab.dart` establishes the target language: checker
  header, title/subtitle rhythm, compact state/count chrome, parchment rows,
  fine separators/borders, and hard game-piece shadow used selectively rather
  than around every line item.

## API contract

No endpoint or wire-shape changes are required.

### Existing public profile read

`GET /friends/:userId/profile` remains:

```json
{
  "contract": "public-profile-v1",
  "user": {
    "id": "user-id",
    "displayName": "Trail Runner",
    "profilePhotoUrl": null,
    "equippedAnimal": null,
    "equippedAccessories": []
  },
  "stats": {
    "racePodiums": {"first": 0, "second": 0, "third": 0},
    "avgStepsPerDay": 0
  }
}
```

The client treats every field after the top-level map as optional/malformed:
missing identity uses call-site fallbacks, missing presentation uses the base
character, and missing/malformed stats show an unavailable marker rather than
silently asserting a real zero. HTTP/auth/network failure keeps the fallback
identity visible and presents an inline retry state inside the sheet. A 404 is
"profile unavailable" and does not expose the raw server error.

### Existing friendship reads and mutations

The dossier may continue using the existing defensive `GET /friends` response
plus the existing send/accept/decline/cancel/remove operations already owned by
`BackendApiService`. No parameter becomes required and no response is
repurposed. The sheet must keep profile load and relationship load independent:
one failure cannot erase the other successful section. Mutation completion
updates the action area locally, calls `onChanged`, and may reconcile from
`GET /friends`; it must not close the whole profile unless the user explicitly
dismisses it.

### Existing Inbox reads and mutations

Continue using `GET /inbox/alerts`, feedback-thread endpoints,
`POST /inbox/alerts/:id/read`, and read-all behavior exactly as today. Visual
compaction must not change the allowlist, merged ordering, cursor ownership,
unread reconciliation, destination validation, or support-thread behavior.

## Data model / migrations

No schema, seed, migration, backfill, cache key, or production data operation is
needed. The backend contract is already additive and deployed independently of
this Flutter presentation. The frontend remains compatible with a backend that
omits optional keys or temporarily lacks the profile route.

## Frontend implementation plan

### 1. Shared public-player dossier

- Add `lib/widgets/public_profile_sheet.dart` as the single owner of the modal
  launcher, profile/relationship state, defensive parsing, and friendship
  mutations. Its public contract is:

  ```dart
  enum PublicProfileRelationship {
    unknown,
    self,
    none,
    outgoing,
    incoming,
    friends,
  }

  Future<void> showPublicProfileSheet({
    required BuildContext context,
    required AuthService authService,
    required BackendApiService backendApiService,
    required String userId,
    required String fallbackName,
    String? fallbackPhotoUrl,
    PublicProfileRelationship initialRelationship =
        PublicProfileRelationship.unknown,
    String? friendshipId,
    VoidCallback? onChanged,
  });
  ```

  `friendshipId` is interpreted only with the explicit relationship enum, so
  accepted, incoming, and outgoing IDs cannot be conflated.
- Replace the full-screen presentation in
  `lib/screens/public_profile_screen.dart` with reusable content that can render
  inside a modal. Keep `PublicProfileScreen` as a compatibility shell that
  delegates to that same content/state owner; it must not retain an independent
  raw `_data`/`_error` parser or mutation path. The shipped player-tap path uses
  `showPublicProfileSheet(...)`.
- Model profile and relationship as independent `Loadable` states. A known
  initial relationship renders immediately. A successful `GET /friends`
  reconciliation supersedes the hint; a failed reconciliation preserves the
  known hint and its actions, while `unknown` becomes a retryable unavailable
  action state. Profile failure never erases relationship controls and
  relationship failure never erases successfully loaded profile content.
- Mutation transitions are explicit: send is `none → outgoing` for a returned
  `PENDING`/legacy response and `none → friends` for reverse-pending
  auto-accept (`ACCEPTED`); accept is `incoming → friends`; decline is
  `incoming → none`; cancel is
  `outgoing → none`; remove is `friends → none`. Apply the transition only on
  mutation success, invoke `onChanged`, and reconcile without regressing a
  newer local mutation when an older read completes.
- The launcher uses a themed, safe-area-aware, scroll-controlled bottom sheet
  with a visible drag handle and maximum height that remains usable on small
  phones and large text. It must resolve palette tokens from the launch
  context before route teardown and avoid inherited lookups on deactivated
  contexts.
- Header: checker/forest identity plate, avatar, `@name`, compact relationship
  status, close affordance. Body: real equipped character as the visual anchor;
  one compact podium strip (gold/silver/bronze); one average-steps stat plate;
  then the relationship action row. Avoid emoji and stock Material `AppBar`.
- Loading uses fallback name/photo immediately plus an in-place skeleton or
  progress treatment. Error and 404 keep a composed dossier with retry copy,
  rather than replacing the sheet with a blank error page.
- Use stable keys and semantic labels for launcher, close, retry, stats, and
  relationship actions. Text must ellipsize or wrap safely at 320 logical
  pixels and at 1.3x/2.0x text scale as appropriate.

### 2. One launcher across identity surfaces

- Move friendship-status parsing/action behavior out of the old two-step
  `friend_request_sheet.dart` into the dossier, preserving defensive map/list
  decoding and current mutations.
- Update all `showFriendRequestSheet` call sites in Leaderboard, Ranked, and
  Race Detail to call the dossier directly. Podium and ordinary rows must agree.
- Update accepted Friends rows to open the dossier, passing user ID, display
  name, photo, friendship ID, and `onChanged`. Move REMOVE FRIEND into the
  dossier so the old remove-only modal is not the primary row interaction.
- Make incoming/outgoing/search Friends identity portions tappable without
  swallowing their existing Accept/Decline/Cancel/Add buttons. Pass known
  relationship IDs so actions can render immediately and remain usable if the
  background friendship refresh fails.
- Self and stealthed/anonymous rows remain non-launchable on these surfaces;
  malformed/missing IDs degrade to the existing noninteractive row. Use
  `Semantics(button: true, label: 'View profile for …')` for tappable identity
  areas and preserve at least 44x44 logical touch targets.
- Extend the same launcher through all Race Detail inspectable identities:
  pending-participant identity regions (without swallowing creator kick), team
  lobby occupied slots (without changing empty-slot join/switch), course runner
  markers (preserving the current progress inspection and adding a distinct
  profile affordance), chat sender avatar/name (preserving message long-press),
  live solo/team standings, completed grouped standings, and the completed
  `RacePodium`/winner display. Carry stable IDs through `GoalTrackRunner` and
  `PodiumFinisher`, and give `GoalTrack`, `HomeCourseTrack`, `TeamLobbyBoard`,
  `RacePodium`, and chat bubbles explicit optional profile callbacks rather
  than importing services into shared visual widgets.
- Add a structural guard enumerating the in-scope surface files so a future
  direct `showFriendRequestSheet` or one-off public-profile push cannot silently
  reintroduce split behavior. This guard complements, not replaces, real widget
  tests.

### 3. Compact Inbox dispatch list

- Keep the existing normalized data/state code in `inbox_screen.dart` and
  replace only the presentation layer.
- Use the same page composition as Races: checker forest header with `INBOX`
  title and a short attention-focused subtitle; embedded and standalone modes
  share typography and spacing, with standalone adding the back control.
- Render rows inside one shared parchment game-piece board with a single outer
  border/shadow. Each row is a compact dispatch line: 36-40px category tile,
  one-line title, one-line preview, small category/time metadata, unread gold
  rail/dot, and a trailing chevron/action semantics. Use 10-12px internal gaps
  and thin separators instead of a separate shadowed `RetroCard` per row.
- Derive a short local timestamp defensively from `createdAt`; invalid/missing
  timestamps omit the label. Do not add grouping or filtering that changes row
  order or visibility.
- Loading, caught-up, error/retry, and load-more live in the same parchment
  board language. Loading/load-more must not cause the header or existing rows
  to jump. Preserve the current 48px minimum touch target even when the visual
  row is denser.
- Keep bottom navigation inset behavior for embedded mode and correct top safe
  areas in both modes. Use palette values only, verifying both light and night.

### 4. Files expected to change

- `lib/screens/public_profile_screen.dart`
- `lib/widgets/friend_request_sheet.dart` (retired/compat wrapper or removed
  after all imports migrate)
- `lib/screens/inbox_screen.dart`
- `lib/screens/tabs/friends_tab.dart`
- `lib/screens/tabs/leaderboard_tab.dart`
- `lib/screens/tabs/ranked_tab.dart`
- `lib/screens/race_detail_screen.dart`
- `lib/widgets/public_profile_sheet.dart`
- `lib/widgets/goal_track.dart`
- `lib/widgets/home_course_track.dart`
- `lib/widgets/team_lobby_board.dart`
- `lib/widgets/race_podium.dart`
- `lib/tutorial/tutorial_preview_data.dart` (fixtures and
  `TutorialPreviewBackendApiService` live together)
- `lib/demo/demo_race_api_service.dart`
- `pubspec.yaml` and `pubspec.lock` (SDK `integration_test` dev dependency
  only; do not change app version/build metadata)
- `integration_test/inbox_embedded_harness_test.dart`
- focused tests under `test/`, including
  `test/demo_race_network_guard_test.dart` and tutorial widget coverage.

Tutorial Friends fixtures must gain deterministic stable user IDs and public
profile payloads. Both `TutorialPreviewBackendApiService` and
`DemoRaceApiService` must explicitly override `fetchPublicProfile`,
`fetchFriends`, `sendFriendRequest`, `respondToFriendRequest`, and
`removeFriend` with deterministic offline behavior. Extend the network guard to
open the dossier and exercise every one of those relationship read/mutation
paths so no inherited method can reach production. The real tutorial Friends
and Race Detail screens are mandatory mirrored surfaces, not optional follow-up.
Because embedded Inbox has no shipped caller, add the required test-only
on-device harness at `integration_test/inbox_embedded_harness_test.dart` so the
manual embedded checkpoint is reachable without production navigation or a
runtime flag.

No backend source change is expected. The backend implementation agent must
first verify the existing contract and integration coverage, then lock it as
"no change" before frontend implementation begins.

## Developer implementation runbook (normative)

Follow these phases in order. A phase is not complete until its listed evidence
exists. Do not combine the profile and Inbox work into one unreviewable edit,
and do not begin production-widget changes before the new tests have failed for
the expected old behavior.

### Locked decision ledger

These decisions are final for this implementation; a developer should not stop
to re-litigate them:

| Question | Locked decision |
|---|---|
| Backend work? | No source/schema change expected; verify and lock the already-additive contracts. |
| Public profile presentation? | One direct modal bottom-sheet dossier, never an intermediate friend menu. |
| Old full-screen class? | Retain only as a compatibility host over the same panel; no shipped caller pushes it. |
| Friendship actions? | Live inside the dossier and update in place without dismissing it. |
| Self/Stealth/missing ID? | No profile launcher. Do not guess or expose identity. |
| Course-runner gesture? | First tap preserves the progress tooltip; its explicit profile affordance opens the dossier. |
| Race invite/member pickers? | Remain selection surfaces; no dossier launcher. |
| Tournament/race cards? | Primary navigation tap wins; no profile launcher on the whole card. |
| Results summary card? | Remains noninteractive because it is a race-summary navigation surface; Race Detail podium/winner is interactive. |
| Home course? | Unchanged; the callback is opt-in and only Race Detail supplies it. |
| Inbox behavior policy? | No changes to classification, order, pagination, read state, support, or destinations—presentation only. |
| Flags/rollout controls? | None. Permanent version-compatible behavior. |
| New artwork/fonts? | None. Reuse existing character renderer, palette, pixel type, and code-native chrome. |
| Demo/tutorial network? | Impossible by construction: all transitive profile/friend calls are fake and guarded. |
| Production action? | Build and verify only; deployment/upload/restart requires a separate explicit authorization. |

### Phase 0 — protect the workspace and lock the backend contract

1. Read `AGENTS.md`, `CLAUDE.local.md`, this document, and the backend repo's
   `AGENTS.md`. Run `git status --short` in both repos. Preserve unrelated user
   work; in particular, the pre-existing `docs/economy.md` modification is out
   of scope and must not be reverted, staged, or reformatted.
2. In the backend, inspect but do not change:
   - `src/modules/social/routes/friends.js`;
   - `src/modules/social/queries/getPublicProfile.js`;
   - `src/modules/social/queries/getFriendsSummary.js`;
   - `test/integration/public-profile.test.js`.
3. Record the locked contract in the implementation handoff:
   - profile read: `GET /friends/:userId/profile` →
     `public-profile-v1` or authenticated `404`;
   - relationship read: `GET /friends?view=summary-v1` with the existing
     legacy/full-response fallback handled by the backend;
   - send: `POST /friends/request` → `{ "friendship": { ... } }`;
   - accept/decline: `PUT /friends/request/:friendshipId` →
     `{ "friendship": { ... } }`;
   - cancel/remove: `DELETE /friends/:friendshipId`.
   Record the expected authenticated HTTP statuses as part of the same
   contract: profile read `200/404/500`; friends read `200/500`; send
   `201/400/409/500`; respond `200/400/409/500`; remove `200/404/500`; and
   missing/invalid authentication `401` for every protected route. Tests may
   exercise representative server failures, but client handling must remain
   defensive for any non-success status.
4. Confirm the backend `test:integration` script targets
   `steps-tracker-integration_test`, never production. Run
   `npm run test:integration` from the backend repo. If infrastructure prevents
   the run, report that exact failure; do not point the command at another DB.
5. Backend result must be either: **contract locked, no source change**, or a
   separately reviewed additive compatibility fix. The frontend agent does not
   begin against an unsettled contract.

### Phase 1 — add the red tests before production code

Add or extend the following suites. Keep every existing assertion; mechanical
renames from the old launcher to the new launcher are allowed, but deleting or
weakening behavior is not.

1. `test/public_profile_sheet_test.dart` — new direct dossier coverage.
2. `test/friend_request_sheet_test.dart` — retain the legacy entry-point tests,
   but change their expected destination from a second full-screen page to the
   same direct dossier content. The compatibility function must still work.
3. `test/friends_public_profile_test.dart` — real `FriendsTab` accepted,
   incoming, outgoing, and search identity hit regions plus trailing-action
   gesture isolation.
4. Extend `test/leaderboard_tab_add_friend_test.dart` for direct dossier
   loading and podium/list parity. Add focused Ranked coverage to the existing
   Ranked suites rather than creating a mocked duplicate screen.
5. Extend the existing Race Detail suites for pending rows, team lobby, course
   tooltip action, chat sender, team/solo standings, final podium, single
   winner, and winning-team roster. Shared-widget callback geometry belongs in
   the existing `GoalTrack`/course/team-lobby/podium widget suites; public-path
   navigation belongs in Race Detail tests.
6. `test/inbox_compact_dispatch_test.dart` — new compact layout and visual-state
   structure; extend existing Inbox navigation/read-all suites for behavioral
   parity rather than duplicating their concurrency fixtures.
7. `test/public_profile_launcher_guard_test.dart` — structural completeness
   guard described in Phase 7.
8. Extend `test/demo_race_network_guard_test.dart` and tutorial widget tests.
9. Add Flutter's SDK `integration_test` package under `dev_dependencies` and a
   test-only `integration_test/inbox_embedded_harness_test.dart` that pumps the
   embedded Inbox on an iOS simulator or Android emulator. It must not add a
   production route or app flag.
10. Add an Add-action concurrency case with this exact sequence: the dossier's
    relationship reconciliation first returns `none`; then the fake/backend
    gains a pending request from the target to the viewer (the viewer now has
    `pending.incoming` without the already-open dossier knowing it); then the
    viewer taps Add. The backend auto-accepts that reverse pending request, so
    the response is `ACCEPTED`, the dossier becomes `friends` rather than
    `outgoing`, and it preserves the returned friendship ID. A request from the
    viewer to the target is a same-direction duplicate and must not be used for
    this fixture. Tutorial/demo fakes reproduce the exact sequence.

Run each focused suite and save the red-stage evidence in the handoff. Expected
failures are: no direct dossier widget/keys, old full-screen/intermediate menu,
missing identity callbacks, per-row Inbox `RetroCard`s, and missing fake API
overrides. Compilation failures caused by the deliberately not-yet-added public
API count as valid red evidence. Unexpected failures must be understood before
continuing.

### Phase 2 — implement the one shared dossier owner

Create `lib/widgets/public_profile_sheet.dart`. This file is the only owner of
public-profile parsing, relationship parsing/state, mutations, and the dossier
layout.

#### Public types and signature

Use these exact public types; do not introduce a second launcher:

```dart
enum PublicProfileRelationship {
  unknown,
  self,
  none,
  outgoing,
  incoming,
  friends,
}

@immutable
class PublicProfileRelationshipSnapshot {
  const PublicProfileRelationshipSnapshot(
    this.relationship, {
    this.friendshipId,
  });

  final PublicProfileRelationship relationship;
  final String? friendshipId;
}

Future<void> showPublicProfileSheet({
  required BuildContext context,
  required AuthService authService,
  required BackendApiService backendApiService,
  required String userId,
  required String fallbackName,
  String? fallbackPhotoUrl,
  PublicProfileRelationship initialRelationship =
      PublicProfileRelationship.unknown,
  String? friendshipId,
  VoidCallback? onChanged,
});
```

Also expose a reusable `PublicProfilePanel` widget with the same identity,
relationship, service, and callback inputs plus an optional
`ScrollController`. `showPublicProfileSheet` and `PublicProfileScreen` must both
delegate to this panel; neither may copy its parsing or mutation logic.

The launcher trims `userId`; a blank ID returns without opening a route. A
missing/empty auth token opens no mutation-capable state: the panel keeps the
fallback identity, shows `SIGN IN TO VIEW PROFILE`, performs no API call, and
offers only Close. Production call sites also guard self before launching; the
panel's `self` handling remains defense in depth and for compatibility tests.

#### Modal configuration

`showPublicProfileSheet` must use `showModalBottomSheet<void>` with:

- `isScrollControlled: true`;
- `useSafeArea: true`;
- `backgroundColor: Colors.transparent`;
- `enableDrag: true`;
- no stock Material drag handle or `AppBar`;
- a `DraggableScrollableSheet(expand: false)` with initial/min/max child sizes
  `0.82 / 0.55 / 0.94`;
- a custom 36×4 drag handle, 24px top corners, and the panel's scroll controller
  passed into its single `CustomScrollView`/`ListView`.

The sheet root key is `public-profile-sheet`. Required stable keys are:

- `public-profile-close`;
- `public-profile-loading` and `public-profile-retry`;
- `public-profile-character`;
- `public-profile-podium-first`, `-second`, and `-third`;
- `public-profile-average-steps`;
- `public-profile-relationship-status`;
- `public-profile-action-add`, `-accept`, `-decline`, `-cancel`, and `-remove`.

#### Independent async state and stale-result guards

1. Store profile and relationship as two independent `Loadable` values:
   `Loadable<Map<String, dynamic>>` and
   `Loadable<PublicProfileRelationshipSnapshot>`.
2. Seed a known caller hint as `Loadable.refreshing(snapshot)`; seed `unknown`
   as `Loadable.loading()`. If `authService.userId == userId`, force `self` and
   do not call `fetchFriends`.
3. Start `fetchPublicProfile` and `fetchFriends` in parallel. Use separate
   monotonically increasing request generations plus one mutation generation.
   Before every state update, require: mounted; identical auth token; identical
   authenticated user ID; identical target user ID; and matching generation.
4. Subscribe to `AuthService`. On token/user rotation, increment all
   generations, clear loaded target data, and dismiss the modal on the next
   frame. A late read or mutation from the old account must do nothing and must
   not call `onChanged`.
5. Disposal removes the auth listener and invalidates all generations.

#### Defensive profile projection

Use private helpers that accept `Object?`; never use unchecked `as`, `.cast`,
or `!` on server data.

- `user` and `stats` must be string-keyed maps assembled entry-by-entry.
- A present non-empty `user.id` that differs from the requested ID invalidates
  the response as unavailable; an absent ID is tolerated for older payloads.
- Name: non-empty `user.displayName`, else trimmed `fallbackName`, else
  `Runner`.
- Photo: non-empty `user.profilePhotoUrl`, else `fallbackPhotoUrl`.
- Animal: non-empty `user.equippedAnimal`, else `null`.
- Accessories: keep only map items and copy only string-keyed entries.
- Each podium value and `avgStepsPerDay` accepts only a finite, non-negative
  number. Round average steps; use an em dash for absent/malformed values. A
  valid numeric zero renders `0` and is not treated as missing.
- `ApiException(statusCode: 404)` renders `PROFILE UNAVAILABLE`; every other
  failure renders `COULDN'T LOAD STATS`. Both preserve fallback identity and
  expose `public-profile-retry`.

#### Defensive relationship projection and precedence

Parse both compact and legacy `GET /friends` shapes. Extract IDs recursively
from top-level `id`, `userId`, `friendId`, `requesterId`, `addresseeId`, then
from `user`, `friend`, `requester`, or `addressee` maps. Evaluate in this exact
order to preserve current behavior:

1. authenticated self → `self`;
2. accepted `friends` match → `friends` with its `friendshipId`;
3. `pending.outgoing` match → `outgoing` with its `friendshipId`;
4. `pending.incoming` match → `incoming` with its `friendshipId`;
5. otherwise → `none`.

A successful read supersedes the initial hint only if no newer mutation began.
A failed read keeps a known hint as error-with-data, so its action remains
usable; failed `unknown` shows a compact retry action and no guessed mutation.

#### Mutation behavior

Only one mutation may run at once. Keep the dossier open throughout. Disable
all relationship buttons while busy and use these exact transitions after a
successful response:

| Action | Required start | Endpoint call | Successful local state |
|---|---|---|---|
| Add | `none` | `sendFriendRequest(addresseeId: userId)` | Parse returned `friendship.status`: `ACCEPTED` → `friends`; `PENDING` or legacy missing status → `outgoing`. Preserve returned `friendship.id` when present. |
| Accept | `incoming` + ID | `respondToFriendRequest(accept: true)` | `friends`, retaining/refreshing the ID |
| Decline | `incoming` + ID | `respondToFriendRequest(accept: false)` | `none`, ID cleared |
| Cancel | `outgoing` + ID | `removeFriend` | `none`, ID cleared |
| Remove | `friends` + ID | `removeFriend` | `none`, ID cleared |

When a mutation starts, increment both the mutation generation and relationship
request generation before awaiting the endpoint; that immediately invalidates
an older reconciliation. After the successful local transition, call
`onChanged` once, then start a new reconciliation captured against the new
generations. For an ID-less Add response, preserve the status transition:
`ACCEPTED` renders `friends` without ID, while `PENDING` or a legacy missing
status renders `outgoing` without ID. In either case the action is disabled,
reconciliation starts immediately, and the client never invents an ID. Cancel
and Remove require a themed confirmation step; Accept/Decline/Add do not.

On every still-current mutation failure, keep the pre-mutation snapshot visible,
re-enable actions, show the existing generic Bara error toast, and immediately
start a generation-fenced authoritative friendship reconciliation. This covers
the server committing before a lost response, another client changing the
relationship, and DELETE returning 404 because the row was already removed. If
reconciliation changes the relationship, apply it and invoke `onChanged`
exactly once for that observed change; if it matches the preserved snapshot,
do not call `onChanged`. A stale mutation or reconciliation after dismissal or
auth rotation does nothing. Do not branch on raw exception strings except for
preserving the existing already-requested conflict copy.

Render relationship states with this exact copy/action matrix:

| State | Status copy | Actions |
|---|---|---|
| loading unknown | `CHECKING FRIENDSHIP…` | 18px progress indicator only |
| error unknown | `FRIENDSHIP STATUS UNAVAILABLE` | `TRY AGAIN` |
| self | `THAT'S YOU` | none |
| none | no extra status chip | `ADD FRIEND` |
| outgoing + ID | `REQUESTED` | `CANCEL REQUEST` |
| outgoing without ID | `REQUESTED` | none until reconciliation supplies an ID |
| incoming + ID | `WANTS TO BE FRIENDS` | `ACCEPT`, `DECLINE` |
| incoming without ID | `REQUEST RECEIVED` | no mutation; retry reconciliation |
| friends + ID | `FRIENDS` | `REMOVE FRIEND` |
| friends without ID | `FRIENDS` | no mutation; retry reconciliation |

Confirmation copy is fixed: Cancel uses title `CANCEL FRIEND REQUEST?`, body
`Cancel your request to @name?`, and destructive button `CANCEL REQUEST`;
Remove uses title `REMOVE FRIEND?`, body `Remove @name from your friends?`, and
destructive button `REMOVE FRIEND`. Both confirmations have `KEEP` as the safe
secondary action. Implement one private `showDialog<bool>` helper using a fully
themed parchment `AlertDialog`, `PixelText`, and `PillButton`; do not stack a
second modal bottom sheet over the dossier.

### Phase 3 — build the dossier's exact visual hierarchy

Use only `AppColors.of(context)`, `PixelText`, `AppAvatar`,
`CapybaraCustomizationPreview`, `PillButton`, `ArcadeCheckerPainter`, and
existing code-native arcade primitives. No asset generation, emoji trophies,
stock `AppBar`, generic `ListTile`, blue/purple gradient, or new font/package.

From top to bottom:

1. Forest/checker identity header: custom handle, 44×44 close target, 64px
   avatar, `@name` (one line/ellipsis), and compact relationship-status chip.
2. Parchment body with subtle `PixelSurfacePainter` texture.
3. Centered equipped character, nominal size 136px, keyed as above. Missing
   presentation renders the base character.
4. One shared trophy plate with three equal cells. Use existing medal colors
   and `Icons.looks_one_rounded`, `looks_two_rounded`, `looks_3_rounded`; no
   emoji. Values use `PixelText.number`.
5. One compact average-steps plate: `AVG STEPS / DAY` and the rounded value or
   em dash.
6. Relationship controls at the bottom, using full-width `PillButton`s or a
   two-button row for Accept/Decline. Wrap the action region in
   `AnimatedSwitcher` (180ms ease-out; zero duration when platform animations
   are disabled) so relationship transitions feel like one persistent card.

Spacing is 16px outer body padding, 12px between plates, 8px inside compact
metadata groups. At 320 logical pixels and 2.0x text scale the sheet must scroll
without horizontal overflow; action rows may stack vertically. Every tappable
identity/action is at least 44×44 and has a semantic button label.

### Phase 4 — retire the split profile paths

1. Replace `lib/widgets/friend_request_sheet.dart` with a thin deprecated
   compatibility adapter that maps its existing arguments to
   `showPublicProfileSheet`. It contains no widget tree, parser, API call, or
   navigation push.
2. Rewrite `lib/screens/public_profile_screen.dart` as a compatibility
   `Scaffold`/safe-area host for `PublicProfilePanel`. It has no independent
   state or stock `AppBar`. Its existing nullable/blank `fallbackName` input
   maps to `Runner` before constructing the panel. No shipped production
   surface may push it.
3. Search with:

   ```sh
   rg -n "showFriendRequestSheet|PublicProfileScreen\(" lib
   ```

   The only allowed hits are the compatibility declarations themselves. Every
   production caller imports `public_profile_sheet.dart` directly.

### Phase 5 — wire Friends, Leaderboard, and Ranked

#### Friends

In `lib/screens/tabs/friends_tab.dart`, add one private `_openPublicProfile`
helper and a small private relationship-hint resolver. Do not duplicate parsing
inside four row builders.

- Accepted row: identity region opens with `friends` + top-level
  `friendshipId`; replace the misleading trailing more-menu icon with a profile
  chevron. Remove the old remove-only menu; Remove lives in the dossier.
- Incoming row: wrap only avatar + name in the launcher; pass `incoming` +
  request `friendshipId`. Accept/Decline remain separate trailing targets.
- Outgoing row: wrap only avatar + name; pass `outgoing` + ID. Pending/Cancel
  remain separate trailing targets.
- Search row: wrap avatar + identity text as one expanded target, excluding the
  trailing ADD/FRIENDS/PENDING control. Resolve the hint by stable ID in order:
  accepted, outgoing, incoming, none. Name fallback is `displayName`, then
  `discoverableName`, then `Runner`; pass its profile photo.
- Missing/blank ID and authenticated self do not get an `InkWell` or button
  semantics. After a successful dossier mutation, invalidate
  `FriendsSummaryRepository`, reload Friends once, then call the existing
  `onFriendsChanged` path. Because the launcher accepts `VoidCallback`, pass a
  callback that uses `unawaited(_refreshAfterDossierMutation())`; that async
  method owns a boolean in-flight guard so multiple taps cannot duplicate the
  repository reload.

#### Leaderboard and Ranked

- Replace every old friendship-sheet call with the new launcher. Preserve
  non-self/non-empty-ID/Stealth guards.
- `LeaderboardTab`: keep `_withFriendTap` as the single wrapper for both podium
  tiles and ordinary rows. Rename `_openFriendSheet` to `_openPublicProfile`.
- `RankedTab`: wire weekly cohort rows, ladder rows, and the separate legacy
  `_PodiumPlace` implementation. Add an optional tap callback to `_PodiumPlace`
  rather than wrapping the whole podium/scope card.
- Pass `initialRelationship: unknown` from leaderboard/race surfaces; their
  payloads do not authoritatively carry friendship status.

### Phase 6 — wire every Race Detail identity without gesture collisions

Add one `_openPublicProfile` helper on `RaceDetailScreen` that rejects blank
IDs, self, and Stealth before calling the shared launcher with the injected
`_api`. Reuse it everywhere below.

1. **Pending solo participants:** split `_buildParticipantRow` into an expanded
   44px-min identity target and trailing status/kick controls. Kick remains a
   separate target and must never bubble into the dossier.
2. **Pending team lobby:** add
   `ValueChanged<Map<String, dynamic>>? onTapMember` to `TeamLobbyBoard`. Wrap
   only occupied non-self slots with stable `userId`; empty slots continue to
   call only `onTapEmptySlot`. Shared widget performs no API work.
3. **Course runners:** add `String? userId` to `GoalTrackRunner`. Add optional
   `ValueChanged<GoalTrackRunner>? onViewProfile` to `GoalTrack` and
   `HomeCourseTrack`. The existing runner tap still selects the anchored
   progress tooltip. For eligible runners, the tooltip adds a 44px-min `VIEW
   PROFILE` affordance that invokes the callback. Home passes no callback and
   therefore keeps its existing tooltip unchanged. Race Detail supplies IDs
   from participant `userId` and the callback in `_buildRaceHero`.
4. **Live team/solo standings:** replace the two existing
   `showFriendRequestSheet` calls with `_openPublicProfile`. Keep effect-icon
   trays outside the parent identity hit region.
5. **Chat:** add `VoidCallback? onSenderTap` to `_ChatBubble`. Render the sender
   identity chrome and message-body gesture region as siblings: wrap only the
   other sender's avatar + rendered sender name in the semantic profile target,
   while the message-body `GestureDetector` retains its current long-press.
   `RaceChatMessage` has no stealth field, so `_buildChatItem` must match its
   `senderId` against the current participant snapshot and suppress the callback
   when that participant has `stealthed == true`. Build the callback only when
   the sender ID is non-empty, not self, not stealthed, and the message
   is a real other-user message. The shared eligibility helper takes an
   explicit `isStealthed`/`canViewProfile` input; it must never infer privacy
   from display text, avatar, or masked presentation.
6. **Completed solo podium:** add `String? userId` and `String? profilePhotoUrl`
   to `PodiumFinisher`; populate them defensively in
   `finishersFromParticipants`. Add
   `ValueChanged<PodiumFinisher>? onTapFinisher` to `RacePodium` and wrap only
   the avatar/name cluster, not empty plinths, numerals, steps, or payouts.
   `RaceResultsSummaryScreen` does not pass the callback and remains
   noninteractive; Race Detail does.
7. **Single-winner fallback:** resolve identity as non-empty `winner.userId`,
   then `winner.id`. Wrap only the avatar/name cluster when it is not self.
8. **Team winner board:** wire each non-self winning-roster avatar/name using
   the same helper; do not wrap the team plaque, totals, or tie chrome.
9. **Final grouped/solo standings:** use the same existing standings wrappers
   as the live board, preserving collapsed/show-all and pagination behavior.

For shared models/widgets, new fields and callbacks are optional with safe
defaults. This keeps Home, summary cards, tutorials, and frozen payload fixtures
source-compatible until their explicit callers opt in.

### Phase 7 — enforce launcher completeness structurally

`test/public_profile_launcher_guard_test.dart` reads the in-scope source files
and enforces all of the following:

1. No production call to `showFriendRequestSheet` outside its compatibility
   declaration.
2. No production construction/push of `PublicProfileScreen` outside its class
   and tests.
3. `showPublicProfileSheet` is referenced by Friends, Leaderboard, Ranked, and
   Race Detail.
4. `GoalTrackRunner` and `PodiumFinisher` retain optional `userId`; shared
   `HomeCourseTrack`, `TeamLobbyBoard`, `RacePodium`, and chat bubble retain the
   optional callback seams.

The guard must check meaningful symbol/file relationships and include sanity
counts so an empty regex cannot pass. It supplements the real widget tests and
must not assert formatting or private line numbers.

### Phase 8 — make tutorial and demo mirrors deterministically offline

In `TutorialPreviewBackendApiService` and `DemoRaceApiService`, override these
exact methods without calling `super`: `fetchPublicProfile`, `fetchFriends`,
`sendFriendRequest`, `respondToFriendRequest`, and `removeFriend`.

- Return deterministic `public-profile-v1` payloads for every seeded fixture
  user ID, including safe zero/missing-field variants.
- Return compact-shaped friends data with stable IDs and relationship IDs.
- Mutations update only fake in-memory relationship state and return the same
  broad envelope shapes as the real API. `removeFriend` returns `Future<void>`.
- Fake send must mirror reverse-pending auto-accept: after the open dossier has
  reconciled to `none`, seed a pending target→viewer request; the viewer's Add
  returns that existing friendship with `status: ACCEPTED`. A normal new
  viewer→target request returns `status: PENDING`; a same-direction duplicate
  follows the real conflict behavior. Preserve the stable relationship ID so
  tutorial/demo tests exercise the real client transition rules.
- Add stable user IDs to tutorial Friends fixtures and a deterministic search
  result so accepted/incoming/outgoing/search launch paths are visible offline.
- Preserve demo script state when a dossier opens/closes; a mutation must not
  advance tutorial/demo beats.

Use these tutorial IDs consistently within each existing fixture family and in
profile payload lookup: existing ranking/race/chat IDs `lb-1`/`lb-2` and
`rk-1`/`rk-2` stay unchanged; Friends rows become `tutorial-maya`,
`tutorial-sam`, `tutorial-jordan`, incoming `tutorial-dana`, outgoing
`tutorial-priya`, and search result `tutorial-chris`. Keep the existing
`fs-*` relationship IDs. Demo profile lookup derives its entries from
`DemoRaceEngine.demoFriends`/the engine roster's existing IDs rather than
maintaining a second handwritten rival-ID list.

Extend `test/demo_race_network_guard_test.dart` in two ways: source guard the
five new overrides in both fakes, and pump/open a real dossier in tutorial/demo
tests while exercising read + mutation. A passing source regex alone is not
sufficient evidence that a transitive call is isolated.

### Phase 9 — rebuild Inbox as one compact dispatch board

Do not change normalization, allowlist, sort, cursors, read-all, item-read,
unread generations, auth generations, destination parsing, support-thread
opening, or `AutomaticKeepAliveClientMixin`. Refactor only `build`, headers,
state shells, row rendering, and timestamp presentation.

#### Header

- Both modes show `INBOX` at 28px with the subtitle `The things that need your
  attention.` at 14px on the same forest/checker field as Races.
- Standalone includes a separate 44×44 back target and respects top safe area;
  embedded omits back and retains its existing bottom-navigation inset.
- Use the same title shadow and 16px horizontal rhythm as `RacesTab`.

#### Shared board

Create one private `_InboxDispatchBoard` (or equivalently named private widget)
with key `inbox-dispatch-board`:

- margin `10px` horizontal, `8px` top, and enough bottom margin for the hard
  shadow;
- parchment fill, 16px radius, 1.5px `parchmentBorder`, one 4px hard shadow;
- one clipped `PixelSurfacePainter` texture behind content;
- populated state uses a lazy `ListView.builder`; do not build all paginated
  rows in a `Column`;
- rows have a 72px visual minimum and at least a 48px semantic tap target,
  10px vertical/12px horizontal padding, and a 1px inset separator;
- no row-level `RetroCard`, elevation, or hard shadow.

Each row key is `inbox-row-<kind>-<id>` where kind is `alert` or `support`.
Composition: 3px unread gold rail; 36px rounded category tile; expanded text
with one-line 14px title and one-line 12.5px preview; 10px category/time
metadata; 18px trailing chevron. Required category icons are:

- support → `Icons.support_agent_rounded`;
- friends → `Icons.person_add_alt_1_rounded`;
- race → `Icons.flag_rounded`;
- tournament → `Icons.emoji_events_rounded`;
- reward → `Icons.card_giftcard_rounded`;
- fallback important → `Icons.notifications_rounded`.

Unread rows use the gold rail, a slightly gold-tinted category tile, and
semantics containing `unread`; read rows do not reserve a visible `NEW` text
column. Entire rows stay tappable and preserve the destination behavior.

#### Timestamp

Parse `createdAt` with `DateTime.tryParse(...).toLocal()`. Invalid/missing values
render no time text. Without adding `intl`, format:

- same local calendar day: `h:mm AM/PM`;
- otherwise: `Mon d` using a private month abbreviation list.

The timestamp is presentation-only and cannot participate in ordering; keep the
existing `_compareRows` result.

#### State shells and keys

Loading, error, empty, and pagination render inside the same board footprint:

- `inbox-loading`: compact existing skeleton/progress treatment;
- `inbox-error` with copy + existing accessible retry button keyed
  `inbox-retry`;
- `inbox-empty`: icon, `YOU'RE CAUGHT UP`, and one short supporting line;
- `inbox-load-more`: existing 48px-min action at the end of the lazy list.

Loading more keeps existing rows mounted and swaps only the load-more action's
label/progress. Do not move or rebuild the header.

### Phase 10 — run focused green verification and review the diff

1. Run every new/modified focused suite once its production code lands.
2. Run existing protected suites most exposed to regression:
   - `test/feature_batch_2026_08_18_navigation_test.dart`;
   - `test/inbox_read_all_frontend_test.dart`;
   - `test/friend_request_sheet_test.dart`;
   - `test/friends_identity_search_test.dart`;
   - `test/leaderboard_tab_add_friend_test.dart`;
   - relevant Ranked, GoalTrack/course, team-lobby, podium, Race Detail,
     tutorial, and demo-network suites.
3. Run `dart format` only on touched Dart files. Review `git diff --check` and
   `git diff --stat`; confirm no unrelated file was rewritten.
4. Search for unchecked server casts/non-null assertions introduced by the
   change and remove them. Existing unrelated casts are not a license to add
   new ones.

### Phase 11 — required global/platform verification

Run, in this order:

1. `flutter pub get` (required if `integration_test` dev dependency changed);
2. `flutter analyze` — must be clean;
3. `flutter test` — full suite once;
4. `flutter devices`, then run
   `flutter test integration_test/inbox_embedded_harness_test.dart -d <listed-ios-simulator-id>`;
5. run the same harness with `<listed-android-emulator-id>`;
6. exact iOS production compile (no flavor):

   ```sh
   flutter build ipa --release \
     --dart-define=BACKEND_BASE_URL=https://steptracker-api.org \
     --dart-define=ADMOB_EXTRA_SPIN_AD_UNIT_ID=ca-app-pub-4538901002392200/8833390717 \
     --dart-define=ADMOB_BANNER_AD_UNIT_ID=ca-app-pub-4538901002392200/5308967309 \
     --dart-define=ADMOB_BOX_TOP_BANNER_AD_UNIT_ID=ca-app-pub-4538901002392200/3019108638 \
     --dart-define=ADMOB_NATIVE_AD_UNIT_ID=ca-app-pub-4538901002392200/9892856363 \
     --dart-define=ADMOB_BOX_REROLL_AD_UNIT_ID=ca-app-pub-4538901002392200/9184830227 \
     --dart-define=ADMOB_RACE_PAYOUT_DOUBLE_AD_UNIT_ID=ca-app-pub-4538901002392200/6376353967 \
     --dart-define=GOOGLE_IOS_CLIENT_ID=784756906133-iod9c45m7guhnpkv8svbdbmb27nctagl.apps.googleusercontent.com
   ```

7. exact Android production compile for the current `2.3.8` first-upload
   versionCode (`203080`):

   Before building, perform a non-secret release preflight: verify
   `android/key.properties` exists; resolve its `storeFile` path and verify the
   keystore exists; and verify the resolved `admobAppId` is present and is not
   Google's test ID `ca-app-pub-3940256099942544~3347511713`. Do not print
   passwords or copy any secret into the handoff. A missing keystore would make
   Gradle silently use the debug signing config, and a missing app ID would use
   the test AdMob application ID; either condition invalidates release-ready
   evidence even if compilation succeeds.

   ```sh
   flutter build appbundle --release --flavor prod \
     --dart-define=BACKEND_BASE_URL=https://steptracker-api.org \
     --dart-define=ADMOB_EXTRA_SPIN_AD_UNIT_ID_ANDROID=ca-app-pub-4538901002392200/4587493133 \
     --dart-define=ADMOB_BANNER_AD_UNIT_ID_ANDROID=ca-app-pub-4538901002392200/8844513901 \
     --dart-define=ADMOB_NATIVE_AD_UNIT_ID_ANDROID=ca-app-pub-4538901002392200/4905268896 \
     --build-number=203080
   ```

   The two Android rewarded IDs are deliberately omitted because
   `DEPLOYMENT.md` records them as not yet provisioned; omission preserves the
   app's existing compile-time disabled behavior and must not be replaced with
   guessed IDs.

   After the build, run:

   ```sh
   keytool -printcert -jarfile \
     build/app/outputs/bundle/prodRelease/app-prod-release.aab
   ```

   Verify the certificate SHA-1 equals the documented upload-key SHA-1 in
   `ANDROID.md`: `DA:57:0C:42:36:72:11:D2:15:6B:2E:86:3F:A0:62:31:A0:B3:08:6A`.
   A debug-signed artifact is compile evidence only and must never be reported
   as release-ready or uploadable.

Do not change app version/build metadata, create a release branch, upload an
artifact, start staging, or deploy production as part of verification. If local
signing blocks an archive, report the exact failure and do not label the work
ready to deploy.

### Phase 12 — code review and completion evidence

After implementation, run the required `code-reviewer` agent on the complete
frontend/backend diff. Resolve every REQUIRED finding and rerun the affected
focused tests, `flutter analyze`, and full `flutter test`. Re-review if fixes are
non-trivial.

The final completion audit must map each acceptance criterion to current
evidence: file/symbol, widget test, full-suite result, backend integration
result, platform build result, and the manual UI checklist handed to the user.
Only then may the handoff say **ready to deploy to production**. It must not
deploy, restart PM2, start staging, write production data, or publish an app
build without separate in-the-moment authorization.

## Backward compatibility and rollout

- Backend first remains satisfied because the additive
  `public-profile-v1` endpoint already exists. This change adds no dependency
  on a new field; all fields are read defensively.
- Frozen older apps keep their existing full-screen/two-step UI and continue to
  use unchanged endpoints. The new app works against an older backend by
  showing fallback identity plus an unavailable/retry stats section; friendship
  actions keep their existing API behavior.
- Inbox mutation and destination semantics are untouched, so backend/client
  version skew cannot alter unread counts or navigate unknown destinations.
- No feature flag or temporary runtime control is introduced.
- Both iOS and Android ship the same Dart changes. Verify responsive layout on
  representative small/large devices and light/night theme before release.
- Actual production deployment is out of scope until the user gives explicit,
  in-the-moment authorization after the ready-to-deploy handoff.

Both reads remain user-triggered and non-polling through existing endpoints;
Postgres remains authoritative and there is no new write/invalidation seam, so
this presentation change does not warrant a new Redis surface.

## Test plan — tests first

The implementation agents must add the following tests and demonstrate that
they fail for the expected pre-change behavior before changing production code.

### Frontend widget/integration tests

1. Pump the real public dossier through its launcher and assert fallback
   identity during loading, successful character/profile/stats rendering,
   missing/null/malformed-field degradation, retryable failure, and dismissal.
2. Assert the public dossier uses theme palette surfaces in light and night,
   fits a 320px viewport, survives 1.3x and 2.0x text scale without exceptions,
   and exposes profile/action semantics.
3. Exercise friendship states through the dossier: self-safe/nonlaunchable,
   none/send, outgoing/cancel, incoming/accept/decline, friends/remove, mutation
   failure, and `onChanged`. Include reverse-pending Add auto-accept
   (`ACCEPTED` → friends with returned ID), legacy missing-status Add
   (`outgoing`), ID-less `ACCEPTED` → friends, ID-less `PENDING`/missing status
   → outgoing, server-commit-plus-transport-failure reconciliation,
   concurrent remote accept reconciliation, and DELETE 404 followed by
   authoritative reconciliation. Assert `onChanged` fires exactly once when a
   failure reconciliation reveals a changed relationship and zero times when
   it confirms the preserved snapshot. Existing friend-sheet assertions may be
   migrated mechanically but may not be weakened or skipped.
4. Pump the real Friends tab with accepted, incoming, outgoing, and search
   fixtures. Tap each identity region and assert the dossier opens while the
   inline action buttons still perform their original actions.
5. Pump real Leaderboard and Ranked widgets and assert both podium/ordinary
   rows open the same dossier; current-user and missing-ID rows do not.
6. Pump real solo and team Race Detail standings fixtures and assert visible
   non-self participants open the dossier; stealthed/self rows and effect-icon
   child gestures retain their existing behavior.
7. Pump pending participants, team-lobby occupied slots, course runners, chat
   senders, completed podium/winner displays, and final grouped Race Detail
   fixtures. Assert each stable non-self identity opens the dossier while
   kick, empty-slot join/switch, course-progress inspection, message long-press,
   and primary race/tournament navigation gestures remain intact.
   Include a chat message whose sender maps to a currently stealthed participant
   and assert neither its avatar nor rendered name exposes a profile callback.
8. Pump tutorial Friends and Race Detail plus the onboarding demo Race Detail;
   open the dossier and perform a friendship action entirely against fake
   services. Extend the demo network guard to prove no production-capable
   method is reached.
9. Pump the real Inbox with mixed alert/support fixtures. Assert compact row
   keys, one shared board, unchanged ordering/allowlist/unread/navigation,
   timestamp degradation, load-more stability, and minimum semantic touch
   targets. Keep the existing read-all/race-condition suites green.
10. Structural guard: all in-scope identity surface files use the shared
   launcher and no shipped code pushes `PublicProfileScreen` or calls the old
   two-step launcher directly.
11. Dismiss the dossier while profile and relationship futures/mutations are
    pending. Late completions must not call `setState` after disposal, invoke
    `onChanged`, or reopen/update the dismissed route.
12. In a separately pumped case, rotate authenticated identity while profile
    and relationship futures/mutations are pending. The sheet dismisses and
    completions from the previous account must not update state or invoke
    `onChanged`.

### Backend verification

- Confirm `test/integration/public-profile.test.js` still covers authentication,
  response shape, visibility/404 rules, aggregates, and optional presentation.
- Run it only after confirming `DATABASE_URL` names a dedicated test database.
  No backend test or source edit is required if the locked contract already
  passes.

### Commands

- `flutter analyze`
- focused Flutter suites first, then `flutter test`
- backend: `npm run test:integration`; its package script hard-codes
  `postgresql://rohan@localhost:5432/steps-tracker-integration_test`, applies
  migrations, and runs the integration glob. Confirm that target before
  execution; never `npm test` and never point a direct Node command at prod.
- Account for both platforms with Flutter tests/analyze plus an iOS and Android
  build or the repo's approved equivalent compile verification when release
  credentials/config permit it. Report any skipped build plainly.

## Acceptance criteria / definition of done

- Inbox visibly matches the Races screen's forest/checker/parchment/pixel
  language and scans as a dense continuous list; oversized independent cards
  are gone.
- Public player profile is fully rebranded as one polished modal dossier with
  real character, profile photo, trophies, average steps, and friendship
  controls.
- Every in-scope visible other-player identity opens the same dossier directly;
  Friends, Leaderboard/Ranked, pending/team-lobby/course/chat/live/final Race
  Detail presentations, and completed podium/winner displays are proven by
  widget tests.
- Inline Friends and Race Detail child actions still work; self, stealth, and
  malformed identities remain safe.
- Loading, empty, error, retry, missing-field, long-name, small-screen,
  large-text, light, and night states are verified.
- Existing Inbox ordering, classification, pagination, read/unread race safety,
  support behavior, and destination allowlist remain unchanged and green.
- No API/schema/flag change is introduced; old and new app/backend version
  combinations degrade safely.
- `flutter analyze` and the full Flutter suite pass; backend contract is
  verified; iOS and Android are accounted for; required manual UI checklist and
  code review have no unresolved required findings.
- Only after all evidence above is current may the work be called ready to
  deploy to production. Production itself is not changed without a separate
  explicit authorization.

## Manual UI-placement test plan

**Manual UI-Placement Test Plan — Inbox and public-profile theme alignment**

*Elements under test:* Inbox alerts move from separate oversized cards into compact rows inside one continuous parchment dispatch board beneath the branded header.

*Elements under test:* Another player’s profile moves from a full-screen page behind an intermediate friendship menu into one direct, scroll-controlled racer-dossier bottom sheet.

*Elements under test:* Friendship controls move into the dossier; accepted, incoming, outgoing, and search identity regions become dossier launch targets while their inline buttons stay separate.

*Elements under test:* Leaderboard podium/list, Ranked weekly/legacy ladder, and Race Detail solo/team/final-standing identities gain the same direct dossier launcher.

*Checklist*

1. **Standalone Inbox — populated, loading, empty, error, and pagination states**
   - **Get there:** Home → Notifications; use an account with mixed unread/read alerts and a support thread, then exercise retry/load-more fixture states.
   - **Verify:** The branded header remains above one continuous dispatch board; all compact rows and separators are inside that board, with loading/error/caught-up/load-more occupying the same board position. Confirm no alert remains in an individually spaced/shadowed card, no row is duplicated, load-more does not move the header or existing rows, the back control stays inside the safe area, and the final row clears the bottom safe area.

2. **Embedded Inbox**
   - **Get there:** The required harness must support a deterministic populated fixture and a manual hold mode. Run `flutter devices`, then run `flutter run -d <ios-simulator-id> -t integration_test/inbox_embedded_harness_test.dart --dart-define=INBOX_HARNESS_HOLD=true`; repeat with `-d <android-emulator-id>`. No production route or flag is permitted.
   - **Verify:** On both devices, the harness visibly labels itself `EMBEDDED INBOX HARNESS`; the embedded header occupies the top of the host without a standalone back control; the same continuous dispatch board begins directly below it; mixed alert/support, read/unread, and load-more rows are visible; and the final row clears the harness bottom-navigation inset. Confirm standalone header chrome is not duplicated. Capture one full-screen screenshot per platform in the implementation handoff, then terminate each harness manually. The checkpoint fails if either command, label, fixture, or screenshot is absent.

3. **Public racer dossier — responsive placement matrix**
   - **Get there:** Open any other player from Friends. Repeat on a 320-logical-pixel phone and a large phone/tablet; set device text scale to 1.3x and then 2.0x; repeat with Profile → Settings → Appearance → Light and Night.
   - **Verify:** A bottom sheet—not a full-screen route—appears with drag handle and close control at the top, identity plate/avatar first, equipped character as the body anchor, podium strip before average-steps plate, and friendship actions last. Confirm nothing is clipped, overlapped, duplicated, or trapped below the safe area; long names do not displace close/status controls; the body scrolls while the sheet remains bounded; dragging the handle dismisses the sheet without the inner scroll stealing the gesture; and the old stock AppBar/full-screen profile and intermediate “VIEW PROFILE” menu never appear.

4. **Friends — accepted**
   - **Get there:** Friends → Friends list → tap an accepted friend’s avatar/name/identity row.
   - **Verify:** The dossier opens directly above Friends and contains the remove-friend action at its bottom. Confirm the old remove-only menu does not appear first or remain available as a duplicate row destination.

5. **Friends — incoming and outgoing**
   - **Get there:** Friends → Pending → tap the avatar/name area of one incoming request and one sent request.
   - **Verify:** Each identity area opens the dossier directly. Confirm tapping Accept, Decline, or Cancel does not open the dossier underneath or above its existing control, and no second profile/menu launcher appears elsewhere in either row.

6. **Friends — search results**
   - **Get there:** Friends → search for users representing addable, pending, and already-friends states → tap each avatar/name region.
   - **Verify:** Each stable-ID identity opens the same dossier directly. Confirm the ADD/PENDING/FRIENDS control remains in its existing trailing region, tapping ADD does not also open the dossier, and missing-ID/self results do not gain a misplaced launcher.

7. **Leaderboard — podium/list across scopes**
   - **Get there:** Leaderboard → Global; tap another player in each occupied podium position and an ordinary list row. Switch the scope control to Friends and repeat podium/list taps.
   - **Verify:** Every non-self podium tile and list identity opens the same dossier directly above the Leaderboard. Confirm the scope control still changes scope without opening a profile, the dossier does not duplicate behind the podium/list, and self or missing-ID rows remain non-launchable.

8. **Ranked — weekly cohort and legacy ladder**
   - **Get there:** Ranked on a current weekly-cohort account → tap other walkers in collapsed and expanded group rows. Then use an older-backend/legacy fixture → tap each occupied podium place and an ordinary ladder row.
   - **Verify:** All non-self weekly rows and both legacy podium/list identities open the same dossier. Confirm “See full group,” Ranked help/friends controls, and self/missing-ID rows do not open it; the legacy podium has no separate or old two-step launcher left behind.

9. **Race Detail — solo active and final standings**
   - **Get there:** Races → open an active solo race, then a completed solo race/results state; tap non-self standings rows, including a row with effect icons.
   - **Verify:** Each identifiable non-stealthed runner opens the dossier directly over Race Detail in both active and final standings. Confirm self/stealthed/anonymous rows remain inert, the old friend-request menu never appears, and tapping an effect icon preserves its own overlay/affordance without also placing a dossier behind it.

10. **Race Detail — team active and final standings**
    - **Get there:** Races → open an active team race and tap another racer in each team’s scoreboard column; then open a completed team race and tap another racer in each grouped final-standing roster.
    - **Verify:** Both the compact team scoreboard cells and the final grouped planks open the same dossier. Confirm team headers, totals, expand/show-all controls, and effect-icon regions do not open it; no launcher is duplicated between the active cell and final plank implementations.

11. **Tab tutorial — Friends mirror**
    - **Get there:** Profile → Admin → re-run tutorial → advance to the real Friends-tab preview.
    - **Verify:** The offline fixture must visibly include one accepted row, one incoming row, one outgoing row, and deterministic search results for addable/already-friends/pending users; every fixture has a stable, asserted user ID and deterministic public-profile payload. Tap each identity region and confirm the dossier opens. Separately tap Accept, Decline, Cancel, Add, and the non-action FRIENDS/PENDING trailing states and confirm identity taps never steal those controls. Confirm tutorial spotlight/chrome stays above its intended target and is not duplicated or displaced after the dossier closes. This checkpoint fails—not conditionally skips—if any seeded row, ID, search result, or local action path is missing.

12. **Tab tutorial — Race Detail preview**
    - **Get there:** Profile → Admin → re-run tutorial → advance to the race-detail/powerups preview → dismiss or advance the spotlight enough to tap another standings identity.
    - **Verify:** The shared real Race Detail row opens the dossier above the preview without displacing the screen; after dismissal, the powerups spotlight still rings its original target. Confirm no full-screen profile route appears and no dossier remains behind the next tutorial beat.

13. **Onboarding demo race mirror**
    - **Get there:** Sign in with a fresh account → onboarding → demo race → reach the live standings beat and tap a rival identity.
    - **Verify:** The dossier must layer above the real demo Race Detail and its separate coach chrome; dismissing it returns to the same beat with coach ring/card in the original position. Confirm no old friendship menu appears, no duplicate sheet remains, and the coach does not sit on top of dossier controls.

14. **Inbox responsive placement matrix**
    - **Get there:** Run standalone and embedded Inbox with the same long-title mixed fixture at 320 logical pixels, on a large phone/tablet, at 1.3x and 2.0x text scale, and in both Light and Night appearance.
    - **Verify:** The header and one-board geometry remain intact in every combination: no horizontal overflow, clipped unread rail/icon/chevron, overlapping metadata, detached separator, card-per-row regression, or hidden final/load-more row. Titles/previews truncate or wrap only as specified, touch targets remain reachable, and palette contrast remains legible. Record the device/viewport, text scale, and theme for every matrix cell; do not substitute a single golden size for this check.

15. **Friends — accepted trailing affordance**
    - **Get there:** Friends → Friends list with an accepted friend, in Light and Night.
    - **Verify:** The accepted row has one trailing profile chevron aligned with the identity target. Tapping the chevron or identity opens the same dossier. Confirm the old more-menu affordance and remove-only sheet are absent, and `REMOVE FRIEND` exists only inside the dossier.

*Surfaces confirmed unaffected:* Tutorial wooden tab bar is a hand-forked copy, but no tab item is added, removed, renamed, or reordered by this change.

*Surfaces confirmed unaffected:* The Races-tab effect plates/inventory slots are hand-forked from Race Detail, but this change does not move or reorder effect/inventory UI.

*Surfaces confirmed unaffected:* Home SETUP fixture suppression is unrelated; neither Inbox nor the dossier adds a Home SETUP element.

*Surfaces confirmed unaffected:* Tutorial spotlight anchors are not attached to the Inbox rows or player identity rows being changed; only layering after opening/dismissing the dossier needs checking.

*Surfaces confirmed unaffected:* Leaderboard and Ranked have no dedicated tutorial preview pages in `tutorial_real_screens.dart`; only their real shell surfaces require checkpoints.

*Surfaces confirmed unaffected:* Race invite/member-pickers remain selection surfaces, so identity taps must keep selecting invitees rather than opening dossiers.

*Surfaces confirmed unaffected:* `RaceResultsSummaryScreen` podium/winner presentation is a separate result-card surface without the in-scope inspectable identity-row launcher; completed standings inside `RaceDetailScreen` remain covered above.

*Harness requirement resolved by the spec:* No production, demo, or tutorial code constructs `InboxHostMode.embedded`; therefore `integration_test/inbox_embedded_harness_test.dart` with the exact two-platform manual-hold command above is mandatory evidence, not an optional implementation discovery.

*Fixture requirement resolved by the spec:* Tutorial Friends currently omits stable user IDs and deterministic search rows; implementation must add the accepted/incoming/outgoing/search fixtures and asserted IDs described in checkpoint 11. Missing data is a failed checkpoint, not a reason to skip it.

*Risks found while planning:* Tutorial and demo Race Detail rosters contain stable user IDs, but their fake API services do not currently override public-profile/friendship calls. Enabling dossier taps without local overrides can leak a network request from a supposedly offline surface.

*Risks found while planning:* Legacy Ranked podium tiles are a separate `_PodiumPlace` implementation from ordinary ladder rows and currently have no player tap; both paths need independent launcher wiring.

*Risks found while planning:* Team Race Detail has two distinct player presentations—active `_teamColumnCell` scoreboard cells and final `_buildLeaderboardPlank` grouped rows—so updating only one leaves a shipped placement gap.

*Risks found while planning:* Friends identity taps share rows with Accept/Decline/Cancel/Add controls, Race Detail rows contain effect-icon child gestures, and Leaderboard shares space with its scope toggle. Launcher hit regions must wrap identity content only, not these child controls.

*Risks found while planning:* Solo `LeaderboardPlank` and team `_teamColumnCell` currently place effect trays inside a broader parent tap region. Identity and effect chrome must be structural siblings with independent gesture regions; gesture-arena ordering alone is not sufficient.

**Manual UI-Placement Test Plan — Race Detail identity-launcher supplement**

*Elements under test:* Pending-race participant avatar/name becomes a dossier launcher while the trailing kick control remains a separate removal target.

*Elements under test:* Occupied team-lobby slots become dossier launchers while empty slots remain join/switch targets and the viewer’s own slot remains non-launchable.

*Elements under test:* Race-course runners gain a profile affordance without removing or duplicating the existing progress tooltip.

*Elements under test:* Another player’s chat sender avatar/name becomes a dossier launcher while message-body long-press remains reserved for the viewer’s deletable messages.

*Elements under test:* Completed solo podium/single-winner and team winning-roster identities become dossier launchers in addition to the final-standings launchers.

*Checklist*

1. **Pending Race Detail — participant identity versus kick**
   - **Get there:** As a race creator, open a pending solo race containing accepted and invited non-self participants.
   - **Verify:** Tap a participant’s avatar/name and confirm the dossier opens directly above Race Detail. Dismiss it, tap the trailing remove-person icon, and confirm only the kick-confirmation sheet appears. Confirm the kick icon is not inside the dossier hit region, the dossier is not left behind the kick sheet, the old friendship menu is absent, and self/missing-ID rows remain non-launchable.

2. **Pending Race Detail — non-creator/read-only participant list**
   - **Get there:** Open the same pending race as an accepted non-creator or spectator.
   - **Verify:** Other identifiable participant avatar/name regions still open the dossier in their existing row positions, while no kick target appears. Confirm invited/accepted status badges remain trailing row chrome and do not open or duplicate the dossier.

3. **Pending Race Detail — team-lobby occupied versus empty slots**
   - **Get there:** Open a pending team race with at least one other occupied slot and one empty slot on each side; use an accepted participant who is allowed to switch teams.
   - **Verify:** Tap another player’s occupied slot and confirm the dossier opens from that filled slot. Dismiss it, tap an empty peg and confirm only the existing join/switch flow starts. Confirm filled and empty hit regions do not overlap, no dossier appears behind the team-switch flow, the viewer’s occupied slot remains non-launchable, and a full team column shows no phantom empty-slot target.

4. **Pending Race Detail — team-lobby invited/spectator states**
   - **Get there:** Reopen the team lobby as an invited player, then as a spectator/read-only preview.
   - **Verify:** Identifiable occupied slots open the dossier, while empty-slot availability remains exactly where the join/switch rules place it. Confirm disabled/read-only empty pegs do not gain dossier behavior, and occupied identities do not trigger the empty-slot action.

5. **Active solo Race Detail — course runner and progress tooltip**
   - **Get there:** Open an active solo race → course hero → tap a non-self, non-stealthed runner.
   - **Verify:** The existing anchored name/progress tooltip still appears beside the selected runner, and its profile affordance opens the dossier directly above the course. Confirm the tooltip is not replaced by an immediate dossier, the profile affordance does not duplicate the tooltip elsewhere, tapping outside dismisses only the intended overlay, and self/stealthed/anonymous runners expose no profile affordance.

6. **Completed solo Race Detail — course runner and progress tooltip**
   - **Get there:** Open a completed solo race → final-position course hero → tap another finisher.
   - **Verify:** The final progress tooltip remains anchored to that runner and offers the same dossier affordance as the active course. Confirm the dossier is not opened twice through the course and final standings, and the self runner remains non-launchable.

7. **Race Detail chat — sender identity versus message long-press**
   - **Get there:** Open an active race → Activity/Chat board → Chat; use a thread containing another player’s message and one of your own persisted messages.
   - **Verify:** First tap the other player’s avatar, dismiss, then separately tap the rendered sender name; each opens exactly one dossier above Chat without moving the message bubble. The sender name must be outside the message body’s long-press region. Tap and long-press the other player’s message body and confirm neither opens nor hides a dossier. Long-press your own persisted body and confirm only the delete-confirmation sheet appears; your own avatar/name remains non-launchable. Confirm pending/failed own messages have neither a misplaced profile target nor delete sheet. Repeat with a message whose sender matches a currently stealthed participant and confirm both avatar and rendered name are inert.

8. **Completed Race Detail — solo podium and single-winner fallback**
   - **Get there:** Open one completed solo race with two or three podium occupants, then a completed solo race with only one qualifying finisher.
   - **Verify:** Tap each non-self podium avatar/name and confirm the dossier opens from the occupied plinth; then tap the non-self single-winner avatar/name and confirm the same dossier opens from the fallback winner card. Confirm empty podium positions, plinth numerals, payout/step lines, and the viewer’s own podium position do not open it; no second launcher remains in the old full-screen path.

9. **Completed Race Detail — team winning roster**
   - **Get there:** Open a completed team race with a winning team, then a tied team race.
   - **Verify:** Each identifiable non-self avatar/name in the winning-team roster opens the dossier while the team plaque and placement pill remain noninteractive chrome. Confirm the viewer’s own winner identity does not launch, and the tie board adds no player-profile target because it contains no winner identities.

10. **Tab tutorial mirror — active course**
    - **Get there:** Profile → Admin → re-run tutorial → race-detail/powerups preview → reach a state where the course can be tapped → select another preview runner.
    - **Verify:** The progress tooltip remains anchored to the preview runner and its profile affordance opens the dossier above the real shared Race Detail. After dismissal, the tutorial spotlight still rings the powerups target; no tooltip, dossier, or full-screen profile remains behind the next beat.

11. **Tab tutorial mirror — chat sender**
    - **Get there:** In the tutorial Race Detail preview, scroll to Activity/Chat → Chat → locate the seeded message from Sam Rivera.
    - **Verify:** Sam’s avatar/name opens the dossier from the sender region while the message bubble stays in place. Confirm the seeded viewer message remains self/non-launchable and its bubble does not acquire a competing profile target.

12. **Onboarding demo race — active course dossier**
    - **Get there:** Sign in with a fresh account → onboarding → demo race → reach the active course → tap a rival runner and use the tooltip’s profile affordance.
    - **Verify:** The racer dossier must open above the course and the hand-forked demo coach chrome. Confirm the progress tooltip still appears first, the coach ring/card does not cover dossier controls, dismissing the dossier returns to the same scripted beat, and no live/full-screen friendship menu appears.

13. **Onboarding demo race — completed podium dossier**
    - **Get there:** Complete the onboarding demo race → wait for the real completed Race Detail podium.
    - **Verify:** Tap each non-self occupied podium identity and confirm the dossier opens above the completed demo and coach/win chrome. Confirm the viewer/winner’s own identity remains non-launchable, no old profile page appears, and dismissing the dossier returns to the same completed podium without restarting or advancing the demo.

14. **Pending solo course runner — tooltip then dossier**
    - **Get there:** Open a pending solo race state that already renders the course/runner preview and select another identifiable runner.
    - **Verify:** The existing progress tooltip appears first and remains anchored. Its explicit `VIEW PROFILE` affordance opens one dossier; the runner itself does not bypass the tooltip. Self, stealthed, anonymous, and missing-ID runners expose no profile affordance, and dismissal returns to the unchanged pending state.

15. **Completed chat — identity and long-press parity**
    - **Get there:** Open a completed race whose Activity/Chat history contains another participant and one of the viewer’s persisted messages.
    - **Verify:** Avatar and rendered sender name independently open the dossier exactly as in the active race; body tap opens nothing. Long-press the viewer’s persisted message body and confirm only the existing delete-confirmation sheet appears; no dossier opens or remains hidden behind it. Privacy suppression for a sender matched to a stealthed participant remains active after completion.

16. **Tutorial/demo relationship action preserves scripted state**
    - **Get there:** In the tab tutorial and onboarding demo, open a seeded rival’s dossier and execute each relationship path exposed by that fixture, including reverse-pending Add auto-accept.
    - **Verify:** Each action is handled only by the deterministic fake, updates the dossier to the contract state, and survives its authoritative fake reconciliation. Dismissal returns to the same tutorial/demo beat, spotlight/coach position, and race progress; no script advances, restarts, or performs a network call. Reopen the dossier and confirm the reconciled relationship persists for the remainder of that scripted session.

*Surfaces confirmed unaffected:* Pending participant lists and team lobbies have no tutorial/demo mirror: the tab-tutorial Race Detail fixture is active solo, and the onboarding demo transitions only between active and completed solo states.

*Surfaces confirmed unaffected:* Onboarding demo chat has no user-message rows, so it has no sender identity checkpoint; its fake engine deliberately returns an empty USER feed.

*Surfaces confirmed unaffected:* The tab-tutorial Race Detail fixture never reaches a completed state, so completed podium/winner coverage belongs to the real completed screen and onboarding demo.

*Surfaces confirmed unaffected:* `HomeCourseTrack` is shared with Home, but Home’s course runner interaction is not part of this feature; Race Detail profile behavior must be opt-in so Home retains only its existing progress tooltip.

*Risks found while planning:* `TeamLobbyBoard` currently exposes a callback only for empty slots; occupied slots have no identity callback or user-ID-aware semantics. Adding the dossier target must not wrap the whole board or empty pegs.

*Risks found while planning:* `GoalTrackRunner` currently carries presentation data but no user ID/profile callback, and `HomeCourseTrack` owns the existing whole-runner tooltip tap. Race Detail needs opt-in identity data plus a profile affordance inside or alongside that tooltip; replacing the runner tap would regress progress inspection and could unintentionally alter Home.

*Risks found while planning:* `_ChatBubble` currently places the rendered sender name inside the same long-press container as message content. Identity chrome (avatar/name) and body must become sibling gesture regions; merely adding a child tap handler leaves an ambiguous gesture arena and fails checkpoints 7 and 15.

*Risks found while planning:* `PodiumFinisher`/`RacePodium` currently discard participant user IDs and expose no tap callback. The shared podium model needs optional identity plumbing without making self, empty plinths, payout text, or unrelated result-card podiums globally tappable.

*Risks found while planning:* The single-winner code reads `winner['id']` while some fixtures, including the demo engine, provide `winner['userId']`. Identity resolution must fall back defensively or the mandatory demo winner/podium behavior will diverge.

*Risks found while planning:* Team winning-roster entries and final-standing planks are separately built inside Race Detail. Wiring only final standings leaves the prominent winning-team identities non-launchable.

*Risks found while planning:* The pending solo state can also render the course runner preview; active/completed course coverage alone leaves that presentation unverified. Checkpoint 14 is mandatory.

*Risks found while planning:* Finished Race Detail retains read-only chat/history presentation. It requires the explicit completed-chat widget case in checkpoint 15; an active-chat assertion is not sufficient parity evidence.

*Risks found while planning:* The tutorial and demo fake API services still need local public-profile/friendship overrides before any mandatory dossier launch is enabled; otherwise the new course, chat, or podium affordance can escape the offline mirror and attempt a live request.

## Revision log

- **Draft:** Inventoried the existing public-profile, friend menu, player-tap,
  Inbox, Races, theme, and backend-contract seams. Chose a compact trail-ledger
  Inbox and modal racer-dossier direction using only existing Bara primitives.
- **Gap pass 1:** Defined "anywhere" as inspectable identity surfaces with a
  stable ID, explicitly protected selection/navigation taps, added all Friends
  relationship states, separated profile and relationship failures, and kept
  inline actions from being swallowed by row taps.
- **Gap pass 2:** Added missing/malformed/404 behavior, small-screen/text-scale/
  night-theme/accessibility checks, a structural launcher guard, explicit
  backend-no-change contract locking, no-flag/version-skew rules, and the
  production-deploy authorization boundary.
- **Architect review — REVISE:** Expanded "anywhere" to pending participants,
  team-lobby slots, course runners, chat senders, live/final standings, and
  completed Race Detail podium/winner presentations; specified the shared
  dossier signature/state machine; made tutorial/demo fake-service coverage
  mandatory; corrected the backend test command; and inserted the UI planner's
  checklist verbatim.
- **Post-review gap pass 1:** Resolved gesture ownership for kick, empty-slot,
  progress-tooltip, effect, chat-long-press, selection, and primary navigation
  surfaces; required stable IDs to flow through shared visual models instead of
  importing API services into them.
- **Post-review gap pass 2:** Added late-future/auth-rotation coverage, preserved
  known relationship actions when reconciliation fails, documented mutation
  precedence, and required a test-only on-device embedded-Inbox host so every
  manual checkpoint is executable without production-only chrome.
- **Architect review round 2 — REVISE:** Named every tutorial/demo API override,
  required the network guard to exercise both relationship reads and all
  mutations, removed conditional demo behavior, and added the UI planner's
  verbatim Race Detail supplement for pending/lobby/course/chat/podium/winner
  placements and their competing gestures.
- **Developer-runbook gap pass 1:** Added a locked decision ledger, exact public
  types/keys/modal geometry, independent async/auth-generation rules, defensive
  profile/relationship projections, mutation and confirmation state matrices,
  file-by-file surface wiring, tutorial/demo fixture IDs, and compact Inbox
  dimensions/copy so implementation requires no product guesses.
- **Developer-runbook gap pass 2:** Corrected mutation-generation timing,
- **Implementation verification (2026-08-24):** Shared dossier wiring,
  defensive relationship state, tutorial/demo offline services, reveal-time
  demo box commits, and Inbox/race identity fixes are implemented. `flutter
  analyze`, feature-focused Flutter suites, Android prod appbundle compilation,
  iOS no-codesign compilation, backend `friends.test.js` (22/22), and
  `public-profile.test.js` (3/3) pass. Production sign-off remains pending:
  a real FriendsTab launcher test now passes, but equivalent real-surface
  coverage for Leaderboard, Ranked, Race Detail, tutorial Friends/Race Detail,
  and the remaining edge-case matrix is incomplete; the repository-wide
  Flutter suite has unrelated existing failures; and signed-device
  verification is unavailable in this environment.
  specified blank-ID/signed-out behavior, made Friends refresh coalescing
  explicit, pinned protected red/green test order and structural guard sanity
  checks, and replaced placeholder platform verification with current
  production-style iOS/Android commands while preserving unprovisioned Android
  rewarded-unit behavior.
- **Final architect/UI review — REQUIRED findings resolved:** Locked reverse-
  pending send auto-accept and HTTP statuses; specified mutation-failure
  reconciliation and exactly-once invalidation; made chat launchers derive
  stealth from the participant snapshot; resolved the `integration_test`/
  `pubspec` contradiction; required keystore, production AdMob ID, and upload-
  certificate proof; and replaced conditional manual checks with deterministic
  embedded-Inbox, tutorial Friends, responsive, gesture-isolation, pending-
  course, completed-chat, and scripted-state checkpoints.
- **Final approval pass:** Corrected the reverse-pending fixture direction and
  ID-less Add transitions, then received architect **APPROVE** and UI-placement
  **APPROVE** with no remaining required findings.
