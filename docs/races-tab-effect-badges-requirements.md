# Races-tab active effect badges — requirements

## Summary & user story

As a racer scanning **Races tab** (nav bar), I want each of my ACTIVE races to
show at a glance whether anything is currently boosting or hurting me, so I know
which race needs attention without opening every detail screen.

Today the races list (`lib/screens/tabs/races_tab.dart` `_buildRaceRow`,
~line 1331) shows name, time left, team scoreline, and my powerup inventory
slots — but nothing about effects on me. Effect data exists only in
`GET /races/:raceId/progress` (`powerupData.activeEffects`), which the list must
NOT call per race (the 2026-07-17 perf build explicitly killed the /races N+1;
see `getRaces.js` Phase B2/B3 comments).

This pairs with the just-shipped race-detail redesign that splits ACTIVE
EFFECTS into BOOSTS / DEBUFFS groups (`race_detail_screen.dart`
`_buildActiveEffectsSection` + `_effectIsBoost`). The list shows the *summary*;
tapping the row opens the detail screen with the full grouped breakdown.

## Scope / non-goals

**In scope**
- Additive `myActiveEffects` field on ACTIVE race summaries in `GET /races`.
- Compact boost/debuff badge cluster on ACTIVE race rows in the races tab.
- Shared frontend polarity helper so list and detail classify identically.

**Non-goals**
- No badges on PENDING/COMPLETED rows (effects only exist while ACTIVE).
- No change to the home-tab race card (`getHomeRaceCard.js`) — follow-up if
  wanted.
- No attacker names on the list (the list summary has no participant roster to
  resolve `sourceUserId` → displayName; names live on the detail screen).
- No change to `GET /races/:raceId/progress` or the detail screen.
- No new push/polling behavior; badges refresh whenever the list refreshes.

## API contract

### `GET /races` — additive field per ACTIVE summary

Backend: `/Users/rohan/repos/stepv2-backend/src/modules/races/queries/getRaces.js`
(route `src/modules/races/routes.js:275`).

```jsonc
// inside each entry of "active" (never on "pending"/"completed"):
{
  "id": "…",
  "slotItems": [...],
  // NEW — effects currently targeting the viewer in this race, createdAt-asc.
  // Present only when status==ACTIVE && powerupsEnabled && viewer is a
  // participant; otherwise omitted entirely (matches slotItems' powerupContext).
  "myActiveEffects": [
    {
      "type": "LEG_CRAMP",          // powerup type, post feature-gating (below)
      "sourceUserId": "u_attacker", // null possible on legacy rows
      "expiresAt": "2026-07-24T01:00:00.000Z" // null => until-used/untimed
    }
  ]
}
```

Notes:
- `onSelf`/`targetUserId` are NOT included: every row targets the viewer by
  construction, so they carry no information. Polarity is derived from
  `sourceUserId` + type (see Frontend plan).
- `id` is NOT included: the list never acts on an individual effect.

### Feature-token gating (mirror of `getRaceProgress.js:611-655`)

The same `X-Client-Features` downcast/withhold rules apply, so the list never
sends a type the binary can't render:
- no `powerups3` → withhold `HITCHHIKE`;
- no `powerups4` → `QUICKSAND` downcasts to `LEG_CRAMP`;
- no `powerups5` → withhold `GHOST_PEPPER`, `COIN_FLIP`, `DECOY`, `UMBRELLA`,
  `PIGGY_BANK`, `DRILL_SERGEANT`, `BOUNTY`; downcast `POWER_OUTAGE`→
  `SIGNAL_JAMMER`, `UPRISING`/`RALLY_FLAG`→`RUNNERS_HIGH`.
- `HIDDEN_FROM_OPPONENTS` filtering does NOT apply — every row already targets
  the viewer, and the progress endpoint likewise always shows the viewer their
  own effects.

Route change: `getRaces(userId, supportsTeamRaces)` grows a third parameter —
an options object `{ clientFeatures }` (or individual booleans) passed from
`req.clientFeatures` at `routes.js:275`. Default = no tokens (old clients get
maximally-downcast types, which is safe because old clients also ignore the
field entirely).

### Error cases

None new — the field rides the existing `GET /races` 200. A failure to load
effects must not fail the list; there is no partial-error state (the effects
come from the same transaction-free reads as the rest of the summary).

### Backward compatibility (rule #1)

- **Old app + new backend:** `myActiveEffects` is additive; frozen binaries
  never read it. Verified pattern: `slotItems`, `myPlacementHidden`, `teams`
  were all shipped exactly this way in this file.
- **New app + old backend:** the field is absent → the frontend reads it with
  `(race['myActiveEffects'] as List?) ?? const []` and renders no badges. No
  crash, no layout shift (the badge cluster is conditionally built).
- Deploy order: backend first, then app. No kill switch needed — the field is
  read-only, additive, and invisible until the new binary rolls out.

## Data model / migrations

**None.** `RaceActiveEffect` already holds everything
(`targetParticipantId`, `targetUserId`, `sourceUserId`, `type`, `status`,
`expiresAt`). No new tables, columns, or backfill.

### Query budget (hard requirement)

`GET /races` currently makes exactly **two** bulk prefetch queries regardless
of race count (`getRaces.js:98-113`), pinned by
`test/queries/getRacesQueryCount.test.js`. This feature must NOT add a third:

- Replace `RaceActiveEffect.findActiveByTypeForParticipants(ids, "DETOUR_SIGN")`
  with a new bulk model method
  `RaceActiveEffect.findActiveForParticipants(participantIds)`
  (`targetParticipantId IN …, status: "ACTIVE", orderBy createdAt asc` — the
  all-types generalization of the existing method in
  `src/modules/powerups/models/raceActiveEffect.js:28`).
- Derive BOTH consumers from that one result set: the Detour mask becomes
  `rows.filter(type === "DETOUR_SIGN")`; `myActiveEffects` is the rows grouped
  by `targetParticipantId`.
- Keep the capability-detected fallback path (`getRaces.js:114-134`) working
  for minimal test fakes: detect `findActiveForParticipants`; if absent, fall
  back to the existing per-participant `findActiveForParticipant` /
  `findActiveByTypeForParticipant` methods.
- If `getRacesQueryCount.test.js` pins the *specific* query shapes rather than
  the count, do NOT edit it silently — surface it (house rule: never modify
  existing tests to make things pass).

## Frontend plan

### Shared polarity helper (new file `lib/utils/effect_polarity.dart`)

Extract the classification that race detail now uses so both surfaces can never
disagree:

```dart
/// Boost = self-cast (sourceUserId == me), unattributed (null/empty source),
/// or a group rally that lands on you as a buff even when a rival/teammate
/// cast it. Everything else from another racer is a debuff.
bool effectIsBoost({
  required String? type,
  required String? sourceUserId,
  required String? myUserId,
})
```

**The progress payload's `onSelf` flag MUST NOT be consulted** — the backend
sets `onSelf: e.targetUserId === userId` (`getRaceProgress.js:651`), so it is
true for EVERY row targeting the viewer, rival attacks included. (Found live
2026-07-23: a rival-cast Rainstorm rendered under BOOSTS because the first
detail-screen implementation short-circuited on `onSelf`.) Classification is
source-based only.

`race_detail_screen.dart` `_effectIsBoost` (line ~4252) becomes a thin wrapper
delegating to this helper — dropping its current `onSelf` short-circuit, which
is the bug above. The `{UPRISING, RALLY_FLAG}` group-boost set lives only in
the helper.

### Races tab (`lib/screens/tabs/races_tab.dart` `_buildRaceRow`)

- Read defensively:
  `final myEffects = (race['myActiveEffects'] as List?)?.whereType<Map>().toList() ?? const [];`
- Only the `status == 'ACTIVE'` branch renders badges (the field only exists
  there anyway).
- Count `boosts` / `debuffs` via the shared helper
  (`myUserId` = `widget.authService.userId`, same accessor the tab already
  uses).
- Render a mini effect-icon cluster on the time-left line, right of `timeLabel`
  (owner decision 2026-07-23: sprites over arrow-count chips; kept on the same
  line to preserve list density):
  - each effect renders its real sprite (`PowerupIcon`, size 14) centered on an
    18×18 tinted plate — `palette.feedBoost` for boosts, `palette.feedAttack`
    for debuffs (bg alpha 0.15, border alpha 0.35, radius 5) — so polarity
    stays readable even when the sprite is unfamiliar;
  - order: boosts first, then debuffs (matches the detail screen's BOOSTS-above-
    DEBUFFS grouping), createdAt-asc within each group (payload order);
  - at most 3 plates render; overflow collapses into a `+N` text chip
    (PixelText.title 10, `palette.textMid`) so the row never wraps;
  - zero effects renders nothing at all (no reserved space, no layout shift
    vs. today).
- All colors via `AppColors.of(context)` — dark mode flips for free (same
  tokens the detail redesign uses).
- States: no loading/error states of their own — the chips are derived from the
  already-loaded list payload. Missing field (old backend) = no chips.
- iOS + Android: pure shared Dart; nothing platform-specific.

## Backward-compat & rollout

1. Deploy backend (additive field; old clients unaffected; query count
   unchanged so no perf regression for any client).
2. Ship app build (frontend renders chips when the field is present).
3. No `testOnly`/flag gating required. During phased App Store rollout, frozen
   binaries hit the new backend and ignore the field; the new binary against a
   not-yet-deployed backend (staging drift) shows no chips and nothing breaks.

## Test plan (tests FIRST, before business logic)

Backend (`test/integration/`, run with `test:integration`, never bare
`npm test`, never prod DB):
1. `GET /races` for a user in an ACTIVE powerup race with (a) a self-cast
   RUNNERS_HIGH and (b) a rival-cast LEG_CRAMP on them → `myActiveEffects` has
   exactly both rows with correct `type`/`sourceUserId`/`expiresAt`; a rival's
   effect on a *third* racer does not appear.
2. Field omitted for: PENDING and COMPLETED summaries, powerups-disabled
   races, and races where the viewer left/declined.
3. Feature gating: rival-cast QUICKSAND appears as `LEG_CRAMP` without
   `powerups4`, as `QUICKSAND` with it; `BOUNTY` withheld without `powerups5`;
   `UPRISING` downcasts to `RUNNERS_HIGH` without `powerups5`.
4. Detour regression: `myPlacementHidden` still true with an ACTIVE
   DETOUR_SIGN on the viewer (the mask now derives from the shared bulk query).
5. Existing `getRacesQueryCount.test.js` still green (query budget unchanged).

Frontend (widget tests pumping the real `RacesTab`, pattern of
`test/races_tab_featured_tournament_test.dart`):
6. Active row with 2 boosts + 1 debuff (incl. rival-cast UPRISING → boost) →
   3 `PowerupIcon` plates render, boosts before debuffs, with the right
   boost/debuff tints.
7. `myActiveEffects` absent → no plates, row identical to today.
8. 5 effects → exactly 3 plates + a `+2` overflow chip; 3 effects → no chip.
9. Detail-screen parity: `effectIsBoost` helper unit cases for the
   {UPRISING, RALLY_FLAG} set + null/empty source (this is the pure-function
   exception where a unit test is the right tool), plus the existing
   `race_detail_active_effects_groups_test.dart` still green after the
   refactor to the shared helper.
10. Regression (live bug 2026-07-23): a rival-cast RAINSTORM row carrying
    `onSelf: true` — the shape the real backend sends for every row targeting
    the viewer — classifies as a DEBUFF on the detail screen. Added as a new
    case in `race_detail_active_effects_groups_test.dart` (new-this-feature
    test file; existing cases must not be altered).

## Acceptance criteria / definition of done

- [ ] `GET /races` ACTIVE summaries carry `myActiveEffects` per contract;
      pending/completed never do.
- [ ] Query count for `GET /races` unchanged (existing count test green).
- [ ] Detour placement masking behavior unchanged.
- [ ] Races tab shows ↑/↓ chips per design; nothing renders when the field is
      absent or empty.
- [ ] List and detail classify every type identically (shared helper; no
      duplicated boost-set).
- [ ] All new tests written first and passing; no existing test modified.
- [ ] `flutter analyze` clean on touched files; both platforms build.

## Revision log

**Gap pass 1**
- Pinned the query-budget rule as a hard requirement with the concrete
  fold-Detour-into-one-query plan; first draft added a third bulk query, which
  would violate the perf build's invariant and its count test.
- Dropped `onSelf`/`targetUserId`/`id` from the contract (always-true /
  redundant / unused) and documented why.
- Added feature-token downcast/withhold rules — first draft sent raw types,
  which can put an unrenderable type (e.g. BOUNTY) in front of a
  powerups5-less binary that *does* read the new field (future binaries won't
  all support future waves).
- Made explicit that attacker names are impossible on the list (no roster in
  the summary payload) → moved to non-goals instead of leaving it ambiguous.

**Gap pass 2**
- Specified the capability-detected fallback path for injected test fakes
  (`getRaces.js:114-134` pattern) — pass 1's single-query plan silently broke
  the legacy-fake branch.
- Added Detour regression test (#4): folding the mask into the generalized
  query changes its data source, which pass 1 left untested.
- Nailed chip placement to the time-left line with a no-layout-shift rule and
  the a-zero-count-chip-is-not-rendered rule (pass 1 said "compact cluster"
  without a location, an ambiguity an implementer would have to guess).
- Required `getRaces` to keep omitting the field (not `[]`) outside
  powerupContext, matching `slotItems` semantics exactly, so snapshot-style
  clients never see a shape change on old races.
- Clarified route plumbing for `clientFeatures` (third param at
  `routes.js:275`) — pass 1 mirrored the progress gating without saying where
  the tokens come from in this code path.

**Live-bug correction 2026-07-23 (post-approval)**
- Owner screenshot showed a rival-cast Rainstorm under BOOSTS on the detail
  screen. Root cause: the payload's `onSelf` means "targets the viewer," not
  "self-cast," so the classifier's `onSelf` short-circuit marked every effect
  on the viewer a boost. Helper signature loses the `onSelf` parameter;
  classification is source-based only; regression test #10 added. The locked
  `GET /races` contract is unaffected (it never had `onSelf`).

**Owner interview 2026-07-23**
- Badge style: mini powerup-icon plates (not arrow-count chips, not hybrid);
  frontend plan + tests 6-8 updated with plate spec, ordering, and 3+overflow
  cap.
- Scope confirmed races tab only; home-tab card stays a non-goal.
