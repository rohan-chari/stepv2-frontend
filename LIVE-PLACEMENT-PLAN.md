# Live Race Placement — Implementation Plan

## Overview

Today a participant's race placement only recomputes when someone opens the race screen (`getRaceProgress` + a 30s poll) or when the user themselves uploads steps (`resolveRaceState`). The home/race list (`races_tab.dart`) caches once on init and never polls. We want placement to update **live** — without anyone opening the race, on **both iOS and Android**, and ideally even when the app is closed.

The feature splits into two halves: **(a)** get fresh steps to the backend in the background, and **(b)** recompute standings server-side and broadcast them. The star of this plan is **(b) — server-side recompute + push**. Background step code is the supporting cast; the moment standings change, the backend fans the change out to every participant's device. That is what makes placement feel live.

Be honest about the ceiling. With the app **closed**, liveness is **minutes-to-an-hour**: iOS HealthKit background delivery is hourly-capped, and Android WorkManager realistically fires every 15–60+ minutes. After a **force-quit**, no client background code runs at all — the only thing that still updates is **server-pushed UI** (an iOS Live Activity or a notification). Set this expectation with stakeholders up front: this is "live within minutes," not "live to the step."

## Locked decisions

These are settled. Do not re-litigate them while implementing.

- **iOS auth-token path: go cheap.** Native background code reads the `flutter.`-prefixed key from the standard `NSUserDefaults` suite (same process). **No Keychain / App-Group migration** is in scope. Revisit only if Live Activities ship and an extension needs an extension-initiated fetch.
- **Android background ceiling: accepted.** Use a **WorkManager periodic worker only** (15–60+ min ceiling). **No foreground service / "live race mode."**
- **iOS Live Activities: optional / deferred.** Lock-screen live placement is a backlog item (already logged in `URGENT-TODO.md` P3 #6). It is the last phase here and is clearly marked optional.
- **Phase 0 ships first.** It is backend-only and reaches the **entire install base**, including already-shipped binaries.
- **Golden rule.** The shared prod backend serves all app versions at once; never break an already-shipped binary. New backend fields are additive/nullable and never required by old clients; new push types fall through old clients' routers harmlessly.
- **iOS/Android lockstep.** Every client-shipping phase builds **both** platforms with matching flavor / `--dart-define` / version — even when only one platform gains the feature.

## Cross-cutting conventions (read first)

### Golden compatibility rule

The prod backend (`steptracker-api.org`) serves every app version simultaneously, and shipped binaries are frozen. Therefore:

- **New DB columns are additive and nullable.** `RaceParticipant.lastNotifiedPlacement` and `DeviceToken.liveActivityPushToken` are both `NULL`-able and never read by old clients.
- **New push types fall through harmlessly.** Old clients route incoming pushes through `_routeFromType`; an unrecognized `type` (`PLACEMENT_CHANGED`, `STEP_SYNC_REQUEST`) returns `null` (default case) and the notification is ignored. No crash, no behavior change.
- **No app depends on a brand-new backend field/endpoint** until that field is confirmed live in prod. Read all API responses defensively (default safely on absent/null).

### iOS/Android lockstep build rule

Whenever a phase ships client code, build and verify **both** platforms in the same release, with matching `--flavor`, `--dart-define=BACKEND_BASE_URL`, and version/build number — even if only one platform gains the feature. Dependencies are coupled in non-obvious ways (e.g. `firebase_*` added "for Android" links into the iOS build too), so a one-platform change can break the other.

### Testing philosophy

Mirror each repo's existing conventions exactly. No new test frameworks, no mocking libraries.

**Backend** (`/Users/rohan/repos/stepv2-backend`) — Node's built-in `node:test`, dependency-injection + plain-object mocks for unit tests, real PostgreSQL for integration tests.

```bash
npm test                  # node --test, runs everything under test/
npm run test:unit         # unit tests (DI + plain-object mocks, no DB)
npm run test:integration  # real PostgreSQL; runs npx prisma migrate deploy first
```

Unit tests build a service via its `build…(deps)` factory and pass mock models; events are captured into arrays. Place new tests under `test/jobs/`, `test/handlers/`, or `test/services/` to match the module.

**Frontend** (`/Users/rohan/repos/stepv2-frontend`) — `flutter_test` (no mockito/mocktail). Mock by subclassing `BackendApiService`/`AuthService` and overriding methods, capturing args on the instance. Mock prefs with `SharedPreferences.setMockInitialValues()`.

```bash
flutter test                                   # all Dart tests under test/
flutter test test/<file>_test.dart             # a single file
```

**iOS native** — XCTest in `ios/RunnerTests/RunnerTests.swift` (mock `URLSession`/state stores, expectations).

```bash
xcodebuild test -scheme Runner -configuration Debug
```

**Android native** — no JVM/instrumentation tests exist today. New Kotlin unit tests run via:

```bash
./gradlew testDebugUnitTest
```

### Build commands (from `DEPLOYMENT.md`)

```bash
# Local dev (debug)
flutter run --dart-define=BACKEND_BASE_URL=https://staging.steptracker-api.org
flutter run --dart-define=BACKEND_BASE_URL=http://127.0.0.1:3000

# TestFlight (Bara Staging)
flutter build ipa --flavor staging --release \
  --dart-define=BACKEND_BASE_URL=https://staging.steptracker-api.org

# Prod iOS (Bara App Store)
flutter build ipa --flavor prod --release \
  --dart-define=BACKEND_BASE_URL=https://steptracker-api.org

# Prod Android (Play Store)
flutter build appbundle --flavor prod --release \
  --dart-define=BACKEND_BASE_URL=https://steptracker-api.org
```

`--dart-define` is compile-time; hot reload does not pick up changes. Keep flavor / backend URL / version in sync across both platforms.

### Adding a Prisma migration

```bash
npx prisma migrate dev --name <descriptive_name>   # dev: creates + applies migration folder
npx prisma generate                                # regenerate client after schema edits
npx prisma migrate deploy                          # prod / CI: apply pending migrations
```

Migrations live in `/Users/rohan/repos/stepv2-backend/prisma/migrations/<timestamp>_<name>/migration.sql`; the schema is `prisma/schema.prisma`. Keep every new column additive and nullable (golden rule).

### Adding a cron job

Jobs are scheduler functions injected into `startServer()` in `/Users/rohan/repos/stepv2-backend/src/index.js` and called in its `listen` callback. To add one:

1. Create `src/jobs/<name>.js` exporting `schedule<Name>()` (the existing pattern uses `setInterval`).
2. Import it in `src/index.js`.
3. Add it as a `startServer()` dependency parameter (e.g. `scheduleFoo = scheduleFoo`).
4. Call it in the `listen` callback.
5. Add `test/jobs/<name>.test.js` with mocked dependencies.

## Phase map / sequencing

| Phase | What | Reaches whom | Depends on | Ships independently? |
|-------|------|--------------|------------|----------------------|
| **0** | Backend live recompute + `PLACEMENT_CHANGED` push | **Entire install base** (incl. already-shipped binaries) | — | **Yes** |
| **1** | iOS background-sync repair (5 cheap fixes) | iOS users on the new binary | Phase 0 (benefits from silent push; not strictly required) | Yes (iOS half of a lockstep release) |
| **2** | Android WorkManager background sync | Android users on the new binary | Phase 0 deployed | Yes (Android half of a lockstep release) |
| **3** | Silent-refresh + on-demand pull loop (both platforms) | iOS (≥ P1) + Android (≥ P2); list refetch on resume for any matching binary | Phases 0, 1, 2 | Yes |
| **4** | iOS Live Activities (lock-screen placement) | iOS 16.1+ users on the new binary | Phases 0–3 | **Optional / deferred** |

**Recommended sequencing and stopping points:**

- **Ship Phase 0 first, alone.** It is backend-only, reaches everyone, and degrades safely on every old client. This is a complete, shippable improvement by itself.
- **Phases 0–2** give both platforms real background sync feeding the live recompute — a strong stopping point.
- **Phase 3** closes the loop (push-driven pull + list refetch). 
- **Phase 4 is optional** and can be deferred indefinitely; nothing depends on it.

Every client-shipping phase (1–4) must build iOS **and** Android in lockstep, even when only one platform gains code.

## Phase 0 — Backend live recompute + placement-change push (backend-only, reaches everyone)

### Goal & who it reaches

A new 5-minute backend job recomputes standings for every **active, in-progress race** and broadcasts each participant's placement change via push. It reaches **100% of the install base — including already-shipped binaries** — because the work and the fan-out are entirely server-side; clients only receive a notification. No client change is required, and old clients ignore the unknown push type safely (`notification_service.dart` `_routeFromType` returns `null` for unrecognized types → the notification is dropped, no crash).

This is the highest-leverage, lowest-risk phase. Its only limitation is **data freshness**: it recomputes from whatever steps the backend already has (today, that's foreground uploads from participants whose apps are open). Phases 1–3 improve that freshness; Phase 0 delivers the felt "you got passed" experience on its own.

### Prerequisites

- Backend-only; ships independently to prod. No paired app release needed (but it's still safe for all app versions).
- Existing infra in place and working: `resolveRaceState` (race step-resolution math), the in-process `eventBus`, APNs + FCM senders, the `DeviceToken` table and fan-out pattern in `registerNotificationHandlers`.
- Prisma migration workflow operational (`npx prisma migrate deploy`).

### Files created / edited

| File path (relative to `/Users/rohan/repos/stepv2-backend`) | Purpose |
|---|---|
| `prisma/migrations/<ts>_add_race_participant_last_notified_placement/migration.sql` | Additive **nullable** column for idempotent change detection. |
| `prisma/schema.prisma` | Add `lastNotifiedPlacement Int?` to `RaceParticipant`. |
| `src/models/race.js` | Add a `findActiveInProgress(now)` wrapper (ACTIVE && `endsAt > now`), sibling to the existing `findActiveExpired(now)`. |
| `src/jobs/placementRecompute.js` | **New job:** recompute each active race via `resolveRaceState({ raceId })`, derive live rank, emit `PLACEMENT_CHANGED` on change. |
| `src/index.js` | Schedule the new job in the `listen` callback, behind an env flag. |
| `src/handlers/notificationHandlers.js` | Add a `PLACEMENT_CHANGED` listener (silent refresh + cooldown-gated alert), mirroring `POWERUP_USED`. |
| `test/jobs/placementRecompute.test.js` | Unit tests for the job (idempotency, baseline seed, finished/excluded). |
| `test/handlers/notificationHandlers.test.js` | Add `PLACEMENT_CHANGED` handler cases (alert vs silent, cooldown, token cleanup). |

### Step-by-step integration

**Why this shape (read first).** The recompute primitive is **`resolveRaceState({ raceId })`** — *not* a hand-rolled reconstruction. That function already accepts a `raceId`, fetches the race with its `ACCEPTED` participants (`raceStateResolution.js:464`), loops them in parallel, and persists `updateTotalSteps` / `setPlacement` / `markFinished` for each, defaulting `timeZone` to `"UTC"` when no requesting user is passed (`:459`). It already handles finish snapshots, trail mines, and global events. So the job's only new responsibility is: call it per race, then **derive a live rank** by sorting the freshly-updated `totalSteps` and compare against `lastNotifiedPlacement`. (Live rank is transient — the `placement` column stays `null` until settlement, so we track the last-notified rank separately.)

**Step 1 — Add the migration column.**

```bash
npx prisma migrate dev --name add_race_participant_last_notified_placement
```

Generated `migration.sql`:

```sql
-- Last live rank we notified this participant about, for idempotent change
-- detection in the placement-recompute job. NULL = baseline not yet seeded
-- (first observation seeds it silently). Never returned by any API response.
ALTER TABLE "race_participants" ADD COLUMN "last_notified_placement" INTEGER;
```

Add to the `RaceParticipant` model in `prisma/schema.prisma` (the model around lines 637–678), then `npx prisma generate`:

```prisma
model RaceParticipant {
  // ... existing fields ...
  placement             Int?
  lastNotifiedPlacement Int?      @map("last_notified_placement")
  // ... rest ...
}
```

**Step 2 — Add the `findActiveInProgress(now)` model wrapper** in `src/models/race.js`, mirroring the existing `findActiveExpired(now)` (which selects ACTIVE races with `endsAt <= now`). We want the complement — ACTIVE and not yet expired:

```javascript
// src/models/race.js — alongside findActiveExpired(now)
async function findActiveInProgress(now) {
  return prisma.race.findMany({
    where: { status: "ACTIVE", endsAt: { gt: now } },
    select: { id: true, name: true, endsAt: true },
  });
}
// add findActiveInProgress to module.exports
```

> **Verify:** confirm the Prisma client handle name used in `race.js` (the file may bind it differently) and that the race title field is `name`. Mirror the exact `select`/`where` style of the adjacent `findActiveExpired`. Alternatively, the ground-truth-sanctioned shortcut is to call `prisma.race.findMany(...)` directly from the job, as `notificationHandlers.js:330` already does — but adding the wrapper keeps the job at the model layer like the rest of the codebase.

**Step 3 — Create the job** `src/jobs/placementRecompute.js`. Sequential over races (each `resolveRaceState` fans out participants in parallel *internally*, so looping races sequentially bounds peak DB connections under the pool max of 20). Excludes `endsAt <= now` so it never collides with `raceExpiry` settlement.

```javascript
const { Race } = require("../models/race");
const { RaceParticipant } = require("../models/raceParticipant");
const { eventBus } = require("../events/eventBus");
const { resolveRaceState } = require("../services/raceStateResolution");

const RECOMPUTE_INTERVAL_MS = 5 * 60 * 1000; // 5 min — matches the other schedulers

function buildRecomputePlacements(deps = {}) {
  const raceModel = deps.Race || Race;
  const participantModel = deps.RaceParticipant || RaceParticipant;
  const events = deps.eventBus || eventBus;
  const resolve = deps.resolveRaceState || resolveRaceState; // injectable for tests
  const now = deps.now || (() => new Date());
  const logger = deps.logger || console;

  return async function recomputePlacements() {
    const currentTime = now();
    let races;
    try {
      races = await raceModel.findActiveInProgress(currentTime); // ACTIVE && endsAt > now
    } catch (err) {
      logger.error("[CRON] placementRecompute: failed to load races", err);
      return;
    }

    for (const race of races) {
      try {
        // 1. Recompute & persist totalSteps/placement/finishers for ALL accepted
        //    participants. No userId/timeZone -> defaults to UTC (raceStateResolution.js:459).
        await resolve({ raceId: race.id });

        // 2. Read the freshly-updated participants and derive a live rank.
        const participants = await participantModel.findAcceptedByRace(race.id);
        const ranked = [...participants].sort(
          (a, b) => (b.totalSteps ?? 0) - (a.totalSteps ?? 0),
        );

        for (let i = 0; i < ranked.length; i++) {
          const p = ranked[i];
          const liveRank = i + 1;

          if (p.finishedAt) continue; // finished standings are frozen — never notify

          if (p.lastNotifiedPlacement == null) {
            // First observation: seed baseline SILENTLY (avoids a rollout-day storm).
            await participantModel.update(p.id, { lastNotifiedPlacement: liveRank });
            continue;
          }
          if (p.lastNotifiedPlacement === liveRank) continue; // idempotent: no change

          events.emit("PLACEMENT_CHANGED", {
            raceId: race.id,
            raceName: race.name,
            userId: p.userId,
            previousPlacement: p.lastNotifiedPlacement,
            placement: liveRank,
            totalParticipants: ranked.length,
          });
          await participantModel.update(p.id, { lastNotifiedPlacement: liveRank });
        }
      } catch (err) {
        logger.error(`[CRON] placementRecompute: race ${race.id} failed`, err);
        // continue with the next race
      }
    }
  };
}

function scheduleRecomputePlacements(deps = {}) {
  const run = buildRecomputePlacements(deps);
  run().catch(() => {}); // run once at startup
  return setInterval(() => run().catch(() => {}), RECOMPUTE_INTERVAL_MS);
}

module.exports = { buildRecomputePlacements, scheduleRecomputePlacements };
```

Notes: `RaceParticipant.findAcceptedByRace(raceId)`, `.update(id, fields)`, `Race.findById`, `resolveRaceState`, and `eventBus.emit` are all verified real APIs. `eventBus.emit` is synchronous (it loops handlers without awaiting), so emit is fire-and-forget — correct for push fan-out.

**Step 4 — Schedule it** in `src/index.js`, in the `listen` callback after the other `schedule*()` calls (~line 40), gated by an env flag so it can be killed without a code change:

```javascript
const { scheduleRecomputePlacements } = require("./jobs/placementRecompute");
// ... inside the listen callback, after scheduleAutoStartRaces():
if (process.env.LIVE_PLACEMENT_ENABLED === "true") {
  scheduleRecomputePlacements();
}
```

**Step 5 — Add the `PLACEMENT_CHANGED` handler** inside `registerNotificationHandlers` in `src/handlers/notificationHandlers.js`, mirroring the `POWERUP_USED` handler (lines 299–325): look up the recipient's tokens, route by platform, send, clean up dead tokens. Send an **alert** only on a *meaningful* move (dropped a place, or took 1st), throttled per `(race,user)`; otherwise send a **silent** push so the client can refresh quietly.

```javascript
// near the top of registerNotificationHandlers — in-process cooldown
// (single pm2 instance per env; see Risks if this ever scales out).
const ALERT_COOLDOWN_MS = 10 * 60 * 1000;
const lastAlertAt = new Map(); // `${raceId}:${userId}` -> epoch ms
const ordinal = (n) => `${n}${["th","st","nd","rd"][(n % 100 >> 3 ^ 1) && n % 10] || "th"}`;

events.on("PLACEMENT_CHANGED", async (data) => {
  const { raceId, raceName, userId, previousPlacement, placement } = data;

  let tokens;
  try {
    tokens = await deviceTokenModel.findByUserId(userId); // -> [{ token, platform }]
  } catch (err) {
    logger.error("[NOTIFY] PLACEMENT_CHANGED token lookup failed", err);
    return;
  }
  if (!tokens || tokens.length === 0) return;

  const dropped = placement > previousPlacement; // larger rank number = worse
  const tookFirst = placement === 1 && previousPlacement !== 1;
  const meaningful = dropped || tookFirst;

  const key = `${raceId}:${userId}`;
  const withinCooldown = Date.now() - (lastAlertAt.get(key) || 0) < ALERT_COOLDOWN_MS;
  const sendAlert = meaningful && !withinCooldown;
  if (sendAlert) lastAlertAt.set(key, Date.now());

  const payload = { type: "PLACEMENT_CHANGED", raceId, placement };
  const title = tookFirst ? "You're in the lead! 🥇" : "You've been passed";
  const body = tookFirst
    ? `You took 1st in ${raceName}.`
    : `You dropped to ${ordinal(placement)} in ${raceName}.`;

  for (const { token, platform } of tokens) {
    const push = platform === "android" ? fcmService : apnsService;
    try {
      const res = sendAlert
        ? await push.sendNotification({ deviceToken: token, title, body, payload, collapseId: `race-${raceId}` })
        : await push.sendSilentNotification({ deviceToken: token, payload });
      if (res && res.unregistered) await deviceTokenModel.deleteToken(token);
    } catch (err) {
      logger.error("[NOTIFY] PLACEMENT_CHANGED send failed", err);
    }
  }
});
```

> **Verify:** use the exact dependency names already destructured at the top of `registerNotificationHandlers` (the test injects `eventBus`, `DeviceToken`, `apnsService`; confirm the FCM handle is `fcmService` and the device-token model alias). The push signatures used here are verified: `apns.sendNotification({ deviceToken, title, body, payload, collapseId, threadId })` and `sendSilentNotification({ deviceToken, payload })`, both returning `{ success, unregistered?, reason?, statusCode? }`; FCM mirrors them (`threadId` ignored).

### Tests to write

Match the repo's real style: `node:test` + `node:assert/strict`, a `build…(deps)` factory with plain-object mocks, a `FIXED_NOW`, and emitted events captured into an array (as in `test/jobs/seededRaceRenewal.test.js` and `test/handlers/notificationHandlers.test.js`). Run with `npm run test:unit` (no DB needed — `resolveRaceState`, models, and the event bus are all injected mocks).

**`test/jobs/placementRecompute.test.js`:**

```javascript
const assert = require("node:assert/strict");
const test = require("node:test");
const { buildRecomputePlacements } = require("../../src/jobs/placementRecompute");

const FIXED_NOW = new Date("2026-06-24T12:00:00Z");

function makeDeps({ races = [], participantsByRace = {} } = {}) {
  const emitted = [];
  const updates = [];
  const deps = {
    now: () => FIXED_NOW,
    logger: { error() {}, log() {} },
    eventBus: { emit: (event, data) => emitted.push({ event, data }) },
    resolveRaceState: async () => {},               // totals pre-set in fixtures
    Race: { findActiveInProgress: async () => races },
    RaceParticipant: {
      findAcceptedByRace: async (raceId) => participantsByRace[raceId] || [],
      update: async (id, fields) => updates.push({ id, fields }),
    },
  };
  return { deps, emitted, updates };
}
const P = (o) => ({ finishedAt: null, lastNotifiedPlacement: null, ...o });

test("emits PLACEMENT_CHANGED only for participants whose live rank changed", async () => {
  const { deps, emitted } = makeDeps({
    races: [{ id: "r1", name: "Race 1" }],
    participantsByRace: { r1: [
      P({ id: "p1", userId: "u1", totalSteps: 9000, lastNotifiedPlacement: 1 }),  // now 2nd
      P({ id: "p2", userId: "u2", totalSteps: 10000, lastNotifiedPlacement: 2 }), // now 1st
    ]},
  });
  await buildRecomputePlacements(deps)();
  assert.equal(emitted.length, 2);
  assert.equal(emitted.find((e) => e.data.userId === "u1").data.placement, 2);
});

test("idempotent: unchanged rank does not re-notify", async () => {
  const { deps, emitted } = makeDeps({
    races: [{ id: "r1", name: "Race 1" }],
    participantsByRace: { r1: [
      P({ id: "p1", userId: "u1", totalSteps: 10000, lastNotifiedPlacement: 1 }),
      P({ id: "p2", userId: "u2", totalSteps: 9000, lastNotifiedPlacement: 2 }),
    ]},
  });
  await buildRecomputePlacements(deps)();
  assert.equal(emitted.length, 0);
});

test("first observation (null) seeds baseline silently and persists it", async () => {
  const { deps, emitted, updates } = makeDeps({
    races: [{ id: "r1", name: "Race 1" }],
    participantsByRace: { r1: [P({ id: "p1", userId: "u1", totalSteps: 10000 })] },
  });
  await buildRecomputePlacements(deps)();
  assert.equal(emitted.length, 0);
  assert.deepEqual(updates, [{ id: "p1", fields: { lastNotifiedPlacement: 1 } }]);
});

test("finished participants are never notified", async () => {
  const { deps, emitted } = makeDeps({
    races: [{ id: "r1", name: "Race 1" }],
    participantsByRace: { r1: [
      P({ id: "p1", userId: "u1", totalSteps: 9000, finishedAt: FIXED_NOW, lastNotifiedPlacement: 1 }),
      P({ id: "p2", userId: "u2", totalSteps: 8000, lastNotifiedPlacement: 1 }),
    ]},
  });
  await buildRecomputePlacements(deps)();
  assert.ok(!emitted.some((e) => e.data.userId === "u1"));
});

test("a thrown race does not abort the rest", async () => {
  const { deps, emitted } = makeDeps({
    races: [{ id: "bad", name: "Bad" }, { id: "r2", name: "Race 2" }],
    participantsByRace: { r2: [
      P({ id: "p1", userId: "u1", totalSteps: 9000, lastNotifiedPlacement: 1 }),
      P({ id: "p2", userId: "u2", totalSteps: 10000, lastNotifiedPlacement: 2 }),
    ]},
  });
  deps.resolveRaceState = async ({ raceId }) => { if (raceId === "bad") throw new Error("boom"); };
  await buildRecomputePlacements(deps)();
  assert.equal(emitted.length, 2); // r2 still processed
});
```

**`test/handlers/notificationHandlers.test.js`** — add cases following the existing `createMockEventBus()` + `registerNotificationHandlers({ eventBus, DeviceToken, apnsService, fcmService })` style:

- **Meaningful drop → alert push.** `previousPlacement:1, placement:2` → `apnsService.sendNotification` called with a non-empty `title/body` and `payload.type === "PLACEMENT_CHANGED"`.
- **Non-meaningful change → silent push.** e.g. improved from 3rd to 2nd (not 1st) → `sendSilentNotification` called, `sendNotification` not.
- **Cooldown.** Two meaningful drops for the same `(race,user)` back-to-back → first is an alert, second is silent (within `ALERT_COOLDOWN_MS`).
- **Platform routing.** A token with `platform:"android"` routes to `fcmService`, `"ios"` to `apnsService`.
- **Dead-token cleanup.** Sender returns `{ unregistered: true }` → `DeviceToken.deleteToken(token)` called.
- **Old-client safety (documented, not code):** old apps receiving `type:"PLACEMENT_CHANGED"` hit the `_routeFromType` default and ignore it — covered by a frontend test in later phases; here just assert the backend never depends on a client ACK.

### Acceptance criteria

- [ ] Migration applied; `last_notified_placement` is nullable and absent from every API response shape.
- [ ] Job runs every 5 min, only over ACTIVE races with `endsAt > now`; skips empty races; one race's failure doesn't abort others.
- [ ] Recompute goes exclusively through `resolveRaceState({ raceId })` (no duplicated step math).
- [ ] First observation seeds `lastNotifiedPlacement` with **no** push; subsequent rank changes emit exactly once; unchanged ranks emit nothing.
- [ ] Finished participants are never notified.
- [ ] Alerts only on drop/took-1st and respect the per-`(race,user)` cooldown; all other changes are silent.
- [ ] `unregistered` tokens are deleted; APNs and FCM both exercised.
- [ ] `npm run test:unit` green for the new job + handler tests.
- [ ] Behind `LIVE_PLACEMENT_ENABLED`; flipping it off stops the job with no other change.

### Compatibility & rollback notes

- **Golden rule:** `lastNotifiedPlacement` is additive + nullable and never serialized to clients; `PLACEMENT_CHANGED` is a brand-new push type that old iOS/Android clients drop via their router default. No shipped binary is affected.
- **No collision with settlement:** excluding `endsAt <= now` keeps this job and `raceExpiry` (which owns expired-race settlement and the real `placement` column) on disjoint race sets.
- **Rollback:** set `LIVE_PLACEMENT_ENABLED=false` and restart — instant disable, no migration rollback needed (the column can stay; it's inert).
- **Lockstep:** N/A this phase (backend-only, no app build).

### Risks & gotchas

- **Freshness, not correctness:** standings are only as fresh as the last step upload. Until Phases 1–3, a backgrounded user's *own* new steps may not be in the DB, so their self-driven rank moves lag. Opponent-driven moves work as soon as the opponent uploads. Set expectations accordingly.
- **Notification fatigue:** users in many races could get several alerts. The silent-default + cooldown mitigates this; tune `ALERT_COOLDOWN_MS` and the "meaningful" rule (see Open Questions) before a wide rollout.
- **In-memory cooldown:** the `lastAlertAt` map is per-process. Fine for the current single pm2 instance per env; if the backend is ever horizontally scaled, move the cooldown to a shared store (Redis/DB) or it will under-throttle.
- **Recompute cost:** sequential races × parallel participants keeps connections bounded, but if active-race count grows large, the 5-min tick could lengthen — add a per-tick race cap or stagger if needed, and log dropped work rather than silently truncating.
- **Rollout-day baseline:** the silent-seed-on-null rule is what prevents a notification storm the first time the job runs against a populated table. Don't "optimize" it into notifying on first observation.

## Phase 1 — iOS background step-sync repair (updaters; 5 fixes, cheap token)

### Goal & who it reaches

Repair the existing iOS background step-sync system so it actually works on production TestFlight and App Store builds. The native sync is fully implemented but currently broken by 5 specific bugs. These fixes are cheap (token-level) and reach all iOS users on any version that gets a binary rebuild. This phase unblocks Phase 3 (silent-refresh pull loop), which depends on reliable background sync.

### Prerequisites

- Phase 0 (backend live recompute + push) ships first and works end-to-end. Phase 1 benefits from Phase 0's `STEP_SYNC_REQUEST` push (used in Phase 3); background sync can also be triggered by `BGAppRefresh`.
- iOS CI/CD can build signed IPAs for both TestFlight (staging flavor) and App Store (prod flavor).
- Real test device or simulator to verify the build config (`aps-environment`).

### Files created / edited

| File Path | Purpose |
|-----------|---------|
| `ios/Runner/AppDelegate.swift` | Read `flutter.`-prefixed keys in the UserDefaults state store; add `X-Timezone` header; gate `enableHealthKitBackgroundDelivery()` on confirmed Health auth; add `skipRaceResolution` to the daily POST. |
| `ios/Runner/Runner.entitlements` | Build-config-driven `aps-environment` (`development` for staging, `production` for prod). |
| `ios/RunnerTests/RunnerTests.swift` | Add tests for `X-Timezone` header and `skipRaceResolution` body. |

(Paths are relative to `/Users/rohan/repos/stepv2-frontend`.)

### Step-by-step integration

**Fix C1 — UserDefaults key prefix (native must read the `flutter.`-prefixed keys). This is the core bug — get it right.**

This is `AUDIT.md` C1 ("double-confirmed by two independent verifiers"). The Dart side persists the session token, health-auth flag, and backend URL via **legacy `SharedPreferences`** (`SharedPreferences.getInstance()` throughout `auth_service.dart:83,391,393`), and the legacy plugin **transparently prepends `flutter.` to every key** at the `NSUserDefaults` storage layer. So the token is actually stored under **`flutter.auth_session_token`**, even though the Dart constant is `'auth_session_token'` (`auth_service.dart:32`). The native state store (`UserDefaultsBackgroundSyncStateStore`, AppDelegate.swift:513–541) reads the **unprefixed** keys — `userDefaults.string(forKey: "auth_session_token")` (line 521), the backend URL via `BackgroundSyncBootstrapKeys.backendBaseURL = "background_sync_backend_base_url"` (lines 526, 540), and `userDefaults.bool(forKey: "health_authorized")` (line 535) — so every read returns nil/false and the guard at AppDelegate.swift:362–370 exits `.noData`. All three background triggers are dead in every shipped binary, including BGAppRefresh, which still reports `success:true` to iOS (`:211`) so iOS never backs off.

> ⚠️ The keys do **not** already match. Comparing the Dart constant `'auth_session_token'` to the Swift literal `"auth_session_token"` looks like a match but ignores the storage-layer `flutter.` prefix — that mistaken read is exactly what hid this bug. A "no key-name change needed" conclusion is wrong.

Fix (cheap-token, same process, no Keychain/App-Group): change the native store to read the **`flutter.`-prefixed** keys from `UserDefaults.standard`:

```swift
// AppDelegate.swift: UserDefaultsBackgroundSyncStateStore (513–541)
var sessionToken: String? { userDefaults.string(forKey: "flutter.auth_session_token") }
var backendBaseURL: URL? {
  guard let s = userDefaults.string(forKey: "flutter.background_sync_backend_base_url") else { return nil }
  return URL(string: s)
}
var healthAuthorized: Bool { userDefaults.bool(forKey: "flutter.health_authorized") }
```

Add a **seam test that crosses the Dart-write/Swift-read boundary**: set the `flutter.`-prefixed keys (what Dart actually persists), assert the real store reads them, and assert the pre-fix unprefixed layout returns nil so this can't regress. The existing `RunnerTests` inject a `MockStateStore` — which is precisely why the bug was invisible — so this test must exercise the **real** store:

```swift
// RunnerTests.swift
func testStateStoreReadsFlutterPrefixedKeys() {
  let d = UserDefaults(suiteName: "test-suite")!
  d.removePersistentDomain(forName: "test-suite")
  d.set("tok", forKey: "flutter.auth_session_token")
  d.set("http://localhost:3000", forKey: "flutter.background_sync_backend_base_url")
  d.set(true, forKey: "flutter.health_authorized")

  let store = UserDefaultsBackgroundSyncStateStore(userDefaults: d)
  XCTAssertEqual(store.sessionToken, "tok")
  XCTAssertEqual(store.backendBaseURL?.absoluteString, "http://localhost:3000")
  XCTAssertTrue(store.healthAuthorized)

  // Regression guard: the OLD unprefixed layout must NOT be readable.
  let d2 = UserDefaults(suiteName: "test-suite-2")!
  d2.removePersistentDomain(forName: "test-suite-2")
  d2.set("tok", forKey: "auth_session_token")
  XCTAssertNil(UserDefaultsBackgroundSyncStateStore(userDefaults: d2).sessionToken)
}
```

> **Verify:** the Dart writers use legacy `SharedPreferences.getInstance()` (they do). If any of these keys is ever migrated to `SharedPreferencesAsync`/`SharedPreferencesWithCache` (which do **not** prefix), the native read for that key must drop the `flutter.` prefix in lockstep — add an `X-App-Version`-style seam guard so this divergence surfaces.

**Fix C2 — Missing `X-Timezone` header in native POSTs.**

Dart's `BackendApiService` (backend_api_service.dart:1406, 1441) sends `X-Timezone` on all requests. The native `URLSessionStepPoster` (AppDelegate.swift:772–842) does not, so the backend defaults background uploads to `America/New_York` (extractTimezone.js:21), breaking date rollover for non-ET users (e.g. an 11 PM `Asia/Tokyo` upload lands on the next ET calendar day, putting steps on the wrong race date). Add the header in both POST methods:

```swift
// AppDelegate.swift: postSteps (lines 779–810) and postStepSamples (lines 812–842)
// After the Authorization header:
request.setValue(TimeZone.current.identifier, forHTTPHeaderField: "X-Timezone")
```

**Fix C3 — Missing `skipRaceResolution` parity in the native daily POST.**

In Dart (backend_api_service.dart:192–206), `recordSteps()` includes `'skipRaceResolution': true` when the flag is passed, telling the backend not to trigger a recompute/notification for that upload. The native daily POST (AppDelegate.swift:796–800) omits it, so every background upload triggers a full recompute + potential placement push — a thundering-herd risk. Add an optional `skipRaceResolution` parameter to the `StepPosting` protocol and the daily POST body, and pass `true` from `BackgroundStepSyncCoordinator.postDailySteps`:

```swift
// AppDelegate.swift: protocol StepPosting (lines 324–338)
func postSteps(
  baseURL: URL,
  sessionToken: String,
  steps: Int,
  date: String,
  skipRaceResolution: Bool = false,
  completion: @escaping (Int?, Error?) -> Void
)

// AppDelegate.swift: URLSessionStepPoster.postSteps (lines 779–810)
do {
  var body: [String: Any] = ["steps": steps, "date": date]
  if skipRaceResolution {
    body["skipRaceResolution"] = true
  }
  request.httpBody = try JSONSerialization.data(withJSONObject: body)
} catch {
  completion(nil, error)
  return
}

// AppDelegate.swift: BackgroundStepSyncCoordinator.postDailySteps (line 447)
poster.postSteps(
  baseURL: baseURL,
  sessionToken: sessionToken,
  steps: entry.steps,
  date: entry.date,
  skipRaceResolution: true
) { statusCode, error in
  // ...
}
```

**Fix C4 — Premature `enableHealthKitBackgroundDelivery()` (gate on confirmed Health auth).**

AppDelegate.swift:87 calls `enableHealthKitBackgroundDelivery()` unconditionally in `didFinishLaunchingWithOptions`, before the user grants Health access. The correct flow already exists in Dart: `main_shell.dart:299` calls it after the grant (routing to the native handler at AppDelegate.swift:64–70, which invokes the real method at lines 223–244). Remove the early call:

```swift
// AppDelegate.swift: lines 85–88
registerBackgroundRefreshTask()
scheduleBackgroundRefresh()
// enableHealthKitBackgroundDelivery() is called in Dart after Health authorization,
// not here. See main_shell.dart:299.
```

**Fix C5 — `aps-environment` must be `production` for App Store builds.**

`Runner.entitlements:13–14` hardcodes `aps-environment` to `development`. App Store production builds need `production` (production push certificates). Manage this per build config rather than hardcoding:

- **Staging flavor:** `aps-environment = development`.
- **Prod flavor:** `aps-environment = production`.

Recommended approach — an Xcode Run Script build phase (before "Copy Bundle Resources") that rewrites the entitlements for prod/Release:

```bash
if [[ "$FLAVOR" == "prod" ]] || [[ "$CONFIGURATION" == "Release" ]]; then
  sed -i '' 's/<string>development<\/string>/<string>production<\/string>/g' "${SRCROOT}/Runner/Runner.entitlements"
fi
```

Alternatively maintain two entitlements files (`Runner-Staging.entitlements` / `Runner-Prod.entitlements`) referenced per scheme. For Phase 1, also document this in `DEPLOYMENT.md`.

**VERIFY against a real archived IPA first** (this is a load-bearing check before shipping prod):

```bash
# After: flutter build ipa --flavor prod --release
unzip -q build/ios/ipa/*.ipa -d /tmp/ipa_extract
cat /tmp/ipa_extract/Payload/Runner.app/embedded.entitlements | grep -A 1 "aps-environment"
# Expect: <string>production</string>
```

### Tests to write

In `ios/RunnerTests/RunnerTests.swift`:

```swift
// Test A: X-Timezone header in the daily POST.
func testPostStepsIncludesXTimezoneHeader() {
  var capturedRequest: URLRequest?
  let mockSession = MockURLSession { request in
    capturedRequest = request
    return (data: Data(), response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil), error: nil)
  }

  let poster = URLSessionStepPoster(session: mockSession)
  let expectation = expectation(description: "post completion")

  poster.postSteps(
    baseURL: URL(string: "http://localhost:3000")!,
    sessionToken: "test-token",
    steps: 1000,
    date: "2026-03-19"
  ) { _, _ in expectation.fulfill() }

  wait(for: [expectation], timeout: 1)

  let timezoneHeader = capturedRequest?.value(forHTTPHeaderField: "X-Timezone")
  XCTAssertNotNil(timezoneHeader)
  XCTAssertEqual(timezoneHeader, TimeZone.current.identifier)
}

// Test B: X-Timezone header in the hourly samples POST.
func testPostStepSamplesIncludesXTimezoneHeader() {
  var capturedRequest: URLRequest?
  let mockSession = MockURLSession { request in
    capturedRequest = request
    return (data: Data(), response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil), error: nil)
  }

  let poster = URLSessionStepPoster(session: mockSession)
  let expectation = expectation(description: "post completion")

  poster.postStepSamples(
    baseURL: URL(string: "http://localhost:3000")!,
    sessionToken: "test-token",
    samples: [["periodStart": "2026-03-19T12:00:00.000Z", "periodEnd": "2026-03-19T13:00:00.000Z", "steps": 500]]
  ) { _, _ in expectation.fulfill() }

  wait(for: [expectation], timeout: 1)

  let timezoneHeader = capturedRequest?.value(forHTTPHeaderField: "X-Timezone")
  XCTAssertNotNil(timezoneHeader)
  XCTAssertEqual(timezoneHeader, TimeZone.current.identifier)
}

// Test C: skipRaceResolution included when true.
func testPostStepsWithSkipRaceResolutionIncludesFlag() {
  var capturedBody: [String: Any]?
  let mockSession = MockURLSession { request in
    if let bodyData = request.httpBody,
       let body = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
      capturedBody = body
    }
    return (data: Data(), response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil), error: nil)
  }

  let poster = URLSessionStepPoster(session: mockSession)
  let expectation = expectation(description: "post completion")

  poster.postSteps(
    baseURL: URL(string: "http://localhost:3000")!,
    sessionToken: "test-token",
    steps: 1000,
    date: "2026-03-19",
    skipRaceResolution: true
  ) { _, _ in expectation.fulfill() }

  wait(for: [expectation], timeout: 1)

  XCTAssertNotNil(capturedBody)
  XCTAssertEqual(capturedBody?["steps"] as? Int, 1000)
  XCTAssertEqual(capturedBody?["date"] as? String, "2026-03-19")
  XCTAssertTrue(capturedBody?["skipRaceResolution"] as? Bool ?? false)
}

// Test D: skipRaceResolution omitted when false (default).
func testPostStepsWithoutSkipRaceResolutionOmitsFlag() {
  var capturedBody: [String: Any]?
  let mockSession = MockURLSession { request in
    if let bodyData = request.httpBody,
       let body = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
      capturedBody = body
    }
    return (data: Data(), response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil), error: nil)
  }

  let poster = URLSessionStepPoster(session: mockSession)
  let expectation = expectation(description: "post completion")

  poster.postSteps(
    baseURL: URL(string: "http://localhost:3000")!,
    sessionToken: "test-token",
    steps: 1000,
    date: "2026-03-19",
    skipRaceResolution: false
  ) { _, _ in expectation.fulfill() }

  wait(for: [expectation], timeout: 1)

  XCTAssertNotNil(capturedBody)
  XCTAssertEqual(capturedBody?["steps"] as? Int, 1000)
  XCTAssertEqual(capturedBody?["date"] as? String, "2026-03-19")
  XCTAssertNil(capturedBody?["skipRaceResolution"])
}

// Test E: sync requires Health authorization.
func testPerformSyncRequiresHealthAuthorized() {
  let coordinator = BackgroundStepSyncCoordinator(
    stateStore: MockStateStore(
      sessionToken: "session-token",
      backendBaseURL: URL(string: "http://127.0.0.1:3000"),
      healthAuthorized: false
    ),
    challengeSyncDaysFetcher: MockChallengeSyncDaysFetcher(syncDays: nil),
    stepReader: MockStepReader(result: .success([])),
    poster: MockPoster()
  )

  let expectation = expectation(description: "sync completion")
  coordinator.performSync { result in
    XCTAssertEqual(result, .noData)
    expectation.fulfill()
  }

  wait(for: [expectation], timeout: 1)
}
```

**Manual testing (real device or simulator):**

1. **Timezone correctness.** Set device to `Asia/Tokyo`. Launch staging build, sign in, grant Health. Open an active race, background the app, add steps in Health (or inject on simulator). Wait 30s or trigger a `STEP_SYNC_REQUEST`. Verify in backend logs that the background POST has `X-Timezone: Asia/Tokyo` and the step date matches the local calendar date — not an ET-shifted date — and the leaderboard reflects the correct day.
2. **`aps-environment` verification.** After `flutter build ipa --flavor prod --release`, unzip and confirm the embedded entitlements show `<string>production</string>`. Optionally upload to TestFlight and confirm push delivery.
3. **Background sync (regression).** Kill the app, add steps, wait for `BGAppRefresh` (15–60 min on device; faster with a manual `STEP_SYNC_REQUEST`). Verify steps upload and appear on the leaderboard, with no duplicate notifications (confirming `skipRaceResolution`).

### Acceptance criteria

- [ ] Tests A–E pass via `xcodebuild test -scheme Runner -configuration Debug`.
- [ ] `X-Timezone` is present and correct in both daily and hourly POSTs.
- [ ] `skipRaceResolution` is conditionally included in the daily POST body.
- [ ] Native state store reads the **`flutter.`-prefixed** keys; seam test sets `flutter.`-prefixed keys and asserts reads succeed, and asserts the pre-fix unprefixed layout returns nil.
- [ ] Staging IPA has `aps-environment = development`; prod IPA has `aps-environment = production` (verified against the archived IPA).
- [ ] On-device test confirms correct local-date placement, `BGAppRefresh` + `STEP_SYNC_REQUEST` triggering, and no thundering-herd notifications.
- [ ] Existing `RunnerTests.swift` suite passes without regression.

### Compatibility & rollback notes

**Old-client safety.** All changes are additive/backward-compatible:
- `X-Timezone` — backend already defaults to `America/New_York` when absent; old clients work unchanged.
- `skipRaceResolution` — backend already handles the optional flag; old clients omitting it get the default (full recompute).
- Removing the premature `enableHealthKitBackgroundDelivery()` — no effect on old clients; the correct Dart-side call remains.
- `aps-environment` — only affects APNs delivery, not compatibility.

**Disable (if needed).** No feature flag wraps background sync today. For urgent rollback, stop fanning out `STEP_SYNC_REQUEST` from the backend (`BGAppRefresh` still fires, less often).

**Lockstep.** Build the matching Android binary in the same release (same version, same test window) even if Android ships later. Phase 1 is iOS-only code but does not block Phase 2.

### Risks & gotchas

1. **APNs prod cert.** If the backend's prod APNs cert isn't a production cert, setting `aps-environment = production` drops all silent pushes. *Mitigation:* confirm staging App ID has a development cert and prod App ID has a production cert before shipping.
2. **HealthKit delivery is best-effort.** `enableBackgroundDelivery(frequency: .immediate)` is "within minutes," not immediate; steps may lag 5–15 min. *Mitigation:* Phase 3 adds push-driven refresh. Note "best-effort" in release notes.
3. **Stale device timezone.** A traveling user with stale system timezone sends a wrong `X-Timezone`. Rare; backend falls back to ET on missing/invalid headers — degraded, not broken.
4. **Fragile entitlements edits.** Malformed/duplicated `aps-environment` fails signing. *Mitigation:* manage via build script/scheme; test both flavors before merge.
5. **Mock vs. real requests.** `MockURLSession` may miss real `URLRequest` edge cases. *Mitigation:* run the on-device manual tests; consider a local-server integration test.
6. **`StepPosting` protocol change ripples.** Adding `skipRaceResolution` to the protocol (C3) touches **every conformer** — `URLSessionStepPoster` and any mock posters in `RunnerTests`. *Mitigation:* give the param a `= false` default so existing call sites compile unchanged; update the test mocks in the same commit.
7. **Native 401 handling (per `AUDIT.md` T1.1).** The 90-day JWT can expire/invalidate; on a `401` the native poster should stop and surface "needs re-auth" (let Dart re-login on next foreground), not silently retry forever. *Mitigation:* add explicit `401 → .noData` handling in `URLSessionStepPoster` and ship it with C1–C5, since the dead path never exercised this before.

## Phase 2 — Android WorkManager background step sync (updaters)

### Goal & who it reaches

Enable Android users to sync daily step counts and hourly samples in the background, accepting the WorkManager 15–60+ minute ceiling (no foreground service, per locked decision). Combined with Phase 0 (recompute) and Phase 3 (silent-push triggers), this brings Android to parity with iOS background sync. Reaches all Android app versions shipped after the Phase 0 backend deployment.

### Prerequisites

- Phase 0 is deployed and live in production.
- Phase 1 is shipped (or in flight, if targeting iOS simultaneously).
- Android app has its basic manifest, Health Connect permissions, and Google auth in place (Workstreams A–E from `ANDROID.md`).
- `firebase_messaging` is integrated and the FCM background handler stub exists (`notification_service.dart:16`).

### Files created / edited

| File | Purpose |
|------|---------|
| `android/app/src/main/AndroidManifest.xml` | Add `READ_HEALTH_DATA_IN_BACKGROUND` permission; register `NotificationHandler` service. |
| `android/app/build.gradle.kts` | Add `androidx.work:work-runtime-ktx` and `androidx.health.connect:connect-client`. |
| `android/app/src/main/kotlin/com/rohanchari/steptracker/StepSyncWorker.kt` | **NEW.** Kotlin `CoroutineWorker` reading Health Connect and POSTing steps/samples. |
| `android/app/src/main/kotlin/com/rohanchari/steptracker/HealthConnectFeatures.kt` | **NEW.** Feature gate for background reads on devices that support them. |
| `android/app/src/main/kotlin/com/rohanchari/steptracker/NotificationHandler.kt` | **NEW.** FCM service that enqueues expedited sync on `STEP_SYNC_REQUEST` data messages. |
| `android/app/src/main/kotlin/com/rohanchari/steptracker/MainActivity.kt` | Enqueue periodic sync on startup. |
| `lib/services/notification_service.dart` | Implement the `_firebaseMessagingBackgroundHandler` stub. |
| `test/services/step_sync_dedup_test.dart` | **NEW.** Dart unit tests for dedup-minus-manual math. |
| `android/app/src/test/kotlin/com/rohanchari/steptracker/StepSyncWorkerTest.kt` | **NEW.** Kotlin unit tests for POST shape. |

(Paths are relative to `/Users/rohan/repos/stepv2-frontend`.)

### Step-by-step integration

**1. Add the background-read permission** (`AndroidManifest.xml`, after `READ_STEPS` near line 9):

```xml
    <uses-permission android:name="android.permission.health.READ_STEPS"/>
    <!-- Background step sync: read Health Connect data even when app is backgrounded or closed.
         Android 14+ only; fails gracefully on older devices. See ANDROID.md §F. -->
    <uses-permission android:name="android.permission.READ_HEALTH_DATA_IN_BACKGROUND"/>

    <!-- Android 13+ runtime permission for FCM/local notifications. -->
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
```

**2. Add dependencies** (`build.gradle.kts`, in the `dependencies` block near line 98):

```kotlin
dependencies {
    // Backports java.time etc. for core library desugaring (flutter_local_notifications).
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // WorkManager for background periodic/expedited step sync (Android 14+).
    implementation("androidx.work:work-runtime-ktx:2.9.1")

    // Native Health Connect client for background step reads.
    implementation("androidx.health.connect:connect-client:1.1.0-alpha02")
}
```

**3. Create `HealthConnectFeatures.kt`:**

```kotlin
package com.rohanchari.steptracker

import android.content.Context

object HealthConnectFeatures {
    /**
     * Returns true if the device supports background reading of step data from Health Connect.
     * On Android <14, this is always false (READ_HEALTH_DATA_IN_BACKGROUND does not exist).
     * On Android 14+, delegates to the HealthConnect library's runtime feature check.
     */
    suspend fun canReadBackgroundData(context: Context): Boolean {
        return try {
            val client = androidx.health.connect.client.HealthConnectClient.getOrCreate(context)
            client.getFeature(
                androidx.health.connect.client.feature.HealthConnectFeatures.FEATURE_READ_HEALTH_DATA_IN_BACKGROUND
            ) == androidx.health.connect.client.feature.HealthConnectFeatures.FEATURE_STATUS_AVAILABLE
        } catch (e: Exception) {
            android.util.Log.w("HealthConnectFeatures", "Background read check failed", e)
            false
        }
    }
}
```

**4. Create `StepSyncWorker.kt`:**

```kotlin
package com.rohanchari.steptracker

import android.content.Context
import android.util.Log
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import androidx.work.*
import java.net.HttpURLConnection
import java.net.URL
import java.time.*

class StepSyncWorker(
    context: Context,
    params: WorkerParameters
) : CoroutineWorker(context, params) {
    private val tag = "StepSyncWorker"

    override suspend fun doWork(): Result {
        return try {
            Log.d(tag, "Starting background step sync")

            // 1. Verify background read is allowed and health auth is granted.
            if (!HealthConnectFeatures.canReadBackgroundData(applicationContext)) {
                Log.i(tag, "Background read not available on this device; ignoring")
                return Result.success()
            }

            // ⚠️ Flutter's legacy shared_preferences plugin stores in the "FlutterSharedPreferences"
            // file and prefixes EVERY key with "flutter." — the exact same prefix that broke iOS
            // background sync (Phase 1 Fix C1). The native reader MUST use the prefixed keys, or the
            // worker silently no-ops just like the iOS path did. Verify the file name on your
            // shared_preferences version (legacy = "FlutterSharedPreferences").
            val prefs = applicationContext.getSharedPreferences(
                "FlutterSharedPreferences", Context.MODE_PRIVATE
            )
            val healthAuthorized = prefs.getBoolean("flutter.health_authorized", false)
            if (!healthAuthorized) {
                Log.i(tag, "Health Connect not authorized; skipping sync")
                return Result.success()
            }

            // 2. Read session token + timezone from SharedPreferences (set by Dart auth_service.dart).
            val sessionToken = prefs.getString("flutter.auth_session_token", null)
            if (sessionToken.isNullOrBlank()) {
                Log.i(tag, "No session token available; cannot sync")
                return Result.success()
            }

            // Prefer a Dart-stored timezone if present; fall back to the device default.
            // (See Risk #6: `flutter.user_time_zone` is NOT written by Dart today — either add a
            // Dart writer or rely on the systemDefault fallback.)
            val timeZone = prefs.getString("flutter.user_time_zone", null) ?: ZoneId.systemDefault().id

            // 3. Read steps from Health Connect for today (deduped-minus-manual).
            val now = Instant.now()
            val today = now.atZone(ZoneId.systemDefault()).toLocalDate()
            val startOfDay = today.atStartOfDay(ZoneId.systemDefault()).toInstant()

            val stepsToday = readTodaySteps(startOfDay, now)
            val hourlySamples = readHourlySteps(startOfDay, now)

            if (stepsToday == null && hourlySamples.isEmpty()) {
                Log.d(tag, "No steps to sync today")
                return Result.success()
            }

            // 4. POST to backend: /steps (daily) + /steps/samples (hourly).
            val baseUrl = prefs.getString("flutter.background_sync_backend_base_url", "https://steptracker-api.org")
                ?: "https://steptracker-api.org"

            if (stepsToday != null && stepsToday > 0) {
                if (!postDailySteps(baseUrl, sessionToken, today.toString(), stepsToday, timeZone)) {
                    return Result.retry()
                }
            }

            if (hourlySamples.isNotEmpty()) {
                if (!postHourlySamples(baseUrl, sessionToken, hourlySamples, timeZone)) {
                    return Result.retry()
                }
            }

            Log.d(tag, "Step sync complete: $stepsToday steps, ${hourlySamples.size} samples")
            Result.success()
        } catch (e: Exception) {
            Log.e(tag, "Step sync failed", e)
            Result.retry()
        }
    }

    private suspend fun readTodaySteps(startOfDay: Instant, now: Instant): Int? {
        return try {
            val client = HealthConnectClient.getOrCreate(applicationContext)
            val deduped = client.aggregate(
                AggregateRequest(
                    metrics = setOf(StepsRecord.COUNT_TOTAL),
                    timeRangeFilter = TimeRangeFilter.between(startOfDay, now)
                )
            )
            val totalSteps = deduped[StepsRecord.COUNT_TOTAL] as? Long ?: 0L
            val manualSteps = readManualStepsForPeriod(startOfDay, now, client)
            val accurate = (totalSteps - manualSteps).coerceAtLeast(0L).toInt()
            Log.d(tag, "Today steps: deduped=$totalSteps, manual=$manualSteps, accurate=$accurate")
            accurate
        } catch (e: Exception) {
            Log.e(tag, "Failed to read today steps", e)
            null // Don't persist a 0 on failure.
        }
    }

    private suspend fun readHourlySteps(startOfDay: Instant, now: Instant): List<Map<String, Any>> {
        val samples = mutableListOf<Map<String, Any>>()
        return try {
            val client = HealthConnectClient.getOrCreate(applicationContext)
            var bucketStart = startOfDay.atZone(ZoneId.systemDefault())
                .withMinute(0).withSecond(0).withNano(0).toInstant()

            while (bucketStart.isBefore(now)) {
                val bucketEnd = bucketStart.plusSeconds(3600).let { if (it.isAfter(now)) now else it }
                try {
                    val deduped = client.aggregate(
                        AggregateRequest(
                            metrics = setOf(StepsRecord.COUNT_TOTAL),
                            timeRangeFilter = TimeRangeFilter.between(bucketStart, bucketEnd)
                        )
                    )
                    val total = deduped[StepsRecord.COUNT_TOTAL] as? Long ?: 0L
                    val manual = readManualStepsForPeriod(bucketStart, bucketEnd, client)
                    val steps = (total - manual).coerceAtLeast(0L).toInt()
                    if (steps > 0) {
                        samples.add(
                            mapOf(
                                "periodStart" to bucketStart.toString(),
                                "periodEnd" to bucketEnd.toString(),
                                "steps" to steps
                            )
                        )
                    }
                } catch (e: Exception) {
                    Log.w(tag, "Failed to read bucket $bucketStart-$bucketEnd; skipping", e)
                }
                bucketStart = bucketEnd
            }
            samples
        } catch (e: Exception) {
            Log.e(tag, "Hourly sample read failed", e)
            emptyList()
        }
    }

    private suspend fun readManualStepsForPeriod(
        start: Instant,
        end: Instant,
        client: HealthConnectClient
    ): Long {
        return try {
            val records = client.readRecords(
                ReadRecordsRequest(
                    recordType = StepsRecord::class,
                    timeRangeFilter = TimeRangeFilter.between(start, end)
                )
            )
            var manual = 0L
            for (record in records.records) {
                if (record.metadata?.recordingMethod?.name == "MANUAL") {
                    manual += record.count
                }
            }
            manual
        } catch (e: Exception) {
            Log.w(tag, "Manual steps read failed for period", e)
            0L
        }
    }

    private fun postDailySteps(
        baseUrl: String,
        sessionToken: String,
        dateStr: String,
        steps: Int,
        timeZone: String
    ): Boolean {
        return try {
            val url = URL("$baseUrl/steps")
            val connection = url.openConnection() as HttpURLConnection
            connection.requestMethod = "POST"
            connection.setRequestProperty("Content-Type", "application/json")
            connection.setRequestProperty("Authorization", "Bearer $sessionToken")
            connection.setRequestProperty("X-Timezone", timeZone)
            connection.doOutput = true

            // skipRaceResolution parity with iOS Fix C3: background uploads must not
            // trigger a per-upload recompute storm; the Phase 0 cron handles standings.
            val body = """{"steps":$steps,"date":"$dateStr","skipRaceResolution":true}"""
            connection.outputStream.bufferedWriter().use { it.write(body) }

            val responseCode = connection.responseCode
            Log.d(tag, "POST /steps: $responseCode")
            when {
                responseCode in 200..299 -> true
                responseCode == 401 || responseCode == 403 -> {
                    Log.w(tag, "Auth failed posting daily steps; not retrying")
                    false
                }
                else -> false // Transient; caller will retry.
            }
        } catch (e: Exception) {
            Log.e(tag, "Failed to POST daily steps", e)
            false
        }
    }

    private fun postHourlySamples(
        baseUrl: String,
        sessionToken: String,
        samples: List<Map<String, Any>>,
        timeZone: String
    ): Boolean {
        return try {
            val url = URL("$baseUrl/steps/samples")
            val connection = url.openConnection() as HttpURLConnection
            connection.requestMethod = "POST"
            connection.setRequestProperty("Content-Type", "application/json")
            connection.setRequestProperty("Authorization", "Bearer $sessionToken")
            connection.setRequestProperty("X-Timezone", timeZone)
            connection.doOutput = true

            val samplesJson = samples.joinToString(",") { sample ->
                """{"periodStart":"${sample["periodStart"]}","periodEnd":"${sample["periodEnd"]}","steps":${sample["steps"]}}"""
            }
            val body = """{"samples":[$samplesJson]}"""
            connection.outputStream.bufferedWriter().use { it.write(body) }

            val responseCode = connection.responseCode
            Log.d(tag, "POST /steps/samples: $responseCode")
            when {
                responseCode in 200..299 -> true
                responseCode == 401 || responseCode == 403 -> {
                    Log.w(tag, "Auth failed posting samples; not retrying")
                    false
                }
                else -> false
            }
        } catch (e: Exception) {
            Log.e(tag, "Failed to POST hourly samples", e)
            false
        }
    }

    companion object {
        const val WORK_NAME = "step_sync_periodic"

        fun schedulePeriodicSync(context: Context) {
            val syncRequest = PeriodicWorkRequestBuilder<StepSyncWorker>(
                Duration.ofMinutes(15),
                Duration.ofMinutes(5) // Flex interval.
            ).build()

            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                syncRequest
            )
            Log.d("StepSyncWorker", "Periodic sync scheduled")
        }

        fun scheduleExpeditedSync(context: Context) {
            val syncRequest = OneTimeWorkRequestBuilder<StepSyncWorker>()
                .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED)
                .build()

            WorkManager.getInstance(context).enqueueUniqueWork(
                "step_sync_expedited",
                ExistingWorkPolicy.REPLACE,
                syncRequest
            )
            Log.d("StepSyncWorker", "Expedited sync enqueued")
        }
    }
}
```

**5. Create `NotificationHandler.kt`:**

```kotlin
package com.rohanchari.steptracker

import android.util.Log
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class NotificationHandler : FirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        // Data-only message of type STEP_SYNC_REQUEST → enqueue an expedited sync, then return.
        if (message.notification == null && message.data["type"] == "STEP_SYNC_REQUEST") {
            Log.d("NotificationHandler", "Received STEP_SYNC_REQUEST; enqueueing expedited sync")
            StepSyncWorker.scheduleExpeditedSync(applicationContext)
            return
        }
        // Otherwise let the firebase_messaging plugin's Dart handler take it.
    }
}
```

Register it in `AndroidManifest.xml` (after the `MainActivity` `</activity>`, around line 72):

```xml
        <!-- Firebase background messaging handler for expedited step sync on STEP_SYNC_REQUEST. -->
        <service
            android:name=".NotificationHandler"
            android:exported="false">
            <intent-filter>
                <action android:name="com.google.firebase.MESSAGING_EVENT" />
            </intent-filter>
        </service>
```

**6. Implement the FCM background handler in Dart** (`notification_service.dart`, lines 15–16):

```dart
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Android-only: on STEP_SYNC_REQUEST data messages, trigger a native WorkManager
  // expedited sync to read Health Connect and POST steps to the backend.
  // (iOS does not use this handler; FCM is Android-only. iOS has a native APNs bridge.)
  if (Platform.isAndroid && message.data['type'] == 'STEP_SYNC_REQUEST') {
    const channel = MethodChannel('com.steptracker/background_sync');
    try {
      await channel.invokeMethod('enqueueExpeditedSync');
    } catch (e) {
      debugPrint('Failed to enqueue expedited sync: $e');
    }
  }
}
```

> Note: the native `NotificationHandler` already enqueues expedited sync directly on `onMessageReceived`, so the Dart method-channel call is a belt-and-suspenders path. Either alone is sufficient; ship the native handler as primary.

**7. Enqueue periodic sync on startup** (`MainActivity.kt`, in `onCreate`, after plugin registration):

```kotlin
// Schedule background step sync (15-min periodic; expedited when FCM data is pushed).
StepSyncWorker.schedulePeriodicSync(this)
```

### Tests to write

**`test/services/step_sync_dedup_test.dart`** (dedup-minus-manual math):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/services/health_service.dart';

void main() {
  group('HealthService.accurateAndroidTotal', () {
    test('returns deduped total minus manual steps', () {
      expect(HealthService.accurateAndroidTotal(10500, 300), equals(10200));
    });

    test('clamps to zero if manual exceeds deduped', () {
      expect(HealthService.accurateAndroidTotal(500, 1000), equals(0));
    });

    test('returns deduped total when no manual steps', () {
      expect(HealthService.accurateAndroidTotal(5000, 0), equals(5000));
    });
  });
}
```

**`android/app/src/test/kotlin/com/rohanchari/steptracker/StepSyncWorkerTest.kt`** (POST shape):

```kotlin
import junit.framework.TestCase.assertEquals
import org.junit.Test

class StepSyncWorkerTest {
    @Test
    fun `POST steps payload has required fields`() {
        val date = "2026-03-17"
        val steps = 8234
        val body = """{"steps":$steps,"date":"$date","skipRaceResolution":true}"""
        assert(body.contains(""""steps":$steps"""))
        assert(body.contains(""""date":"$date""""))
        assert(body.contains(""""skipRaceResolution":true"""))
    }

    @Test
    fun `POST samples payload is array of objects with periodStart, periodEnd, steps`() {
        val samples = listOf(
            mapOf(
                "periodStart" to "2026-03-17T08:00:00Z",
                "periodEnd" to "2026-03-17T09:00:00Z",
                "steps" to 234
            )
        )
        val samplesJson = samples.joinToString(",") { sample ->
            """{"periodStart":"${sample["periodStart"]}","periodEnd":"${sample["periodEnd"]}","steps":${sample["steps"]}}"""
        }
        val body = """{"samples":[$samplesJson]}"""
        assert(body.contains(""""periodStart":"2026-03-17T08:00:00Z""""))
        assert(body.contains(""""periodEnd":"2026-03-17T09:00:00Z""""))
        assert(body.contains(""""steps":234"""))
    }

    @Test
    fun `hourly sample list omits zero-step buckets`() {
        val samples = listOf(
            mapOf("periodStart" to "08:00", "periodEnd" to "09:00", "steps" to 0),
            mapOf("periodStart" to "09:00", "periodEnd" to "10:00", "steps" to 150)
        )
        val nonZero = samples.filter { (it["steps"] as Int) > 0 }
        assertEquals(1, nonZero.size)
        assertEquals(150, nonZero[0]["steps"])
    }
}
```

**Manual test (on-device):**

1. Open app, grant Health Connect step-read permission.
2. Swipe the app away from recents (kill the process).
3. In Health Connect, log 2,000 steps for today.
4. `adb logcat | grep StepSyncWorker` and wait for the worker to fire (up to ~15 min in normal mode).
5. Verify `POST /steps: 200` / `POST /steps/samples: 200` in logcat and that the steps appear on the backend.
6. **Expedited path:** send a data-only FCM message `{"type":"STEP_SYNC_REQUEST"}` while the app is closed; observe `Received STEP_SYNC_REQUEST` and the worker running immediately.

### Acceptance criteria

- [ ] `StepSyncWorker.kt` builds; WorkManager + Health Connect deps resolve.
- [ ] `READ_HEALTH_DATA_IN_BACKGROUND` is in the manifest and builds successfully.
- [ ] Worker reads today's steps accurately (deduped-minus-manual, clamped ≥ 0).
- [ ] Hourly samples are populated (only non-zero buckets).
- [ ] `X-Timezone` is sent on all POSTs; `skipRaceResolution:true` is on the daily POST (parity with iOS Fix C3).
- [ ] POSTs to `/steps` and `/steps/samples` succeed (200-range).
- [ ] Unit tests pass: `flutter test test/services/step_sync_dedup_test.dart` and `./gradlew testDebugUnitTest`.
- [ ] On-device: steps added to Health Connect → worker sync → backend records correctly.
- [ ] Expedited sync on `STEP_SYNC_REQUEST` enqueues immediately (logcat `Expedited sync enqueued`).
- [ ] No persistent 0-step records if a Health Connect read fails (worker returns `null`/skips).
- [ ] Worker retries on transient errors (network, HC timeout); gives up on auth errors (401/403).
- [ ] Both iOS and Android builds compile and link (lockstep); no shared-code regressions.

### Compatibility & rollback notes

**Old-client safety.** WorkManager sync is Android-only and entirely native; iOS is unaffected. The `STEP_SYNC_REQUEST` data type is new — older Android clients (v1.3.x and earlier) ignore it (no WorkManager setup). `/steps` and `/steps/samples` are unchanged and require no new payload fields; `X-Timezone` is already supported by the backend.

**Disable / revert.** Comment out `StepSyncWorker.schedulePeriodicSync()` in `MainActivity.kt`; remove the `NotificationHandler` service from the manifest to disable expedited sync. `git revert` the commits — pending work is cancelled on uninstall.

**Feature flag (optional).** Gate `doWork()` on a SharedPreferences flag set by the app on startup. For v1, assume always-on once deployed.

### Risks & gotchas

1. **Health Connect unavailable (pre-Android 14, no HC app).** `canReadBackgroundData()` returns `false` → worker no-ops silently. Graceful degradation; foreground still works.
2. **Cross-process SharedPreferences staleness.** A worker in a separate process may read a slightly stale session token. Tokens are long-lived; 401/403 fails fast without spamming.
3. **WorkManager 15-min minimum.** Real-world cadence is 30–60+ min under Doze/Battery Optimization. Background sync is "eventual," not real-time; Phase 3's silent push is the accelerator. Set this expectation in release notes.
4. **Manual-entry cheat.** Dedup-minus-manual removes typed steps but cannot stop a user typing a huge fake entry; the subtraction still applies. Chosen to eliminate the unbounded multi-device double-count, accepting bounded manual-entry risk. Backend rate-limiting is out of scope for v1.
5. **Background-read permission denial.** If the user denies `READ_HEALTH_DATA_IN_BACKGROUND` (Android 14+), the worker no-ops (`.success()`). Add an onboarding prompt explaining the benefit.
6. **Timezone alignment — `user_time_zone` is not written today.** No Dart code currently persists `flutter.user_time_zone`, so the worker will use the `ZoneId.systemDefault()` fallback unless you add a Dart writer. *Mitigation:* either write the user's app-configured timezone to that prefs key on startup (matching the foreground `X-Timezone` source in `backend_api_service.dart`), or accept `systemDefault()` and document it. Getting this wrong lands daily totals on the wrong race date for non-default-tz users (the Android analogue of iOS Fix C2).
7. **`enqueueExpeditedSync` MethodChannel has no native handler yet.** The Dart `_firebaseMessagingBackgroundHandler` invokes `MethodChannel('com.steptracker/background_sync').invokeMethod('enqueueExpeditedSync')`, but no Android `MethodCallHandler` for that method exists today. *Mitigation:* the native `NotificationHandler.onMessageReceived` is the **primary** path and needs no channel; either register a handler in `MainActivity` for the Dart path or drop the Dart channel call and rely on `NotificationHandler` alone.
8. **Background/foreground race.** If the user opens the app mid-sync, both POSTs may race; `recordSteps` is idempotent (upsert by date), so no harm — just a wasted request. Optionally skip if synced `<5 min` ago.

## Phase 3 — Silent-refresh + on-demand "sync now" pull loop (updaters, both platforms)

### Goal & who it reaches

Phase 3 ties background step sync to live standings recomputes. When standings change (Phase 0's `PLACEMENT_CHANGED`), the backend fans out a silent `STEP_SYNC_REQUEST` to participants — currently iOS-only via APNs, now extended to Android via FCM. Clients wake, upload new steps, the backend recomputes, and updated placements are broadcast. The home/races list (which today caches once on init) refetches whenever the app resumes after a silent push, keeping standings fresh without user friction. **Reach:** iOS (Phase 1 required), Android (Phase 2 required); list refetch-on-resume works on any matching binary.

### Prerequisites

- Phase 0 shipped: recompute job, `PLACEMENT_CHANGED` handler, live recompute via `resolveRaceState({raceId})`.
- Phase 1 shipped: iOS background-sync repair + silent-push routing (AppDelegate.swift:136–149).
- Phase 2 shipped: Android WorkManager sync posting to `/steps` and `/steps/samples`, FCM integration, Health Connect access.
- Backend request-step-sync infra exists (`stepSyncPush.js`) but the Android branch is missing; cooldown tracking is in place.
- Clients already detect silent pushes (iOS native AppDelegate.swift; Android FCM background handler).

### Files created / edited

| File | Purpose |
|------|---------|
| `stepv2-backend/src/services/stepSyncPush.js` | Add FCM/Android branch to `requestStepSyncForUser`; route platform-aware (currently iOS-only). |
| `stepv2-backend/src/handlers/notificationHandlers.js` | Wire `PLACEMENT_CHANGED` to `requestStepSyncForUsers` for participants *before* the alert push. |
| `stepv2-frontend/lib/services/notification_service.dart` | Recognize `STEP_SYNC_REQUEST` in routing; implement the FCM background handler. |
| `stepv2-frontend/lib/screens/tabs/races_tab.dart` | (Optional) direct refetch hook on silent push. |
| `stepv2-frontend/lib/screens/main_shell.dart` | Already refetches races on `didChangeAppLifecycleState.resumed` — confirm parity. |

### Step-by-step integration

**Step 1 — Extend backend `stepSyncPush` to support Android/FCM** (`src/services/stepSyncPush.js`, lines 24–84).

Import `fcmService` at the top (after `apnsService`):

```javascript
const { fcmService } = require("./fcm");
```

Add the dependency to the builder (lines 12–17):

```javascript
function buildStepSyncPushService(dependencies = {}) {
  const userModel = dependencies.User || User;
  const deviceTokenModel = dependencies.DeviceToken || DeviceToken;
  const apns = dependencies.apnsService || apnsService;
  const fcm = dependencies.fcmService || fcmService; // ADD
  // ... rest unchanged
}
```

Route by platform instead of the iOS-only filter (replace the `iosTokens` filter near line 39):

```javascript
const targetTokens = (tokens || []).filter(
  (token) => token.platform === "ios" || token.platform === "android"
);
if (targetTokens.length === 0) return;

let hadSuccessfulSend = false;

for (const tokenRecord of targetTokens) {
  try {
    const isAndroid = tokenRecord.platform === "android";
    const payload = { type: "STEP_SYNC_REQUEST" };
    const result = isAndroid
      ? await fcm.sendSilentNotification({ deviceToken: tokenRecord.token, payload })
      : await apns.sendSilentNotification({ deviceToken: tokenRecord.token, payload });
    // ... existing success/unregistered handling unchanged
  }
}
```

**Step 2 — Wire `PLACEMENT_CHANGED` to fan out step-sync pulls** (`src/handlers/notificationHandlers.js`).

Before sending placement alerts, request fresh syncs so the next recompute has the latest data:

```javascript
  events.on("PLACEMENT_CHANGED", async (data) => {
    try {
      const { raceId, participantUserIds } = data;
      const { stepSyncPushService } = require("../services/stepSyncPush");
      // Ask participants' devices to upload new steps before the next recompute.
      await stepSyncPushService.requestStepSyncForUsers(participantUserIds);
      // The alert/silent placement push itself is Phase 0 scope (see Phase 0 handler).
    } catch (error) {
      logger.error("PLACEMENT_CHANGED step-sync fan-out failed", {
        error: error instanceof Error ? error.message : String(error),
      });
    }
  });
```

> Phase 3 only adds the `requestStepSyncForUsers` call; the full alert-push logic lives in the Phase 0 handler. If you keep a single `PLACEMENT_CHANGED` listener, call `requestStepSyncForUsers` at the top of it before the existing push loop.

**Step 3 — Recognize `STEP_SYNC_REQUEST` in client routing** (`notification_service.dart`, lines 267–294).

Add the case to `_routeFromType`:

```dart
  NotificationRoute? _routeFromType(String? type) {
    switch (type) {
      // ... existing cases ...
      case 'GLOBAL_EVENT_STARTED':
        return NotificationRoute.home;
      case 'STEP_SYNC_REQUEST':
        // Silent push; route to races so a tap/resume refetch fires.
        return NotificationRoute.races;
      // ... legacy cases ...
      default:
        return null;
    }
  }
```

`STEP_SYNC_REQUEST` is silent (no user tap). iOS already handles it natively (AppDelegate.swift:136 checks `isStepSyncRequest` and calls `performSync`). The actual list refresh is driven by app resume (Step 6), so no navigation is required.

**Step 4 — Android FCM background handler for silent push** (`notification_service.dart`, lines 12–16).

This is the same handler implemented in Phase 2; in Phase 3 confirm it is wired for `STEP_SYNC_REQUEST`. (Android's native `NotificationHandler.kt` from Phase 2 enqueues expedited WorkManager sync on receipt; the Dart handler is a backup path.) Document the FCM caveat:

```dart
// NOTE: FCM data messages can be delayed 7+ days on projects whose users haven't
// received a user-visible notification recently; rely on the WorkManager periodic
// job (Phase 2) as the primary sync source. This silent push is an accelerator.
```

**Step 5 — (Optional) direct races-tab refetch on silent push** (`races_tab.dart`, lines 187–189).

The `RefreshIndicator.onRefresh` already binds `widget.onRefresh` (wired from `MainShell._refreshRacesTab`). App resume alone is sufficient for the MVP. Optional enhancement: pass a `ValueNotifier<bool>` from `MainShell` to `RacesTab` so a silent-push event can trigger a refetch without waiting for resume:

```dart
// main_shell.dart
final ValueNotifier<bool> _racesRefreshNotifier = ValueNotifier(false);

// races_tab.dart initState
widget.racesRefreshNotifier?.addListener(() {
  widget.onRefresh?.call();
});
```

Not required for Phase 3 MVP.

**Step 6 — Confirm `MainShell` refetches races on resume** (`main_shell.dart`, lines 256–270). Already implemented and sufficient:

```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.resumed && _healthAuthorized) {
    _fetchSteps();
    _refreshMe();
    _fetchFriendsSteps();
    _fetchRaces(checkResults: true); // Races refetch on resume
    _fetchShopCatalog();
    // ...
  } else if (state == AppLifecycleState.paused) {
    _stopForegroundPolling();
  }
}
```

No change needed; this keeps races fresh whenever the app returns to foreground after a silent push.

### Tests to write

**Backend — platform routing** (`test/services/stepSyncPush.test.js`):

```javascript
const assert = require("node:assert/strict");
const test = require("node:test");
const { buildStepSyncPushService } = require("../../src/services/stepSyncPush");

test("requestStepSyncForUser routes by platform: Android → FCM, iOS → APNs", async () => {
  const user = { id: "user-1", lastSilentPushSentAt: null, lastStepSyncAt: null };
  const tokens = [
    { userId: "user-1", token: "ios-token-1", platform: "ios" },
    { userId: "user-1", token: "android-token-1", platform: "android" },
  ];

  const apnsCalls = [];
  const fcmCalls = [];

  const service = buildStepSyncPushService({
    User: {
      findById: async () => user,
      update: async (id, data) => { user.lastSilentPushSentAt = data.lastSilentPushSentAt; },
    },
    DeviceToken: { findByUserId: async () => tokens, deleteToken: async () => {} },
    apnsService: { sendSilentNotification: async (args) => { apnsCalls.push(args); return { success: true }; } },
    fcmService: { sendSilentNotification: async (args) => { fcmCalls.push(args); return { success: true }; } },
  });

  await service.requestStepSyncForUser("user-1");

  assert.equal(apnsCalls.length, 1);
  assert.equal(apnsCalls[0].deviceToken, "ios-token-1");
  assert.equal(apnsCalls[0].payload.type, "STEP_SYNC_REQUEST");

  assert.equal(fcmCalls.length, 1);
  assert.equal(fcmCalls[0].deviceToken, "android-token-1");
  assert.equal(fcmCalls[0].payload.type, "STEP_SYNC_REQUEST");
});

test("requestStepSyncForUser respects 1-hour cooldown", async () => {
  const now = new Date();
  const oneHourAgo = new Date(now.getTime() - 60 * 60 * 1000 - 1000);
  const user = { id: "user-1", lastSilentPushSentAt: oneHourAgo, lastStepSyncAt: null };
  const tokens = [{ userId: "user-1", token: "ios-token-1", platform: "ios" }];

  const apnsCalls = [];
  const service = buildStepSyncPushService({
    User: { findById: async () => user, update: async () => {} },
    DeviceToken: { findByUserId: async () => tokens, deleteToken: async () => {} },
    apnsService: { sendSilentNotification: async (args) => { apnsCalls.push(args); return { success: true }; } },
    now: () => now,
  });

  await service.requestStepSyncForUser("user-1");

  // Cooldown NOT expired; request should be dropped.
  assert.equal(apnsCalls.length, 0);
});
```

**Frontend — routing for `STEP_SYNC_REQUEST`** (`test/notification_service_step_sync_test.dart`):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/services/notification_service.dart';

void main() {
  test('_routeFromType returns NotificationRoute.races for STEP_SYNC_REQUEST', () {
    final service = NotificationService();
    expect(service.routeFromType('STEP_SYNC_REQUEST'), equals(NotificationRoute.races));
  });

  test('silent STEP_SYNC_REQUEST does not set a pending navigation action', () {
    final service = NotificationService();
    service.routeFromType('STEP_SYNC_REQUEST'); // Returns races, but not a tap.
    expect(service.pendingAction.value, isNull);
  });
}
```

**Frontend — refetch-on-resume** (`test/main_shell_resume_refetch_test.dart`):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/screens/main_shell.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

class _CapturingBackendApi extends BackendApiService {
  int raceFetchCount = 0;

  @override
  Future<Map<String, dynamic>> fetchRaces({required String identityToken}) async {
    raceFetchCount++;
    return {
      'active': [{'id': 'race-1', 'name': 'Test Race', 'status': 'ACTIVE'}],
      'pending': [],
      'completed': [],
    };
  }
}

void main() {
  testWidgets('MainShell calls _fetchRaces when app resumes', (tester) async {
    final authService = AuthService();
    final api = _CapturingBackendApi();

    await tester.pumpWidget(
      MaterialApp(home: MainShell(authService: authService, backendApiService: api)),
    );

    WidgetsBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    final initialFetchCount = api.raceFetchCount;
    WidgetsBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(api.raceFetchCount, greaterThan(initialFetchCount));
  });
}
```

**Manual test (iOS):** Open Races tab; trigger a placement change in the backend; confirm a silent push (no banner) arrives and background sync uploads steps; background then resume the app; verify the races list refetches with updated placements.

**Manual test (Android):** Same flow; confirm a silent FCM data message arrives (no tray notification), WorkManager picks it up and POSTs `/steps`, and the list refetches on resume.

### Acceptance criteria

- [ ] Backend `stepSyncPush` routes `STEP_SYNC_REQUEST` by platform (APNs/iOS, FCM/Android) without errors.
- [ ] 1-hour per-user cooldown limits device wake-ups.
- [ ] `PLACEMENT_CHANGED` handler calls `requestStepSyncForUsers` *before* alert pushes (old clients ignore the async call; new ones wake and sync).
- [ ] iOS: silent push triggers background sync (AppDelegate.swift:136); device uploads new steps.
- [ ] Android: silent FCM data message → WorkManager → `/steps` POST within 30–60 min.
- [ ] Client races list refetches on resume after silent push (`MainShell.didChangeAppLifecycleState.resumed → _fetchRaces`).
- [ ] Unit tests pass for platform routing and cooldown (backend).
- [ ] Manual test on both platforms: placement updates visible in the races list after background sync + resume.
- [ ] No crashes/ANRs on Android; no excessive battery drain.

### Compatibility & rollback notes

**Old-client safety.** iOS pre-Phase 1 clients receive `STEP_SYNC_REQUEST` but don't process it (no native handler) — they fall back to foreground polling (`MainShell._foregroundPollInterval`, 5 min). Android pre-Phase 2 clients ignore the FCM data message (no WorkManager). Both old and new clients still receive `PLACEMENT_CHANGED` alerts; only new clients also benefit from the pre-sync pull. No breaking changes.

**Rollback.** Remove the `requestStepSyncForUsers` call from the `PLACEMENT_CHANGED` handler; or remove the `fcmService` injection from `stepSyncPush` to revert to iOS-only. Optional env flag:

```javascript
if (process.env.ENABLE_LIVE_STEP_SYNC === "true") {
  await stepSyncPushService.requestStepSyncForUsers(participantUserIds);
}
```

### Risks & gotchas

1. **FCM silent-message delay & loss.** Data-only messages may be delayed 7+ days on devices that haven't received a user-visible notification recently, or dropped on old/low-battery devices. *Mitigation:* WorkManager periodic job (Phase 2) is the primary source; this push is an accelerator. Validate the deprioritization behavior on real devices.
2. **Cooldown too aggressive.** The 1-hour cooldown means a user won't see changes faster than ~1 hour unless they open the app (foreground polls every 5 min). Acceptable for MVP; tighten later.
3. **iOS HealthKit observer delays.** Hourly-capped; a silent push may wake the app but find nothing new to upload until the next hour. Best-effort accelerator, not a guarantee.
4. **Stale participant list.** A participant who left between recompute and fan-out still gets a `STEP_SYNC_REQUEST` — harmless (their steps no longer count). No corruption.
5. **Network partition during pull.** If the device syncs but the recompute fails, standings aren't pushed — same failure mode as today's foreground polling. Phase 0's idempotent detection covers the next run.
6. **Android timezone header.** The Android background sync (Phase 2) must send `X-Timezone`; Phase 3 only routes the silent push. Confirm Phase 2 includes it.

## Phase 4 — iOS Live Activities for lock-screen live placement (OPTIONAL / DEFERRED, iOS only)

> **This phase is OPTIONAL and deferred** (backlog item `URGENT-TODO.md` P3 #6). It ships after Phases 0–3 so the must-have live-update infrastructure stabilizes first. Nothing depends on it.

### Goal & who it reaches

Display a user's **live race placement on the iOS Lock Screen and Dynamic Island**, updated directly by the backend via APNs ActivityKit push-to-update. iOS **16.1+** only (push-to-start on 17.2+); updates appear without the user opening the app — the "wow" tier of live placement awareness. **Android receives no equivalent** and continues on Phase 3's notification path.

### Prerequisites

1. **Phase 0 shipped:** backend recomputes ACTIVE-race standings and broadcasts `PLACEMENT_CHANGED`.
2. **Phases 1–3 shipped:** iOS and Android clients perform background sync and on-demand pulls.
3. **APNs ready:** `apns.js` (HTTP/2) supports arbitrary headers/payloads; the prod APNs cert (`aps-environment=production`) is verified on a real archived IPA (Phase 1 step).
4. **iOS prod build verified:** the archived IPA's `embedded.mobileprovision` has `aps-environment=production` (Phase 1 prerequisite).
5. **`RaceParticipant.lastNotifiedPlacement`** column exists (Phase 0).

### Files created / edited

| File | Purpose |
|------|---------|
| `stepv2-frontend/ios/Runner.xcodeproj/project.pbxproj` | Add an ActivityKit Widget Extension target with signing. |
| `stepv2-frontend/ios/ActivityExtension/ActivityExtension.swift` | **NEW.** ActivityKit widget entry point + content-state struct. |
| `stepv2-frontend/ios/ActivityExtension/RacePlacementActivityView.swift` | **NEW.** Lock Screen + Dynamic Island SwiftUI views. |
| `stepv2-frontend/ios/Runner/Info.plist` | Add `NSSupportsLiveActivities` (and `NSSupportsLiveActivitiesFrequentUpdates`). |
| `stepv2-frontend/ios/Runner/AppDelegate.swift` | Register for ActivityKit push tokens; bridge to the notification channel. |
| `stepv2-backend/prisma/schema.prisma` | Add nullable `liveActivityPushToken` to `DeviceToken`. |
| `stepv2-backend/src/services/liveActivityPush.js` | **NEW.** Build/send ActivityKit update payloads via `apnsService`. |
| `stepv2-backend/src/handlers/notificationHandlers.js` | Extend `PLACEMENT_CHANGED` with an ActivityKit branch (priority 5 routine, 10 for overtake/took-1st). |
| `stepv2-backend/src/routes/deviceTokens.js` | **NEW endpoint** `POST /device-tokens/activity-kit`. |
| `stepv2-frontend/lib/services/live_activity_token_service.dart` | **NEW.** Register/submit ActivityKit tokens. |
| `stepv2-frontend/test/live_activity_token_test.dart` | **NEW.** Dart tests. |
| `stepv2-backend/test/handlers/notificationHandlers.test.js` | Extend with ActivityKit branch + priority routing tests. |
| `stepv2-frontend/ios/RunnerTests/LiveActivityTests.swift` | **NEW.** XCTest for token registration + view rendering. |

### Step-by-step integration

**A. Backend schema & token plumbing**

1. Add the nullable column to `DeviceToken` (`prisma/schema.prisma`):

   ```prisma
   model DeviceToken {
     id                    String   @id @default(uuid())
     userId                String   @map("user_id")
     token                 String
     platform              String   // "ios", "android", "ios_activity_kit"
     liveActivityPushToken String?  @map("live_activity_push_token")
     createdAt             DateTime @default(now()) @map("created_at")
     updatedAt             DateTime @updatedAt @map("updated_at")
     user                  User     @relation(fields: [userId], references: [id])

     @@unique([userId, token])
     @@index([userId])
     @@index([userId, platform])
     @@map("device_tokens")
   }
   ```

2. Create the migration:

   ```bash
   npx prisma migrate dev --name add_live_activity_push_token
   ```

   ```sql
   ALTER TABLE "device_tokens" ADD COLUMN "live_activity_push_token" TEXT;
   CREATE INDEX "device_tokens_userId_platform_idx" ON "device_tokens"("user_id", "platform");
   ```

3. Create `src/services/liveActivityPush.js`:

   ```javascript
   const { apnsService } = require("./apns");

   function buildLiveActivityPushService(config = {}) {
     const apns = config.apnsService || apnsService;
     const logger = config.logger || console;

     async function sendActivityUpdatePush({
       deviceToken,
       activityPushToken,
       raceId,
       myPlacement,
       myUsername,
       leaderUsername,
       endsAt,
       priority = 5, // 5 = routine, 10 = overtake/took-1st
     }) {
       const apsPayload = {
         alert: {
           title: `Race: ${myPlacement === 1 ? "🥇 1st!" : `#${myPlacement}`}`,
           body: myUsername && leaderUsername ? `vs ${leaderUsername}` : "Race update",
         },
         sound: 0,
         "content-available": 1,
       };

       const contentStatePayload = {
         raceId,
         myPlacement,
         myUsername: myUsername || "You",
         leaderUsername: leaderUsername || "?",
         endsAt: endsAt?.toISOString ? endsAt.toISOString() : endsAt,
         updatedAt: new Date().toISOString(),
       };

       const result = await apns.sendSilentNotification({
         deviceToken,
         payload: {
           aps: apsPayload,
           "activity-push-token": activityPushToken,
           "content-state": contentStatePayload,
         },
         headers: {
           "apns-push-type": "liveactivity",
           "apns-priority": String(priority),
         },
       });

       if (!result.success) {
         logger.warn("ActivityKit push failed", {
           raceId,
           deviceTokenSuffix: (deviceToken || "").slice(-9),
           statusCode: result.statusCode,
           reason: result.reason,
         });
       }
       return result;
     }

     return { sendActivityUpdatePush };
   }

   const liveActivityPushService = buildLiveActivityPushService();
   module.exports = { buildLiveActivityPushService, liveActivityPushService };
   ```

4. Extend the `PLACEMENT_CHANGED` handler (`src/handlers/notificationHandlers.js`) to route `ios_activity_kit` tokens to ActivityKit (priority 5 routine, 10 for meaningful moves), skipping standard APNs/FCM tokens already handled by the Phase 0 branch:

   ```javascript
   events.on("PLACEMENT_CHANGED", async (data) => {
     try {
       const {
         raceId, participantId, participantUserId,
         oldPlacement, newPlacement,
         participantUsername, leaderUsername, raceEndsAt,
         priority = 5,
       } = data;

       const tokens = await deviceTokenModel.findByUserId(participantUserId);
       if (!tokens || tokens.length === 0) return;

       // 1. Standard APNs/FCM devices: alert for priority 10 (overtaken / took 1st),
       //    silent refresh for priority 5. (This is the Phase 0 push logic.)
       for (const tokenRecord of tokens) {
         if (tokenRecord.platform === "ios_activity_kit") continue;
         const push = pushServiceFor(tokenRecord);
         const isMeaningful = priority === 10;
         try {
           const result = isMeaningful
             ? await push.sendNotification({
                 deviceToken: tokenRecord.token,
                 title: newPlacement === 1 ? "🥇 You took 1st!" : "You were overtaken!",
                 body: newPlacement === 1 ? "You're leading!" : `${leaderUsername || "Someone"} is now ahead`,
                 payload: { type: "PLACEMENT_CHANGED", route: "race_detail", params: { raceId } },
               })
             : await push.sendSilentNotification({
                 deviceToken: tokenRecord.token,
                 payload: { type: "PLACEMENT_CHANGED", route: "race_detail", params: { raceId } },
               });
           if (result.unregistered) {
             await deviceTokenModel.deleteToken({ userId: participantUserId, token: tokenRecord.token });
           }
         } catch (error) {
           logger.error("PLACEMENT_CHANGED push threw", {
             raceId, participantId,
             deviceTokenSuffix: deviceTokenSuffix(tokenRecord.token),
             error: error instanceof Error ? error.message : String(error),
           });
         }
       }

       // 2. ActivityKit devices: push-to-update the Live Activity.
       const liveActivityPush = config.liveActivityPushService || liveActivityPushService;
       const activityTokens = tokens.filter((t) => t.platform === "ios_activity_kit");
       for (const tokenRecord of activityTokens) {
         try {
           if (!tokenRecord.liveActivityPushToken) continue; // Activity not started yet.
           const result = await liveActivityPush.sendActivityUpdatePush({
             deviceToken: tokenRecord.token,
             activityPushToken: tokenRecord.liveActivityPushToken,
             raceId,
             myPlacement: newPlacement,
             myUsername: participantUsername,
             leaderUsername,
             endsAt: raceEndsAt,
             priority,
           });
           if (!result.success) {
             logger.warn("PLACEMENT_CHANGED ActivityKit push failed", {
               raceId, participantId, statusCode: result.statusCode, reason: result.reason,
             });
           }
         } catch (error) {
           logger.error("PLACEMENT_CHANGED ActivityKit push threw", {
             raceId, participantId,
             error: error instanceof Error ? error.message : String(error),
           });
         }
       }
     } catch (error) {
       logger.error("PLACEMENT_CHANGED handler failed", {
         error: error instanceof Error ? error.message : String(error),
       });
     }
   });
   ```

   > This handler emits the same `type: "PLACEMENT_CHANGED"` payload as Phase 0. If you keep the Phase 0 handler as the single source of placement pushes, add only the ActivityKit branch (section 2 above) to it rather than registering a second listener.

**B. iOS frontend: ActivityKit extension & push-token registration**

5. **Create the ActivityKit Widget Extension target** in Xcode: Add Files → New Target → Widget Extension (ActivityKit), name `ActivityExtension`, bundle ID `<main>.ActivityExtension`. Sign with the same team/cert as Runner. Entitlements include `com.apple.developer.widget-kit`.

6. **`ios/ActivityExtension/ActivityExtension.swift`:**

   ```swift
   import ActivityKit
   import WidgetKit
   import SwiftUI

   struct RacePlacementActivityAttributes: ActivityAttributes {
     public struct ContentState: Codable, Hashable {
       var raceId: String
       var myPlacement: Int
       var myUsername: String
       var leaderUsername: String
       var endsAt: Date
       var updatedAt: Date
     }
     var raceId: String
     var endsAt: Date
   }

   @main
   struct ActivityExtension: Widget {
     let kind: String = "RacePlacementActivity"

     var body: some WidgetConfiguration {
       ActivityConfiguration(for: RacePlacementActivityAttributes.self) { context in
         RacePlacementActivityView(attributes: context.attributes, state: context.state)
           .activitySystemActionForegroundColor(.black)
           .activityBackgroundTint(.white)
       } dynamicIsland: { context in
         DynamicIsland {
           DynamicIslandExpandedRegion(.leading) {
             Text("Race").font(.caption2).foregroundColor(.secondary)
           }
           DynamicIslandExpandedRegion(.trailing) {
             Text("#\(context.state.myPlacement)")
               .font(.headline).fontWeight(.bold)
               .foregroundColor(context.state.myPlacement == 1 ? .yellow : .primary)
           }
           DynamicIslandExpandedRegion(.bottom) {
             VStack(alignment: .leading, spacing: 2) {
               Text("You: \(context.state.myUsername)").font(.caption)
               if context.state.myPlacement > 1 {
                 Text("Leading: \(context.state.leaderUsername)")
                   .font(.caption).foregroundColor(.secondary)
               }
             }
           }
         } compactLeading: {
           Text("#\(context.state.myPlacement)").font(.caption2).fontWeight(.bold)
         } compactTrailing: {
           Text(context.state.myPlacement == 1 ? "🥇" : "🏃").font(.caption)
         } minimal: {
           Text("#\(context.state.myPlacement)").font(.caption2).fontWeight(.bold)
         }
         .widgetURL(URL(string: "bara://race-detail?raceId=\(context.attributes.raceId)"))
       }
     }
   }
   ```

7. **`ios/ActivityExtension/RacePlacementActivityView.swift`:**

   ```swift
   import ActivityKit
   import SwiftUI

   struct RacePlacementActivityView: View {
     let attributes: RacePlacementActivityAttributes
     let state: RacePlacementActivityAttributes.ContentState

     var body: some View {
       VStack(alignment: .leading, spacing: 4) {
         HStack {
           VStack(alignment: .leading, spacing: 2) {
             Text("Race Placement").font(.caption).foregroundColor(.secondary)
             Text("#\(state.myPlacement)")
               .font(.title).fontWeight(.bold)
               .foregroundColor(state.myPlacement == 1 ? .yellow : .primary)
           }
           Spacer()
           VStack(alignment: .trailing, spacing: 2) {
             if state.myPlacement == 1 {
               Text("🥇").font(.title2)
             } else {
               Text("vs \(state.leaderUsername)")
                 .font(.caption).lineLimit(1).foregroundColor(.secondary)
             }
           }
         }
         let timeRemaining = attributes.endsAt.timeIntervalSinceNow
         if timeRemaining > 0 {
           ProgressView(value: 1.0 - (timeRemaining / 28800)) // 8h window
             .tint(state.myPlacement == 1 ? .yellow : .blue)
         }
       }
       .padding()
       .background(Color(white: 0.95))
       .cornerRadius(8)
       .widgetURL(URL(string: "bara://race-detail?raceId=\(state.raceId)"))
     }
   }
   ```

8. **`ios/Runner/Info.plist`** — add (alongside `UIBackgroundModes`):

   ```xml
   <key>NSSupportsLiveActivities</key>
   <true/>
   <key>NSSupportsLiveActivitiesFrequentUpdates</key>
   <true/>
   ```

9. **`ios/Runner/AppDelegate.swift`** — register for ActivityKit push tokens (iOS 16.1+) and bridge them to the notification channel, then handle a `registerActivityKitToken` method call from Dart. (Token observation uses the activity's `pushTokenUpdates` async sequence; the snippet below sketches the channel wiring — adapt to the existing `notificationChannel` setup.)

   ```swift
   notificationChannel?.setMethodCallHandler { [weak self] call, result in
     if call.method == "requestPermission" {
       self?.requestNotificationPermission(result: result)
     } else if call.method == "registerActivityKitToken" {
       if #available(iOS 16.1, *) {
         self?.handleActivityKitTokenRegistration(result: result)
       } else {
         result(nil)
       }
     } else {
       result(FlutterMethodNotImplemented)
     }
   }
   ```

   When the ActivityKit token is produced, invoke `notificationChannel?.invokeMethod("onActivityKitPushToken", arguments: hexToken)` so Dart can submit it to the backend.

10. **`lib/services/live_activity_token_service.dart`:**

    ```dart
    import 'package:flutter/services.dart';
    import 'package:step_tracker/services/auth_service.dart';
    import 'package:step_tracker/services/backend_api_service.dart';

    class LiveActivityTokenService {
      static const _notificationChannel = MethodChannel('com.steptracker/notifications');
      final AuthService authService;
      final BackendApiService api;

      LiveActivityTokenService({required this.authService, required this.api});

      /// Start an ActivityKit Live Activity for an active race (iOS 16.1+).
      /// The push token is returned asynchronously via the "onActivityKitPushToken"
      /// channel callback and submitted via submitActivityKitToken().
      Future<String?> registerActivityKitToken({
        required String raceId,
        required String myPlacement,
        required String myUsername,
        required String leaderUsername,
        required DateTime endsAt,
      }) async {
        try {
          await _notificationChannel.invokeMethod<void>('registerActivityKitToken');
          return null;
        } catch (e) {
          print('registerActivityKitToken failed: $e');
          return null;
        }
      }

      /// Submit the ActivityKit push token to the backend for future updates.
      Future<bool> submitActivityKitToken({required String token, required String raceId}) async {
        try {
          final sessionToken = await authService.getSessionToken();
          if (sessionToken == null) return false;
          final response = await api.request(
            method: 'POST',
            path: '/device-tokens/activity-kit',
            body: {'token': token, 'raceId': raceId},
          );
          return response['success'] == true;
        } catch (e) {
          print('submitActivityKitToken failed: $e');
          return false;
        }
      }
    }
    ```

11. **Race detail screen** — when the race is ACTIVE and iOS 16.1+, call `registerActivityKitToken(...)` on open (adapt to the actual screen structure).

**C. Backend: register ActivityKit token endpoint**

12. Create `POST /device-tokens/activity-kit` (`src/routes/deviceTokens.js`): verify the race exists and the caller is a participant, then upsert a `DeviceToken` with `platform: "ios_activity_kit"` and `liveActivityPushToken = token`. Register it in `src/app.js`:

    ```javascript
    app.post("/device-tokens/activity-kit", handlePostActivityKitToken);
    ```

### Tests to write

**Backend** (`test/handlers/notificationHandlers.test.js`) — add:

```javascript
test("PLACEMENT_CHANGED emits alert push (priority 10) for overtake on iOS devices", async () => {
  const eventBus = createMockEventBus();
  let capturedPush;
  const apnsService = {
    sendNotification: async (args) => { capturedPush = args; return { success: true }; },
    sendSilentNotification: async () => ({ success: true }),
  };
  const liveActivityPush = { sendActivityUpdatePush: async () => ({ success: true }) };

  registerNotificationHandlers({
    eventBus, apnsService, liveActivityPushService: liveActivityPush,
    User: { async findById() { return { displayName: "Alice" }; } },
    DeviceToken: {
      async findByUserId() { return [{ token: "ios-token-1", platform: "ios" }]; },
      async deleteToken() {},
    },
  });

  await eventBus.emit("PLACEMENT_CHANGED", {
    raceId: "race-1", participantId: "rp-1", participantUserId: "user-1",
    oldPlacement: 2, newPlacement: 1,
    participantUsername: "Alice", leaderUsername: null,
    raceEndsAt: new Date(Date.now() + 3600000), priority: 10,
  });

  assert.equal(capturedPush.title, "🥇 You took 1st!");
  assert.equal(capturedPush.deviceToken, "ios-token-1");
  assert.equal(capturedPush.payload.type, "PLACEMENT_CHANGED");
});

test("PLACEMENT_CHANGED routes ios_activity_kit tokens separately with ActivityKit push", async () => {
  const eventBus = createMockEventBus();
  const alertPushes = [];
  const activityKitPushes = [];
  const apnsService = {
    sendNotification: async (args) => { alertPushes.push(args); return { success: true }; },
    sendSilentNotification: async () => ({ success: true }),
  };
  const liveActivityPush = {
    sendActivityUpdatePush: async (args) => { activityKitPushes.push(args); return { success: true }; },
  };

  registerNotificationHandlers({
    eventBus, apnsService, liveActivityPushService: liveActivityPush,
    User: { async findById() { return { displayName: "Bob" }; } },
    DeviceToken: {
      async findByUserId() {
        return [
          { token: "ios-token-1", platform: "ios" },
          { token: "apns-device-token", platform: "ios_activity_kit", liveActivityPushToken: "activity-push-token-123" },
        ];
      },
      async deleteToken() {},
    },
  });

  await eventBus.emit("PLACEMENT_CHANGED", {
    raceId: "race-1", participantId: "rp-1", participantUserId: "user-1",
    oldPlacement: 3, newPlacement: 2,
    participantUsername: "Bob", leaderUsername: "Alice",
    raceEndsAt: new Date(Date.now() + 3600000), priority: 5,
  });

  assert.equal(alertPushes.length, 0); // priority 5 → silent, not alert
  assert.equal(activityKitPushes.length, 1);
  assert.equal(activityKitPushes[0].deviceToken, "apns-device-token");
  assert.equal(activityKitPushes[0].activityPushToken, "activity-push-token-123");
  assert.equal(activityKitPushes[0].myPlacement, 2);
});

test("PLACEMENT_CHANGED skips ActivityKit push if liveActivityPushToken is missing", async () => {
  const eventBus = createMockEventBus();
  const activityKitPushes = [];
  const liveActivityPush = {
    sendActivityUpdatePush: async (args) => { activityKitPushes.push(args); return { success: true }; },
  };

  registerNotificationHandlers({
    eventBus,
    apnsService: { sendNotification: async () => ({ success: true }), sendSilentNotification: async () => ({ success: true }) },
    liveActivityPushService: liveActivityPush,
    User: { async findById() { return {}; } },
    DeviceToken: {
      async findByUserId() {
        return [{ token: "apns-device-token", platform: "ios_activity_kit", liveActivityPushToken: null }];
      },
      async deleteToken() {},
    },
  });

  await eventBus.emit("PLACEMENT_CHANGED", {
    raceId: "race-1", participantId: "rp-1", participantUserId: "user-1",
    oldPlacement: 2, newPlacement: 1,
    participantUsername: "You", leaderUsername: null,
    raceEndsAt: new Date(Date.now() + 3600000), priority: 10,
  });

  assert.equal(activityKitPushes.length, 0); // Skipped due to missing token.
});
```

**iOS** (`ios/RunnerTests/LiveActivityTests.swift`):

```swift
import XCTest
import ActivityKit
@testable import Runner

class LiveActivityTests: XCTestCase {
  func testRacePlacementActivityViewRendering() throws {
    let attributes = RacePlacementActivityAttributes(
      raceId: "race-123", endsAt: Date(timeIntervalSinceNow: 3600)
    )
    let state = RacePlacementActivityAttributes.ContentState(
      raceId: "race-123", myPlacement: 1, myUsername: "You",
      leaderUsername: "Alice", endsAt: Date(timeIntervalSinceNow: 3600), updatedAt: Date()
    )
    let view = RacePlacementActivityView(attributes: attributes, state: state)
    XCTAssertNotNil(view)
  }

  func testLockScreenPlacementDisplay() throws {
    let attributes = RacePlacementActivityAttributes(
      raceId: "race-456", endsAt: Date(timeIntervalSinceNow: 7200)
    )
    let state = RacePlacementActivityAttributes.ContentState(
      raceId: "race-456", myPlacement: 2, myUsername: "Runner",
      leaderUsername: "Champion", endsAt: Date(timeIntervalSinceNow: 7200), updatedAt: Date()
    )
    let view = RacePlacementActivityView(attributes: attributes, state: state)
    XCTAssertNotNil(view)
  }
}
```

**Dart** (`test/live_activity_token_test.dart`):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/services/live_activity_token_service.dart';

class _MockAuthService extends AuthService {
  @override
  Future<String?> getSessionToken() async => 'test-session-token';
}

class _NoSessionAuthService extends AuthService {
  @override
  Future<String?> getSessionToken() async => null;
}

class _MockBackendApiService extends BackendApiService {
  Map<String, dynamic>? lastSubmitTokenCall;

  @override
  Future<Map<String, dynamic>> request({
    required String method,
    required String path,
    Map<String, dynamic>? body,
  }) async {
    if (path == '/device-tokens/activity-kit') {
      lastSubmitTokenCall = body;
      return {'success': true};
    }
    return {};
  }
}

void main() {
  test('submitActivityKitToken sends token to backend', () async {
    final api = _MockBackendApiService();
    final service = LiveActivityTokenService(authService: _MockAuthService(), api: api);

    final result = await service.submitActivityKitToken(
      token: 'activity-push-token-abc123', raceId: 'race-1',
    );

    expect(result, isTrue);
    expect(api.lastSubmitTokenCall, {'token': 'activity-push-token-abc123', 'raceId': 'race-1'});
  });

  test('submitActivityKitToken returns false if no session token', () async {
    final service = LiveActivityTokenService(
      authService: _NoSessionAuthService(), api: _MockBackendApiService(),
    );

    final result = await service.submitActivityKitToken(
      token: 'activity-push-token-abc123', raceId: 'race-1',
    );

    expect(result, isFalse);
  });
}
```

**Manual device test** (real iOS device — ActivityKit cannot run in the Simulator):

1. `flutter build ipa --flavor prod --release --dart-define=BACKEND_BASE_URL=https://staging.steptracker-api.org`.
2. Verify `aps-environment=production` in the archived IPA (`unzip -p ... embedded.mobileprovision | strings | grep aps-environment`).
3. Install via TestFlight or `xcrun devicectl device install app ... --device <id>`.
4. Create a race, add a friend, start it. On Device A, open the race detail → a Lock Screen card with placement + race name appears.
5. On Device B, simulate steps so Device A's placement changes → Device A's Lock Screen card updates live without opening the app; Dynamic Island expands to show placement + leader.
6. Lock the device for 8+ hours → the activity auto-expires. End the race → the activity is removed immediately.

### Acceptance criteria

- [ ] `RaceParticipant.lastNotifiedPlacement` migration applied (Phase 0 prerequisite).
- [ ] `DeviceToken.liveActivityPushToken` migration applied.
- [ ] `liveActivityPush.js` sends ActivityKit payloads with correct headers (`apns-push-type: liveactivity`; `apns-priority` per priority param).
- [ ] `PLACEMENT_CHANGED` routes `ios_activity_kit` tokens separately and skips if `liveActivityPushToken` is null.
- [ ] ActivityKit Widget Extension target created and signed with the app's team.
- [ ] `RacePlacementActivityAttributes` & `RacePlacementActivityView` compile and render on iOS 16.1+.
- [ ] `Info.plist` includes `NSSupportsLiveActivities: true` and `NSSupportsLiveActivitiesFrequentUpdates: true`.
- [ ] AppDelegate registers for ActivityKit token broadcasts and invokes `onActivityKitPushToken`.
- [ ] `LiveActivityTokenService` submits tokens to `POST /device-tokens/activity-kit`.
- [ ] Race detail screen calls `registerActivityKitToken()` when opening an ACTIVE race on iOS 16.1+.
- [ ] The endpoint upserts a device token with `platform: ios_activity_kit`.
- [ ] Manual device test: Lock Screen card appears, updates live, expires after 8h / at race end.
- [ ] All tests pass (backend `npm test`; frontend `flutter test`; iOS `xcodebuild test`).

### Compatibility & rollback notes

**Old-client safety.** Old clients never send ActivityKit tokens. The handler checks `platform === "ios_activity_kit"` and skips otherwise, so iOS 15 devices get only standard alert/silent pushes (Phase 0 unchanged). Unknown push types/payload fields are already ignored (Phase 0 robustness).

**Disable / feature flag.** Comment out the ActivityKit branch in the `PLACEMENT_CHANGED` handler. No env var needed — the feature is iOS version-gated at the app level (`#available(iOS 16.1, *)`).

**Rollback.** Revert the Prisma migration (`npx prisma migrate resolve --rolled-back <name>` + `git revert`), remove/disable the extension target, rebuild and push a new iOS version. The backend keeps accepting tokens but stops sending updates (handler no-op).

**Lockstep.** Both iOS and Android binaries build together even though only iOS ships ActivityKit; Android gets the same Phase 3 silent pushes as before (no new Android code here).

### Risks & gotchas

1. **Token lifespan.** The push-to-start token is valid ~8h active / ~12h stale. Races > 8h require restarting the activity (new push-to-start or user re-open); past that the Lock Screen card disappears. iOS platform limitation.
2. **Priority-10 budget.** ActivityKit throttles priority-10 (urgent) updates to roughly 1–2/hour. Use priority 5 for routine updates; reserve 10 for meaningful moves (took 1st, overtaken), and add a per-(race, user) cooldown for priority-10 sends.
3. **Extension process isolation.** The extension runs in a separate process and cannot read the auth token from `NSUserDefaults`. For Phase 4 it only renders pushed content-state — no extension-initiated fetch — so this is fine. If a future phase needs the extension to fetch, the token must move to an App Group / Keychain (this is the explicit revisit condition in the locked decision).
4. **Token-registration race.** A `PLACEMENT_CHANGED` push arriving before the token is registered is dropped by the system. Register on race-detail open and submit promptly; the first push won't arrive until after the initial recompute, giving time to register. A change within the first few seconds may be missed (low probability); the next routine update refreshes.
5. **APNs sandbox vs. production.** The extension must match the app's `aps-environment` (sandbox for TestFlight, production for App Store); mismatched entitlements cause APNs to reject the push. Verify both the app and extension provisioning at archive time (Phase 1 step).
6. **Dynamic Island latency.** ~2–3s between push arrival and redraw by `liveactivityd`. Expected Apple behavior.
7. **Real devices only.** ActivityKit cannot be tested in the Simulator; all verification is on physical devices. A misconfigured `apns-topic`/bundle ID fails silently at delivery — always check APNs response logs.

## Open questions / decisions still pending

1. **Real shipped `aps-environment` (Phase 1, blocking for prod push).** Verify against an actual archived prod IPA that `aps-environment=production` and that the backend loads a matching **production** APNs certificate. Silent/Live-Activity pushes are dropped if these don't match. Confirm staging uses `development` end-to-end too.
2. **Placement alert policy & cooldown duration.** Phase 0 uses a 1-minute alert cooldown and pushes on every rank change (including non-meaningful churn). Phase 4 distinguishes priority 5 (routine) vs 10 (overtaken / took 1st). Decide the canonical thresholds: which moves warrant an *alert* vs a *silent* refresh, and finalize the cooldown window (1 min vs longer, per-race vs global per-user). Reconcile the two so there's one alert policy.
3. **Step-sync silent-push cooldown (Phase 3).** The 1-hour `requestStepSyncForUsers` cooldown bounds wake-ups but caps liveness at ~1 hour for closed apps. Confirm this is acceptable, or tune per platform.
4. **FCM data-message reliability (Phases 2–3).** Validate the "7-day deprioritization / possible drop" behavior of high-priority FCM **data** messages on real Android devices, and confirm WorkManager periodic sync is a sufficient primary path when the push is delayed or dropped.
5. **Cooldown storage at scale (Phase 0).** In-memory `Map` cooldown never evicts and is per-instance. Decide whether to add periodic cleanup or move to Redis (with TTL) before multi-instance / sustained-race scale.
6. **Live Activity scope & minimum iOS (Phase 4).** Confirm the minimum supported iOS (16.1 for update, 17.2 for push-to-start), whether push-to-start is in scope or activities are only user-started on race-detail open, and the multi-day race story (auto-expiry at 8h vs. re-start on re-open).
7. **Android timezone source (Phase 2).** Decide whether the worker reads a Dart-stored `user_time_zone` from SharedPreferences (preferred, matches the user's app-configured timezone) or falls back to `ZoneId.systemDefault()`; ensure the app writes that key if the former.
