# Inbox feedback usernames requirements

## Summary & user story

As an administrator triaging the in-app Inbox, I want each feedback/support
thread to show the submitting user's current discoverable username, so I can
identify and respond to the right person instead of seeing an anonymous entry.

## Scope / non-goals

In scope:

- Add the submitter's current `displayName` to the existing admin feedback-thread list
  response.
- Keep the existing Flutter Inbox byline, which already renders the name and
  safely falls back to `Anonymous` when the field is absent, null, or blank.
- Cover the response contract and the real admin Inbox rendering path.

Out of scope:

- Changing feedback submission, thread ownership, privacy, or retention.
- Exposing email, user ID, profile photo, or staff identity.
- Adding a new endpoint, migration, feature flag, or release gate.

## Existing implementation points

- Backend route: `/Users/rohan/repos/stepv2-backend/src/modules/admin/routes.js`,
  `GET /feedback/threads`.
- Backend data: `FeedbackThread.userId` relates to `User.displayName`; no schema
  migration is required.
- Frontend API: `lib/services/backend_api_service.dart` already reads the raw
  thread envelope defensively.
- Frontend Inbox: `lib/screens/admin_sections.dart` already formats
  `displayName` and falls back to `Anonymous`.

## API contract

Extend each object in the existing `GET /admin/feedback/threads` `threads`
array additively:

```json
{
  "id": "thread-uuid",
  "suggestionId": "suggestion-uuid",
  "displayName": "Walker",
  "preview": "Feedback text",
  "lastMessageAt": "2026-08-23T12:00:00.000Z",
  "userUnread": true
}
```

`displayName` is `string|null`. The backend reads the current value directly
from the Postgres `User` relation on this existing admin list query; it is not
cached in Redis and no identity snapshot is stored on the thread. The backend
must select only `{ displayName: true }` from the relation. If an older backend
omits it, the current frontend remains safe and displays `Anonymous`. No
existing field is removed or repurposed, and no new request parameter is
required. The endpoint remains admin-gated and retains its existing
`inbox_v1`/`apiInboxV1Enabled` gate, cursor/limit errors, and 500 behavior.

The thread-detail endpoint remains unchanged and continues to expose only
thread/message content; this change does not expand its PII surface.

## Frontend plan

No functional Flutter code change is expected: the existing `_byline` path
uses a non-empty string `displayName` and defensively falls back to
`Anonymous`. Verify Android and iOS use the same Dart path. Preserve the
loading, error, empty, and legacy-response behavior.

## Backward compatibility & rollout

This is an additive backend response field. Old app binaries ignore it, and
the current app works against an old backend because its fallback remains.
Deploy the backend first, then the app only if a new app build is otherwise
needed. No feature flag or test-only gate is needed because the carrying app
already knows how to render the field.

## Test plan (tests first)

1. Backend integration test over real HTTP: create a thread, rename its user,
   and assert the admin list returns the new current `displayName`; separately
   assert a null-name user returns `null`. Assert the response does not expose
   email or unrelated profile data. Confirm the dedicated test database before
   running; never use production.
2. Frontend widget integration test: override the actual
   `fetchAdminFeedbackThreads` path and prove present, null, blank, and missing
   names render correctly, alongside existing loading/error/empty behavior.
3. Run `npm run test:unit`, the targeted backend integration test,
   `flutter analyze`, and the relevant Flutter tests.

## Acceptance criteria / definition of done

- Admin Inbox support-thread rows show the feedback submitter's username.
- Missing/null names continue to render safely as `Anonymous`.
- Existing authorization and privacy boundaries are unchanged.
- Tests are written before implementation and pass.
- Backend unit/integration checks and frontend analysis/relevant tests pass.
- Code review confirms the additive compatibility contract and production
  deploy order.

## Revision log

- Pass 1: identified that the frontend renderer already supports
  `displayName`; narrowed the implementation to the backend thread-list
  projection and defensive tests.
- Pass 2: confirmed no migration or new endpoint is needed, preserved the
  legacy fallback, and kept thread detail free of profile data.
- Architect review: required selecting only the related user's current
  `displayName`, preserving the existing capability/setting gate, testing
  rename freshness and null names over real HTTP, and routing the read through
  the feedback query seam; incorporated above.
- Manual UI-placement test plan: both Admin Tools dashboard layouts, present
  and legacy fallback rows, and thread-detail non-expansion; no tutorial or
  regular-user Inbox mirror exists.
