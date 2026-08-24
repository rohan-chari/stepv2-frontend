# Decoy redirection and concurrency requirements

## Summary & user story

As a racer, I can arm at most one active Decoy in a race, and that Decoy protects me from every supported offensive powerup, including Rainstorm and Power Outage, regardless of race format.

## Scope / non-goals

In scope: backend validation for one active Decoy per `(race, user)`, race-format-independent redirection of Rainstorm and Power Outage, and end-to-end/integration regression coverage. Existing Decoy redirect-pool rules, shield ordering, team eligibility, and one-hop behavior remain unchanged unless required to make these two powerups redirect.

Out of scope: balance changes, new UI, catalog changes, migrations that alter historical effects, or release flags.

## API contract

`POST /races/:raceId/powerups/:id/use` remains the existing endpoint and request/response shape. A second active Decoy is rejected with HTTP `409` and `{ error, code: "DECOY_ACTIVE" }`; the held item remains `HELD` via `retainHeld:true`. Older clients already display the server `error` string and safely ignore the additive code.

For AoE results, the existing outer `{ result }` wrapper remains. Additive fields are `redirectedToUserIds` (unique final destinations, deterministic response order), `decoyBlockedCount`, and `affected` (unique final effect targets). Preserve `redirected`, `redirectedBy: "DECOY"`, and singular `redirectedToUserId` only when exactly one redirect occurred. The original area-of-effect operation must not be applied to the Decoy holder; each victim is processed once, each live Decoy is consumed once, and the effect is applied once to the selected destination with no second Decoy chain. A missing destination fizzles only that victim’s slot; a two-participant race therefore consumes the Decoy as a block. Existing clients can ignore additive result fields and continue rendering the normal powerup result.

## Data model / migrations

No schema migration is required. Existing `RaceActiveEffect` rows are authoritative; active means `status: "ACTIVE"` and `expiresAt > now`. The existing transaction wrapper must lock the race/participants in its established order, check and create the Decoy inside that transaction, and retain Postgres as the authority; no Redis lock, participant bulk write, or inline settlement is allowed. An expired-but-still-active historical row is inactive for validation/interception and is not rewritten. Historical duplicate rows, if found, are not rewritten by this change. The existing post-commit resolution enqueue remains unchanged.

## Frontend plan

No new screen or placement is required. The existing use-powerup error path must continue to show the backend error safely; missing `code` or redirect fields must default to the current generic behavior. iOS and Android share the same Dart path and require no platform-specific changes.

## Backward compatibility & rollout

Deploy backend first, then the app only if a client-side copy change is needed. Frozen clients remain compatible: the endpoint is unchanged, error text remains present, and new fields are additive. No release flag or test-only gate is permitted.

## Test plan (tests first)

1. Backend integration tests through the public HTTP endpoint prove a second Decoy is rejected, the inventory item is retained, expired Decoys can be re-armed, and concurrent duplicate activation leaves exactly one active row.
2. Backend integration tests prove Rainstorm and Power Outage redirect through Decoy in solo (including 3+ runners), head-to-head, and 2v2/larger team races, including no-destination fizzle/block, one-participant behavior, multiple Decoys, duplicate destinations, and destination Umbrella/Socks processing. Team rules are explicit: AoE targets enemy-team runners only; an enemy-team Decoy may redirect to an eligible caster teammate; caster teammates are never AoE victims.
3. Existing powerup suites remain unchanged except for mechanical fixture updates required by the public behavior.
4. Frontend widget/integration coverage is added only if the current response model or error renderer requires a code/redirect parsing change.

## Acceptance criteria / definition of done

- A user cannot have more than one active Decoy per race, including concurrent requests.
- Rainstorm is Decoy-redirectable in every race format and does not affect the Decoy holder when redirected.
- Power Outage is Decoy-redirectable in every race format and does not jam the Decoy holder when redirected.
- Rainstorm with no other active runner preserves its existing rejection; Power Outage with no affected runner preserves its existing zero-affected result.
- Existing Mirror, Socks, team-pool, one-hop, and two-player behavior remains green.
- Tests are written first and pass against a dedicated test database; `npm run test:unit`, the relevant integration suites, `flutter analyze`, and relevant Flutter tests are green.
- Architect and code-reviewer reviews run before the production greenlight; version-skew and both-platform implications are explicitly verified.

## Revision log

- Pass 1: narrowed the change to existing endpoint/effect machinery, made the duplicate rule concurrency-safe, and specified additive API compatibility.
- Pass 2: added explicit solo/head-to-head/team coverage, the two-player fizzle case, and preservation of existing shield-chain/team eligibility behavior.
- Architect review: required revisions applied — exact `409` contract, transaction authority/ordering, expiry semantics, per-victim AoE algorithm, team/solo edge cases, and partial-outcome fields/tests.
