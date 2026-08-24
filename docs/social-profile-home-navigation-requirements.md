# Social profiles and home navigation — requirements

## Summary & user story

Users should see a simpler home screen: no leaderboard link, no profile control
in the header, and no Inbox tab. The tab currently called Rank is labeled
Leaderboard. Home shows a Notifications card above Daily Reward and Shop only
when the user has more than one unread notification; tapping it opens the
existing inbox screen. Profile returns to the bottom-right navigation item.

When a user taps another user's name, the existing add-friend sheet remains the
first interaction. A new `VIEW PROFILE` action below it opens a public profile
showing that user's character/equipped accessories, race wins/podium trophies,
and average step count. Missing or unavailable fields render safe placeholders.

## Scope / non-goals

In scope: Flutter shell/home/nav changes, public profile read API and screen,
integration/widget coverage, and one-time production cleanup of existing test
notifications. Out of scope: changing race scoring, ranked calculations,
friendship semantics, notification generation, or profile editing.

## API contract

Add authenticated `GET /friends/:userId/profile` with an additive response:

```json
{
  "contract": "public-profile-v1",
  "user": {"id":"...", "displayName":"...", "profilePhotoUrl":null,
           "equippedAnimal":null, "equippedAccessories":[]},
  "stats": {"racePodiums":{"first":0,"second":0,"third":0},
            "avgStepsPerDay":0}
}
```

The endpoint returns 401 for missing/invalid auth, 404 with the same body for
unknown, deleted, review, blank-name, or non-discoverable users, and 500 only
for infrastructure failure. Discovery is the existing social identity policy:
non-null display name and non-review account; hidden leaderboard status does
not expose extra private data and must not be used as a bypass. Self access is
allowed only when it already satisfies that policy. The response never includes
email, client features, or raw cache fields. Character output is filtered by
the existing `characterPresentation` rules, client features, release channel,
and remote-asset support; no test-only assets are returned.

Stats are Postgres source-of-truth aggregates. Average steps means the rounded
arithmetic mean of recorded daily step rows through today (zero when there are
no rows); race trophies count completed, accepted, non-forfeited participants
using the existing effective team placement rules. Existing endpoints and
response keys remain unchanged; old app versions ignore this new endpoint and
continue using existing friendship sheets. Only a missing route (not a profile
404) may be treated as unsupported by a future client.

The existing Inbox alert endpoint remains the source for unread count and
mark-read behavior. The new home card uses a defensive count (`> 1` only).

## Data model / migrations

No new user columns are required. Reuse user presentation/equipped-accessory
data and existing race participant and daily step rows. If the backend needs a
query module, keep all aggregates read-only and null-safe.

## Frontend plan

- Rename visible Rank navigation copy to Leaderboard without changing route or
  index contracts.
- Remove the Home leaderboard ticket and header profile affordance.
- Remove Inbox from the visible shell nav; retain the existing inbox route and
  open it from Home Notifications.
- Place Profile at bottom-right of the nav bar as shell page index 4. Inbox
  remains a pushed route and is never a shell page.
- Add a Home Notifications card immediately above Daily Reward and Shop; render
  only for unread count > 1, and refresh count after opening/reading Inbox.
- Extend the existing friend request sheet with a View Profile button below
  the current add-friend behavior.
- Add a public profile screen that loads the new endpoint, renders the real
  equipped character/accessories, trophy counts, and average steps, with
  loading/error/unknown-user states.
- Use the same Dart behavior for iOS and Android and avoid unchecked casts or
  non-null assertions on server data.

## Backward compatibility / rollout

Deploy backend first. Old binaries receive no changed required fields and do
not call the new route. The carrying app falls back safely if the endpoint is
404, a field is absent, or the server predates the route. No release flag is
added. The production notification cleanup is a separately authorized,
explicitly scoped one-time data operation against only test-flight users; it
must be executed only after resolving the exact production user scope and
backing up/counting affected rows.

## Test plan (tests first)

- Backend integration: public profile response, visibility/404 behavior,
  aggregate correctness, and missing optional presentation data.
- Frontend integration/widget: shell labels/order, Home notification threshold
  (0/1 hidden, 2 visible), Inbox navigation, profile placement, friend sheet
  preserving add-friend and exposing View Profile, and profile loading/error/
  rendered stats.
- Run `flutter analyze` and the relevant Flutter test suites; backend tests use
  the dedicated test database only.

## Acceptance criteria / definition of done

All requested Home/nav changes and public profile behavior are implemented,
tested through public paths, both platforms remain accounted for, version skew
is safe, manual UI mirror checks are handed to the user, code review passes,
and production notification cleanup is verified complete. Ready-to-deploy is
not claimed with failing or skipped required checks.

## Manual UI-placement test plan

1. Live shell: Home, Races, Leaderboard, Friends, Profile in that order; no
   Inbox item; Profile bottom-right; selected tab and back behavior work.
2. Home: no `home-leaderboards-ticket` and no `home-profile-button`; with 0/1
   unread the notification card is absent, with 2+ it appears exactly once
   immediately above Daily Reward and Shop and opens pushed Inbox.
3. Friends, Leaderboard, Ranked, and Race Detail: tapping a person's name
   still opens the add-friend sheet first; `VIEW PROFILE` is below that action
   and opens the public profile; back returns to the originating surface.
4. Public profile: character/accessories, first/second/third trophies, average
   steps, missing assets, 404, loading, and error states remain correctly laid
   out on iOS and Android.
5. `lib/tutorial/tutorial_real_screens.dart`: hand-copied tab bar matches the
   live five-item order and Profile mapping; real Home/Friends screens retain
   spotlight anchors and do not require network access. Check demo fixtures in
   `demo_race_api_service.dart`, `demo_race_engine.dart`,
   `tutorial_preview_data.dart`, and `demo_auth_service.dart`; demo race
   surfaces themselves do not render this shell and are unaffected.

## Revision log

- Draft: consolidated the navigation cleanup, notification threshold, and
  public-profile interaction while preserving existing add-friend behavior.
- Gap pass 1: made the endpoint additive, visibility-aware, and defensive for
  frozen clients; prohibited new release flags and scoped production cleanup.
- Gap pass 2: required public-path integration coverage and explicit loading,
  error, and tutorial/mirror placement checks.
