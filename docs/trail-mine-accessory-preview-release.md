# Trail Mine placement and accessory preview release

User has deferred the frontend release to bundle further changes. No new build
number is reserved and no upload will be performed. Existing App Review
submission/build 19 must remain untouched. Backend deployment is also pending.

Implementation is complete. No
new build upload or backend deployment has occurred. Build 20 is already available to existing internal testers and retains
the previous gold-lock styling; this release supersedes that styling.

The new preview endpoint returns a read-only, server-approved character and
outfit. Older clients retain their existing API behavior. Mine position is
optional metadata on an existing owner-only active effect. No migration,
price/odds change, new art or feature flag is required.

Requirements and manual UI checks are recorded in
[the feature specification](trail-mine-visibility-accessory-preview-requirements.md).
Independent architecture review approved the design after bounded-read and
lifecycle details were pinned. Independent implementation review is clear after remote-character readiness
and manifest-channel fixes. Native release verification is deferred with the
combined release. Manual device checks are not claimed.

## Backend verification

Scoped backend commit `430a289` is on `release/trail-preview-21`, based on the
previous release and excluding another session's unrelated paged-odds changes.
Its isolated real HTTP run passed 30/30 with zero skips on local
`steps-tracker-integration_test`. The implementation checkout's explicit-test-DB
unit run passed 3399/3399. Preview adds 2–4 bounded SELECTs by structural
inspection; mine projection adds none. Evidence:
`docs/artifacts/trail-mine-accessory-preview/backend-verification.json`.

Backend production deployment remains pending and must precede the eventual
carrying app release. No schema changes or migration are needed. Neither current
production backend nor the existing App Review submission was modified.

## Validation limits

No physical-device UI pass or new signed iOS/Android build is claimed. Both
platforms use the same changed Dart implementation; paired build verification
belongs to the user's later combined release. The previously documented 36
baseline admin-suite failures were not rerun or changed by this feature.

## Frontend verification

The focused Shop/wardrobe/mine/demo regression run passed 174 tests; its command
also referenced one nonexistent test filename, producing a runner load error
rather than a behavior failure. The corrected relevant tutorial/mine selection
passed 53/53. The final preview widget suite passed 18/18, including remote
cold/warm readiness, compatible fallback, malformed/older responses, read-only
dismissal, session replacement and retry. Final `flutter analyze` is clean. Frontend implementation commit: `2741c1f`.
Counts overlap and are not a unique-test total. Test changes replace only the
explicitly superseded lock/scrim expectations, retaining ownership and tap checks.
