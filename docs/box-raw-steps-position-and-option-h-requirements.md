# Mystery-box position from raw walked steps + Option H trailer catch-up drops

Status: DRAFT — awaiting approval. Backend repo: `/Users/rohan/repos/stepv2-backend`.

## Summary & user story

Players complain drop odds feel rigged: trailers farm offense (Wrong Turn, Leg
Cramp) while leaders draw self-boosts. The game-analyst investigation
(`docs/economy.md` §3.3b–f, §7, §8) found the real defects and the user chose
this scope:

1. **Exploit fix (backend code):** the position used for mystery-box drop odds
   is today computed from `race_participants.total_steps` — the
   effect-sensitive leaderboard total — at **open** time. Two manipulations
   follow: *box banking* (earn boxes while leading, open while temporarily
   last for 45% RARE odds) and *powerup hoarding* (unused bonus powerups keep
   your `totalSteps` low, pinning you at trailing odds all race; worth up to
   +12.5% under Option H). Fix: compute the **odds position from raw walked
   steps** (`baseAdjusted`), the same manipulation-proof quantity box progress
   already uses (`src/modules/powerups/boxSteps.js`). Raw steps only grow by
   walking, so neither banking nor hoarding moves your odds.
2. **Option H config (no deploy):** re-tilt the drop tables so trailing
   players catch up with self-boosts instead of griefing — Protein Shake /
   Trail Mix / Runner's High go 4% → ~17% each at last place; Wrong Turn +
   Leg Cramp share drops 28% → ~4%. Offense peaks at mid-pack. Exact table in
   `docs/economy.md` §8 Option H. Single `balance_config` row edit.

Explicitly declined by the user: **Option E** (position-scaled box interval /
box frequency change). Not in scope.

As a trailing player, I catch up by getting boosts for myself, not by
attacking the leader; as a leader, I stop being chain-griefed; as any player,
I can't game my drop odds by sitting on boxes or powerups.

## Scope / non-goals

- IN: `raw_steps` persistence, odds-position switch to raw steps in every
  roll/disclosure path, Option H `balance_config` edit, `rarityByType` drift
  reconcile (WRONG_TURN, SNEAKY_SWAP).
- OUT: box interval/frequency (Option E — declined), repeat-target cap
  (economy.md Option F), Wrong Turn −M clamp (Option G), any new powerup
  type, any frontend UI change, any change to `isStepLeader`/`isStepLast`
  semantics, any change to the rarity-tier curve (`positionOdds` rows still
  sum to 1.0). **Settlement and coin payouts are untouched**:
  `raceExpiry`/`completeRace` and all coin writes keep reading Postgres
  `totalSteps` — this is an odds-position change, not a scoring change.

## Current reality (verified 2026-08-09)

- Roll: `src/modules/powerups/commands/openMysteryBox.js:132-168` sorts
  `allParticipants` by `totalSteps` for `position`, then builds ctx via
  `buildRollContext` (`powerupOdds.js:97-116`).
- Reroll: `src/modules/powerups/commands/rerollMysteryBox.js:258-295` — same
  pattern. Batch open (`openMysteryBoxBatch.js`) delegates to `openMysteryBox`
  per box, so it inherits the fix.
- Disclosure: `src/modules/races/queries/getRaceProgress.js:143-209`
  (`buildDropOdds`) computes `position` from the same effect-sensitive
  `stepTotals`. Roll and disclosure share `buildRollContext` /
  `eligiblePoolFor` so they cannot drift — this invariant must survive.
- Raw walked steps (`baseAdjusted`) are computed only inside the
  `getRaceProgress` replay (`getRaceProgress.js:287-359`,
  `participantStepsMap`) and published into the shared snapshot as
  `participants[].baseAdjusted` (`raceProgressSnapshot` allowlist;
  `null` in the cheap persisted-columns fallback, `getRaceProgress.js:688`).
  They are **not persisted** on `race_participants` — that is the gap this
  spec closes.
- **Leaderboard totals have FOUR writers, not one** (architect finding — the
  v2 worker does NOT share the replay persist loop):
  1. `getRaceProgress.js:488-495` legacy persist — runs only when
     `redisStandingsEnabled` is OFF (`getRaceProgress.js:1175-1184`; flag at
     `src/shared/config/appSettings.js:126`).
  2. The v2 worker path (the PROD configuration): `raceStateResolution.js:834`
     (`processRace`) → write captured by the proxy at
     `computeRaceState.js:32-46` → replayed inside the fence at
     `raceResolutionQueueV2.js:210-223` as
     `tx.raceParticipant.update({ data: { totalSteps, totalsUpdatedAt } })`.
  3. `reconcileUploaderRaces.js:152` (step-upload path — freshest raw source;
     `baseAdjusted` in scope at line 160).
  4. (Model seam for all of the above: `raceParticipant.js:130`.)
  Any `raw_steps` design that misses writer 2 leaves the column NULL forever
  in prod and the exploit open.
- Config: live prod `balance_config` row `5ba76396…` v3. `validateConfig`
  accepts a type living in a `dropPool` tier different from its
  `rarityByType` tier — the seam Option H uses. Known drift: prod
  `rarityByType.WRONG_TURN = RARE` (defaults say UNCOMMON) and
  `SNEAKY_SWAP` the mirror image.

## API contract

**No new or changed endpoints.** The `dropOdds` block of
`GET /races/:id/progress` keeps its exact shape
(`{ configVersion, position, totalParticipants, rarity, byType? }`); only the
*value* of `position` (and consequently `byType` weights) can differ when a
player's raw and boosted ranks diverge. `rarity` still sums to 1.0 ± 0.01, so
the frozen odds sheet keeps rendering. `byType` keys are existing powerup
types only.

Older app versions: fully compatible. No client change is required at all;
this ships with zero app release.

Error cases: unchanged (`MysteryBoxOpenError` paths untouched).

## Data model / migration

Prisma migration on `race_participants`:

```sql
ALTER TABLE race_participants ADD COLUMN raw_steps INTEGER; -- nullable
```

- Prisma model field: `rawSteps Int? @map("raw_steps")`. No index —
  `raw_steps` is never a query predicate; reviewers should not add one.
- **No backfill.** `NULL` means "no writer has persisted since deploy"; every
  reader falls back to `totalSteps` (exactly today's behavior). Rows heal on
  the next persist of each active race; finished races never need it.
- **Write path — ALL FOUR writers** (architect item 1):
  add `updateStepTotals(id, { totalSteps, rawSteps })` to the model and keep
  `updateTotalSteps` as a thin wrapper (callers spread the model —
  `computeRaceState.js:38`, `reconcileUploaderRaces.js:152` — so a silent
  signature change is easy to miss). Then:
  1. Legacy replay persist `getRaceProgress.js:488-495` — `rawSteps` from
     `participantStepsMap`.
  2. v2 worker: extend the capture record to
     `{ kind: "participantTotal", participantId, totalSteps, rawSteps }`
     (`computeRaceState.js:38-41` — an uncaptured write "escapes the
     worker's fence") and include `rawSteps` in the fenced replay's `data`
     (`raceResolutionQueueV2.js:212-216`). No new writer, no request-path
     bulk write — reuse the existing fenced loop and its ascending-userId
     ordering.
  3. Upload reconcile `reconcileUploaderRaces.js:152` — `baseAdjusted` is in
     scope at line 160.
- **Frozen participants** (architect item 3): `rawOf` mirrors `totalFor`
  (`getRaceProgress.js:655-656`) — finished/forfeited rows keep their last
  persisted `raw_steps` and are never advanced by the replay (the persist
  loop already skips frozen rows at `:490`; the worker path must skip them
  identically).
- Read rule — **all-or-nothing per RACE, never per row** (analyst R1): if
  **any** accepted participant in the race has NULL `raw_steps`, use
  `totalSteps` for **every** participant in that race; only when all rows are
  healed does the race switch to raw. A per-row mix would rank a healed
  player's raw steps against an unhealed player's boosted total and hand out
  unearned trailing odds (reachable via mid-race joiners or a partially
  failed persist).
- Persist monotonically (analyst S1): `rawSteps = max(existing, baseAdjusted)`
  — re-syncs can rewrite `step_samples` downward and position must not drift
  backward. Do NOT reuse the deprecated `max_box_progress_steps` column for
  this (`racePowerupStateSync.js:113-116` — no longer read, values stale).

## Backend implementation path (in order)

1. **Migration** (above). Deploy-safe: nullable column, no reads yet.
2. **Model** `src/modules/races/models/raceParticipant.js` — add
   `updateStepTotals`, keep `updateTotalSteps` as a wrapper (see data-model
   section).
3. **All four persist sites** write `rawSteps` (see data-model section:
   legacy replay, v2 capture record + fenced replay, upload reconcile), each
   with the monotonic `max()` rule and frozen-row skip.
4. **Shared position helper** (architect suggestion, adopted as REQUIRED
   here): extract `rawPositionFor({ participants, race, userId })` — the
   solo sort / team sums over **persisted** `rawOf(p)` with the per-race
   all-or-nothing NULL fallback — rather than copy-pasting the sort. Extend
   the structural guard
   (`test/services/teamOnlyCtxStructuralGuard.test.js:26-50`) to assert all
   THREE roll/disclosure sites (open, reroll, dropOdds) derive position from
   this one helper.
5. **Roll position** `openMysteryBox.js:132-149` and **reroll**
   `rerollMysteryBox.js:258-295` — use `rawPositionFor` over the persisted
   participant rows they already load (`findAcceptedByRace`,
   `raceParticipant.js:100-108`). **Do NOT touch** `buildRollContext`'s
   `stepTotals` / `myTotalSteps` inputs: `isStepLeader` / `isStepLast` stay
   on effect-sensitive `totalSteps` so the RED_CARD / SECOND_WIND drop
   exclusions keep matching their use-time checks (analyst requirement,
   economy.md §8 H).
6. **Disclosure position** `getRaceProgress.js` `buildDropOdds` — the SAME
   `rawPositionFor` over the SAME source: **persisted participant rows**
   (already in scope in `buildViewerResponse`, `getRaceProgress.js:1107,
   1251-1265`) — never live-replay or snapshot `baseAdjusted`, which can
   lead the column by a replay cycle and make the quoted odds disagree with
   the actual roll exactly in the manipulated case (architect item 2;
   invariant documented at `powerupOdds.js:161-163`). Consequences, all
   REQUIRED:
   - **No snapshot shape change; `raceProgressSnapshot` untouched** — the
     pinned allowlist guard (`raceProgressSnapshot.js:91-104, 150-176`)
     stays green by construction, no `SCHEMA_VERSION` bump, inert with
     `REDIS_URL` unset (architect item 5).
   - `loadPersistedState` keeps `participants[].baseAdjusted: null`
     (`getRaceProgress.js:686-688`) — filling it would silently reroute the
     requester's box countdown at `:780-796` and mis-fire the box gate
     (architect item 4).
   - `ctx` step inputs stay on `totalSteps` as in step 5.
7. **Rarity stamp fix** (architect item 6 — closes a coin faucet Option H
   would otherwise open): `openMysteryBox.js:244` stamps the *rolled tier*
   onto the row, and `discardRewards.priceFor`
   (`src/modules/powerups/services/discardRewards.js:41-48`) pays off that
   stamp — so a Protein Shake rolled from `dropPool.UNCOMMON` would discard
   for 5 coins instead of 2, a faucet concentrated on trailing players
   (~51% of their drops under H; bounded by `POWERUP_DISCARD_DAILY_COIN_CAP`
   = 40/day). **Decision: stamp `config.rarityByType[type]` (canonical
   rarity) whenever it differs from the rolled tier** — both open branches
   and reroll. This also removes the tint inconsistency: clients tint, price,
   and discard the copy on one consistent ladder. (Upgrades were already
   safe: `powerupUpgrades.js:76-79` keys off `rarityByType`.)
8. **Config edit — staging first, then prod** (after 1–7 are deployed, since
   Option H amplifies the hoarding exploit if applied first — ORDER IS
   MANDATORY):
   - New `balance_config` version row containing the **complete** config
     (stored config ignores code defaults — never a partial patch row).
   - Option H exactly as specified in `docs/economy.md` §8: add
     `PROTEIN_SHAKE`, `TRAIL_MIX`, `RUNNERS_HIGH` to `dropPool.UNCOMMON`;
     `positionOdds.first = [0.52, 0.20, 0.28]`,
     `positionOdds.last = [0.30, 0.36, 0.34]`;
     `leadingDownweight = { RUNNERS_HIGH: 0.5, PROTEIN_SHAKE: 0.7, TRAIL_MIX: 0.7 }`;
     `trailingDownweight = { WRONG_TURN: 0.2, LEG_CRAMP: 0.25, PINECONE_TOSS: 0.4, DETOUR_SIGN: 0.4, SNEAKY_SWAP: 0.5, CLEANSE: 0.5, MIRROR: 0.5 }`
     (STEALTH_MODE removed from trailingDownweight); `leaderExcluded` /
     `lastPlaceExcluded` / `rarityByType` / `typeWeights` / prices otherwise
     unchanged. Never set any down-weight such that a tier's total weight can
     reach 0 — `drawWeighted` falls back to a uniform pick and inverts the
     nerf (`powerupOdds.js:226`).
   - Reconcile drift in the same row: `rarityByType.WRONG_TURN → UNCOMMON`
     (upgrade ladder 195 → 130 coins, player-favorable);
     `SNEAKY_SWAP → RARE` (130 → 195 — approved by user 2026-08-09). Note:
     `upgradeCost` is evaluated at purchase time from `rarityForType`, so
     already-held rows are unaffected; WRONG_TURN's move matches what the
     drop tier already stamps on rows, so only the upgrade ladder moves.
   - `validateConfig` must return `[]`; run the seeded Monte Carlo guard.
   - Rollback: repoint to the previous config version row (existing kill
     switch — clearing the four positionRules lists — also still works).

## Frontend plan

**No frontend changes.** The odds sheet, box open flow, and race screens are
entirely server-driven for these values; a missing/absent field situation
cannot arise because the payload shape is unchanged. iOS and Android are
affected identically (server-side only). The rarity-stamp fix (step 7) means
boosted commons rolled from the UNCOMMON tier are stamped, tinted, priced,
and discarded consistently as COMMON — no tint inconsistency remains.

**Accepted frozen-client UX consequence** (architect item 8): the shipped
odds sheet renders `Position ${position} of ${totalParticipants}` from
`dropOdds.position` (`lib/widgets/odds_sheet.dart:402-403`). Whenever a
player's raw and boosted ranks diverge, every shipped binary will show an
odds-sheet position that contradicts the leaderboard next to it. This is the
feature working as intended (your odds follow your walking, not your buffs);
accepted as-is, with a copy tweak ("based on steps walked") as an optional
follow-up in the next app release. No mirrored surfaces affected: `dropOdds`
appears only in `race_detail_screen.dart`, `case_opening_screen.dart`,
`multi_case_opening_screen.dart`, `odds_sheet.dart`; no tutorial/demo
fixture fabricates it, so the sheet simply hides there.

No UI element is added, moved, resized, or removed → `ui-test-planner` not
required for this spec.

## Backward-compat & rollout

- Deploy order: **backend deploy (steps 1–7) → verify → config edit staging →
  verify → config edit prod (step 8).** No app release involved; frozen
  clients on every version see only different odds numbers in an unchanged
  payload.
- The new column is nullable and unread by old code; a rollback of the code
  deploy leaves a harmless extra column.
- Behavior before first replay persist of a race: `raw_steps` null → position
  falls back to `totalSteps` → exactly today's behavior (degrades to the
  status quo, never worse).
- Redis down: persisted-columns path uses the new column with the same
  fallback; no new Redis dependency.
- Step inflation: Option H injects ~+45% more self-boost steps per race
  (economy.md §8). Accepted by design intent (catch-up); revisit only if
  `target_steps` races finish noticeably fast — trim `positionOdds`
  COMMON/UNCOMMON mass, no code change.

## Test plan (tests written FIRST, integration-first)

Backend `test/integration/` (real HTTP + test DB — confirm `DATABASE_URL` is
the test DB; run `test:integration`, never bare `npm test`):

1. **Raw-position roll:** seed a 3-player race where player A has the highest
   `totalSteps` purely via `bonusSteps`/buff effects but the lowest raw
   walked steps; open a mystery box as A with an injected roll seam and
   assert the roll was performed at last-place position. DI mechanics: build
   the app with
   `createRacesRouter({ openMysteryBox: buildOpenMysteryBox({ rollPowerupOdds: spy }) })`
   (`routes.js:117-160`) — the spy captures `position` while the request
   still exercises the real route/handler chain.
2. **Disclosure parity:** same seed; `GET /races/:id/progress` for A asserts
   `dropOdds.position === 3` (raw last) while the leaderboard shows A first —
   and `dropOdds.position` equals the position the roll in test 1 actually
   used (architect item 2), on the replay, snapshot-served, and
   persisted-fallback paths.
3. **Null fallback:** (a) `raw_steps` NULL for all rows → open + progress
   behave exactly as today (position from `totalSteps`); no crash, no shape
   change. (b) **Partial heal (analyst R1):** one participant NULL, others
   populated → the ENTIRE race still ranks on `totalSteps` for every
   participant (no raw-vs-boosted mixed comparison).
3b. **Reroll raw-position (analyst R3):** mirror of test 1 through the real
   reroll route — a bonus-inflated `totalSteps` leader with lowest raw steps
   rerolls at last-place position.
4. **Team race:** team position computed from summed raw steps; a team
   leading only via bonus steps rolls as trailing.
5. **Exclusion predicates unchanged:** a raw-trailing player who is
   `totalSteps` step-leader still cannot roll SECOND_WIND/RED_CARD
   (leaderExcluded keyed off `isStepLeader` on `totalSteps`).
6. **All writers persist raw_steps:**
   (a) legacy replay path (Redis flag OFF): after a progress replay the
   column equals the replay's `baseAdjusted` per participant;
   (b) **v2 worker path (the PROD config — architect item 7):** with
   `redisStandingsEnabled` ON against local test Redis, assert the worker
   writes `raw_steps` under its fence and that snapshot-served `/progress`
   and a real open agree on position;
   (c) upload-reconcile path writes it;
   (d) the whole suite stays green with `REDIS_URL` unset;
   (e) extend `test/integration/race-queue-v2-single-writer.test.js` so the
   new column adds ZERO request-path participant writes;
   (f) monotonicity: a downward re-sync of samples never lowers `raw_steps`;
   (g) frozen participants: a finished player's `raw_steps` stops advancing
   and their `rawOf` mirrors `totalFor`.
6b. **Discard payout (step 7):** a Protein Shake rolled from the UNCOMMON
   tier discards for the COMMON price (2 coins, not 5) and the row is
   stamped COMMON.
7. **Config guard (unit-tier, structural):** Option H candidate config passes
   `validateConfig` with `[]`; no tier's weight sum can hit 0 at any
   normalized position in {0, 0.25, 0.4, 0.5, 0.6, 0.75, 1} (0.4/0.6 are the
   `leadingDownweightFrom`/`trailingDownweightFrom` ramp endpoints — analyst
   S2); seeded Monte Carlo guard stays green.
8. All existing roll/disclosure structural-guard and odds tests stay green
   with zero weakened assertions.

## Acceptance criteria / definition of done

- Opening, rerolling, and the quoted odds all derive position from raw walked
  steps with the NULL fallback; all three progress serving paths agree.
- Banking/hoarding scenario (test 1/2) provably yields leader odds for a
  raw-leader regardless of held boxes/powerups.
- Full integration suite green; no existing assertion weakened.
- Option H config live on staging, validated, then prod; `docs/economy.md`
  §8 marked APPLIED with the config version id.
- `code-reviewer` agent has reviewed the diff.

## Open questions (Phase 3)

None. (SNEAKY_SWAP reconcile direction: user approved 130 → 195 on
2026-08-09.)

## Revision log

- Draft 1: initial spec from economy.md §8 + code exploration.
- Architect review (REVISE, 2026-08-09), all 8 REQUIRED items folded in:
  (1) `raw_steps` written by ALL FOUR total writers — the v2 worker's
  capture-record/fenced-replay path (the prod configuration) and the
  upload-reconcile path, not just the legacy replay persist, correcting a
  false "worker shares the replay persist" claim in Current reality;
  (2) roll AND disclosure pinned to the persisted rows via one shared
  `rawPositionFor` helper + extended structural guard; (3) frozen-row
  `rawOf`-mirrors-`totalFor` rule; (4) `loadPersistedState` keeps
  `baseAdjusted: null` (box-countdown protection); (5) explicit "no snapshot
  shape change" so the allowlist guard holds by construction; (6) rarity
  stamp fix — canonical `rarityByType` stamped when tier and rarity
  disagree, closing the 5-vs-2-coin discard faucet H would open; (7) test
  plan covers the Redis-ON worker path, REDIS_URL-unset, single-writer
  guard extension; (8) frozen-client odds-sheet position/leaderboard
  contradiction recorded as accepted UX. Suggestions adopted: DI mechanics
  for test 1, `updateStepTotals` + wrapper, Prisma field note, no-index
  note, settlement-untouched non-goal, held-rows-unaffected pricing note.
- Gap pass 1: added the mandatory ordering (code fix before config edit —
  Option H amplifies hoarding if applied alone); pinned the "ctx step inputs
  stay on totalSteps" rule to both roll and disclosure sites symmetrically;
  added the persisted-fallback serving path to the disclosure step and test
  2; added complete-row config trap (stored config ignores code defaults) and
  the zero-weight uniform-fallback trap; noted batch open inherits via
  delegation.
- Game-analyst review (SOUND WITH CHANGES, 2026-08-09): R1 per-race
  all-or-nothing NULL fallback (no raw-vs-boosted mixed ranking); R2 roll and
  disclosure pinned to the same persisted `raw_steps` source on all serving
  paths; R3 reroll integration test added; S1 monotonic max() persist +
  do-not-reuse `max_box_progress_steps`; S2 ramp-endpoint sweep positions.
  Confirmed H alone (E declined) stays sound; box volume remains the dominant
  snowball term — future axis if complaints persist.
- Gap pass 2: added mixed-fleet NULL-fallback test and team-race raw-sum
  test; clarified no-backfill healing behavior and rollback story; recorded
  the uncommon-stamp cosmetic on boosted commons; confirmed
  `updateTotalSteps` caller sweep before signature change; scoped
  ui-test-planner out with justification; surfaced SNEAKY_SWAP price
  direction as the single open user question.
