# Powerup activation clarity and invariants

## Summary and user story

Powerup use should communicate the committed action and its outcome without
blocking target selection, show Trail Mix's projected unique-type reward before
commit, enforce one active Leech per victim, list both shop and mystery-box
powerups in the field manual, and display Ghost Pepper as two distinct
30-minute phases.

As a racer, I can choose a target without an activation overlay covering the
picker, understand Trail Mix's reward before spending it, trust that only one
opponent can Leech me at once, learn every obtainable powerup in the manual,
and see whether Ghost Pepper is in its boost or burnout phase.

## Current-state findings

- `lib/screens/race_detail_screen.dart` calls `_showPowerupProcessing(...,
  preparing)` while fetching targeting context and before every target picker;
  the same overlay is later switched to `activating` immediately before the
  use request.
- Trail Mix already returns `result.bonus` from
  `src/modules/powerups/commands/usePowerup.js`, and its direct-impact metadata
  already records `uniqueTypes` and `perType`, but the frontend's ordinary
  success branch ignores those fields. The race-progress payload does not
  expose a pre-use count.
- Leech currently uses `LEECH_MAX_PER_VICTIM = 2`; production direct-use
  transactions lock the race and accepted participant cohort, so changing the
  invariant to one remains concurrency-safe. Tests explicitly permit a second
  distinct leecher today.
- `getPowerupCopyCatalog.js` derives availability solely from active shop rows,
  filters every non-shop row out, then stamps retained rows as both
  `{shop:true, roll:true}`. `PowerupCopy.guideEntries` correctly trusts that
  server availability, which is why the manual appears shop-only.
- Ghost Pepper already lasts 30 minutes boosted plus 30 minutes frozen and
  persists `startsAt`, `expiresAt`, `metadata.boostMs`, and `metadata.freezeMs`.
  The frontend currently displays only `expiresAt - now`, producing a single
  countdown from 60 minutes.

## Scope

1. Remove the full-screen powerup-processing overlay from all pre-commit work:
   target-context fetches, target pickers, direction pickers, and cancel paths.
   Show it only after all required choices are complete and immediately before
   the network use request starts. Keep it visible until success or failure.
2. Add an additive Trail Mix preview to race powerup data with the number of
   unique powerup types that the server would count if Trail Mix were used now.
   In the Trail Mix action sheet, show `N unique powerups × P = B bonus steps`
   for the selected tier. Include Trail Mix itself in `N`, matching use-time
   behavior. After success, show the authoritative returned count and bonus.
3. Permit at most one live Leech effect on a victim in a race, regardless of
   attacker. Reject later attempts before coins are deducted or the item is
   consumed, using a stable coded conflict. Product decision: first active
   Leech wins; a different attacker must wait until that Leech expires or is
   cleared. The user explicitly accepted this cross-attacker rule on
   2026-08-29.
4. Correct the catalog's availability model so all active, client-renderable
   shop or mystery-box-roll powerups appear in the manual. Preserve capability
   filtering and exclude container/internal or unavailable types.
5. Display Ghost Pepper's timer as two phase-local countdowns: `BOOST · 30:00`
   down to zero, then `BURNOUT · 30:00` down to zero. Use server timestamps and
   metadata; never change its scoring duration or multiplier.

## Non-goals

- No changes to powerup odds, prices, Trail Mix per-type magnitudes, Ghost
  Pepper scoring, Leech transfer ratio/duration, or catalog art.
- No new release flags or runtime toggles.
- No redesign of unrelated active-effect rows or target pickers.
- No cleanup or recomputation of historical expired effects. If production
  contains duplicate live Leech rows at deploy time, retain the earliest
  deterministic row and expire later duplicates during migration/deploy repair.

## API contract

### Existing `GET /races/:raceId/progress`

Add to the existing `powerupData` object:

```json
{
  "trailMix": {
    "uniqueTypesIfUsedNow": 4
  }
}
```

- The count is viewer-specific, Postgres-authoritative, integer, at least `1`, and includes
  `TRAIL_MIX` because use-time logic adds it before calculating the bonus.
- Query and emit it only when the viewer is accepted and currently holds a
  usable Trail Mix, avoiding an unconditional query on the hot polling path.
  Keep it out of the shared Redis progress snapshot. The preview is advisory;
  another activation may change the count before POST `/use`, and the use
  response remains authoritative. Omission remains valid.
- Old clients ignore the field. New clients talking to an old backend omit the
  preview and retain the ordinary use button; after-use messaging falls back
  to `result.bonus` or the generic activated toast.

### Existing `POST /races/:raceId/powerups/:powerupId/use`

For successful Trail Mix use, extend the existing `result` object:

```json
{
  "result": {
    "bonus": 400,
    "uniqueTypes": 4,
    "perType": 100
  }
}
```

The three fields are authoritative use-time values. `bonus` already exists;
`uniqueTypes` and `perType` become additive top-level result fields instead of
living only in direct-impact metadata.

For a Leech attempt when the target already has a live Leech:

```json
{
  "error": "This rival is already being leeched",
  "code": "LEECH_TARGET_ALREADY_ACTIVE"
}
```

Return HTTP `409`; keep the race-bound item `HELD`, refund a redeemed stash
item through the existing rejection wrapper, and deduct no coins. The check
must use only truly live effects (`ACTIVE`, unexpired at transaction time).

### Existing `GET /powerups/catalog`

Keep the response shape. Correct each entry's availability:

```json
"availability": { "shop": false, "roll": true }
```

- Set `availabilityVersion: 2` only when both shop and balance sources load
  authoritatively. If either source falls back or throws, omit availability
  fields and return the full capability-safe copy catalog.
- `shop` is true only for an active shop row on `req.releaseChannel`.
- Export a canonical helper beside `powerupOdds.eligiblePoolFor` that computes
  the union across every legal rarity, box position, solo/team mode, and the
  request's client capabilities. `roll` is true when the type survives at least
  one legal context with positive effective selection weight. Do not reuse
  `getEligiblePowerupPool`, which represents a different daily/shop catalog.
- Include a catalog row when `shop || roll`; exclude it when both are false.
- Preserve the endpoint's capability gates and stable canonical ordering.
- An availability lookup failure omits `availabilityVersion` and returns the
  full capability-safe copy catalog, preserving the current fail-open contract.

### Existing progress response: Ghost Pepper viewer overlay

The current public effect serializer strips `startsAt` and `metadata`. Add only
these allowlisted fields to viewer-visible Ghost Pepper rows:

```json
{
  "startsAt": "2026-08-29T14:00:00.000Z",
  "phaseDurations": { "boostMs": 1800000, "burnoutMs": 1800000 }
}
```

Do not expose raw effect metadata. Attach the fields in the per-viewer overlay
after shared snapshot hydration so they never enter the shared Redis snapshot.
Frontend parsing validates ISO timestamps and positive bounded integers;
missing/malformed fields fall back to the legacy total-remaining countdown.

## Data model and repair

No schema column is required.

Add a narrowly scoped idempotent repair command (not a Prisma migration) that
finds live Leech rows grouped by
`(race_id, target_participant_id)`, keeps the earliest by `starts_at, id`, and
marks all later rows `EXPIRED` with `expires_at = LEAST(expires_at, now())`.
The repair uses one cutoff timestamp, reports affected race/victim/effect IDs,
and touches no other type. Per race it serializes against request writers and
defers any race that could concurrently settle unless an explicitly authorized
quiescence procedure makes it safe. It preserves/finalizes active-impact
boundaries, invalidates race-progress cache, and enqueues a fresh C0 resolution
generation after commit. Run audit → apply → zero-duplicate post-audit.
Production apply requires separate explicit live-data-repair authorization.
Never run integration tests against production.

The runtime invariant remains enforced in the race-locked use transaction; a
database partial unique index is not used because liveness depends on both
status and wall-clock expiry.

## Backend implementation plan

1. Tests first in the dedicated integration database:
   - progress returns the viewer-specific Trail Mix count and isolates users;
   - Trail Mix use returns `bonus`, `uniqueTypes`, and `perType`;
   - one live Leech rejects a distinct second attacker with coded `409`, no
     consumption/coin deduction; expired/non-active Leech does not block;
   - concurrent Leech attempts serialize and leave exactly one live row;
   - catalog returns shop-only, roll-only, both, and neither correctly while
     preserving capability gates and availability-failure fallback;
   - repair command is dry-run-safe, idempotent, and touches only duplicate live
     Leech rows.
2. Reuse `RacePowerup.findUsedTypesByParticipant` for the preview and centralize
   the `+ TRAIL_MIX` count calculation so preview and use cannot diverge.
3. Set the Leech victim cap to one, use a stable error code, filter by live
   status/expiry, and update stacking-guide copy plus frontend fallback copy.
4. Build roll availability from the exported canonical union helper; do not
   duplicate a stale hardcoded list in the query.
5. Thread release channel through route/query DI. Bump the default-off catalog
   Redis key namespace and include release channel plus capability variants.
   Invalidate all variants after copy, shop-item, balance save, and rollback
   mutations. Redis failure/unset always falls back to Postgres.
6. Deploy and verify cap-one code on both production HTTP workers first. Then,
   only with separate repair authorization, run audit/apply/post-audit. This
   prevents an old worker recreating a second Leech after cleanup.

## Frontend implementation plan

1. Tests first by pumping the real race detail screen and guide sheet.
2. Delete the `preparing` overlay phase and all pre-picker overlay calls. Keep
   target loading inside the existing picker/sheet surface if feedback is
   needed; the full-screen processing overlay begins only after selection.
3. Add a compact Trail Mix calculation plate beneath its description. For each
   tier, use the selected tier label/magnitude and the server count. If the
   count is absent/malformed, hide the plate rather than guessing. On success,
   parse result numbers defensively and show `Trail Mix: N unique powerups ·
   +B steps`; fall back safely when fields are absent.
4. Keep the manual's existing visual language and scroll behavior. Once the
   corrected catalog arrives, render all entries where either availability bit
   is true. Add small `BOX`, `SHOP`, or `BOX + SHOP` source chips so the expanded
   list explains acquisition rather than looking accidental.
5. Add a shared defensive Ghost Pepper phase formatter used by the personal
   active-effects row and team-card tooltip countdown. During boost, calculate
   `startsAt + boostMs - now`; during burnout, calculate `expiresAt - now`.
   Label both phase and remaining time. Legacy/malformed rows use the existing
   total countdown.
6. Verify iOS and Android layouts at 320/390/430 widths, large text, light/night
   themes, reduced motion, solo/team races, and tutorial/demo mirrors.

## Backward compatibility and rollout

- Deploy backend first. Old apps ignore additive progress/use/catalog fields.
- Correct catalog availability only changes a new guide-capable client's
  catalog contents. Already-shipped guide-capable clients immediately receive
  expanded entries after backend deploy but ignore new source fields; frozen
  clients without the guide capability retain their historical contract.
- Catalog Redis is default-off. V2 keys are release-channel/capability scoped,
  stale V1 keys cannot serve V2 semantics, Redis tests use only local db15, and
  Redis-unset behavior is covered separately.
- The stricter Leech rejection is safe for old clients: they already render
  server errors and retain/refund rejected items through existing behavior.
- Frontend requires no new field for correctness. Missing Trail Mix preview or
  Ghost Pepper metadata degrades to current behavior without crashing.
- No feature flag. The permanent invariant and additive contracts ship
  directly.

## Test plan

### Backend

- Real HTTP integration coverage for progress, use, rejection, catalog, and
  caller isolation against `steps-tracker-integration_test`.
- Simultaneous real-HTTP activations proving exactly one success, one coded
  `409`, one live effect, and unchanged item/coin state for the loser.
- Structural/source test ensuring catalog roll availability imports canonical
  eligibility logic rather than maintaining a second type list.
- Repair integration tests against the dedicated test database, including
  repair-vs-use, deferred settlement-risk races, cache invalidation, boundary
  finalization, and idempotence.
- Catalog matrix for prod/TestFlight isolation, stale-key immunity, old parser
  compatibility, local Redis db15, and Redis unset.
- `npm run test:unit`; relevant integration suites; never bare `npm test`.

### Frontend

- Target picker opens with no `powerup-processing-overlay`; cancelling never
  shows it; confirming shows `ACTIVATING` only while the use future is pending.
- Trail Mix sheet renders exact base and upgraded calculations from server
  count, hides malformed/absent preview, and success uses authoritative values.
- Manual shows representative roll-only and shop-only entries with source chips
  and keeps both tab scroll positions on narrow/large-text screens.
- Ghost Pepper row and team tooltip count 30→0 for boost, then 30→0 for burnout;
  malformed metadata falls back without exception.
- Existing protected assertions remain intact.
- `flutter analyze` and focused/full relevant widget tests pass.

## Acceptance criteria and definition of done

- No full-screen activation overlay appears before a targeting/direction choice
  is committed.
- Trail Mix visibly explains its projected unique count and bonus before use,
  and confirms the authoritative count/bonus after use.
- At most one live Leech exists per victim per race, including concurrent use;
  production duplicate live rows are repaired and audited to zero.
- The manual includes every capability-visible powerup obtainable from the shop
  or mystery boxes and labels its source.
- Ghost Pepper visibly runs two separately labeled 30-minute countdowns without
  changing scoring.
- Frontend analysis is clean; required integration/widget tests pass; architect,
  game analyst, UI test planner, and final code reviewer gates are complete.

## Manual UI-placement test plan

1. Ordinary target picker and Bounty: no overlay during loading, selection,
   cancel, or back; one `ACTIVATING` overlay only after target commitment.
2. Quicksand, Pinecone Toss, and Sneaky Swap: specialized picker/context paths
   follow the same timing.
3. Team race enemy-only target and direction paths follow the same timing.
4. Stash redemption retains its row-level busy state, but no full-screen
   overlay appears until a final choice is committed.
5. Trail Mix plate sits below its description, updates for base/upgraded tiers,
   authoritative success appears once, and malformed/old preview leaves no gap.
6. Manual shows shop-only, box-only, and dual-source entries once in canonical
   order with one source chip; both tab scroll offsets remain independent.
7. Solo Ghost Pepper shows one row counting `BOOST` 30→0 then resetting to
   `BURNOUT` 30→0; malformed data yields one legacy countdown.
8. Team Ghost Pepper tooltip stays anchored/in-bounds with the same phase-local
   countdown and fallback.
9. Demo Shortcut beat keeps the picker unobscured, coach/spotlight aligned, and
   starts activation only after CapyBot is accepted.
10. Demo single-box opening uses the expanded shared manual and returns to the
    correct beat; multi-case opening is verified unaffected.
11. Tab tutorial POWERUPS spotlight stays aligned and no new UI appears without
    corresponding fixture data.
12. Repeat items 5–8 at 320/390/430 widths, largest text, light/night,
    iOS/Android, and reduced motion.

Mirror decisions: `demo_race_api_service.dart` preserves target-use timing and
no-network behavior; `demo_race_engine.dart` and `tutorial_preview_data.dart`
need no Trail Mix/Ghost Pepper fixture unless the tutorial is intentionally
expanded, but explicit absence tests are required; `demo_auth_service.dart`
and `tutorial_real_screens.dart` are verified unchanged; existing
`tutorialPowerupsKey` and coach spotlight anchors remain on the POWERUPS block.

## Revision log

- Draft: mapped the existing activation overlay, Trail Mix result path, Leech
  cap/locking, catalog availability bug, and Ghost Pepper metadata/countdown.
- Gap pass 1: added pre-use and authoritative post-use Trail Mix contracts,
  malformed-field fallbacks, source chips, and explicit old-client behavior.
- Gap pass 2: added concurrent Leech enforcement, production duplicate repair,
  canonical roll-eligibility reuse, phase-local Ghost Pepper fallback behavior,
  and integration-level proof requirements.
- Architect review: replaced the nonexistent raw Ghost Pepper metadata contract
  with an allowlisted viewer overlay; pinned roll-union semantics,
  release-channel/cache isolation, conditional Trail Mix polling, safe post-
  deploy Leech repair ordering, and real-HTTP concurrency proof.
- Game analyst review: recorded zero direct economy delta and the cap-one
  protective slot-lock risk; the user explicitly accepted first-active-wins
  across different attackers.
- UI test planner: added the 12-point placement checklist and mirror decisions.
