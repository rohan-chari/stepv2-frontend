# Feedback email handoff requirements

Status: approved by owner; Stage A implemented, external preflight and deployment pending

## Summary and user story

Replace Bara's database-backed feedback/support conversation feature with email
to `support@barastep.com`.

As a Bara user, I want **SEND FEEDBACK** on Home to submit through Bara's
existing in-app sheet and arrive in Bara Support's email, with an optional
reply address so support can answer me outside the app. As an operator, I want
new feedback to arrive in the support mailbox rather than the app's admin
Inbox, while existing support conversations expire naturally and later cleanup
removes retired APIs, UI, jobs, projections, and database objects without
breaking released app versions.

## Current implementation and implications

This is currently one feature spread across several systems, not one Home
button:

- Home keeps its Feedback card last in the Home feed and opens the shared
  in-app sheet from `lib/screens/tabs/home_tab.dart` (currently lines 624-667).
- `lib/widgets/feedback_sheet.dart` owns the 2,000-character form, auth-token
  requirement, loading/retry states, and `POST /feedback/suggestions` call
  (currently lines 16-199).
- `BackendApiService` exposes submission, user-thread, and admin-thread methods
  in `lib/services/backend_api_service.dart` (currently lines 1671-1697 and
  2470-2564).
- The real Home screen is also rendered in the tutorial. Its fake backend
  overrides `submitSuggestion` specifically to prevent a real write from the
  tutorial (`lib/tutorial/tutorial_preview_data.dart`).
- The user Inbox merges ordinary alerts with support threads and includes a
  support-thread detail/reply screen (`lib/screens/inbox_screen.dart`). Its
  unread badge is therefore not currently an alerts-only count.
- The admin app renders the support-thread list/detail/reply UI through
  `AdminInboxBody` in `lib/screens/admin_sections.dart`, used in both admin
  layouts in `lib/screens/admin_screen.dart`.
- The backend `POST /feedback/suggestions` creates a `Suggestion`,
  `FeedbackThread`, and initial `FeedbackMessage` in one transaction
  (`src/modules/feedback/commands/createSuggestion.js`, currently lines
  68-125). User and admin thread routes then read/write those records.
- Prisma stores free-form feedback in `Suggestion`, `FeedbackThread`, and
  `FeedbackMessage` (`prisma/schema.prisma`, currently lines 246-265 and
  643-679). Threads/messages expire after 30 days, but the parent `Suggestion`
  remains until account deletion.
- Support threads contribute to Inbox unread totals
  (`src/modules/inbox/queries/getInboxUnreadCounts.js`), are handled by the
  Inbox expiry job, and are explicitly deleted by account deletion.
- Staff replies produce `SUPPORT_REPLY_CREATED_V1` domain events and visible
  notifications. Retiring threads therefore also retires that producer,
  projection branch, delivery/audit mapping, and their tests.

## Locked product and provider decisions

- Keep the existing branded in-app feedback sheet; do not depend on a device
  mail client.
- Add optional **EMAIL FOR A REPLY**. Select Reply-To from a valid entered
  address, then a valid stored account email, otherwise omit it and put
  `NO REPLY ADDRESS — DO NOT REPLY` at the top of the message body.
- Send through Google Workspace's SMTP relay. Occasional duplicate mail after
  an ambiguous network timeout is explicitly acceptable; no client or provider
  idempotency mechanism is required.
- Envelope: From `Bara Support <support@barastep.com>`, To
  `support@barastep.com`, Subject `USER FEEDBACK • <8 uppercase hex
  characters>` derived from the random Message-ID so unrelated submissions do
  not become one Gmail conversation, user address only in Reply-To.
- `feedback-bounces@barastep.com` is an intentionally unprovisioned envelope
  sender, not a Workspace user, alias, or Group; delivery-status notices are
  discarded. Support mail follows the existing mailbox's normal retention and
  may remain until manually deleted. No secondary provider archive, delivery
  webhook, or open/click tracking. Account deletion cannot recall an
  already-sent email; the product/privacy copy must say so.
- Existing database-backed conversations remain available until the expiry job
  has removed the final active thread. Replies currently extend expiry by 30
  days, so this is a data-driven drain, not a guaranteed calendar deadline.

## Scope

### Release A frontend

- Keep the Home card, placement, headline, button key, sheet, 2,000-character
  limit, and retry-safe draft.
- Add one optional reply-email field between message and SUBMIT. Make the sheet
  scrollable with the keyboard open on compact iOS and Android devices.
- Add concise disclosure copy: **Your feedback is emailed to Bara Support.**
- Add an `X-Platform` header of `ios` or `android` to the standard Flutter
  request helper.
- Preserve the existing user/admin support-thread UI throughout the drain.
- Update the tutorial fake service signature; tutorial interaction must never
  send real feedback.

### Release A backend

- Send new submissions through Google Workspace SMTP relay without storing
  message content in Bara's feedback tables.
- Add content-free durable attempt/quota metadata for an atomic five-per-day
  limit across both production workers.
- Preserve all existing support-thread reads, writes, unread counts, expiry,
  staff-reply events, and admin UI contracts for retained conversations.
- Update the privacy page and operational documentation before launch.

### Post-drain cleanup

- Only after a SELECT-only check reports zero active threads: install DB-free
  compatibility handlers, remove support from user/admin UI and Inbox unread
  counts, then drop legacy tables in a later deploy.
- Preserve the Settings SUPPORT web link; it is a different path.

### Non-goals

- No feature/release flag, runtime delivery toggle, attachment upload, CRM,
  support SLA, inbound-mail parsing, or delivery webhook in this release.
- No production deploy, DNS mutation, provider-account mutation, or production
  database write without separate in-the-moment approval.
- No special behavior branch for old app versions.

## Provider, authentication, and loop-safety contract

- Use Google Workspace SMTP relay at `smtp-relay.gmail.com` with STARTTLS on
  port 587 through an injected Nodemailer transport. Configure Workspace to
  allow only the production server's explicit static IP, require TLS, and
  restrict senders to Bara's domain/registered address. No Gmail username,
  password, OAuth token, or app password is committed or required by the app.
- SMTP host/port are fixed infrastructure constants, not feature controls.
  Missing/invalid transport configuration or connection failure returns
  `503 EMAIL_DELIVERY_UNAVAILABLE`; the server still starts so unrelated app
  functions remain available.
- Because live DMARC is `p=reject; sp=reject; adkim=s; aspf=s`, a pre-release
  delivered-header test must show Google DKIM `d=barastep.com` and DMARC pass
  for From `support@barastep.com`.
- Use the controlled, unprovisioned `feedback-bounces@barastep.com` address as
  Nodemailer's `envelope.from` while visible header From remains
  `support@barastep.com`. Delivery-status notices are intentionally discarded;
  verify no catch-all/routing rule sends them into support and preflight
  Google's actual Return-Path rewrite from a delivered message.
- Nodemailer uses `secure:false`, `requireTLS:true`, bounded connection,
  greeting, and socket timeouts, and one exact envelope recipient. Acceptance
  requires `info.accepted` to contain only `support@barastep.com` and no
  rejection.
- Disable vacation/automatic replies on the support mailbox, verify no
  forwarding rule routes support mail back to itself, and test discarded bounce,
  forwarding, user Reply-To, and absent Reply-To cases before prod.
- Register Bara's sending domain/address for Apple private-email relay before
  relying on replies to Apple relay addresses.
- SMTP acceptance means the relay accepted `support@barastep.com` after DATA;
  it does not guarantee final mailbox delivery. Store only the generated
  Message-ID and attempt state, never message content.

## API contract and frozen clients

### `POST /feedback/suggestions`

Authentication and existing `text`/`category` bounds remain. Request fields are
additive:

```json
{
  "text": "Feedback text",
  "category": null,
  "replyToEmail": "person@example.com"
}
```

- `text`: required trimmed string, 1–2,000 characters.
- `category`: optional null/blank or trimmed string up to 64 characters;
  preserve it as a plain-text label in the email.
- `replyToEmail`: optional null/blank or one mailbox up to 254 characters.
  Reject CR/LF, controls, display-name syntax, comma/semicolon lists, and any
  value the provider's mailbox parser rejects. Apply the same parser to a
  stored fallback email, but omit an invalid stored fallback rather than
  blocking feedback the user did not enter. Entered/stored addresses are
  unverified routing hints, never identity evidence.
- `X-App-Version`: existing bounded provenance. `X-Platform`: new bounded
  `ios`/`android` provenance; missing/unknown stores/sends no platform value and
  never rejects feedback.

Every successful request represents a new SMTP send:

```json
HTTP 201
{ "ok": true, "delivery": "email" }
```

A frozen backend ignores new request fields and returns historical
`201 {"ok":true}` after database acceptance. A new client treats missing or
unknown `delivery` as generic **Feedback received** and must not claim email
delivery. With `delivery:"email"`, it may say **Sent to Bara Support**.

Errors use `{ "error": "safe message", "code": "CODE" }`:

- `400 INVALID_TEXT`, `INVALID_CATEGORY`, or `INVALID_REPLY_TO_EMAIL`.
- `429 DAILY_LIMIT_REACHED` after five reserved/accepted submissions per user
  per UTC day.
- `503 EMAIL_DELIVERY_UNAVAILABLE` for missing config or definitive provider
  rejection; a reserved quota slot is released on definitive failure.
- `503 EMAIL_DELIVERY_UNCERTAIN` for timeout/connection loss after dispatch may
  have reached Google; keep the slot reserved. Retrying may create a duplicate
  and the app says so plainly.
- `500 INTERNAL_ERROR` only for failures before known SMTP acceptance. Once
  Google returns final acceptance, bounded ACCEPTED-state finalize retries run;
  if they still fail, log the metadata failure and return the successful `201`
  so the client is not encouraged to duplicate a known-accepted email.

Do not expose SMTP details, Message-IDs, stored account email, or internal errors
to the client.

### Legacy thread compatibility after drain

- `GET /feedback/threads` -> `200 {"threads":[],"nextCursor":null}`.
- authorized `GET /admin/feedback/threads` -> the same empty envelope.
- authorized `GET /admin/feedback/suggestions` ->
  `200 {"suggestions":[],"nextBefore":null}`.
- drained detail and user/admin message routes -> historical `404 NOT_FOUND`.

These permanent handlers do no legacy-table access. They land before table
drops so frozen clients never receive route-level 404s or malformed envelopes.

## Data model and atomic delivery state

Add `FeedbackEmailAttempt` (mapped to `feedback_email_attempts`):

- `id` UUID primary key; `userId` FK to User with cascade delete.
- `utcDay` and state `RESERVED|ACCEPTED|FAILED`.
- non-null generated `messageId`, nullable `lastErrorCode`; `createdAt`,
  `updatedAt`, and
  `expiresAt`.
- indexes `(userId,utcDay,state)` and `(expiresAt)`.

Never store feedback text, category, display name, or reply address in this
table. Retain attempts seven days for quota/operational diagnosis, delete them
through a bounded expiry job, and cascade them on account deletion.

The feedback module owns `buildFeedbackEmailAttemptExpiry` and
`scheduleFeedbackEmailAttemptExpiry`. It uses a durable `job_runs` claim,
deletes in bounded batches, and is registered only inside the existing
`startCrons()` instance-0 guard so two PM2 workers cannot schedule competing
cleanup loops.

Reserve quota under a per-user/UTC-day Postgres advisory transaction lock:

1. Canonicalize and validate the request without persisting its content.
2. Count `RESERVED|ACCEPTED` attempts plus same-day legacy `Suggestion` rows
   during the cutover day. If five, return 429.
3. Generate a random RFC-compliant Message-ID, insert it with RESERVED, and
   commit before calling SMTP. Two PM2 workers serialize quota reservation;
   Redis is never authoritative.
4. Send the plain-text email with that Message-ID.
5. SMTP acceptance -> persist ACCEPTED + Message-ID.
6. An SMTP rejection at MAIL FROM, RCPT TO, or DATA is definitive: mark FAILED
   and release the slot. Socket loss/timeout before DATA begins is also
   definitive. Socket loss/timeout after DATA begins but before Google's final
   `250` is uncertain: remain RESERVED and consume the slot.
7. Once final `250` acceptance is known, return `201 delivery:"email"` even if
   bounded ACCEPTED-state persistence retries fail.

Every retry is a new attempt and may create a duplicate email. The sheet keeps
the draft and clearly says **We couldn't confirm delivery. Retrying may send a
duplicate.** This is an explicitly accepted product tradeoff; no request
digest, client key, Redis dedupe, or provider idempotency is added. A
client-side timeout/no response uses the same warning because the server may
have completed the send.

## Backend module shape

- `src/modules/feedback/models/feedbackEmailAttempt.js`: Prisma metadata and
  atomic reservation/finalization operations.
- `src/modules/feedback/services/googleWorkspaceFeedbackTransport.js`:
  injected Nodemailer/SMTP adapter; no Prisma and no user-built raw headers.
- `src/modules/feedback/commands/sendFeedbackEmail.js`: validation,
  canonicalization, quota orchestration, plain-text message formatting, and
  injected transport/clock/UUID/model collaborators.
- `src/modules/feedback/routes.js`: thin authenticated route through the repo's
  shared `asyncHandler`/`AppError` mapping; no Prisma/provider calls in route.
- `src/modules/feedback/index.js`: model -> service/command -> routes-last
  exports. Provider and Prisma are always faked in unit seams; integration tests
  use real HTTP/test Postgres and a fake transport, never live email.

The plain-text email body includes feedback, optional category, display name,
app version/platform, and whether Reply-To is present. Never include user ID,
auth/provider subject, token, device/installation/ad ID, steps/health data, or
arbitrary headers. If an HTML alternative is later added, escape every value.

## Privacy and retention

- Do not provision a dedicated Workspace user/alias or a special retention OU.
  Support email follows the mailbox's normal retention and may remain until a
  support operator manually deletes it. Restrict mailbox access to support
  operators.
- Update `web/src/pages/PrivacyPage.vue` before launch: name Google Workspace as
  the support processor, disclose feedback/reply-address transfer and manual
  mailbox deletion, and correct the statement that account deletion removes
  all copies. Make the same correction in `web/src/pages/SupportPage.vue`.
  Review iOS App Privacy and Google Play Data Safety disclosures.
- No delivery webhook or local message-body logs. Operational metrics are only
  attempt state, Message-ID, latency/error class, and aggregate counts.

## Data-driven legacy drain and three-stage cleanup

### Stage A0: shared-lock compatibility release

- First apply the additive `feedback_email_attempts` migration while every
  worker still runs the legacy backend. Then change the legacy
  `createSuggestion` command so its per-user/UTC-day count includes both
  Suggestions and `RESERVED|ACCEPTED` attempts, and its quota check plus
  Suggestion/thread/message creation occur under the same Postgres advisory
  transaction lock the new quota model will use.
- Deploy A0 backend-first to both PM2 workers and verify both are running it.
  This prevents an A0 worker from admitting a sixth legacy submission after an
  A1 worker reserves the fifth slot during the later rolling reload.

### Stage A1: additive email release

- Add Google Workspace SMTP delivery and stop creating new legacy content rows.
  Count same-day legacy Suggestions and new attempts together under the A0
  lock; the attempt metadata/table is already present from the A0 prerequisite.
- Keep legacy tables, all existing reads/replies, support unread counts,
  support events/projections, expiry job, account deletion, and both admin
  layouts. Every reply may extend expiry another 30 days.
- Deploy A1 backend-first, then the same frontend behavior on iOS and Android.

### Drain gate

- Let existing conversations expire naturally. Do not export or immediately
  delete them.
- Continue legacy behavior while any `feedback_threads.expires_at > now()` row
  exists. After the expiry job runs, a SELECT-only production check must report
  zero active and zero total thread rows before Stage B.
- Also require zero nonterminal `SUPPORT_REPLY_CREATED_V1` outbox events and
  projections, and zero remaining `SUPPORT_REPLY` Inbox/delivery rows. These
  consumers can still dereference thread/message tables after the thread UI is
  empty.
- A fresh explicit approval is required for each production deploy/data step.

### Stage B: DB-free code release

- Replace legacy list/detail/write routes with permanent shims; remove all
  support unread counting/cache dependencies, support events/projection,
  expiry/account-deletion references, queries/commands, and user/admin UI.
- Invalidate affected Inbox unread caches so `totalUnreadCount` safely converges
  to the alerts-only `unreadCount`; retain both response fields.
- Keep `Suggestion`, `FeedbackThread`, and `FeedbackMessage` models/tables for
  rollback. Deploy the Stage B backend first, verify the complete rollout, then
  ship the alerts-only frontend. Start the one-week Stage C observation clock
  only after the backend rollout is complete.

### Stage C: destructive schema release

- Only Stage-B-or-newer code may run. Under separate production approval,
  delete retained parent Suggestion rows and drop messages -> threads ->
  suggestions, indexes, FKs, Prisma models, and User relations through a checked
  migration (never `prisma db push`).
- After Stage C, rollback floor is Stage B; Stage A code is no longer safe.

## Tests-first implementation plan

### Backend Stage A

- A0 real-HTTP concurrency proves two simultaneous legacy submissions share the
  advisory lock and cannot pass the fifth-slot boundary. A deterministic real
  two-server mixed test proves four legacy rows plus a committed A1 reservation
  make an A0 worker reject a sixth submission.
- Real HTTP + confirmed `*_test` Postgres: accepted send/discriminator,
  validation/error envelopes, missing config, SMTP rejection/timeout,
  ambiguous timeout reservation, accepted-then-finalize failure, definitive
  failure quota release, account deletion, and attempt expiry.
- Two real app/server instances: simultaneous sixth submissions reserve at most
  five. Concurrent/retried requests may send duplicates but cannot reserve more
  than the daily limit.
- Exact envelope/Reply-To/plain-text body, absent Reply-To warning, bounded
  provenance, no forbidden identifiers, pre-dispatch Message-ID persistence,
  exact accepted recipient, SMTP stage classification, and known-acceptance
  finalize-failure success semantics.
- Attempt-expiry job coverage proves instance-0-only scheduling, durable claim,
  bounded seven-day deletion, and account-deletion cascade.
- Existing Inbox/domain integration tests seed legacy rows through test setup
  and continue exercising public read/reply HTTP paths. Do not weaken/delete
  them merely because POST no longer creates threads.

### Frontend Stage A

- Pump real Home/sheet: field order, compact keyboard-open scroll, validation,
  loading/error/draft preservation, `delivery:"email"` vs missing/unknown
  delivery copy, disclosure copy, and duplicate-warning copy after ambiguous
  delivery.
- Prove no platform mail client is invoked and tutorial fake cannot send.
- Preserve existing Home order and legacy Inbox/admin surfaces during drain.

### Stages B/C

- Real HTTP compatibility envelopes/auth; no legacy-table queries; Inbox counts
  alerts-only; account deletion/expiry and domain producer matrix remain valid;
  drain evidence includes zero nonterminal support events/projections and zero
  support Inbox/delivery rows.
- Frontend real Inbox/admin layouts on both platforms remove all support entry
  paths without gaps and preserve ordinary alerts.
- Apply migrations to disposable Postgres with legacy rows and prove Stage A
  works before Stage B, Stage B works with tables present, and only Stage B-or-
  newer works after Stage C.

## Acceptance criteria / definition of done

- New submissions are accepted through Google Workspace SMTP relay to the
  locked envelope and no feedback content is stored in Bara's feedback tables.
- Reply-To is safe and useful when available; absent-address mail cannot create
  a support loop.
- Atomic five/day quota holds across exactly two workers; occasional duplicate
  email after an ambiguous retry is accepted.
- Frozen app/backend combinations render honest success and remain usable.
- Existing conversations drain data-dependently; destructive cleanup follows
  additive attempt migration -> A0 on both workers -> A1 -> zero
  thread/support-event work -> B backend -> B frontend -> at least one week ->
  C with separate prod approvals.
- Privacy/store disclosures, DNS/DMARC delivered-header evidence, mailbox loop
  tests, Flutter analyze/tests, backend unit/integration tests, both platforms,
  code review, and the manual UI checklist are complete.

## Manual UI-placement test plan

**Elements under test:** Home Feedback card remains once, as the final Home
section below Suggested Races.

**Elements under test:** Optional EMAIL FOR A REPLY field is added once inside
the existing feedback sheet, between the feedback message area and SUBMIT.

**Elements under test:** During the 30-day drain, existing user and admin
support-thread rows and reply screens remain in their current locations.

**Elements under test:** In the later cleanup release, support-thread rows,
reply screens, and both platform-specific admin INBOX sections are removed
without leaving gaps or duplicates.

### Checklist

1. **Home tab — real screen, drain release**
   - **Get there:** Sign in on iOS → Home → scroll to the bottom.
   - **Verify:** The Feedback card appears exactly once, remains below Suggested
     Races as the final Home section, and has not appeared higher in the feed or
     beneath a second copy.
2. **Feedback sheet — compact iOS screen**
   - **Get there:** On an iPhone SE-sized device or simulator → Home → bottom
     Feedback card → SEND FEEDBACK.
   - **Verify:** The sheet contains one feedback message area, then one EMAIL
     FOR A REPLY field, then one SUBMIT action. Focus each field so the keyboard
     is open and confirm the sheet can scroll far enough to reveal and tap
     SUBMIT; the button is not left behind the keyboard or clipped below the
     screen.
3. **Feedback sheet — compact Android screen**
   - **Get there:** On a compact Android device or emulator → Home → bottom
     Feedback card → SEND FEEDBACK.
   - **Verify:** The same message-field → reply-email-field → SUBMIT order
     appears once. With the keyboard open on each field, SUBMIT remains
     reachable by scrolling and no field or action is duplicated outside the
     sheet.
4. **Tutorial Home mirror — onboarding and replay**
   - **Get there:** First use a fresh account that enters onboarding → tutorial;
     then use Profile → SETTINGS → VIEW TUTORIAL for the replay path. Check the
     first and final Home beats.
   - **Verify:** The tutorial continues to show the real Home layout with no
     Feedback card moved into or duplicated within the visible upper Home
     viewport. After leaving the tutorial, the real Home Feedback card is still
     only at the bottom of Home.
5. **User Inbox — retained during the 30-day drain**
   - **Get there:** Use an account with a support conversation created before
     the email cutover → Home → notification bell/Inbox → tap its BARA SUPPORT
     row.
   - **Verify:** The support row still appears once among the Inbox items, and
     tapping it still opens the existing BARA SUPPORT conversation with the
     reply composer at the bottom. It has not moved to Home, Settings, or a
     second Inbox section.
6. **Admin tools — retained during the 30-day drain**
   - **Get there:** Use an admin account with a pre-cutover support conversation
     → Profile → SETTINGS → ADMIN TOOLS. Run once on iOS and once on Android;
     scroll to INBOX and open the support row.
   - **Verify:** Each platform-specific admin layout still contains one INBOX
     section in its existing position between configuration/metrics content and
     debug content. The support row opens one SUPPORT REPLY screen with its
     composer at the bottom; no second support panel appears elsewhere.
7. **User Inbox — later post-drain cleanup release**
   - **Get there:** After the separately approved cleanup release, open Home →
     notification bell/Inbox using an account that also has ordinary alerts.
   - **Verify:** Ordinary alert rows remain in their existing list position, but
     no BARA SUPPORT heading, support row, support conversation, or reply
     composer appears. There is no empty support-only gap or duplicate alerts
     section where support content used to be.
8. **Admin tools — later post-drain cleanup release**
   - **Get there:** After cleanup, use an admin account → Profile → SETTINGS →
     ADMIN TOOLS. Check both iOS and Android builds.
   - **Verify:** The support-thread INBOX section is absent in both
     platform-specific admin layouts, its former space is closed, and the
     sections immediately before and after it remain in order. No support row
     or SUPPORT REPLY route remains reachable from Admin Tools.

**Surfaces confirmed unaffected:** Settings → HELP & LEGAL → SUPPORT is a
separate web-support action and does not render the feedback sheet or legacy
thread UI; it should remain in place.

**Surfaces confirmed unaffected:** Demo race tutorial and race-detail tutorial
previews do not render Home's Feedback card or the feedback sheet.

**Surfaces confirmed unaffected:** Races, Friends, Boards, and Profile tabs do
not render feedback submission or support-thread UI.

**Risks found while planning:** The tutorial uses the real `HomeTab`, so the new
`submitSuggestion` signature must also be mirrored by
`TutorialPreviewBackendApiService`; otherwise a tutorial interaction could
escape to the real API.

**Risks found while planning:** The tutorial spotlight overlay absorbs
gestures, while the Feedback card sits below the initial Home viewport. Its
exact bottom placement cannot be positively inspected inside the tutorial on a
normal device; the real-screen checkpoint and existing real-widget tutorial
coverage must guard that shared placement.

**Risks found while planning:** Adding a second text field to the current
`mainAxisSize: min` sheet can overflow on compact devices when the keyboard
opens unless the sheet body itself becomes scrollable.

**Risks found while planning:** Admin Tools has separate iOS metrics-dashboard
and non-iOS legacy layouts, and each independently inserts `AdminInboxBody`;
the later removal must update and inspect both branches.

**Risks found while planning:** User support conversations have two entry
paths—the merged Inbox list and direct support-thread notification
destinations. Both must remain during the drain and disappear only in the later
cleanup release.

## Revision log

- **Draft exploration (2026-08-27):** expanded the request from the Home button
  to include the shared sheet, user Inbox, admin layouts, unread counts,
  support-reply notifications, expiry/account deletion, old-client routes, and
  three-table data lifecycle.
- **Gap pass 1 (2026-08-27):** corrected the unsafe idea of immediately deleting
  the old endpoint/tables. Added permanent compatibility envelopes, a two-phase
  migration, backend-first deploy order, rollback boundaries, and separate prod
  approval.
- **Gap pass 2 (2026-08-27):** added no-mail-client recovery, the distinction
  between composer launch and actual send, tutorial external-launch isolation,
  mailbox/provider retention and account-deletion implications, reply-to null
  handling, sender authentication, abuse controls, and the requirement that the
  legacy shim never acknowledge discarded feedback.
- **Owner interview 1 (2026-08-27):** old-version-specific forwarding was made
  a non-requirement; existing rows will drain under the current 30-day policy.
  In response to the owner's mail-client coverage concern, revised the
  recommendation to backend delivery with a verified Bara From address and an
  optional user Reply-To field. Documented that iOS `mailto:` already targets
  the selected default client (including Gmail), while Gmail-specific fallback
  is not universal enough to solve the concern.
- **Owner interview 2 + UI review (2026-08-27):** locked From/To to
  `support@barastep.com`, subject prefix to `USER FEEDBACK`, and user email
  solely to Reply-To. The owner later approved a unique server-generated
  subject suffix to prevent unrelated Gmail conversation grouping and
  initially confirmed that the 30-day Workspace policy could cover all support
  mailbox email, then explicitly declined a retention OU and extra bounce user;
  the final design uses normal mailbox retention and an unprovisioned bounce
  sink. Added the manual checklist verbatim and made compact-sheet
  scrolling, both admin layout branches, and both legacy thread entry paths
  explicit implementation requirements.
- **Architect review (2026-08-27):** changed the design to Resend HTTPS with
  exact-domain DKIM/DMARC evidence; added structured provider idempotency,
  content-free atomic Postgres quota metadata, exact API discriminators/errors,
  unverified Reply-To handling, privacy/store disclosure work, a data-driven
  drain, and separate A/B/C releases with a one-week pre-drop observation.
- **Post-review gap pass 1 (2026-08-27):** reconciled old-backend `201` behavior
  with honest client copy, preserved legacy Inbox/admin surfaces through the
  drain, made invalid stored fallback email non-blocking, and added explicit
  same-address mailbox loop controls.
- **Post-review gap pass 2 (2026-08-27):** bounded the PENDING retry window to
  Resend's 24-hour idempotency guarantee, defined FAILED replay behavior, added
  seven-day metadata expiry semantics, and added in-sheet 30-day processing
  disclosure plus its widget coverage.
- **Owner provider revision (2026-08-27):** replaced Resend with the existing
  Google Workspace SMTP relay and removed client/provider idempotency by owner
  decision. Simplified durable state to content-free quota attempts; an
  ambiguous retry may duplicate mail and consumes another reserved slot, while
  the five/day limit remains atomic across two workers.
- **SMTP architect re-review (2026-08-27):** removed final idempotency remnants;
  added A0 shared-lock rollout safety, pre-dispatch Message-ID persistence,
  exact SMTP uncertainty/finalization semantics, controlled bounce envelope,
  instance-0 durable attempt expiry, enforceable Workspace OU auto-deletion,
  support-page disclosure, support-event drain gates, and backend-first Stage B
  ordering.
- **Post-SMTP gap pass 1 (2026-08-27):** checked every old/new rolling-worker
  pairing, migration compatibility, fifth-slot boundary, accepted-but-unfinalized
  result, and client timeout; made duplicates explicit without allowing quota
  races or dishonest success copy.
- **Post-SMTP gap pass 2 (2026-08-27):** checked the invisible SMTP envelope,
  same-mailbox loop paths, enforceable Inbox/Sent/Trash/bounce retention,
  account-deletion disclosures, attempt cleanup scheduling, and pending support
  notification work before legacy table readers are removed.
