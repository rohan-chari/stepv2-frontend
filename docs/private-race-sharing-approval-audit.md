# Private-Race Shared-Link and Join-Approval Audit

Status: read-only investigation. No implementation changes are implied by
this document.

Scope: Bara iOS private-race shared links, approval requests, creator
notifications, and related authentication, friendship, lifecycle, and
Universal Link behavior.

## 1. Executive Summary

The system has two private-race sharing paths:

1. Legacy share tokens stored directly on `Race.shareToken`, which use direct
   joining by possession of the token.
2. Approval-capable links stored in `RaceShareLink`, which create a separate
   `RaceJoinRequest` requiring creator approval.

The current approval-capable flow is:

```text
https://barastep.com/r/<opaque-token>
  -> DeepLinkService
  -> AuthService.pendingShareToken
  -> MainShell._drainPendingShare
  -> GET /races/share/:token
  -> POST /races/share/:token/join-requests
  -> RaceJoinRequest(status=PENDING)
  -> durable inbox notification
  -> creator Inbox
  -> POST /races/:raceId/join-requests/:requestId/respond
```

The strongest code-supported findings are:

- The frontend automatically drains the link from `MainShell`; it does not
  first navigate to a durable race page and wait for a separate user action.
- Preview failures are swallowed. If the preview cannot be fetched, the
  frontend treats approval as not required and may attempt the legacy automatic
  join path.
- The pending token is cleared in `finally`, including transient failures.
  This can make an intermittent failure look like a broken or one-time link.
- The backend creates the join request and creator inbox alert in the same
  transaction. A missing push should not itself remove the durable request.
- The approval relationship check is creator-to-requester. Accepted friendship
  is allowed; no friendship is allowed; a declined friendship or suppression
  row is blocked. Friendship with another participant is not a special grant.
- The creator request list is correctly filtered by race, `PENDING` status, and
  creator authorization, with bounded cursor pagination.
- Current source contains `privateJoinApproval`. The approval flow was added
  in frontend commit `7613181` on August 26, 2026. The repository cannot prove
  which exact `2.3.13` TestFlight build the reported user ran.

## 2. Current Architecture

### Frontend

| Path | Relevant symbols | Role |
|---|---|---|
| `lib/services/deep_link_service.dart` | `DeepLinkService`, `parseShareToken`, `handleLink`, `initialize` | Parses HTTPS and `bara://` links and persists pending tokens. |
| `lib/services/auth_service.dart` | pending share-token persistence | Preserves a link across authentication and onboarding. |
| `lib/main.dart` | startup initialization | Initializes notifications, auth, deep-link capture, and attribution. |
| `lib/screens/main_shell.dart` | `_drainPendingShare`, `_confirmPrivateJoinRequest`, `_showPrivateJoinPending` | Previews, requests approval, joins, and navigates. |
| `lib/services/backend_api_service.dart` | share/join-request methods | Single frontend HTTP surface. |
| `lib/screens/race_detail_screen.dart` | `_canShareRace`, `_shareRace` | Controls share eligibility and creates the link. |
| `lib/screens/inbox_screen.dart` | join-request handling | Displays creator alerts and accepts/declines requests. |
| `lib/services/notification_service.dart` | notification routing | Initializes and routes local/push notifications. |
| `lib/services/race_stream_coordinator.dart` | stream/polling | Refreshes race changes, but is not the primary approval-list mechanism. |

### Backend

| Path | Relevant symbols | Role |
|---|---|---|
| `src/app.js` | `/r/:token`, link-open logging | Web landing page and share-link telemetry. |
| `src/modules/races/routes.js` | shared preview, request, join routes | Registers the flow’s HTTP endpoints. |
| `src/modules/races/commands/createRaceShareLink.js` | `createRaceShareLink` | Mints approval-capable or legacy links. |
| `src/modules/races/models/raceShareLink.js` | `RaceShareLink`, `hashShareToken` | Hashes and resolves capable tokens. |
| `src/modules/races/queries/getSharedRacePreview.js` | `getSharedRacePreview` | Public display-safe preview. |
| `src/modules/races/commands/createRaceJoinRequest.js` | `createRaceJoinRequest` | Creates pending requests. |
| `src/modules/races/services/raceJoinRequests.js` | relationship policy and serialization | Friendship checks and request wire format. |
| `src/modules/races/queries/listRaceJoinRequests.js` | `listRaceJoinRequests` | Creator-only pending list. |
| `src/modules/races/commands/respondRaceJoinRequest.js` | `respondRaceJoinRequest` | Accept/decline flow. |
| `src/modules/races/commands/joinRaceByShareToken.js` | `joinRaceByShareToken` | Legacy direct-join path. |
| `src/modules/races/commands/joinRaceCore.js` | `joinRaceCore` | Shared participant creation and eligibility logic. |
| `src/modules/races/models/race.js` | `findByShareToken` | Legacy token lookup. |
| `src/modules/inbox/services/inbox.js` | `createInboxAlert` | Durable in-app alert creation. |
| `src/modules/notifications/*` | notification projection/delivery | Push and delivery infrastructure. |
| `prisma/schema.prisma` | race/link/request/notification models | Database schema. |

## 3. End-to-End Private Race Link Flow

### Link creation

`RaceDetailScreen._shareRace` requires the current user to be an accepted
participant and the race to be neither completed nor cancelled. It calls
`BackendApiService.createRaceShareLink`.

The backend `createRaceShareLink`:

- rejects tournament and seeded races;
- requires an accepted participant;
- checks the `privatejoinapproval` capability;
- for a capable private race, generates an opaque token;
- stores only its SHA-256 hash in `RaceShareLink.tokenHash`;
- records the race and sharer;
- sets a roughly 30-day expiry;
- returns the raw token and `approvalRequired: true`.

The frontend capability header contains `privateJoinApproval`; the backend
normalizes and checks `privatejoinapproval`.

### Link formats

The intended HTTPS URL is:

```text
https://barastep.com/r/<opaque-token>
```

The iOS entitlements also declare `steptracker-api.org` for compatibility.
The custom-scheme fallback is:

```text
bara://join/<opaque-token>
```

The parser also accepts `bara://race/<token>` and `bara:///r/<token>`.

### Link capture

`lib/main.dart` initializes the shared `AuthService`, then
`DeepLinkService.initialize` before `runApp`.

`DeepLinkService.initialize`:

- calls `AppLinks.getInitialLink()` for cold start;
- calls `handleLink` for the initial URI;
- subscribes to `uriLinkStream` for warm links.

`handleLink`:

- handles referral codes first;
- handles tournament links separately;
- accepts `/r/<token>` and supported `bara://` forms;
- rejects `BARA-` referral codes as race tokens;
- persists a valid race token with `AuthService.setPendingShareToken`;
- publishes it via `pendingToken`.

### MainShell drain

`MainShell._drainPendingShare`:

1. waits until onboarding is complete;
2. requires a nonempty auth token;
3. fetches the public shared-race preview;
4. shows `_confirmPrivateJoinRequest` when `_shareApprovalRequired` is true;
5. selects a team for team races;
6. calls the approval endpoint for capable private links;
7. otherwise calls the direct share-token join endpoint;
8. shows pending or navigates to the race;
9. clears the pending token in `finally` for every outcome.

## 4. End-to-End Approval Request Flow

The frontend calls:

```text
POST /races/share/:token/join-requests
Authorization: Bearer <identity token>
X-Client-Features: <features>
```

Body for an individual race:

```json
{"team": null}
```

Body for a team race:

```json
{"team": "TEAM_A"}
```

`createRaceJoinRequest` runs in a Prisma transaction and:

1. hashes and resolves the share token;
2. rejects unknown, revoked, or expired links;
3. locks the race row;
4. loads the race, participants, and creator;
5. checks creator/requester relationship policy;
6. requires race status `PENDING`;
7. rejects any existing participant row for the requester;
8. checks accepted capacity;
9. checks large-team compatibility;
10. validates team selection and team capacity;
11. returns an existing pending request idempotently;
12. enforces a 24-hour cooldown after decline;
13. inserts `RaceJoinRequest(status=PENDING)`;
14. creates the creator’s durable inbox alert;
15. commits;
16. publishes a best-effort inbox wakeup.

The response is HTTP 202 with the serialized request.

### Creator discovery

The creator list endpoint is:

```text
GET /races/:raceId/join-requests?status=PENDING&limit=20
```

`listRaceJoinRequests` requires:

- a real race;
- `race.creatorId === authenticated user ID`;
- `status=PENDING`;
- bounded limit 1–50;
- optional cursor ordered by `createdAt DESC, id DESC`.

### Approval

Inbox calls:

```text
POST /races/:raceId/join-requests/:requestId/respond
```

with `{"action":"ACCEPT"}` or `{"action":"DECLINE"}`.

Decline changes the request to `DECLINED` and creates a requester result alert.

Accept obtains the race join lock, reloads request/race state, rechecks
eligibility, invokes `joinRaceCore`, changes the request to `ACCEPTED`, creates
the requester result alert, and runs deferred post-commit work. Failed
acceptance changes the request to `EXPIRED` with a `failureCode`.

## 5. Failure Mode A: Approval Missing

### Request never reaches the backend

The preview request is wrapped in `catch (_) {}`. A failed preview leaves
`preview == null`, so `_shareApprovalRequired` is false and the frontend may
call the automatic join endpoint instead of the approval endpoint.

The pending token is cleared unconditionally in `finally`, including network,
auth, parsing, and generic failures. The user must retap the original link.

The request can also be skipped when:

- onboarding is still active;
- authentication has not restored an identity token;
- the approval dialog is dismissed;
- a team picker is dismissed;
- the widget is unmounted.

The frontend does not record a request-attempt ID distinguishing these cases.

### Backend rejection paths

| Condition | HTTP | Code |
|---|---:|---|
| Unknown token | 404 | `RACE_NOT_FOUND` |
| Revoked/expired link | 410 | `SHARE_LINK_EXPIRED` |
| Missing race | 404 | `RACE_NOT_FOUND` |
| Declined/suppressed creator relationship | 409 | `BLOCKED_RELATIONSHIP` |
| Race not `PENDING` | 400 | `RACE_NOT_JOINABLE` |
| Existing participant row | 409 | `ALREADY_PARTICIPATING` |
| Race full | 409 | `RACE_FULL` |
| Unsupported large-team race | 400 | update-required compatibility error |
| Invalid/missing team | 400 | `INVALID_TEAM` |
| Full team | 400 | `INVALID_TEAM` |
| Team supplied to individual race | 400 | `INVALID_TEAM` |
| Declined request within 24 hours | 409 | `JOIN_REQUEST_COOLDOWN` |

### Request exists but is hidden

The backend request list itself is correctly scoped to `raceId` and
`status=PENDING`, and authorization is checked against the race creator. The
main hiding possibilities are a non-pending terminal state, stale UI, a
different race, pagination, or transaction rollback.

No frontend filter was found that removes valid pending requests based on
requester, friendship, or invitation type.

### Notification versus approval state

The request row and creator inbox alert are created in the same transaction.
The post-commit inbox wakeup is best-effort. Push delivery is downstream.

Therefore:

- a missing push does not prove a missing request;
- a durable request should remain visible after Inbox refresh;
- if alert creation fails inside the transaction, request creation should roll
  back as well;
- a wakeup or APNs failure can delay visibility without deleting state.

### Stale creator state

Inbox has initial loading, refresh, wakeup/polling, and resume-related refresh
paths. The race-detail screen is not shown to have a dedicated live join-request
poll. A creator remaining on the race screen may not see a new request until
Inbox or the request list is refreshed.

## 6. Failure Mode B: Link Fails

The parser silently ignores:

- paths other than `/r/<token>`;
- unsupported custom-scheme forms;
- tokens outside `[A-Za-z0-9_-]{1,128}`;
- referral-style `BARA-` tokens.

If iOS does not recognize the Universal Link, Safari may open instead of Bara.
The repository declares associated domains but cannot prove deployed AASA
correctness.

The landing page’s custom-scheme fallback depends on the user reaching the web
page and tapping its Open in App action.

Cold-start capture occurs before `runApp` and is persisted, which is intended
to survive auth/onboarding. The final drain still depends on auth restoration,
onboarding completion, MainShell mounting, and the auth-transition path
triggering a drain.

Warm links are handled fire-and-forget. A link can arrive while a dialog or
onboarding gate is active, and a later link can overwrite the pending token.

Most importantly, a preview failure is converted into a legacy-join attempt and
then the token is consumed. This is the clearest code-supported explanation for
an intermittent “link does not work” report.

## 7. iOS / Deep Link Lifecycle

Repository-verifiable configuration:

- `ios/Runner/Runner.entitlements` declares:
  - `applinks:barastep.com`
  - `applinks:steptracker-api.org`
- `ios/Runner/Info.plist` declares the `bara` scheme.
- `lib/services/deep_link_service.dart` uses `app_links`.
- `lib/main.dart` captures the cold-start URI before `runApp`.

Not verifiable from this repository:

- deployed AASA contents;
- Apple team/app identifier correctness;
- redirects, TLS, CDN caching, and content type;
- embedded entitlements in the affected archive;
- App Store/TestFlight behavior for the exact reported build.

The shared entitlements file also contains `aps-environment=development`, with
comments indicating production provisioning still required verification.

## 8. Authentication and Authorization

`GET /races/share/:token` is public and returns display-safe metadata. This is
the intended way for a nonparticipant to reach the pre-join flow.

The ordinary authenticated race-details endpoint remains participant-scoped;
the shared preview avoids requiring race membership before requesting access.

The request endpoint requires authentication and applies the creator/requester
relationship check described above.

Legacy direct joining uses possession of the share token as the invite. Capable
private links use approval requests instead.

## 9. Friend System Interaction

There is no separate friends-of-friends permission tier in the shared-link
flow.

The actual creator/requester rules are:

```text
accepted friendship       -> allowed
no friendship             -> allowed
declined friendship       -> blocked
suppression row            -> blocked
friendship with participant -> no special grant
```

Direct invitations are participant rows with `status=INVITED`; shared-link
requests are `RaceJoinRequest` rows.

## 10. Database State Machine

### `Race`

Relevant fields include `id`, `creatorId`, `status`, `isPublic`,
`maxParticipants`, `isTeamRace`, `teamSize`, nullable legacy `shareToken`,
`tournamentId`, and start/end timestamps.

### `RaceParticipant`

Relevant fields include race/user relationships, `status` values such as
`INVITED`, `ACCEPTED`, and `DECLINED`, optional team, and participation
timestamps. Any participant row for the requester blocks a new shared-link
request.

### `RaceShareLink`

Fields:

- `id` primary key;
- unique `tokenHash`;
- `raceId`;
- `sharedByUserId` and display-name snapshot;
- `createdAt`, `revokedAt`, `expiresAt`.

### `RaceJoinRequest`

Fields:

- `id` primary key;
- `raceId`, `shareLinkId`;
- sharer and requester IDs/display snapshots;
- `creatorUserId`;
- optional `team`;
- `status`, default `PENDING`;
- `createdAt`, `updatedAt`, `respondedAt`;
- `terminalActorUserId`;
- `failureCode`.

Indexes are:

```text
(raceId, status, createdAt DESC, id DESC)
(raceId, requesterUserId, createdAt DESC)
```

State transitions:

```text
PENDING -> ACCEPTED
PENDING -> DECLINED
PENDING -> EXPIRED
```

### Idempotency and duplicates

- Repeated request while one is pending returns the existing pending row.
- A declined request has a 24-hour cooldown.
- Existing participant/invite rows block a new request.
- Acceptance and race joining use a race join lock.
- A request already responded to is returned without repeating the action.

## 11. Notifications

Approval notification creation occurs transactionally with request creation:

```text
RaceJoinRequest insert
  + inbox alert insert
  -> transaction commit
  -> best-effort inbox wakeup
  -> push/in-app delivery processing
```

The creator alert has type `PRIVATE_RACE_JOIN_APPROVAL` and a destination
containing route `raceJoinRequest`, `raceId`, and `requestId`.

The requester receives `PRIVATE_RACE_JOIN_RESULT` after acceptance or decline.

The repository does not provide incident-level proof of APNs delivery. The
durable database request and notification must be checked separately from push
provider receipts.

## 12. Version 2.3.13 Differences

Current frontend HEAD is `83e79cd`. Current source advertises
`privateJoinApproval`.

The approval frontend flow was added in commit `7613181`, dated August 26,
2026. The repository contains multiple TestFlight tags using marketing version
`2.3.13`, so the marketing version cannot identify the binary.

The exact affected build cannot be identified from repository evidence alone.
Older clients without the capability are expected to remain on the legacy
share-token path, but compatibility must be verified against the exact build
and link-generation path.

## 13. Existing Tests

Relevant tests include:

- `test/deep_link_service_test.dart` — race/referral URI parsing and pending
  token behavior;
- `test/main_shell_team_share_link_test.dart` — team share-link behavior;
- `test/inbox_read_all_frontend_test.dart` — Inbox read/render behavior;
- `test/race_detail_screen_test.dart` — race-detail/share behavior;
- backend integration tests under `test/integration/` — race joining,
  invitations, lifecycle, and notification behavior;
- backend race-sharing/reliability tests associated with commit `219b38e`.

Important gaps remain around preview failure, token retention, logged-out cold
start, push-independent durable state, friendship suppression, duplicate taps,
full/start races, and exact `2.3.13` compatibility.

## 14. Reproduction Matrix

| App state | Auth | Relationship | Direct invite | Race state | Expected |
|---|---|---|---|---|---|
| Foreground | Logged in | Creator friend | No | Pending/not full | Preview, approval dialog, request, creator pending item. |
| Foreground | Logged in | Unrelated | No | Pending/not full | Same unless prior creator decline/suppression exists. |
| Foreground | Logged in | Participant friend only | No | Pending/not full | Same; participant friendship has no special effect. |
| Background | Logged in | Allowed | No | Pending/not full | Warm link capture and request flow. |
| Terminated | Logged in | Allowed | No | Pending/not full | Cold capture, persisted token, request flow. |
| Terminated | Logged out | Allowed | No | Pending/not full | Token survives login/onboarding, then request flow. |
| First launch | Logged out | Allowed | No | Pending/not full | Token survives onboarding, then request flow. |
| Any | Logged in | Declined/suppressed creator relationship | No | Pending/not full | `409 BLOCKED_RELATIONSHIP`; no request row. |
| Any | Logged in | Any | Yes | Pending/not full | Direct invitation acceptance path. |
| Any | Logged in | Any | No | Active | `400 RACE_NOT_JOINABLE`. |
| Any | Logged in | Any | No | Full | `409 RACE_FULL`. |
| Any | Logged in | Any | No | Expired | `410 SHARE_LINK_EXPIRED`. |
| Any | Logged in | Any | No | Team pending | Team selection followed by request. |
| Any | Logged in | Any | No | Preview network failure | Current code may attempt legacy join and consume token. |
| Any | Logged in | Any | No | Push disabled | Durable Inbox state should remain available. |

For every reproduction capture the URL, build number, preview status, join
request status, response code, database rows, notification row, push attempt,
and creator Inbox response.

## 15. Suspected Root Causes

### 1. Preview failures select the wrong path

Confidence: high.

`MainShell._drainPendingShare` ignores preview exceptions and defaults approval
to false. This explains both a missing approval request and a link that appears
not to work.

Confirm with a controlled preview timeout/500 and verify that
`POST /join-requests` is absent while the legacy join endpoint is attempted.

### 2. Transient failures consume the pending token

Confidence: high.

The token is cleared in `finally`, including transient errors. This explains
intermittent Failure B and requires the original link to be retapped.

Confirm by interrupting network access during preview or request and checking
whether the stored token is gone.

### 3. The reported build may predate approval support

Confidence: medium.

The approval flow was introduced in `7613181`, while the user supplied only the
marketing version `2.3.13`, which was reused for multiple builds.

Confirm using the exact App Store/TestFlight build number and archive contents.

### 4. Push delivery may be missing while durable state exists

Confidence: medium.

Request and alert persistence are distinct from wakeup and APNs delivery. This
explains a missing notification but not a missing manually refreshed request.

Confirm by comparing `RaceJoinRequest`, `Notification`, and push-provider rows.

### 5. Relationship suppression blocks the requester

Confidence: medium.

Declined friendship or suppression rows cause `BLOCKED_RELATIONSHIP` even when
the link was shared by a participant.

Confirm by inspecting the creator/requester friendship records and response
code.

### 6. Universal Link/AASA configuration is wrong

Confidence: medium.

The repository declares associated domains but cannot prove production AASA
deployment or the affected archive’s embedded entitlements.

Confirm on a clean device and by fetching both production AASA files.

### 7. Auth/onboarding drain race

Confidence: low to medium.

Persistence is intended to bridge auth/onboarding, but exact auth-transition
coverage is not proven by static inspection.

Confirm with a cold link followed by login and onboarding while observing the
pending-token lifecycle.

## 16. Recommended Fix Plan

No code was implemented as part of this audit.

The smallest safe direction for the strongest candidates is:

- distinguish preview success from preview failure;
- do not fall back to automatic joining after an unknown preview failure;
- preserve pending tokens across transient failures;
- clear them only after success or explicit dismissal/permanent invalidity;
- add integration coverage for cold start, login, onboarding, preview failure,
  durable notification creation, and push-independent state;
- verify the exact shipped build and production AASA/APNs configuration before
  changing behavior.

## 17. Files That Would Need Modification

Potential frontend files:

- `lib/screens/main_shell.dart` — preview failure handling and token lifecycle;
- `lib/services/deep_link_service.dart` — only if parser/lifecycle changes are
  needed;
- `lib/services/auth_service.dart` — only if auth-transition persistence needs
  adjustment;
- `lib/services/backend_api_service.dart` — only if response contracts change;
- `lib/screens/inbox_screen.dart` — only if refresh/display behavior changes;
- `lib/services/notification_service.dart` — only if push routing changes;
- `ios/Runner/Runner.entitlements` — only after provisioning verification.

Potential backend files:

- `src/modules/races/commands/createRaceJoinRequest.js`;
- `src/modules/races/queries/listRaceJoinRequests.js`;
- `src/modules/races/commands/respondRaceJoinRequest.js`;
- `src/modules/races/services/raceJoinRequests.js`;
- `src/modules/races/queries/getSharedRacePreview.js`;
- `src/modules/races/routes.js`;
- inbox and notification services under `src/modules/inbox` and
  `src/modules/notifications`.

No schema migration is currently indicated by the audit.

## 18. Open Questions

1. What exact iOS build number was the affected user running?
2. Did that build include commit `7613181` or an equivalent implementation?
3. What exact URL was shared, and which build generated it?
4. Did iOS receive it as a Universal Link, Safari URL, or `bara://` link?
5. Are production AASA files correct for both declared domains?
6. What statuses and response codes did the preview and join-request calls
   return?
7. Was the join-request endpoint called at all?
8. Did the requester have a declined friendship or suppression row with the
   creator?
9. What was the race status, capacity, and race type at request time?
10. Did a `RaceJoinRequest` row exist, and what terminal/pending state did it
    have?
11. Did the corresponding creator `Notification` row exist?
12. Was an APNs attempt recorded, and was it accepted or rejected?
13. Was the creator in Inbox or only on the race-detail screen?
14. Did the cold logged-out path preserve the token through auth/onboarding?
15. Did the failure coincide with a timeout, 5xx, auth restoration failure, or
    app termination?
16. Do production logs correlate token, race, requester, request ID,
    notification creation, and push delivery without exposing sensitive data?
17. Was the link generated before or after approval-capability rollout?
18. Are older clients still distributing legacy private-race links?
19. Was the requester directly invited, already an invitee/participant, or a
    nonparticipant using a shared link?
