# Banner ads remote control and Admin toggle

## Summary & user story

As an operator, I need the existing `bannerAdsEnabled` database setting to
control banner rendering in the mobile app and to be editable from Admin →
Config, so banner inventory can be paused or resumed without an app release.

## Scope / non-goals

In scope: consume the existing `/auth/me` `featureFlags.bannerAdsEnabled`
boolean, make all existing banner placements honor it, and restore one
`Banner ads` switch in the Admin Config panel using the existing
`GET/PATCH /admin/settings` contract.

Out of scope: rewarded ads, box-reroll ads, changing ad unit IDs, new release
flags, or database schema changes. Because the backend recently graduated this
setting to a permanent compatibility value, this work explicitly reactivates
the existing `bannerAdsEnabled` operational control in the backend; it does not
introduce a second flag.

## Existing contract

The backend must retain and expose the existing setting as a mutable boolean.
It currently has a graduated/permanent path that always returns `true` and
rejects writes; the backend implementation must move `bannerAdsEnabled` back
to the mutable known/admin-exposed set, with a safe default of `true` for
older/missing rows, and remove it from the permanent rejection list. It must
continue returning:

```json
{"featureFlags":{"bannerAdsEnabled":false}}
```

from `/auth/me`. `GET /admin/settings` returns the settings envelope, and
`PATCH /admin/settings` accepts `{ "bannerAdsEnabled": false }` and returns
`{ "settings": { ... } }`. No migration is needed, but backend code and tests
must be deployed before the app. PATCH errors remain `401`/`403` for auth,
`400` for unknown/non-boolean keys, and `500` for server failure. The client
must validate the returned envelope and roll back on any error.

The minimum client behavior is additive: old clients that do not read the
remote value continue their existing build-time behavior. Do not change the
backend default away from `true` until the carrying app build is available;
production is currently explicitly set to `true`.

## Frontend plan

1. Add defensive `AuthService` state for the flag. A present boolean is used;
   a missing/malformed value defaults to enabled for compatibility with older
   backends and the current shipped behavior. Sign-out resets the value to
   enabled.
2. Make `AdService` expose a runtime banner gate, set by `AuthService`, while
   retaining the build-time unit-ID gate. The effective gate is
   `remoteEnabled && platformUnitIdPresent` for standard, box-top, and native
   banner placements. `dualBoxBannersEnabled` remains independent. Use one
   shared notifier/controller so mounted slots and direct spacing checks rebuild
   when the flag changes; false→true must arm a previously suppressed slot.
3. Ensure `AdBannerSlot`, `AdInlineCard`, and existing direct banner spacing
   checks use the runtime-aware gate. Rewarded-ad gates remain unchanged.
   Explicitly cover shell, race detail/results, public races, tournament,
   case/multi-case opening, daily reward, Shop/Get Coins, and Races in-feed
   native placements. Handle in-flight/stale banner loads safely on both
   transitions.
4. Restore the `Banner ads` switch in Admin → Config. It loads from
   `GET /admin/settings`, optimistically updates through `PATCH /admin/settings`,
   rolls back on failure, and treats absent/malformed values as enabled. The
   panel shows a saving/disabled state and an error toast on failure.
5. Keep iOS and Android behavior identical; build-time platform unit IDs remain
   required in addition to the remote flag.

## Tests-first plan

- Frontend widget/integration test: a real banner slot reserves no space while
  the runtime flag is false and resumes when true, without affecting rewarded
  ads.
- Auth parsing test: missing/null/malformed `bannerAdsEnabled` defaults safely
  to enabled; explicit false is retained.
- Admin widget test: Config renders `Banner ads`, loads its value, sends the
  existing patch payload, and rolls back on a failed save.
- Preserve and update only assertions that describe the intentionally restored
  control; do not weaken unrelated existing tests.

## Backward compatibility & rollout

Deploy backend first, with `bannerAdsEnabled` mutable and default/fallback
`true`; then ship the iOS and Android app build. The current production row is
`true`. Existing binaries continue using their frozen build-time behavior until
updated, so no pre-release false value is permitted. App-setting reads retain
the existing bounded settings/auth cache behavior (up to roughly 30–60 seconds
depending on the cached response); no new cache or runtime toggle is added.
This is the existing operational setting being restored, not a new release
flag.

## Acceptance criteria

- Explicit `false` from `/auth/me` prevents every banner widget and associated
  banner spacing from rendering.
- Explicit `true` permits existing build-enabled banner placements.
- Missing or malformed remote data does not crash and defaults enabled.
- Backend `/auth/me` and Admin settings visibly expose and persist the switch
  through the existing
  API, with defensive loading/error behavior.
- `flutter analyze` and relevant tests pass; iOS and Android code paths compile
  from the same Dart implementation.

## Manual UI-placement test plan

Admin → Settings → Admin → Admin Tools → expand CONFIG. Verify `Banner ads`
appears above the Home service banner, has the correct current value, disables
while saving, and restores its prior value with an error toast if saving fails.
Sign in on both iOS and Android, verify a build with banner unit IDs shows a
banner when enabled and no banner/empty reserved gap when disabled. Check Home,
Shop, race detail, case opening, daily reward, and race results. No demo-race
tutorial or tab-tutorial Admin mirror reuses this panel; still verify tutorial
screens do not regress when the global banner gate is false.

## Revision log

- Gap pass 1: identified that the existing backend flag is already additive and
  that the frontend currently hardcodes `AuthService.bannerAdsEnabled` and
  only checks build-time AdMob IDs; added a runtime notification gate.
- Gap pass 2: added malformed/missing-field defaults, rollback behavior,
  direct-spacing coverage, rewarded-ad non-regression, and iOS/Android checks.
- Architect/UI review: pending.
