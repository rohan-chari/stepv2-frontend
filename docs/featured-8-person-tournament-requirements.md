# Featured 8-Person Tournament Requirements

## Summary & user story

As a Bara user, I want an 8-person featured tournament available alongside the
existing 4-person featured tournament, so I can join a larger free bracket. When
the 8-person lobby reaches eight accepted participants, it must start and a
replacement open 8-person lobby must be created automatically.

## Scope / non-goals

In scope:

- Activate and configure the existing canonical 8-person `TournamentSeed` row
  (`seed-tournament-weekly-showdown` / `WEEKLY_SHOWDOWN`); do not create a
  duplicate seed.
- Reconcile that seed through the existing tournament seed renewal job.
- Expose the seeded lobby through the existing featured tournament discovery
  response and existing frontend featured row.
- Add integration coverage proving initial seeding and full-lobby replacement.

Out of scope:

- New frontend widgets, endpoints, bracket math, or tournament states.
- Changes to the existing 4-person seed.
- Changes to buy-in rules, payout formulas, scoring, or round advancement.
- A release flag or staged rollout control.

## Current implementation evidence

- `stepv2-backend/prisma/schema.prisma` defines `TournamentSeed` with
  `bracketSize`, duration, powerups, prize, and `active`.
- `stepv2-backend/src/modules/tournaments/jobs/tournamentSeedRenewal.js`
  processes every active seed, promotes a full pending lobby, and then creates
  exactly one open pending lobby for that seed. The database partial unique
  index is the concurrency backstop.
- The launch migration seeds `DAILY_DASH` with bracket size 4.
- `stepv2-backend/src/modules/home/queries/getSuggestedRaces.js` adapts public
  seeded tournaments into the existing discovery payload.
- `lib/screens/main_shell.dart` already merges `featuredTournaments` into the
  featured races row and safely treats a missing `featured` field as empty.
- `lib/models/home_race_suggestion.dart` already accepts tournament cards and
  defensively parses optional fields.

## Product decisions

The new seed is proposed as:

| Field | Value |
|---|---|
| `id` | `seed-tournament-weekly-showdown` (existing canonical row) |
| `kind` | `WEEKLY_SHOWDOWN` (existing stable kind) |
| `name` | `8 Racer Tourney` |
| `bracketSize` | `8` |
| `matchupDurationDays` | `2` |
| `powerupsEnabled` | `false` |
| `championPrizeCoins` | `150` |
| `active` | `true` |

The prize and duration are seed configuration, not a new economy or scoring
rule. They should remain consistent between migration and fresh-install seed
data. If the product owner wants different copy, duration, or prize, change
these values before approval; no code design depends on the particular values.

## API contract

No endpoint shape changes.

Existing compatible behavior remains:

- Existing clients continue receiving the existing discovery response. Clients
  that do not understand tournament cards ignore the additive tournament data;
  clients that do understand tournaments render the new card using the existing
  `bracketSize` field.
- The existing `GET /home/suggested-races` / tournament discovery payload is
  reused. The new card is returned only when the existing tournament capability
  negotiation permits it.
- The existing join and detail endpoints are unchanged. The backend validates
  the seeded row's bracket size through existing tournament logic.
- Missing or older `featured` data continues to degrade to the existing empty
  state in the Flutter client.

## Data model / migrations

Add a forward-only migration updating the existing canonical 8-person
`TournamentSeed` by stable `id` (including `active=true`). Do not insert a
second 8-person seed or edit an already-applied migration.

Update `prisma/seed.js` so a fresh database and a migrated database agree on the
canonical row. Preserve unrelated/admin-tuned values according to the
repository's normal seed policy, while this approved feature owns the canonical
row's name, size, duration, powerup setting, prize, and active state.

Do not backfill tournaments. The renewal job creates the first open lobby on
its next run, and a full lobby is promoted before replacement creation.

## Backend implementation path

1. Write integration tests first in the backend tournament integration suite:
   run the renewal job against the test database, assert one pending 8-person
   tournament with zero participants, fill it through the public join path,
   run renewal, and assert the original is no longer pending and exactly one
   different pending 8-person lobby exists.
2. Add the migration and fresh-seed entry.
3. Reuse `tournamentSeedRenewal.js`; do not add a second scheduler or special
   8-person branch.
4. Verify concurrent renewal remains idempotent and never creates two pending
   lobbies for the same seed.

## Frontend plan

No Dart production code is expected. Verify both iOS and Android behavior via
the shared Flutter code:

- the featured row renders both existing and new seeded tournament cards;
- tapping the new card opens the existing tournament detail screen;
- the card shows 8 racers from the existing `bracketSize` field;
- older backend responses with no new seed remain unchanged;
- null/missing optional tournament fields do not crash discovery or detail.

## Backward compatibility & rollout

The change is additive and permanent; no feature flag is permitted. Deploy the
backend migration and code first, then validate discovery and joining, then
ship the app only if a frontend change becomes necessary. Old app versions that
already support tournaments either show the new card or ignore it through their
existing capability behavior. Old app versions without tournament support are
unchanged. The backend must not remove or repurpose any existing field.

Do not start staging merely for verification. Integration tests must use the
dedicated test database, never production.

## Test plan

- Backend integration: first renewal creates the 8-person lobby.
- Backend integration: joining eight users reaches exactly capacity and starts
  the tournament through the existing full-join path.
- Backend integration: subsequent renewal creates exactly one replacement open
  lobby for the same seed.
- Backend integration: repeated/concurrent renewal does not duplicate the open
  lobby.
- Backend compatibility: existing 4-person featured seed behavior remains
  unchanged and discovery returns both seeded tournament types.
- Frontend: run the existing discovery/widget suites; add a widget test only if
  current fixtures cannot prove the 8-person card is rendered.
- `flutter analyze`, relevant Flutter tests, and backend unit/integration tests.

## Acceptance criteria / definition of done

- A fresh or migrated database has one active 8-person featured seed.
- The renewal job creates one open 8-person lobby per active seed.
- When that lobby fills, it starts and the next renewal creates one new open
  8-person lobby without duplicating it.
- The existing 4-person featured tournament still behaves identically.
- Existing clients remain compatible with the unchanged API shapes.
- Required tests pass in a test database; Flutter analyze is clean.
- Architect review and post-implementation code review are complete.

## Revision log

- Gap pass 1: made the replacement lifecycle explicit (full lobby is promoted
  before a new lobby is minted), required test-database integration coverage,
  and prohibited a new scheduler/flag.
- Gap pass 2: added migration-vs-`prisma/seed.js` parity, concurrency/idempotency
  coverage, old-client behavior, and explicit iOS/Android verification.
- Architect review: completed before approval; implementation must preserve the
  existing per-seed renewal/replacement and old-client compatibility paths.

## Manual UI-placement test plan

No new or moved UI is planned. The existing featured row consumes the additive
seeded tournament card. Verify the existing surfaces during acceptance:

1. Open the Races tab on iOS and Android with an active 8-person seeded lobby;
   confirm the card appears alongside the existing featured content.
2. Confirm the card reads as an 8-person bracket and opens the existing detail
   screen.
3. Fill the lobby, refresh, and confirm the old card transitions according to
   existing tournament behavior while a replacement 8-person card appears.
4. Verify an older/feature-disabled client still shows its prior featured
   content without a crash.
