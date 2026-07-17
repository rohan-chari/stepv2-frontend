# Tournament Mode — Requirements & Implementation Spec

**Repos:** `stepv2-frontend` (Flutter, iOS "Bara" + Android) and `stepv2-backend` (Node/Express + Prisma/Postgres, `steptracker-api.org`).
**Date:** 2026-07-16 · **Author:** PM/BA pass (Claude) for Rohan.
**Build model:** contract-first, then two Opus agents (backend + frontend) in parallel, tests-first. Backend owns the API contract and old-client compat; frontend consumes the contract verbatim and ships iOS + Android in lockstep.

---

## 1. Summary & user story

A **Tournament** is a single-elimination bracket of **1v1, winner-take-all step matchups**. The creator picks a bracket size (4, 8, or 16 players) and a **matchup duration** (1, 2, or 3 days). Once the bracket is full, the creator starts it: players are randomly paired into round-1 matchups, each matchup runs as a normal head-to-head step race for the chosen duration, winners advance round by round, and the last capybara standing takes the **entire pot** of buy-ins. Alongside user-created brackets, **featured tournaments** (system-seeded, always free, minted champion prize) keep one standing open bracket per template and start automatically the moment they fill (§6.10).

> *As a competitive user, I want to enter a multi-day bracket against friends (or the public) where each round is a fresh 1v1 sprint, so that winning feels like a playoff run and the coin prize is meaningful.*

Why this shape: every matchup is an ordinary 2-person, time-based, WINNER_TAKES_ALL race — the app's existing race engine (step attribution, live leaderboards, settlement, chat, overtake nudges) runs each matchup unchanged. The only genuinely new machinery is the **bracket layer**: a `Tournament` entity, round advancement, and a tournament-level pot.

## 2. Scope / non-goals

**In scope (v1):**
- Single-elimination brackets of exactly **4, 8, or 16** players (2/3/4 rounds).
- Matchup duration **1, 2, or 3 days**, uniform for every round, fixed at creation.
- **Random seeding** at start.
- Optional **buy-in** on a per-size ladder (0, or 10–{100/100/62} for 4/8/16-brackets — pot caps 400/800/992); champion takes 100% of the pot.
- **Powerups as a creator toggle** (matchups inherit; per-matchup scoping is automatic since each matchup is its own race).
- **Featured (seeded) tournaments:** auto-generated, always free, pop-when-full, minted champion prize; launch seed "Daily Dash" (§6.10).
- Invite friends, share link, and optional **public** listing to fill the bracket.
- Creator **manual start**, allowed only when the bracket is exactly full.
- Bracket lobby / live bracket / champion screens on the frontend; each matchup opens the existing race-detail screen.
- Forfeit/leave semantics, cancel-with-refund while pending, tournament pushes, old-client invisibility.

**Non-goals (v1) — explicitly out:**
- Byes / partial brackets / odd sizes; double elimination; best-of-N matchups.
- Creator-controlled or skill-based seeding (always random).
- Scheduled auto-start (`scheduledStartAt`) for tournaments.
- Editing a tournament after creation (name/buy-in/size/powerups are fixed; cancel & recreate instead).
- Re-buys, losers' bracket, third-place match, or any non-champion payout.
- Tournament-level chat (each matchup keeps the existing per-race chat between its 2 players).
- Tournament tickets on the home-tab ACTIVE_RACES card (v2 candidate).
- Featured tournaments with buy-ins, midnight-anchored featured starts, auto-enroll (`autoJoinFeaturedRaces`-style) into featured tournaments, and more than one launch seed — all v2 candidates.

## 3. Decisions locked (PM interview, 2026-07-16)

| # | Decision |
|---|----------|
| D1 | **Brackets are 4, 8, or 16 players, powers of two only, and must be completely full to start.** No byes, no partial brackets. |
| D2 | **Matchup duration is 1, 2, or 3 days**, chosen at creation, identical for every round. |
| D3 | **Exact step tie → the earlier tournament joiner (`TournamentParticipant.joinedAt`) advances.** Deterministic, surfaced honestly in UI copy. |
| D4 | **Buy-in windows scale with bracket size** (revised 2026-07-16 — a 4-bracket must not pay ~1,000): buy-in is 0 (free) or 10–`TOURNAMENT_BUYIN_MAX[bracketSize]` where the max is **100 / 100 / 62** for 4 / 8 / 16 — pot caps of **400 / 800 / 992**. Max winnings grow with bracket size; only a 16-bracket approaches 1,000. Champion takes the whole pot. |
| D5 | **Powerups are a creator toggle** (same toggle + step-interval controls as regular races); matchup races inherit the setting. Effects are naturally scoped per matchup (each matchup is its own race — no cross-matchup AoE). Fresh powerup slots each round. The bracket view must apply the same display illusions (Stealth etc.) as the race room, or it becomes a stealth-defeating side channel (§6.4). |
| D6 | **Immediate round rollover:** next round starts within ~5–10 min of the previous round fully settling (`raceExpiry` cadence), `endsAt = now + duration`. No rest day. |
| D7 | **Public tournaments: yes** — creator toggle, browsable via `GET /tournaments/public`, surfaced on the existing Public Races screen. |
| D8 | **Eliminated players are bracket spectators:** they keep the live bracket view (near-live totals) until the champion is crowned. **REVISED 2026-07-16: matchup race rooms are now spectatable** — any tournament participant can tap any matchup on the bracket to open its race detail READ-ONLY (chat/powerups/forfeit hidden; leaderboard visible). Backend relaxes the `getRaceDetails`/`getRaceProgress` 403 for tournament races when the viewer is an ACCEPTED participant of that tournament; writes stay participant-only. |
| D9 | **Featured tournaments start pop-when-full:** one standing open bracket per seed template; the join that fills the last slot starts it on the spot (inline, same lock), and the 60s renewal cron immediately seeds a fresh open one (and acts as backup promoter after a crash). |
| D10 | **Featured tournaments are always FREE with a minted champion prize** (system-funded, like seeded-race finish rewards). Real buy-ins are user-tournament-only. |
| D11 | **Launch lineup: one seed — "Daily Dash":** 4-bracket, 1-day matchups, powerups off, free, **150-coin** minted champion prize (~2–3 day event). Seeds are DB rows (migration-inserted, `active`-toggled) — more/bigger ones can be added later without code changes. |
| D13 | **Featured tournaments surface in the races-tab featured row (revised placement, 2026-07-16; filter scope corrected):** an **ALL / RACES / TOURNAMENTS** pill sits ABOVE the featured row and filters the **featured row only** — ALL = featured races + featured (seeded) tournaments mixed, RACES = featured races only, TOURNAMENTS = featured tournaments only (curated/seeded like Daily Dash). The pill does **NOT** filter the user's own races/brackets — those sections (active/invites/setup/done + MY BRACKETS) always render below, unfiltered. Public Races screen keeps its FEATURED tournament cards too (unchanged). No backend change — the client merges `fetchPublicTournaments().featured` into the row; `GET /races/featured` stays byte-identical. |
| D14 | **Tournament view = draggable March Madness bracket (2026-07-16):** the tournament detail screen's body becomes a pannable/zoomable bracket canvas (`InteractiveViewer`) with the app's checkered-green background tiled as the draggable grid the bracket sits on. Rounds progress to a single crowned champion with drawn connector lines; matchup boxes hold two player slots (filled capybara+@name / open / winner / eliminated / TBD). PENDING fills leaf slots by **join order as a client-side preview** (backend still seeds at start — pre-start positions are labeled a preview, no backend/contract change); ACTIVE shows the real bracket with my-matchup highlighted (tap → race detail); COMPLETED crowns the champion (confetti only for the champion viewer). Replaces the static "THE FIELD" grid. Built with the mobile-design + frontend-design skills. **Open question surfaced to Rohan:** whether joining should lock a fixed bracket spot (deterministic join-order seeding, a small backend change to D3) or keep random-seed-at-start with the pre-start bracket as a preview — deferred until he sees the view. |
| D12 | **Featured repeat-entry guard (added 2026-07-16):** a user may not join a seed's open lobby while **still alive** in another non-completed tournament of the same seed (`409 ALREADY_IN_FEATURED`). Eliminated players may hop into the next lobby immediately. Without this, free respawning lobbies + minted prizes + steps-count-in-every-race = an unbounded mint loop (stack concurrent brackets, or 4 colluding accounts popping lobbies on repeat). The guard throttles farming to one live shot at the prize per seed per user. |

## 4. Backward-compat & the #1 rule (frozen old clients)

The prod backend serves every shipped binary at once. Tournament must be **invisible and harmless** to any client that doesn't advertise support.

- **New `X-Client-Features` token: `tournaments`.** The app adds it to `clientFeaturesHeader` (`lib/services/backend_api_service.dart:89-91`). Backend parses it via the existing `resolveClientFeatures` (`src/utils/clientFeatures.js`) and records it stickily (`src/middleware/requireAuth.js:57-70`).
- **Old app + new backend:**
  - All `/tournaments/*` endpoints are new — old clients never call them.
  - **Matchup races are excluded from every existing race listing for ALL clients** (`race.tournamentId != null` is skipped in `getRaces`, `getPublicRaces`, `getFeaturedRaces`, and the home race card) — old clients never see a matchup race at all; new clients reach matchups only through the tournament screen. Mirrors the `race.isTeamRace && !supportsTeamRaces` skips (`src/queries/getRaces.js:66`, `getPublicRaces.js:20`).
  - `GET /races` gains an additive `tournaments` array **only for token clients**; old clients' JSON is byte-identical.
  - New push types (`TOURNAMENT_*`) are safe: old apps show the alert and no-op the deep link (`notification_service.dart:338-339`; backend `notificationHandlers.js:541-542`).
  - All new DB columns are nullable/additive; no existing row changes shape.
- **New app + old/current backend:** deploy order is **backend first** (locked convention). Still, the app reads defensively: missing `tournaments` key → no tournament UI; `POST /tournaments` 404 → generic "can't do that yet" toast.
- **Kill switch:** `AppSetting` key `tournamentsEnabled` (default true), checked at **create and every join/accept path** — same pattern as `teamRacesEnabled` (`createRace.js:131-139`). Start and round advancement are deliberately NOT gated: flipping the switch stops new entries while already-filled brackets finish out and pay their champion.
- **Rollout:** backend deploy (migrate + code) → verify old-client listing shapes unchanged on staging → App Store / Play builds (~1 week phased). No `testOnly` needed beyond the token gate: clients without the token simply never see tournaments.

## 5. Data model / migrations (Prisma — all additive)

```prisma
enum TournamentStatus { PENDING ACTIVE COMPLETED CANCELLED }

model Tournament {
  id                  String   @id @default(uuid())
  creatorId           String?                  // null = seeded/featured (mirrors Race.creatorId)
  seedId              String?                  // links to TournamentSeed for featured brackets
  name                String
  status              TournamentStatus @default(PENDING)
  bracketSize         Int                      // 4 | 8 | 16
  matchupDurationDays Int                      // 1 | 2 | 3
  buyInAmount         Int      @default(0)     // 0, or 10..TOURNAMENT_BUYIN_MAX[bracketSize] = 100/100/62 (D4 ladder)
  potCoins            Int      @default(0)
  powerupsEnabled     Boolean  @default(false)  // creator toggle (D5); matchup races inherit
  powerupStepInterval Int?                      // same semantics/default as races
  isPublic            Boolean  @default(false)
  shareToken          String?  @unique
  timezone            String?                  // creator's IANA zone at creation; "America/New_York" for seeded (matchup races inherit it)
  currentRound        Int      @default(0)     // 0 = not started; 1..totalRounds while active
  totalRounds         Int                      // log2(bracketSize)
  championUserId      String?
  createdAt           DateTime @default(now())
  startedAt           DateTime?
  completedAt         DateTime?

  creator      User? @relation("TournamentCreator", fields: [creatorId], references: [id])
  champion     User? @relation("TournamentChampion", fields: [championUserId], references: [id])
  seed         TournamentSeed? @relation(fields: [seedId], references: [id])
  participants TournamentParticipant[]
  races        Race[]

  @@index([isPublic, status])
  @@index([creatorId, status])
  @@index([seedId, status])
}

model TournamentSeed {
  id                  String   @id            // stable key, e.g. "seed-tournament-daily-dash"
  kind                String   @unique        // e.g. "DAILY_DASH"
  name                String                  // copied verbatim to each minted tournament
  bracketSize         Int
  matchupDurationDays Int
  powerupsEnabled     Boolean  @default(false)
  powerupStepInterval Int?
  championPrizeCoins  Int                     // minted prize (featured are always free, D10); ≤ 1000
  active              Boolean  @default(true) // cron only reconciles active seeds
  createdAt           DateTime @default(now())
  updatedAt           DateTime @updatedAt

  tournaments Tournament[]
}

model TournamentParticipant {
  id                String   @id @default(uuid())
  tournamentId      String
  userId            String
  status            RaceParticipantStatus @default(INVITED)  // reuse INVITED/ACCEPTED/DECLINED
  seed              Int?                   // bracket slot 0..bracketSize-1, assigned at start
  eliminatedInRound Int?                   // null = still alive (or champion)
  buyInAmount       Int      @default(0)
  buyInStatus       RaceBuyInStatus @default(NONE)           // reuse NONE/HELD/COMMITTED/REFUNDED
  buyInVersion      Int      @default(0)                     // increments on every refund; suffixes ledger refIds (§7)
  joinedAt          DateTime @default(now())                 // ACCEPT time (updated on re-accept); the D3 tiebreak key
  createdAt         DateTime @default(now())

  tournament Tournament @relation(fields: [tournamentId], references: [id])
  user       User       @relation(fields: [userId], references: [id])

  @@unique([tournamentId, userId])
  @@index([userId, status])
}
```

**`Race` additions (nullable — old rows/clients unaffected):**
```prisma
  tournamentId          String?
  tournamentRound       Int?      // 1-based
  tournamentMatchIndex  Int?      // 0-based within the round
  tournament            Tournament? @relation(fields: [tournamentId], references: [id])
  @@unique([tournamentId, tournamentRound, tournamentMatchIndex])  // advancement idempotency backstop
  @@index([tournamentId, status])
```

**Matchup race rows are otherwise ordinary races:** `timeBased: true`, `maxDurationDays = matchupDurationDays`, `maxParticipants: 2`, `payoutPreset: WINNER_TAKES_ALL`, `buyInAmount: 0`, `potCoins: 0` (money lives on the Tournament), `isPublic: false`, `powerupsEnabled = tournament.powerupsEnabled` + `powerupStepInterval = tournament.powerupStepInterval` (D5 — fresh powerup slots every round, effects scoped to the matchup automatically), `timezone = tournament.timezone`, `creatorId = tournament.creatorId`, `shareToken: null` (matchups are never share-joinable), `name = "<tournament name> — <round label>"` (server-generated, truncated to the race-name limit; engine-created races skip user-facing name validation). Both participants are created ACCEPTED with `joinedAt = startedAt` and `baselineSteps` snapshotted exactly as `startRace.js:127-142` does.

**Migration:** one migration adding the enum, three tables (plus the `User` back-relations `tournamentsCreated`/`tournamentsWon`/`tournamentEntries`), the three `Race` columns + index/unique, and the launch seed row INSERT (`seed-tournament-daily-dash` / `DAILY_DASH` / "Daily Dash" / bracketSize 4 / 1-day matchups / powerups off / prize 150) — same pattern as the race-seed migration. No backfill needed (all new-null).

## 6. Backend behavior & API contract (pinned before either agent implements)

All endpoints under auth like `/races`. Every failure returns `{ "error": "<human copy>", "code": "<STABLE_CODE>" }` — old clients read `error`, the new app maps `code` (same convention as team races, `backend_api_service.dart:1914-1941`).

### 6.1 `POST /tournaments` — create

Requires `tournaments` token (else `403 UPDATE_REQUIRED`) and `tournamentsEnabled` AppSetting (else `403 FEATURE_DISABLED`).

Request:
```json
{
  "name": "Friday Gauntlet",
  "bracketSize": 8,
  "matchupDurationDays": 2,
  "buyInAmount": 50,
  "powerupsEnabled": true,
  "powerupStepInterval": 2500,
  "isPublic": true,
  "inviteeIds": ["u1", "u2"]
}
```
Validation: `bracketSize ∈ {4,8,16}`; `matchupDurationDays ∈ {1,2,3}`; `buyInAmount` 0 or 10–`TOURNAMENT_BUYIN_MAX[bracketSize]` with `TOURNAMENT_BUYIN_MAX = {4: 100, 8: 100, 16: 62}` (D4 ladder — pot caps 400/800/992; a new `validateTournamentBuyIn` in a shared constants module both agents read) and affordable by creator (`ensureUserCanAfford`); powerup fields validated exactly as `createRace` does; name 1–30 chars (tighter than races so generated matchup-race names fit, see §6.5); `inviteeIds` all friends **whose sticky `User.clientFeatures` contains `tournaments`** — a friend on a frozen old build can receive the push but can never see or answer the invite, so such invitees are rejected with `400 INVITEE_NEEDS_UPDATE` (the code and its error copy already exist from team races). Over-inviting beyond bracketSize−1 is allowed — capacity is enforced at accept time, first-come-first-served. Creator is inserted ACCEPTED with buy-in **held** (`reserveTournamentBuyIn`, §7). `timezone` from `X-Timezone`. `shareToken` always minted. Invitees inserted INVITED and pushed `TOURNAMENT_INVITE_SENT`.

Response `201`:
```json
{ "tournament": { "id": "t1", "name": "Friday Gauntlet", "status": "PENDING",
  "bracketSize": 8, "matchupDurationDays": 2, "buyInAmount": 50, "potCoins": 50,
  "powerupsEnabled": true, "powerupStepInterval": 2500,
  "isPublic": true, "shareToken": "abc123", "currentRound": 0, "totalRounds": 3,
  "creatorId": "me", "championUserId": null, "startedAt": null,
  "acceptedCount": 1, "myStatus": "ACCEPTED",
  "participants": [ { "userId": "me", "displayName": "…", "status": "ACCEPTED",
    "seed": null, "eliminatedInRound": null, "avatar": "…", "animal": "…",
    "equippedAccessories": [] } ],
  "rounds": [] } }
```
`rounds` (see 6.4) is the bracket; empty while PENDING.

### 6.2 Join / invite-respond / leave / kick (PENDING only)

- `POST /tournaments/:id/join` — public join. Errors: `404 TOURNAMENT_NOT_FOUND` (also returned when the client lacks the token — don't leak existence), `409 TOURNAMENT_FULL`, `409 ALREADY_JOINED`, `400 INSUFFICIENT_COINS`, `409 TOURNAMENT_NOT_PENDING`, `403 NOT_PUBLIC`, and for featured brackets `409 ALREADY_IN_FEATURED` (D12 guard, §6.10).
- `POST /tournaments/share/:token/join` — share-link join (bypasses `isPublic`; token is the invite). Same errors minus `NOT_PUBLIC`. `GET /tournaments/share/:token` returns an unauthed preview (name, bracketSize, filled count, buyIn) like `GET /races/share/:token`.
- `PUT /tournaments/:id/respond` `{ "accept": true }` — invite accept/decline. Accept holds the buy-in; errors as above plus `403 NOT_INVITED`, `409 ALREADY_RESPONDED`.
- `POST /tournaments/:id/invite` `{ "userIds": ["u3"] }` — creator-only, PENDING only, friends of the creator, skips users already ACCEPTED/INVITED (a previously DECLINED/left user is re-flipped to INVITED). Invitees without the sticky `tournaments` client feature are skipped and reported back in the response (`{ "invited": [...], "needsUpdate": [...] }`) so the lobby can say "Sam needs to update the app." Pushes `TOURNAMENT_INVITE_SENT`. Errors: `403 NOT_CREATOR`, `409 TOURNAMENT_NOT_PENDING`.
- `POST /tournaments/:id/leave` — PENDING only; refunds the held buy-in and **soft-removes** the participant: row is kept with `status: DECLINED`, `buyInStatus: REFUNDED`, `buyInVersion` incremented (never deleted — the version counter must survive so a rejoin's ledger refIds stay unique, §7). Creator cannot leave (must cancel): `400 CREATOR_CANNOT_LEAVE`. After start: `409 TOURNAMENT_NOT_PENDING` (use forfeit, §6.7).
- `POST /tournaments/:id/kick` `{ "userId": "u2" }` — creator-only, PENDING only; same soft-remove + refund as leave. Errors: `403 NOT_CREATOR`, `404 PARTICIPANT_NOT_FOUND`.
- **Rejoin after leave/kick/decline:** any join/accept path finding an existing DECLINED row **updates** it back to ACCEPTED (fresh `joinedAt = now` — the D3 tiebreak key reflects the latest entry) instead of inserting, holding the buy-in under the incremented `buyInVersion`.

Join/accept/invite/kick/leave all run inside a tournament row lock (`SELECT … FOR UPDATE`, same discipline as `withRaceJoinLock` in `editRace.js`) so capacity checks can't race. Capacity counts **ACCEPTED only** (INVITED don't hold a slot — same counting rule as team sides, `src/utils/teamRaces.js:6-28`); a full-bracket accept fails with `TOURNAMENT_FULL`. All mutations return the full tournament payload (6.4 shape).

### 6.3 Listings

- `GET /races` (existing): for token clients only, adds a sibling key `"tournaments": [ …summary objects… ]` containing every tournament where I'm ACCEPTED and status ≠ CANCELLED, **plus ones where I'm INVITED only while they're still PENDING** (a stale invite to a started/finished bracket must not linger). Ordered ACTIVE → PENDING → COMPLETED (COMPLETED capped at the last 5), newest first within each group. Summary = the 6.1 `tournament` object minus `participants`/`rounds`, plus `myStatus`, `myEliminatedInRound`, `acceptedCount`, and `myCurrentMatchRaceId` (the raceId of my live matchup, null if none). Old clients: key absent from their responses — byte-identical JSON.
- `GET /tournaments/public` — token-gated; response `{ "featured": [...], "tournaments": [...] }`. `featured` = each active seed's open bracket (§6.10 — stays listed even when joined/full; card flips client-side). `tournaments` = user-created PENDING public tournaments with open slots, excluding ones I'm in; newest first, capped at 25. Summary shape everywhere, + `seedKind`/`championPrizeCoins` on featured entries.
- `GET /tournaments/:id` — full payload (6.4). Any authenticated participant (including eliminated, per D8) or, while PENDING, anyone who can see it (public or via invite). Else `404 TOURNAMENT_NOT_FOUND`. **Spectating is bracket-level only:** `GET /races/:raceId` / `/progress` for a matchup race stay restricted to that matchup's two players — eliminated players watch via the bracket's near-live totals, not other people's race rooms.
- **Matchup race payloads** (`getRaceDetails` / `getRaceProgress`) gain additive fields for their two participants: `tournamentId`, `tournamentRound`, `tournamentRoundLabel`, `tournamentName` — the frontend banner (§9) reads them defensively.

### 6.4 `GET /tournaments/:id` payload — the bracket

```json
{ "tournament": { "…summary fields as 6.1…",
  "participants": [ { "userId": "u1", "displayName": "…", "status": "ACCEPTED",
      "seed": 3, "eliminatedInRound": 1, "avatar": "…", "animal": "…",
      "equippedAccessories": [] } ],
  "rounds": [
    { "round": 1, "label": "QUARTERFINALS",
      "matchups": [
        { "matchIndex": 0, "raceId": "r1", "status": "COMPLETED",
          "endsAt": "2026-07-18T14:00:00.000Z",
          "players": [
            { "userId": "u1", "totalSteps": 18452, "forfeited": false },
            { "userId": "u2", "totalSteps": 12001, "forfeited": false } ],
          "winnerUserId": "u1", "tie": false }
      ] }
  ] } }
```
- `label` server-computed: 16 → ROUND OF 16 / QUARTERFINALS / SEMIFINALS / FINAL; 8 → QF/SF/FINAL; 4 → SEMIFINALS/FINAL.
- Future rounds appear with `raceId: null` and `players: []` placeholders so the client can draw the whole bracket skeleton.
- `totalSteps` comes from the persisted `RaceParticipant.totalSteps` (refreshed every 5 min by `placementRecompute` and on race-detail opens) — the bracket view is *near-live*; the true 30s-polled live view is the matchup's race-detail screen.
- **Display illusions must carry over (D5):** when powerups are enabled, the `players` block of any non-COMPLETED matchup applies the same viewer-dependent illusions (Stealth, Detour, Imposter) as `getRaceProgress` — otherwise the bracket is a side channel that defeats Stealth. Extract the illusion logic from `getRaceProgress.js` into a shared helper rather than duplicating it. COMPLETED matchups always show true finals.

### 6.5 Start & round advancement (the new engine)

**`POST /tournaments/:id/start`** — creator-only, PENDING-only, requires `acceptedCount == bracketSize` (else `409 BRACKET_NOT_FULL` with `error` "Need N more racers"). In one transaction:
1. Conditional `PENDING→ACTIVE` flip (idempotency, like `startRace.js:116-124`).
2. Commit pot: all HELD buy-ins → COMMITTED; `potCoins = bracketSize × buyInAmount`.
3. Random-shuffle ACCEPTED participants → assign `seed` 0..N−1.
4. Create + start round-1 matchup races **in the same transaction** (a crash never leaves a half-created round): match *i* pairs seeds `2i` and `2i+1`; `startedAt = now`, `endsAt = now + matchupDurationDays`, participants ACCEPTED with `baselineSteps` snapshot (extract the snapshot logic from `startRace.js:127-142` into a shared helper — do not duplicate it).
5. `currentRound = 1`; emit `TOURNAMENT_STARTED` after commit (per-player copy includes the opponent's name; push `params` carry both `tournamentId` and the player's matchup `raceId`).

**Advancement — `advanceTournament(tournamentId)` service:**
- Trigger: `completeRace` gets a tournament branch — when the settling race has `tournamentId`, after the normal complete flip it records the matchup winner and calls `advanceTournament`. A safety sweep in the `raceExpiry` job also calls it for any ACTIVE tournament whose current-round races are all COMPLETED (belt-and-braces against a crashed advance).
- Inside a tournament `FOR UPDATE` lock: if any current-round matchup race is not COMPLETED → return (no-op). Otherwise:
  - Compute round winners (see 6.6). Push `TOURNAMENT_ELIMINATED` to losers and `TOURNAMENT_MATCHUP_WON` to winners (suppressed for the final — see below). **Note:** `eliminatedInRound = currentRound` is stamped on the loser **at matchup completion** (in the `completeRace` tournament branch, including early forfeit completions), not here — the D12 repeat-entry guard must free a knocked-out player the moment their own matchup settles, not when the slowest matchup of the round does. Advancement only reads it.
  - **Not the final:** create + start round `r+1` races in one transaction — match *i* pairs the winners of round-`r` matches `2i` and `2i+1`; `startedAt = now`, `endsAt = now + matchupDurationDays`, fresh baselines. `currentRound = r+1`. Push `TOURNAMENT_ROUND_STARTED` to the survivors (new opponent name; `params` carry `tournamentId` + their `raceId`). The `@@unique([tournamentId, tournamentRound, tournamentMatchIndex])` constraint makes double-advancement a hard DB error, not silent duplicate races.
  - **The final:** set `championUserId`, `status = COMPLETED`, `completedAt = now`; pay the champion the whole `potCoins` (§7); push `TOURNAMENT_CHAMPION` to the winner and `TOURNAMENT_COMPLETED` to everyone else.
- Latency: all matchups in a round share `endsAt`, and `raceExpiry` runs every 5 min — the next round starts within ~5–10 min of round end (D6).

**Matchup races and existing side systems:**
- `completeRace` for a matchup: `potCoins = 0` so `computeRacePayouts` pays nothing; `seedId = null` so no minted finish reward. **Referral rewards and review-prompt "happy moment" must skip races with `tournamentId`** — a 4-round tournament must not count as 4 completed races for referral credit or trigger 4 review prompts.
- Notification handlers **suppress `RACE_STARTED`/`RACE_COMPLETED`** when `race.tournamentId != null` (the tournament pushes replace them). `PLACEMENT_CHANGED` overtake nudges stay on — "you lost the lead" is exactly right in a 1v1.
- `autoStartScheduledRaces`, seeded renewal, editRace: matchup races have no `scheduledStartAt`/`seedId`, and **every race-level mutation path returns `400 TOURNAMENT_RACE_LOCKED` when `race.tournamentId != null`**: `PATCH /races/:id`, `DELETE /races/:id`, `POST /races/:id/forfeit`, `POST /races/:id/join`, `PUT /races/:id/respond`, `POST /races/:id/invite`, kick, `POST /races/:id/share` (link creation), and `POST /races/:id/leave`. Matchups are managed only by the tournament engine; chat, progress reads, and step scoring work unchanged.

### 6.6 Matchup winner & tiebreak (D3)

Winner = higher effective `totalSteps` at settlement (identical math to today's `raceExpiry` — shared `raceStateResolution`). A forfeited player always loses (6.7). On an **exact tie**: the player whose `TournamentParticipant.joinedAt` is earlier advances. **Important:** the generic `raceExpiry` standings sort breaks ties by reach-time-then-userId (`raceExpiry.js:161-170`) — the tournament branch must NOT inherit that; on equal totals it applies the tournament tiebreak explicitly and sets `Race.winnerUserId` accordingly. `tie` in the §6.4 payload is derived at read time (both finalized totals equal), not stored; UI copy stays honest ("Tied — Alice advances on earlier entry"). No coin flips, no replays (v1).

### 6.7 Forfeit / withdrawal after start

`POST /tournaments/:id/forfeit` — for a player with a live matchup: sets `forfeitedAt` on their matchup `RaceParticipant` **and immediately completes that matchup** (opponent wins, `winnerUserId = opponent`), then runs the normal advancement check. Eliminated players and players with no live matchup get `409 NO_LIVE_MATCHUP`. No refunds after start (buy-ins are COMMITTED). The existing `POST /races/:id/forfeit` returns `400 TOURNAMENT_RACE_LOCKED` for matchup races so there's exactly one forfeit path.

If **both** players of a matchup forfeit (sequentially — the first forfeit completes the matchup, so this can't truly happen; the second player simply loses normally): no special case needed. Document this in tests.

### 6.8 Cancel

`DELETE /tournaments/:id` — creator-only, **PENDING only**: refund every HELD buy-in, status → CANCELLED, push `TOURNAMENT_CANCELLED` to accepted/invited. After start: `409 TOURNAMENT_NOT_PENDING` — an active bracket cannot be cancelled in v1 (creator can forfeit like anyone else).

### 6.9 Error-code table

| HTTP | code | When |
|---|---|---|
| 403 | `UPDATE_REQUIRED` | Client lacks `tournaments` token on create/join/respond |
| 403 | `FEATURE_DISABLED` | `tournamentsEnabled` AppSetting off |
| 404 | `TOURNAMENT_NOT_FOUND` | Missing, or hidden from this viewer |
| 409 | `TOURNAMENT_FULL` | Join when acceptedCount == bracketSize |
| 409 | `ALREADY_JOINED` | Duplicate join/accept |
| 409 | `TOURNAMENT_NOT_PENDING` | Join/leave/kick/cancel after start |
| 409 | `BRACKET_NOT_FULL` | Start before full |
| 409 | `NO_LIVE_MATCHUP` | Forfeit with nothing live |
| 409 | `ALREADY_IN_FEATURED` | Joining a featured bracket while still alive in another one from the same seed (D12) |
| 400 | `INSUFFICIENT_COINS` | Can't afford buy-in |
| 403 | `NOT_CREATOR` / `NOT_INVITED` / `NOT_PUBLIC` | As named |
| 404 | `PARTICIPANT_NOT_FOUND` | Kick target isn't in the lobby |
| 409 | `ALREADY_RESPONDED` | Re-answering an invite |
| 400 | `CREATOR_CANNOT_LEAVE` | Creator tries leave instead of cancel |
| 400 | `INVITEE_NEEDS_UPDATE` | Create-time invitee has never advertised the `tournaments` feature (existing code, reused) |
| 400 | `TOURNAMENT_RACE_LOCKED` | Any race-level mutation attempted directly on a matchup race (§6.5 list) |
| 400 | `VALIDATION` | Bad bracketSize/duration/buyIn/name |

### 6.10 Featured (seeded) tournaments — D9/D10/D11

Auto-generated brackets minted from `TournamentSeed` templates, modeled on the seeded-race system (`seededRaceRenewal.js`) with one twist: promotion is **fill-triggered, not time-anchored**.

**Renewal job** — new `tournamentSeedRenewal`, 60s cadence (registered in `src/index.js` beside `scheduleSeededRaceRenewal`, with the same in-process overlap guard). For each `active: true` seed it enforces two invariants, in order:
1. **Backup-promote:** if a PENDING seeded tournament is already full (`acceptedCount == bracketSize`) — possible only if a fill-join crashed between join and start — promote it now.
2. **Ensure exactly one open PENDING tournament per seed:** if none exists, mint one — `creatorId: null`, `seedId`, `isPublic: true`, `buyInAmount: 0`, `potCoins: 0`, name/bracketSize/duration/powerup fields copied from the seed, `timezone: "America/New_York"` (no creator to inherit from; same anchor as seeded races), `shareToken` minted (featured brackets are shareable).

The reconciler also respects the `tournamentsEnabled` AppSetting: while the kill switch is off it mints **no** new lobbies (joins are blocked anyway — an unjoinable lobby would just be noise), and resumes on the next tick after re-enable.

If a seed is flipped `active: false`, the reconciler **cancels its open PENDING tournament** (normal cancel semantics; free, so no refunds) so players aren't stranded in a lobby that will never respawn — running/ACTIVE ones finish naturally. This is also the featured kill switch (no new AppSetting needed).

**Repeat-entry guard (D12):** on any join path (public or share-link) into a tournament with `seedId != null`, reject with `409 ALREADY_IN_FEATURED` if the user has an ACCEPTED `TournamentParticipant` row in **another tournament of the same seed** whose status is PENDING or ACTIVE and whose `eliminatedInRound` is null (still alive). Eliminated players (stamped at their own matchup's completion, §6.5 — including forfeits) and players whose bracket has COMPLETED/CANCELLED join freely. The guard is per-seed, so a future second seed doesn't lock users out across templates. This check runs inside the same join lock, before capacity.

**Pop-when-full (D9):** the join/accept that reaches `acceptedCount == bracketSize` triggers the §6.5 start transaction **inline, inside the same tournament row lock** (seeding, round-1 races, pushes). Concurrent joiners past capacity get `TOURNAMENT_FULL` as usual. The cron's invariant 2 then spawns the next open bracket within ≤60s. The §6.5 creator-start endpoint simply never applies (`creatorId: null` matches no caller → creator-only endpoints return `NOT_CREATOR`; there is nothing to kick/cancel/invite/edit — join, share-join, and leave are the only lobby verbs).

**Prize (D10):** featured tournaments are always free; the champion is paid a **minted** `seed.championPrizeCoins` in the §6.5 final branch — `awardCoins({ reason: "tournament_champion_reward", refId: "<tournamentId>:champion" })` — a distinct reason from the pot payout (`tournament_payout`), mirroring how seeded races' `race_finish_reward` is separate from buy-in payouts. Exactly one of the two prize paths fires per tournament: pot if `buyInAmount > 0`, minted if `seedId != null`; a free user-created tournament pays nothing.

**Surfacing:** `GET /tournaments/public` gains a sibling `featured: [...]` array (summary shape + `seedKind`, `championPrizeCoins`) listing each active seed's open PENDING bracket — pinned above the user-created list, kept in the array even when I've joined (card flips JOIN → VIEW, like `getFeaturedRaces`). Featured tournaments I'm in appear in my `GET /races` tournaments bucket like any other (summaries carry `seedKind`/`championPrizeCoins` so tickets can show the prize). **No changes to `GET /races/featured`** — old clients' featured-races payload is untouched, and everything featured-tournament lives behind the new token-gated endpoints.

**Launch lineup (D11):** the single migration-inserted seed "Daily Dash" (4-bracket, 1-day matchups, powerups off, 150-coin prize). Adding "Weekly Gauntlet"-style seeds later is a DB insert, no code change. `championPrizeCoins` must respect the 1,000-coin winnings cap (enforced in the renewal job as a guard, not just convention).

## 7. Coins & ledger (idempotent refIds)

New `CoinTransaction` reasons, following `raceBuyIns.js` patterns:

| Event | reason | refId |
|---|---|---|
| Hold at join/accept | `tournament_buy_in_hold` | `<tournamentId>:<userId>:v<buyInVersion>` |
| Refund (leave/kick/cancel) | `tournament_buy_in_refund` | `<tournamentId>:<userId>:v<buyInVersion>` (same version as the hold it reverses) |
| Champion payout (pot, user tournaments) | `tournament_payout` | `<tournamentId>:champion` |
| Champion prize (minted, featured) | `tournament_champion_reward` | `<tournamentId>:champion` |

All through the existing idempotent `awardCoins` (`@@unique(userId, reason, refId)`). Every refId is versioned from day one (`:v0` for the first hold — consistency beats cleverness). The version counter lives on `TournamentParticipant.buyInVersion` and is incremented **at refund time**; because leave/kick soft-remove the row (§6.2) rather than deleting it, the counter survives leave→rejoin cycles — a re-hold uses `:v1`, `:v2`, … and can never silently no-op against an old ledger row. This is the `buyInVersion` lesson from the team-race-fixes batch (Issue 4) applied preemptively. A free tournament (`buyInAmount: 0`) writes no ledger rows at all (hold/refund/payout are skipped, not written as zero).

## 8. Push notifications (new types — additive, old clients no-op the deep link)

All via the existing `sendNotificationToUser` + `Notification` audit rows. `route: "tournament_detail"`, `params: { tournamentId }` unless noted.

| type | To | Copy sketch |
|---|---|---|
| `TOURNAMENT_INVITE_SENT` | invitee | "🏆 {creator} invited you to {name} — {bracketSize} racers, winner takes {pot}!" (free bracket: "…winner takes the crown!") |
| `TOURNAMENT_STARTED` | all players | "The bracket is set! Round 1: you vs {opponent}. {days}d — go!" (routes to `race_detail` of their matchup) |
| `TOURNAMENT_ROUND_STARTED` | survivors | "{label}! You drew {opponent}. {days}d on the clock." (routes to their matchup) |
| `TOURNAMENT_MATCHUP_WON` | round winners (not final) | "You won your matchup! {label} is next." |
| `TOURNAMENT_ELIMINATED` | round losers | "Knocked out in the {label} by {opponent}. Follow the bracket to the end!" |
| `TOURNAMENT_CHAMPION` | champion | "🏆 CHAMPION! You swept {name} and won {pot|prize} coins!" (free user bracket: "…took the crown!") |
| `TOURNAMENT_COMPLETED` | everyone else | "{champion} took the crown in {name}." |
| `TOURNAMENT_CANCELLED` | accepted+invited | "{name} was called off — your {buyIn} coins are back." |

Suppressed for matchup races: `RACE_STARTED`, `RACE_COMPLETED` (replaced by the above). Kept: `PLACEMENT_CHANGED` overtake nudges, `POWERUP_USED` (when the creator enabled powerups, D5), race chat pushes.

## 9. Frontend plan (iOS + Android in lockstep; load `mobile-design` skill before any UI work)

No `Race`/`Tournament` Dart classes — raw `Map` + a new static-helper util, in the `lib/utils/team_race.dart` mold.

**New `lib/utils/tournament.dart`:**
- `Tournament.isX(map)`-style defensive readers for every field in §6.4 (missing → safe default, never crash).
- `roundLabel`, `myMatchup(tournament, userId)`, `aliveCount`, `champion` helpers.
- `tournamentErrorCopy(code)` mapping the §6.9 table to playful copy with a generic default (sibling of `teamRaceErrorCopy`, `team_race.dart:300-346`).

**API layer (`lib/services/backend_api_service.dart`):**
- Add `tournaments` to `clientFeaturesHeader`.
- New methods mirroring §6: `createTournament`, `fetchTournament`, `fetchPublicTournaments`, `joinTournament`, `joinTournamentByShareToken`, `fetchSharedTournament`, `respondToTournamentInvite`, `inviteToTournament`, `leaveTournament`, `kickTournamentParticipant`, `startTournament`, `forfeitTournament`, `cancelTournament`, `createTournamentShareLink`. Each a small sibling of the race methods; existing methods untouched (the `createTeamRace` precedent, `:855`).
- `fetchRaces` consumers read the new `tournaments` key defensively (absent → `[]`).

**Create flow (`lib/screens/create_race_screen.dart`):**
- Third signpost option **"TOURNAMENT"** beside FREE-FOR-ALL / TEAMS (`:391-416`).
- Tournament reveal: bracket-size picker (4/8/16 — "8 RACERS · 3 ROUNDS" subcopy), matchup-duration chips (1/2/3 days), buy-in toggle + amount (reused widget, `:1120-1250`) with the **D4 ladder max** ("MAX 100 FOR 8 RACERS · POT UP TO 800" — clamp and re-validate when bracket size changes so a stale 100 can't survive a switch to 16), the existing powerup toggle + interval controls (D5), public toggle, invitees. **Hidden in tournament mode:** payout preset (always WTA), max-participants, duration chips `[3,5,7,14]`, scheduled start, team controls.
- Submit branches to `createTournament`; success routes to the new tournament detail screen.

**New `lib/screens/tournament_detail_screen.dart`** — one parchment board per section, no cards-in-cards, `all(14)` padding:
- **PENDING (lobby):** filled/empty slot grid ("5 OF 8 RACERS"), invite + share-link buttons, pot/prize plaque ("WINNER TAKES 400 🪙" / featured: "CHAMPION WINS 150 🪙"), creator-only START (disabled until full, with "NEED 3 MORE" label), leave/kick/cancel affordances. **Featured lobbies** (`seedId` present, read defensively): no creator controls at all — the copy is "STARTS THE MOMENT IT FILLS"; join/leave/share only. Slot rendering reuses `AnimatedCapybaraWithAccessories` (the `TeamLobbyBoard` precedent, `lib/widgets/team_lobby_board.dart`).
- **ACTIVE (bracket):** the marquee view — a wooden-bracket board: rounds as columns (horizontal scroll for 16), each matchup a small plank pair with avatars, near-live step counts, winner check / strikethrough on the eliminated. **My live matchup** gets a highlighted "YOUR MATCHUP — TAP TO RACE" plank opening the existing race-detail screen (which gives the full 30s-polling H2H experience unchanged). Round countdown from the shared `endsAt`. Forfeit via the branded dialog pattern (`race_detail_screen.dart:946-987`) with consequence copy ("Your opponent advances. No refunds.").
- **COMPLETED:** champion plank with crown + pot; `CelebrationConfetti` **only if the viewer is the champion** (confetti-on-finish rule). Full final bracket stays browsable (D8).
- Polling: 60s `Timer.periodic` refresh of `fetchTournament` while PENDING/ACTIVE, using the same `racePollLifecycleAction` pause/resume pattern (`race_detail_screen.dart:263-296`).
- States: loading skeleton, error retry, and every field defensive.

**Races tab (`lib/screens/tabs/races_tab.dart`):** a TOURNAMENTS section above/with the existing buckets rendering summary tickets (name, 🏆, "ROUND 2 OF 3 · YOU'RE ALIVE" / "KNOCKED OUT" / "5/8 FILLED", pot). Invited tournaments render in the invites section with accept/decline via `respondToTournamentInvite`. Tap → tournament detail.

**Public races screen (`lib/screens/public_races_screen.dart`):** a pinned **FEATURED** 🏆 card per active seed at the top (from `fetchPublicTournaments().featured` — name, "4 RACERS · 1-DAY KNOCKOUTS", "3 OF 4 IN", "CHAMPION WINS 150 🪙", JOIN flips to VIEW once joined; free, so no confirm dialog; the D12 guard surfaces as `tournamentErrorCopy('ALREADY_IN_FEATURED')` → "Finish your current bracket first!", and the card can pre-disable JOIN when the summary shows me still alive in one), then user-created public tournaments as distinct 🏆 cards below; paid joins → confirm buy-in dialog (paid-invite pattern, `race_detail_screen.dart:758-799`) → `joinTournament`.

**Race detail (`lib/screens/race_detail_screen.dart`):** when the race map carries `tournamentId` (returned by `getRaceDetails`/`progress` for matchups), show a tappable banner "🏆 {ROUND LABEL} — {tournament name}" linking to the bracket, and hide the race-level forfeit/cancel/edit affordances (tournament screen owns forfeit).

**Pushes (`lib/services/notification_service.dart`):** add `tournamentDetail` to `NotificationRoute`; map the §8 types (`TOURNAMENT_STARTED`/`TOURNAMENT_ROUND_STARTED` → `raceDetail` with the matchup raceId when present, else tournament); extract `tournamentId` from params like `raceId` (`:277-289`).

**Deep links (`lib/services/deep_link_service.dart`):** `/t/<token>` universal link + `bara://tournament/<token>` → shared-tournament preview → join flow (mirrors `/r/<token>`). **Backend side-task:** the share-landing web route and the AASA / assetlinks path lists must gain `/t/*` alongside `/r/*` — without that, iOS/Android universal links for tournaments silently fall back to the browser.

## 10. Test plan (tests-first, both agents; never bare `npm test`, never the prod DB, never modify existing tests)

**Backend unit (`test:unit`):**
- Bracket math: pairing (seeds 2i vs 2i+1), winners-of-2i/2i+1 advancement, totalRounds/labels for 4/8/16.
- Winner resolution: higher steps wins; exact tie → earlier `joinedAt` advances, `tie` flagged; forfeited player loses regardless of steps.
- Validation: bracketSize/duration/name matrices; buy-in ladder matrix (max 100/100/62, pots never exceed 400/800/992); powerup field validation parity with `createRace`.
- Refund/hold/payout refId generation incl. versioned re-hold after leave→rejoin.
- `advanceTournament` no-op when round incomplete; final-round path sets champion + status.

**Backend integration (`test:integration`, test DB only):**
- Full happy path: create(8) → 7 joins (mix of invite-accept, public join, share token) → start → verify 4 matchup races (baselines, endsAt, WTA/no-pot config) → force-settle round 1 → verify round 2 created within the same sweep, losers eliminated → … → final → champion paid exactly `potCoins`, ledger rows idempotent on re-run.
- Concurrency: two matchups settling in one sweep advance the round exactly once (unique-constraint backstop); double `start` call flips once; join races at capacity → one `TOURNAMENT_FULL`.
- Forfeit: live-matchup forfeit completes the matchup and advances; `NO_LIVE_MATCHUP` for eliminated; every race-level mutation path (forfeit/PATCH/DELETE/join/respond/invite/kick/share/leave) on a matchup → `TOURNAMENT_RACE_LOCKED`.
- Money: cancel-refunds-all; leave→rejoin soft-remove preserves `buyInVersion` and re-holds under `:v<n+1>` (assert the second hold actually charges); free tournament writes zero ledger rows.
- Scoring: a 1-day matchup started mid-day attributes start-day steps correctly (samples-only start-day rule) and settles at exactly `startedAt + 1d`.
- Exact-tie matchup: winner is the earlier tournament `joinedAt`, NOT the generic userId sort; late invite via `POST /tournaments/:id/invite` reaches a full lobby → accept fails `TOURNAMENT_FULL`.
- **Old-client invisibility:** requests without the `tournaments` token get byte-identical `GET /races` (no `tournaments` key) and never see matchup races in `/races`, `/races/public`, `/races/featured`, or the home card; create/join without token → `UPDATE_REQUIRED`.
- Referral + review-happy-moment exclusion for matchup races; `RACE_STARTED`/`RACE_COMPLETED` suppressed, tournament pushes emitted (audit rows).
- Kill switch off → create/join blocked, in-flight tournament still advances.
- Powerups (D5): matchup races inherit the toggle + interval; a powerup-enabled tournament grants fresh slots each round; Stealth in a live matchup is masked identically in the bracket payload and unmasked once COMPLETED.
- Featured guard (D12): joining while alive in a same-seed bracket → `ALREADY_IN_FEATURED`; a round-1 loser can join the next lobby the moment their matchup settles (before the round finishes); a forfeiter is likewise freed immediately; the champion can join the next lobby after completion; the guard doesn't block across different seeds; `eliminatedInRound` stamped at matchup completion.
- Featured (D9–D11): reconciler mints exactly one open bracket per active seed and is idempotent across ticks; the fill-join starts the tournament inline and a fresh bracket appears on the next tick; a crash between fill and start is repaired by backup-promote; champion gets exactly one minted `tournament_champion_reward` (idempotent on re-settle); flipping `active: false` cancels the open lobby and stops respawns while an ACTIVE featured bracket finishes and pays; creator-only endpoints on a seeded tournament → `NOT_CREATOR`; featured entries never appear in old-client payloads (`/races/featured` byte-identical).

**Frontend (`flutter test`):**
- `tournament.dart` defensive parsing: full payload, empty map, missing rounds/players, unknown status.
- `tournamentErrorCopy` covers every §6.9 code + default.
- Create-screen tournament mode: hidden controls (payout/max/schedule/teams), bracket+duration selection, powerup toggle passthrough, buy-in max re-clamps when bracket size changes, submit payload shape.
- Bracket board widget: PENDING slots, ACTIVE with placeholders for future rounds, eliminated strikethrough, champion state; confetti only for champion viewer.
- Races-tab ticket states (alive/eliminated/filling); notification route mapping for all `TOURNAMENT_*` types and unknown-type fallthrough.
- Featured card states (open/joined/nearly-full), prize plaque rendering, featured lobby hides creator controls, `featured` key absent → no featured section (old backend).

## 11. Acceptance criteria / definition of done

- [ ] All §10 tests written first, failing for the right reason, then green; no existing test modified.
- [ ] Prisma migration applied on local + staging; prod deploy is backend-first.
- [ ] A frozen old client (no `tournaments` header) shows byte-identical race lists against the new backend and never sees a matchup race anywhere.
- [ ] Full 8-bracket run on staging: create → fill via all three join paths → start → 3 rounds advance automatically → champion paid pot exactly once; ledger audit clean.
- [ ] Featured flow on staging: Daily Dash lobby auto-appears, 4th join pops it instantly, fresh lobby respawns ≤60s, champion gets the minted 150, seed `active: false` cancels the open lobby.
- [ ] Tie and forfeit paths verified on staging.
- [ ] `tournamentsEnabled` kill switch verified (blocks create/join, running brackets finish).
- [ ] iOS **and** Android builds pass (`flutter build ipa` + `flutter build appbundle --flavor prod`), same version/build number.
- [ ] Design pass: mobile-design skill loaded; parchment/wood identity; one-board sections; confetti only on the champion's completed view.
- [ ] Push deep links land: invite → tournament, round start → matchup race, champion → tournament.
- [ ] Universal links: `/t/*` added to the share-landing route and the AASA + assetlinks path lists; verified on a device for both platforms.
- [ ] Spec's Decisions table fully locked (no PENDING rows) and reflected in code.

## 12. Revision log

- **Draft 1 (2026-07-16):** initial spec from backend/frontend exploration reports.
- **Pass 1 — correctness & edge cases (2026-07-16):**
  1. **Ledger free-entry bug:** leave originally *deleted* the participant row, destroying `buyInVersion` — a rejoin's hold refId would collide with the old hold and `awardCoins` would silently no-op (free entry). Changed to soft-remove (row kept as DECLINED, version incremented at refund); §6.2/§7 rewritten; refId table fixed to always-versioned `:v<n>`.
  2. **Tiebreak override:** the generic `raceExpiry` sort breaks ties by reach-time-then-userId; §6.6 now explicitly forbids inheriting that for matchups and pins the earlier-`joinedAt` rule; `tie` clarified as derived, not stored.
  3. **Missing endpoint:** added `POST /tournaments/:id/invite` (post-create invites from the lobby) + over-invite semantics (capacity enforced at accept, ACCEPTED-only counting).
  4. **Race-level lockout hardened:** enumerated *every* race mutation path (join/respond/invite/kick/share/leave/forfeit/PATCH/DELETE) returning `TOURNAMENT_RACE_LOCKED`; matchups get `shareToken: null`.
  5. **Name overflow:** tournament names capped at 30 chars; matchup race names server-generated ("<name> — <label>") and exempt from user-facing validation.
  6. Round creation pinned as single-transaction; pushes carry both `tournamentId` and `raceId`; kill switch scoped to entries only (running brackets finish); D8 narrowed to bracket-level spectating (race rooms stay private); free tournaments write zero ledger rows; added tests for 1-day start-day scoring, rejoin re-charge, tie rule, and full-lobby accepts.
- **Pass 2 — contract, client reachability & rollout (2026-07-16):**
  1. **Stranded old-app invitees:** an invite to a friend on a frozen build would push them toward a feature their app can't render, leaving a permanent phantom INVITED slot. Fixed by gating invitees on the sticky `User.clientFeatures` record — create rejects with the existing `INVITEE_NEEDS_UPDATE` code; the lobby invite endpoint skips and reports `needsUpdate` so the UI can explain.
  2. **Stale invites:** `GET /races` originally listed INVITED tournaments regardless of status — an unanswered invite to a now-ACTIVE bracket would linger as an unactionable ticket. Now INVITED rows are listed only while PENDING.
  3. Pinned tournaments-bucket ordering (ACTIVE → PENDING → COMPLETED, newest first per group).
  4. Error table: added `INVITEE_NEEDS_UPDATE`; widened `TOURNAMENT_RACE_LOCKED` description to the full §6.5 mutation list.
  5. Free-bracket push copy variant (no "{pot}" for 0-coin tournaments).
  6. Acceptance criteria: added the `/t/*` AASA/assetlinks universal-link item (without it tournament share links silently fall back to the browser).
- **Phase 3 — interview fold-in (2026-07-16):** all eight decisions locked (§3). Changes vs the draft's assumptions: **D4** — pot hard-capped at 1,000 coins, buy-in max now scales with bracket size (`min(200, ⌊1000/bracketSize⌋)`; new `validateTournamentBuyIn`; create-screen buy-in clamp re-validates on bracket-size change). **D5** — powerups changed from "disabled v1" to a **creator toggle**: `powerupsEnabled`/`powerupStepInterval` added to the Tournament model, request/response contract, and matchup-race inheritance; noted that per-matchup scoping is automatic (each matchup is its own race) and pinned the bracket-payload illusion rule (Stealth must be masked in the bracket exactly as in the race room, via a shared helper). D1/D2/D3/D6/D7/D8 confirmed as recommended.
- **Phase 3b — featured tournaments + buy-in ladder (2026-07-16, second interview):** D4 revised to the per-size ladder (max buy-in 100/100/62 → pot caps 400/800/992, replacing the flat 1000 cap); D9–D11 added (pop-when-full featured brackets, always-free with minted `tournament_champion_reward`, single "Daily Dash" launch seed). New: `TournamentSeed` model + migration seed row, `tournamentSeedRenewal` 60s job (backup-promote + one-open-lobby invariants, inactive-seed lobby cancellation as the featured kill path), `featured` array on `GET /tournaments/public`, featured lobby/card frontend states, `Tournament.creatorId` made nullable.
- **Final pass (2026-07-16):** summary updated to mention featured brackets; stale schema comments fixed to the D4 ladder; seeded timezone noted in the model; pinned that the seed reconciler mints no new lobbies while `tournamentsEnabled` is off (joins are blocked, a lobby would be unjoinable noise) and resumes after re-enable.
- **D12 addendum (2026-07-16, post-launch question from Rohan):** identified that free respawning lobbies + minted prizes + steps-counting-in-every-race allowed unbounded concurrent featured entries (a mint-farming loop, worst with colluding accounts). Added the per-seed alive-guard: `409 ALREADY_IN_FEATURED` on join while still alive in a same-seed bracket; eliminated players free immediately. Forced one engine change: `eliminatedInRound` is stamped at **matchup completion** (completeRace tournament branch, incl. forfeits), not at round advancement, so knocked-out players are freed the moment their own matchup settles. Error table, §6.2/§6.5/§6.10, frontend copy/card state, and tests updated; both build agents notified mid-flight.
