# Races-tab capacity projection v2: frontend parity

This note locks the frontend side of backend load profile
`authenticated-races-tab-reveal-v1@2.0.0` and expected projection marker
`races-tab-open-projection-v2`. It does not change the app or introduce a
test-only screen model. The load fixture uses the same existing API shapes that
the production `MainShell` passes into the real `RacesTab` on iOS and Android.

## Request fan-out

One reveal performs the existing production sequence:

1. `GET /races?view=compact-v1` is awaited as the core refresh.
2. `GET /races/discovery-summary` starts after core settles and updates the
   PUBLIC count without blocking the core refresh.
3. `GET /friends?view=summary-v1` starts beside discovery only when the loaded
   friend list is empty or older than 60 seconds. The normal profile fixes the
   reveal after the repository's one-second reuse window and before the
   60-second freshness boundary.

The production-widget sequencing and conditional friends branch are locked by
`test/main_shell_nav_order_test.dart`. Exact methods, paths, query parameters,
and the three response contract markers are locked by
`test/backend_api_service_sync_v2_test.dart`.

## Projection-to-render mapping

| v2 projection family | Existing frontend consumer | Visible behavior under test |
| --- | --- | --- |
| `ordinary.active/pending/completed/invited` | `RacesTab` bucket getters and state pills | active, waiting, completed, and pinned invite rows plus per-state counts |
| ordinary `name`, `status`, `myStatus`, `isCreator`, `participantCount`, `creatorDisplayValue`, `maxDurationDays`, and time fields | `RacesTab._buildRaceRow` | title, ACTIVE/SETUP/INVITE state, runner/creator copy, duration, and live countdown |
| ordinary favorite state/order and classic/team kind | `RacesTab._pinnedEntries`, `_entriesFor`, and `TeamRace` | PINNED classic/team groups, pin state, and stable order |
| ordinary placement `privacyActive`, `displayValue`, canonical `value`, and `hidden` | `RacesTab._buildRaceRow` | privacy-safe ordinal or `??? PLACE`; canonical placement is not painted while privacy projection is active |
| ordinary team size, caller team, names, totals, total timestamp, and winner | `TeamRace` readers used by `RacesTab` | format chip, named scoreline, persisted totals, and `as of` label |
| `ordinaryInventoryByRace` | `RacesTab._buildInventoryRow` | held powerup, unopened mystery box, and queued box slots |
| `ordinaryEffectsByRace` | `RacesTab._buildEffectCluster` | positive and negative effect plates beside inventory |
| `tournaments.invited/pending/active/completed` | `Tournament.personalListState` and `RacesTab` | action-first invite, lobby/between-rounds, live-match, eliminated, champion, and completed-nonchampion placement |
| tournament favorite state/order | `RacesTab._pinnedEntries` | PINNED tournament group and pin state |
| tournament bracket, accepted count, round, prize, identity, animal, and accessories | `Tournament` readers used by `RacesTab._buildTournamentRow` | lobby fill, round label, prize, and caller avatar |
| `tournamentMatchByTournament` placement, end time, round, inventory, and queue | `Tournament.match*` readers used by `RacesTab` | matchup ordinal/hidden rank, countdown, held item, mystery box, and queued box |
| `discovery.publicRaceCount` | `MainShell._refreshRacesDiscovery` → `RacesTab.publicRacesCount` | count in the PUBLIC action |
| `friends.shouldRequest/expectedCount/expectedContract` | `MainShell._maybeRefreshFriends` and shared repository | conditional background branch; friends are context for later detail navigation, not extra Races-tab rows |

`test/races_tab_capacity_projection_v2_parity_test.dart` pumps the real widget
with one compact response spanning the 28 required coverage variants and
asserts these visible branches across ACTIVE, PENDING/invites, and COMPLETED.
It also covers missing additive v2 fields so an older backend continues to
degrade without a crash.

## Explicit boundaries

- Cancelled tournaments are not a 29th fixture variant. The current
  `GET /races?view=compact-v1` contract filters them out, so this workload
  cannot materialize that dormant defensive UI branch without changing the
  application API. Results must not claim cancelled-tournament coverage.
- Featured/public race cards and featured tournaments do not render on the
  personal Races tab. Discovery contributes only the PUBLIC count here.
- Race detail, navigation after a row tap, joins, race creation, review prompts,
  and payout-double flows are outside a tab-reveal measurement.
- Rarity remains response-content evidence for held inventory, but the Races
  row selects its icon by powerup type; rarity does not create a separate
  visible branch.

## Platform and compatibility accounting

The Races tab, request service, and these widget tests are shared Dart code, so
the parity lock applies equally to iOS and Android. No dependency, native file,
build-time define, endpoint, response model, or UI behavior changes as part of
this verification. All v2 fields remain additive and existing defensive
fallbacks remain intact for older backend versions.
