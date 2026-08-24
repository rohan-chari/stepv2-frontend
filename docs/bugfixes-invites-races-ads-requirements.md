# Invites, race payouts, team starts, and rewarded-ad corrections

## Summary & user story

As a runner, I should see only one pending-invite card, a neutral `CONTINUE`
action after losing a team race, fair weekly-race coin awards (never below 10
coins), correctly themed reroll controls, and a clearly bounded daily coin-ad
reward. A team race whose invited roster has fully joined should start without
waiting for a scheduled fallback.

## Scope / non-goals

In scope: remove the duplicate visual invite background; change the losing
results action copy; canonicalize weekly challenge payouts and future cohort
capacity; update mystery-box reroll button colors; randomize the server-authoritative
coin-ad reward to 25–50 inclusive and cap it at five successful grants per user
per local day; auto-start full invited team races. Existing race types,
non-weekly payout tables, ad units, and unrelated tournament payouts are out.

## API and data contract

1. Weekly challenge settlement must use an additive/versioned payout policy for
   future seeds, with a minimum awarded amount of 10 coins. Existing finalized
   ledger rows are immutable; no retroactive wallet rewrite is part of this
   change. The server remains authoritative and old clients continue rendering
   the returned integer payout.
2. Future weekly challenge cohort creation/enrollment must enforce a maximum of
   100 members per cohort. Existing cohorts are not split or rewritten.
3. `/daily-reward/status` keeps its existing shape and may continue omitting
   `adCoinReward` for old clients. When present, `adCoinReward.coinAmount` is an
   integer in `[25,50]`, `dailyCap` is `5`, and `remainingToday` is bounded
   `0..5`. The claim/SSV path chooses and persists the amount server-side,
   exactly once; the client never supplies the amount. Old clients safely hide
   the section if the additive block is absent.
4. Full invited team races use the existing join/start endpoint and transaction
   path. When accepted participants equal the invited team roster capacity,
   the server transitions the race to started atomically and idempotently.
   Existing clients need no new required field or parameter.

## Data model / migration

Prefer existing payout/ad-grant fields and immutable snapshots. Add only the
smallest persisted policy/version or grant amount column if current schemas do
not already support it; default old rows to legacy behavior. No destructive
backfill. Verify migrations against a dedicated test database only.

## Frontend plan

- `lib/screens/main_shell.dart` / `lib/widgets/home_invite_overlay.dart`:
  preserve one overlay/card surface and remove the underlying duplicate invite
  decoration; keep accept/decline/error states intact.
- `lib/screens/race_results_summary_screen.dart` and
  `lib/screens/ranked_results_summary_screen.dart`: use `CONTINUE` for losing
  team-race results while preserving the existing winner/non-team behavior.
- `lib/screens/case_opening_screen.dart` and
  `lib/screens/multi_case_opening_screen.dart`: use the app’s shared green /
  yellow / red button treatment for reroll actions, including disabled/loading
  states, without changing eligibility.
- `lib/screens/get_coins_screen.dart`: display server values defensively,
  including missing/null legacy fields; show the bounded reward and remaining
  count and never calculate or mint coins locally.

Both iOS and Android use the same Dart behavior; no platform may be released
alone.

## Backward compatibility & rollout

Deploy backend first, then the app. Old app binaries see the same existing
endpoints and response fields; additive ad metadata is optional. No release
flag is added. Existing weekly settlements and ad grants retain their stored
values; only future policy rows use the corrected rules. Do not start staging
without explicit authorization.

## Tests-first plan

Backend integration tests (dedicated test DB): weekly payout floor and future
100-member cohort cap; daily ad grants remain 25–50 and stop after five;
duplicate/replayed SSV cannot mint twice; full invited team join auto-starts and
partial rosters do not. Frontend widget/integration tests: one invite card with
no background duplicate; losing team results show `CONTINUE` and not `NICE`;
reroll controls use the shared semantic colors; ad status renders bounded
server values and degrades safely when the block is absent.

## Acceptance criteria / definition of done

All requested flows pass their tests, `flutter analyze` and relevant Flutter
tests are clean, backend unit/integration commands are clean against a test DB,
both platform builds are accounted for, version skew is documented, the UI
manual checklist covers Home/race results/case opening/tutorial mirrors, and
code review has found no release blocker.

## Manual UI-placement test plan

- Home pending invite: verify exactly one parchment invite card, no visible
  card/stripe/shadow behind it, and accept/decline/retry remain aligned.
- Real team-race loss: verify the result action reads `CONTINUE`; verify winner
  and non-team result variants retain intended copy.
- Mystery-box single and open-all flows: verify reroll buttons match the
  existing green/yellow/red semantic palette in idle, loading, disabled, and
  error states; check demo/tutorial mirrors do not gain a network ad flow.
- Get Coins: verify reward copy shows 25–50 coins, `5 per day`, decrements after
  each successful claim, and disappears/disabled at zero; verify narrow phones
  and accessibility text.
- Full invited team race: verify the lobby changes to started immediately after
  the final invited participant joins; verify partial and non-invited/public
  races retain their current start behavior.

## Revision log

- Draft pass 1: separated immutable historical payouts from future weekly
  policy, made ad amount server-authoritative, and required atomic idempotent
  team auto-start.
- Draft pass 2: added old-client omission behavior, both-platform coverage,
  tutorial/demo placement checks, and explicit test-database restrictions.

