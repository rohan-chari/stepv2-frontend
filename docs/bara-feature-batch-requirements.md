# Bara Feature and Bugfix Implementation Specification

Status: approved in advance by the user; implementation follows the required spec-review workflow.

## Scope and order

Implement, in order: Daily Spin coin labels; Bara Gold pricing copy; Bara Gold store presentation; completed pinned-race filtering; Team Chat measurement; Decoy activity normalization. Preserve backend authority, old-client compatibility, idempotency, bounded queries, and no synchronous per-user fan-out. Do not change odds, prices, payout rules, or product policy as part of this batch.

Non-goals: removing Team Chat, redesigning notification infrastructure, automatically clearing all favorites at race completion, adding per-recipient Decoy activity rows, introducing release flags, or moving reward selection/entitlement decisions into Flutter.

## 1. Daily Spin coin labels

Use one defensive Flutter formatter for wheel, reel, result, and history surfaces. Prefer the exact fulfilled amount, then a valid backend-provided range, then generic `Coins` only when no amount exists. Never invent an amount. Preserve legacy values Day 1–5 = 10/20/30/40/50 and Day 6 fallback = 100, while keeping backend RNG and claim authority unchanged.

Primary files: `lib/screens/daily_reward_screen.dart`, `lib/services/backend_api_service.dart`. Add widget regressions for every ladder amount, fallback, common/uncommon/rare coin result, extra-spin result, range, and missing amount. No backend/schema change unless a source field is genuinely absent.

## 2. Bara Gold pricing copy

Replace abstract copy such as `Eligible rewarded actions skip the ad` with wording describing only confirmed benefits: ad-free eligible extra Daily Spin and ad-free eligible box reroll. Do not claim all rewarded ads are skipped. Keep backend enforcement unchanged. Update paywall copy tests and retain tests proving unrelated rewarded placements remain ad-backed.

## 3. Bara Gold store presentation

Group catalog items inside each applicable category into Standard and Bara Gold subsections using backend-provided premium classification and existing ordering. Remove decorative Gold outline and repeated Gold badge/text from individual Gold tiles. Gold subscribers retain normal member price/owned/equipped states. Non-members use `Get Gold` unless the backend explicitly supplies active direct-purchase availability and valid product price. Do not infer future direct purchase from premium status.

Primary files: `lib/screens/tabs/shop_tab.dart`, `lib/widgets/shop_product_grid.dart`, `lib/widgets/shop_character_card.dart`, `lib/widgets/shop_tile_name.dart`, `lib/widgets/locked_shop_art.dart`, `lib/widgets/tier_badge.dart`. Preserve missing-field-safe rendering and backend policy authority. Add mixed/only-standard/only-Gold, member/non-member, ownership, affordability, direct-purchase metadata, and missing-IAP widget tests.

## 4. Completed pinned races

Keep `RaceParticipant.favoritedAt` unchanged. Filter completed and cancelled races from pinned presentation in backend reads, using existing lifecycle helpers/indexes where possible. Add defensive Flutter removal when a loaded race becomes terminal. Do not update every participant at completion, do not add per-user invalidation, and do not add an index without measured query evidence.

Primary backend files: `src/modules/races/commands/setRaceFavorite.js`, `src/modules/races/models/raceParticipant.js`, race list queries/services/caches, and completion/resolution paths. Primary frontend: `lib/screens/tabs/races_tab.dart` and race refresh handling. Test active/pending/terminal, closed-app, open-realtime, cache refresh, pagination, team, tournament, and retained-favorite-row behavior.

## 5. Team Chat measurement

Do not remove Team Chat. First use bounded 30/60/90-day read-only analysis over `races`, `race_messages`, and `race_participants` to measure races with messages, sender percentage, intensity buckets, repeat usage, and race-size correlation. Do not run production queries during implementation without explicit operational authorization. Existing data cannot measure opens/readers/retention correlation; add only `team_chat_opened` instrumentation if send metrics are insufficient, with no message body or participant list.

Relevant schema: `RaceMessage` with `raceId`, `senderId`, `kind`, `body`, `createdAt`, `deletedAt`, `audience`, and `team`; indexes include race/time, race/audience/team/time, and the non-deleted watermark index. Keep message pagination, rate limits, cache behavior, and shared realtime infrastructure unchanged.

## 6. Decoy activity normalization

Preserve one canonical activity row for the original power-up action. Enrich `RacePowerupEvent.metadata` additively with a versioned structure containing action, original/final targets, redirect type/owner/recipient, and constrained outcome. Use arrays only for genuine multi-landing AoE results. Keep `actorUserId` as the original attacker and never create a representation implying the Decoy owner attacked the redirected target.

Centralize event construction in a helper used by power-up branches. It must return the existing event fields plus metadata and canonical description. Normal, redirect, and redirect-then-block descriptions must preserve attacker, original target, Decoy owner, final target, power-up, and outcome. Keep notification infrastructure intact, but make notification attribution consume the same semantics where possible. Activity persistence remains transactional with power-up mutation; notification/realtime failures must not delete activity.

Audit/test `SHORTCUT`, `RED_CARD`, `WRONG_TURN`, `LEG_CRAMP`, `SIGNAL_JAMMER`, `LEECH`, `HITCHHIKE`, `QUICKSAND`, `RAINSTORM`, `PINECONE_TOSS`, plus `MIRROR`, `COMPRESSION_SOCKS`, `UMBRELLA`, and `IMPOSTER` interactions. Cover redirects to attacker, attacker teammate, Decoy-owner teammate, already-affected/invalid/forfeited/inactive targets, completion races, defenses, multiple Decoys, AoE, retries, rollback, projection failure, and realtime failure. Do not add activity/notification fan-out.

Primary files: `src/modules/powerups/commands/usePowerup.js`, power-up event/effect models and policy, race feed queries, notification handlers/projection, and `lib/screens/race_detail_screen.dart`.

## API and compatibility requirements

Any new event metadata is additive and nullable. Preserve the existing `POWERUP_REDIRECTED` event and its current wire fields; do not replace it or create a parallel event system. Old clients continue receiving the existing `eventType`, `powerupType`, `targetUserId`, and human-readable `description`; they ignore unknown metadata. Do not remove or repurpose fields, add required request parameters, or require a new endpoint for old clients. Missing/null server fields must render safe unavailable/default states in Flutter. Backend remains authoritative for catalog policy, entitlements, reward selection, race status, targeting, and idempotency.

The implementation must document exact JSON request/response shapes for every changed endpoint, status/error codes, idempotency keys, and backend-lag behavior. The existing `RacePowerupEvent.create` model currently defaults to global Prisma; make it transaction-aware before relying on it for atomic activity persistence. Preserve `bara-billing-v1` fields and existing product IDs. Do not add Flutter SKU/policy allowlists or grant benefits solely from client state. Any new capability token must be added to both duplicated `backend_api_service.dart` capability branches and must be optional/additive.

### Locked backend contract (2026-09-17)

This is the exact backend contract for the backend-owned portion of this batch.
It is additive except for the documented terminal-race presentation rule. No
new request parameter, capability token, migration, or release flag is added.

#### `GET /races`

Request: existing authenticated request; no new headers or parameters. The
existing optional `X-Client-Features` header remains tolerant and may be absent.

Response remains the existing object with these required top-level arrays:

```json
{ "active": [], "pending": [], "completed": [] }
```

Every existing race object and field remains available. For the viewer's
favorite projection, `isFavorite` is `true` only when the viewer's accepted
participant row has a non-null `favoritedAt` and the race status is `PENDING`
or `ACTIVE`. For `COMPLETED` and `CANCELLED` races, `isFavorite` is `false` in
this read projection so the row cannot enter the pinned presentation.
The persisted participant `favoritedAt` value is not modified or cleared and
continues to be serialized as its existing ISO timestamp or `null`. Completed
races remain in `completed` for history. The existing response has no cancelled
bucket, so cancelled races remain omitted from these three arrays; the
implementation does not add a new bucket or clear the durable favorite.
Neither terminal status is pinned. Legacy clients continue to receive the same
arrays, fields, and status values and safely ignore any fields they do not know.

Errors are unchanged: `401` with the existing authentication error envelope;
unexpected failures remain `500 {"error":"Internal server error"}`.

#### `PUT /races/:raceId/favorite`

Request remains exactly:

```json
{ "favorite": true }
```

or `{ "favorite": false }`; no idempotency key is required or accepted.

Success remains `200`:

```json
{
  "raceId": "<race id>",
  "isFavorite": true,
  "favoritedAt": "<ISO-8601 timestamp>"
}
```

For `favorite:false`, `isFavorite` is `false` and `favoritedAt` is `null`.
Repeating the same `true` request is idempotent and preserves the original
timestamp. Malformed `favorite` values return `400` with
`{"error":"favorite must be boolean","code":"INVALID_FAVORITE"}`;
non-membership returns `404` with the existing race-not-found envelope; an
unauthenticated request returns `401`.

#### `GET /races/:raceId/feed`

Request remains the existing authenticated request with optional `cursor` and
`limit` query parameters and optional client capability header.

Response remains:

```json
{
  "events": [
    {
      "id": "<event id>",
      "eventType": "POWERUP_REDIRECTED",
      "powerupType": "<PowerupType>",
      "description": "<human-readable description>",
      "actorUserId": "<original attacker or existing event actor>",
      "targetUserId": "<existing event target or null>",
      "metadata": null,
      "createdAt": "<ISO-8601 timestamp>"
    }
  ],
  "nextCursor": "<existing cursor or null>"
}
```

`metadata` remains nullable. Decoy-related events may add the following
nullable `activityV1` object without removing or repurposing existing metadata
keys:

```json
{
  "activityV1": {
    "action": "POWERUP_USE",
    "version": 1,
    "originalAttackerUserId": "<attacker>",
    "originalTargetUserId": "<target before Decoy>",
    "finalTargetUserId": "<final landing or null when blocked>",
    "redirect": {
      "type": "DECOY",
      "ownerUserId": "<Decoy owner>",
      "recipientUserId": "<redirect destination>"
    },
    "outcome": "REDIRECTED"
  }
}
```

`redirect` is `null` when no redirect occurred. `outcome` is one of
`APPLIED`, `REDIRECTED`, `BLOCKED`, or `REFLECTED`; a redirect-then-block
terminal event uses `outcome:"BLOCKED"` while retaining the same original and
final target context. Arrays are not used for single-target activity. Existing
`POWERUP_REDIRECTED` rows remain exactly that event type, retain their existing
`eventType`, `powerupType`, `targetUserId`, `description`, actor attribution,
and legacy flat metadata keys (`attackerUserId`, `decoyOwnerUserId`, and
`redirectedUserId`).

Feed/read errors remain `401` unauthenticated, `404 {"error":"Race not
found"}` for an unavailable race, `403 {"error":"You are not a participant
in this race"}` for an unauthorized reader, and the existing `500` envelope
for unexpected failures. Pagination cursor behavior is unchanged.

#### `POST /races/:raceId/powerups/:powerupId/use`

Request remains the existing optional JSON object; all fields are optional and
no idempotency parameter is added:

```json
{
  "targetUserId": "<optional user id>",
  "targetUserIds": ["<optional Quicksand target ids>"],
  "targetDirection": "<optional>",
  "swapOfferedPowerupId": "<optional>",
  "swapRequestedPowerupId": "<optional>",
  "upgradeLevel": 0,
  "targetEffectId": "<optional>"
}
```

Success remains `200 {"result":<existing result>}` (and, when present, the
existing additive top-level `activeImpactReceipt`; X-Ray also retains its
existing top-level `ok` and `scan`). The durable idempotency key is the held
`powerupId` scoped to its owning user and race: an atomic retry of the same
request cannot consume the item twice, duplicate effects, duplicate coins, or
duplicate canonical activity. A second use after consumption returns `409`
with `{"error":"This powerup has already been used or discarded","code":"POWERUP_ALREADY_USED"}`
when the atomic consume guard detects the race; legacy non-atomic paths retain
their existing `400` error without a code. Existing validation, targeting,
cooldown, retired-item, race-state, and insufficient-coin status/error codes
are unchanged. In particular, Decoy remains a shield and does not create a
new event type or notification fan-out. Any transaction rollback removes the
power-up mutation, effects, coins, and activity row together; notification and
realtime failures remain post-commit/non-fatal.

Backend lag behavior: an older backend may omit `activityV1` and may return
the pre-filter favorite projection; new clients must treat missing metadata as
legacy activity and defensively handle the older favorite value. A new backend
does not require any new request field from frozen clients.

## Scale and correctness requirements

No N+1 reads, unbounded feed/chat queries, participant-wide completion writes, synchronous notification fan-out, provider calls on hot paths, client-side reward RNG, per-item catalog calls, or new Redis key per viewer. Preserve race write fences, lock ordering, conditional power-up consumption, claim/credit idempotency, bounded pagination, cache invalidation, and existing resolution/notification workers.

Redis remains rebuildable cache-only. Settlement and coins remain PostgreSQL-authoritative. Participant bulk writes remain in the existing resolution worker architecture; do not introduce a second queue or request-path bulk writer. Run backend integration tests against a dedicated test database with both local Redis and `REDIS_URL` unset where cache fallback is relevant. Test mixed old/new app-backend payloads.

## Tests-first plan

Write failing focused tests before implementation. Frontend tests must pump real screens/widgets. Backend behavior tests must use public HTTP integration paths where possible and a dedicated test database, never production. Existing assertions must not be weakened or deleted. Run relevant focused suites, then `flutter analyze`, `flutter test`, backend unit/integration commands as applicable, and both-platform accounting before completion.

## Acceptance criteria

- Daily Spin shows every known coin amount/range and safely handles missing data.
- Paywall copy describes only confirmed Gold ad-free benefits.
- Gold store sections are grouped without repeated decorative tile branding and use server policy for CTAs.
- Completed/cancelled races never appear in pinned sections without participant-wide cleanup writes.
- Team Chat measurement is bounded and does not claim unavailable open/read metrics.
- Decoy events preserve original attacker, original target, Decoy owner, final target, power-up, and outcome without misleading team attribution.
- Old clients remain compatible; mutations remain transactional/idempotent; no scale regression is introduced.

## Manual UI-placement test plan

The UI planner identified unrelated pre-existing placement work in its broad repository scan. The applicable checklist for this batch is:

1. **Daily Spin:** On narrow iOS and Android devices with enlarged text, verify the amount remains inside each wheel/reel tile and result modal; no generic `Coins` appears when amount/range exists; missing amount remains a safe fallback without clipping.
2. **Bara Gold paywall:** Verify the revised benefit copy wraps inside the existing benefit card on narrow devices, appears once, and does not claim unrelated rewarded placements.
3. **Shop:** Verify Standard and Bara Gold subsection headers and grids at narrow/wide widths for power-ups, avatars, accessories, and any mixed category. Verify no duplicate Gold outline/label remains and no tile is duplicated in both groups. Check owned, locked, insufficient-coin, and missing-IAP states.
4. **Pinned races:** Verify an active pinned race appears, then complete it while the app is open and verify the pinned card disappears after realtime refresh. Reopen after completion and verify it remains absent while completed history remains available. Repeat for team races and narrow layouts.
5. **Race activity:** In a real active team race with long activity text, verify normal and Decoy redirect sentences wrap completely inside the activity panel, preserve the original attacker, and do not overlap adjacent rows. Repeat in the onboarding/demo race and tab tutorial race-detail preview; ensure no old duplicate activity position remains.
6. **Team Chat:** Verify existing chat placement and team-only audience behavior remain unchanged while any optional `team_chat_opened` instrumentation is added. Check active team race, completed race, narrow layout, and tutorial/demo mirrors if instrumentation is present there.
7. **Mirrors/fixtures:** Check demo services/engine, tab tutorial previews, onboarding, hand-copied tab chrome, and spotlight keys for every moved or removed store, Daily Spin, pinned-race, activity, and chat element. Keep positive `stepsUntilNextPowerup` and tutorial fixture identity fields intact where those fixtures are used.

Surfaces confirmed unaffected by this batch: OS notification-banner placement, main/tab bar ordering, Create Race/share-link/tournament entry, and RacesTab effect plates unless the implementation changes them.

## Revision log

- Initial draft: consolidated from the approved user specification and repository research report.
- Gap pass 1: added explicit non-goals, additive API compatibility, no-production-query constraint, backend-authority boundary, bounded Team Chat instrumentation, and tests-first requirements.
- Gap pass 2: added cross-platform/old-client safety, transaction/idempotency requirements, AoE metadata handling, race-completion write-avoidance, and manual UI-placement coverage requirement.
- Architect review: pending.
- Architect review: required changes folded: exact endpoint/error/idempotency contracts, preservation of `POWERUP_REDIRECTED`, transaction-aware event persistence, backend-authoritative billing/catalog, completed-race filtering without cleanup fan-out, Redis/cache classification, capability-branch parity, and mixed-version tests.
- UI test-planner review: applicable checklist folded above; unrelated pre-existing placement findings excluded from this batch.
- Game-analyst review: `SOUND`; no required changes. Daily Spin labels, Gold copy, and store presentation have zero odds, price, reward, source, sink, or EV delta. Ranges must remain ranges and non-members must not receive purchase actions from premium classification alone.
