# Feature and bug batch — 2026-08-28 B

## Status

Implemented and production-artifact verified on 2026-08-28. Architecture,
game-economy, UI-placement, and final code reviews completed; the final code
review verdict is SHIP. Production deployment, store upload, review submission,
and customer release remain separately authorized actions.

## Summary and user stories

This batch collects the next set of fixes and features after the completed
2026-08-28 batch. It closes a race Stealth Mode privacy leak, turns the existing
mystery-box powerup guide into a mechanics/stacking reference, repairs attack
push deep links, adds server-persisted favorite races, attributes impact popups
to the attacker, makes natural-expiry Activity rows report their exact step
impact, and formats million-scale Profile totals readably.

As a racer using Stealth Mode, I want opponents to see neither my identity,
steps, nor true live placement, so they cannot reconstruct my track position
from a missing number in the standings.

As a racer viewing a stealthed opponent, I want the remaining visible racers to
have a simple, contiguous display order, so the standings remain understandable
without disclosing the hidden racer's real rank.

As a player learning the game, I want the mystery-box help sheet to explain both
what every powerup does and how repeat/overlapping effects combine, so I can use
items without discovering stacking rules through rejected casts.

As a player who receives an attack push, I want tapping it to open the race in
which I was attacked, so I can understand and respond immediately.

As a player in many races, I want to favorite important races and keep them at
the top of each Races shelf on every device.

As a player whose score changed, I want the popup to name the attacker when
privacy permits, and I want the Activity entry at natural effect expiry to state
the exact steps gained or lost.

As a player reading my Profile, I want million-scale all-time steps rendered as
`1.5M` instead of `1503.3k`.

## Item 1 — Stealth Mode must not leak placement through rank gaps

### Problem and current implementation evidence

The product copy promises that Stealth Mode will “Hide your name, steps, and
track position while Stealth is active”
(`lib/constants/powerup_copy.dart:429-430`). The name, avatar, accessories,
steps, multiplier, and the stealthed row's own `placement` are masked today,
but the other rows retain their authoritative placements.

The backend:

- computes canonical placements over the complete accepted roster before any
  viewer-specific masking (`src/modules/races/queries/getRaceProgress.js:745-755`
  and `:796-811`);
- serializes a stealthed opponent with `placement: null`, while serializing
  every visible opponent with the original `entry.placement`
  (`getRaceProgress.js:1469-1495`); and
- pins stealthed rows above visible rows in the response (`:1497-1504`).

The frontend correctly paints `?` on a stealthed row, but it deliberately keeps
the backend placement on every visible row
(`lib/utils/race_participant_display.dart:67-77,98-120`,
`lib/screens/race_detail_screen.dart:10623-10655`, and
`lib/widgets/leaderboard_plank.dart:31-37,68-75`).

That leaves a direct side channel. If the real order is Alice `#1`, stealthed
Bob `#2`, and Carol `#3`, an opponent sees `?`, Alice `#1`, Carol `#3`. The
missing `#2` reveals Bob's live position. With one stealthed opponent the leak
is exact; with several it reveals the set of hidden placements and can reveal
more when viewers compare consecutive refreshes.

The wire payload also retains the stealthed participant's stable `userId` for
client identity and target-eligibility mechanics. This item does not attempt to
make an authenticated API response anonymous to a modified client. It fixes the
ordinary product/UI promise: no true track position is disclosed in the
standings or their rank summaries.

### Required behavior

For each viewer of an ACTIVE race:

1. Compute scoring, canonical order, persisted/live placement, prizes, finish
   behavior, powerup targeting, and notifications over the complete roster,
   exactly as today. Stealth is presentation privacy only.
2. Determine which unfinished opponents are stealthed for this viewer using the
   existing `collectRaceIllusions` / `isStealthedForViewer` rules. A user always
   sees their own unmasked row. Finished racers remain unmasked under the
   existing rule.
3. Keep each masked row as an anonymous `?` row at the top of the standings, as
   today. Do not remove the row: the accepted-participant count and roster shape
   are not secret, and removing it would make the activation/disappearance more
   confusing.
4. Give every masked row `placement: null`. It shows `?`, receives no medal, and
   exposes no name, avatar, accessories, animal, steps, multiplier, profile tap,
   finish badge, or true placement.
5. Re-number visible unfinished rows contiguously in their canonical relative
   order after excluding all rows masked for this viewer. Display placements are
   `1..N`, where `N` is the number of visible ranked rows. No true-rank gaps may
   remain.
6. The response/UI order remains: masked rows first in stable server order,
   followed by visible rows ordered by their viewer-relative display placement.
   A masked row's array position is never treated as a rank.
7. Viewer-relative display rank and canonical payout rank are different facts.
   New-capability responses add explicit display-rank fields for standings and
   pinned-self UI while preserving canonical placement for settlement logic.
   A client must never feed compact display rank into payout eligibility or
   projected payout calculations.
8. Detour Sign remains stronger: it masks every row and every placement for the
   detoured viewer. Existing all-null fallback behavior remains unchanged.
9. Team-race individual rows use the same race-wide viewer-relative placement
   rule before they are arranged into team columns. Team totals, winner state,
   team payout rules, and team placement remain honest and unchanged.
10. Apply the same privacy projection to every active-race rank surface:
    `/races/:raceId/progress`, `GET /races`, `/home/race-card`, target-context
    summaries, top-three rows, `userPlacement`, and cache overlays. No ordinary
    Home, Races, detail, or powerup-target UI may expose the canonical gap.
11. When no opponent is stealthed for the viewer, every response and rendered
    rank remains byte-for-byte/behaviorally equivalent to the current canonical
    placement path.

Example with one masked opponent:

| Canonical order | Opponent-facing standings |
|---|---|
| Alice `#1` | hidden row `?` |
| Bob `#2` (stealthed) | Alice `#1` |
| Carol `#3` | Carol `#2` |

Example with two masked opponents:

| Canonical order | Opponent-facing standings |
|---|---|
| Alice `#1` (stealthed) | hidden row `?` |
| Bob `#2` | hidden row `?` |
| Carol `#3` (stealthed) | Bob `#1` |
| Dana `#4` | Dana `#2` |

The order of the two anonymous rows must not encode their canonical placements.
Use a stable non-ranking order already available in the response construction
(for example accepted-roster/payload order with a deterministic user-ID
tie-break), not real placement or total steps. Otherwise two simultaneous
stealthed rows would continue leaking which anonymous row is ahead.

## Item 2 — Two-page powerup and stacking explainer

### Problem and current implementation evidence

The mystery-box screen already has a `?` guide affordance
(`lib/screens/case_opening_screen.dart:454`) and a draggable `POWERUP GUIDE`
sheet (`:611-691`). The sheet is one flat list backed by a local
`_powerupEntries` constant (`:10-121`). That list is incomplete relative to the
current user-renderable catalog and carries stale literal descriptions even
though `PowerupCopy` and `GET /powerups/catalog` are the established copy source
(`lib/constants/powerup_copy.dart:1-23`,
`lib/services/backend_api_service.dart:714-751`, and backend
`src/modules/powerups/queries/getPowerupCopyCatalog.js:26-76`).

Stacking is not a single yes/no rule:

- overlapping different buffs add their active multipliers, while a global
  step event multiplies the resulting signed rate
  (`docs/buff-stacking-and-event-scoring-requirements.md:31-84`);
- most timed effects reject a second active copy of the same type, including
  Runner's High, Ghost Pepper, Stealth, Wrong Turn, Detour Sign, Lucky
  Horseshoe, Campfire Rest, Compression Socks, Mirror, Leg Cramp, and Signal
  Jammer (`src/modules/powerups/commands/usePowerup.js:2390-2457,2513-2605,
  2729-2751`);
- Leg Cramp and Wrong Turn are mutually exclusive on one target (`:2404-2440`);
- Leech and Hitchhike use pair/target caps rather than a blanket same-type rule
  (`:2460-2511`); and
- instantaneous or inventory/control powerups do not have a meaningful active
  stack.

A static prose paragraph would become wrong as these rules evolve. The guide
must use a structured, backend-served stacking contract with a bundled offline
fallback, following the existing powerup-copy model.

### Required behavior

1. Tapping the existing mystery-box `?` opens one sheet with a two-option pixel
   segmented control: **POWERUPS** and **STACKING**. POWERUPS is selected first.
2. POWERUPS lists every powerup visible to this client capability set, in the
   backend catalog order, with icon, name, and current long description. Remove
   `_powerupEntries` as an independent copy source.
3. STACKING begins with a compact explanation that “stacking” has two separate
   meanings: using another copy of the same powerup while one is active, and
   combining different simultaneous effects.
4. Each stacking row shows the powerup icon/name plus two explicit statements:
   **Same powerup** and **Other effects**. Do not collapse them into an ambiguous
   “stackable / not stackable” badge.
5. The structured rule vocabulary is:
   - same powerup: `NOT_APPLICABLE`, `BLOCKED`, `EXTENDS`, `ALLOWED`, or
     `LIMITED`;
   - other effects: `NOT_APPLICABLE`, `ALLOWED`, `CONDITIONAL`, or `CONFLICTS`;
   - a required plain-language `summary` explains caps, precedence, extension,
     or the relevant conflict.
6. Examples must make the shipped mechanics concrete: different active boosts
   add together; freeze wins over boosts/reversal; Wrong Turn negates the
   effective rate when not frozen; Leg Cramp and Wrong Turn cannot coexist;
   Leech allows one per attacker-target pair and at most two attackers per
   victim; Hitchhike allows one active link per caster and one per target.
   Runner's High and the other additive buffs are `CONDITIONAL`, not
   unqualified `ALLOWED`: freeze overrides, Rainstorm reduces, losing Coin Flip
   subtracts, and Wrong Turn negates the final rate. Rainstorm is `LIMITED` to
   one active storm per caster; storms from different casters may overlap, but
   the victim penalty clamps at one `0.5x`. Uprising and Rally Flag are
   `EXTENDS`: repeated casts merge each beneficiary window to the later expiry
   and never add another multiplier row. Coin Flip is `ALLOWED` but nonlinear:
   wins add (`2x + 2x = 4x`), losses clamp at `M−0.5`, and a mixed win/loss is
   also `M−0.5`, subject to freeze/Wrong Turn precedence.
7. Instant powerups such as Red Card, Shortcut, Protein Shake, and Second Wind
   say that stacking is not applicable because they resolve immediately; the
   guide must not misleadingly label them “cannot stack.”
8. Unknown/missing/malformed stacking metadata keeps the row on both pages; its
   STACKING row says “Stacking details unavailable” and never guesses. A
   complete bundled fallback covers every type known to this app when the
   backend/catalog is unavailable.
9. Tab selection remains stable while scrolling, the two pages keep independent
   scroll positions, and the sheet fits 320–430 pt widths, large text, day/night
   themes, and reduced motion without clipped controls.
10. This item documents existing mechanics only. It changes no stacking limit,
    multiplier, duration, targeting rule, price, rarity, or odds.
11. Power Outage is `LIMITED`: repeated casts are accepted and consumed while
    already-outaged recipients are skipped. It can coexist with Signal Jammer;
    Signal Jammer prevents Cleanse/Quick Rinse even though either can clear an
    Outage alone. Quicksand rejects Quicksand or Leg Cramp targets, while direct
    Leg Cramp currently permits a redundant overlap with Quicksand; the guide
    states this existing asymmetry without changing mechanics.
12. Pocket Watch, Cleanse, and Quick Rinse use `samePowerup:NOT_APPLICABLE` and
    `otherEffects:CONDITIONAL`, with their actual allowlists, exclusions, and
    cooldowns summarized. Defense precedence is Mirror → Decoy → Compression
    Socks; Umbrella separately blocks area attacks and duplicate Umbrellas add
    no benefit. Hitchhike copy says only what its current scorer supports and
    never claims that every boost carries over.
13. “Visible to this client capability set” is a complete, guide-specific rule:
    exclude retired types such as Imposter and every p2/p3/p5 or other gated
    type whose required capability is absent, while preserving the established
    Quicksand and Hitchhike-variant filtering. The capability set participates
    in the catalog cache/ETag variant.

### UI design direction

Keep Bara's tactile pixel/arcade language rather than introducing default
Material tabs or list tiles. The guide should read like a compact field manual:
parchment surface, existing powerup art, strong pixel section labels, and
small rule plates for the two stacking axes. The favorite control is UI chrome,
not new artwork: use the platform `star_rounded` glyph inside the same outlined,
pressed-depth circle language as existing race-card controls. A short fill/scale
response may confirm the toggle, but reduced-motion users get an immediate state
swap and all meaning remains visible without animation or color alone.

## Item 3 — Attack push notifications open the affected race

### Problem and current implementation evidence

The intended contract mostly exists: backend `POWERUP_USED_V1` attack pushes
carry `{type:"POWERUP_USED", route:"race_detail", params:{raceId}}`
(`src/modules/notifications/services/domainEventV1Projection.js:264-277`), and
Flutter maps `POWERUP_USED` to `NotificationRoute.raceDetail`
(`lib/services/notification_service.dart:606-633,803-842`). Android receives
stringified nested `params`; iOS normally receives a native map. `MainShell`
opens `action.params['raceId']` and falls back when the race is unavailable
(`lib/screens/main_shell.dart:1015-1028`). Cold-start actions require a later
authenticated drain because `ValueNotifier` does not replay an already-set
value (`main_shell.dart:1633-1643`).

The reported production behavior—Red Card tap landing on Home—means this must
be treated as an end-to-end contract bug, not “already fixed” based on isolated
helpers. The delivered provider payload, native bridge, auth/startup timing,
route extraction, and navigator result must all be tested together.

### Required behavior

1. Every visible push telling a user that another racer attacked/affected them,
   including Red Card and the existing `POWERUP_USED` offensive allowlist,
   deep-links to the exact race from the durable event's `raceId`.
2. The behavior works on iOS/APNs and Android/FCM for: foreground local
   notification tap, background tap, terminated/cold-start tap, and a tap that
   arrives before authentication/MainShell is ready.
3. Normalize all compatible payload shapes at the client boundary: top-level
   `raceId`, nested map `params.raceId`, and JSON-string `params`. Malformed or
   absent IDs do not throw.
4. A pending cold-start action is retained until the authenticated shell can
   navigate; it is consumed exactly once. It must not be lost because a listener
   attached after the value was set, and must not open duplicate detail routes.
   Clear the action only after the navigator accepts the route. If navigation is
   busy/unavailable, authentication changes, or another detail route is opening,
   retain/queue it and drain it after readiness or route completion. Duplicate
   callbacks for the same launch action coalesce to one navigation.
5. If the race is deleted, inaccessible, or no longer returned, land on the
   Races tab and show the existing “That race is no longer available” notice.
   Do not silently fall back to Home.
6. Tapping a Stealth-authored attack push still opens the race without exposing
   the hidden attacker's name in the push or route payload.
7. Do not add a new push type solely for Red Card. Repair the shared attack
   destination contract so all current and future `POWERUP_USED` attacks work.

## Item 4 — Favorite races and pin them within Races shelves

### Required behavior

1. An accepted participant can favorite or unfavorite an ordinary race from a
   star-in-a-circle control in the card's fixed trailing-actions area, directly
   before its chevron/status edge. Empty star means not favorite; filled gold
   star means favorite. The control has at least a 44×44 semantic tap target,
   does not squeeze the race name/placement row, and does not trigger the card's
   navigation tap.
2. Favorites are account/server persisted and therefore survive refresh,
   reinstall, logout/login, and switching devices. They are not a local-only
   preference.
3. Favorite races pin above non-favorites within the currently selected ACTIVE,
   PENDING, or COMPLETED shelf. Within each favorite/non-favorite partition,
   retain the shelf's existing secondary order (for ACTIVE, soonest-ending
   first). Invitations remain above the state pills and cannot be favorited
   before acceptance.
4. Tournaments are unchanged in this batch. Ordinary races remain before
   tournaments under the existing merged-list rule; favorite ordinary races
   pin only within the ordinary-race portion of their shelf.
5. Tapping the star updates optimistically, moves the card immediately, and
   disables/coalesces repeated mutation taps for that race. On failure, restore
   the previous state/order and show an error toast.
6. A missing `isFavorite`/`favoritedAt` from an older backend defaults to not
   favorite. Malformed fields never crash or reorder the list.
7. Favoriting has no effect on race membership, invitations, notifications,
   unread state, scoring, placement, payouts, featured/public discovery, or
   server-side race-list eligibility.

Current ordering lives in `RacesTab._entriesFor` and `_sortByTimeLeft`
(`lib/screens/tabs/races_tab.dart:264-275,491-508`); ordinary race cards are
built by `_buildRaceRow` (`:1447-1775`). There is no favorite field, mutation,
or backend model today. `RaceParticipant` is the natural owner because it is
already unique per `(raceId,userId)` and represents the user's membership
(`prisma/schema.prisma:1845-1979`).

## Item 5 — Impact popups name the attacker

### Problem and required behavior

Active impact popups parse only ID, type, delta, time, and description
(`lib/screens/race_detail_screen.dart:226-273`) and render a generic server
description (`:1338-1412`). The active-effect rail can name an attacker from
`sourceUserId`, but popup rows do not carry privacy-safe attacker attribution.

1. For an incoming opponent-caused impact, the popup subtitle includes
   `Attacked by @Name` (or grammatically equivalent copy) above/beside the exact
   signed step result. The name is the actor responsible for the final landing:
   direct caster normally, reflecting defender after a Mirror bounce, and
   original caster after a Decoy redirect.
2. Self-buffs, self-costs, system/global effects, and unattributable legacy rows
   omit the attacker line rather than saying the user attacked themselves.
3. If the attacker was protected by Stealth when the attack was committed, the
   immutable attribution is `???`; it must not reveal the identity later after
   Stealth expires. Deleted/unknown actors also degrade to no name or `???`.
4. The backend returns an additive nullable `attackerDisplayName`; clients trim
   and validate it. Missing, empty, non-string, or overlong values render the
   existing popup unchanged.
5. Attribution is recorded when the impact source is committed, not inferred
   from the current leaderboard at popup time. Direct and delayed/timed impact
   paths must use the same attribution helper so Mirror, Decoy, Stealth, expiry,
   settlement handoff, and retries cannot diverge.
6. Popup acknowledgment/idempotency, exact `deltaSteps`, popup eligibility, and
   modal serialization remain unchanged.

## Item 6 — Natural-expiry Activity states exact steps gained or lost

### Problem and required behavior

The shared feed currently writes a generic `<Powerup> wore off.` event in
`src/modules/powerups/commands/expireEffects.js:128-175`. Recipient-private
impact rows already carry exact nonzero `deltaSteps` and replace their linked
shared source rows in `RaceFeedService`
(`src/modules/races/models/raceImpactEvent.js:20-75` and
`lib/services/race_feed_service.dart:344-371`), but their stored description is
generic “gained/lost synced steps from/to Powerup.”

1. When a score-changing timed effect reaches its natural `expiresAt` and its
   recipient-private impact resolves to a nonzero delta, the private Activity
   sentence is:
   - `<Powerup> wore off. You gained N steps.` for a positive delta; or
   - `<Powerup> wore off. You lost N steps.` for a negative delta.
2. Use comma-formatted absolute integers and the canonical powerup name. The
   signed numeric field remains available separately; frontend must not parse
   the sentence to recover the amount.
3. The exact delta is visible only to the affected recipient. The shared/public
   race feed remains generic and must not disclose a private step impact to
   other racers or defeat Stealth.
4. Link/suppress the generic shared expiry row when the recipient-private exact
   row is present, so the affected user sees one authoritative Activity entry,
   not adjacent generic and exact duplicates.
5. Natural expiry is distinct from Cleanse, Quick Rinse shortening, race finish,
   forfeit, cancellation, or administrative repair. Those paths use accurate
   “ended/changed” copy and must not claim the effect naturally “wore off.”
6. A zero, pending, approximate, malformed, or unsynced delta never produces a
   fabricated amount. Preserve the generic shared expiry row in those cases.
7. Retry/replay must preserve one private impact and one shared event at most;
   no duplicate rows or changing amounts across refreshes.

## Item 7 — Profile all-time steps use million notation

### Required behavior

`ProfileTab._formatSteps` currently formats every value at or above 1,000 as
one-decimal thousands, so 1,503,300 becomes `1503.3k`
(`lib/screens/tabs/profile_tab.dart:721-725,781`). Change only the **All Time**
Profile metric formatting:

1. Values at or above 1,000,000 render in uppercase millions with one decimal:
   `1,000,000 → 1.0M`, `1,503,300 → 1.5M`, `12,960,000 → 13.0M`.
2. Values from 1,000 through 999,999 retain the existing one-decimal lowercase
   `k` format; values below 1,000 remain plain integers.
3. Round to the nearest tenth using the existing Dart numeric formatter. Do not
   truncate and do not change the backend stats value.
4. Loading, error, refresh, accessibility, and the other Profile metrics remain
   unchanged. Public-profile surfaces do not currently show all-time steps and
   are out of scope.

## Scope

### In scope so far

1. Viewer-relative, contiguous display placement across every active ordinary
   race rank projection while one or more opponents are protected by Stealth.
2. Solo/classic and team race standings, including pinned-self/gap rendering.
3. Race progress, `GET /races`, Home race card, target-context summaries,
   top-three rows, `myPlacement`/`userPlacement`, and their cache overlays.
4. Defensive frontend behavior against both the current backend's gapped
   response and the corrected backend's contiguous response.
5. Integration/widget regression coverage for one and multiple stealthed users,
   refreshes, ties, self-view, expiry, finished racers, Detour Sign, and team
   layouts.
6. A two-page powerup/stacking guide opened from the existing mystery-box help
   affordance, driven by structured catalog metadata and an offline fallback.
7. End-to-end attack-push routing into the affected race on iOS and Android.
8. Server-persisted favorite state for ordinary accepted race memberships,
   card controls, optimistic mutation, and pinned shelf ordering.
9. Privacy-safe attacker attribution on recipient impact popups.
10. Exact recipient-private natural-expiry step impact in Activity without
    leaking the amount into the shared feed.
11. Million notation for the Profile All Time metric.
12. iOS and Android behavior from the shared Flutter implementation, including
    cold/background/foreground notification paths and all changed UI mirrors.

### Non-goals so far

- Changing canonical scoring, stored placements, finish order, payout tiers,
  team totals, team winner calculation, drop odds, powerup targeting, or the
  Stealth duration/rarity.
- Changing any powerup stacking, conflict, multiplier, duration, cap, price,
  rarity, availability, or roll rule. Item 2 explains shipped mechanics only.
- Removing the anonymous row or hiding the number of race participants.
- Removing stable IDs from the authenticated API. That would require a separate
  opaque-target-token contract across powerup targeting, polling, pagination,
  and client row identity.
- Changing the separate “Hide me from the global leaderboard” setting. That
  path already filters hidden users before public global ranks are calculated.
- Favoriting tournaments, public races the user has not joined, or pending
  invitations; adding favorite folders/tags, notification changes, or a
  favorites-only filter.
- Exposing exact private impact amounts in the shared/public race activity feed.
- Renaming historical impact actors after a profile rename or backfilling
  attacker names onto pre-release impact rows.
- Changing public-profile statistics or any Profile metric other than the
  signed-in user's All Time display formatting.
- Adding a feature flag, rollout percentage, kill switch, or temporary runtime
  control.
- Deploying backend changes, uploading builds, submitting for review, or
  releasing either platform as part of spec approval.

## API contract

All changes are additive or presentation corrections. Existing request shapes,
success/error status codes, and fields remain accepted. Older clients ignore
new catalog, favorite, and impact-attribution fields.

### Active-race display-rank capability and projections

Add a client feature token for the privacy-safe display-rank contract. Add it
to both ternary branches of Flutter's `clientFeaturesHeader`; a build flavor or
platform must not accidentally omit it. For capable clients, all rank-bearing
active-race endpoints distinguish:

- canonical `placement`/`myPlacement`/`userPlacement`, used only for settlement,
  historical truth, and payout math; and
- additive nullable `displayPlacement`/`myDisplayPlacement`/
  `userDisplayPlacement`, safe for this viewer's UI.

They also expose an additive boolean `placementPrivacyActive`. It is true when
Stealth or Detour makes any canonical rank unsafe to present. Under Stealth,
visible display ranks are contiguous and masked rows are null; under Detour all
display ranks are null. Capable clients render only display fields whenever
privacy is active and retain canonical fields solely for payout calculations.
When privacy is inactive, display fields equal canonical values.

The same contract applies to `/races/:raceId/progress`, `GET /races`,
`/home/race-card`, every top-three entry, `userPlacement`, and any rank-bearing
powerup target-context response. Home top-three truncation occurs after the
viewer-safe anonymous/visible projection so neither inclusion nor numeric labels
reveal the canonical position. Viewer overlays are applied after stable shared
cache reads.

For tokenless/frozen clients, the backend downcast must not substitute compact
rank into the legacy canonical field. While placement privacy is active it
masks unsafe numeric placement summaries and suppresses placement-dependent
projected payout data, so an old client can neither infer a gap nor calculate a
false payout tier. No-Stealth and completed-race legacy payloads remain
unchanged.

### `GET /races/:raceId/progress`

The existing participant shape remains additive/nullable-compatible:

```json
{
  "participants": [
    {
      "userId": "hidden-user-id",
      "displayName": "???",
      "profilePhotoUrl": null,
      "accessories": [],
      "animal": null,
      "totalSteps": null,
      "placement": null,
      "currentMultiplier": null,
      "stealthed": true
    },
    {
      "userId": "visible-user-id",
      "displayName": "Visible Racer",
      "totalSteps": 12000,
      "placement": 2,
      "displayPlacement": 1,
      "stealthed": false
    }
  ],
  "myPlacement": 2,
  "myDisplayPlacement": 1,
  "myPlacementHidden": false,
  "placementPrivacyActive": true
}
```

Contract clarification for ACTIVE races:

- `placement` and `myPlacement` remain canonical for capable clients so payout
  and finish projections cannot accidentally use compact rank.
- `displayPlacement` and `myDisplayPlacement` are the only rank values rendered
  while `placementPrivacyActive` is true.
- With no viewer-masked racers display rank equals canonical live placement.
- With Stealth-masked racers, visible rows receive a contiguous relative display
  rank that excludes masked rows; masked rows receive `null` for both fields.
- Under Detour Sign, all participant placements and `myPlacement` remain null,
  display placements remain null, and `myPlacementHidden` remains true.
- Completed-race placement remains canonical and unchanged because Stealth no
  longer masks finished racers.

The helper that derives viewer-relative placements must operate only on an
in-memory, already-ranked projection. It must never overwrite database
`RaceParticipant.placement`, snapshot canonical placement, or inputs used by
payout/notification logic.

No new error case is introduced. Existing authentication, authorization, race
not-found, and server-error behavior is unchanged.

### `GET /powerups/catalog`

The response adds top-level `stackingVersion`, and each powerup row adds a
`stacking` object:

```json
{
  "stackingVersion": 1,
  "powerups": [
    {
      "type": "RUNNERS_HIGH",
      "name": "Runner's High",
      "description": "2x steps for 1 hour",
      "shortDescription": "2x steps",
      "upgradeTierLabels": [],
      "stacking": {
        "samePowerup": "BLOCKED",
        "otherEffects": "CONDITIONAL",
        "summary": "Only one Runner's High can be active. Buffs add; freeze overrides, Rainstorm reduces, losing Coin Flip subtracts, and Wrong Turn negates the final rate."
      }
    }
  ]
}
```

Rules:

- `samePowerup` is one of `NOT_APPLICABLE`, `BLOCKED`, `EXTENDS`, `ALLOWED`,
  `LIMITED`; `otherEffects` is one of `NOT_APPLICABLE`, `ALLOWED`,
  `CONDITIONAL`, `CONFLICTS`.
- `summary` is a non-empty bounded string (maximum 240 Unicode scalar values).
- The backend emits this object for every powerup visible to the request's
  complete capability set and excludes retired/gated rows. Unknown future enum values are ignored by old/new clients
  rather than invalidating the rest of the catalog.
- Add top-level integer `stackingVersion`; increment it in the same change as
  the code-owned stacking table. Replace the existing catalog cache namespace
  with a versioned `powerup-copy-catalog:v2:<capability-hash>` key and derive the
  HTTP ETag from `stackingVersion`, copy version, and capability hash, so a warm
  pre-deploy payload cannot omit stacking or leak gated rows. Preserve
  the existing ISO `version` field semantics for powerup-copy row updates.
- The endpoint remains unauthenticated and keeps existing 200/304/error
  behavior. Old clients ignore `stacking`; new clients use persisted/bundled
  fallback when the endpoint is absent or malformed.

The metadata is derived from a reviewed code-owned rule table beside the
mechanics, not an independently editable admin value. It must be updated in the
same change as any future stacking-mechanics change.

### `GET /races`

Every ordinary race summary for the authenticated accepted participant adds:

```json
{
  "isFavorite": true,
  "favoritedAt": "2026-08-28T18:10:00.000Z"
}
```

`isFavorite` is always boolean on the new backend. `favoritedAt` is an ISO-8601
UTC string when true and null when false. Invitations for which the caller is
not accepted return false/null or omit the additive fields consistently; they
cannot be mutated. Tournaments are unchanged.

`favoritedAt` is a caller-specific Postgres overlay, never a stable Redis race
field. The existing `v1:user:races:*` keys/TTLs keep their established shapes;
`raceListCache.FIELD_CLASSIFICATION` must classify favorite fields as per-user
overlay data, with generation fencing and Postgres fallback.

### `PUT /races/:raceId/favorite`

Authenticated request:

```json
{ "favorite": true }
```

Success (`200 OK`):

```json
{
  "raceId": "race-uuid",
  "isFavorite": true,
  "favoritedAt": "2026-08-28T18:10:00.000Z"
}
```

Sending `false` clears the timestamp and returns `isFavorite:false,
favoritedAt:null`. Repeating `true` preserves the original `favoritedAt` rather
than bumping it; repeating either desired state is idempotent and returns 200
without creating extra rows/events.

Errors:

- `400 INVALID_FAVORITE` — body missing, `favorite` missing, or not boolean.
- `401` — unauthenticated, unchanged common auth shape.
- `404 RACE_NOT_FOUND` — race absent or caller has no accepted membership;
  foreign IDs are indistinguishable from absent IDs.
- `500` — unchanged safe server error; no partial state.

No notification, feed event, analytics-visible social event, or race update is
emitted by this preference mutation.

### Push payload contract for attack notifications

No new endpoint or push type is added. A visible opponent-attack notification
must preserve this provider-independent logical payload:

```json
{
  "type": "POWERUP_USED",
  "route": "race_detail",
  "params": { "raceId": "race-uuid" }
}
```

APNs may carry `params` as a native dictionary; FCM stringifies nested values.
Provider adapters must preserve the same `raceId`, and the client accepts the
native-map, JSON-string, and legacy top-level forms. Payloads remain additive;
older apps still show the notification even if they fail to deep-link.

### Active impact popup/private Activity responses

Existing active impact notice and private Activity rows add one nullable field:

```json
{
  "id": "impact:uuid",
  "powerupType": "RED_CARD",
  "deltaSteps": -1200,
  "description": "You lost 1,200 synced steps to Red Card.",
  "attackerDisplayName": "TrailRunner",
  "valueStatus": "SYNCED_SNAPSHOT",
  "resolvedAt": "2026-08-28T18:10:00.000Z"
}
```

- `attackerDisplayName` is a trimmed privacy-filtered snapshot, `"???"`, or
  null. A real name uses the existing 30-character display-name limit. `???`
  means the final responsible actor was Stealth-hidden at the committed source
  boundary; null means self/system/legacy/unattributable and omits the UI line.
- Natural-expiry private Activity rows keep the same shape/delta but author the
  final description as `<Powerup> wore off. You gained/lost N steps.`
- Popup and private Activity projections of the same impact expose identical
  attacker attribution and amount. Acknowledgment behavior is unchanged.
- Shared race activity retains generic expiry copy and never receives the
  private `deltaSteps` or attacker snapshot solely because of this item.

## Data model and migrations

Item 1 requires no schema change. Canonical placement remains the
stored/source-of-truth value; viewer-relative placement exists only during
response serialization.

Any cached race-progress core must continue to store canonical facts. The
viewer-specific projection and Stealth compaction happen after cache/snapshot
read so one viewer's redacted placement cannot be served to another viewer.

Item 2 requires no database migration. Add a code-owned complete stacking-rule
table to the backend catalog projection and a bundled Flutter fallback. Catalog
cache keys/ETags must change with the serialized metadata; invalidate existing
derived catalog variants on deploy through the existing catalog invalidation
path.

Item 4 adds one nullable column to `race_participants`:

```prisma
favoritedAt DateTime? @map("favorited_at")
```

Use an additive migration only. Existing rows remain null (not favorite); no
backfill is needed. Add no new index in this batch: the existing unique
`(raceId,userId)` lookup serves mutation, and the list already loads a bounded
membership set before its in-memory favorite partition. If production evidence
later disproves that assumption, index work gets a separate measured change.

Items 5–6 add nullable durable source facts. Use additive typed columns where
the value participates in querying/integrity, or exact versioned metadata keys
where the existing active-effect metadata contract is already durable:

```prisma
attackerDisplayName String? @map("attacker_display_name")
```

Every delayed `RaceActiveEffect` records the final responsible actor ID,
privacy-safe display snapshot, cast-time hidden bit, original natural
`expiresAt`, and versioned boundary/end-reason metadata transactionally at
cast/redirect/reflection time. `expiresAt` may still change for Quick Rinse, but
the original boundary is immutable. Allowed end reasons distinguish at least
`NATURAL`, `CLEANSE`, `QUICK_RINSE`, `RACE_FINISH`, `FORFEIT`, `CANCELLED`, and
`ADMIN_REPAIR`.

Mirror stores the reflecting defender as responsible actor; Decoy preserves
the original caster while changing the recipient; Leech, Trail Mine, and Drill
Sergeant carry their final actor snapshot through delayed resolution. Cleanse
and Quick Rinse set a non-natural end reason without destroying original
expiry. Finish/forfeit paths do likewise. Retry/replay consumes the immutable
facts and never resolves current profile or Stealth state again.

No backfill: historical rows safely omit the new popup line. The value is a
display snapshot, not an authorization identity and not a relation. It is
deleted with the race/recipient through the row's existing cascades. New writes
store null for self/system/unattributable impacts, `???` for cast-time Stealth,
or the bounded display name permitted at source commit.

The same fenced C0 transaction that commits a natural boundary creates and
links the generic `EFFECT_EXPIRED` source feed event to the private impact. The
private description uses the immutable canonical attributed `deltaSteps`
(chronological marginal allocation), never theoretical raw-window math. Unique
keys and transaction fencing make replay return the same link/copy rather than
inserting an unlinked or differently worded row.

## Backend implementation plan

### Item 1 — Stealth ranks

1. Add failing HTTP integration coverage through the real progress endpoint
   before changing business logic. Do not import the serializer helper from the
   integration test.
2. Add a small pure helper beside the existing race illusion/progress projection
   code only if needed to keep the serializer readable. It accepts canonical
   ordered entries plus the viewer-masked set and returns presentation-only
   placements without mutating its inputs.
3. In `src/modules/races/queries/getRaceProgress.js`, build the viewer-visible
   placement map after illusion collection and before participant serialization.
   Use it for visible rows and for `myPlacement`; retain null for masked rows.
4. Sort multiple anonymous rows by a deterministic non-score/non-placement key,
   then visible rows by viewer-relative placement. Do not let stable sort inherit
   canonical placement order for the anonymous bucket.
5. Preserve Detour, Imposter, pagination/page projection, targetability, compact
   capability paths, and snapshot/cache separation. Audit any alternate progress
   projection at `getRaceProgress.js:1959-1996` so optimized and fallback paths
   cannot diverge.
6. Do not change `placementOrder.js`, persistence jobs, settlement, prize code,
   or notification rank calculations.

### Item 2 — stacking guide metadata

1. Write catalog contract tests first for every currently user-renderable type,
   capability filtering, enum validation, summary bounds, ETag changes, and no
   effect on the existing name/description fields.
2. Add a code-owned `powerupStackingGuide` table under
   `src/modules/powerups/constants/`. Audit it against all active-effect creation
   guards, `effectMultiplier`, Leech/Hitchhike caps, Pocket Watch, Cleanse/Quick
   Rinse, and instant powerups. The required game-analysis review signs off on
   the table before implementation approval.
3. Project the structured object additively from
   `getPowerupCopyCatalog.js`; include it in derived-cache variants and ETag
   versioning without making the database copy row authoritative for mechanics.
4. Add a structural guard requiring every visible `POWERUP_COPY_TYPES` member
   to have exactly one stacking record, so a new powerup cannot silently ship
   without guide semantics.

### Item 3 — attack-push deep link

1. Reproduce the failure through the durable domain event → alert/outbox → real
   APNs/FCM serializer payload, then through the Flutter tap parser and shell.
2. Keep `domainEventV1Projection.POWERUP_USED_V1` on `race_detail` with nested
   `raceId`; repair any legacy handler/transport branch that drops it. Both
   provider adapters must have payload-shape tests.
3. Do not mark delivery successful if payload normalization strips the
   destination. Preserve current delivery idempotency and notification audit.

### Item 4 — favorite persistence

1. Add the nullable migration and model methods after failing HTTP tests exist.
2. Implement the preference through a race-domain model method and one injected
   command exported from the module `index.js`. The route is an `asyncHandler`
   thin adapter only; business logic does not live in `routes.js`. Use existing
   `AppError` subclasses to produce the specified `{error, code}` responses.
   The accepted-membership-scoped model update makes absent and foreign
   memberships the same 404.
3. Thread `isFavorite`/`favoritedAt` through every `GET /races` ordinary-race
   projection, including lean/cache/optimized variants. Never place the field
   on a shared cache entry before the viewer overlay.
4. `favoritedAt` remains Postgres source of truth and is applied only as a
   per-user overlay. Post-commit, invalidate only the caller's existing
   `v1:user:races:*` entries, with the existing TTLs and generation fence. Redis
   failure falls back to Postgres; never put favorite state in a stable shared
   race field. Do not invalidate race progress, leaderboard, scoring, or every
   participant's list.

### Items 5–6 — impact attribution and expiry copy

1. Add failing real-HTTP active-impact/private-feed tests before schema/business
   changes, then add the nullable attribution migration.
2. Centralize impact actor attribution at the source-commit boundary. Direct
   impacts and active effects both carry the final responsible actor and a
   cast-time Stealth-hidden bit through durable work/retry payloads. Persist only
   the permitted display snapshot in `RaceImpactEvent`.
   Persist original expiry and the versioned boundary/end reason at the same
   boundary so later resolution never guesses from a mutated `expiresAt`.
3. Update every impact creation path—inline direct sources, v2 resolution worker,
   expiry, forfeit/finish, and retry replay—to call the helper. Unique keys and
   calculation version remain unchanged unless a schema-compatible projection
   version bump is proven necessary.
4. At a natural effect boundary, author the recipient-private exact wear-off
   description and link it to the generic shared expiry event. If transaction
   ordering currently creates the private impact before the shared event,
   restructure the fenced write/handoff so linkage is atomic/idempotent rather
   than performing a race-prone later repair.
   Mirror, Decoy, Leech, Trail Mine, Drill Sergeant, Cleanse, Quick Rinse,
   finish, forfeit, and retry paths must each have an explicit consumer test.
5. Preserve generic shared copy, Stealth redaction, nonzero/SYNCED_SNAPSHOT
   eligibility, and completed authoritative settlement behavior.

## Frontend implementation plan

### Item 1 — Stealth ranks

1. Add failing widget/integration-style tests that pump the real race-detail
   screen before changing display logic.
2. Update `orderRaceParticipantsForDisplay` to compute a defensive visible-rank
   projection whenever the payload contains one or more `stealthed:true` rows:
   masked rows remain first with no trusted rank; visible rows receive contiguous
   display indices even if an older backend sends canonical gaps.
3. Pass the derived display rank—not raw server placement—to
   `_buildLeaderboardPlank` for solo and team paths. Keep `rankHidden: true` on
   masked rows and suppress medals there.
4. Ensure pinned-self placement and any gap marker use the same derived visible
   rank. Do not compare a compact display rank against a canonical `myPlacement`
   from an older backend; derive locally while masked rows exist.
   Keep canonical placement in a separately named value used only by
   `RacePayoutScorecard`/projected payout logic. When an old backend provides no
   privacy indicator or safe display field while masked rows exist, compact the
   UI locally but suppress placement-dependent payout projections rather than
   presenting a false tier.
5. Preserve the current all-null Detour fallback and the no-Stealth path. Missing,
   null, negative, duplicated, non-numeric, or out-of-order backend placements
   must not crash the screen.
6. Because demo race and tutorial flows render the real race-detail screen,
   update only their fake payloads where needed to exercise the state; do not
   fork a separate standings implementation.

There are no new Item 1 loading, empty, or error states. It is a rank-label and
viewer-specific response correction within the existing standings state.

### Item 2 — guide UI

1. Write a widget test against the real Case Opening screen, then extract the
   inline `_showPowerupGuide` body into a reusable stateful guide sheet.
2. Replace `_powerupEntries` with validated `PowerupCopy` catalog iteration.
   Extend `PowerupCopyEntry` parsing/persistence with optional stacking fields;
   unknown fields/enums degrade per Item 2 without rejecting usable base copy.
3. Add the two-option `ArcadeTabSelector`/project-standard segmented control,
   independent scroll controllers, semantics, and responsive layout. Preserve
   the mystery-box reel, odds affordance, close behavior, and demo off-script
   gate.
4. Make the complete bundled fallback mechanically match the reviewed backend
   rule table. The backend snapshot overrides it when valid.

### Item 3 — notification routing

1. Extend `NotificationService` normalization so iOS and Android accept nested
   map, JSON-string, and top-level `raceId` without platform divergence.
2. Ensure MainShell drains a pre-existing cold-start action only after auth,
   onboarding/health gates, and navigator readiness, and consumes it once.
3. Reuse `_openRaceFromCard(...fallbackOnUnavailable:true)` and its navigation
   guard. Acknowledge/clear only after navigation is accepted; busy/unready
   attempts remain queued and drain after route/auth/navigator readiness. Do not
   create a parallel push-only race navigator.

### Item 4 — favorite UI/order

1. Add a defensive `updateRaceFavorite` API method and parse favorite fields as
   optional.
2. Add the star-in-circle control to ordinary `_buildRaceRow` cards with
   separate gesture semantics. Maintain an in-flight set keyed by race ID,
   optimistically patch the local row, and rollback/toast on failure.
3. Partition ordinary rows favorite-first inside `_entriesFor`, then apply the
   current state-specific ordering inside each partition. Do not reorder invites
   or tournaments.
4. Reconcile optimistic state with the next authoritative `GET /races` refresh
   without an old response overwriting a newer local mutation; use a per-race
   mutation generation/epoch.
5. Demo/tutorial fixtures that render RacesTab default missing fields to false
   and include one favorite example where the manual plan requires it.

### Item 5 — popup attribution

1. Extend `_ActiveImpactNotice.tryParse` with an optional trimmed bounded
   `attackerDisplayName`; malformed attribution never rejects an otherwise valid
   impact.
2. Extend `showPowerupRevealModal` with an optional attacker line and render it
   only for non-null attribution. Keep signed steps visually primary and fit
   `???`, long handles, 320 pt width, and large text.
3. Preserve the shared modal/route serialization guard and acknowledge only
   after the attributed popup is dismissed successfully.

### Item 6 — Activity expiry copy

1. No client-side amount calculation or sentence synthesis: render the
   authoritative private description and keep `deltaSteps` typed for tests/future
   presentation.
2. Verify `RaceFeedService` suppresses the linked generic expiry source row and
   restores it if a private page is removed/replaced. Malformed private rows must
   not suppress a valid shared event.

### Item 7 — Profile formatting

1. Add a focused formatter/widget test first, then update the Profile All Time
   formatter with the million branch. Keep all source values as integers.
2. Do not reuse the abbreviated All Time formatter for average/day metrics or
   change public-profile formatting.

## Backward compatibility and rollout

Backend deploys first, then the matching iOS and Android builds are produced and
verified together.

- **Old app against new backend:** tokenless responses retain legacy meanings
  when privacy is inactive. While Stealth/Detour privacy is active, unsafe rank
  summaries and placement-dependent payout projections are suppressed by the
  downcast; compact display rank is not repurposed as payout rank. Home, Races,
  progress, and target-context downcasts are tested.
- **New app against old backend:** the frontend detects masked rows and compacts
  visible display ranks locally, so the current gapped payload is safe.
- **New app against new backend:** additive display fields drive UI while
  canonical fields remain isolated for payout math; frontend defensive logic is
  idempotent.
- **No-Stealth and completed races:** placement semantics are unchanged, limiting
  mixed-version risk.
- **Powerup catalog:** old clients ignore additive `stacking`. New clients
  talking to an old backend use the complete bundled table. A malformed new
  field cannot invalidate otherwise valid name/description copy.
- **Attack pushes:** no new notification type is required. Old clients continue
  to display the alert; payload destination repair is additive and provider
  compatible. New clients accept historical payload shapes still in trays.
- **Favorites:** old clients ignore `isFavorite`/`favoritedAt` and keep their
  current list order; they cannot mutate favorites but do not clear them. New
  clients against an old backend show all rows unstarred and disable/rollback a
  mutation cleanly on 404/405 without hiding the race. The nullable migration is
  safe during rolling backend deploys.
- **Impact attribution:** old clients ignore the nullable column/response field
  and render current generic popups. New clients omit the attacker line against
  an old backend. Historical rows are not backfilled. Exact expiry copy is a
  private description change; old clients already render that string.
- **Profile format:** frontend-only and independent of backend version.

Backend deploy order within the batch is: additive migrations first through the
normal migration deployment, then backend code capable of reading/writing them,
then the matching iOS and Android app builds. No destructive cleanup follows in
this release.

No release flag is needed. All corrected/additive behavior is permanent.
Production deployment remains separately authorized in the moment.

## Tests-first plan

### Backend tests — Item 1 Stealth ranks

Before business logic, add tests under `test/integration/` that create real users
and an ACTIVE race, record different step totals, activate real Stealth powerups,
and call the authenticated progress endpoint as different viewers:

1. One stealthed middle-ranked opponent returns `placement:null`; visible rows
   return contiguous `1,2` rather than `1,3`; `myPlacement` matches the viewer's
   compact row.
2. One stealthed canonical leader does not cause visible standings to start at
   `2`.
3. One stealthed canonical last-place racer does not leave a trailing gap.
4. Two stealthed opponents return two anonymous null-placement rows whose mutual
   order is deterministic but unrelated to canonical score/placement; visible
   rows are contiguous.
5. The Stealth owner sees their own real name, steps, and canonical placement
   when no other opponent is stealthed.
6. Different viewers receive independently correct projections; no cache or
   snapshot cross-viewer contamination occurs.
7. Expiry and finished-racer cases restore canonical placement.
8. Detour keeps every placement and `myPlacement` null.
9. Team-race individual rows compact across the accepted roster while team
   totals and winner state remain unchanged.
10. No-Stealth response parity is unchanged.
11. Capable `/home/race-card`, `GET /races`, and target-context projections mask
    or compact top-three rows, `userPlacement`, `myPlacement`, and cache overlays
    without changing payout fields; tokenless versions suppress unsafe ranks and
    payout projections. Frozen-client widget/contract fixtures prove no gap or
    false tier.

### Backend tests — Items 2–6

Write the public-path integration tests first except for pure catalog-table
completeness/provider serialization, where focused unit/structural tests are the
appropriate complement:

1. Catalog returns a valid two-axis stacking object for every capability-visible
   powerup; capability-hidden types remain hidden; 304/ETag changes after a rule
   version change; old response fields remain identical.
2. A structural parity test walks the canonical powerup list and rejects missing,
   duplicate, unknown-enum, empty-summary, or overlong stacking records.
3. Real Red Card use emits one durable `POWERUP_USED_V1` alert whose outbox APNs
   and FCM payloads retain the exact race ID. Include a Stealth caster and every
   offensive type in the allowlist through a table-driven real-HTTP suite.
4. Favorite true/false/idempotent mutation through HTTP; malformed body,
   unauthenticated, invited-only, foreign, and absent race errors; cross-user
   isolation; `GET /races` lean/cache variants return only the caller's state.
5. Favorite mutation invalidates the caller's list without changing another
   participant's cached response; concurrent true/false requests settle to the
   last committed state without duplicate rows.
6. Incoming direct Red Card/Shortcut and delayed Leg Cramp/Wrong Turn impacts
   return the correct attacker snapshot; self-buff/system rows return null.
7. Mirror reflection, Decoy redirect, and cast-time Stealth return the final
   responsible privacy-safe name. Expiring Stealth later never reveals a stored
   `???`; retries preserve the same snapshot.
8. Natural expiry returns one private exact sentence and a linked generic shared
   expiry row; the affected user sees the private projection while another racer
   sees only generic copy.
9. Positive/negative, zero, early Cleanse/Quick Rinse, finish, forfeit, replay,
   and malformed/legacy impact cases use the correct wording and deduplication.

Run cache-backed public-path integration variants against local test Redis DB
15 for two-viewer Stealth isolation, catalog v2 key/ETag invalidation, and
caller-only favorite invalidation/generation fencing. Then run the same public
paths with `REDIS_URL` unset to prove Postgres or bundled fallbacks. Confirm both
`DATABASE_URL` and Redis target are dedicated local/test resources; never use
production Postgres or Redis.

Confirm `DATABASE_URL` points to a dedicated local/test Postgres before running
integration tests. Run the single new integration suite while iterating, then
the relevant existing Stealth/Detour suites. Never run bare `npm test`.

### Frontend tests — Item 1 Stealth ranks

Before display logic, extend the Stealth ordering regression coverage and pump
the real race-detail screen:

1. Payload `?, #1, #3` renders `?, #1, #2` without a `#3` or duplicate medal.
2. Two hidden rows plus visible canonical gaps render `?, ?, #1, #2, ...`.
3. Solo and team layouts use identical compact semantics.
4. Pinned-self and gap markers agree with the compact rank.
5. Hidden rows have no medal, profile tap, avatar/accessories, effect tray,
   multiplier, steps, or finish badge.
6. All-null Detour payload preserves its existing masked behavior.
7. No-Stealth payload keeps authoritative placements, including deterministic
   tie behavior and malformed-field defensive handling.
8. Demo/tutorial fake services render the same result through the real screen.

### Frontend tests — Items 2–7

1. Case Opening `?` opens POWERUPS by default; toggle reaches STACKING; both
   pages show the backend catalog order/copy and preserve independent scrolling.
2. Stacking rows render same-type and other-effect statements for blocked,
   limited, conditional, allowed, instant, missing, malformed, and unknown-enum
   fixtures. A persisted/bundled fallback works with an old/offline backend.
3. Guide layout remains usable at 320/390/430 pt widths, large text, day/night,
   and reduced motion; reel/odds/close and demo off-script gates still work.
4. NotificationService parses APNs native params, FCM JSON params, and top-level
   race IDs. Foreground/background/cold taps open the real race detail once;
   pre-auth action survives; missing race falls to Races with the notice. Add
   busy-route, navigator-not-created, auth-change, and duplicate-launch callback
   cases proving the action is retained until accepted and consumed once.
5. RacesTab shows an accessible empty/filled star, star taps do not open the
   card, favorites pin within ACTIVE/PENDING/COMPLETED while preserving
   secondary order, and tournaments/invites remain in place.
6. Favorite optimistic success, rapid repeat, rollback/error, stale refresh,
   missing fields, malformed fields, logout/account switch, and cross-device
   authoritative refresh are covered through the real RacesTab/API seam.
7. Impact popup shows `Attacked by @Name`, `???`, or no line as appropriate;
   long handles and narrow/large-text layouts do not clip; signed steps and
   acknowledgment/modal serialization remain correct.
8. Recipient Activity shows one exact natural-expiry sentence and suppresses
   its linked generic row; other viewers and malformed private rows retain
   generic copy.
9. Profile All Time renders boundary values `999`, `1.0k`, `999.9k`, `1.0M`,
   `1.5M`, and `13.0M`, while other metrics and loading/error states are
   unchanged.

After implementation, run the focused suites, `flutter analyze`, and the full
`flutter test` suite. Account for both iOS and Android; build checks follow the
final batch's combined risk rather than being run item-by-item during drafting.

## Acceptance criteria and definition of done

- No ordinary race UI exposes a missing rank that reveals a stealthed racer's
  canonical live placement.
- Masked rows show `?`; visible rows show contiguous viewer-relative ranks.
- Multiple masked rows do not encode their relative order through score,
  canonical placement, medals, or array-index rank.
- `myPlacement`, pinned-self rendering, solo standings, and team standings agree.
- Scoring, settlement, stored placement, payouts, notifications, team totals,
  targetability, and Stealth duration/odds are unchanged.
- The existing mystery-box help opens a two-page, complete, data-driven powerup
  and stacking guide; every shown rule matches server mechanics and distinguishes
  same-type reuse from overlap with other effects.
- Tapping any delivered attack push opens its race exactly once on iOS and
  Android in foreground, background, and cold-start states; unavailable races
  fall back to Races, never silently to Home.
- Accepted users can persistently favorite/unfavorite ordinary races; starred
  cards pin within each shelf without disturbing invitations, tournaments, or
  the existing secondary order.
- Incoming impact popups name the responsible attacker when permitted and never
  reveal a cast-time stealthed attacker later.
- Natural-expiry Activity gives the affected recipient one exact gained/lost
  sentence while every other participant retains generic copy.
- Profile All Time uses one-decimal `M` notation at one million and above.
- New HTTP integration and real-screen widget tests are written first, fail for
  the expected missing behavior, and then pass.
- Existing tests are not weakened, skipped, or deleted.
- Version-skew behavior is covered in both directions.
- `flutter analyze`, relevant/full Flutter tests, backend unit tests, and relevant
  backend integration tests are green before the eventual batch is called done.
- The final accumulated spec completes two fresh-eyes gap passes, architect
  review, any reviews triggered by later items, owner approval, implementation
  by the required agents, and combined code review.
- No deployment or store action occurs without its separate authorization.

## Open questions

None for Items 1–7. The following owner language is resolved into explicit draft
decisions for later approval:

- retain anonymous Stealth rows but exclude them from visible rank numbering;
- divide the existing mystery-box help sheet into POWERUPS and STACKING pages;
- use a star-in-circle on ordinary race cards and persist favorites server-side;
- make all shared attack pushes—not Red Card alone—deep-link to their race;
- show the privacy-safe final responsible attacker on impact popups;
- place exact wear-off amounts only in recipient-private Activity; and
- format Profile All Time values at/above one million with one decimal `M`.

If the owner wants tournaments to be favorite-able, exact wear-off amounts to
be public, or a different million threshold/style, that would materially change
the present scope and should be stated before final review.

## Manual UI-placement test plan

**Manual UI-Placement Test Plan — Feature batch 2026-08-28 B**

*Elements under test:* Mystery-box guide gains a POWERUPS / STACKING selector below the guide title, with independently scrolling content beneath it.

*Elements under test:* Ordinary race cards gain an empty/filled star-in-circle in the fixed trailing-actions area, immediately before the status/chevron edge.

*Elements under test:* Incoming-impact popup gains an attacker line beside/above the signed step result.

*Elements under test:* Stealthed standings keep anonymous `?` rows first while visible solo/team rank labels become contiguous; pinned-self rank uses the same numbering.

*Elements under test:* Profile → All Time changes from oversized `k` notation to a shorter one-decimal `M` value in the existing stat row.

*Checklist*

1. **Real Case Opening screen**
   - **Get there:** Races → open an ACTIVE ordinary race with an unopened mystery box → open the box → tap `?`.
   - **Verify:** POWERUPS / STACKING sits once below the guide heading and above the content; POWERUPS is the initial page. Switch pages, scroll each, switch back, and confirm the selector stays fixed, each list resumes where it was, and no old flat guide is duplicated beneath either page.

2. **Onboarding demo race → real Case Opening mirror**
   - **Get there:** Sign in with a fresh/test account eligible for the playable onboarding demo → follow the scripted race until its mystery box opens → tap `?`.
   - **Verify:** The same two-page guide occupies the same title/selector/content order inside the demo reel, with no second guide or old flat list. Dismiss it and confirm the scripted coach remains outside the sheet rather than covering its selector or rows.

3. **Real Races tab — all ordinary-race shelves**
   - **Get there:** Use an account with at least two ordinary races in each of ACTIVE, PENDING, and COMPLETED, including one favorite and one non-favorite; also retain an unanswered invite and a tournament. Open Races and tap each state pill.
   - **Verify:** Every accepted ordinary card has exactly one star circle immediately before its existing trailing status/chevron; it never appears in the name/placement row or inventory/effect row. Favorite cards are grouped at the top of their ordinary CLASSIC/TEAMS section, followed by unstarred cards; invitations remain above the state pills, tournaments remain in TOURNAMENTS after ordinary groups, and neither receives a star. Confirm no star remains in a card’s old position after its card moves.

4. **Tab tutorial → RacesTab mirror**
   - **Get there:** Profile → Settings → VIEW TUTORIAL → advance to “Race your friends” and “Grab mystery boxes.”
   - **Verify:** The seeded first ordinary race shows the star in the same trailing position as production without covering the race name, placement chip, mystery-box row, or chevron. The `races.card` spotlight still rings the whole first ordinary card and the `races.box` spotlight still rings its inventory box—not the new star. No star appears on the seeded tournament.

5. **Real solo race standings**
   - **Get there:** Open a staging/test ACTIVE solo race where a middle-ranked opponent is stealthed and the viewer is low enough to trigger the pinned-self/gap presentation.
   - **Verify:** Anonymous `?` row(s) remain together at the top with no medal; visible rank shields beneath them read consecutively `1, 2, …` with no missing label. The pinned-self row shows that same compact rank, and any gap marker separates rows without reintroducing the canonical number. No second rank appears on an anonymous row.

6. **Real team race scoreboard/standings**
   - **Get there:** Open a staging/test ACTIVE team race containing a stealthed opponent.
   - **Verify:** In the two-column STANDINGS, the anonymous racer retains `?` while visible individual rank shields are contiguous across the whole roster, even when consecutive ranks land in different team columns. Team score cards/totals stay above the columns and do not acquire individual compact-rank labels. No old gapped rank remains elsewhere in the race detail.

7. **Tutorial/demo race-detail mirrors — Stealth**
   - **Get there:** Re-run the tab tutorial to “Mess with rivals,” and run the playable onboarding demo to its race-detail standings, using the verification build’s seeded middle-ranked Stealth fixture.
   - **Verify:** Both real-screen mirrors show the anonymous row and contiguous visible rank shields in the same positions as a real race. In the tab tutorial, the `raceDetail.powerups` spotlight still rings the POWERUPS section rather than a standings row; in the playable demo, coach rings/cards do not cover or point at the shifted rank labels.

8. **Incoming-impact popup**
   - **Get there:** In a staging/test ACTIVE race, have another account attack this device’s racer, then reopen/resume the affected race so the impact reveal appears.
   - **Verify:** The attacker line appears once between the popup’s descriptive area and signed-step result, without displacing the result from visual prominence or duplicating it in the title/footer. Trigger a privacy-hidden `???` attribution and a legacy/self impact with no attribution; `???` occupies the same line position, while the unattributed popup closes the space completely rather than leaving a blank row.

9. **Profile All Time**
   - **Get there:** Profile on an account with at least 1,000,000 all-time steps; also Profile → Settings → VIEW TUTORIAL is the route used to inspect tutorial mirrors.
   - **Verify:** `1.xM` appears once on the right side of the existing All Time row, aligned with the other metric values; the label remains on the left and no old `xxxx.xk` text remains. Other metric rows retain their positions. Note: the current tutorial has no Profile beat, so there is no manually reachable Profile preview to check.

10. **Narrow width, large text, day/night, reduced motion sweep**
    - **Get there:** Repeat checkpoints 1, 3, 5, 8, and 9 on the narrowest supported phone/emulator (about 320 pt), then at the largest supported OS text size. Switch LIGHT/DARK through Profile → Settings → Appearance. Enable the OS reduced-motion setting and reopen the guide/favorite screen/popup.
    - **Verify:** Guide selector and rule plates remain above their content without clipping or horizontal escape; race-card star remains between content and chevron without squeezing the name/placement row; rank shields stay attached to their rows/columns; attacker line, signed result, and Continue button remain vertically ordered and scrollable; All Time value stays inside its row. Reduced motion causes no intermediate/duplicate star or page placement, and both themes preserve the same layout.

*Surfaces confirmed unaffected:* MultiCaseOpeningScreen/Open All does not construct or share the Case Opening `?` guide, so it gains no selector.

*Surfaces confirmed unaffected:* Daily Reward uses a hand-forked reel and does not construct CaseOpeningScreen, so it gains no powerup guide.

*Surfaces confirmed unaffected:* Home race cards are a separate implementation; favorite placement is scoped to RacesTab ordinary cards.

*Surfaces confirmed unaffected:* Tournament cards and unanswered invitation cards use separate branches and are explicitly non-favoriteable.

*Surfaces confirmed unaffected:* DemoRaceHost does not render RacesTab, so it has no favorite-card mirror; its relevant mirror is RaceDetailScreen/CaseOpeningScreen only.

*Surfaces confirmed unaffected:* Impact popups are suppressed when RaceDetailScreen runs with `demoMode: true`, so neither onboarding demo nor tab tutorial should acquire the attacker line.

*Surfaces confirmed unaffected:* Activity expiry changes existing row text only; they add, move, or remove no UI element.

*Surfaces confirmed unaffected:* Attack notification routing changes destination behavior only; it adds, moves, or removes no visible control.

*Surfaces confirmed unaffected:* Public profiles do not render the signed-in Profile All Time metric.

*Risks found while planning:* `tutorialPreviewRacesData()` currently has no favorite fields. It needs one favorited ordinary ACTIVE example while keeping `race-active-1` first, or the tutorial cannot visually exercise the new star state and its existing `races.card`/`races.box` anchors may move to the wrong card.

*Risks found while planning:* Both `tutorialPreviewRaceParticipants()` and DemoRaceEngine currently seed every racer as `stealthed:false`; neither mirror can expose the rank fix without a deliberate verification fixture/state.

*Risks found while planning:* The tab tutorial spotlights POWERUPS, not STANDINGS, and its overlay may prevent scrolling to the rank rows. A human-reachable verification fixture/debug entry is needed if the standings remain off-screen.

*Risks found while planning:* TutorialRealHost contains a ProfileTab branch and million-scale `allTime: 2417800` fixture, but `_buildSteps()` has no Profile step, making that mirror dormant and unreachable during the shipped tutorial.

*Risks found while planning:* The favorite is being inserted into a horizontally tight card header that already contains name, team-format chip, placement chip, optional pending status, and chevron; 320 pt/large-text testing is the highest-value card check.

*Risks found while planning:* `tutorialCardKey` wraps the whole first card and `tutorialBoxKey` wraps its inventory row. Reordering favorites must not change which seeded ordinary card owns those keys.

*Risks found while planning:* The guide is shared automatically by production and demo CaseOpeningScreen, but demo off-script gating and coach chrome are separate; the sheet must remain usable without allowing its dismissal/taps to advance or strand the scripted beat.

## Revision log

- **2026-08-28 — Initial draft:** Added Item 1 from the owner-confirmed Stealth
  behavior and traced the current backend serializer, frontend ordering, rank
  shield, and product copy.
- **2026-08-28 — Fresh-eyes gap pass 1:** Expanded the fix from the anonymous
  shield alone to visible-row compaction, `myPlacement`, pinned-self rendering,
  team standings, Detour precedence, and old-backend/new-client behavior.
- **2026-08-28 — Fresh-eyes gap pass 2:** Prevented multiple anonymous rows from
  leaking their internal order; pinned viewer-specific cache separation,
  no-mutation of canonical placement, optimized/fallback parity, and explicit
  old-client behavior.
- **2026-08-28 — Items 2–7 draft:** Added the powerup/stacking guide, attack-push
  deep link, race favorites, popup attacker attribution, exact natural-expiry
  Activity copy, and Profile million formatting after tracing the current
  catalog, notification, RacesTab, impact-event, feed-merge, and Profile paths.
- **2026-08-28 — Items 2–7 fresh-eyes gap pass 1:** Split stacking into same-type
  and cross-effect semantics; made guide metadata backend-served with offline
  fallback; expanded notification routing across provider/startup states; made
  favorites server-persisted and cache/viewer safe; added cast-time Stealth
  privacy to attacker attribution.
- **2026-08-28 — Items 2–7 fresh-eyes gap pass 2:** Separated recipient-private
  expiry amounts from the shared feed; prevented duplicate generic/exact rows;
  distinguished natural from forced effect endings; pinned favorite concurrency,
  old/new version behavior, exact API errors, schema/backfill rules, and
  tests-first coverage for both platforms.
- **2026-08-28 — Review and approval:** Architecture returned REVISE; the
  capability-safe rank/payout split, all rank surfaces, lossless push handoff,
  durable impact attribution/end reason, race-domain favorite/cache design, and
  Redis test matrix were added. Game analysis corrected the stacking table and
  `docs/economy.md`; UI-placement review supplied the verbatim checklist above.
  The owner approved implementation.
- **2026-08-28 — Implemented and verified:** Completed all seven items across
  the shared backend and Flutter app, added the nullable favorite/attribution
  migration, passed backend unit and affected integration suites against the
  dedicated test database/Redis DB 15, passed Flutter analysis and the full
  widget suite, and built signed production iOS and Android artifacts. Final
  combined code review returned SHIP. No environment was deployed and no store
  artifact was uploaded.
