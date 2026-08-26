# Referral Contest Joined Dashboard — Requirements

Status: **DRAFT — AWAITING PRODUCT APPROVAL**

## 1. Summary and user story

After a signed-in user accepts the active global referral contest rules and the
entry request succeeds, Bara replaces the legacy curved-trail experience with a
compact joined dashboard matching the shipped Overview and Official Rules
screens.

As an entrant, I can immediately see the prize, remaining time, my qualified
and pending-review referrals, and my current rank; copy or share my invite; see
recent referral activity; and open the contest leaderboard.

The screen prioritizes, in order: progress, sharing, recent activity, and the
leaderboard. It does not repeat entry instructions or legal copy.

## 2. Scope

### In scope

- Replace `ContestTrailScene` for joined global contests only.
- Reuse the current referral green texture, compact header, cream panels,
  chunky forest-green shadows, gold primary button, typography, trophy, and
  envelope art.
- Dynamic qualified count, pending-review count, rank, rank context, invite
  code, share URL, embedded leaderboard preview, and recent activity.
- Header share action and primary share CTA use the existing native share flow.
- Copy affordances for invite code and share URL.
- Pull-to-refresh through the existing contest reload path.
- Loading skeletons, empty recent-activity state, missing-rank state, and
  recoverable load/share/copy errors.
- An embedded leaderboard preview with the top three plus the entrant. `View
  Full` expands the existing leaderboard surface; no new Screen 4 is included.

### Out of scope

- Changes to contest rules, scoring, qualification, tie-breaking, rewards,
  entry, countdown semantics, or admin workflows.
- A full referral-history screen (`VIEW ALL` is omitted until such a route
  exists).
- A new leaderboard route or Screen 4.
- New decorative art. Existing coherent referral assets are reused.
- Background polling or refresh-on-every-resume.

## 3. Product behavior

### Entry and routing

- The successful rules-screen join continues into the existing
  `GiveawayScreen` joined state; no second copy of contest state or route is
  introduced.
- An already joined entrant opening the contest from Home or Referrals lands on
  the joined dashboard.
- Back behavior remains unchanged.

### Summary

- Shows trophy, formatted coin prize, human countdown, and `JOINED` badge.
- Uses the same countdown source and formatter as Overview/Rules.
- `ELIGIBLE` shows `JOINED`; `UNDER_REVIEW` retains its existing notice.
  `INELIGIBLE` and `WITHDRAWN` never show `JOINED`, stats, invite, copy, or
  share. Sharing is disabled while the contest is verifying or final. Cancelled
  contests are unreachable from the current-member query and are out of scope.

### Progress

- `QUALIFIED` = `standing.verifiedCount`.
- `PENDING` = `standing.reviewableCount`; supporting copy is `REVIEW` rather
  than claiming every newly signed-up referral is pending.
- `RANK` = `standing.provisionalRank`, displayed as `#n`; missing rank displays
  an em dash.
- `percentile` = `ceil(100 * rank / rankedEntrantCount)`, clamped to 1–100,
  where only entrants with verified referrals are ranked.
- For rank `r > 1`, `nextTargetRank = r - 1` and
  `referralsBehindNextTarget = ahead.verifiedCount - mine.verifiedCount + 1`.
  First place and unranked entrants have no next target; unranked entrants have
  no percentile. Missing/invalid additive context is hidden safely.
- All values are defensive: missing/null/malformed additive fields render safe
  zero/empty states and never crash an older or newer app/backend pairing.

### Invite

- The actual `share.code` and `share.url` are shown.
- Copying either value uses the clipboard and the existing Bara feedback style.
- Header and primary CTA invoke the existing native share sheet with the
  existing referral share copy and exact backend URL.
- The invite URL is read-only UI, not an editable text field.

### Recent referrals

- Shows at most four newest items, newest first.
- Only a public display name, event time, and coarse status are exposed. No
  user ID, provider identity, race ID, device/network signal, review reason, or
  internal fraud state is returned.
- Supported client statuses are `SIGNED_UP`, `IN_RACE`, `UNDER_REVIEW`,
  `QUALIFIED`, and `NOT_COUNTED`.
- `NOT_COUNTED` is returned only for an explicit contest-point rejection; it
  does not claim the person was globally or legally disqualified and never
  reveals why.
- Each recent item parses independently. Malformed or unknown-status items are
  skipped; they never invalidate the established contest payload and are never
  misleadingly downgraded to `SIGNED_UP`.
- When no items exist, the card says `NO REFERRALS YET` and `Share your invite
  to get started.` without a duplicate large CTA.
- Only rows with a live referral, live non-review referee, and valid current
  public display name are shown. Deleted/invalid identities are omitted and
  never reconstructed from hashes, snapshots, or IDs. Progress totals may
  therefore exceed visible activity rows.
- Times are rendered from `occurredAt` as compact relative times from UTC
  instants. Future or
  invalid timestamps fall back safely.

## 4. API contract

### Existing endpoint, additive response

`GET /giveaways/current/me`

Authentication, feature negotiation, cache headers, existing fields, and
existing error behavior remain unchanged. The backend adds optional activity
and standing-context fields:

```json
{
  "recentReferrals": [
    {
      "displayName": "capy.king",
      "occurredAt": "2026-08-25T21:00:00.000Z",
      "status": "QUALIFIED"
    }
  ],
  "standing": {
    "verifiedCount": 4,
    "reviewableCount": 1,
    "provisionalRank": 8,
    "reachedCountAt": "2026-08-25T21:00:00.000Z",
    "percentile": 27,
    "referralsBehindNextTarget": 2,
    "nextTargetRank": 7
  }
}
```

Contract rules:

- `recentReferrals` is always an array for clients advertising
  `referral_contest_global_v1`; it is empty when there is no visible current
  contest, the member has withdrawn, the member has not joined, or there are no
  attributable rows.
- Maximum four records. The server orders by `occurredAt DESC`, then a stable
  internal ID descending before stripping all IDs from serialization.
- Older clients ignore the additive field. The Flutter model defaults a missing
  or null field to `[]` for mixed-version safety.
- No new request parameter is required.
- Rank-context fields are derived from the already-materialized full standings
  inside `memberCurrent`, never from the truncated serialized leaderboard and
  without another query.
- The public unauthenticated contest endpoint does not expose this field.

### Server status derivation

- Precedence is: explicit rejected review → `NOT_COUNTED`; verified fact or
  approved flagged fact → `QUALIFIED`; unresolved flagged fact →
  `UNDER_REVIEW`; eligible race activity → `IN_RACE`; otherwise `SIGNED_UP`.
- Fact classification is shared with standings rather than reimplemented.
- `occurredAt` is the rejection review time for `NOT_COUNTED`, qualification
  time for `QUALIFIED`/`UNDER_REVIEW`, qualifying-race join time for `IN_RACE`,
  and attribution time for `SIGNED_UP`.
- The entrant event window begins at `max(contest.startsAt,
  entry.rulesAcceptedAt)`. Signup uses `Referral.createdAt`; race activity uses
  participant `joinedAt`; fact states use `qualifiedAt`. All qualifying facts
  remain before the exclusive `contest.endsAt` boundary. A pre-entry
  attribution that qualifies after entry remains visible and scored.
- `IN_RACE` means the referee is accepted in a non-seeded, non-tournament race
  with another accepted participant, joined in the event window, and has no
  higher-precedence fact state. It reuses the social-domain qualification
  predicate pieces; it does not promise the race will ultimately qualify.

### Errors

- Existing endpoint status/error envelopes remain unchanged.
- Failure to load recent activity is fail-soft: log the bounded diagnostic and
  return `recentReferrals: []`; it must not make the established contest payload
  unavailable.

## 5. Backend implementation

- Social owns and exports the referral/race/fact candidate query; Giveaways owns
  the point-review overlay and public serialization. The collaborator is
  injected into `buildGiveawayService` and invoked only for a capable client
  with a joined global entrant.
- Add a bounded query/service that reads referrals attributable to the current
  entrant and maps them to the coarse public contract above.
- Reuse contest qualification and review semantics; do not fork scoring logic.
- Use Postgres directly (no Redis): fetch at most four candidates per event
  source, merge/classify only that fixed small candidate set, batch-load review
  and race state, and perform no per-row queries.
- Add expand-only composite indexes for the ordered paths, including
  `Referral(referrerId, createdAt)` and the accepted-participant access path
  `RaceParticipant(userId, status, joinedAt)`, subject to implementation query
  confirmation. This requires an additive migration.
- Catch only failure from the injected recent-activity collaborator, log a
  bounded diagnostic, and return `[]`; never wrap standings, entry, or share in
  that fail-soft catch.
- Add the field in `memberCurrent` only. Preserve the exact legacy no-contest
  response shape for clients without the global-contest capability if existing
  integration contracts require it.

## 6. Flutter implementation

- Introduce a focused joined-dashboard widget under `lib/widgets/`; keep
  `GiveawayScreen` responsible for loading, refresh, navigation, and sharing.
- Extend `GiveawayCurrent` with a defensive `recentReferrals` list and a small
  enum/value model. Do not use unchecked casts or required server fields.
- Reuse shared Screen 1/2 visual primitives/constants rather than duplicate
  greens, creams, shadows, radii, prize/countdown formatting, or CTA styling.
- Structure: compact header; summary; `YOUR STANDING`; one combined standing
  card with large rank and qualified count plus context strip; embedded top-3
  plus entrant leaderboard preview; compact invite; minor recent activity.
- Remove the three equal stat cards and the bottom `VIEW LEADERBOARD` button.
- Compose preview rows from `leaderboard.take(3)` and the viewer's entry and
  standing. Identify self by unique rank, never display name; highlight rather
  than duplicate a viewer already in the top three.
- `View Full` inside the preview expands/collapses the existing inline drawer,
  preserves state across refresh, and moves accessibility focus to it.
- Next-target chase copy appears only while active for eligible/under-review
  entrants. Verifying/final screens retain rank context without a chase prompt.
  Unranked active copy invites the entrant to earn their first qualification.
- Page margins are 16 dp. Invite uses the established gold CTA in a compact
  horizontal layout where width permits and stacks without shrinking tap
  targets on narrow/large-text layouts.
- The header action is share only when sharing is allowed. Pull-to-refresh
  replaces the old header refresh action.
- RefreshIndicator triggers the existing reload once and does not poll.
- Decorative icons are excluded from semantics; copy/share/buttons and the
  progress values have explicit accessible labels.

## 7. Loading, empty, and failure states

- Header stays visible during load. Content shows shape-matched skeletons, not
  a page-level spinner.
- Missing invite data hides copy/share controls and presents existing retry
  feedback; no placeholder code or fake URL is rendered.
- Missing rank renders `—`.
- Zero progress renders `0`, not blank.
- Recent activity load failure degrades to the same empty card while the rest
  of the dashboard remains usable.

## 8. Testing (tests first)

### Backend integration

- Through authenticated HTTP and a dedicated test Postgres, assert the additive
  recent-referral response for signed-up, in-race, qualified, and explicitly
  rejected referrals, plus unresolved flagged facts and approved/rejected
  precedence.
- Assert exact `occurredAt` meaning, deterministic tie order, newest-first
  order, maximum four, contest/entry window filtering, and
  no user IDs/provider hashes/race IDs/review reasons in the serialized body.
- Assert pre-entry attribution that qualifies after entry, no contest, not
  joined, withdrawn, deleted/invalid/review-account referees, and legacy-client
  behavior.
- Assert a recent-query failure returns `[]` with the unchanged core payload.
  Without the capability, assert the key is absent and the collaborator is not
  invoked.
- Assert existing standing, leaderboard, entry, and share fields remain
  unchanged.

### Flutter widget/integration

- Pump the real joined `GiveawayScreen` with API-shaped payloads and assert
  summary, dynamic stats, invite code/link, recent rows, and button hierarchy.
- Assert missing/null additive data gives safe empty states.
- Assert malformed and unknown recent rows are skipped without rejecting the
  dashboard.
- Assert header and main share actions use the exact existing share URL.
- Assert copy actions copy the correct values.
- Assert leaderboard action opens the existing real leaderboard surface.
- Assert pull-to-refresh invokes the service and updates values.
- Assert withdrawn, ineligible, under-review, verifying, and final states expose
  only their permitted controls and never misleading `JOINED`/share actions.
- Assert 375, 390, and 430 logical-pixel widths have no overflow; verify text
  scaling and both iOS/Android rendering paths through shared Flutter code.
- Replace old curved-trail assertions; do not weaken unrelated contest tests.

## 9. Compatibility and rollout

- Backend change is additive and deploys before the app.
- Old clients continue using all existing response keys and ignore
  `recentReferrals`.
- New clients tolerate an old backend by defaulting `recentReferrals` to `[]`.
- No feature flag, kill switch, or new build-time configuration.
- No production or staging deployment is part of implementation approval.
- Both iOS and Android builds use the same Dart implementation and must be
  accounted for before release.

## 10. Acceptance criteria

- Joined entrants never see the curved trail UI.
- The screen answers prize, time left, qualified count, pending-review count,
  rank, and next action without scrolling on a normal Pro-size phone where
  practical; smaller phones scroll naturally.
- All primary card edges align to the same 16 dp margins and match Screen 1/2
  styling.
- No dynamic examples are hardcoded.
- Share and copy use the entrant's exact backend code/URL.
- Recent activity is privacy-minimized, capped, correctly ordered, and safely
  absent with an older backend.
- `flutter analyze` is clean; relevant frontend and backend integration tests
  pass; no existing test is skipped or weakened.
- Required architect, UI-placement, and post-implementation code reviews are
  complete before the work is called done.

## 11. Gap-pass revision log

### Pass 1 — data and privacy

- Replaced the mockup's unsupported percentile with an intentional omission.
- Distinguished `reviewableCount` from generic pending signups so the stat does
  not misrepresent scoring.
- Added a minimized recent-activity contract that excludes internal IDs and
  fraud details and degrades independently from the core contest response.

### Pass 2 — navigation, lifecycle, and compatibility

- Scoped leaderboard navigation to the existing real surface because Screen 4
  is not part of this request; removed fake `VIEW ALL` navigation.
- Defined non-active lifecycle handling so a joined screen cannot falsely show
  `JOINED` for final/cancelled contests.
- Added old-backend/new-app and new-backend/old-app behavior, test-first public
  HTTP coverage, and explicit no-deploy/no-flag constraints.
