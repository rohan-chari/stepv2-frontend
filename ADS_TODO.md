# Ads — deferred work

## Interstitial on race-results dismiss (TODO)

Deferred from the ad-placement expansion (banner shipped instead; see
`race_results_summary_screen.dart` — `TODO(ads-interstitial)` at the NICE
button's `pop()`).

When/if we add it:

- Fires **after** `Navigator.pop()` of `RaceResultsSummaryScreen` — never
  before the user has seen their results.
- Frequency-capped: max 1 per app session (in-memory flag in AdService is
  enough; no persistence needed).
- Needs a new `ADMOB_INTERSTITIAL_AD_UNIT_ID` dart-define (create the unit in
  the AdMob console, update `DEPLOYMENT.md` build commands) and an
  `AdService.showInterstitial()` that preloads while the results modal is up
  and no-ops on any load failure.
- Same platform gating as banners (`AdService.bannersEnabled` pattern:
  iOS-only until Android ads are enabled).
