# Inbox read-all requirements

## Summary & user story

When a user opens the Notifications page, they expect the Home badge to stay
cleared after leaving the page or restarting the app. As a user, I want one
open action to mark the inbox notifications I just reviewed as read, without
the client issuing one network mutation per row or missing notifications on a
later page.

## Scope / non-goals

In scope:

- Add an additive authenticated backend endpoint that marks the current user's
  unread inbox alerts and unread support threads read in one transaction.
- Return authoritative combined unread counts and mutation counts.
- Replace the Flutter page's paginated per-alert clear loop with one endpoint
  call when the Home-launched standalone Notifications page opens.
- Keep the existing per-alert and per-thread read endpoints for older clients
  and item-level interactions.
- Make Inbox cards more compact without changing their content or routing.

Out of scope:

- Removing or changing existing notification types, destinations, retention,
  push delivery, or notification preferences.
- Adding a release flag or migration.
- Clearing notifications merely by visiting embedded/tutorial Inbox surfaces;
  only the existing Home-launched standalone route opts into clear-on-open.

## API contract

### `POST /inbox/read-all`

Authenticated endpoint. It requires the same `inbox_v1` client feature and
server setting checks as `/inbox/alerts`. Request body is `{}` (an absent body
is also accepted by the existing JSON middleware).

Success response `200`:

```json
{
  "readAlertCount": 7,
  "readThreadCount": 0,
  "unreadCount": 0,
  "totalUnreadCount": 0
}
```

`unreadCount` remains the alert-only count for compatibility with clients that
already understand that field. `totalUnreadCount` is the combined alert plus
support-thread count. All fields are non-negative integers. The endpoint is
idempotent: a second call returns zero mutation counts and the same current
unread totals.

The frontend read-all parser accepts `totalUnreadCount` only when it is a
non-negative integer. A missing, non-object, negative, fractional, or otherwise
malformed `totalUnreadCount` is a recoverable failure and must not clear the
local badge; `unreadCount` must never substitute for the missing combined count
on this endpoint. Malformed JSON/body returns `400 INVALID_BODY`; object bodies
with unknown fields are ignored for forward compatibility, and an omitted body
is accepted.

Errors match the existing Inbox route: `404 FEATURE_DISABLED` when Inbox is
unavailable, `401` for missing/invalid auth, and `500 INTERNAL_ERROR` for an
unexpected failure. No existing endpoint or response is removed or changed.

## Data model / migrations

Additive indexes are included for the bulk predicates: 
`(userId, readAt, expiresAt)` on alerts and `(userId, userReadAt, expiresAt)` on
threads. They require no data backfill and are invisible to old clients/code.
In one Prisma transaction, use one shared `now`, update unread `InboxAlert` rows
for the authenticated user (`readAt = now`) and unread `FeedbackThread` rows
(`userReadAt = now`) with `updateMany`, and calculate both counts inside the
same transaction. Return the `updateMany.count` values. Invalidate the
existing per-user unread cache after commit; invalidation failure must not undo
or turn a committed read-all into a 500 response.

## Frontend plan

- Add `BackendApiService.markInboxReadAll`, defensively parse missing or
  malformed response counts, and tolerate older backends returning `404` or
  transport errors.
- On the standalone Home-launched Inbox screen, call the endpoint exactly once
  per screen instance after the initial Inbox load. Use a mutation-generation
  barrier so an older alerts refresh cannot overwrite the authoritative result.
  Update both alert `readAt` and support `unread`/`unreadByUser` locally. Keep
  the prior badge on failure; only a valid combined count can update it. The
  destination-routing call site and Home call site must share one explicit
  clear-on-open policy; embedded/tutorial Inbox remains non-clearing.
- Do not make Home depend on any new field; it continues to render the existing
  unread count and an empty-state label.
- Compact Inbox cards by reducing vertical padding and gaps while preserving
  readable category/title/body/action text and tap targets.
- The Dart path is shared by iOS and Android; no platform-specific changes are
  required.

## Backward compatibility & rollout

- Deploy backend first. Old binaries never call the new endpoint and continue
  using existing per-alert/per-thread endpoints unchanged.
- The new app treats `404`, missing fields, and malformed responses as a
  recoverable clear failure; it never crashes or falsely clears a badge.
- No feature flag, migration, or test-only behavior is needed.

## Test plan

Tests are written before implementation:

Backend integration:

- authenticated read-all marks all unread alert and support rows and returns
  zero combined counts;
- repeat read-all is idempotent;
- one user's call cannot mutate another user's rows;
- expired rows are excluded;
- transaction rollback leaves both tables unchanged if either update fails;
- concurrent read-all calls are idempotent;
- foreign-user rows cannot be changed;
- auth, feature-disabled, malformed body, and exact legacy response-key cases;
- Redis local-db/cache-disabled, Redis-down, and unset-URL invalidation paths;
- old `/inbox/alerts` and individual read routes remain compatible.

Frontend widget/integration:

- standalone Inbox invokes read-all once on open and updates the Home callback
  from the authoritative response;
- read-all failure leaves the existing badge/read semantics intact;
- missing/malformed optional response counts fail safely;
- compact cards retain the visible fields and tap behavior.
- a new app receiving a definite old-backend `404` does not enter a per-row
  mutation fallback loop; transient failures remain retryable.

## Acceptance criteria / definition of done

- The endpoint is additive, transactional, idempotent, cache-invalidating, and
  covered by real HTTP integration tests against the dedicated test database.
- Flutter uses the endpoint for clear-on-open and no longer paginates or loops
  per-alert for that action.
- Existing suites remain green; `flutter analyze` and backend unit/integration
  commands are clean.
- Both iOS and Android use the same verified Dart path.
- Architect/code review is complete and the manual UI checklist is handed off.

## Revision log

- Initial draft: identified that the current client-side pagination loop can
  miss rows and can leave the persisted Home count stale; designed a single
  backend transaction and authoritative response.
- Gap pass 1: included support-thread unread state because the Home badge is a
  combined count; preserved old alert-only response semantics.
- Gap pass 2: added idempotency, expiry, user isolation, disabled-feature,
  malformed-response, and old-client compatibility requirements.
- Architect review: made combined-count parsing strict, specified transaction
  and cache semantics, added DI/module boundaries, index assessment, rollback/
  concurrency/Redis/error coverage, and required one clear-on-open call per
  standalone screen instance.

## Manual UI-placement test plan

### Manual UI-placement test plan

1. Home Notifications card: with unread alerts/support, verify the combined
   badge, tap target, and navigation to standalone Notifications; with zero,
   verify the persistent empty-state card.
2. Standalone Notifications: verify compact alert and support cards retain
   category, NEW state, title, body, OPEN/REPLY action, chronological order,
   and a practical 48dp+ tap target; verify no clipping with long copy and
   LOAD MORE.
3. Read-all success/failure: verify successful open updates Home to zero and
   remains zero after back, cold restart, and repeat open; verify 404/5xx/
   timeout preserves the prior badge and per-item read behavior.
4. Embedded Inbox and all three navigation-test fixtures: verify they do not
   clear on open, preserve their existing header/insets/order, and retain
   per-item read behavior.
5. Tutorial Home, Races, Friends, Profile, and race-detail previews: verify
   no new Inbox route, card, badge, or spotlight shift is introduced.
6. Demo race tutorial: verify no live Inbox or read-all behavior appears in
   demo beats, prologue, detail, or result surfaces.
7. iOS: verify safe-area placement, header back/swipe back, background/return,
   cold restart, success, and failure behavior.
8. Android: verify system back/gesture, safe-area/system-bar placement,
   background/return, cold restart, success, and failure behavior.
