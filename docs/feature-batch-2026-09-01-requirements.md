# Race retention, inventory, identity, tutorial, and UI fixes — requirements

**Status:** reviewed; awaiting explicit owner approval  
**Planning date:** 2026-09-01  
**Implementation:** explicitly not authorized

## 1. Summary and user stories

This batch fixes six misleading or unsafe surfaces and adds four retention or
education improvements:

1. Stealthed racers must be anonymous everywhere in an active race, including
   the course, standings, avatars, accessories, steps, rank, profile actions,
   and any completed-race fallback that remains privacy-sensitive.
2. A completed custom race can be rematched: one new custom race is created
   from the old race's approved settings and everyone else from the old roster
   receives a normal invite.
3. Personal tournament cards use the same information hierarchy as ordinary
   race cards and do not show the viewer's capybara/avatar at the leading edge.
4. Settings links to `@BaraStepsApp` on X/Twitter and `@Bara.steps.app` on
   Instagram.
5. A revealed mystery-box powerup can still use its existing one-time,
   rewarded-ad reroll after the reveal modal closes, from its stash action
   sheet. The reveal-time action remains unchanged.
6. Daily-reward item reveals identify `POWERUP` versus `ACCESSORY` and explain
   the correct inventory destination/action.
7. The first real visit to Shop launches a shop-specific spotlight tutorial.
8. New or changed usernames/display names containing profanity are rejected by
   the backend and explained consistently by every current client entry point.
9. Referral-contest calls to action and rule headings use theme-semantic,
   readable foreground colors in both light and night themes.
10. Contest sharing ideas render as non-interactive icon bullets, not controls,
    with the owner-supplied copy.

**User stories.** As a racer, I cannot identify someone protected by Stealth;
I can keep a good custom-race cohort together after settlement; I can reroll an
eligible box result even if I dismissed its reveal; and I understand where a
daily item went. As a new shopper, I understand the Shop on first visit. As a
community member, I do not encounter newly accepted profane public names. As a
contest entrant, I can read the rules and distinguish suggestions from buttons.

## 2. Scope and non-goals

### In scope

- iOS and Android Flutter behavior and mirrored tutorial/demo surfaces.
- Backend additions needed for atomic rematch creation and authoritative name
  validation.
- Integration/widget tests written before business logic.
- Accessibility semantics, narrow-screen layout, and both app themes.
- Safe fallback when a new response field or error code is absent.

### Non-goals

- No change to Stealth duration, odds, targeting rules, or effect economy.
- No change to custom-race scoring, prizes, buy-ins, team logic, or tournaments.
- No change to the existing reveal-time reroll, reroll odds, ad grant price,
  reroll-all behavior, or discard rewards.
- No redesign of the entire Shop, daily reel, contest, or tournament bracket.
- No release flag, rollout percentage, kill switch, or temporary runtime
  toggle. All behavior is permanent and version-compatible.
- No staging/prod operation, deployment, build upload, or implementation in
  this planning phase.

## 3. Current-state findings

### 3.1 Stealth leak

The active course already masks a stealthed runner's name, position, animal,
and accessories (`lib/screens/race_detail_screen.dart:6073-6093`), while
`LeaderboardPlank` masks name, photo, multiplier, and steps
(`lib/widgets/leaderboard_plank.dart:88-115,273-280`). The supplied screenshot
still exposes the identity associated with Stealth, so implementation must
trace the actual standings call site and every alternate renderer, not merely
patch the shared plank. The completed hero currently reads raw `displayName`,
photo, accessories, and animal without a Stealth branch
(`lib/screens/race_detail_screen.dart:8741-8755`), a confirmed privacy gap if
the server continues to mark the row stealthed at completion.

### 3.2 Rematch surfaces and race creation

The finish popup is `RaceResultsSummaryScreen`; its rewarded-ad CTA is built
near `lib/screens/race_results_summary_screen.dart:756-773`. The completed race
detail ends after final standings and activity/chat
(`lib/screens/race_detail_screen.dart:8811-8841`) and has no retention CTA.
Existing creation and invitation contracts are separate backend commands
(`src/modules/races/commands/createRace.js` and `inviteToRace.js`), so chaining
two client calls would permit partial completion and duplicate races. Rematch
therefore needs one transactional, idempotent server command.

### 3.3 Tournament card

The tournament row intentionally builds the viewer's `myIdentity` and renders
a leading `RacerAvatar` (`lib/screens/tabs/races_tab.dart:1520-1525,
1627-1639`). This is the capybara visible in the supplied card. Removal is a
frontend-only layout change; partial/older tournament payload handling remains.

### 3.4 Community links

The current Instagram row uses `@bara.steps` and `instagram.com/bara.steps`;
the X row uses `@barastepz` and `x.com/barastepz`
(`lib/screens/settings_screen.dart:467-490`). Both visible handle and URL must
change together.

### 3.5 Deferred reroll

The backend already stores `rerolledAt` on the exact per-race `RacePowerup`
row (`prisma/schema.prisma:2167-2170`) and `rerollMysteryBox` already requires
an active race, owned HELD/unused box-origin row, rarity, upgrade level zero,
and `rerolledAt == null` before atomically consuming one verified ad grant
(`src/modules/powerups/commands/rerollMysteryBox.js:126-257`). The Flutter
screen already owns the rewarded-ad/retry flow
(`lib/screens/race_detail_screen.dart:6834-7153`) but wires it only to the box
reveal (`:7186-7188`). The ordinary stash sheet currently offers USE/DISCARD
near `:4091-4202`. No migration or new endpoint is expected for this item.

### 3.6 Daily item reveal

The daily reward reads `rewardType` defensively and distinguishes valid
powerups and accessories (`lib/screens/daily_reward_screen.dart:1314-1327`). A
powerup currently says only “Added to your powerups” (`:1427-1443`), while an
accessory has no type/destination guidance (`:1469-1477`). Missing/malformed
item payloads already fall back safely to the coin presentation and must keep
doing so.

### 3.7 Tutorial foundation

The existing app tutorial uses real-screen previews and `SpotlightOverlay`
under `lib/tutorial/`; Shop has stable keys including
`shop-segment-control`, `shop-category-pills`, `shop-dressing-room-stage`, and
`shop-product-grid` (`lib/screens/tabs/shop_tab.dart:1336-1913`). The shop
tutorial must run on the real Shop tab, not a fake fork, persist completion per
account where the current auth contract supports that, and never run in a
demo/tutorial preview or for an already-completed user.

### 3.8 Name validation

Flutter locally validates length, whitespace, and allowed characters
(`lib/screens/display_name_screen.dart:145-176`), but authoritative writes and
availability checks are backend routes. Backend validation is shared through
`src/shared/lib/displayNameValidator` and used by
`src/modules/users/routes.js`; all `PUT /auth/me/display-name`, discoverable
identity, availability-check, and generated/suggested-name paths must share the
same profanity decision. Client-only blocking would remain bypassable by old
app versions.

### 3.9 Contest contrast and suggestion styling

The dashboard's OFFICIAL RULES control uses theme tokens but the supplied
night screenshot shows its foreground collapsing into its panel
(`lib/widgets/referral_contest_joined_dashboard.dart:100-116`). The rules title
uses `textLight` directly on the green page (`lib/screens/giveaway_rules_screen.dart:
270-293`), while section headings use `grassDark` on a night panel (`:321-348`),
causing the supplied failures. Share ideas are two bordered mini-cards in a row
(`lib/widgets/referral_contest_joined_dashboard.dart:839-897`), which visually
read as tappable despite having no actions.

## 4. Detailed requirements

### R1. Stealth anonymity

- The backend, not Flutter, owns the privacy boundary. While Stealth is active,
  every progress/details/list/winner/podium participant projection uses one
  masked shape: `stealthed:true`, null/non-correlatable identity, no real
  `userId`, name, photo, animal/accessories/presentation, source/target IDs,
  exact steps, exact placement, or stable-ID ordering. Do not provide two
  alternate rosters that can be joined to recover identity.
- The mask lasts only while the effect is currently active. After its normal
  expiry, ordinary identity may return. At race completion, the server evaluates
  expiry once and serializes consistently; any row still marked stealthed stays
  fully masked in completed rosters/winner/podium payloads.
- Treat either defensive boolean spelling, `stealthed == true` or
  `isStealthed == true`, as hidden at every rendering boundary.
- While hidden, render name and steps as `???`, rank as `?`, the established
  anonymous avatar, no profile photo, animal, accessories, multiplier/effects,
  friend/profile tap, winner identity, or identity-bearing semantics.
- Do not infer identity from stable row order, course position, winner payload,
  active-effect ownership, or a second details/progress roster.
- Prefer server-masked payloads. Client masking remains defense in depth for
  mixed backend versions.
- Preserve visible participants' server placements and existing partial-null
  ordering behavior.

### R2. Custom-race rematch

- Eligible source: completed, non-seeded, non-tournament custom race in which
  the caller was an accepted participant. Any former accepted participant may
  initiate; the caller becomes creator of the new race.
- Add one authenticated endpoint: `POST /races/:raceId/rematch`.
- Request:

```json
{
  "idempotencyKey": "client-generated-uuid"
}
```

- Success `201` for first creation and `200` for idempotent replay:

```json
{
  "race": { "id": "new-race-id", "status": "PENDING" },
  "sourceRaceId": "completed-race-id",
  "plannedInviteeUserIds": ["former-participant-id"],
  "inviteState": "QUEUED",
  "skipped": [
    { "userId": "id", "reason": "ACCOUNT_UNAVAILABLE" }
  ]
}
```

- Errors use stable codes: `SOURCE_NOT_FOUND` (404), `NOT_PARTICIPANT` (403),
  `SOURCE_NOT_COMPLETED` (409),
  `SOURCE_NOT_REMATCHABLE` (409), and malformed/missing idempotency key (400).
- In the request transaction, snapshot/copy the source's complete gameplay
  configuration (name, race type/mode, target or duration/window,
  powerup-enabled configuration and interval, privacy/discovery, team size and
  team configuration, participant capacity, buy-in selection, and every other
  persisted **player-facing creator-controlled** gameplay setting), create
  the new race with caller as creator/ACCEPTED, record the immutable roster and
  response snapshot in the idempotency receipt, and enqueue a durable Postgres
  `REMATCH_INVITES` command. The request path must **not** bulk-write
  `race_participants`: C0 remains the sole bulk writer.
- A race-keyed, fenced worker with a lease token performs the cohort fan-out in
  ascending user-ID lock order, creates ordinary INVITED rows, and appends
  `RACE_INVITE_SENT_V1` outbox events in the same worker transaction; delivery
  is post-commit. The endpoint may return/navigation may proceed with
  `inviteState: QUEUED`. Receipt/status reads eventually report `COMPLETED` plus
  immutable invited/skipped results. A retry or concurrent tap returns the same
  race and receipt, never a second race.
- “Identical” refers to gameplay configuration, not lifecycle identity. Never
  copy source ID, status/timestamps (including the completed race's past
  scheduled-start instant), steps, effects, powerups, boxes, messages,
  payouts already earned, join requests, tournament IDs, seed IDs, share token,
  settlement fields, favorites, or notification history.
- Rematch must call or refactor through the canonical **current** create-race
  validation/economy path. Never copy server-derived economy state such as
  funded-prize/pool amounts, prize calculation version/unit/cap, payout curve or
  rounding metadata/version, team-pool multiplier/version/reward, pot/buy-in
  hold statuses, or funded-exposure stamps. Recompute all current server-owned
  values and enforce the initiator's current active-race limit and fresh buy-in
  hold. Existing invite acceptance remains authoritative for each invitee's
  affordability/hold, active-race limit, capacity/team validity, and funded
  exposure.
- “Unlimited” is sequential, not simultaneous multiplication: under a
  source-level transactional/advisory lock, permit at most one PENDING or ACTIVE
  rematch descendant of a completed source across all initiators. If one exists,
  return that existing descendant or `409 REMATCH_ALREADY_LIVE`; after it
  completes or is cancelled, any former participant may create another.
- Automatic cohort invitations do not bypass account safety. Skip deleted,
  banned, blocked, or otherwise unavailable accounts; authorize the otherwise
  non-friend fanout only for accepted members of the source cohort; create
  ordinary expiring INVITED rows; and coalesce/rate-limit repeat notifications.
  Fresh idempotency keys must not become an invite/push flooding mechanism.
- Push/inbox invites use the existing race invitation event and deep link so
  frozen clients can accept normally. No new required parameter is added to an
  old endpoint.
- Result popup: for each eligible custom race, show `REMATCH` with a circular
  redo icon immediately above the rewarded-ad button. While creating, disable
  duplicate taps; on success dismiss/navigate to the new pending race; on error
  keep the popup and show actionable copy.
- Completed detail: place the same CTA after the completion/payout summary and
  before final standings, using the same coordinator and error copy.
- Multiple completed races in one result popup must bind the action to one
  specific source race; the UI must not ambiguously rematch the whole batch.
- Add additive `capabilities.rematchCustomRace: true` to the authenticated
  capability envelope and viewer-specific `rematchEligible: true|false` on
  completed result/detail projections. The CTA requires both true; a missing,
  null, or malformed value fails closed. Viewer-specific eligibility must not
  enter shared Redis race fragments. This contract is not client-feature-token
  gated, so old clients ignore it and no header branch can drift.

### R3. Tournament card parity

- Remove the leading viewer identity/avatar and its semantics from personal
  tournament cards.
- Reflow name, round/status, countdown, inventory, placement, prize, pin, and
  chevron into the same leading/content/trailing rhythm as ordinary cards.
- Keep the entire card tap target, tournament detail destination, state labels,
  inventory, theme behavior, and missing-field fallbacks.
- Apply the same real widget in tutorial previews; do not hand-fork a preview.

### R4. Community handles

- Instagram visible text: `@Bara.steps.app`; confirmed URL:
  `https://instagram.com/Bara.steps.app`.
- X/Twitter visible text: `@BaraStepsApp`; URL:
  `https://x.com/BaraStepsApp`.
- Keep icons, layout, external-launch behavior, and failure handling.

### R5. Stash reroll

- Preserve the current reveal-time reroll without visual or behavioral change.
- In the generic held-powerup sheet, add a rewarded-ad `REROLL` action below
  USE and DISCARD only when the backend-provided row is safely known eligible:
  stable nonempty ID, `status == HELD`, box-origin rarity present,
  `upgradeLevel == 0`, and `rerolledAt == null`; the screen advertises reroll
  capability; the race is active; and the platform has the dedicated ad unit.
- Unknown/missing fields fail closed and hide the new action. An older backend
  or Android configuration with no unit sees today's sheet.
- Reuse the existing `_rerollBoxPowerup` ad, SSV verification, bounded retry,
  lifecycle, account-binding, and error flow. Do not mint or locally assume a
  reroll.
- On success, close or update the sheet, refresh progress, show the replacement
  result clearly, and ensure USE/DISCARD target the replacement server row.
- Server remains authoritative for races that end, concurrent use/discard,
  upgraded items, and already-rerolled items. These failures must not create a
  second roll; eligibility checks occur before an ad is shown where locally
  knowable.
- Preserve the current position-sensitive reroll behavior: delaying until a
  later position may change expected result, exactly as the existing endpoint
  does. Do not snapshot the original opening context.
- Consume the verified ad grant and compare-and-set the exact powerup row's
  type/rarity/config version/`rerolledAt` in one DB transaction. Concurrent
  race end, use, discard, or reroll must either complete one reroll atomically
  or leave the grant unconsumed; it must never charge the watch and lose the
  reroll.

### R6. Daily reward item labels

- A valid powerup reveal displays a visible `POWERUP` type label only. It adds
  no inventory/equip/use instruction.
- A valid accessory reveal displays `ACCESSORY` and the exact owner-approved
  instruction about opening Shop inventory to equip it (§10).
- Coins and coin fallbacks do not show item labels or equip copy.
- Type labels and accessory destination copy must remain readable in light/night themes,
  support text scaling, and use defensive payload checks.

### R7. First-visit Shop tutorial

- Trigger after the first real Shop tab is fully laid out for every
  authenticated account that lacks the `shop_v1` completion record, once per
  account; do not trigger merely because a preview/test has built Shop.
- Four beats:
  1. `STORE / INVENTORY` segment — where to buy versus manage owned items.
  2. Category pills — characters/accessories/powerups.
  3. Dressing-room stage — preview/equip presentation.
  4. Product grid/card — select an item to see details and price/ad action.
- Use the established spotlight visual language and a moving cutout measured
  after the target is on screen. Scroll/reveal the target before measuring.
- Provide NEXT/BACK where the current tutorial supports it and an explicit
  close/skip that records completion; reopening Shop does not replay it.
- Add a dedicated `VIEW SHOP TUTORIAL` action in Settings. Replay deliberately
  ignores the completion record for that navigation only and does not clear or
  duplicate the stored completion.
- Persist through nullable `User.shopTutorialCompletedAt` and the idempotent
  `/shop/tutorial/complete` command. Local cache may suppress flicker but cannot
  be the only account-level truth.
- Missing completion data means not completed: existing accounts as well as new
  accounts receive the tutorial on their next real Shop visit.

### R8. Profanity-safe usernames

- Add one shared backend validator used by availability checks and every public
  display-name write path. Normalize Unicode (NFKC), case, common separators,
  and obvious leetspeak/spacing attempts before matching, while retaining the
  existing allowed-character and length rules.
- Reject profane input with `400` and stable additive code
  `DISPLAY_NAME_PROFANE`; return no matched term or internal filter details.
- Availability endpoint returns unavailable with a reason/code new clients can
  map; old clients already treat unavailable/400 as failure.
- Generated/suggested fallback names must pass the same validator.
- Flutter pre-check may improve feedback, but server enforcement is mandatory.
- Friendly copy: “Choose a name without profanity.” Generic fallback remains
  for older backends/unknown codes.
- On authenticated-user serialization, evaluate the stored display name with
  the same validator and add `displayNameRequiresRename: true` when it is
  profane. Do not silently rewrite or null the stored value.
- A new client that receives that additive flag presents a blocking rename gate
  before normal app content. It cannot be skipped or dismissed; successful
  authoritative rename clears the condition. Old clients ignore the new flag,
  while all future write attempts remain protected server-side.
- Initial dictionary scope is English profanity plus normalized case, Unicode,
  separators, and common leetspeak variants. Structure the validator so reviewed
  language dictionaries can be added later without changing endpoint contracts.
  No fuzzy substring rule may reject arbitrary innocent names.
- Exact endpoint behavior:
  - display/discoverable-name writes: `400 {"error":"Choose a name without profanity.","code":"DISPLAY_NAME_PROFANE"}`;
  - `/auth/check-display-name`: preserve HTTP 200 and the existing availability
    shape, returning `{"available":false,"reason":"Choose a name without profanity.","code":"DISPLAY_NAME_PROFANE"}`.
- Put the rule in the injected domain command/shared validator, not only Express
  routes, so no caller can bypass it. Successful rename and every auth cache
  path recompute the flag.
- While an account is flagged, public serializers emit the safe placeholder
  `Name unavailable` instead of the offensive stored name. The owner's
  authenticated payload may retain the raw value only for editing and adds the
  defensive boolean. Cover Apple, Google, review account, `/auth/session`
  compact/legacy, `/auth/me`, and successful rename shapes. Place the Flutter
  gate at the authenticated root so deep links cannot bypass it. Frozen clients
  cannot be forced into new UI, but they still see the safe public placeholder
  and cannot submit another profane write.

### R9. Theme-readable contest UI

- Replace colors selected for semantic hue alone with theme-aware foreground
  tokens appropriate to the actual surface. OFFICIAL RULES and every section
  heading must be plainly legible in light and night themes.
- Target WCAG AA contrast: at least 4.5:1 for these small text sizes. Add a
  deterministic contrast test/helper assertion for the exact foreground /
  background token pairs used.
- Preserve the established palette and pixel typography; do not add hardcoded
  one-theme colors or create a parallel contest-only theme.
- Include enabled, pressed, and disabled rules-control states, text scaling,
  and the pre-join and joined contest routes.

### R10. Non-button share ideas

- Replace the two mini-cards with a vertical, non-interactive icon-bullet list:
  - Drop it in the group chat
  - Get the family involved
  - Show your coworkers you’re better than them
- Remove “Post it on Instagram” from this suggestion list. Keep the actual
  `SHARE YOUR INVITE` button as the only share control in the card.
- No Material/Ink response, button semantics, borders, filled bubbles, or
  per-row tap targets. The list is one descriptive semantics group.
- Keep the “MAKE SOME NOISE” heading and prize encouragement line, with wrapping
  that works on narrow screens and large text.

## 5. Data model and migrations

### Rematch

Add an idempotency ledger rather than a flag:

- `RaceRematchRequest`: `id`, `requesterUserId`, `sourceRaceId`,
  `idempotencyKey`, `newRaceId`, `createdAt`; store/query descendant lifecycle
  so the source-level one-live-descendant rule is enforceable under lock.
- Unique `(requesterUserId, idempotencyKey)`. Do **not** make source race unique:
  unlimited sequential rematches are allowed. Each operation uses a fresh key;
  retries with the same key return the same new race. Add an index supporting
  live-descendant lookup, but not a permanent source uniqueness constraint.
- Foreign keys cascade/restrict consistently with race deletion policy. The
  ledger is server-only and never leaks via broad serialization.

#### Race field mapping (required implementation contract)

| Treatment | `Race` scalar columns |
|---|---|
| **COPY as creator input, then revalidate** | `name`, `targetSteps`, `maxDurationDays`, `buyInAmount` (as requested input only), `payoutPreset`, `powerupsEnabled`, `powerupStepInterval`, `isPublic`, `maxParticipants`, `timeBased`, `isTeamRace`, `teamSize`, `teamAName`, `teamBName` |
| **RESET / generate fresh** | `id`, `creatorId` (set to initiator), `seedId`, `status=PENDING`, `potCoins=0`, `startedAt`, `endsAt`, `scheduledStartAt`, `scheduledEndAt`, `timezone`, `completedAt`, `winnerUserId`, `shareToken`, `winnerTeam`, `tournamentId`, `tournamentRound`, `tournamentMatchIndex`, `tournamentPowerupsActivatedAt`, `seededBucketId`, `createdAt`, `updatedAt` |
| **RECOMPUTE through current canonical creation policy** | `fundedPrize`, `prizePoolCoins`, `prizeCoinUnit`, `prizePoolMaxCoins`, `prizeCalculationVersion`, `payoutRoundingVersion`, `payoutRoundingMetadata`, `exitActionsEnabled`, `payoutCurve`, `creationSource=REMATCH`, `startPolicy`, `teamPoolMultBps`, `teamPayoutVersion`, `teamWinnerRewardCoins` |

Relations and all participant/effect/settlement artifacts are fresh, never
copied. If historical `buyInAmount` is no longer legal or current policy turns
that configuration into a free/funded race, **current policy wins** or the
endpoint rejects with the canonical validation code; it must not reproduce an
obsolete paid economy. A paid rematch holds the initiator's fresh coins through
the existing coin seam with deterministic `refId = rematch:<receiptId>:creator`.

### Shop tutorial

Add nullable `User.shopTutorialCompletedAt`. Exact field semantics: missing key
= backend unsupported and the new client does **not** auto-launch; explicit
`null` = supported and incomplete; ISO timestamp = complete. Add it to every
auth/provision/session shape and `AUTH_SHELL_FIELDS`.

### Username filter

No schema is required. Existing-name remediation uses the additive blocking
rename flag in R8; no destructive bulk rewrite is required.

### Stash reroll and other UI fixes

No migration. `RacePowerup.rerolledAt` is already nullable and authoritative.

## 6. API contracts

### New

- `POST /races/:raceId/rematch`: exact contract in R2.
- `POST /shop/tutorial/complete` in the existing Shop module, with empty body,
  idempotent `200` returning
  `{ "tutorialKey": "shop_v1", "completedAt": "ISO-8601" }`.

### Changed additively

- Auth/user payload may add nullable `shopTutorialCompletedAt`, or a nested
  tutorial-completion map, plus boolean `displayNameRequiresRename`. New Flutter
  reads them defensively; frozen clients ignore them.
- Existing display-name endpoints may add `code: DISPLAY_NAME_PROFANE` on a
  rejection. Success shapes and old validation codes remain unchanged.
- Existing race progress should expose enough defensive row fields to decide
  reroll visibility (`id`, `status`, `rarity`, `upgradeLevel`, `rerolledAt`).
  If any is presently omitted, add it only; never repurpose existing fields.

### Rematch idempotency and durable work details

- `idempotencyKey` is a canonical UUID string, maximum 36 characters. Reserve
  insert-first under the source/live-descendant lock.
- Same requester/key/same source replays immutable receipt data with `200`;
  same requester/key/different source returns `409 IDEMPOTENCY_KEY_REUSED`.
- `newRaceId` is unique, `sourceRaceId` is indexed, and the receipt persists the
  immutable source-roster/planned-invite snapshot plus final invited/skipped
  result. A failure before race/command commit leaves no receipt; worker failure
  retains retryable durable work and never creates a second race.
- Explicit FK policy: requester/source/new-race deletion is restricted while
  live work exists; completed historical receipts may be retained with IDs as
  scalar audit data according to existing account/race deletion policy.
- Team rematches preserve source team assignment for each accepted cohort member
  when still valid. Invalid/full/incompatible invitees are skipped with stable
  reasons. Invitations expire after the existing 72-hour interval.

## 7. Tests-first plan

### Backend integration tests (confirmed test DB only)

1. Rematch via real HTTP creates one pending custom race, caller accepted, all
   other eligible former accepted participants captured as planned invites,
   approved settings copied, forbidden runtime/settlement state absent, and a
   durable worker command committed. Run the fenced worker and assert normal
   invite rows/outbox events appear post-commit.
2. Same idempotency key and concurrent duplicate requests return the same race;
   transactional failure creates neither partial race nor partial invite set.
   Cover insert-conflict loser, same-key/different-source reuse, failure after
   reservation, unique `newRaceId`, immutable replay snapshot, and first `201`
   versus replay `200`.
3. Reject active/pending, seeded, tournament, unauthorized, and deleted sources
   without mutation. Prove every former accepted participant can initiate and
   becomes creator. Prove a fresh key while a descendant is PENDING/ACTIVE
   returns that descendant or `REMATCH_ALREADY_LIVE`, then a fresh key after it
   completes/cancels creates the next sequential rematch.
4. Rematch uses current canonical validation/economy: server-derived payout and
   exposure stamps are recalculated, initiator buy-in is freshly held, invitees
   pay only on normal acceptance, active/capacity/team/affordability rules remain,
   and historical V1/V2 economy stamps cannot be cloned.
5. Cohort fanout skips blocked/deleted/banned/unavailable users, retains normal
   invite expiry, and rate-limits/coalesces repeated push delivery.
6. Frozen-client regression: existing create/invite/list response shapes remain
   accepted; new invites can be accepted with the old endpoint.
7. Real HTTP display-name write, discoverable-name write, and availability
   check reject direct, case-varied, separated, and leetspeak profanity while
   allowing an explicit clean near-match corpus. Suggested names remain clean.
   `/auth/me` marks a seeded existing profane name as requiring rename, a clean
   name is unmarked, and successful rename clears the condition.
8. If tutorial persistence changes backend, completion is idempotent and auth
   payload omission/null is safe for old accounts and old client headers.
9. Existing reroll integration tests remain unchanged and pass; add a request
   made long after reveal proving the held row can still reroll once and a
   second request returns `ALREADY_REROLLED`. Add concurrent use/discard/reroll
   and race-end tests proving grant consumption and row mutation are atomic.

### Frontend widget/integration tests

1. Pump the real race detail with a stealthed row through every active/completed
   renderer and assert no name, photo, animal, accessory, profile action,
   numeric steps, numeric hidden rank, or identity semantics appears.
   Backend real-HTTP coverage must additionally prove progress, details, race
   lists, winner/podium, alternate rosters, and ordering cannot be correlated to
   recover a masked identity.
2. Pump result popup and completed detail with eligible/ineligible/partial race
   data; assert rematch placement, per-race binding, loading/error behavior, and
   navigation on success. Assert rewarded-ad CTA remains.
3. Pump real personal tournament cards across ACTIVE/PENDING/COMPLETED and
   missing identity payloads; assert no leading avatar and matching alignment.
4. Settings shows exact handles and launches exact URLs.
5. Pump the real stash sheet for eligible, already-rerolled, upgraded,
   inventory-origin, missing-field, disabled-capability, unsupported-platform,
   and race-ended states; assert REROLL visibility and that the existing
   controller performs one refresh/result handoff.
6. Daily powerup/accessory/coin/fallback/malformed results show the exact
   appropriate labels and guidance.
7. First real Shop visit for new and existing incomplete accounts shows all
   spotlight beats, persists completion, does not auto-replay, replays from the
   dedicated Settings action without clearing state, scrolls to targets, and
   does not trigger in demo/tutorial previews.
8. Every Flutter name entry point maps `DISPLAY_NAME_PROFANE`; the blocking
   rename gate is inescapable until a successful write; and an older backend
   without the new flag/error remains safe.
9. Contest dashboard/rules in light and night themes assert AA token contrast,
   readable styles, large-text layout, non-button share-list semantics, exact
   three bullets, and one actual share CTA.
10. Existing protected tests are not weakened, skipped, or deleted.

## 8. Backward compatibility and rollout

- Deploy backend first, then build/verify both iOS and Android. No frontend may
  require the new rematch/tutorial fields or error codes before production
  serves them.
- Frozen clients ignore the new rematch endpoint and additive fields. They
  receive ordinary invites created by a new client and continue accepting via
  the existing endpoint.
- A new client against an older backend hides rematch and the stash reroll
  action when capability/eligibility data is absent, uses generic name errors,
  and does not crash on absent tutorial completion. A missing tutorial field
  means unsupported/no auto-launch, preventing an unpersistable replay loop.
- The server continues to accept clean display-name writes from old clients but
  rejects profane ones authoritatively.
- Existing installed users with no `shop_v1` completion receive the tutorial on
  their next Shop visit. The durable completion stamp prevents auto-replay; no
  release flag is introduced.
- No new content asset is required by this plan. If implementation adds an
  unbundled asset, apply the repo's `testOnly:true` rollout rule.
- Postgres is the sole source of truth for rematch receipts, durable invite work,
  tutorial completion, coins/ad grants, name validation state, and Stealth.
  Redis is cache only. Invalidate requester/invitee race-list membership after
  worker commits and `v1:user:{id}:authme` through the existing user-update seam
  after tutorial completion or rename; test Redis enabled and `REDIS_URL` unset.
- Rollout order: (1) additive migrations compatible with old backend workers,
  (2) backend code rolling across exactly two production workers, (3) verify old
  client response contracts, mixed-worker behavior, and Redis-unset fallback,
  then (4) build and verify both iOS and Android. No staging start is authorized.

## 9. Acceptance criteria / definition of done

- All ten owner requests meet R1–R10 on iOS and Android.
- `flutter analyze` is clean and relevant Flutter tests pass.
- Backend unit/integration commands follow backend AGENTS.md; integration tests
  run only after confirming a dedicated local/test Postgres URL, never prod.
- Version-skew behavior in §8 is tested and recorded.
- Architect, game-economy, UI-placement, and post-implementation code review
  requirements are satisfied at their required phases.
- The manual UI checklist is delivered to the owner before implementation is
  called done.

## 10. Owner decisions (locked 2026-09-01)

1. Any former accepted participant may initiate a rematch, and the same source
   can be rematched an unlimited number of times.
2. Rematch immediately creates the gameplay-identical fresh race and invites
   the whole former accepted roster; it does not detour through Create Race.
3. The inventory/equip instruction appears only for accessories. Powerups get
   a type label but no equip instruction.
4. Every incomplete account receives the Shop tutorial, and Settings has a
   replay action.
5. Existing profane names force a blocking rename on next app open. Initial
   matching scope is English plus the normalization/evasion rules in R8.
6. Instagram is confirmed as `instagram.com/Bara.steps.app`.

## 11. Revision log

- **Phase 1 draft (2026-09-01):** mapped all ten requests to the current Flutter
  and backend paths. Identified the completed-race Stealth renderer, atomic
  rematch/idempotency need, existing durable reroll guard, backend-only name
  authority, tournament avatar producer, and contest token/surface mismatch.
- **Gap pass 1 (2026-09-01):** added multi-race popup binding, concurrent rematch
  protection, forbidden copied fields, invite-event compatibility, server-side
  tutorial persistence, Android ad-unit fail-closed behavior, completed-race
  Stealth coverage, semantic identity leakage, and correct powerup-versus-
  accessory destination copy.
- **Gap pass 2 (2026-09-01):** added real-HTTP name-path parity, Unicode/leetspeak
  normalization with clean near-match tests, AA contrast checks, non-button
  semantics, mixed-version fallback behavior, no-release-flag constraint,
  both-platform requirement, and explicit unresolved owner decisions. No
  implementation or production action was taken.
- **Phase 3 interview fold-in (2026-09-01):** locked any-participant and
  unlimited rematches, immediate gameplay-identical creation with automatic
  invites, accessory-only equip guidance, all-account Shop education with
  Settings replay, blocking remediation for existing profane names, and the
  confirmed Instagram destination. Clarified fresh lifecycle timestamps,
  per-operation idempotency, initial English normalization scope, and the
  additive authenticated-user rename flag.
- **Post-interview gap pass 1 (2026-09-01):** reconciled unlimited rematches with
  duplicate-tap safety by removing source uniqueness while retaining
  requester/key uniqueness; added tests proving two intentional rematches and
  one idempotent retry.
- **Post-interview gap pass 2 (2026-09-01):** made “identical” an enumerated
  gameplay snapshot rather than an impossible copy of past lifecycle fields;
  added non-destructive existing-name detection, old-client behavior, and
  replay-without-state-reset semantics. Zero product questions remain.
- **Economy review (2026-09-01):** verdict `SOUND WITH CHANGES`. Required the
  canonical current race-creation economy path, recalculated server-owned
  payout/funding stamps, fresh buy-in/acceptance checks, one live rematch
  descendant per source with unlimited sequential rematches, safe/rate-limited
  cohort invites, and atomic ad-grant plus powerup-row reroll mutation. Explicitly
  retained the existing current-position reroll strategy; no odds changed.
- **Architect review (2026-09-01):** verdict `REVISE`. Added the Race
  COPY/RESET/RECOMPUTE table and canonical current economy path; moved roster
  fan-out to a durable C0 worker command; completed receipt/idempotency and
  invite semantics; added explicit rematch capability/eligibility; selected the
  exact Shop tutorial field/endpoint and missing-field behavior; specified
  endpoint-specific profanity responses and safe public placeholder; moved the
  Stealth boundary server-side; enumerated Postgres/cache invalidation and
  migration-first rollout; and resolved powerup-label copy. All required
  changes were folded in.
- **Post-review gap pass 1 (2026-09-01):** verified the durable C0 worker owns
  all rematch participant fan-out, the request/receipt response distinguishes
  queued from completed invites, viewer-specific eligibility stays out of
  shared cache fragments, and sequential-unlimited rematches cannot multiply
  one source concurrently. Added no new product decisions.
- **Post-review gap pass 2 (2026-09-01):** reconciled missing-versus-null Shop
  completion for older backends, force-rename behavior for frozen clients,
  server-side Stealth expiry/completion semantics, current-policy buy-in
  handling, exact daily copy, cache invalidation, and migration-first rolling
  deployment. A stale/open-language scan and Markdown diff check were clean.
- **UI-placement review (2026-09-01):** inserted the planner's checklist and
  risks verbatim in §12, including real/demo/tutorial mirrors, result batching,
  Shop target measurement, contest-height growth, themes, platforms, narrow
  devices, and large text.

## 12. Manual UI-placement test plan

**Manual UI-Placement Test Plan — September 2026 feature batch**

*Elements under test:* Stealthed racers replace every identity-bearing course, standings, and completed-result element with anonymous placeholders in the same row/slot.

*Elements under test:* `REMATCH` with a circular redo icon is added above the rewarded-ad control in the result popup and between the completion/payout summary and final standings on completed custom-race detail.

*Elements under test:* The viewer capybara/avatar is removed from personal tournament cards and the remaining card content reflows into the ordinary-card leading/content/trailing rhythm.

*Elements under test:* Updated Instagram and X handles remain in the Settings COMMUNITY section; `VIEW SHOP TUTORIAL` is added to HELP & LEGAL near `VIEW TUTORIAL`.

*Elements under test:* Eligible held powerup sheets add `REROLL` below USE and DISCARD; ineligible sheets retain the current two-action layout.

*Elements under test:* Daily reward item reveals add a `POWERUP` or `ACCESSORY` label; only an accessory adds the inventory/equip instruction beneath its reveal content.

*Elements under test:* A four-beat spotlight moves across the real Shop’s STORE/INVENTORY segment, category pills, dressing-room stage, and product grid/card.

*Elements under test:* A blocking rename screen is inserted before normal app content for an account with a profane stored name.

*Elements under test:* Contest sharing mini-cards are removed and replaced in the same “MAKE SOME NOISE” area by a three-item vertical icon-bullet list; `SHARE YOUR INVITE` remains the sole button.

*Elements under test:* OFFICIAL RULES remains at the bottom of the joined contest page and rule section headings remain above their respective body copy without collisions in either theme.

*Checklist*

1. **Weekly/custom race detail — real active screen**
   - **Get there:** On iOS, open an active race containing one stealthed opponent; repeat on Android in the other app theme.
   - **Verify:** The hidden racer still occupies the expected course and standings row, but `???`, `?`, and the anonymous avatar occupy the name/rank/identity positions; no photo, animal, accessory, multiplier/effect badge, or profile affordance appears in or beside that row. Confirm the real identity is not duplicated elsewhere on the course, standings, active-effects area, or winner/leader chrome. Use one narrow device or large text setting and confirm placeholders remain inside their row.

2. **Race detail — demo race tutorial and tab-tutorial preview**
   - **Get there:** Sign in with an account that can replay onboarding → run the demo race; then Settings → VIEW TUTORIAL → advance to the Races and race-detail preview beats.
   - **Verify:** Where the fixtures contain a stealthed racer, the same anonymous placeholders occupy the production positions and the identity is absent from every duplicate row. The course, standings, effect tray, inventory, and tutorial spotlight anchors stay aligned; no identity appears in the demo coach chrome. If no hidden racer appears, record that as a fixture failure, not a pass.

3. **Completed custom race — result popup**
   - **Get there:** Finish one eligible custom race and open its placement/results popup; also use a result batch containing more than one completed race if available.
   - **Verify:** `REMATCH` appears for the specific eligible race immediately above the existing rewarded-ad button, with its circular redo icon inside the same CTA. The ad button remains in its old position below it; REMATCH is not duplicated elsewhere in the popup. In a multi-race popup, each visible action is clearly attached to one race rather than floating as a batch-wide action. Confirm an ineligible seeded/tournament result has no empty REMATCH gap. Repeat with large text and ensure the controls remain ordered and reachable without overlap.

4. **Completed custom race — real detail screen**
   - **Get there:** Races → completed eligible custom race.
   - **Verify:** `REMATCH` appears after the completion/payout summary and before final standings. It is absent from the old end-of-screen position and not repeated near activity/chat. Any stealthed finisher/winner retains anonymous content in the hero and final standings positions, with no raw avatar/accessory/name duplicated. Open a completed seeded or tournament race and confirm no REMATCH or reserved blank space appears.

5. **Personal tournament card — real Races tab**
   - **Get there:** Races → TOURNAMENTS with a personal tournament in each available state (pending, live, completed).
   - **Verify:** No capybara/viewer avatar or “your racer” leading slot remains. Tournament name and round/status begin on the same leading alignment as neighboring ordinary/team race-card content; inventory stays beneath the content and placement/prize/pin/chevron remain in the trailing area. Confirm there is no leftover indent or duplicate identity image. Repeat on a narrow device or large text setting.

6. **Personal tournament card — tab tutorial preview**
   - **Get there:** Settings → VIEW TUTORIAL → Races preview containing a tournament.
   - **Verify:** The reused tournament card also has no leading viewer avatar and matches the real Races-tab alignment. The ordinary race stays ahead of tournaments as expected, and the existing card/box spotlight still rings its intended ordinary race rather than shifting onto the reflowed tournament card. If the preview fixture has no tournament, record the missing checkpoint as a fixture failure.

7. **Settings — HELP & LEGAL and COMMUNITY**
   - **Get there:** Profile → Settings on iOS and Android.
   - **Verify:** `VIEW SHOP TUTORIAL` appears once in HELP & LEGAL adjacent to the existing `VIEW TUTORIAL`, without displacing or duplicating Support/legal rows. COMMUNITY still sits between HELP & LEGAL and ABOUT US/ACCOUNT; Instagram shows `@Bara.steps.app` and X shows `@BaraStepsApp` in their existing rows, with no old handles elsewhere. At large text, both handles and replay rows remain contained and tappable without overlapping adjacent sections.

8. **Held-powerup action sheet — real race detail**
   - **Get there:** Open an active race with one eligible, box-origin, unused powerup in YOUR STASH; tap it. Then inspect a normal/ineligible held powerup.
   - **Verify:** The eligible sheet orders USE, DISCARD, then REROLL, with REROLL directly beneath DISCARD in the same action area. The old reveal-time reroll remains only on its reveal surface and is not duplicated above USE. The ineligible sheet contains only the existing actions and leaves no blank third-row space. After a successful deferred reroll, the replacement reveal/result occupies the normal result position and reopening the sheet does not show a second REROLL. Repeat where the Android ad unit is unavailable and confirm the sheet keeps the old two-action layout.

9. **Held-powerup action sheet — demo race and tutorial race-detail preview**
   - **Get there:** Run the demo race tutorial to its inventory interaction; then Settings → VIEW TUTORIAL → race-detail powerups beat.
   - **Verify:** The production inventory slot and its sheet remain positioned correctly inside both reused race-detail surfaces. If fixture data qualifies for deferred reroll, REROLL appears third; if the tutorial intentionally suppresses it, there is no blank space or misplaced spotlight. The powerups spotlight still rings the inventory/effect area, not the new sheet action.

10. **Daily reward item reveal**
    - **Get there:** Open Daily Reward with a powerup result, then an accessory result, then a coin result; test one result with large text.
    - **Verify:** `POWERUP` occupies the type-label position for a powerup with no equip instruction below it. `ACCESSORY` occupies the same label position for an accessory, and “Go to your inventory to equip this item” appears beneath the accessory reveal content. The coin result has neither label nor instruction and leaves no empty item-only gap. Labels and guidance remain within the reveal card/sheet and above any footer ad.

11. **Shop — automatic first-visit tutorial on the real tab**
    - **Get there:** Use an existing authenticated account with no `shop_v1` completion → tap Shop for the first real visit.
    - **Verify:** Beat 1 rings STORE/INVENTORY; beat 2 rings category pills; beat 3 rings the dressing-room stage; beat 4 scrolls as needed and rings a product grid/card. Each cutout follows its target’s current on-screen location, NEXT/BACK/close remain reachable, and no target is highlighted twice or left highlighted in its old position. Complete/close it, leave Shop, return, and confirm no overlay is duplicated or auto-replayed.

12. **Shop — Settings replay, narrow layout, and themes**
    - **Get there:** Profile → Settings → VIEW SHOP TUTORIAL; repeat once in each theme, using large text or the narrowest supported device for one run.
    - **Verify:** Replay opens the real Shop tab and presents the same four targets in the same order. When a target requires scrolling, its cutout is measured after scrolling and remains centered on the visible widget; overlay controls do not cover the highlighted control or fall under the bottom tab bar/safe area. Closing replay returns cleanly with no orphaned dim layer.

13. **Blocking rename gate**
    - **Get there:** Launch the app while authenticated as an existing account marked as requiring a rename.
    - **Verify:** The rename screen appears above normal shell content before Home/Races can be seen or tapped, with no dismiss, back, tab-bar, or underlying-content escape visible. Validation feedback stays attached to the name field/action area. After a successful rename, the gate is removed and the normal initial screen occupies its usual position; the same rename UI reached from Settings and contest/home name prompts remains normally embedded rather than double-stacked.

14. **Referral contest — joined dashboard**
    - **Get there:** Home/referral entry → open a joined contest in light theme, then night theme; use large text for one pass.
    - **Verify:** Under “MAKE SOME NOISE,” a vertical icon-bullet list shows exactly three rows in this order: group chat, family, coworkers. The former two bordered/fill mini-cards and “Post it on Instagram” are absent, with no empty two-column footprint. `SHARE YOUR INVITE` remains the only button below the list, and the prize encouragement remains between list and button without overlap. OFFICIAL RULES remains a single full-width control at the bottom after Recent Referrals and does not collide with the preceding card.

15. **Referral contest — official rules page**
    - **Get there:** From the joined dashboard, tap OFFICIAL RULES; repeat through any pre-join rules entry point, once per theme and once with large text.
    - **Verify:** The contest/prize summary remains at the top, followed by the OFFICIAL RULES title and one vertically ordered section per rule. Every section heading stays immediately above its own body text and beside its intended icon; no heading shifts behind an icon, divider, or neighboring section, and no duplicate title appears. Scroll through the full page to confirm the long content remains reachable.

16. **Platform and adaptive-layout sweep**
    - **Get there:** Run the changed real surfaces once on iOS and once on Android, splitting light/night themes between them; repeat the densest result popup, tournament card, Settings, daily reveal, Shop overlay, and contest list at the largest practical text scale.
    - **Verify:** Added controls and labels remain inside safe areas, scroll views, cards, sheets, and overlays; bottom banners/tab bars do not cover them. Every added element is present only in its new specified position and absent from its former or unintended positions.

*Surfaces confirmed unaffected:* Public/featured tournament cards in `public_races_screen.dart` use `TournamentGameCard`, not the personal tournament row with `tournament-identity-avatar-*`; they should retain their current leading treatment.

*Surfaces confirmed unaffected:* Tournament detail/bracket screens do not render the personal Races-tab viewer-avatar row and require no avatar-removal checkpoint.

*Surfaces confirmed unaffected:* Create Race and Race Invite demo-prologue screens are not used by immediate rematch, because rematch deliberately bypasses copied-settings confirmation.

*Surfaces confirmed unaffected:* `case_opening_screen.dart` and `multi_case_opening_screen.dart` host mystery-box reveals, but the new deferred REROLL belongs to the held-powerup sheet; their existing reveal-time action must remain visually unchanged.

*Surfaces confirmed unaffected:* Home, Friends, Boards, and Profile tab tutorial previews do not render personal tournament rows, race-result REMATCH, daily item reveals, contest rules, or held-powerup sheets.

*Surfaces confirmed unaffected:* Giveaway admin screens are separate from the entrant joined dashboard/rules widgets and do not receive the share-list or rule-heading placement changes.

*Surfaces confirmed unaffected:* The tutorial’s hand-copied bottom tab bar is not reordered or renamed by this batch.

*Risks found while planning:* `RacesTab` is reused by `tutorial_real_screens.dart`, but the preview must contain a tournament fixture or avatar removal cannot be visually verified there; its existing spotlight intentionally anchors to the first ordinary race card.

*Risks found while planning:* `RaceDetailScreen` is reused by both `demo_race_host.dart` and `tutorial_real_screens.dart`, while demo coach chrome is hand-forked. Stealth, deferred reroll, and completed REMATCH states need explicit fixture coverage or these elements can be silently absent.

*Risks found while planning:* The result popup is launched separately by `main_shell.dart`; demo `_WinCard`/coach chrome is not the production `RaceResultsSummaryScreen`. Adding REMATCH to one does not automatically place it in the other, and the spec should keep demo results intentionally unaffected unless a rematchable demo source is provided.

*Risks found while planning:* Race-detail effect/inventory presentation has a hand-forked copy in `races_tab.dart`. The new REROLL is sheet-only, but implementation must avoid accidentally adding a third inline action or spacing change to the tab copy.

*Risks found while planning:* Shop’s four existing target keys are on real widgets, but the current general tutorial key map does not expose Shop beats. The overlay must measure targets after tab layout/scroll and must be suppressed in tutorial previews, or it may auto-launch over the app tutorial.

*Risks found while planning:* Completed-race Stealth currently has a raw identity hero path, so testing standings alone will miss the most visible leak.

*Risks found while planning:* A batched results popup can represent multiple races; one floating REMATCH control would be visually ambiguous unless it is nested in the selected/source race result.

*Risks found while planning:* Settings must gain a replay route without altering the hand-copied tutorial tab bar or launching a second tutorial overlay beneath/above the Shop tutorial.

*Risks found while planning:* The contest suggestion rows currently share a horizontal two-card footprint. Replacing them with three vertical bullets materially increases height and may push the real share button or OFFICIAL RULES below existing viewport assumptions at large text.
