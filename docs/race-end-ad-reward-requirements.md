# Race-end rewarded ad: flat 50-coin bonus

## Summary & user story

When a user opens completed race results, they may watch one rewarded ad for
the eligible completed races in the results batch and receive a flat 50-coin
bonus for each race. A batch of N races credits exactly 50 × N.
The ad no longer doubles (or partially doubles) the race's step/prize payout,
and eligibility is not limited to one completed race per day.

This makes the reward predictable: a race that paid 600 coins still offers
exactly 50 additional coins, and every eligible race has the same offer.

## Scope / non-goals

In scope:

- Replace the existing race-payout-double bonus calculation with a fixed 50
  coins per claimed race while retaining the existing one-ad batch flow.
- Allow every otherwise eligible completed, non-tournament race to offer the
  ad; retain one claim per race and the existing SSV/idempotency protections.
- Keep the existing prepare/claim endpoints and additive response shape where
  practical, so already shipped clients do not crash.
- Update the race-results UI copy to say `+50 COINS` and describe a flat bonus.
- Retain iOS and Android rewarded-ad support and production ad-unit handling.

Out of scope:

- Changing race prize-pool payouts, placement rules, or any other coin source.
- Changing the separate daily coin ad, extra-spin ad, or box-reroll ad.
- A release flag or phased rollout. Permanent behavior is required by the repo
  contract; the backend must remain compatible with older clients during the
  app rollout.

## Current implementation points

- Frontend offer parsing and copy: `lib/models/race_payout_double_offer.dart`
  and `lib/screens/race_results_summary_screen.dart`.
- Frontend API surface: `lib/services/backend_api_service.dart`.
- Backend offer calculation and eligibility: 
  `src/modules/races/services/racePayoutDoublePolicy.js` and
  `src/modules/races/commands/createRacePayoutDoubleOffer.js`.
- Backend claim and SSV crediting: `src/modules/races/commands/claimRacePayoutDouble.js`
  and `src/modules/economy/commands/grantAdReward.js`.
- Backend route contract: `src/modules/races/routes.js`.

## API contract

Keep the existing authenticated endpoints and request fields. The exact
registered routes are:

- `POST /races/results/double-payout/offer`: preserve the current request
  fields and encoding used by the existing client method.
- `POST /races/results/double-payout/:offerId/claim`: empty body; `offerId` is
  a path parameter.

Document exact status codes and `{error, code}` responses from `routes.js`, and
test these public routes rather than importing internal handlers.

The prepare response remains additive-compatible:

```json
{
  "offerId": "uuid",
  "raceIds": ["uuid"],
  "baseCoins": 600,
  "bonusCoins": 100,
  "maxBonusCoins": 100,
  "rolling24hRemainingBeforeClaim": 100,
  "rewardMode": "flat_50",
  "status": "PENDING"
}
```

`baseCoins` remains the snapshotted race prize for truthful compatibility;
new code no longer uses it to calculate a flat reward. For new flat-mode
offers, `bonusCoins` is 50 × the number of races and additive
`rewardMode: "flat_50"` identifies the semantics. Keep legacy numeric fields
populated for old clients. The claim response continues to return
`awarded`, `alreadyClaimed`, `raceIds`, `baseCoins`, `bonusCoins`, and optional
`coins`, plus the additive reward mode.

The backend must not require new request parameters, remove existing response
fields, or reject old clients solely because they send the existing
`race_payout_double` capability. New clients advertise the additive
`race_payout_flat_50` capability; old backend workers reject that token, which
prevents a mixed worker from claiming a flat offer with legacy math. The new
backend accepts either token. Older clients may still display legacy copy, but
they receive the server-authoritative amount and remain safe. New frontend
code must fail closed for missing or malformed additive fields.

Eligibility errors remain the existing safe errors (`INVALID_REQUEST`,
`PREPARATION_DISABLED` only if the existing operational ad configuration is
absent, `RESULTS_ALREADY_SEEN`, `OFFER_PENDING`, and `OFFER_CHANGED`). The
rolling 24-hour issuance allowance and cohort gating are removed for new
flat-mode offers. Existing per-race uniqueness, batch idempotency, and SSV
verification remain mandatory. Replay returns the same result without a
second credit, and a race cannot occur in two claimed offers.

## Data model / migrations

Add an expand-only `rewardMode` column to the offer model. Existing rows read
as `legacy_double`; new rows write `flat_50`. Keep existing integer columns
non-nullable and populated for old clients. Existing pending legacy offers
must retain their stored bonus through GET, prepare retry, claim, replay, and
reconciliation; new flat offers store an immutable total of 50 × race count.
Claim logic must never recalculate either mode from `baseCoins`. Add a
migration and default-safe reads.

Legacy pending offers created before deployment should remain claimable for
their stored amount, subject to the existing validation, rather than being
silently rewritten. New offers use the flat amount.

## Frontend plan

- Preserve the existing model/class and endpoint method names for mechanical
  compatibility, or rename only with a compatibility alias if useful.
- Display `WATCH AD · +50 COINS` for one race and `WATCH AD · +50 COINS PER
  RACE` for a multi-race batch; show the exact total after success.
- Do not display “double”, “another [payout]”, “partial”, or “qualifying
  race prizes” for new offers.
- Keep loading, ad-not-ready, unearned, verification retry, already-claimed,
  and malformed/missing-field fallback states.
- Render the offer on every eligible completed race returned by the existing
  results queue, including the demo/tutorial paths that render the real
  results screen. No new artwork is required.
- Verify both iOS and Android; the existing rewarded-ad unit defines remain
  the production configuration.

## Backward compatibility & rollout

Deploy backend first. The backend change is additive at the JSON boundary and
continues accepting old app requests. Existing binaries may use old “double”
copy, but cannot receive more than the server credits and cannot claim a race
twice. Ship the frontend after backend verification; no `testOnly` asset or
release flag is needed.

Because this changes a coin source, the backend deploy must be monitored for
duplicate claims, SSV failures, flat-versus-legacy claims, claims per race,
and unexpected aggregate issuance. Production remains at
exactly two PM2 workers; do not start staging for verification.

## Test plan (tests first)

Backend:

1. Integration-test the exact public routes and errors for race prizes of 0,
   50, 600, and multiple races.
2. Integration-test a batch of N races snapshots and credits exactly 50 × N,
   is idempotent on replay, and cannot claim a race twice.
3. Cover concurrent prepare/claim, duplicate/foreign SSV callbacks, missing ad
   configuration, the operational issuance brake, results-seen forfeiture,
   Postgres-only settlement with `REDIS_URL` unset, and legacy pending offers.
4. Test old app → new backend and new app → old backend payload behavior.
5. Run backend unit tests and the dedicated integration suite against the test
   database only.

Frontend:

1. Pump the real results screen with a 600-coin race and assert `+50 COINS`
   and flat-bonus copy.
2. Assert two eligible races in the same day offer 50 per race and the final
   credited total is 100.
3. Assert malformed/missing server reward fields hide the panel safely.
4. Assert ad failure and verification retry leave the balance unchanged.
5. Run analyzer and relevant Flutter integration/widget tests.

## Acceptance criteria / definition of done

- Every newly prepared eligible race has a server-authoritative bonus of 50;
  a batch total is 50 × race count.
- No daily one-race or rolling bonus cap remains for new flat-mode offers.
- A user can claim at most once per eligible race, with SSV and idempotency
  protections intact.
- Results UI consistently communicates a flat 50-coin reward on both platforms.
- Existing clients remain compatible with the backend response and claim path.
- Tests are written first and pass; `flutter analyze` is clean; backend tests
  pass; both platforms are accounted for; manual UI checklist and code review
  are complete.

## Manual UI-placement test plan

- Complete two races on the same day; open the results popup and confirm both
  eligible races expose the flat `+50 COINS` offer.
- Confirm a race paying 600 coins shows a separate 50-coin ad bonus and never
  says “double”.
- Watch an ad on iOS and Android production-configured builds; confirm the
  balance increases by exactly 50 and the offer changes to earned state.
- Dismiss/reopen results after an interrupted ad; confirm recovery does not
  duplicate the credit.
- Exercise the demo race tutorial and tab tutorial results surfaces, plus the
  normal race-results popup, confirming copy and placement are consistent.
- Verify malformed/legacy backend payloads hide or safely degrade the panel.

## Revision log

- Initial draft: identified the existing payout-double endpoint as the
  compatibility boundary and separated the new flat ad reward from race prize
  payouts.
- Gap pass 1: added legacy pending-offer handling, no-new-params contract,
  same-day multi-race coverage, and test-database restrictions.
- Gap pass 2: added explicit old-client behavior, iOS/Android verification,
  tutorial mirrors, and operational monitoring requirements.
- Architect review required changes: corrected exact route semantics, defined
  batch total 50 × N, added low/zero-prize handling, legacy immutability,
  reward-mode storage, migration, and mixed-version tests.
- Economy review: pending.
