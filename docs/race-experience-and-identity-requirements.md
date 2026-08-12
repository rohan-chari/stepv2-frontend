# Race experience, invite gate, and discoverable identity requirements

**Status:** Architect approved — awaiting explicit user approval before
implementation.

## 1. Summary and user stories

This package makes six related product surfaces feel intentional and closes two
social-identity gaps:

1. Replace the text-heavy race-details card and prize-pool bottom sheet with a
   compact arcade scorecard that has one visual hierarchy and one source of
   payout truth.
2. Put `Continue` above the optional `REROLL ALL` action in the multi-box result
   modal, matching the single-box flow.
3. Put invited runners' decision actions immediately under race details in one
   row, using yellow for the positive action and red for decline.
4. Remove invite rows from the Races tab and require pending invitations to be
   answered in a blocking decision modal when the user enters that tab.
5. Replace the title-screen tagline/mission copy with the marketing mission
   statement and replace the generic purple question-mark cube with a newly
   generated, house-style mystery-box icon that resembles Bara's in-game box.
6. Ask new users for a discoverable first/last name before they choose a race
   display name; prompt existing users who have not completed that setup; allow
   Friends search to match either identity; and verify the intended automatic
   friendship behavior for quick-race sharing/referrals.

As a runner, I can understand duration, prize, payout rule, and my likely reward
at a glance instead of parsing a paragraph stack.

As an invitee, I must answer an invitation before using the Races tab, and the
same accept/decline decision is visually consistent on race detail.

As a new user, I understand why Bara asks for my real name, see it prefilled when
the identity provider supplied it, and then deliberately choose what other
runners see in races. Existing users get the same setup on Home without being
locked out of the app.

## 2. Current-state evidence

- `lib/screens/race_detail_screen.dart:3441-3610` owns the hero prize chip and
  prize-pool sheet. `:3698-3825` owns the inline race-details/payout card. Both
  independently compose the same payout facts, which permits visual drift.
- The same `_buildRaceInfoCard` is rendered in pending and invited-active race
  states (`race_detail_screen.dart:3930-3932` and `:4376-4378`). The real race
  screen is also used by demo/tutorial infrastructure, so this is not a single
  screenshot-only surface.
- Pending invite actions currently sit well below the details/participant/lobby
  content and stack vertically (`race_detail_screen.dart:4281-4320`). Team
  invites are a special case: acceptance currently requires choosing a team peg.
- `lib/screens/multi_case_opening_screen.dart:495-534` renders `REROLL ALL`, its
  disclaimer, and then `Continue`. The protected test at
  `test/batch_2026_08_10b_reroll_all_test.dart:355-375` explicitly pins that old
  order and must be mechanically updated to the newly approved order, not
  deleted or weakened.
- `lib/screens/tabs/races_tab.dart:416-436` counts invite rows in the header and
  feeds them into the personal list. `:679-820` pins race and tournament invite
  rows above the state pills. Tutorial preview data also contains an invite
  fixture (`lib/tutorial/tutorial_preview_data.dart:428-480`).
- `lib/screens/main_shell.dart:3032-3050` allows horizontal page swipes and only
  refreshes races after the Races page has become current. A real blocking gate
  therefore needs shell/tab coordination; simply showing a dialog from a row
  tap is insufficient.
- Home already promotes one pending race invite via
  `lib/screens/tabs/home_tab.dart:413-444`; this remains the non-blocking Home
  treatment.
- `lib/screens/start_screen.dart:245-280` renders `STEP. RACE. WIN.` plus the
  older mission line. `_FeatureRow` uses
  `assets/images/title_feat_box.png` (`:498-504`), currently a purple
  question-mark cube.
- User identity currently has `User.name` (provider-supplied, not an explicit
  discoverability choice) and unique nullable `User.displayName`; no explicit
  first/last-name completion marker exists (`backend/prisma/schema.prisma:9-25`).
  Provisioning deliberately generates an unrelated fun display name in
  `backend/src/modules/users/services/ensureAppleUser.js:16-102` and the Google
  counterpart. The display-name validator allows only 4-30 ASCII letters,
  digits, and underscores, with no spaces
  (`backend/src/shared/lib/displayNameValidator.js:3-58`).
- Friends search currently matches only `displayName` and returns
  `{id, displayName, profilePhotoUrl}`
  (`backend/src/modules/users/models/user.js:355-375`); the Flutter hint and
  result rows say/show display name only
  (`lib/screens/tabs/friends_tab.dart:455-490,760-799`).
- Existing Home SETUP composition is centralized in
  `lib/screens/tabs/home_tab.dart:1418-1540`; that is the required remediation
  surface for active users, rather than a new one-off popup.
- Referral attribution already performs a best-effort accepted friendship after
  successful new-signup attribution and late code redemption
  (`backend/src/modules/social/commands/recordReferral.js:98-124` and
  `redeemReferralCode.js:110-145`). Share-token race join itself does not create
  a friendship (`backend/src/modules/races/commands/joinRaceByShareToken.js`).

## 3. Scope

### In scope

- Shared compact payout presentation for inline Race Details and the prize sheet.
- Pending/active invited-race action placement and colors.
- Multi-box result action reorder.
- Races-tab invitation decision gate and removal of inline invite rows/metric.
- Start-screen copy and one replacement generated PNG.
- New discoverable-name persistence, setup flow, Home remediation row, and
  Friends search behavior.
- Integration coverage for the locked automatic-friendship rule.
- iOS and Android parity, accessibility, text scaling, small-screen behavior,
  dark mode, demo/tutorial mirrors, and defensive response parsing.

### Non-goals

- Changing prize amounts, payout curves, eligibility, buy-ins, race duration,
  referral reward amounts, or any other economy rule.
- Changing the Home pending-invite card into a blocking prompt.
- Removing old invitation endpoints or fields. Frozen clients still need them.
- Reworking the single-box opening flow beyond using it as ordering reference.
- Making first/last name visible in races, leaderboards, chat, or notifications;
  only `displayName` remains the public race identity.
- Deploying to production. Implementation approval does not authorize a deploy.

## 4. Visual and interaction direction

The direction is **compact arcade scorecard**, not a generic Material settings
card: parchment playing surface, strong gold score numerals, hairline/divider
structure, short uppercase labels, and one dominant answer per block. The
existing pixel/arcade type and green checker world remain; no new unrelated
font, gradient language, or pictorial CustomPainter art is introduced.

### 4.1 Shared compact race-details scorecard

Create a reusable payout-presentation model/widget rather than maintaining
parallel text stacks. Proposed inline hierarchy:

```text
┌──────────────────────────────────────────┐
│ DURATION                 PRIZE POOL  [PROJECTED]
│ 1 DAY                    ◉ 1,160          │
├──────────────────────────────────────────┤
│ TOP HALF PAID            1ST PLACE        │
│ 29 OF 58                 ◉ 351            │
│ [ YOU: 7TH · 198 PROJECTED ]   PAYOUTS ›  │
└──────────────────────────────────────────┘
```

Rules:

- The top row is always two balanced metric cells when a funded pool exists.
  Legacy buy-in races retain three compact cells: duration, buy-in, pot.
- The lower area renders at most two fact columns plus an optional one-line
  viewer status. It does not repeat prose such as “bigger prizes up top” and
  “final payouts settle…” inline. Explanatory prose moves to the sheet.
- Graded curve: left fact is paid cut (`29 OF 58`), right fact is first-place
  projection (`351`). Even split: left fact is paid cut, right fact is estimated
  per-head amount. Winner-take-all/top-three: retain concise podium facts.
- `PROJECTED`/`MAX` remain explicit and adjacent to the pool value. No value is
  inferred client-side; all amounts continue to come from `payoutTiers` and
  `prizePool` with existing defensive fallbacks.
- “PAYOUTS ›” is a minimum 44x44 semantic tap target even if its visible label
  is small.
- Inline scorecard target height at 1.0 text scale: no more than 190 logical
  pixels for the screenshot's graded case, excluding the section heading.
  It must grow rather than clip at 1.3 text scale.
- A missing/malformed `payoutTiers` omits the lower payout block and still shows
  duration/pool. A missing `prizePool` retains the legacy buy-in/pot path.

### 4.2 Sleek prize-pool sheet

Replace the sparse centered text column with a structured bottom sheet using
the same presentation model:

- drag handle and `PRIZE POOL` title row with status tag;
- one gold “total pool” hero band containing coin icon + amount, rather than an
  unanchored number and separate `gold` line;
- one short rule callout (team split, projected settlement, max, or no callout
  when none is needed);
- a `PAYOUTS` section with compact tier rows or the graded/even summary and the
  full lazy list;
- safe-area bottom spacing and a maximum scrollable height so 150 paid places
  remain usable on small devices;
- the team case must not render a misleading per-runner full-pool amount.

The hero chip, inline scorecard, and sheet must share parsing/presentation logic
so projected/max/team/even/graded decisions cannot diverge.

### 4.3 Invite actions on race detail

- For a non-team pending invite, render one 48px-high row immediately after the
  Race Details card: yellow `ACCEPT` on the left, red `DECLINE` on the right.
- For an active-but-still-invited race, the same row appears immediately after
  Race Details, followed by the compact “already underway” note.
- Loading disables both actions and changes only the active label to
  `JOINING…`/`DECLINING…`; double taps are impossible.
- Use semantic positive/decision-yellow and destructive-red tokens that work in
  light/night palettes. Do not reuse green against the green checker background.
- Team invites use the same yellow `ACCEPT` action and omit a side picker. The
  existing backend already treats an omitted team as auto-assignment to the
  smaller side, with ties going to Team A and both-full returning `TEAM_FULL`.
  Race detail removes the invited-only “tap a peg” requirement while preserving
  the lobby as context.
- A paid invite states the buy-in on the yellow control (`ACCEPT · 100`) and
  shows the coin icon/charge before the tap. Existing insufficient-balance and
  race-closed errors remain authoritative; the UI never hides a cost inside a
  generic `ACCEPT` action.

### 4.4 Multi-box result order

After result tiles and any queued/auto-activated notes:

1. green `Continue`;
2. 14px gap;
3. optional yellow `REROLL ALL`;
4. reroll disclaimer.

`Continue` remains disabled while a rewarded-ad reroll is in flight. When reroll
is unavailable, the card contains only `Continue`, with no orphan gap. The
protected old-order assertion is updated to assert the new order and all of its
existing availability/disabled-state coverage remains.

### 4.5 Start screen

- Remove both `STEP. RACE. WIN.` and the old mission subtitle. Replace them with
  the exact single statement: `Step challenges are more fun when you can steal
  someone’s steps.` It may wrap to two/three balanced lines and must remain
  readable over the sky at compact and tall phone heights.
- Generate a new transparent pixel-art feature icon through the `imagegen` +
  `accessory-art` workflow. Generate into scratch, use a flat chroma-key
  background, remove it with the provided script, composite on white for review,
  and perform one targeted regeneration if critique finds a miss.
- Reference `title_feat_trophy.png`, `title_feat_board.png`, the current purple
  cube, and the actual race-detail opening UI. The new icon is a compact
  cream/parchment arcade cabinet with a deep charcoal-felt reel window, dark
  frame, gold center pointers/glow, and small colorful powerup tiles. It is not a
  green/gold chest. It must have chunky pixels, a continuous black outline,
  clean alpha, and remain legible at 54-64px.
- Install only the approved PNG at `assets/images/title_feat_box.png` (same path
  avoids manifest/catalog changes). This is title-screen UI art, not a shop
  cosmetic: no `shop_items` row or `testOnly` catalog flip is required.

## 5. Races-tab invitation decision gate

### 5.1 Entry behavior

- Home keeps its existing promoted pending-invite card.
- The Races tab no longer renders an `INVITES` metric, invite header, race invite
  rows, or tournament invite rows in its normal content.
- When the user navigates/swipes to Races, the Races child is already an opaque
  gate surface (never a stale list frame), and the shell refreshes invitation
  state. While unresolved, a full-surface loading state prevents interaction
  with or semantic access to the race list. `ExcludeSemantics`/focus trapping
  keeps screen readers out of obscured content.
- If there are pending decisions, present a non-dismissible arcade modal. The
  user cannot tap the barrier or swipe it down. Android back/tab switching either
  exits to the previous non-Races tab or is blocked according to the explicit
  §12 decision; neither path ever exposes Races before resolution.
- Each modal shows inviter, race/bracket name, duration/start state, team rule if
  relevant, buy-in if any, and yellow accept + red decline in one row. A paid
  accept label includes its coin cost. Team acceptance sends no team choice and
  uses the existing server auto-assignment rule; the button remains `ACCEPT`.
- Both race and tournament invitations are gated. Multiple invitations are
  processed one at a time in deterministic order: all tournaments first by
  `createdAt` ascending (oldest first), then races by earliest invite expiry,
  scheduled start, or creation time as specified in §7.5.
  After a successful response, refresh from the backend and show the next. When
  none remain, reveal the standard Races page.
- A network error leaves the decision modal open, re-enables both buttons, shows
  a concise inline error, and offers Retry. It never optimistically removes an
  invite.
- If the initial refresh itself fails, show Retry plus the approved exit-to-Home
  action; never reveal potentially stale Races content and never claim there are
  zero invites.
- Once a user is already viewing a resolved Races page, an ordinary pull-to-
  refresh failure does not suddenly cover it with the entry gate. The blocking
  preflight runs per transition into Races, not on every background refresh.
- After removing the invite metric, the header becomes two balanced metrics:
  `ACTIVE` and `WAITING` (pending races). It does not replace INVITES with a
  misleading count from another state.

### 5.2 Ownership and mirrors

- `MainShell` owns entry interception/refresh because `PageView` swipes bypass
  bottom-navigation callbacks.
- The supported branch uses an explicit epoch-tagged state machine:
  `unverified → checking(epoch) → decision(epoch, queue) | open(epoch) |
  error(epoch)`. `unsupported` is a separate stable legacy state. Leaving Races
  resets a supported branch to `unverified`; the prebuilt Races child paints an
  opaque, nonsemantic gate in every state except `open`, so a partial PageView
  swipe never reveals stale list pixels.
- Every entry increments the epoch and forces a network refresh, bypassing stale
  `Loadable` data. Only a result whose epoch still matches may transition the
  gate. A failed fresh request cannot treat cached races as invite verification.
- In `decision`, modal barrier, Android back, bottom tabs, and PageView navigation
  are blocked. An invite-response network failure moves to `error` while
  retaining the queue; `error` and initial checking failure offer `RETRY` and
  `BACK TO HOME`. Exiting returns Home and resets to `unverified`; it never
  reveals Races. A successful response forces a fresh same-epoch list read
  before advancing.
- A dedicated `RaceInviteDecisionGate` owns presentation; `RacesTab` receives
  only accepted/pending/completed content and has no duplicate invite responder.
- When the backend does not advertise
  `user.featureFlags.racesInviteDecisionGateEnabled == true`, state is
  `unsupported` and `RacesTab` preserves the existing inline invite responders/
  strip/header byte-for-byte. Missing, null, false, or any non-Boolean value is
  unsupported; only literal Boolean true enables the gate.
- Remove/update tutorial preview invite fixtures and Races-tab effect/tutorial
  copies that assume an inline invite strip. Home tutorial fixtures retain their
  promoted invite where applicable.
- Deep-linking directly to an invited race still uses race detail and its own
  immediate decision row; the Races-tab gate is not the only response path.

## 6. Discoverable identity and onboarding

### 6.1 Data semantics

Do not repurpose provider `User.name`. Add explicit nullable fields:

```prisma
firstName                    String?   @map("first_name")
lastName                     String?   @map("last_name")
discoverableNameSearch       String?   @map("discoverable_name_search")
nameSetupOnboardingRequired  Boolean   @default(false) @map("name_setup_onboarding_required")
nameSetupCompletedAt         DateTime? @map("name_setup_completed_at")
```

`nameSetupCompletedAt` is the authoritative completion bit. Provider names do
not silently mark setup complete. All columns are additive; the identity/search
columns are nullable and the cohort Boolean has a safe false default. They are
deleted with the user row.
`nameSetupOnboardingRequired` distinguishes rollout cohorts: existing users
default false and receive only the Home SETUP row. A create-branch provision
stamps true **only when both** the default-off
`discoverableIdentityOnboardingEnrollmentEnabled` server flag is true and that
same request advertises the `discoverable_identity` client feature. Tokenless
or flag-off creates remain false, and an existing-user sign-in never changes the
cohort bit. A capable client blocks only when the backend contract is supported,
`required == true`, and completion is null. It is never inferred from
`createdAt`, health/tutorial state, current flag value, or a missing field.

`discoverableNameSearch` is a server-maintained normalized combination of first
+ last name (for example `nathan chari`). It is never sent to clients. One shared
normalizer is used on writes and queries: Unicode NFKD; remove combining marks;
lowercase; replace every run outside Unicode letters/numbers with one ASCII
space; trim/collapse spaces. Keeping a dedicated value makes single-token,
last-name, and combined matching one indexed predicate without concatenating
every row at request time.

Validation contract:

- trim/collapse whitespace;
- first name 1-50 Unicode grapheme clusters; last name null/empty or 1-50;
- letters, combining marks, apostrophes, hyphens, and spaces inside a component;
- no control characters, emoji, URLs, or profanity;
- last name is optional for single-name cultures; first name remains required.

### 6.2 New-user flow and App Review rationale

For a capable new client, identity setup is the first product step after the
provider/referral welcome and before health permission:

**Page 1 — HELP FRIENDS FIND YOU**

- Copy: `Add the name people know you by. It is only used so friends can find
  you in Bara.`
- Separate required `First name` and optional `Last name` fields.
- Prefill from the Apple/Google provider name when present, but require the user
  to review and submit it; never infer completion from provider data.
- The CTA is `THAT'S ME` or `CONTINUE`, not “create another account/name.”

**Page 2 — YOUR RACE NAME**

- Copy: `This is what people will see in races. We combined your name to get
  you started — change it if you want.`
- Prefill a valid display-name candidate derived from the submitted names.
- Keep live uniqueness validation, character rules, profanity handling, retry,
  and an explicit confirmation tap.
- Only after page 2 succeeds does onboarding continue to health/tutorial/race.
- If the app is killed after Page 1, the required bit remains true and completion
  remains null. Resume refetches `/auth/me`, repopulates the saved fields, and
  returns to Page 2 (or lets Back edit Page 1); it never skips confirmation.

This makes the reason for the post-login request explicit, avoids asking the
user to invent an unrelated identity immediately after Sign in with Apple, and
uses provider data as a convenience rather than pretending it is unavailable.

### 6.3 Existing-user remediation

- If `nameSetupCompletedAt` is null/missing, Home SETUP renders first a `HELP
  FRIENDS FIND YOU` row with the same explanation and `ADD YOUR NAME` action.
- It opens the same two-page flow. Existing `displayName` is preserved as the
  Page 2 default rather than overwritten by first+last; the user may keep it
  with one confirmation tap.
- This remediation is not a global blocker and does not hide races, rewards, or
  settings. It remains until both pages complete successfully.
- If an older backend omits the completion field, the new app must distinguish
  “contract unsupported” from explicit null. It must not nag every user when
  pointed at an older backend. New-backend authenticated-user envelopes return
  the safe identity state fields additively to every client (old apps ignore
  them), so field presence establishes support without a cache variant. In the
  carrying build, supported + `required == false` + null completion immediately
  shows Home remediation; the enrollment flag controls only future capable
  create-branch blocking and never hides existing-user remediation.
- The existing generated-name chip is retired/suppressed after this feature is
  enabled to avoid two competing name asks. Old clients retain their current
  generated-name behavior.

### 6.4 Friends search

Capable search matches every eligible account's `displayName`, preserving
today's handle discovery for existing users, and matches the normalized combined
discoverable name only when `nameSetupCompletedAt IS NOT NULL`. Thus an abandoned
Page 1 is never public, while an incomplete existing user remains findable by
their established race handle. Response never exposes email or provider
identifiers.

The approved disclosure shape is:

```jsonc
{
  "users": [{
    "id": "user-uuid",
    "displayName": "NathanChari",
    "profilePhotoUrl": null,
    "discoverableName": "Nathan Chari"
  }]
}
```

When present, the result row shows `Nathan Chari` as the primary identification
line and `@NathanChari` as the race-name secondary line. An incomplete user's
handle-only result keeps the existing single-line treatment and omits
`discoverableName`. Frozen clients ignore the additive key and continue
displaying only `displayName`.
If a legacy rename later leaves `displayName` null, render only the completed
discoverable name and action; never crash or print a bare `@`.

Use one backend query, exclude the caller/review accounts as today, cap at 20,
and deduplicate users who match multiple fields. The eligibility predicate is
`handle match OR (completed setup AND discoverable-name match)`. Derive two parameters: the
trimmed/lowercased literal handle query under the existing display-name rules,
and the §6.1 normalized discoverable-name query. Parameterized SQL ranks with an
explicit `CASE`: exact handle, exact discoverable name, handle prefix,
discoverable-name prefix, other substring match; ties use
`lower(display_name) NULLS LAST, id`. The predicates cover both
`lower(display_name)` and `discoverable_name_search`, use the matching indexes,
and apply `LIMIT 20`; the service never fetches an arbitrary batch and sorts it
in Dart/JavaScript.

Because this broadens search from pseudonymous handles to real names, capable
requests require at least two normalized characters and use an exact fixed-window
limit of 30 searches per authenticated account per UTC minute.
The Flutter field keeps its current debounce/cancellation behavior. Frozen-client
display-name-only behavior is unchanged. Logs/analytics must not record raw name
queries.

## 7. API contract

All additions are optional/additive. A new client feature token
`discoverable_identity` is sent by both header-construction paths.

### 7.1 `PUT /auth/me/discoverable-name` — new

Request:

```json
{ "firstName": "Nathan", "lastName": "Chari" }
```

`lastName` may be `null` or an empty string and is normalized to null. A
single-name user's combined discoverable/search name and initial display-name
candidate derive from `firstName` alone.

Success `200`:

```jsonc
{
  "user": {
    "id": "user-uuid",
    "firstName": "Nathan",
    "lastName": "Chari",
    "nameSetupOnboardingRequired": true,
    "nameSetupCompletedAt": null
  },
  "suggestedDisplayName": "NathanChari"
}
```

The first page does **not** set completion because Page 2 still needs explicit
confirmation. `suggestedDisplayName` is a valid available candidate selected by
the server under the existing uniqueness rules; it is not persisted yet. The
candidate is built with the existing ASCII normalizer/transliteration helper,
first+last with whitespace removed, then collision suffixes; if normalization
produces fewer than four valid characters, fall back to the existing generated
fun-name algorithm. This guarantees Page 2 never receives an invalid default
even when the discoverable name itself is Unicode.
The suggestion is advisory: another user may claim it before Page 2, so only the
Page 2 write is authoritative and its 409 path returns a fresh suggestion.

Errors:

- `400 {"code":"INVALID_FIRST_NAME","error":"…"}`
- `400 {"code":"INVALID_LAST_NAME","error":"…"}`
- `401` existing auth envelope
- `500` generic; no partial write advertised as complete

Repeated valid calls replace the pending discoverable name and return a fresh
suggestion. A non-string `firstName` always produces `INVALID_FIRST_NAME`; a
`lastName` value that is neither string nor null always produces
`INVALID_LAST_NAME`. The committed write invalidates every
`v1:user:<id>:authme` variant. Old clients never call this endpoint.

### 7.2 `PUT /auth/me/display-name` — additive request behavior

Existing body remains valid:

```json
{ "displayName": "NathanChari" }
```

Capable flow sends the additive confirmation bit:

```json
{ "displayName": "NathanChari", "completeDiscoverableNameSetup": true }
```

When `completeDiscoverableNameSetup:true`, the backend requires valid persisted
first/last input, updates the display name and stamps
`nameSetupCompletedAt=now()` atomically. It preserves
`nameSetupOnboardingRequired` as the immutable cohort/audit bit; clients gate on
`required && completedAt == null`. Omitting the request field preserves today's
behavior exactly, so frozen clients can still rename without affecting setup.
If `completeDiscoverableNameSetup` is present but is not Boolean, return
`400 {"code":"INVALID_DISCOVERABLE_SETUP_FLAG","error":"…"}`. Boolean false
is legacy rename behavior and never stamps completion.

Additional error:

- `409 {"code":"DISPLAY_NAME_TAKEN","error":"…","suggestedDisplayName":"NathanChari27"}`
- `400 {"code":"DISCOVERABLE_NAME_REQUIRED","error":"…"}` only when the new
  confirmation bit is true and Page 1 data is absent/invalid

Success continues to return `{user:{…}}` with additive safe identity state. The
committed write invalidates every `v1:user:<id>:authme` variant and the user's
`v1:user:<id>:cosmetics` entry because cosmetics payloads carry display name.

### 7.3 Provision, `/auth/me`, and session responses

- Provider provisioning remains backward compatible and keeps generating a
  valid fallback display name for frozen clients. The create branch receives
  parsed request features and stamps required only for feature-token + enrollment-
  flag requests; tokenless creates and every existing-user branch stay false.
- New-backend provision, `/auth/me`, `/auth/session`, reviewer, and other
  authenticated own-user envelopes add `firstName`, `lastName`,
  `nameSetupOnboardingRequired`, and `nameSetupCompletedAt` to all clients. Old
  apps ignore them, so `/auth/me` does not gain a client-feature cache-key axis.
  Absent keys mean unsupported backend; explicit null means incomplete; only
  supported + required true + null completion blocks onboarding.
- Every spread-based serializer explicitly removes `discoverableNameSearch` and
  never emits it. Introduce one safe authenticated-user serializer rather than
  relying on raw Prisma spread behavior.
- No new provision request field is required.

### 7.4 Friends search

Keep frozen-client `GET /friends/search?q=` unchanged: display-name-only matching
and the old response shape. New clients use `POST /friends/search` so real-name
queries live in the request body and are not written into nginx access-log URLs.

Request:

```json
{ "q": "Nathan Chari" }
```

Success is the approved `{"users":[…]}` shape in §6.4. The new Flutter client
falls back to legacy GET only on a definite 404 from an older backend; it never
falls back on 400/401/429/500. To avoid leaking a name query into URL logs, the
404 transition does not replay the current value as a GET. It switches the field
to legacy race-name-only mode, clears the results, and requires a new query with
a `Search race names` hint.
`discoverableName` is populated only for completed rows; handle-only incomplete
rows omit it or return null, and clients treat both forms identically.

Errors:

- `400 {"error":"Search query must be at least 2 characters","code":"SEARCH_QUERY_TOO_SHORT"}`
- `400 {"error":"Search query is required","code":"INVALID_SEARCH_QUERY"}`
  for absent/wrong-type body values
- `429 {"error":"Too many searches","code":"SEARCH_RATE_LIMITED"}` plus an
  integer `Retry-After` header giving seconds to the next UTC-minute window

Validate body type and normalized minimum length before quota accounting, so
invalid/too-short requests do not consume quota. A valid attempt then uses an
atomic Postgres upsert on one per-user fixed-window row; no raw query is stored.
Search results are an indexed bounded Postgres read, not Redis-cached.

### 7.5 Invitations

No backend endpoint is removed or repurposed. The gate uses existing list and
respond endpoints. Add these exact optional fields to existing list summaries:

```jsonc
// invited race summary
{
  "createdAt": "2026-08-11T20:00:00.000Z",
  "scheduledStartAt": null,
  "myInviteExpiresAt": "2026-08-12T20:00:00.000Z"
}

// invited tournament summary
{
  "createdAt": "2026-08-11T19:00:00.000Z",
  "creator": {
    "id": "user-uuid",
    "displayName": "MayaChen",
    "profilePhotoUrl": null
  }
}
```

All timestamps are ISO-8601 strings or null when the underlying optional value
is absent; malformed/missing values sort last client-side. Decision ordering is
all tournaments first by `createdAt` ascending (oldest first), then races by
`myInviteExpiresAt ?? scheduledStartAt ?? createdAt`, with stable type then id
tie-breakers. Old clients ignore these fields and keep inline rows.
The gate preserves existing server error codes for full teams/brackets,
already-answered invites, insufficient balance, and started/expired races. A
400/409 proving another device already answered triggers a refresh and advances
rather than displaying a permanent failure.

### 7.6 Automatic friendship

Under default-off `quickRaceShareAutoFriendEnabled`, a successful share-token
join of a `QUICK_CREATE` race commits the accepted participant and eligible
friendship mutation in one Prisma transaction. Precedence is exact:

1. accepted friendship → no-op;
2. canonical-pair suppression exists → join succeeds, no friendship mutation
   even if a pending row exists;
3. declined friendship → join succeeds, no mutation;
4. unsuppressed pending in either direction → update to accepted;
5. no row → create accepted from creator to joiner.

An unexpected friendship write failure rolls back the participant join. Cache
invalidation, pushes/events, onboarding boxes, and private-race auto-start run
after commit and failures there never roll back the durable join/friendship.
Friend removal commits deletion plus suppression upsert in one transaction. A
decline likewise commits the `DECLINED` status and canonical suppression upsert
atomically. A later manual send may reopen the friendship row as `PENDING` but
does not delete suppression; only the recipient's explicit manual acceptance may
establish friendship. Every automatic friendship path, including existing
referral attribution, consults suppression before upgrading a pending row, so it
cannot restore a deliberately removed or declined relationship. Manual requests
and explicit manual acceptance otherwise retain today's behavior. Referral
attribution overlapping an accepted pair converges on the accepted no-op. Public
browse-join and non-quick share joins do not auto-friend. Join/remove/decline
response shapes remain unchanged.

## 8. Data model and migration

1. Add nullable `first_name`, `last_name`, `discoverable_name_search`, and
   `name_setup_completed_at`, plus non-null
   `name_setup_onboarding_required BOOLEAN DEFAULT false`. No user-data backfill.
2. Add an exact suppression table:

   ```prisma
   model FriendshipAutoLinkSuppression {
     userAId   String   @map("user_a_id")
     userBId   String   @map("user_b_id")
     reason    String   @default("REMOVED")
     createdAt DateTime @default(now()) @map("created_at")
     userA User @relation("AutoLinkSuppressionA", fields: [userAId], references: [id], onDelete: Cascade)
     userB User @relation("AutoLinkSuppressionB", fields: [userBId], references: [id], onDelete: Cascade)
     @@id([userAId, userBId])
     @@map("friendship_auto_link_suppressions")
   }
   ```

   Pair IDs are always lexicographically sorted before read/write. The raw
   migration adds `CHECK (user_a_id < user_b_id)` so reversed duplicates cannot
   bypass canonicalization. In the same rollout, backfill a suppression pair for
   every currently `DECLINED` friendship before enabling automatic linking. Past
   removals whose rows were already deleted cannot be reconstructed and are the
   documented historical limitation. All automatic friendship paths consult the
   table. Manual send/accept paths ignore it.
3. Add one bounded quota row per account:

   ```prisma
   model FriendSearchRateWindow {
     userId      String   @id @map("user_id")
     windowStart DateTime @map("window_start")
     count       Int
     user User @relation(fields: [userId], references: [id], onDelete: Cascade)
     @@map("friend_search_rate_windows")
   }
   ```

   One atomic upsert resets count for a new UTC minute or increments the current
   window. It never stores query text.
4. Raw migration/runbook SQL installs or verifies `pg_trgm`, then creates GIN
   trigram indexes matching the query predicates exactly:
   `lower(display_name) gin_trgm_ops` for non-null/non-review rows and
   `discoverable_name_search gin_trgm_ops` partial on
   `name_setup_completed_at IS NOT NULL`, non-null search value, and non-review.
   Use `CREATE INDEX CONCURRENTLY` outside Prisma's transaction where required;
   verify extension/index presence and `EXPLAIN (ANALYZE, BUFFERS)` on
   production-like data before flag enablement.
5. Prisma/provider code must tolerate old rows. Backend serializers default
   only at the response edge and never invent completion.
6. Account deletion cascades suppression/quota rows and removes the User PII;
   verify the new fields have no orphan audit/event copy and update privacy/data-
   deletion documentation.
7. Do not backfill from `User.name`: that provider value was not collected under
   the new discoverability explanation and may be stale/incomplete.
8. Identity, completion, suppression, rate-window, and search truth live in
   Postgres. Search results are not added to Redis.

## 9. Implementation path

### 9.1 Backend

Follow the backend's post-refactor module contract:

- user commands/queries under `src/modules/users` (including
  `setDiscoverableName`, completion through the existing display-name command,
  shared normalization/suggestion, and safe authenticated-user serialization);
- identity search/quota and quick-share friendship/suppression commands under
  `src/modules/social`;
- thin injected routers using `asyncHandler` and standard `AppError`
  `{error, code}` mapping, while preserving legacy display-name messages/statuses;
- public exports through each module's `index.js`;
- request feature parsing is threaded into both provision routes/services, not
  read from global state;
- refactor the quick share join's durable participant/friendship portion to use
  one injected Prisma transaction, followed by post-commit caches/events/boxes/
  auto-start; make friend removal deletion+suppression one transaction; and make
  decline status+suppression another. The migration performs the declined-pair
  suppression backfill before any auto-link flag is enabled.

### 9.2 Frontend

1. Extract a defensive payout view model and shared scorecard/sheet widgets from
   `race_detail_screen.dart`; preserve all existing keys where compatibility
   tests/coach marks depend on them and add stable keys for new regions.
2. Replace inline info and bottom-sheet composition, then relocate invited
   action rows. Preserve team-lobby logic and demoMode restrictions.
3. Reorder multi-box actions and update the protected order assertion while
   retaining every existing reroll availability/ad/in-flight assertion.
4. Introduce the shell-owned invitation gate; remove invite strip/metric code
   from `RacesTab`; update tutorial fixtures and any forked race-tab previews.
5. Update title copy and, only after spec approval, run image generation,
   transparency cleanup, white-background critique, 54/64px fit check, and
   replace the title feature PNG.
6. Extend `AuthService` with contains-key guarded first/last/completion state and
   persistence scoped to the authenticated user. Never use unchecked casts.
7. Build a reusable two-page `DiscoverableIdentityFlow` used as onboarding gate
   and Home remediation route. Ensure keyboard, back, retry, offline, loading,
   small-screen, and accessibility states.
8. Insert the new-user gate before health permission without regressing referral
   welcome/pending share-token retention. Gate only when contract fields are
   present, `nameSetupOnboardingRequired == true`, and completion is null.
   Existing users remain non-blocking and use Home SETUP.
9. Add the Home SETUP row and suppress the generated-name chip under the new
   feature contract.
10. Update Friends search hint/results and refresh friend/setup state after
    identity completion or referral actions.
11. Mirror-risk work is explicit: remove/reclassify `race-invite-1`; give
    `DemoRaceEngine.raceDetails()` and `tutorialPreviewRaceDetail()` funded pool/
    tiers so the redesigned UI is exercised; mark tutorial Home identity setup
    complete so SETUP does not shift anchors; remeasure `tutorialPotKey`,
    `races.card`, `races.box`, clock and powerup-tray spotlights; add a real
    two-line Friends search-result fixture/test; keep Settings → Edit Display
    Name as the direct race-handle editor, never the two-page flow.
12. Account for iOS and Android together; no platform-specific visual fork.

## 10. Backward compatibility and rollout

- Deploy backend additions first, then ship iOS and Android in lockstep.
- Old app + new backend: old display-name endpoints, invite rows, search response,
  race joins, and generated fallback names continue working. Additive response
  fields are ignored.
- New app + old backend: payout and all existing race UI work; discoverable-name
  setup is not shown because support is not advertised; no crash on absent keys;
  old invite behavior must remain available as a safe fallback rather than
  leaving the Races tab permanently gated.
- Specifically, the invite gate is enabled only by an explicit backend runtime
  flag/capability. If support is absent, `RacesTab` retains the current inline
  invite strip and three-metric header. This compatibility branch remains until
  old backends are no longer a supported pairing; it is not deleted merely
  because the new branch is the default in development.
- Runtime flags default false:
  `discoverableIdentityOnboardingEnrollmentEnabled` controls only stamping
  capable create-branch accounts; `racesInviteDecisionGateEnabled` controls the
  new-vs-inline invite UI for capable apps; and
  `quickRaceShareAutoFriendEnabled` controls transactional quick-share linking.
  Backend contract support and safe identity-field presence are not conflated
  with enrollment.
- Declare all three keys in backend `KNOWN_FLAGS` with false defaults. Only
  `racesInviteDecisionGateEnabled` is client capability transport: every
  authenticated own-user envelope exposes it at
  `user.featureFlags.racesInviteDecisionGateEnabled`. The enrollment and
  auto-friend switches remain server-only. Auth-me cache means a flag flip may
  take the existing bounded 10-second TTL to reach a client; this is acceptable
  for staged rollout and rollback, and no user may be stranded because the
  unsupported inline branch remains available.
- Rollout order: deploy migrations/endpoints/serializers with all flags off;
  verify staging including Redis-on and `REDIS_URL` unset; ship iOS + Android.
  The carrying build immediately shows non-blocking Home remediation for existing
  incomplete users. After the build is broadly available, enable invite gate and
  quick-share auto-friend, then enable new-user blocking enrollment. A frozen
  client creating an account after enablement lacks the feature token, remains
  `required=false`, and is never trapped by a flow it cannot render.
- The replacement title PNG is bundled and not server-catalog content, so it
  needs no `testOnly` row. Both platform builds must include it.
- Update App Store privacy answers/privacy policy for explicit real-name
  collection/search discoverability before submission. App Review notes should
  explain the two identities and include the exact Page 1/Page 2 copy/screens.
- No production migration, flag flip, seed, or deploy occurs without explicit
  in-the-moment approval.

## 11. Tests-first plan

### Backend integration tests (write and observe failure before logic)

1. Apple and Google provision matrices cover enrollment flag on/off × feature
   token present/absent, plus existing-user sign-in: only capable+flag-on new
   creates stamp required and an existing row is never restamped.
2. Every new-backend own-user envelope returns safe identity state to old/new
   clients, never returns `discoverableNameSearch`, and keeps legacy fields;
   Redis-on and `REDIS_URL`-unset paths agree.
3. Page 1 accepts supported Unicode names, normalizes whitespace, rejects each
   invalid category, persists no completion stamp, and returns an available
   valid advisory display-name suggestion. Page-1 users remain absent from POST
   identity search. Wrong-type first/last errors use the exact codes.
4. Page 2 atomically updates display name + completion; collision leaves both
   prior display name and completion unchanged; retry suggestion works.
5. Existing `PUT /auth/me/display-name` without the Boolean (and with false)
   retains exact behavior; wrong-type flag gets the new code. Page 1 invalidates
   all auth-me variants; Page 2 invalidates auth-me + cosmetics, verified with
   Redis on and unset.
6. `POST /friends/search` via real HTTP finds by handle/first/last/combined name,
   deduplicates, excludes self/review rows, caps 20, returns only approved fields,
   and asserts the exact SQL rank ordering. An incomplete existing user remains
   findable by handle with no `discoverableName`, but never matches real-name
   input; a completed row matches both. Two-character and 30/minute boundaries,
   31st-request 429/`Retry-After`, per-account isolation, fixed-window reset,
   wrong types, and invalid requests not consuming quota are covered. `GET`
   remains display-name-only. Migration tests verify the decline backfill/check,
   pg_trgm/index predicates, and that production-like `EXPLAIN` uses the indexes.
7. Account deletion removes discoverable-name PII and cascades quota/suppression.
8. Quick-share auto-friend through public HTTP/real DB covers flag off, create,
   reverse pending upgrade, accepted idempotency, declined, suppression (including
   pending+suppression precedence), referral overlap, self-protection, concurrent
   retry, and injected friendship failure rolling back participant. Removal and
   decline rollback tests prove status/deletion and suppression are atomic. Cover
   decline → manual resend → quick-share and referral: both automatic paths stay
   suppressed, while only explicit manual acceptance establishes friendship. Do
   not substitute unit tests for this path.
9. Invite list responses add the exact race/tournament fields with ISO/null
   behavior; response endpoints and frozen-client shapes remain compatible.
   Every authenticated own-user envelope exposes the race-gate flag, and literal
   true/false/absent/malformed parsing selects the specified branch.

Before any backend integration run, print/verify `DATABASE_URL` identifies the
dedicated local `*_test` database. Never run against prod and never use bare
`npm test`; use the single integration suite while diagnosing, then
`npm run test:integration`/`npm run test:unit` for final verification.

### Frontend widget/integration tests (write and observe failure first)

1. Pump the real race detail screen for funded graded, even, top-three, legacy
   buy-in, missing fields, team, invited pending, invited active, night mode,
   small viewport, and 1.3 text scale. Assert hierarchy, compact bound/no
   overflow, correct values, and payout-sheet opening.
2. Pump the real team prize sheet and assert no misleading per-runner full-pool
   payout; long tier list scrolls.
3. Assert yellow/red invite row sits directly below Race Details and works in
   pending/active paths; include the approved team behavior.
4. Assert `Continue` is above reroll, remains disabled during reroll, and no gap
   remains without reroll. Preserve every existing protected reroll assertion.
5. Pump MainShell/RacesTab through tap and partial/full PageView swipe: the opaque
   unverified/checking surface prevents stale pixels/semantics; zero invites
   opens; one blocks; barrier, drag, Android back, and tabs cannot bypass a
   decision; checking/action error can exit Home; multiple invites follow exact
   order; stale epoch results are ignored; leaving/re-entering forces fresh;
   flag-off/old-backend inline fallback remains usable. Literal true enables the
   gate; false, absent, null, and malformed feature-flag values stay unsupported.
6. Assert Races tab contains no invite metric/strip/rows while Home pending invite
   remains in the enabled branch; assert the old-backend/flag-off branch still
   renders today's inline invite treatment.
7. Pump title screen at compact/tall sizes: approved mission copy, no old copy,
   replacement asset fits with no overflow/missing-asset exception.
8. Pump new-user two-page identity flow with provider prefill, availability,
   collision, back/retry/offline/keyboard and completion. Assert health gate is
   not reached first when feature is enabled and unchanged when disabled.
9. Pump Home SETUP for explicit-null/absent/supported/complete states; existing
   display name is preserved and generated-name chip does not compete.
10. Pump Friends search with old/new response shapes; safe missing/null fields,
    completed real-name + race-name row, incomplete handle-only row, and no
    unchecked cast crash. At the real HTTP/service seam, a POST 404 issues no GET,
    clears results, and switches the hint/mode; the next newly entered handle
    query uses legacy GET. POST 400/401/429/500 never downgrade or issue GET.
11. Pump demo/tutorial real screens and update placement expectations without
    deleting existing assertions.

### Final verification

- `flutter analyze` clean.
- Relevant focused Flutter suites pass, then full `flutter test` passes.
- Backend unit + integration suites pass against test DB.
- Both iOS and Android builds are accounted for; if build commands cannot be run,
  report them as skipped rather than claiming done.
- Generated PNG alpha/corners, white composite, icon-size legibility, and asset
  bundle loading are manually verified.
- Required `code-reviewer` runs after combined implementation.

## 12. Interview decisions

Decided by user on 2026-08-11:

1. The marketing mission statement replaces both old title lines.
2. Race and tournament invites are both gated and processed one at a time until
   none remain.
3. Team acceptance auto-assigns the side; the button remains `ACCEPT`.
4. Offline/error users may return Home, but may not reveal Races.
5. Last name is optional; race display names keep the current no-space handle
   rules; search results visibly show real discoverable name above `@RaceName`.
6. Every quick-created race share-link joiner is auto-friended with the creator,
   except when a prior decline/removal suppresses automatic restoration.
7. Superseded by the user's implementation-stage art review: the approved title
   icon is the generated chunky 3D/isometric version of Bara's regular wooden
   mystery box—brown planks, green corner hardware, gold question marks—not the
   earlier cream/dark-reel cabinet concept or the original purple cube.
8. Existing active users with incomplete discoverable-name setup see only the
   non-blocking Home SETUP row and are never forced back into onboarding.

## 13. Acceptance criteria / definition of done

- Items 1-8 above are implemented according to answered decisions with no open
  requirement remaining.
- Race detail and prize sheet are compact, structured, truthful for every payout
  mode, and share one presentation model.
- Invite actions are adjacent to details, one row, yellow/red; the Races tab has
  no inline invite content and its decision gate cannot be accidentally bypassed.
- Continue precedes REROLL ALL without losing ad/reroll safety.
- Title copy is exact and replacement art passes the accessory-art critique loop.
- New users complete understandable name + race-name setup; existing incomplete
  users see Home remediation; Friends search follows the approved privacy rule.
- Approved automatic-friend behavior is proven through a real HTTP/DB integration
  path, not inferred from command unit tests.
- Frozen clients and older backend combinations retain safe behavior.
- Tests-first evidence, clean analysis, platform parity, required manual UI
  checklist, architect review, and code review are all reported honestly.

## 14. Manual UI-placement test plan

**Manual UI-Placement Test Plan — Race experience, invite gate, title, and discoverable identity**

*Elements under test:* Race Details changes from a tall prose stack to a compact scorecard; its payout sheet changes from a loose centered column to a structured, scrollable sheet.

*Elements under test:* Pending race actions move from below participants/team lobby to one side-by-side row immediately below Race Details; the active-invite note moves below that row.

*Elements under test:* Races-tab invite metric, header, and inline rows are removed; a shell-level blocking invite modal appears before normal Races content.

*Elements under test:* Multi-box `Continue` moves from below `REROLL ALL` to directly above it.

*Elements under test:* The title screen’s two tagline blocks become one mission-statement block; the old purple cube is replaced in the same `EARN POWERUPS` feature slot.

*Elements under test:* New-user identity setup adds first/last-name Page 1 before race-name Page 2.

*Elements under test:* Existing users missing identity setup get a first-row Home SETUP prompt opening those same two pages.

*Elements under test:* Friends search results change from one handle line to real name above `@raceName`.

*Checklist*

1. **Start screen — real signed-out screen**
   - **Get there:** Sign out or cold-launch with no saved session.
   - **Verify:** One mission-statement block occupies the former tagline/subtitle area; neither of the two old text blocks remains elsewhere. The replacement box art remains in the middle `EARN POWERUPS` feature slot, and the purple question-mark cube is not duplicated above, below, or in another feature slot.

2. **New-user onboarding — required identity cohort**
   - **Get there:** Sign in on staging with a fresh Apple/Google account whose response explicitly requires discoverable-name onboarding.
   - **Verify:** `HELP FRIENDS FIND YOU` is the first identity page after the provider/referral welcome and before health permission. First name and optional last name are separate fields on this page. Continuing opens `YOUR RACE NAME` as Page 2, with one no-space race-name field and its confirmation action. Back from Page 2 returns to Page 1; the old standalone display-name page does not also appear before or after this pair.

3. **Home remediation — existing incomplete user**
   - **Get there:** Sign in with an existing active staging user whose identity capability is supported and completion value is explicitly null; open Home.
   - **Verify:** `HELP FRIENDS FIND YOU` is the first row inside the existing SETUP board, below Home’s quick-action area and before pending invite/next-race content. The old generated-name/change-name prompt is not also present. Tap `ADD YOUR NAME` and verify Page 1 then Page 2 appear in that order; returning to Home does not move this setup into a popup or global blocker.

4. **Home tab tutorial preview**
   - **Get there:** Profile → Settings/Admin → re-run the tab tutorial; view the first Home spotlight.
   - **Verify:** No discoverable-name SETUP row leaks into the tutorial or pushes the spotlighted Home content downward. No old generated-name row appears there either.

5. **Friends search — real Friends tab**
   - **Get there:** Friends → search for a seeded user with both a discoverable real name and race name.
   - **Verify:** Each result row places the real name as the primary line and `@raceName` directly beneath it, with the avatar still on the left and the row action still on the right. The handle is not also rendered as the only/duplicate primary line.

6. **Races tab — no unresolved invites**
   - **Get there:** Use an account with active and waiting races but no pending invitations; enter Races once by tapping the tab and once by swiping from Home.
   - **Verify:** The header contains exactly two balanced metrics, `ACTIVE` and `WAITING`. There is no `INVITES` metric, invite section header, race-invite row, or tournament-invite row above the state pills. Normal race cards begin after the header/actions and state pills.

7. **Races tab — blocking invite gate**
   - **Get there:** Use a staging account with at least one race invite and one tournament invite; enter Races from another tab.
   - **Verify:** A full-surface gate/loading layer appears before any stale Races list is exposed, followed by one non-dismissible invite modal centered over the gated surface. Accept and decline are in one row in the modal. After each decision, the next invite occupies the same modal position; normal Races content appears only after the last modal is gone. Repeat entry by horizontal swipe to confirm the modal is not limited to bottom-tab taps.

8. **Races tab — initial-load failure**
   - **Get there:** With a pending invite, disable networking before entering Races.
   - **Verify:** The failure surface remains in front of the Races list and places Retry plus exit-to-Home on that surface. No race rows, invite strips, or tab content become visible in the old positions behind it.

9. **Races tab — tab tutorial mirror**
   - **Get there:** Profile → Settings/Admin → re-run tutorial; advance to both Races steps.
   - **Verify:** The preview also has only `ACTIVE` and `WAITING`, with no invite strip or invited race masquerading as a waiting row. The “Race your friends” spotlight still rings the first active race card, and the mystery-box spotlight still rings the inventory box in that card after the removed invite content shifts the list upward.

10. **Pending and active invite race detail — real screens**
    - **Get there:** Deep-link/open a pending non-team invite, then a pending team invite; also open an already-started race where the user remains invited.
    - **Verify:** Each invite shows one side-by-side accept/decline row immediately below the Race Details card. It is absent from its old location below participants or the team lobby. Team invite acceptance is in that same row, with no separate “tap a peg to join” instruction. In the active-invite case, the action row comes first and the “already underway” note immediately follows it; neither action is duplicated below the note.

11. **Compact Race Details and prize sheet — real race detail**
    - **Get there:** Open a funded pending race with graded payouts and tap its prize-pool hero chip; then open a funded team race and tap the chip.
    - **Verify:** Race Details places duration/pool in the top metric row, payout facts in at most two lower columns, optional viewer status on one line, and the payouts affordance at the lower edge. The former prose stack is absent. The sheet orders drag handle/title, one total-pool hero band, one rule callout when applicable, then the payouts section; the old free-floating amount plus separate unit line is absent. On the team sheet, no full-pool per-runner tier is duplicated below the split callout. Scroll a long payout list and verify it remains inside the sheet rather than extending behind the device bottom.

12. **Race-detail demo tutorial mirror**
    - **Get there:** With the funded payout fields enabled in the demo fixture, start/re-run the demo race and reach its real race-detail stage; tap the prize chip during a freely scrollable beat.
    - **Verify:** The funded prize chip remains in the race hero and opens the same structured sheet as production. It is not duplicated in the coach chrome. The coach ring for the clock/powerup tray still surrounds its intended element after any payout-related layout shift.

13. **Race-detail tab-tutorial preview mirror**
    - **Get there:** Re-run the tab tutorial and advance from the Races box step into the real race-detail preview.
    - **Verify:** With funded preview data, the prize chip remains in the hero and no old payout stack appears elsewhere. The `raceDetail.powerups` spotlight still rings the powerup tray rather than the new prize UI or an empty offset.

14. **Multi-box opening — production and demo**
    - **Get there:** On an iOS build containing the reroll ad define, open multiple boxes at once in a real race; then re-run the demo race and use its multi-box open.
    - **Verify:** In production, `Continue` is immediately below the result/activation notes, followed by the reroll control and then its disclaimer; `Continue` is not still below the disclaimer. In the demo, where reroll is unavailable, only `Continue` occupies that action area and there is no empty reroll-sized gap.

*Surfaces confirmed unaffected:* Single-box opening remains unchanged; it already places its continue action before the optional reroll treatment and does not render `MultiCaseOpeningScreen`.

*Surfaces confirmed unaffected:* Demo race invite actions are not a mirror of invited-user actions: `RaceDetailScreen` is opened with `demoMode: true` and its fixture user is already accepted.

*Surfaces confirmed unaffected:* The tab-tutorial race-detail fixture is also active/accepted, so it does not render the pending or active-invite action row.

*Surfaces confirmed unaffected:* The Races-tab gate is owned by `MainShell`; `tutorial_real_screens.dart` constructs `RacesTab` directly, so the tutorial should mirror invite-strip removal but should not present the production entry modal.

*Surfaces confirmed unaffected:* Settings → Edit Display Name remains a direct race-name editor; the new two-page discoverable-name flow is limited to required onboarding and Home remediation.

*Surfaces confirmed unaffected:* Friends search result layout has no currently reachable tutorial mirror: the tab tutorial has no Friends step and its seeded search service always returns an empty list.

*Risks found while planning:*

- `tutorial_preview_data.dart` currently includes `race-invite-1`. Unless removed or deliberately reclassified, it can leak into the tutorial as a waiting race after the dedicated invite strip is deleted.
- `DemoRaceEngine.raceDetails()` and `tutorialPreviewRaceDetail()` currently omit `prizePool` and `payoutTiers`; the redesigned prize UI will be absent from both mirrors unless those fixtures fabricate supported payout data.
- The Home tutorial suppresses SETUP through seeded user data, not a dedicated flag. Adding explicit null completion fields to `TutorialPreviewAuthService` can unexpectedly show the new remediation row and shift Home spotlight anchors.
- Races entry can occur through both bottom-tab taps and `PageView` swipes. A gate attached only to the tab callback will expose the page on swipe.
- `tutorialPotKey` wraps the whole Races header, while `races.card` and `races.box` attach to the first active row. Removing the invite metric/strip changes geometry without compile-time protection; all three anchors need remeasurement.
- The demo’s multi-box flow intentionally omits reroll wiring, and Android normally does not build the reroll control. The new three-element order can only be visually checked on an iOS build with the reroll ad define.
- The Friends tutorial backend returns no search results, so it cannot catch a missing `discoverableName` fixture or broken two-line result placement.
- `DisplayNameScreen` is also launched from Settings. Reusing or refactoring it for onboarding must not accidentally insert first/last-name Page 1 into ordinary Settings race-name editing.

## 15. Revision log

- Initial draft: mapped all eight user items to current frontend/backend code,
  separated referral auto-friend from share-join auto-friend, proposed shared
  payout presentation, and recorded unresolved product/privacy decisions.
- Gap pass 1: added an immutable new-user onboarding cohort bit so existing
  users are never accidentally re-blocked; specified crash/resume behavior;
  added a normalized private search column, parameterized ranked query and
  trigram index plan; and locked valid display-name suggestion derivation for
  Unicode discoverable names.
- Gap pass 2: prevented stale Races content from flashing during swipe entry;
  specified focus/semantics, initial-refresh failure, per-entry vs background
  refresh, old-backend inline-invite fallback, two-metric header, paid/team and
  already-answered invite handling; and added capable real-name search minimum,
  rate-limit, and no-raw-query-logging safeguards.
- User interview round 1: locked copy replacement, both invite types and full
  sequencing, server auto-assigned teams, offline exit to Home, optional last
  name, no-space race handles, visible discoverable names, quick-share
  auto-friend with prior-removal suppression, and cabinet-derived imagegen art.
- User interview round 2: confirmed existing users remain non-blocking and use
  Home SETUP only. No open product questions remain.
- Architect revision: separated contract support, rollout, and cohort enrollment;
  made authenticated identity serialization cache-safe; specified private POST
  name search, quota/index contracts, an epoch-owned opaque invite gate, exact
  invite ordering/payloads, and transactional auto-link suppression.
- UI placement review: added every production/demo/tutorial mirror and coach-mark
  anchor to the implementation and manual verification paths, including funded
  payout fixtures and a real two-line Friends search fixture.
- Post-review gap pass 1: removed stale team-selection/tournament-expiry wording,
  locked handle-vs-real-name query normalization and total ordering, and made
  old-backend POST fallback avoid replaying PII in a GET URL.
- Post-review gap pass 2: made prior-removal suppression authoritative across all
  automatic friendship sources and added referral/manual-request boundary tests.
- Architect re-review revision: preserved handle search for incomplete existing
  users, made decline suppression durable across resend and automatic links,
  pinned the invite flag transport/cache behavior and oldest-first ordering, and
  moved Dart fallback assertions to the frontend HTTP seam.
- Final architect re-review: APPROVE with no remaining required issues or
  suggestions.
- Implementation-stage art review: user rejected the cabinet concept, requested
  the regular wooden race box in the original title icon's 3D format, reviewed
  the generated preview, and explicitly approved it for installation.
