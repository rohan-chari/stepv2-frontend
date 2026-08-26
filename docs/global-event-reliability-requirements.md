# Daily global-event activation and notification reliability

**Status:** Product- and architect-approved for implementation on 2026-08-26
with a ten-active-installation ceiling. This document authorizes tests and
implementation only—not
deployment, staging start, production migration, token quarantine, or any
production write.

## 1. Summary and user story

The local daily 2x event has three related reliability defects:

1. a large same-time timezone cohort is activated serially behind a 100-row,
   five-second budget that runs only once per minute;
2. its start notification is created only after activation and then traverses a
   second serial expansion/projection burst; and
3. push registrations represent raw tokens rather than app installations, so
   one account accumulated 125 iOS tokens and provider acceptance still could
   not identify whether the user's current device displayed the notification.

Fix the complete path while preserving yesterday's important isolation rule:
gameplay and event visibility must never depend on notification tables, Redis,
APNs, or FCM. Pre-create a durable notification schedule downstream from each
future entitlement, activate due entitlements in set-based micro-batches with
isolated fallback, continuously drain due work, account for every eligible user
and active installation, and make token ownership bounded and self-healing.

User story: when my daily event starts, scoring and the in-app banner become
active promptly and independently; if I am eligible and have an active push
installation, the backend submits the existing start push immediately and can
explain its terminal outcome without stale registrations delaying the cohort.

“Delivered” in this spec means accepted by APNs/FCM, not guaranteed device
display. Apple and Google can accept, store, throttle, or discard a request, and
the OS/user may suppress presentation. The product guarantee is complete,
durable targeting and provider-attempt accounting for every eligible active
installation—not an impossible guarantee that every OS shows an alert.

## 2. Scope and non-goals

### 2.1 In scope

- Local-event start-boundary throughput and continuous backlog drain.
- Independent, advance materialization of one notification schedule per future
  entitlement, including timezone relocation updates.
- Exact-boundary notification release, eligibility gating, deterministic
  deduplication, catch-up while the event is still active, and reconciliation.
- Existing Inbox/outbox/APNs/FCM delivery with bounded concurrency, retry,
  expiry, and provider message-ID capture.
- Installation-aware iOS and Android registration, global token ownership,
  bounded active registrations, reversible stale-token quarantine, and safe
  provider-error cleanup.
- Request-time timezone reconciliation from the prior draft, retaining its
  once-before-worldwide-envelope abuse protections.
- Integration-first performance, crash, rolling-version, and completeness
  tests; operations metrics and alert thresholds.

### 2.2 Non-goals

- No event multiplier, duration, frequency, scoring, race-eligibility, copy,
  notification preference, or visible UI change.
- No guarantee of APNs/FCM or operating-system display.
- No GPS/IP proof of timezone and no post-disclosure event relocation.
- No replacement of the general notification-domain isolation architecture for
  unrelated notification types.
- No external message broker, Redis durability, topic/broadcast push, or direct
  provider calls from event/gameplay code.
- No production capacity change: production remains exactly two PM2 HTTP
  workers and the existing single cron role.
- No release flag, percentage rollout, kill switch, or temporary runtime
  control.

## 3. Incident evidence and root cause

### 3.1 Production incident on 2026-08-26

- 561 Eastern-time entitlements became due at 10:32 ET.
- 498 remained pending around 10:33:45; the backlog did not reach zero until
  approximately 10:45:29.
- The boundary worker ran for about five seconds, then slept until the next
  one-minute tick.
- Rohan's entitlement was activated at 10:43:44.462, 11 minutes 44 seconds late,
  losing roughly 39% of the 30-minute visible opportunity even though timestamped
  scoring could later recover eligible steps.
- Rohan's notification then spent about 12 seconds in event expansion and 78
  seconds in recipient projection. The Inbox alert appeared at 10:45:15 and
  APNs accepted attempts at 10:45:16.
- The cohort's domain-event-to-notification-intent latency was about 5.9 seconds
  at p50, 86.5 seconds at p95, and 93.1 seconds maximum.
- Rohan had 125 stored iOS tokens. APNs returned success for every request,
  including the most recently updated token, but the user reported no displayed
  notification. The adapter discarded APNs response IDs, so exact request
  diagnosis stopped at provider acceptance.

### 3.2 Why the design regressed

The original local-event implementation processed up to 100 entitlements in
one transaction and acquired shared locks once. Commit `3eb21d1` changed that
batch to one serial transaction per entitlement to prevent one user's failure
from rolling back the cohort, but retained the 100-row/five-second cap and
one-minute scheduler. The isolation goal was correct; serial execution plus
minute sleeps was not.

Commit `2697d61` correctly removed notification scheduling/Inbox work from the
gameplay transaction. It replaced the former advance schedule with one
`GLOBAL_STEP_EVENT_ACTIVATED_V1` parent event per user. At a timezone boundary,
hundreds of parents then entered serial event expansion and four-way recipient
projection. Notification failure no longer blocked gameplay, but notification
creation became both later and burstier.

The banner does not wait for push delivery. Both banner eligibility and the
activation domain event wait for the same entitlement activation transaction,
which made the two appear causally coupled during the incident.

The 125-token accumulation predates both changes. `DeviceToken` is unique only
on `(userId,token)`; registration has no installation identity, logout removes
only the one locally cached token, and token rotation/reinstall can therefore
append registrations forever.

## 4. Research basis

- Apple requires apps to register for remote notifications on each launch,
  warns not to use a locally cached device token as the current token, notes
  that tokens can change, and requires providers to support multiple devices:
  [Registering your app with APNs](https://developer.apple.com/documentation/UserNotifications/registering-your-app-with-apns).
- APNs request acceptance is not device display. Requests support an
  `apns-id` for correlation and `apns-expiration` to prevent stale delivery:
  [Sending notification requests to APNs](https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns)
  and [APNs delivery status and metrics](https://developer.apple.com/documentation/usernotifications/viewing-the-status-of-push-notifications-using-metrics-and-apns).
- Firebase recommends installation identities plus a server-side registration
  timestamp, refreshing that timestamp on upload, proactively removing stale
  registrations, and deleting registrations only on confirmed invalid-token
  responses: [FCM registration management](https://firebase.google.com/docs/cloud-messaging/manage-tokens).
- Large FCM senders must use bounded concurrency, honor throttling, and retry
  with exponential backoff and jitter rather than retry amplification:
  [FCM at-scale guidance](https://firebase.google.com/docs/cloud-messaging/scale-fcm).
- Redis Pub/Sub is at-most-once; a disconnected subscriber loses the message,
  so it may wake a durable scan but cannot own correctness:
  [Redis Pub/Sub delivery semantics](https://redis.io/docs/latest/develop/pubsub/).
- PostgreSQL documents `SKIP LOCKED` as suitable for queue-like multi-consumer
  access: [PostgreSQL `SELECT`](https://www.postgresql.org/docs/current/sql-select.html).

Large consumer applications use durable event/queue records, horizontal
workers, bounded fan-out, idempotency, provider batching/concurrency, retry, and
reconciliation. They do not synchronously loop through every user in the
business transaction, and they do not equate a provider's success response with
device presentation. This spec applies those principles at the app's current
scale without adding an external broker.

## 5. Required architecture

### 5.1 End-to-end flow

```text
future entitlement transaction
  -> generic scheduled-entitlement domain event (durable Postgres)
  -> early notification projection
  -> PENDING NotificationSchedule (availableAt = personal startsAt)

personal startsAt
  -> set-based entitlement activation (gameplay authority)
  -> impact rows + banner/scoring visibility commit independently

due-schedule worker
  -> bulk tri-state eligibility check
  -> Inbox alert + provider outbox
  -> APNs/FCM attempts for active installations
  -> durable per-installation terminal outcomes

reconciler
  -> compares eligible entitlements with every downstream stage
  -> repairs deterministic missing work until event expiry
```

Postgres is authoritative at every arrow. Redis contains only `DUE_SCAN` wake
hints after commit. Lost/duplicate hints change latency only, never correctness.

### 5.2 Advance notification schedule without gameplay coupling

When a future entitlement is created, append
`GLOBAL_STEP_EVENT_ENTITLEMENT_SCHEDULED_V1` to the existing generic domain
outbox in the same transaction. Its exact envelope is projectable immediately:

```js
{
  eventKey: `GLOBAL_STEP_EVENT_ENTITLEMENT_SCHEDULED_V1:${entitlementId}:${scheduleRevision}`,
  eventType: "GLOBAL_STEP_EVENT_ENTITLEMENT_SCHEDULED_V1",
  schemaVersion: 1,
  aggregateType: "GLOBAL_STEP_EVENT_ENTITLEMENT",
  aggregateId: entitlementId,
  occurredAt: now,
  availableAt: now,
  payload: {
    eventId, entitlementId, userId, multiplier,
    startsAt, endsAt, scheduleRevision, timezone
  },
  audience: [{ recipientId: userId, facts: {} }]
}
```

It records only domain facts and does not import or write notification, Inbox,
token, Redis, APNs, or FCM code. `DomainEvent.availableAt=now` deliberately
makes the candidate projectable early. The event-specific projection handler,
not the generic projector, maps `payload.startsAt` to the notification
schedule's `availableAt`; it must never use the domain event's availability as
the push release time.

The normal downstream projector processes this event before `startsAt` and
upserts one invisible `NotificationSchedule` with:

- delivery key `visible:GLOBAL_EVENT_STARTED:{userId}:{eventId}`;
- `availableAt = entitlement.startsAt`;
- `expiresAt = entitlement.endsAt`;
- `sourceRef = entitlement.id`; and
- the existing frozen-client payload, type, copy, and Home route.

The parent scheduler plans the earliest worldwide window at least 36 hours in
advance. Revision zero must project within five minutes of entitlement creation
and at least 12 hours before `startsAt` when the entitlement existed by that
deadline. Later-created valid entitlements and relocation revisions project
within five seconds. Domain-event retention cannot remove a revision until the
corresponding schedule is terminal.

Timezone relocation increments an additive entitlement `scheduleRevision` and
appends the same versioned event with the new revision. Projection uses one
revision-aware SQL upsert equivalent to:

```sql
ON CONFLICT (recipient_user_id, delivery_key) DO UPDATE
SET available_at = EXCLUDED.available_at,
    expires_at = EXCLUDED.expires_at,
    payload = EXCLUDED.payload,
    source_revision = EXCLUDED.source_revision
WHERE notification_schedules.status = 'PENDING'
  AND notification_schedules.source_revision < EXCLUDED.source_revision
```

It never moves a claimed/materialized alert. The relocation transaction remains
notification-agnostic and retains all safeguards in section 7.

Revision updates are monotonic: replaying revision zero after revision one is a
no-op. If an older activation projection creates the keyed Inbox alert first,
new schedule release links to that existing alert/outbox and marks the schedule
materialized instead of creating a second one.

Local activation no longer needs to append
`GLOBAL_STEP_EVENT_ACTIVATED_V1` to create its push. Existing events and pending
rows from older workers continue to drain. Both old activation projection and
new schedule release use the same delivery key, so rolling-version overlap can
materialize only one Inbox alert/outbox. Legacy global events retain their
existing compatible path until their lifecycle naturally drains.

An entitlement can exist before its final race eligibility is known. Therefore
the schedule is a candidate, not permission to send.

This event is consumer-first during a rolling deploy. Every process advertises
notification schema generation 2; no entitlement producer or timezone
relocation path may emit this event until the generation census in section 8.1
proves every expected owner is current. New projectors include a bounded repair
that resets this exact event type from terminal
`UNKNOWN_DOMAIN_EVENT_VERSION` to retryable only after its handler is installed.
Rollback first stops generation-2 production by allowing an old/missing owner
heartbeat to make the census false; the generation-2 consumer remains deployed
until no pending or retryable scheduled-entitlement event exists.

### 5.3 Fast, isolated entitlement activation

Replace one-entitlement serial processing with set-based micro-batches:

1. discover at most 100 due/retry-eligible entitlement IDs without row locks,
   ordered by `(startsAt,id)`;
2. discover affected race IDs without locks;
3. ensure and lock all affected C0 resolution rows in one set-based primitive,
   ordered by race ID—never two statements per race;
4. acquire the global enrollment advisory lock;
5. only then lock the candidate entitlements ordered by `(startsAt,id)`, using
   `SKIP LOCKED`, and reread/revalidate due and retry predicates;
6. reread race participation eligibility in one set-based query;
7. bulk insert unique race impacts and resolution enqueues;
8. bulk update each entitlement's correct terminal start outcome; and
9. commit gameplay state without touching notification implementation tables.

The universal order is therefore C0 rows -> global enrollment lock ->
entitlements. Candidate discovery never establishes ownership. Every activation,
late-enrollment, repair, settlement, and timezone-relocation writer must use this
order before generation-2 production is allowed. The census blocks mixed old/new
writers from enabling the new path; integration tests force both historical
opposing orders during rollout and prove the new generation remains disabled
until the old owner expires.

Lock-set closure is mandatory. After acquiring the discovered C0 set and then
the global lock, the writer rereads affected race IDs before locking
entitlements. If that set contains any race not already C0-fenced, it makes no
domain write and aborts the whole transaction with retryable
`GLOBAL_EVENT_LOCK_SET_CHANGED`; it never acquires a newly discovered C0 row out
of order. The next jittered retry rediscovers the expanded set. Every affected
writer and the structural lock inventory enforce this closure rule.

If a micro-batch fails with a classified row-local validation/data error,
recursively bisect it to isolate the row. Bisection depth is at most seven for a
100-row batch and total transaction attempts are capped at 255 per drain cycle.
Healthy halves commit immediately. A singleton atomically increments
`startAttemptCount`, records sanitized `startLastErrorCode`, and sets
`startNextAttemptAt` using full-jitter exponential backoff beginning at 250 ms
and capped at 30 seconds. After eight row-local attempts, or once `endsAt` is
reached, it becomes `FAILED_TERMINAL`, stamps `startFailedAt`, produces no
impact/push, and raises a completeness alert/manual-repair item.

Only constraint/check/data-shape failures explicitly mapped by code are
row-local. Connection loss, `40001`, `40P01`, lock/statement timeout,
serialization, pool exhaustion, and unknown SQLSTATEs are transaction-wide;
they never bisect and instead back off the whole page with jitter. The queue
predicate excludes `startNextAttemptAt > now`, preventing hot-spin.

After any claim returns a full page—or any due row remains—the cron role loops
again immediately. It does not sleep for the one-minute scheduler interval or
stop merely because five seconds elapsed. A next-due timer targets the earliest
future entitlement, with a one-second Postgres recovery scan after restart or a
missed timer. Work and concurrency remain bounded; the loop yields between
batches so other cron jobs are not starved.

### 5.4 Exact-boundary schedule release

The schedule worker targets the indexed earliest `availableAt`. At and after
that instant it claims up to 500 due schedules ordered by `(availableAt,id)`
with `SKIP LOCKED` and evaluates
all global-event rows in one bulk query:

- `ELIGIBLE`: activation is terminal-eligible and at least one race impact
  exists; atomically materialize the existing Inbox alert/outbox.
- `PENDING_ACTIVATION`: entitlement is still pending and the event remains
  open; defer 250 milliseconds and keep continuously draining.
- `INELIGIBLE_TERMINAL`: no active race, stale, missing, ended, or otherwise
  terminal-ineligible; cancel with an explicit reason.

`NO_ACTIVE_RACES` specifically becomes `CANCELLED_NO_ACTIVE_RACE`, a dormant
state rather than irrevocable ineligibility. If late enrollment first creates an
impact and changes the entitlement to `ACTIVATED_LATE_JOIN` before `endsAt`, its
domain transaction appends the already-deployed deterministic
`GLOBAL_STEP_EVENT_ACTIVATED_V1:{entitlementId}` event. Its existing projector
materializes the keyed alert/outbox immediately; the notification reconciler
then CASes the dormant schedule to `MATERIALIZED` and links the existing keyed
artifacts. After `endsAt` the schedule becomes `EXPIRED`. Reusing the known event
type avoids a second rolling-version capability and deterministic delivery key
prevents a second push if on-time materialization already won.

The worker performs set-based Inbox/outbox inserts with unique keys rather than
an N+1 eligibility/materialization loop. A full batch triggers another immediate
batch. A Redis wake after projection/activation is best effort only; the active
250-millisecond due loop and one-second reconciliation scan are sufficient
without Redis.

This reuses the existing environment-prefixed `notification:wake` scan hint. No
new Redis cache/stream/sorted set or application setting is introduced.

If an eligible activation is delayed, the push may catch up only while
`now < entitlement.endsAt`. APNs/FCM expiry/TTL equals the remaining event
window. No event-start notification is submitted after the event ends.

### 5.5 Completeness reconciliation

Reconciliation is split at the generic domain-event boundary:

- the steps-owned reconciler repairs only entitlement -> scheduled-entitlement
  domain-event publication; it never reads/writes notification tables; and
- notification-owned reconcilers repair domain event -> schedule -> Inbox/
  outbox -> delivery targets; they never change entitlement/gameplay state.

Each job pages at most 500 rows using a stable `(createdAt,id)` or
`(availableAt,id)` cursor, a five-second work budget, and deterministic keys.
Full pages schedule an immediate continuation; otherwise the steady recovery
cadence is one second near a due boundary and one minute for future work. No
one-second job performs a full-table census.

Every local entitlement has one expected schedule key before its start. The
separate owners continuously and idempotently repair these gaps:

- future entitlement without scheduled domain event;
- scheduled domain event without `NotificationSchedule`;
- terminal eligible activation without schedule/Inbox/outbox;
- leased/retryable outbox past its deadline; and
- snapshotted active registration without a terminal delivery-target row.

Repairs reuse the deterministic keys and never duplicate durable alerts or
outboxes. The operator census reports counts and oldest age at each stage, plus
the denominator:

`eligible entitlements -> schedules -> alerts/outboxes -> active installations
-> accepted / invalid / no-device / permanent-fail / exhausted`.

At first outbox claim, one transaction creates durable `PENDING` targets for the
current active registrations. Each target stores `deviceTokenId`, recipient user
ID, installation ID, platform/environment, token fingerprint, and token
ownership generation—but never a raw token snapshot. That target set is the
immutable denominator. A token uploaded later is not a retroactive target.

Before every provider call, delivery rereads the exact `DeviceToken` row and may
read its current raw token only when row ID, recipient, installation, status,
generation, environment, and fingerprint all still match. Rotation,
reassignment, logout, invalidation, or quarantine converts a pending target to
terminal `SUPERSEDED`, `OWNERSHIP_CHANGED`, `INVALID`, or `QUARANTINED`; no stale
owner/token is ever sent. `ACCEPTED`, those four states, `PERMANENT_FAIL`,
`EXHAUSTED`, and `NO_DEVICE` are terminal. The outbox completes only when every
snapshotted target is terminal; retries select only retryable targets.

`NO_DEVICE`, notification permission unavailable to the server, provider
rejection, and retry exhaustion are explicit terminal outcomes, not “delivered.”
The existing Inbox alert remains visible even when no push-capable installation
exists.

### 5.6 Provider delivery semantics

The existing Inbox delivery worker remains the sole visible APNs/FCM sender.
It continuously drains full pages instead of waiting 15 seconds after each page.
Initial separately enforced code constants are: 128 claimed outbox rows, 64
concurrent recipients, at most 10 targets for one recipient, at most 64 global
APNs calls, 64 global FCM calls, and 32 concurrent DB outcome writes. Provider
semaphores cap total calls, so recipient x target limits can never create 640
simultaneous sends. Final constants may be lowered in code before release if the
required load test fails provider or host headroom; they are not runtime flags.

Leases last 30 seconds and renew every 10 seconds with the existing lease token.
Graceful shutdown stops claims, waits up to four seconds for in-flight calls and
outcome writes, then leaves remaining leases for expiry/reclaim. The worker
retries only transient targets, honors `Retry-After`, uses exponential backoff
with full jitter, clips all retries at notification expiry, and never retries an
accepted/terminal target.

For event pushes:

- Provider adapter input adds `expiresAt`, a <=64-byte deterministic collapse
  key (`event:` plus a bounded hash), and expected provider environment.
- APNs uses priority 10 and integer epoch-seconds `apns-expiration`; it records
  returned `apns-id` and selected environment.
- FCM uses high priority and a nonnegative remaining TTL clipped to provider
  limits; it records the returned message name/ID.
- `InboxDeliveryDeviceAttempt.ACCEPTED` means provider accepted. Rename operator
  labels that currently call this state simply `DELIVERED` to
  `PROVIDER_ACCEPTED`; public APIs need not change.
- Provider IDs, status/reason, attempt count, timestamps, and token/installation
  fingerprints are sufficient to investigate one request without logging raw
  tokens.

Installation-aware APNs rows are sent only to their recorded environment.
Legacy rows with unknown environment may retain the existing one-time
`BadDeviceToken` environment fallback; a successful fallback stamps the
environment. Once the environment/topic is known, an APNs invalid-token result
is terminal for that exact registration.

Both adapters return the normalized contract
`{success,statusCode,reason,providerMessageId,environment,retryAfterMs,
invalidToken,permanent}`. HTTP 429/5xx/timeouts are transient; provider
unregistered/expired registration responses are invalid-token terminal; other
4xx responses are permanent only after payload validation distinguishes token
errors from application errors. APNs `Retry-After` and FCM retry metadata feed
the same jittered retry scheduler.

At-least-once provider submission remains explicit: a process can crash after
provider acceptance but before recording it. Durable intent and Inbox creation
are exactly-once by key; physical push presentation is neither exactly-once nor
guaranteed.

## 6. Installation-aware token lifecycle

### 6.1 Registration contract

Extend `POST /notifications/device-token` additively with optional fields:

```json
{
  "deviceToken": "...",
  "platform": "ios|android",
  "installationId": "optional-for-old-clients",
  "providerEnvironment": "optional"
}
```

`deviceToken` is 1..4096 bytes, `installationId` is optional for old clients but
when present is 1..128 ASCII characters matching `[A-Za-z0-9._:-]+`, and
platform remains exactly `ios|android`. Invalid requests use standard
`{error,code}` `AppError` responses. Successful POST remains backward-compatible
and adds capability metadata:

```json
{"success":true,"registrationVersion":2,"installationAccepted":true|false}
```

`installationAccepted` is true only when a valid installation ID was bound;
legacy two-field registration returns false. Flutter parses both additive fields
defensively: absent/wrong-typed `registrationVersion` defaults to 1 and absent/
wrong-typed `installationAccepted` defaults to false.

Old clients' existing two-field requests remain valid. New clients send a
stable app-installation identifier and the current OS/provider token whenever
an authenticated session starts and whenever the token changes. The server
stamps `lastRegisteredAt` on every upload, even when the token is unchanged.
`providerEnvironment` is normalized by the server from authenticated app/build
context; an arbitrary client value is never trusted as authorization or routing
for another app/topic.

For iOS, the only accepted values are `production` and `sandbox`. The production
backend pins topic `APNS_BUNDLE_ID=com.rohanchari.steptracker` and environment
`production`; nonproduction backends pin their configured topic and `sandbox`.
An optional client value must match the server-pinned value or is rejected. The
field is omitted/ignored for Android because FCM has no APNs environment split.

DELETE accepts either the legacy exact token or the additive shape:

```json
{"deviceToken":"current-token-if-known","installationId":"installation-id"}
```

When both are present, the new backend requires them to identify the same
authenticated user's active installation or returns `409 REGISTRATION_MISMATCH`;
installation identity takes precedence after that check. Success is
`{success:true,removed:n}` and remains safe for old clients. The new app sends
both values whenever the current token is available so an older backend can
still unregister it. It sends installation-only DELETE only after the current
session observed `registrationVersion >= 2`; otherwise it safely skips remote
logout cleanup and relies on ownership reassignment at next registration.

The exact error matrix is:

| Operation | HTTP | `code` |
|---|---:|---|
| POST missing/empty token | 400 | `DEVICE_TOKEN_REQUIRED` |
| POST token over 4096 bytes | 400 | `DEVICE_TOKEN_TOO_LONG` |
| POST invalid platform | 400 | `DEVICE_PLATFORM_INVALID` |
| POST invalid installation ID | 400 | `INSTALLATION_ID_INVALID` |
| POST invalid/mismatched iOS environment | 400 | `PROVIDER_ENVIRONMENT_INVALID` / `PROVIDER_ENVIRONMENT_MISMATCH` |
| DELETE missing both identifiers | 400 | `DEVICE_REGISTRATION_IDENTIFIER_REQUIRED` |
| DELETE invalid/oversized identifier | 400 | corresponding token/installation code above |
| DELETE installation-only on v2 backend | 200 | success body |
| DELETE token/installation mismatch | 409 | `REGISTRATION_MISMATCH` |

Every error body is `{"error":"stable human message","code":"..."}`.

Android obtains its Firebase Installation ID from Firebase Installations; if FID
lookup fails, token registration falls back to the legacy two-field request and
retries installation binding next session. iOS creates an app-scoped random UUID
in Keychain with a `ThisDeviceOnly` accessibility class; if secure storage is
unavailable it likewise registers the current token through the legacy contract
and retries binding later. Neither identifier is a hardware ID. Regeneration
safely creates a new installation while cap/quarantine bounds abandoned rows.
If Keychain preserves the UUID across app deletion/reinstall, the app reuses it;
a second identity appears only when secure storage was actually cleared or
unavailable and a new UUID is generated.

On iOS, stop reposting `_keyDeviceToken` from `SharedPreferences` as if it were
current. Ask APNs to register each launch and upload the token supplied by the
current callback. A short-lived in-memory token supports same-session logout;
installation identity handles version-2 logout, so persistent token caching is
unnecessary.

The route is reduced to validation/response wiring with `asyncHandler` and
`AppError`. Registration, reassignment, cap enforcement, and deletion live in
injected notification-domain commands/models; no new Prisma logic is added to
the legacy route or shared provider helper.

### 6.2 Ownership and bounded registrations

`DeviceToken` gains nullable/additive installation and lifecycle fields:

- `installationId`, `lastRegisteredAt`, `lastProviderAcceptedAt`;
- `status` (`ACTIVE`, `QUARANTINED`, `INVALIDATED`, `SUPERSEDED`), nullable
  `statusReason`, `statusChangedAt`;
- `ownershipGeneration int default 1`, optional provider environment; and
- no raw token in operational logs or metrics.

Null status on legacy rows is read as active during phase one. Final partial
unique indexes enforce one active row per `(platform,installationId)` when the
ID is present and one active owner per `(platform,token)`. Multiple real
installations remain supported.

Registration runs in one transaction. It derives advisory-lock keys for the
platform/token and optional platform/installation identity, sorts those keys,
and acquires them in that order. It discovers both potentially matching rows,
then acquires affected-user advisory locks in ascending user ID order. It
revalidates after locks before writing:

- matching token and installation refreshes the canonical row;
- matching installation with a rotated token updates that canonical row and
  increments `ownershipGeneration` when no separate token row exists;
- a token active on another account is marked `SUPERSEDED` with
  `OWNERSHIP_CHANGED`, then bound to the authenticated account's canonical
  installation row;
- while the existing `(userId,token)` compatibility index remains, if token and
  installation resolve to different rows the **token row** is canonical: mark
  the old installation row `SUPERSEDED`, clear its installation ID, then bind
  that installation/user and an incremented generation to the token row. Raw
  token is never copied onto a second same-user row; and
- legacy requests without installation identity use token identity as their
  stable fence and remain one row per current token.

These identity locks plus the final unique indexes make concurrent reassignment,
rotation, and collision deterministic without leaking a token across accounts.
The existing `(userId,token)` unique index remains throughout this story. Any
future switch to installation-row canonicalization is a separate contract
migration no earlier than one week after all old backend writers are unavailable.

An account may have at most **10 active push installations** across both
platforms. While holding that user's lock, registration activates the current
row, orders all active rows by `(lastRegisteredAt DESC,id DESC)`, keeps the first
ten, and marks the remainder `QUARANTINED` with reason `QUARANTINED_CAP`.
Therefore two simultaneous eleventh registrations converge to the same ten.
The cap is based on production evidence (p95 two tokens; highest non-Rohan
account seven) and leaves headroom while making 125 active sends impossible.

The migration does not irreversibly delete excess rows. For accounts above the
cap, keep the ten most recently registered/updated rows active and mark older
rows `QUARANTINED_CAP`. A later valid registration immediately reactivates its
installation and rotates another least-recent row into quarantine. Raw
quarantined tokens are removed after 180 days only when no nonterminal target
references them.

### 6.3 Safe stale pruning

- Confirmed APNs/FCM unregistered/expired-token responses invalidate the exact
  row immediately. Payload-level `INVALID_ARGUMENT` does not delete a token
  unless the adapter proves the payload itself was valid and the provider says
  the registration is invalid.
- Installation-aware rows not refreshed for 90 days are quarantined, not
  deleted. Opening the app re-registers/reactivates them.
- Legacy rows without `installationId` are not age-pruned because frozen clients
  may not refresh them regularly. They are still subject to exact provider
  invalidation and the ten-active-row cap.
- Provider acceptance refreshes `lastProviderAcceptedAt` but does not replace a
  client registration timestamp and does not prove device display.
- Invalidated/superseded rows retain raw tokens for 30 days, and quarantined rows
  for 180 days, then cleanup removes them only when no nonterminal delivery
  target references them. Cleanup is bounded to 500 rows, resumable by
  `(statusChangedAt,id)`, audited by counts/reasons, and never runs in a user
  request or provider-send transaction.

## 7. Request-time timezone reconciliation

The prior request-time draft is folded into this spec with the following
normative behavior:

- only a valid, explicit changed `X-Timezone` on an authenticated request can
  reconcile an entitlement;
- update `users.timezone` and the eligible entitlement atomically;
- relocate the same `(eventId,userId)` row at most once and only before the
  parent's earliest worldwide compatibility-envelope start;
- require old and new personal starts to be future, no processing/impact/
  domain disclosure fence, and no neighboring-event overlap;
- update timezone/local date/start/end and increment `scheduleRevision` in the
  same transaction, then append the generic scheduled-entitlement event;
- keep Redis presentation-cache invalidation best effort and never use Redis as
  the relocation authority or retry marker; and
- fail open to the user's requested API operation under the existing bounded
  lock/statement/transaction timeouts.

Relocation never reads notification schedules, Inbox, outbox, targets, or
provider state. The parent's earliest-worldwide-envelope check plus domain-owned
`startProcessedAt`, impact, summary, activation-event, and disclosure fences are
the complete authority. Because relocation is forbidden before any personal
release boundary can arrive, the downstream pending schedule is safely advanced
by revision and cannot have been legitimately materialized.

Replace the two current middleware writes with one injected collaborator and
one transaction. Candidate entitlement/race discovery is non-locking; the
transaction then takes set-based C0 locks ordered by race ID, the global
enrollment lock, and at most four entitlement rows ordered by `(startsAt,id)`.
It rereads all predicates, updates `users.timezone` plus eligible entitlement
rows, increments revisions, and appends revision events atomically. A failure
rolls all of those writes back, so the unchanged stored timezone remains the
durable retry marker for the next request. Only after commit does middleware
update the request-scoped user and invalidate presentation caches best effort.

The collaborator also applies the existing 48-hour stable-timezone state machine
in that same user transaction: changed observed zones set/refresh
`globalEventTimezoneCandidate` and its timestamp; a repeated candidate after 48
hours promotes `globalEventTimezone`; observing the stable zone clears stale
candidate state. A valid unchanged immediate timezone still enters the
collaborator only when candidate cleanup/promotion has a non-null mutation;
otherwise steady state performs zero writes and no entitlement reconciliation.

The synchronous request path uses one set-based artifact check, no per-row
transaction loop, no more than eight application SQL statements excluding
transaction control, `lock_timeout=100ms`, `statement_timeout=400ms`, and a
500ms transaction budget with no inline retry. Timeout/failure fails open to the
requested endpoint. Every affected writer must use the same C0 -> global ->
entitlement order before the generation census permits relocation. If
activation wins, relocation loses safely.

No app release is required for timezone observation because current and many
older clients already send the header. Token installation identity does require
a new iOS/Android build, but the backend remains compatible with frozen clients.

## 8. Data model and compatibility migrations

Add only backward-compatible fields/tables/indexes:

1. `GlobalStepEventEntitlement`
   - `timezoneRelocatedAt timestamp null`;
   - `timezoneRelocatedFrom text null`;
   - `scheduleRevision int not null default 0`;
   - `startAttemptCount int not null default 0`, `startNextAttemptAt timestamp
     null`, `startLastErrorCode text null`, `startFailedAt timestamp null`.
2. `NotificationSchedule`
   - `sourceRevision int not null default 0`;
   - retain unique `(recipientUserId,deliveryKey)`.
3. `DeviceToken`
   - lifecycle/installation fields from section 6;
   - partial uniqueness for active installation ownership and global provider
     token ownership after duplicate reconciliation.
4. `InboxDeliveryDeviceAttempt`
   - nullable `deviceTokenId`, recipient user ID, installation ID,
     `ownershipGeneration`, token fingerprint, platform/environment;
   - target disposition, next-attempt time, provider message ID/response time.
5. `InboxDeliveryOutbox`
   - nullable `expiresAt`; legacy null rows retain existing no-expiry behavior.
6. Existing `GlobalStepEventCronOwner`, expanded as the single compatibility
   census rather than introducing a competing table:
   - logical owner ID, per-boot UUID, role, generation, capabilities,
     heartbeat/expiry, and updated timestamp.
7. Singleton `GlobalStepEventGenerationState`
   - required generation, nullable continuous `readySince`, nullable
     `quarantineStartedAt`, and updated timestamp.

Required indexes/constraints are:

- partial activation queues `(starts_at,id) WHERE start_processed_at IS NULL`
  and `(start_next_attempt_at,starts_at,id) WHERE start_processed_at IS NULL`;
- notification schedule `(status,available_at,id)`;
- delivery target `(outbox_id,disposition,id)`,
  `(disposition,next_attempt_at,id)`, and
  `(device_token_id,ownership_generation,disposition)`;
- active-token LRU `(user_id,status,last_registered_at,id)` and stale cleanup
  `(status,status_changed_at,id)`;
- final partial unique active token `(platform,token) WHERE status='ACTIVE'` and
  active installation `(platform,installation_id) WHERE status='ACTIVE' AND
  installation_id IS NOT NULL`;
- generation-owner expiry `(generation,expires_at,logical_owner_id,boot_id)`; and
- bounded reconciler indexes matching their `(created_at,id)` and
  `(available_at,id)` cursors.

Representative production-shaped `EXPLAIN (ANALYZE,BUFFERS)` fixtures must use
these indexes for due-queue claims and LRU/stale scans, with no full-table sort
or sequential scan once tables exceed the fixture threshold. Every query has an
explicit `LIMIT`; index plans and p95 lock/connection waits are load-test gates.

### 8.1 Generation census and permanent compatibility gate

Expected production logical owners are exactly `http:0`, `http:1`,
`resolution:0`, and `cron:0`, derived from `STEPS_PROCESS_ROLE` plus PM2 instance
identity. Every process creates a random boot UUID and heartbeats outside the
`startCrons()`/`NODE_APP_INSTANCE=0` guard every 15 seconds with a 45-second
expiry. The primary key includes logical owner plus boot UUID, so overlapping
old/new PM2 processes create extra live rows and cannot mask one another.

Generation 2 capability bits are: scheduled-event consumer, universal C0 lock
order/closure, token lifecycle writer/reader, target-aware sender, and
reconciler ownership. Readiness requires exactly one unexpired boot for each
expected logical owner, no additional live boot, and every bit. Its transaction
sets singleton `readySince` only on the first continuously ready observation and
clears it on any mismatch. Generation 2 becomes usable only when
`now-readySince >= 90 seconds`, two full heartbeat-expiry windows.

This expands and replaces the behavior of the existing
`GlobalStepEventCronOwner`; its prior local-aware owner-count check becomes a
capability query over these same rows/state. There is no second census.

Generation readiness is a permanent mixed-version compatibility precondition,
not a feature toggle. Producers and timezone relocation preserve legacy-safe
behavior while false. Registration phase-one code treats null token status as
active. No quarantine, duplicate-owner reassignment, or final partial-unique
index creation occurs until readiness is continuously true and the bounded
duplicate audit is clean.

When quarantine first begins, stamp `quarantineStartedAt`. From that instant,
token readers/senders/writers are permanently roll-forward-only: no version
that ignores status may be restored, even if readiness later becomes false. A
false census still stops new scheduled-event production, but never re-enables
legacy token reads. Before final partial indexes, one audited update converts
every surviving null status to `ACTIVE`; dedup/cap quarantine then runs and the
conflict audit must report zero.

Use a compatibility-safe two-phase migration. First add nullable/defaulted
columns and nonunique indexes. Deploy code that can filter active rows and
enforce ownership/caps transactionally, but retains the legacy-compatible upsert
until continuous generation readiness is proven. Then quarantine duplicate `(platform,token)`
owners and excess rows, then add the supporting unique indexes concurrently.
Keep the most recently registered/updated owner active and quarantine
conflicting older owners with an audit reason. The generation census is a
rolling-version compatibility stamp, not a feature flag or behavior toggle.

No existing API field is removed or repurposed. Old app binaries remain valid;
new backend code accepts old registration payloads. The data-quarantine phase
does not run while an old sender that ignores token status is live. Rollback
before the final uniqueness phase is code-only; after final constraints, roll
forward with the compatible new registration code rather than restoring a
writer that cannot satisfy the new invariant.

The first phase also installs the new event consumer while producers remain
census-blocked. Startup repair resets only scheduled-entitlement events that an
old projector terminal-failed as `UNKNOWN_DOMAIN_EVENT_VERSION`, at most 500 per
page with deterministic audit counts. The second data phase runs only after all
owners are generation 2; final unique indexes are applied concurrently only
after quarantine/dedup leaves zero conflicts.

During schedule materialization, copy `NotificationSchedule.expiresAt` to
`InboxDeliveryOutbox.expiresAt` atomically. If the keyed old Inbox alert/outbox
already exists, CAS-fill its null expiry with the event expiry before marking
the schedule materialized. Claims exclude expired outboxes; retries cap
`availableAt` at expiry; APNs expiration and FCM TTL read outbox expiry. Legacy
outboxes with null expiry retain current behavior.

The retained unique `(outboxId,tokenHash)` is the delivery-target idempotency
boundary, including `tokenHash='__NO_DEVICE__'` for the no-device sentinel.

### 8.2 Process/job ownership and shutdown

Every process starts only the census heartbeat outside cron guards. The existing
single `cron:0` branch of `startCrons()` owns and retains stop handles for:

- existing `build/scheduleGlobalStepEvents`, which remains responsible for
  parent/legacy planning and gains an async stop handle;
- `build/scheduleGlobalEventBoundaryDrain`;
- `build/scheduleGlobalEventEntitlementEventReconciler` (steps-owned);
- existing `build/scheduleDomainEventProjection`;
- `build/scheduleNotificationScheduleRelease`;
- `build/scheduleNotificationCompletenessReconciler` (notification-owned);
- existing target-aware `build/scheduleInboxDelivery`; and
- `build/scheduleDeviceTokenCleanup`.

Each `buildX` accepts injected clock/repository/limits for integration tests;
each `scheduleX` owns timers/subscriptions, prevents overlapping runs, and
returns an idempotent async `stop()` handle. HTTP/resolution processes never
claim these queues.

SIGTERM first stops all new claims/timers/subscriptions, closes the HTTP server,
then waits at most four seconds for registered job stop handles and provider
adapters. Four seconds remains below the existing five-second application hard
exit and ten-second PM2 kill timeout. Unfinished provider work is not declared
successful; its 30-second fenced lease expires and Postgres recovery reclaims
it. No PM2 timeout/capacity change is required.

Deploy order after later approval is additive database migration, backend, then
iOS and Android together. Backend correctness and event notification fan-out do
not wait for the app release; installation-aware replacement improves as users
upgrade.

## 9. Performance and reliability objectives

Measure from each personal `startsAt`, with separate, named SLIs:

- eligible gameplay activation/banner authority: p95 <= 2 seconds, p99 <= 5
  seconds;
- eligible activation to Inbox/outbox materialization: p95 <= 1 second, p99 <=
  3 seconds;
- `startsAt` to first adapter submission attempt for a valid snapshotted target:
  p95 <= 5 seconds, p99 <= 10 seconds;
- adapter-call to provider acceptance: p95 <= 500 ms and p99 <= 2 seconds in
  the healthy-provider load profile;
- `startsAt` to first provider acceptance: p95 <= 5 seconds and p99 <= 10
  seconds only for valid targets during the healthy-provider profile; it is not
  an SLO during a provider outage;
- 100% of eligible entitlements have a `MATERIALIZED` schedule, Inbox alert,
  and push outbox; an eligible cancellation/expiry is a failed run, and every
  snapshotted target reaches an explicit terminal accounting state before
  `endsAt`;
- no eligible pending activation, pending schedule, or retryable outbox may be
  older than 30 seconds without an operational alert.

Activation denominators include every syntactically valid due entitlement;
terminal row-local corruption is reported separately and fails the completeness
gate. Submission denominators exclude ineligible/no-device targets and include
every active valid target snapshotted at first claim. Acceptance denominators
include only provider responses that are capable of acceptance; invalid tokens
remain explicit terminal failures. All retries are clipped at `endsAt`, and an
outage run passes by durable recovery/terminal-expiry accounting—not by meeting
the healthy-provider latency objective.

Extend the existing load-testing contract with an `event_boundary_10000`
profile and raise only that validated profile's user ceiling to 10,000. Fixtures
contain 10,000 simultaneously due users: 70% in one active race, 20% in two,
10% in three; active-registration distribution is 20%/60%/15%/4%/1% with
0/1/2/5/10 installations. Those distributions must execute to exactly 14,000
race memberships and 12,000 active installations. The healthy provider stub
must expose an exact first-cycle census of 11,904 accepted, 60 throttled, 24
transient, and 12 invalid dispositions across those 12,000 installations, in
addition to p50 40 ms, p95 120 ms,
p99 300 ms, 0.5% HTTP 429 with 250 ms `Retry-After`, 0.2% transient 503, and
0.1% confirmed invalid tokens. A separate outage run returns transient failure
for 60 seconds and proves recovery/expiry without claiming acceptance SLOs.

Each run has a two-minute warmup, ten-minute measured window, and three clean
repetitions while background load sustains 25 authenticated HTTP requests/sec
and 50 resolution jobs/sec. Pass gates are: cron RSS < 512 MiB; no process RSS
crosses its committed PM2 ceiling; DB pool wait p99 <= 100 ms; lock wait p99 <=
100 ms; HTTP p95 latency degrades <=20% from warmup; unrelated resolution/cron
queue lag increases <=2 seconds; no pool exhaustion; no event-loop stall above
250 ms; and all stage SLOs above pass in each repetition. Claims remain bounded
and there is no one-minute/15-second sawtooth. Failure requires architecture or
code-constant revision before deployment, never a production capacity change by
assumption.

A separate provisioning profile creates 10,000 future entitlements, revision-0
domain events, and schedules within ten minutes, with every schedule projected
within five minutes of its entitlement and at least 12 hours before start under
the 36-hour planning horizon.

## 10. Tests-first implementation plan

All new tests must fail for the intended reason before business logic changes.
Backend integration tests use only a dedicated `*_test` Postgres and local
Redis DB 15 where Redis is relevant; never production.

### 10.1 Activation and schedule integration tests

1. Through the real local-event lifecycle, 561 same-time entitlements activate
   and create impacts/banner eligibility within the objectives without a minute
   sleep.
2. One malformed entitlement triggers batch bisection; all healthy users
   activate; the singleton follows durable jittered retry without hot-spin and
   reaches explicit terminal failure after the bounded attempt/expiry rule.
3. Two claimers, process restart, lock timeout, and duplicate ticks produce no
   duplicate impacts, resolution jobs, alerts, or pushes.
4. Entitlement creation emits an immediately projectable event whose handler
   schedules at payload `startsAt`; revision-aware SQL ignores stale revisions
   and never exposes an Inbox alert early.
5. At start, bulk tri-state release sends only terminal-eligible users; pending
   activation is retried at 250 milliseconds; no-race users enter dormant
   cancellation; stale/ended users expire.
6. Projector and provider outages recover from Postgres without Redis. Redis
   restart, eviction, duplicate/lost wake, and `REDIS_URL` unset change no final
   result.
7. Crash in every handoff window replays by deterministic key.
8. Old `GLOBAL_STEP_EVENT_ACTIVATED_V1` projection racing new schedule release
   creates one compatible alert/outbox/push intent.
9. Notification failure never rolls back activation/scoring/banner state, and
   gameplay failure never releases an ineligible schedule.
10. Delayed catch-up sends only before `endsAt`; provider TTL/expiration equals
    the remaining event window.
11. Separate steps/notification reconcilers repair each intentionally missing
    stage without crossing imports/tables and record every terminal outcome.
12. Existing local-event scoring, race settlement, Home/race banner, payload,
    and routing integration tests remain unchanged and green.
13. Historical entitlement-first and new C0-first writers run concurrently;
    generation readiness remains false until the old owner expires, after which
    every writer follows C0 -> global -> entitlement with no deadlock.
14. Consumer-first rollout does not emit unknown events to an old projector;
    bounded repair resets only matching `UNKNOWN_DOMAIN_EVENT_VERSION` rows.
15. Query-plan tests cover every queue/LRU/reconciler index and reject unbounded
    or N+1 hot-path scans at production-shaped cardinality.
16. A user with no race at the boundary receives no push then; first late
    enrollment before event end emits the generic late-activation event, rearms
    the dormant schedule, and produces one catch-up push. Late enrollment after
    expiry produces none.
17. Post-global-lock race-set expansion aborts with no writes, retries from
    discovery, and never acquires a C0 fence out of order.
18. Schedule materialization copies expiry to a new/existing outbox; claims and
    retries stop at expiry while legacy null-expiry notifications remain intact.
19. Per-boot overlapping PM2 owner rows keep readiness false; `readySince`
    clears on any gap and generation enables only after 90 continuous seconds.

### 10.2 Token lifecycle integration tests

1. Old two-field registration still works; new registration updates one
   installation row and `lastRegisteredAt` on every upload.
2. Token rotation replaces the same installation row; reinstall reuses a
   preserved Keychain identity, while an actually reset/new installation
   creates a bounded second row.
3. Registering a token after account switch atomically removes it from the old
   account before enabling it for the new account.
4. Ten real installations remain active; the eleventh quarantines the least
   recent; re-registration reversibly reactivates it. No send reads more than
   ten active rows for one account.
5. A 125-row legacy fixture migrates to ten active and 115 quarantined rows,
   never 125 provider attempts, with no irreversible deletion.
6. Confirmed unregistered errors invalidate only the exact token. Transient,
   timeout, throttling, and ambiguous payload errors do not prune it.
7. Installation-aware 90-day rows quarantine and reactivate on launch; legacy
   unbound rows are not age-pruned.
8. Partial multi-device acceptance retries only transient devices and records
   provider IDs without raw-token logs.
9. iOS startup uses the current APNs callback, never a cached token repost;
   Android uploads current FID/token; logout works by installation ID.
10. Frozen iOS/Android binaries remain compatible throughout a rolling backend
    deploy.
11. Known APNs environments use one provider host; legacy unknown rows may
    fallback once and persist the successful environment.
12. Concurrent rotation, cross-account reassignment, token/installation row
    collision, and two eleventh registrations obey sorted identity/user locks,
    final unique indexes, deterministic canonical-row selection, and LRU cap.
13. First claim snapshots durable targets. Rotation, logout, quarantine, and
    account switch before retry yield `SUPERSEDED`, `QUARANTINED`, or
    `OWNERSHIP_CHANGED` without sending the stale token to either user.
14. POST/DELETE exact old/new payloads, validation limits, capability response,
    mismatch response, and old-backend logout fallback are tested through real
    HTTP routes.
15. Lease renewal, graceful shutdown, global provider semaphores, DB-write
    semaphore, provider IDs, expiry units, `Retry-After`, and normalized error
    mapping are integration-covered.
16. Compatibility collision keeps the token row canonical under the retained
    `(userId,token)` index; null statuses are backfilled active before cap/dedup
    and final partial-index creation.

### 10.3 Timezone integration tests

Retain every test in the prior request-time draft: pre-envelope Denver-to-New
York relocation, unchanged/invalid/missing headers, transaction rollback retry,
old/new start fences, once-only relocation, UTC+14 disclosure, neighboring
window non-overlap, concurrent boundary/late enrollment lock orders, Redis
cache failure, frozen clients, and real scoring/settlement against the final
persisted interval. Add schedule-revision tests proving the notification moves
to the same final interval and cannot be released at the old one. Force
middleware transaction failure after the user-row operation and prove the
timezone remains unchanged so the next request retries; assert the four-row,
eight-statement, 100/400/500 ms bounds.

### 10.4 Verification

- Backend: relevant integration suites first, then `npm run test:integration`
  and `npm run test:unit`; never bare `npm test`.
- Extend and run the existing capacity harness for provisioning, healthy
  boundary, and provider-outage profiles exactly as section 9 defines.
- Frontend: real notification service/backend-contract tests, `flutter test`,
  and clean `flutter analyze`.
- Build and verify iOS and Android in lockstep for the installation-ID release.
- Run the code-reviewer after non-trivial implementation. No UI-placement
  checklist is required because no visible element is added, moved, or removed.
- Structural guards prove only delivery code invokes APNs/FCM, steps code cannot
  import notification persistence, and activation uses the set-based C0 writer.
- Startup tests prove every process heartbeats outside cron guards, only cron:0
  owns queue schedulers, every stop handle runs on SIGTERM, claims cease, and
  the four-second drain remains below existing hard/PM2 termination windows.

## 11. Observability and operations

Expose stage-specific counters/histograms and oldest-age gauges without raw
tokens or notification payloads:

- due/claimed/activated/failed entitlements and batch-bisection count;
- expected/missing/pending/materialized/canceled/expired schedules;
- start-to-activation, activation-to-alert, alert-to-provider-acceptance;
- outbox leased/retry/permanent/exhausted and provider throttling;
- active/quarantined/invalidated registrations per platform, cap evictions,
  cross-account reassignments, and provider-invalid cleanup;
- active-token count distribution and anomaly alert above ten; and
- eligible users with no active installation versus provider-accepted users.

Alert on any 30-second oldest eligible backlog, objective breach, completeness
mismatch, scheduler heartbeat failure, or active-token invariant violation.
Runbooks must distinguish event activation, notification materialization,
provider acceptance, and OS display. “User did not see push” first checks the
current installation registration and provider ID; it never treats Inbox outbox
`DELIVERED` alone as proof of presentation.

Production verification remains SELECT-only until separately authorized.
Staging stays shut down unless the user gives explicit in-the-moment permission.

## 12. Rollout and rollback

- No feature flag. Permanent behavior is additive and version-compatible.
- Apply the expand-only compatibility migration and deploy generation-2
  consumer/writer code. Producer behavior remains legacy-safe until all exact
  owners pass the permanent generation census for two expiry windows. Then new
  schedule production begins automatically, bounded unknown-event repair runs,
  and the audited token quarantine/final concurrent-index phase may proceed.
  Release iOS and Android together only after the backend contract is live.
- The new backend continues accepting old token requests and old activation
  events. New clients read additive capability fields defensively; old clients
  ignore them.
- Before `quarantineStartedAt`, rollback first makes the census false so no new
  event is produced and retains a generation-2 consumer until all new event rows
  are terminal; a fully legacy-compatible code rollback is still possible.
  From `quarantineStartedAt` onward, token writer/reader/sender code is
  roll-forward-only even before final constraints. Event production may still
  stop on a false census, but an incompatible token reader is never restored.
  Never reverse/drop schema during an incident.
- Pre-deploy proof uses a test database and production-shaped synthetic load.
  Deployment, production migration, token quarantine, or production writes
  require fresh explicit authorization after spec approval and implementation
  review.

## 13. Acceptance criteria

- A same-time cohort does not drain one user per transaction followed by a
  one-minute sleep; healthy users are not blocked by one bad row.
- Event scoring/banner state commits independently and meets activation SLOs.
- Every future entitlement has a durable advance notification candidate, every
  eligible activation is reconciled to one alert/outbox, and every active
  registration snapshotted for that outbox has a terminal target state before
  event expiry.
- Normal event pushes reach APNs/FCM acceptance within the provider SLO without
  waiting for activation-domain-event fan-out.
- No push is released early, to an ineligible user, or after the event expires.
- Redis loss cannot lose or duplicate durable work.
- At most ten active push installations exist per account; token rotation and
  account switching cannot append or leak registrations indefinitely; the
  former 125-token shape is impossible.
- Operator language and metrics distinguish provider acceptance from device
  display and retain provider correlation IDs.
- Timezone relocation updates gameplay and notification windows atomically by
  revision and cannot create a second opportunity.
- Frozen app versions and rolling backend versions remain compatible.
- Generation gating prevents old projectors from terminal-failing newly
  produced event types and prevents old token senders from bypassing quarantine.
- Required integration/performance suites pass, both mobile platforms are
  verified, architect and code reviews are complete, and no Definition of Done
  step is silently skipped.

## 14. Resolved owner decision

On 2026-08-26 the owner approved the proposed hard ceiling of ten active
installations per account. It is deliberately above the observed normal maximum
of seven and below any count that can materially amplify fan-out.

## 15. Revision log

- Initial consolidated draft: combined the request-time timezone correction,
  2026-08-26 boundary-throughput incident, advance event notification schedule,
  completeness reconciliation, provider semantics, and installation-aware
  token lifecycle.
- Research pass: incorporated Apple token/acceptance/expiration guidance,
  Firebase installation/freshness/backoff guidance, Redis at-most-once limits,
  and PostgreSQL queue-claim semantics.
- Gap pass 1: defined monotonic schedule-event keys and retention, closed the
  old/new materialization race, snapshotted the installation denominator,
  allowed only pending schedules during timezone relocation, and split token
  migration into generation-fenced compatibility phases.
- Gap pass 2: made provider environment server-normalized, separated bounded
  recipient/device concurrency, required the 10,000-recipient load test to meet
  the SLO, defined legacy APNs fallback convergence, and rechecked no-flag,
  two-worker, frozen-client, Redis-loss, expiry, and rollback behavior.
- Owner approval: approved implementation and the ten-active-installation cap;
  deployment and production mutations remain separately gated.
- Architect review 1 (`REVISE`): corrected universal lock acquisition, durable
  poison-row retry, exact early event semantics, consumer-first generation
  rollout, split reconcilers, ownership-safe delivery targets, transactional
  token invariants and HTTP compatibility, hot-path indexes, provider
  concurrency/contracts, provisioning headroom, and executable load gates.
- Architect review 2 (`REVISE`): added per-boot continuous census readiness and
  roll-forward quarantine boundary, lock-set closure, dormant late-join rearm,
  domain-only timezone authority with stable-candidate preservation,
  compatibility-index-safe token canonicalization, outbox expiry propagation,
  exact HTTP/provider-environment contracts, and cron/shutdown ownership.
- Architect review 3 (`REVISE`, one issue): removed the unnecessary new late-
  activation event type, reused the existing deterministic activation event,
  and made the existing parent/legacy scheduler an explicit shutdown owner.
- Architect confirmation: no required issues or suggestions remained; verdict
  `APPROVE`.
