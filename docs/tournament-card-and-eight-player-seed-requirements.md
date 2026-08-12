# Tournament card parity and 8-player featured seed — requirements

**Repos:** `stepv2-frontend` and `stepv2-backend`
**Status:** Draft — approved for implementation
**Date:** 2026-08-12

## Summary and user story

Bring a user's tournament card in the Races tab into the same visual language as the race cards: rounded parchment card, elevated dark-green shadow, capybara identity, clear time/status hierarchy, placement pill, inventory strip when a matchup is live, and a right chevron. It must remain recognisably a tournament through its round/status marker.

Add a second, app-funded featured tournament seed with an eight-player bracket now that the existing four-player bracket reliably fills. The bracket uses the already-shipped single-elimination tournament engine, is free to enter, starts immediately when full, and mints one champion prize.

> As an active racer, I can recognise a tournament as one of my live game cards at a glance, and can join a longer, higher-stakes eight-player featured bracket without changing how tournaments work.

## Scope

### In scope

- Restyle the personal tournament rows for ACTIVE, PENDING, and COMPLETED states in the Races tab only.
- Preserve navigation to tournament detail and all existing status / placement / countdown semantics.
- Create one additional `TournamentSeed` DB row for an eight-player featured tournament.
- Let the existing 60-second seeded-tournament renewal worker mint exactly one open lobby for the new seed and start it when its eighth participant joins.
- Make the seed discoverable anywhere existing featured tournament summaries are shown, including Public Races and home suggestions, using the current generic payload.

### Non-goals

- No changes to the bracket engine, pairing/seeding, client-feature token, or old-client listing behaviour. The only API addition is the optional, characters-gated `myIdentity` summary on a tournament list item (§API contract).
- No changes to user-created 4/8/16-player tournaments.
- A player may be alive in one featured tournament per seed. The existing per-seed `ALREADY_IN_FEATURED` guard remains unchanged: Tourneys and Weekly Showdown may run concurrently for the same player, but duplicate live entries into either individual seed remain forbidden (product decision, 2026-08-12).
- No new artwork assets, animations, or changes to the tournament detail bracket board.

## Current-state evidence

- Personal rows are created by `_buildTournamentRow` in `lib/screens/tabs/races_tab.dart:1097`; it is a flat `Material` stripe and does not use the race-card outer geometry.
- Ordinary race cards are created by `_buildRaceRow` in the same file and establish the visual reference seen in the supplied screen.
- `TournamentGameCard` already gives discovery cards a different polished shared treatment (`lib/widgets/tournament_game_card.dart:17`); this change deliberately targets the personal-list card only.
- The backend accepts `4`, `8`, and `16` bracket sizes (`src/modules/tournaments/constants/tournaments.js`), and `TournamentSeed.bracketSize` is generic (`prisma/schema.prisma`). The renewal worker derives round count and capacity from that seed, so an 8-player row is data-only.
- The initial migration currently contains only Daily Dash, a 4-player / 1-day / 150-coin seed (`prisma/migrations/20260716150000_add_tournaments/migration.sql`).

## UI design and frontend plan

Design direction: retain the app's tactile arcade-race language rather than introducing a separate tournament panel. A tournament is a race season card: its capybara is the player's equipped identity, while a compact gold outlined round plaque says what stage they are in.

1. Refactor the common visual primitives currently private to `RacesTab` only as far as necessary; do not duplicate capybara, inventory, placement, or chevron rendering.
2. Replace the flat stripe returned by `_buildTournamentRow` with the same outer card geometry used by `_buildRaceRow`: parchment surface, rounded outer corners, dark-green bottom shadow/border, full-width spacing between cards, and an `InkWell` tap target.
3. Layout:
   - leading: the viewer's capybara/equipped accessories from an additive participant/identity summary; if absent, retain the existing neutral fallback without crashing;
   - centre: name, countdown or lobby/result line, then the four-slot live-match inventory rail where applicable;
   - trailing: existing placement pill if available, `CHAMPION` / `ALIVE` / `LOBBY` / `OUT` status, prize coin row, and right chevron;
   - top-line: retain an all-caps round plaque (`BRACKET`, `QUARTERFINALS`, `SEMIFINALS`, `FINAL`) but use the shared chip treatment.
4. Keep the summary parser defensive. Missing identity/accessory/current-match/placement fields must render the fallback portions of the card, never use an unchecked cast or non-null assertion.
5. Tournament invitations are out of scope. Preserve their existing modal/decision flow and compact accept/decline presentation; the supplied issue concerns a user's personal tournament row, not an invite.
6. Add widget tests first for outer-card parity keys, title/time/status/placement/chevron visibility, live inventory, missing optional fields, and tap navigation. Existing tournament list tests remain protected.

## 8-player seed: proposed contract and data plan

## API contract

`GET /races` retains its optional `tournaments` array. Each `tournaments[]` summary gains an additive, optional `myIdentity` only when the requesting client advertises `characters`:

```json
{"myIdentity":{"displayName":"Trail Walker","animal":"CAPYBARA","equippedAccessories":[{"slot":"HAT","assetId":"..."}]}}
```

All of `myIdentity`, `displayName`, `animal`, and `equippedAccessories` may be absent or null. The app shows a neutral identity fallback. The backend resolves the requesting user's identity once per list response, then attaches it to the summaries—never one query per tournament. Clients without `characters`, old app binaries, and no-token requests keep their present JSON shapes.

Existing `GET /tournaments/public`, home suggestions, and tournament detail serialization already include generic `seedKind`, `bracketSize`, duration, filled count, and prize data; older clients neither call them nor advertise the tournaments feature token.

Add one additive Prisma migration that inserts an active `TournamentSeed` row with a new stable ID and kind. The exact product values are still open (see below); proposed defaults for review are:

| Field | Proposal |
| --- | --- |
| stable ID / kind | `seed-tournament-weekly-showdown` / `WEEKLY_SHOWDOWN` |
| display name | `8 Racer Tourney` |
| bracket size | `8` |
| matchup duration | `2 days` (the current backend clamps 1-day tournament matchups to 2 days; three rounds normally take about six days) |
| powerups | on (product decision, 2026-08-12) |
| entry | free |
| champion prize | `300` coins — exactly 2x 4 Racer Tourney's current 150-coin prize (product decision, 2026-08-12). Equal-skill EV is 37.5 coins/entrant, equal to 4 Racer Tourney; a dual winner receives both independent prizes (450 total). |
| active | `false` at migration; activate only after the carrying app build has rolled out, using the existing seed control |

The migration is additive and insert-only. It must be idempotent across already-provisioned environments (`ON CONFLICT`/equivalent against stable ID), and renames the existing seed's display name to `4 Racer Tourney` without changing its stable ID/kind. It inserts the new seed as `8 Racer Tourney`. It adds nullable `Tournament.championPrizeCoinsSnapshot`; renewal stamps the seed prize into it at lobby creation, serializer and settlement prefer it, and legacy rows fall back to `TournamentSeed.championPrizeCoins`. A later seed-prize edit therefore cannot alter an in-flight bracket's award.

Preflight upgraded DBs for duplicate PENDING seeded tournaments. Add a Postgres partial unique index enforcing one PENDING tournament per non-null `seed_id`; renewal handles a uniqueness conflict by re-reading the winner. Postgres is the sole authority for seed configuration, lobbies, participants, entry eligibility, prize snapshots, settlement, and the ledger. Redis is not read or written for joins, expiry/advancement, or coin mutation.

## Backward compatibility and rollout

- Existing tournament endpoints and all old race-list payloads remain byte-compatible: no existing field changes and no new required requests.
- An old app lacks the `tournaments` client feature and will not see tournament summaries or matchup races; it remains unaffected by the new DB row.
- A new app against a backend before the migration simply sees the existing seed(s). No frontend dependency on the new seed is introduced.
- Deploy backend migration and service code verification first; there is no required app code for the seed itself. Deploy the card styling in the iOS and Android app together after backend verification.
- A seed can be disabled using its existing `active` field. Disabling cancels only its open lobby and does not interrupt active brackets, per the current renewal-worker semantics. The existing global `tournamentsEnabled` switch remains the immediate rollback for all new tournament entries.

## Featured-entry guard

Retain the existing per-seed guard: a join returns `409 ALREADY_IN_FEATURED` only when the player is ACCEPTED, `eliminatedInRound IS NULL`, and PENDING/ACTIVE in a tournament with the **same** `seedId`. They may join 8 Racer Tourney while alive in 4 Racer Tourney, and vice versa; eliminated players remain immediately eligible for the next lobby of that same seed.

Public Races and Home discovery keep the existing per-seed joinability predicate. Therefore Home Suggested Races may suggest 8 Racer Tourney to a player alive in 4 Racer Tourney, because it is genuinely joinable; it must still omit another 4 Racer Tourney lobby for that player.

## Test plan (tests written before implementation)

Frontend:

- Widget-test the personal tournament card against active, pending, completed, champion, eliminated, and minimal/missing-field payloads.
- Confirm the card opens tournament detail and the live inventory rail is present only for a live matchup.
- Verify both light and dark app themes, narrow phone widths, long names, and the existing demo/tutorial host surfaces that render the Races tab.
- Add ACTIVE, PENDING, and COMPLETED identity-bearing tournament fixtures to `tutorialPreviewRacesData()` plus a missing-identity fallback. Verify `tutorial_real_screens.dart` continues to host the real RacesTab and its `races.card` / `races.box` spotlights remain on the first ordinary race. `demo_race_api_service.dart`, `demo_race_engine.dart`, and `demo_auth_service` do not render this row and need no change.

Backend:

- Migration test: fresh and upgraded test DBs contain Tourneys unchanged plus one inactive 8-player seed; preflight catches duplicate PENDING seeded lobbies before the partial unique index.
- Integration test: concurrent renewals create exactly one open 8-player lobby; eight joins start it; three rounds complete; the snapshotted prize mints exactly once even after a seed-prize edit.
- Regression test: the existing Tourneys seed continues to create/fill/renew independently; a player alive in either featured seed gets `ALREADY_IN_FEATURED` when joining the other, and an eliminated player can join immediately.
- Real-HTTP join regression: a player alive in 4 Racer Tourney can join 8 Racer Tourney; a second 4 Racer Tourney join returns `409 ALREADY_IN_FEATURED`; an eliminated player can rejoin that seed immediately.
- Home suggestion regression: while alive in 4 Racer Tourney, 8 Racer Tourney remains eligible and may appear in `GET /home/suggested-races`; a second 4 Racer Tourney lobby is absent because it is not joinable.
- Regression test: no-token old-client race-list shapes are unchanged.

## Acceptance criteria

- In the Races tab, a tournament card reads as the same family as the surrounding race cards in the supplied screenshot: rounded parchment card, dark-green depth, leading character, hierarchy, status/placement, and chevron.
- It remains safely renderable from partial/older tournament summaries.
- An 8-player featured lobby appears, fills, runs three two-day knockout rounds, and pays exactly one configured prize to the champion.
- Tourneys, user-created tournaments, and older clients remain unaffected.
- `flutter analyze` is clean; relevant frontend widget tests and backend integration tests pass against a confirmed non-production test DB; iOS and Android are accounted for.

## Revision log

- Phase 1 (2026-08-12): drafted from the existing frontend row implementation and the backend's generic seed/renewal architecture. Identified that the seed addition is configuration/migration work, not a new API or bracket-engine feature. Added initial proposed 8-player economics only as a decision for review; it is not approved or committed.
- Phase 2 pass 1 (2026-08-12): constrained the UI change to the personal Races-tab rows, retained invite-strip uncertainty rather than silently widening scope, and explicitly guarded partial payload reads and old-client byte compatibility.
- Phase 2 pass 2 (2026-08-12): added a cross-seed entry rule, migration idempotence, seed kill-switch semantics, and explicit verification that the 8-player bracket completes three rounds and mints once.
- Phase 3 interview fold-in (2026-08-12): product locked powerups ON for the eight-player seed and clarified that invite UI is not part of this card migration.
- Economy review (2026-08-12): set the recommended prize at 400 (50 EV/entrant); discovered live drift that the existing seed is named Tourneys, has powerups ON, and that 1-day tournament rounds are currently clamped to 2 days. Added staged activation and surfaced cross-seed concurrent entry as a required product decision before architect review.
- Phase 3b interview fold-in (2026-08-12): product initially approved, then superseded, a global featured-tournament alive guard. Final decision: retain the existing per-seed `ALREADY_IN_FEATURED` predicate so Tourneys and Weekly Showdown can be joined concurrently.
- Architect review (2026-08-12): added the required bounded characters-gated `myIdentity` contract; immutable prize snapshot; partial unique seeded-lobby index with duplicate preflight; Postgres-only storage placement; and explicit tutorial/demo mirror work. The suggested global advisory-lock/discovery change was deliberately removed after product selected per-seed concurrent entry. Two fresh gap passes after those contract changes found no further open requirement.
- Phase 3c interview fold-in (2026-08-12): renamed the existing featured display name to `4 Racer Tourney` and the new eight-player seed to `8 Racer Tourney`; stable seed IDs/kinds are unchanged. The earlier `400` prize recommendation is superseded by the concurrent-entry economy finding and remains unresolved pending product choice.
- Phase 3d interview fold-in + economy review (2026-08-12): product set the 8 Racer Tourney prize at exactly double 4 Racer Tourney's live 150-coin payout: 300 coins. Cross-seed entry and independent payouts are intentional. Verdict: SOUND WITH CHANGES—retain the immutable lobby prize snapshot and monitor 8-seed completion/mints, champion overlap, repeated cohorts, and any mint not equal to 300.

## Manual UI-placement test plan

**Elements under test:** Personal ACTIVE, PENDING, and COMPLETED tournament rows move from a flat full-width stripe to the same rounded parchment, dark-green-shadow card family as personal race cards, with leading capybara identity, centre hierarchy/live inventory rail, trailing placement/status/prize, and chevron.

1. **Real Races tab — ACTIVE:** With a live tournament matchup, verify a separated rounded parchment card with green depth; leading capybara; centred name/round/countdown/four-slot inventory; trailing placement, ALIVE, prize and chevron; no old stripe or duplicate.
2. **Real Races tab — PENDING:** With an accepted lobby, verify the same card lane, identity, BRACKET plaque, lobby copy, LOBBY/prize/chevron; no live inventory and no old stripe.
3. **Real Races tab — COMPLETED:** Check champion and eliminated results. Verify the rounded card, identity, result hierarchy, placement if supplied, CHAMPION or OUT, prize, chevron, and no stripe.
4. **Narrow mixed list:** On a narrow phone with races and a tournament, verify all content stays inside the shared full-width card lane without wrapping into an extra row or showing a flat separator.
5. **Tutorial Races-tab preview:** Settings → View Tutorial → Races beats. Verify the added fixtures use the same placement, have no duplicates, and the existing first-race/mystery-box spotlights still ring the ordinary race and its boxes.

**Unaffected surfaces:** Tournament invitation modal/accept-decline ticket; Public Races `TournamentGameCard`; Home suggestions; tournament detail bracket board; demo race tutorial (does not instantiate RacesTab); and tab-bar placement. The implementation must nevertheless add tutorial fixtures, preserve spotlight anchors, test missing identity fallback, and confine the inventory rail to live matchups.
