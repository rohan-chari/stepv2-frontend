# Unity Ads via AdMob Mediation

## Summary & user story

As the app owner, I want Unity Ads available as an AdMob mediation bidder on
iOS and Android so the app has an active demand source after ironSource direct
demand sunset, without changing the app's existing AdMob ad-unit and reward
flows.

## Scope / non-goals

In scope: add the official Flutter Unity Ads mediation adapter, preserve the
existing AdMob SDK and IronSource adapter, document the dashboard values the
owner must supply, and verify both native platforms resolve the adapter.

Out of scope: creating Unity Ads or AdMob dashboard projects, creating
placements, entering app IDs/Game IDs, configuring mediation groups, changing
ad-unit IDs, changing reward economics, or migrating to LevelPlay.

## API contract

No backend endpoint or response changes are required. AdMob remains the sole
client ad/SSV integration surface. Existing backend reward claims remain
unchanged.

## Data model / migrations

None.

## Frontend plan

1. Add Google's `gma_mediation_unity: ^1.9.0` Flutter package, the documented
   compatible adapter for the repository's pinned `google_mobile_ads: ^9.0.0`.
2. Keep AdMob SDK initialization in `lib/services/ad_service.dart`; no direct
   Unity initialization is added because AdMob mediation owns adapter setup.
3. Add Unity GDPR/CCPA consent propagation before the first ad request. Until
   the app has a user-facing consent provider, pass explicit conservative
   `false` values and fail closed before AdMob initialization if the native
   Unity privacy calls fail. ATT authorization is not a substitute for
   GDPR/US-state consent.
4. Add no new runtime-required ad-unit config. Until the owner completes dashboard
   setup and supplies the required Unity bidding credentials, the existing
   AdMob demand continues to work and Unity simply contributes no fill.
5. Update iOS and Android dependency resolution together, preserving the
   existing Meta, AppLovin, and IronSource adapters, AdMob initialization,
   ad-unit defines, SKAdNetwork entries, rewarded SSV/custom-data behavior,
   and banner/native/rewarded flows.
6. Add a concise setup handoff documenting the exact per-platform Unity Game
   ID/placement mappings,
   AdMob mediation credentials, privacy settings, and test-mode steps the owner
   must complete outside the codebase.

## Backward compatibility & rollout

This is additive and requires no backend deployment. Existing app versions are
unaffected. Builds without completed dashboard configuration continue using
existing AdMob sources. The owner should complete Unity and AdMob setup before
shipping the build, then verify iOS and Android independently.

No release flag or temporary runtime toggle is permitted.

## Test plan

- Write a source/dependency regression test if the repository's existing test
  conventions support checking required mediation packages.
- Run `flutter pub get`.
- Run `flutter analyze`.
- Run the relevant Flutter tests.
- Confirm the generated iOS Podfile.lock and Android dependency graph contain
  the Unity Ads SDK and AdMob mediation adapter without evicting existing
  adapters; retain the existing iOS Unity SKAdNetwork entry.
- Verify iOS and Android release builds using the repository's build commands,
  in addition to `flutter analyze` and `flutter test`.
- Perform owner-led device tests after dashboard configuration: test banner,
  rewarded, and any interstitial placements on both platforms.

## Acceptance criteria / definition of done

- Unity Ads' official AdMob bidding adapter is declared once in `pubspec.yaml`
  at `^1.9.0`, while `google_mobile_ads` remains on 9.0.0.
- iOS and Android resolve compatible Unity SDK and adapter dependencies.
- Existing IronSource, AdMob, reward, and SSV code is preserved.
- `flutter analyze` and relevant tests pass.
- The owner receives the exact outside-codebase setup checklist, including
  Ad Inspector single-source testing and adapter-response inspection.
- Code review is completed before declaring implementation done.

## Manual setup handoff

The owner must create/configure Unity Ads mediation projects and bidding
placements, copy the exact iOS and Android Game IDs and placement IDs, add
Unity Ads bidding to each applicable AdMob mediation group, configure Unity
Ads in AdMob's GDPR and US-state privacy partner lists, update app-ads.txt,
and enable test mode for the test device. Waterfall is intentionally excluded:
Google's current guide marks Unity waterfall mediation deprecated after
January 31, 2026. Use Ad Inspector to test Unity as a single ad source and
inspect adapter responses. No Unity fill is an acceptable result while AdMob
continues to serve normally.

| Ad format | iOS Game ID | iOS placement ID | Android Game ID | Android placement ID |
| --- | --- | --- | --- | --- |
| Banner | Owner supplies | Owner supplies | Owner supplies | Owner supplies |
| Rewarded | Owner supplies | Owner supplies | Owner supplies | Owner supplies |
| Interstitial (if enabled later) | Owner supplies | Owner supplies | Owner supplies | Owner supplies |

These Unity values are entered in AdMob's mediation bidder configuration; the
app continues using its existing AdMob ad-unit IDs.

## Revision log

- Gap pass 1: clarified that this is AdMob mediation, not LevelPlay, and that
  no backend or reward changes are needed.
- Gap pass 2: added version-compatibility, no-config degradation, both-platform
  verification, privacy/app-ads.txt handoff, and explicit non-goals.
- Architect review: pending approval and implementation review.
- Architect review: required changes incorporated; implementation awaits user
  approval, including the consent-propagation scope.
