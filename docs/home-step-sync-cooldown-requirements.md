# Home step-sync cooldown requirements

## Summary and user story

When a runner pulls to refresh Home repeatedly, the app currently reads Health
and calls `POST /steps/sync-v2` every time. Each accepted upload marks every
active race the runner belongs to dirty. The race-keyed worker coalesces those
marks, but the uploads, database work, and worker pressure are still needless
when the runner's data has not materially changed.

Add a 30-second cooldown for user-initiated Home pulls. A runner who pulls too
soon sees the friendly toast `You just synced — try again in 18 seconds.` The
pull ends immediately without new network work; the Home screen remains usable
and background refreshes continue normally.

## Scope

- Gate only the user-initiated pull-to-refresh path on the Home tab.
- Server remains authoritative: a new opt-in cooldown response protects against
  rapid pulls from multiple devices or a future client regression.
- Return an existing-safe response shape that tells the client how long remains.
- Preserve the existing race-keyed queue: one row per race, with repeated
  enqueues merged into its generation and triggering-user set.

## Non-goals

- Do not throttle cold start, foreground/resume sync, Health authorization,
  manual legacy `/steps` fallback, or background job polling.
- Do not stop `GET /home/race-card`, suggestions, friends, or profile refreshes.
- Do not rely exclusively on device clock or local state for enforcement.
- Do not change race scoring, queue correctness, or settlement concurrency.

## Current behavior

1. Home pull calls `_persistSteps()` in `lib/screens/main_shell.dart`.
2. The app reads today's steps and samples, then posts `/steps/sync-v2`.
3. The backend persists the upload and calls `enqueueMany` for the runner's
   active race IDs. This is race-keyed, not one job per refresh: each race has
   one queue row and a new upload increments its generation.
4. The worker processes the queue and writes the authoritative race state.

## API contract

### `POST /steps/sync-v2` (additive opt-in request header)

New clients send `X-Step-Sync-Intent: home-pull` only for a Home pull. All
existing callers omit it and retain today's behavior.

When an eligible `home-pull` arrives less than 30 seconds after a prior
accepted eligible `home-pull` for the same user, the backend returns:

```json
{
  "error": "Step sync is cooling down",
  "code": "STEP_SYNC_COOLDOWN",
  "retryAfterSeconds": 18
}
```

with HTTP 429. It performs no step/sample write, reservation write, cache
invalidation, event emission, or queue enqueue.

The cooldown is recorded in the normal Transaction A step/sample write. A
validation/auth failure or rolled-back transaction does not consume it. A
lost response after commit does consume it, but the client retry uses the same
idempotency key and receives the stored successful result before cooldown
admission is considered.

Older clients omit the header, so the backend never applies this new rejection
to them. New clients talking to an older backend never receive the code and
continue normally.

### Cooldown storage and atomicity

Add nullable `User.lastHomePullStepSyncAt` with no backfill. Postgres is the
authoritative record: Redis is not suitable because it is disposable cached
data and a flush/eviction would silently bypass the cross-device rule.

After validation and existing same-key idempotency replay/recovery handling,
Transaction A conditionally stamps the column using database time only when it
is null or at least 30 seconds old. Exactly one concurrent device wins. A
loser reads the authoritative timestamp and returns the remaining time rounded
up to 1..30 seconds, with `Retry-After` and `Cache-Control: no-store` headers.
No timer polls any server; the client uses this one response only for copy.

## Frontend plan

1. Add `homePull` intent to `BackendApiService.recordStepSyncV2`; it sends the
   header only for the Home pull caller.
2. Parse 429 `STEP_SYNC_COOLDOWN` into a distinct non-error outcome with a
   defensive nullable `retryAfterSeconds`.
3. In `_refreshHomeTabInner`, on cooldown:
   - retain current step/race cards;
   - show the toast `You just synced. Try again in 18 seconds.`, with the
     rounded-up remaining seconds;
   - do not start job polling;
   - end the RefreshIndicator promptly;
   - do not issue legacy writes.
4. Keep the in-flight coalescer. It prevents overlapping gestures before any
   request starts; the server window handles restart/multi-device cases.
5. iOS and Android share this Dart behavior. Missing/malformed cooldown JSON
   degrades to the existing error-safe sync outcome rather than crashing.

## Backward compatibility and rollout

1. Deploy the additive backend migration and handler first.
2. Verify old app calls without the header still receive today's 202 response.
3. Ship iOS and Android app builds together. No server flag is needed because
   enforcement is opt-in by header.
4. Rollback is safe: remove the header from a new app build or disable the
   server's header branch; old clients are unaffected throughout.

## Test plan (tests first)

Backend integration tests against test Postgres:

- first opted-in pull succeeds and stamps the Postgres cooldown timestamp;
- second opted-in pull inside 30 seconds receives 429, remaining seconds, and
  makes no additional queue generation/write;
- pull after the window succeeds;
- header-omitting old client remains unrestricted;
- concurrent eligible requests from the same user permit exactly one;
- same-key ambiguous-response retry/recovery returns its stored result rather
  than a cooldown rejection; invalid/rolled-back requests do not stamp;
- only exact `X-Step-Sync-Intent: home-pull` is opted in; headerless/other
  values retain existing behavior.

Frontend widget/API tests:

- header is sent only for a Home pull;
- 429 cooldown parses defensively and causes no legacy fallback;
- pull shows the countdown toast, retains visible Home data, and makes no
  network request;
- malformed/missing retry delay cannot crash;
- Home pull after a successful wait follows normal sync behavior.

## Acceptance criteria

- A rapid Home pull cannot create additional step-sync queue generations for
  a capable client within 30 seconds.
- The user gets an immediate, clear countdown instead of a long spinner.
- Older binaries, legacy fallback, cold start, resume, and both mobile
  platforms behave exactly as before.
- Tests pass, Flutter analysis is clean aside from documented unrelated
  workspace failures, and manual placement checks are completed.

## Manual UI-placement test plan

1. On iOS and Android, pull Home once then pull again within 30 seconds.
   Verify the cooldown toast appears in the top app overlay, below the
   status-bar safe area and above Home content—not inside a card, the scroll
   view, or the tab bar.
2. With visible Home cards, repeat the rapid second pull. Verify cards stay in
   their existing positions behind the toast; no empty state or duplicate UI
   appears.
3. Verify the tutorial Home preview, tutorial spotlights, demo race tutorial,
   and all non-Home tabs are unchanged. The tutorial uses a no-op Home refresh
   callback and must never display this toast.

## Revision log

- Draft: distinguished the race-keyed, coalescing queue from request fan-out;
  scoped cooldown to deliberate Home pulls so correctness/background sync is
  not delayed.
- Gap pass 1: moved enforcement to the server and made it opt-in to preserve
  frozen-client compatibility; required no-work 429 semantics.
- Gap pass 2: added server-time/multi-device race handling, failed-request
  behavior, and explicit no-legacy-fallback UI behavior.
- Architect revision: use an additive Postgres timestamp rather than Redis,
  because Redis is disposable derived data and cannot authoritatively enforce
  a cross-device admission rule. Added idempotency-first ordering and the
  established 429 error shape/headers.
- Product decision: during the cooldown, a Home pull makes no network request
  and shows `You just synced — try again in X seconds.`
