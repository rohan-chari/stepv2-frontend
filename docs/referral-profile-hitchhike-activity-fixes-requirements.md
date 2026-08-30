# Referral rules, self profile, Hitchhike, and activity clarity requirements

## Summary and user stories

This batch fixes four user-facing inconsistencies without introducing release
flags or changing the rules of any unrelated powerup:

1. As a referral-contest entrant, I read a natural-language contest window and
   do not see internal interval notation rendered as stray characters.
2. As a racer, I can tap my own visible name/avatar anywhere that the same tap
   opens another racer's public profile and see my own average daily steps,
   podium trophies, character, and accessories.
3. As a Hitchhike target, I can be the target of at most one live Hitchhike at
   an instant, including when the attack lands on me through Decoy redirection.
4. As a race participant, I can understand powerup activity at a glance:
   harmful powerup names are always readable red, beneficial/defensive powerup
   names are always readable green, and a Decoy redirect followed by a block
   appears as two chronological activity messages.

The reported contest artifact is not random prize copy. The server-authored
rule currently exposes the half-open-interval notation `[startsAt, endsAt)`
(backend `src/modules/giveaways/services/standardRules.js:39`). The in-app rules
screen renders that text with the pixel body font
(`lib/screens/giveaway_rules_screen.dart:297-371`); unsupported punctuation in
that font is displayed as the reported `$1.`-like glyphs. User-facing copy must
not contain programming notation.

## Scope

### In scope

- Replace the global Bara-account contest-window rule with plain language that
  preserves the exact inclusive-start/exclusive-end eligibility rule.
- Regenerate the immutable standard rules version/hash whenever the standard
  template copy changes, and add a narrowly scoped audited amendment command
  for eligible scheduled/active global contests before clients display the new
  copy.
- Enable self-profile taps on every existing public-profile launcher that
  currently suppresses only because the row/runner is the signed-in user,
  including race course runners, race leaderboard rows, race podium/finishers,
  and the global/friends leaderboard. Preserve stealth and invalid-ID guards.
- Enforce the one-live-Hitchhike-per-target invariant against the final landing
  target after Decoy resolution, under the existing race mutation lock and
  before item/coin consumption.
- Emit a shared, durable feed event for a successful Decoy redirect and retain
  the separate final reflected/blocked/applied event.
- Give every recognized powerup name in Activity and Timeline a semantic
  valence color derived from the powerup type, never from the surrounding event
  outcome.
- Cover both iOS and Android Flutter surfaces and real demo/tutorial mirrors
  that render `RaceDetailScreen`.

### Non-goals

- No change to referral qualification timestamps, contest dates, prizes,
  winner selection, or the half-open eligibility calculation.
- No redesign of the public-profile sheet and no private stats added to its
  response.
- No change to the one-active-Hitchhike-per-caster rule, duration, copy ratio,
  scoring, price, inventory source, Mirror behavior, or Socks behavior.
- No Decoy chaining. A redirected attack still ignores a second Decoy on the
  landing target.
- No recoloring of ordinary prose, chat, avatars, timestamps, mystery-box
  events, or non-powerup system messages.
- No release flag, rollout percentage, kill switch, or temporary environment
  control.

## Current-state evidence and implementation path

### Referral rules

- Backend standard copy is generated and hashed in
  `src/modules/giveaways/services/standardRules.js:15-68` (backend).
- Draft editing and initial publication regenerate standard rules in
  `src/modules/giveaways/services/giveawayService.js:378-390` (backend).
- The frontend preserves the server-owned rules body and only replaces ISO
  instants with Eastern display text in
  `lib/screens/giveaway_rules_screen.dart:740-790`.

Implementation:

1. Bump the internal approved template discriminator from `bara-account-v1` to
   `bara-account-v2`, but keep the serialized rules version prefix
   `bara-account-v1-` for frozen-client compatibility. The amended stamp is
   `bara-account-v1-{first24(sha256(material including internal
   standardTemplateVersion: "bara-account-v2"))}` and is therefore distinct
   from its canonical v1 predecessor while remaining parseable by shipped apps.
2. Change only the `Contest window` body to:
   `The contest runs from {startsAt} through {endsAt}. These server timestamps
   are stored in UTC. A referral counts only if it qualifies at or after you
   join, at or after the contest start, and before the contest end.`
3. Keep ISO instants in the immutable server copy; the existing frontend
   formatter continues to localize them to Eastern time.
4. There is no existing published-rules amendment path: draft editing rejects
   published contests and existing entries are immutable. Add the narrowly
   scoped admin operation `POST /admin/giveaways/:id/amend-standard-rules`.
   Require a UUIDv4 `Idempotency-Key` and body
   `{ "revision": 4, "templateVersion": "bara-account-v2", "reason":
   "Replace internal interval notation with equivalent plain language" }`.
   Under one database transaction, lock the contest row `FOR UPDATE`, require
   matching revision, `BARA_ACCOUNT` eligibility, lifecycle `PUBLISHED`, and
   derived status `SCHEDULED` or `ACTIVE`. Before replacement, recompute the
   canonical v1 predecessor from the unchanged contest material and require the
   stored v1 version, hash, and complete sections to match it byte-for-byte;
   otherwise return `INVALID_RULES_AMENDMENT` rather than overwrite custom,
   corrupt, or previously amended rules. Require the exact v2 generated
   template and reject any request that changes dates, eligibility,
   prize, ranking, or other material terms. Store regenerated version/sections/
   hash and increment revision atomically. The `giveawayAuditEvent` action is
   `AMEND_STANDARD_RULES` and its request/response snapshots must contain the
   reason plus old and new version, hash, and complete sections. Idempotent
   replay returns the original response; stale revision returns 409.
5. Treat the amended v1-wire-compatible document as a non-material
   clarification of the same boundary. Existing predecessor-v1
   entrants remain eligible with their persisted `acceptedRulesVersion`, hash,
   and `rulesAcceptedAt`; they are not forced through impossible re-entry. New
   entrants accept the amended stamp. Qualification remains
   `qualifiedAt >= max(startsAt, rulesAcceptedAt)` and `< endsAt` for both
   cohorts. Public rules show the current amended document while entrant audit data
   continues to prove which version each entrant accepted.
6. Implement the operation as injected business logic in
   `src/modules/giveaways/commands/amendStandardRules.js`, with contest/audit
   persistence behind model-layer methods. Export it through the giveaways
   command/module indexes and wire only authentication, parsing, and response
   forwarding in the thin `asyncHandler` route in
   `src/modules/giveaways/routes/admin.js`. Do not add amendment business logic
   to the monolithic `giveawayService.js` or route handler.

### Self public profile

- `showPublicProfileSheet` and `PublicProfilePanel` already recognize a self
  relationship and skip friend mutations
  (`lib/widgets/public_profile_sheet.dart:21-147`).
- `GET /friends/:userId/profile` accepts an arbitrary discoverable ID and does
  not reject the authenticated user's ID
  (`src/modules/social/routes/friends.js:184-211` and
  `src/modules/social/queries/getPublicProfile.js:69-112`, backend).
- Suppression currently exists in race runner/participant/finisher launchers
  (`lib/screens/race_detail_screen.dart:4817-4865`), race leaderboard planks
  (`lib/screens/race_detail_screen.dart:10975-11022`), and leaderboard rows
  (`lib/screens/tabs/leaderboard_tab.dart:938-962`).

Implementation:

1. Remove only the `isUser`/`isMe`/viewer-ID early returns and `!isMe`
   conditions that disable an otherwise valid profile tap.
2. Continue blocking taps for stealthed identities, blank/missing IDs, preview
   identities that do not map to a real user, and any intentionally anonymous
   row.
3. Route self taps through the same `showPublicProfileSheet`; pass
   `PublicProfileRelationship.self` when known to avoid a needless friends
   fetch. The panel already treats self as non-mutable.
4. Do not add a new endpoint. Loading, retry, 404, auth invalidation, missing
   optional stats, and missing cosmetic fields retain the existing sheet
   behavior.

### Final-target Hitchhike invariant

- Direct activation already checks one live link per caster and one per target
  before consumption in
  `src/modules/powerups/commands/usePowerup.js:2558-2588` (backend).
- Decoy changes `resolvedTargetUserId` later in the same locked command at
  `src/modules/powerups/commands/usePowerup.js:2943-3013` (backend), after the
  current target-cap check. That ordering permits a redirect to bypass the cap.

Implementation:

1. Extract/reuse a `assertHitchhikeAvailableForFinalTarget` check that queries
   live race effects at the command's injected `now()` instant.
2. Keep the caster-level check before defense consumption.
3. Run the target-level check once the final landing is known: on the direct
   path before defenses consume anything; on the Decoy path after the redirect
   candidate is chosen but before the Decoy, Socks, held Hitchhike, or coins are
   consumed.
4. If the redirected target already has a live Hitchhike, return HTTP 409 with
   code `HITCHHIKE_TARGET_FULL`, cause no net item loss, retain the
   original target's Decoy because no valid attack resolution occurred, create
   no feed event/effect, and enqueue no scoring change.
   A redeemed store item is atomically marked `DISCARDED` and returned as one
   unit to the user's global inventory by `refundRedeemedOnRejection`; a
   legacy/non-redeemed race-held row remains `HELD`. Original purchase coins
   are not refunded and no activation/upgrade coins are charged.
5. Production `usePowerup` runs inside `runInPrismaTransaction`, locks the race
   row, then the relevant participant/item rows. Capture one
   `hitchhikeCheckTime = now()` and use it for caster and final-target liveness:
   `startsAt <= checkTime && expiresAt > checkTime`. Two
   simultaneous direct/redirected attempts that resolve to the same target must
   leave exactly one live row.

## API contract

No public endpoint is added or removed. One narrowly scoped authenticated admin
operation is added for the rules clarification described above.

### `POST /admin/giveaways/:id/amend-standard-rules`

Header: `Idempotency-Key: <UUIDv4>`.

```json
{
  "revision": 4,
  "templateVersion": "bara-account-v2",
  "reason": "Replace internal interval notation with equivalent plain language"
}
```

Success is HTTP 200 with the existing full admin contest response. Errors are
401/403 for admin auth, 404 for an unavailable contest, 409
`REVISION_CONFLICT` for stale revision, 409 `INVALID_TRANSITION` outside a
scheduled/active published global contest, and 422 `INVALID_RULES_AMENDMENT`
if the requested template is not the exact approved non-material successor.
The endpoint cannot accept arbitrary sections or modify any other contest
field.

### `GET /friends/:userId/profile`

Request is unchanged. `:userId` may equal the authenticated user ID. The
existing response stays unchanged:

```json
{
  "contract": "public-profile-v1",
  "user": {
    "id": "user-id",
    "displayName": "Nathan",
    "profilePhotoUrl": null,
    "equippedAnimal": null,
    "equippedAccessories": []
  },
  "stats": {
    "racePodiums": { "first": 0, "second": 0, "third": 0 },
    "avgStepsPerDay": 0
  }
}
```

Error behavior is unchanged: 401 for invalid auth, 404 for missing or
non-discoverable identity, and 500 for an unexpected failure. Optional fields
remain nullable/default-safe.

### `POST /races/:raceId/powerups/:powerupId/use`

The Hitchhike request remains:

```json
{ "targetUserId": "participant-user-id" }
```

Success and existing block/redirect responses are unchanged. The existing
error becomes authoritative for both direct and final redirected targets:

```json
{
  "error": "Someone is already hitching a ride on that racer",
  "code": "HITCHHIKE_TARGET_FULL"
}
```

with HTTP 409. A redeemed item returns to global inventory; only a legacy
non-redeemed race-held item remains held. No activation/upgrade coins are
charged and no new required request member is introduced.

### Race Activity/Timeline feed

The existing paginated message/feed response is additive. A successful Decoy
redirect creates an ordinary shared system event with:

```json
{
  "id": "event-id",
  "eventType": "POWERUP_REDIRECTED",
  "powerupType": "HITCHHIKE",
  "actorUserId": "decoy-owner-user-id",
  "targetUserId": "redirected-user-id",
  "metadata": {
    "attackerUserId": "attacker-user-id",
    "decoyOwnerUserId": "decoy-owner-user-id",
    "redirectedUserId": "redirected-user-id"
  },
  "description": "Nathan's Decoy redirected Anjali's Hitchhike to Shefali.",
  "createdAt": "2026-08-29T12:00:00.000Z"
}
```

For the reported chain, the terminal event is separately persisted:

```json
{
  "eventType": "POWERUP_BLOCKED",
  "powerupType": "HITCHHIKE",
  "actorUserId": "redirected-user-id",
  "targetUserId": "attacker-user-id",
  "description": "Shefali's Compression Socks blocked the redirected Hitchhike."
}
```

The redirect event must sort before the terminal event in ascending chronology.
Write both through the injected `RacePowerupEvent.create` seam and explicitly
assign distinct timestamps from a captured base instant (redirect at `t`,
terminal at `t + 1 millisecond`) so JavaScript `Date`, Prisma,
`(createdAt DESC, id DESC)`, and compound SYSTEM cursors preserve relative order
even across a page boundary. `RacePowerupEvent.create` therefore accepts an
optional injected `createdAt` while retaining the database default for all old
callers. Activity `nextCursor` remains an opaque string: emit the existing
base64url v1 JSON form `{ "v": 1, "at": "<ISO>", "kind": "SYSTEM", "id":
"<event-id>" }`, accept that form on subsequent requests, and continue accepting
legacy ISO createdAt-only cursor strings from frozen clients. Do not expose an
object cursor on the wire. Absolute adjacency is not promised when another committed writer falls
between the pair. `POWERUP_REDIRECTED` is additive: frozen clients render it as an ordinary
system message using the supplied description, or ignore unknown styling and
continue rendering all other events.

The wording uses display names without adding `@` server-side; existing UI/name
presentation rules remain authoritative. Both feed projections must inspect
the additive named-principal metadata and redact every stealthed named user for
the current viewer, not merely top-level actor/target. The attacker may see
their own name under the existing self-view policy; other viewers see `???`.

## Activity color semantics

`FeedBubble` currently lets `POWERUP_BLOCKED`/`POWERUP_REFLECTED` force the
highlight color to shield blue before considering the named powerup
(`lib/widgets/feed_bubble.dart:42-61`) and can match only the single name named
by `powerupType`. Replace this with one exhaustive, shared presentation
classifier and multi-mention parser used by Activity and Timeline. Match every
recognized bundled/catalog powerup name independently, longest name first,
case-sensitively at Unicode letter/number boundaries, without overlapping or
duplicating spans. The server `powerupType` remains a hint, not a limit on which
names are colored.

- **Harmful / red (`AppColors.feedAttack`)**: any powerup whose effect harms,
  restricts, reverses, steals from, freezes, or negatively manipulates another
  racer. This includes Wrong Turn, Leg Cramp, Red Card, Banana Peel, Detour
  Sign, Trail Mine, Pinecone Toss, Pickpocket (`SNEAKY_SWAP`), Imposter,
  Rainstorm, Signal Jammer, Leech, Quicksand, Power Outage, Drill Sergeant, and
  Bounty. A reflected or blocked harmful powerup name remains red.
- **Beneficial or defensive / green (`AppColors.feedBoost`)**: any powerup that
  adds/copies steps for its beneficiary, buffs, cleanses, protects, redirects,
  reveals defenses, or grants coins/rewards. This includes Protein Shake,
  Runner's High, Second Wind, Trail Mix, Fanny Pack, Lucky Horseshoe, Campfire
  Rest, Trail Magnet, Pocket Watch, Stealth Mode, Mirror, Compression Socks,
  Cleanse, X-Ray/Defense Scan, Hitchhike, Quick Rinse, Uprising, Ghost Pepper,
  Coin Flip, Decoy, Umbrella, Rally Flag, Piggy Bank, and Shell. Hitchhike is
  green because it gives copied steps to its owner even though it targets
  another racer.
- **Transfer / red:** Shortcut steals steps from a rival and Pickpocket steals a
  held item, so both are harmful/red even though the caster benefits. This
  explicit assignment overrides any generic "gives the user value" heuristic.
- **Context-dependent Mystery Potion**: color the explicitly named rolled
  powerup by that rolled type when the API supplies it; if the only available
  type is `MYSTERY_POTION`, use the existing neutral/gold treatment rather than
  guessing.
- **Unknown future type**: use readable neutral text (`textMid`/`textDark`), not
  red or green. Missing/null `powerupType` never crashes.

The new redirect sentence must color both `Decoy` green and `Hitchhike` green;
the terminal sentence must color both `Compression Socks` green and
`Hitchhike` green. Only the matched powerup-name spans receive semantic color. The sentence body
keeps normal text color. Both chosen red and green must meet WCAG AA contrast
for normal text on the parchment background in light and dark themes; if the
existing `feedBoost` fails, introduce a darker semantic feed-positive token in
`lib/styles.dart` and use it consistently. Do not use shield blue for a named
powerup.

## Data model and migrations

No schema migration is required.

- Contest rules version, hash, and sections continue using existing columns.
- Postgres `RacePowerupEvent` remains the source of truth. No new Redis data
  surface is introduced; model-seam post-commit invalidation refreshes the
  existing cached SYSTEM list.
- `RacePowerupEvent.eventType` is stored as text/the existing event type shape;
  add `POWERUP_REDIRECTED` to validation/serialization allowlists if any, but do
  not remove or repurpose old types.
- The Hitchhike invariant is enforced inside the existing race mutation lock;
  no destructive uniqueness migration is introduced because expiry-aware
  partial uniqueness is command-time logic and historical rows must remain.

Before deployment, run a SELECT-only audit grouping active, unexpired
`HITCHHIKE` rows by `(race_id, target_user_id)` with `HAVING COUNT(*) > 1`.
After the new backend prevents further duplicates, a nonzero result blocks the
live-invariant claim: either wait until the latest returned `expires_at` passes
and re-audit to zero, or obtain separate explicit authorization for a
deterministic remediation plan that names retained/expired rows and documents
the scoring impact. Do not mutate production data as part of this feature or
claim acceptance criterion 4 while duplicates remain without that separate,
in-the-moment authorization.

## Frontend states and placement

- Self profile uses the existing 82%-height draggable profile sheet, loading
  skeleton, error/retry panel, and content layout. It shows a self relationship
  with no add/accept/cancel/remove-friend action.
- Failed self profile fetch leaves the existing sheet error state; it must not
  fall back to editable private-profile UI.
- Activity and Timeline both route system rows through `FeedBubble`, so the
  semantic color change is made once and verified on both projections.
- Long redirect/block messages wrap naturally without clipping at supported
  phone widths and text scales. No new visual component or image asset is
  added.
- Demo/tutorial surfaces that render the real race detail screen inherit the
  behavior. Fake services must support a self-profile fixture if their visible
  self row is tappable; preview/anonymous runners remain non-interactive.

## Backward compatibility and rollout

1. Backend first, then Flutter iOS and Android together.
2. Old clients against the new backend:
   - continue parsing the unchanged profile and powerup-use shapes;
   - receive the same 409 code already used for a full direct Hitchhike target;
   - may display the additive `POWERUP_REDIRECTED` row as plain system text;
   - continue displaying the terminal Socks-block event;
   - receive amended contest rules through the existing rules payload/version
     contract.
3. New clients against an older backend:
   - self profile works because the existing endpoint already supports it;
   - missing redirect rows simply leave the old one-message chain;
   - unknown/missing `powerupType` falls back to neutral;
   - server remains authoritative for Hitchhike conflicts.
4. No build-time config changes, new asset dependency, `testOnly` content, or
   feature gating is required.
5. Rules amendment/publication is an operational data write and production
   deployment/data changes require separate explicit authorization.

## Tests-first plan

### Backend integration tests (write and observe failing first)

1. Extend the real redeem-then-use HTTP Hitchhike/Decoy/Socks suite: target A's Decoy selects B,
   B already has a live Hitchhike, activation returns 409
   `HITCHHIKE_TARGET_FULL`; Decoy remains active, the redeemed race row becomes
   `DISCARDED`, global Hitchhike inventory is incremented, activation coins are
   unchanged, and no new event/effect exists. A separate legacy-held fixture
   proves the non-redeemed row remains `HELD`.
2. Concurrent real-HTTP direct and Decoy-redirected Hitchhikes resolving to the
   same B yield one 200, one 409, and exactly one live target row.
3. Anjali -> Nathan (Decoy) -> Shefali (Socks) returns the existing blocked
   response and `GET` Activity/Timeline exposes exactly two ordered system rows
   with the specified redirect and redirected-block wording and IDs.
4. Decoy -> unshielded target exposes redirect then applied-use rows; Decoy with
   no eligible target remains one absorbed/block row, not a false redirect.
5. Stealth variants do not leak an attacker identity through the new redirect
   row.
6. Public-profile real HTTP test requests the caller's own user ID and asserts
   the unchanged v1 response with average steps and podium counts.
7. Contest workflow integration asserts newly generated amended rules retain
   the frozen-compatible `bara-account-v1-` wire prefix, have a distinct hash
   stamp derived from the internal v2 discriminator, contain the
   plain-language boundary sentence, exclude `[startsAt, endsAt)`, preserve the
   exact instants, and change version/hash when the template changes.
8. Published-contest amendment integration covers authorization, row/revision
   locking, idempotent replay, complete old/new audit snapshots, rejection of
   arbitrary/material amendments, and mixed entrants: v1 entrants keep counting
   at `qualifiedAt == rulesAcceptedAt`, while new entrants accept the amended
   stamped version.
   It also proves a frozen client submitting stale v1 for a new entry receives
   the existing 409 `RULES_CHANGED` with `currentRulesVersion`, then succeeds
   only after accepting v2; a pre-existing v1 entrant's idempotent old entry
   replay remains readable and is not rewritten.
9. Feed pagination places the redirect/terminal pair across a page boundary and
   proves neither row is skipped and relative order survives both the Activity
   and Timeline endpoints; the emitted cursor decodes to the exact v1 compound
   shape including `v: 1`, and a legacy ISO cursor remains accepted.
10. With a warm SYSTEM message cache, using the powerup invalidates through the
    injected event-model seam and both rows appear on the next read. Repeat the
    public-path case with `REDIS_URL` unset to prove Postgres fallback.
11. Boundary liveness proves `expiresAt == hitchhikeCheckTime` is expired while
    `expiresAt > hitchhikeCheckTime` blocks the final target.

Unit tests are acceptable only for the deterministic standard-rules hash/copy
and exhaustive powerup presentation classifier; they do not replace the HTTP
tests above. Confirm `DATABASE_URL` names a dedicated test database before any
backend integration suite. Run `npm run test:integration` for the relevant
files and `npm run test:unit`; never run bare `npm test`.

### Frontend widget/integration tests (write and observe failing first)

1. Pump the real race detail screen, tap the signed-in user's course runner,
   leaderboard plank, and podium/finisher where present, and assert the public
   profile sheet shows self stats and no friendship action.
2. Pump the real global/friends leaderboard, tap the self row, and assert the
   same behavior. Existing opponent and stealth guards remain covered.
3. Pump Activity and Timeline with `POWERUP_REFLECTED` + `WRONG_TURN`; inspect
   the RichText span and assert Wrong Turn is attack red in both.
4. Repeat with a beneficial step powerup and Compression Socks/Decoy; assert
   readable positive green in blocked/redirected and ordinary-use events.
5. Table-drive every bundled/legacy powerup type through the classifier and assert each
   expected valence plus neutral fallback for null/unknown.
6. Pump the two-message Decoy -> Socks chain at narrow width, large text scale,
   light theme, and dark theme; assert both complete sentences are present and
   no overflow exception occurs. Inspect spans to prove both powerup names in
   each sentence are independently matched and colored.
7. Pump contest rules containing the v2 body and assert the localized dates are
   shown and no half-open notation/stray `$1.` text exists.
8. Pump demo/tutorial mirrors with a real self identity and verify the intended
   tap behavior or explicit preview guard.

After implementation, run `flutter analyze` and the relevant Flutter tests,
then the full `flutter test` suite. Both iOS and Android are accounted for by
the shared Dart changes; any release build must verify both platforms in
lockstep.

## Acceptance criteria

1. Referral rules show human-readable Eastern dates and plain-language
   inclusive-start/exclusive-end eligibility with no interval notation or
   stray `$1.` glyphs.
2. Tapping one's own visible, identifiable name/avatar on every existing public
   profile-enabled race/leaderboard surface opens the same profile sheet and
   shows average daily steps, podium trophies, character, and accessories.
3. The self sheet never offers friendship actions; anonymous/stealthed rows
   remain protected.
4. No final target has more than one live Hitchhike, whether selected directly
   or via Decoy and under concurrent attempts.
5. A rejected redirected Hitchhike causes no net item loss, consumes no Decoy
   or Socks, charges no activation/upgrade coins, and changes no scoring state:
   a redeemed race row is discarded and one unit returns to global inventory,
   while a legacy non-redeemed row remains held.
6. Every recognized harmful powerup name is red and every recognized
   beneficial/defensive powerup name is readable green in both Activity and
   Timeline, independent of used/reflected/blocked/redirected outcome.
7. The reported Decoy -> redirected target -> Socks chain produces two clear,
   ordered messages that name both stages.
8. Frozen clients remain functional; no existing API member or event is removed
   or repurposed.
9. Required tests were written first and pass; `flutter analyze` is clean; both
   platforms are accounted for; architect/code review gates are satisfied.

## Manual UI-placement test plan

**Manual UI-Placement Test Plan — Referral rules, self profile, and activity clarity fixes**

*Elements under test:* The signed-in racer’s existing name/avatar tap affordance is added wherever another identifiable racer already opens the public-profile sheet: race course runner, participant/team rows, race standings, and finished-race winner/podium rows.

*Elements under test:* The signed-in player’s Global and Friends leaderboard row becomes tappable in place; tapping it opens the existing public-profile sheet without adding a second profile entry point.

*Elements under test:* A Decoy redirect followed by a block appears as two adjacent system rows in Activity and Timeline, ordered redirect first and terminal block second.

*Elements under test:* Highlighted powerup-name spans remain inline within each Activity/Timeline sentence and wrap inside the existing feed bubble without clipping, overlap, or duplicated text.

*Elements under test:* The referral contest-window rule remains in the existing “Contest window” section of the Official Rules document card, with the plain-language boundary sentence replacing the interval-notation text in place.

*Checklist*

1. **Real race detail — active race course**
   - **Get there:** Open any active solo race containing your account and at least one identifiable opponent → tap your runner on the course to reveal its name callout.
   - **Verify:** Your existing name/avatar callout now includes the profile affordance in the same position used for opponents; tapping it opens the existing public-profile sheet over the race. Confirm no duplicate affordance appears elsewhere on the course and the old non-interactive self callout is gone.

2. **Real race detail — participant, team, and standings rows**
   - **Get there:** Open seeded/dev races that expose the pending participant list, team lobby/roster, team standings, and ordinary race leaderboard; use races containing your identifiable row.
   - **Verify:** Your existing avatar/name area is tappable on each applicable row without moving or duplicating the row. The sheet overlays the race detail screen, and your name/avatar is not still non-interactive in its former location. Stealthed or anonymous rows remain without a profile affordance.

3. **Real race detail — finished race**
   - **Get there:** Open completed seeded/dev races covering a multi-finisher solo podium, a single-winner card, and a winning-team board, with your account represented in each fixture.
   - **Verify:** Your existing podium plinth or winner/team-member name/avatar is tappable in place and opens the same public-profile sheet. Confirm no second copy of your identity or profile control appears beside the result component, and the previous non-interactive self presentation is gone.

4. **Public-profile sheet opened from self**
   - **Get there:** Open the sheet from one race surface above.
   - **Verify:** The existing draggable sheet occupies its usual approximately 82%-height overlay and retains the established header, character/accessories, average-steps, and trophies arrangement. No add, accept, cancel, or remove-friend control appears in the action area, and the race screen remains behind the sheet rather than navigating to private Profile.

5. **Boards — Global and Friends leaderboards**
   - **Get there:** Main navigation → Boards → switch between Global and Friends; ensure your row is present, using the pinned self row if you are outside the loaded ranks.
   - **Verify:** Tapping your existing row/name/avatar opens the same public-profile sheet in both scopes. The row remains in its current rank position, is not duplicated, and is no longer the only identifiable row without the existing profile interaction.

6. **Onboarding demo race mirror**
   - **Get there:** Sign in with a fresh account → onboarding → start the playable demo race; reach a beat where the real race course or standings show your demo racer.
   - **Verify:** Your visible demo name/avatar has the self-profile affordance in the same place as the real race screen and opens the existing sheet without leaving the demo. Close it and confirm the demo resumes with no duplicated identity or profile control.

7. **Tutorial race-detail preview mirror**
   - **Get there:** Profile → Settings → View Tutorial → advance to “Mess with rivals.”
   - **Verify:** On the embedded real race-detail preview, the visible Rohan/self runner or standings identity uses the same in-place profile affordance and opens the fixture-backed public-profile sheet without escaping the tutorial. Close it and confirm the tutorial spotlight still rings the Powerups area, not the self-profile affordance.

8. **Activity — two-message chain and wrapping**
   - **Get there:** Open a seeded/dev active race whose Activity contains Anjali → Nathan Decoy → Shefali Compression Socks; select ACTIVITY. Repeat on the narrowest supported phone with the largest supported text size.
   - **Verify:** Two separate feed bubbles appear together in chronological reading order: the Decoy redirect immediately before the redirected Hitchhike block. Each powerup name stays inline in its own sentence; both full messages wrap inside the card with no clipping, overlap, horizontal scrolling, merged bubble, or duplicate combined message.

9. **Timeline — two-message chain and wrapping**
   - **Get there:** Open a seeded/dev race backed by the unified Timeline projection with the same chain; scroll to the event pair. Repeat on the narrowest supported phone with the largest supported text size.
   - **Verify:** The same two system bubbles appear adjacent in the Timeline’s displayed chronology, redirect before terminal block. Both full sentences and their inline powerup-name spans remain inside the existing timeline card; neither message remains as the old single combined/terminal-only presentation.

10. **Official referral contest rules**
    - **Get there:** Home referral-contest banner → View contest → Official Rules; also enter through the joined contest dashboard’s Official Rules link if the account has joined.
    - **Verify:** In the existing document card, “Contest window” remains in its established section order and shows one naturally wrapped plain-language paragraph beneath that heading. The old interval-notation line is absent, no duplicate contest-window section appears, and the sticky acceptance footer does not cover the final wrapped lines.

*Surfaces confirmed unaffected:* Home, Races, Friends, and Profile tab tutorial previews do not render the Boards leaderboard, Official Rules document, or the affected race feed rows.

*Surfaces confirmed unaffected:* The tutorial’s hand-copied wooden tab bar only labels the Boards destination; this change does not add, remove, or reorder a tab item.

*Surfaces confirmed unaffected:* The standalone Profile tab is private-profile UI and is not a mirror of the public-profile sheet opened from racer identities.

*Surfaces confirmed unaffected:* Race Invite, Create Race, case-opening screens, effect trays, inventory slots, and demo coach/results chrome do not host the changed identity launchers, referral-rule paragraph, or feed-row layout.

*Surfaces confirmed unaffected:* The separate non-contest referral-program rules screen does not render the server-owned giveaway “Contest window” section.

*Risks found while planning:* `RaceDetailScreen` is shared by both the onboarding demo and tutorial preview, but their data is hand-forked; their self rows must retain a valid fixture user ID for the new affordance to appear.

*Risks found while planning:* Both fake APIs already implement self-profile responses, but preview/anonymous identities must remain explicitly non-interactive so a fixture-only ID does not try to open a real profile.

*Risks found while planning:* The demo and tutorial preview feeds currently contain ordinary powerup events, not the Decoy-to-Socks two-row chain; implementation must add representative fixture rows if that layout is expected to be manually verifiable in those mirrors.

*Risks found while planning:* The race-detail tutorial spotlight anchors Powerups, not profile identities; changing hit regions around the course or standings must not intercept the scripted Powerups tap or shift that spotlight.

*Risks found while planning:* Activity and Timeline use the same feed bubble but opposite/list-specific chronology handling, so adjacency and redirect-before-block ordering must be checked separately on both projections.

*Risks found while planning:* The course exposes profile access inside the runner callout rather than directly on every sprite; enabling self there must preserve the existing callout geometry at narrow widths.

## Revision log

- **Draft (2026-08-29):** Traced the four reports to server rules copy, explicit
  self-tap guards, pre-Decoy Hitchhike validation ordering, and event-type-first
  feed coloring/missing redirect event.
- **Gap pass 1 (2026-08-29):** Added final-target timing, concurrency, and
  non-consumption requirements; distinguished Decoy fizzle from redirect;
  specified immutable rules version/hash amendment behavior; preserved stealth
  anonymity and frozen-client parsing.
- **Gap pass 2 (2026-08-29):** Made the color classifier exhaustive with
  unknown/Mystery Potion fallbacks and contrast requirements; expanded self-tap
  coverage to course, standings, podium, global/friends, and demo/tutorial
  mirrors; added exact API examples and integration-first evidence.
- **Architect review (2026-08-29):** Required an exact audited published-rules
  amendment contract and mixed v1/v2 entrant policy; corrected store-item
  rejection semantics; made feed ordering cursor-safe; added structured stealth
  principals, multi-name coloring, cache/Postgres tests, and a zero-duplicate
  deployment gate. All REQUIRED changes were incorporated.
- **Post-architect gap pass 1 (2026-08-29):** Reconciled strict/inclusive join
  wording with the qualification query, specified exact admin errors and
  idempotency, and separated relative ordering from absolute adjacency.
- **Post-architect gap pass 2 (2026-08-29):** Verified all bundled/legacy
  powerup names have an explicit valence or neutral fallback; added real
  redeem-then-use, warm-cache, Redis-off, cursor-boundary, and expiry-boundary
  coverage; resolved demo/tutorial fixture risks.
- **UI test planner (2026-08-29):** Inserted the checklist and risks verbatim.
