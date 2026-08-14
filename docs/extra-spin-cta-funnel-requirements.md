# Extra-spin CTA and funnel requirements

## Summary and user story

Players who have opened today's free daily mystery box and have a rewarded ad
available should immediately understand that watching one short ad earns a
second mystery-box spin. We will make that offer more prominent on Home and
record a privacy-bounded funnel that identifies where people abandon it.

The product owner explicitly approved this scope without an A/B test. This
feature does not change daily-spin odds, reward values, ad caps, or eligibility.

## Scope

1. Record the extra-spin funnel as best-effort activation analytics:
   - `extra_spin_offer_shown`: an eligible offer is visible.
   - `extra_spin_cta_tapped`: the player taps the Home reward ticket or the
     daily-reward CTA.
   - `extra_spin_ad_ready`: a rewarded ad has loaded for an eligible offer.
   - `extra_spin_ad_not_ready`: an eligible offer is rendered but loading did
     not produce a ready ad. The reason is a bounded `result` context value.
   - `extra_spin_ad_completed`: `showAndAwaitReward()` returned true. This is
     client-side progress only, not proof of a reward.
   - `extra_spin_claim_succeeded`: the backend claim returned a reward. The
     existing server-verified `ad_reward_grants` remains the source of truth
     for completed watches and rewards.
2. Replace the eligible Home `EXTRA SPIN` secondary pill with a prominent,
   accessible reward-ticket CTA. It shows a video/play icon, a box/reward icon,
   `BONUS MYSTERY BOX`, and `WATCH A SHORT AD · +1 SPIN`.
3. Make the daily-reward screen's existing primary CTA use the same value-first
   wording. It retains the `CLAIM EXTRA SPIN` state for an already verified
   pending grant and the loading/disabled states.
4. Use one restrained, finite entrance glint/pulse when the Home ticket becomes
   eligible. It must not loop indefinitely, flash rapidly, or interfere with
   accessibility/reduce-motion platform behavior.

## Non-goals

- No experiment flags, cohorts, or A/B test.
- No new ad unit, no change to the reward, odds, daily cap, or SSV rules.
- No client assertion that an ad was rewarded; only the existing signed AdMob
  SSV callback grants the server reward.
- No new personal data or free-form telemetry context.
- No change to non-eligible, unsupported, anonymous, legacy, or old-backend
  experiences.

## Existing contract and API plan

The app already posts queued, authenticated activation telemetry to
`POST /analytics/activation-events` via
`lib/services/activation_analytics_service.dart` and
`lib/services/backend_api_service.dart`. The backend validates a bounded event
name/context allowlist in `src/modules/analytics/routes.js`, then stores events
in `activation_events`.

The backend change is additive only:

- Add the six names above to `ALLOWED_EVENT_NAMES` in the backend and Flutter
  allowlists.
- Add bounded `result` values `load_failed`, `unsupported`, and `dismissed` to
  the existing context allowlist. Existing values remain unchanged.
- Existing request/response shapes do not change:

```json
POST /analytics/activation-events
{ "events": [{ "id": "opaque-id", "onboardingSessionId": "optional-id", "name": "extra_spin_cta_tapped", "context": {"surface":"home"}, "appVersion": "2.3.3", "platform": "ios", "timestamp": "2026-08-13T00:00:00.000Z" }] }
// 202 { "accepted": 1, "inserted": 1 }
```

The UI retains the existing daily-reward status contract: optional
`adExtraSpin` with `available`, `pendingGrant`, and `used`. It continues to
hide/disable safely if this field is absent, malformed, or ads are unsupported.

## Data model and reporting

No migration or new table is needed. `activation_events` already has bounded
event names, optional context JSON, app version, platform, and timestamps.

The admin statistics query should add an `extraSpinFunnel` block for a trailing
30-day ET window. It reports distinct users per stage, grouped by platform and
app version, and server-verified watches/redeemed spins from
`ad_reward_grants` alongside client-side funnel stages. It must label the two
sources clearly: client telemetry can be lost offline; SSV is authoritative.

## Frontend implementation plan

1. Write frontend widget/service tests first.
2. Extend `ActivationAnalyticsService` with the bounded event and context
   allowlists. It must keep the queue capped at 50 and preserve its existing
   best-effort/no-navigation-await semantics.
3. Allow `DailyRewardScreen` to receive the same injected analytics service
   pattern used elsewhere, defaulting to a real service. Record offer shown
   once per screen presentation after a valid eligible status arrives; record
   readiness after `load`; record CTA tap before starting the flow; record
   completion only after `showAndAwaitReward()` returns true; record successful
   claim after the claim endpoint returns.
4. Update `StreakChip`, which owns the Home entry point and preloads the
   controller, to render a dedicated `ExtraSpinRewardTicket` widget instead of
   the generic secondary pill while `_extraSpinAvailable` is true. Pass the
   injected analytics instance into `DailyRewardScreen` so Home and sheet use
   the same queue. Record the ticket's shown/tap stages with `surface: home`.
5. The ticket must work at 320pt width, expose one semantic button label that
   includes the reward and ad, have a minimum 48pt touch target, and avoid
   overflow. Its one-time animation must settle deterministically in tests.
6. Keep iOS and Android in lockstep. Platform ad support stays controlled by
   the existing platform-specific build defines; builds without an ad unit do
   not advertise `ads` and never render this ticket.

## Backward compatibility and rollout

Deploy backend first. A new app against an old backend safely loses only
unknown telemetry event names because the endpoint soft-drops unrecognized
names per event; the reward UI still relies solely on the already-additive
`adExtraSpin` status. An old app against the new backend is unchanged: it sends
no new event names and ignores the new admin statistics fields.

Deploy backend, verify its integration tests on a non-production database, then
ship iOS and Android builds together with their respective rewarded-ad defines.

## Test plan

Backend, tests first:

- Integration test that each new event name/context is accepted, persists with
  its platform/version, and malformed or unapproved context is rejected.
- Admin statistics integration test for the new funnel block, ensuring ET
  windowing, platform/version grouping, and SSV-vs-client labels/counts.
- Run the relevant integration suite only against the dedicated test DB.

Frontend, tests first:

- Service test proving all six names and bounded contexts queue/send, while an
  unknown name/context does not escape.
- Real-screen widget tests for eligible ticket render, semantics, 320pt fit,
  one-time animation, and tap navigation.
- Screen tests covering offer shown, ready, tapped, completed, claim success,
  pending grant, ad not ready/failure, unsupported ads, and missing/malformed
  `adExtraSpin`.
- Existing reward and ad tests remain intact; no assertions are weakened.

## Acceptance criteria / definition of done

- Eligible Home users see the value-first reward ticket and can open the same
  daily-reward flow.
- Ineligible and unsupported users see their current safe UI.
- The six funnel events are accepted by backend and client allowlists; no
  unbounded context or PII is sent.
- Admin reporting can distinguish client funnel stages from verified SSV
  watches and redeemed spins by platform/version.
- Relevant tests pass; `flutter analyze` is clean; backend integration tests
  run only on the test DB; iOS and Android release defines are accounted for.

## Manual UI-placement test plan

1. **Real Home tab:** on an ad-supported build with a user who has claimed the
   free box and has `adExtraSpin.available` or `pendingGrant`, the ticket sits
   in the first quick-actions row, immediately left of SHOP. The generic
   `EXTRA SPIN` pill is absent and not duplicated.
2. **Daily Reward from Home:** tapping the ticket keeps one bottom primary
   action in the card. With a ready ad it uses value-first wording; it is not
   duplicated elsewhere.
3. **Verified pending grant:** the same position says `CLAIM EXTRA SPIN`; no
   watch-ad CTA is also shown.
4. **Loading/not-ready ad:** the disabled/loading CTA remains in the card's
   bottom primary-action position, with no second CTA.
5. **Get Coins → Daily Reward:** the shared Daily Reward screen has the same
   placement and no duplicate/alternate CTA.
6. **Daily-reward reminder notification → Daily Reward:** the shared screen
   has the same eligible CTA after notification routing, even though it does
   not receive Home's preloaded controller.
7. **Tab tutorial Home preview:** the real Home preview uses the same ticket
   position when an explicitly eligible fixture is supplied; its shipped
   unclaimed fixture must not show a misleading ticket.
8. **Home controls:** no ticket appears for unclaimed, already-used, or
   adless/unsupported states.

Unaffected surfaces confirmed: the demo race tutorial, race-detail tutorial
preview, hand-copied tutorial tab bar, and Home SETUP section do not render the
quick-actions row. Risks to address: the tutorial preview service currently
returns unclaimed status only; no current spotlight anchors the ticket; and
StreakChip needs an injected analytics service without changing row order.

## Revision log

- Phase 2 pass 1: separated client-reported `ad_completed` from SSV-verified
  watch/reward so analytics cannot overstate rewarded-ad completion.
- Phase 2 pass 2: constrained all new telemetry to names plus bounded context,
  required once-per-presentation impressions, and explicitly preserved the
  pending-grant/unsupported/old-backend paths.
- UI-placement review: added every real/shared/tutorial surface and fixture
  risk to the manual plan; confirmed no demo-race or race-detail mirror work.
- Product direction update: the initially approved tall, value-forward reward
  ticket proved visually disruptive in staging. The Home control now keeps the
  exact existing StreakChip/PillButton footprint and familiar `EXTRA SPIN`
  copy; its attention treatment is a finite contained shimmer and pop. The
  value-forward wording remains on the Daily Reward sheet CTA.
