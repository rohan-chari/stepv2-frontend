# Referral Contest — Global Coin-Only Entry and Experience Refresh

Status: **APPROVED FOR IMPLEMENTATION**. The owner explicitly requested the
changes and asked the team to carry the full spec workflow through production
readiness without pausing for another presentation-only approval round.

This document supersedes the eligibility, entry, Home-banner presentation,
contest-detail presentation, and draft-deletion portions of
`docs/referral-giveaway-requirements.md`. Scoring, deterministic ranking,
anti-fraud review, contest lifecycle, and exactly-once coin award behavior from
that document remain authoritative unless changed here.

## 1. Summary and user story

Bara referral contests are free, deterministic competitions whose only prize
is non-transferable Bara coins with no cash value and no redemption path. Any
signed-in Bara account that is permitted to use the app under Bara's existing
Terms may join by reading and accepting the contest rules. The contest does not
ask for age, state, country, residency, ID, tax, or payment information.

As a Bara user, tapping the active contest card first gives me a focused,
scrollable explanation of the prize, contest window, rules, and the exact steps
needed to win. Once I accept, the same route becomes a polished contest hub
where I can see my progress, share my invite, and follow the leaderboard.

As an admin, I can set the short, catchy Home-card message while creating or
editing a draft, and I can permanently delete an unused draft after confirming
the destructive action.

## 2. Current implementation seams

- The current Home card is implemented in
  `lib/widgets/home_giveaway_banner.dart:10-260`; its animated shimmer and
  three-color gradient are specifically removed by this change.
- Home reads the additive `homeGiveawayBanner` field in
  `lib/screens/tabs/home_tab.dart`; that placement below the Home hero and above
  quick actions remains the single contest-banner slot.
- The current detail and entry UI are combined in
  `lib/screens/giveaway_screen.dart:14-888`; the repeated parchment-card stack
  and separate age/residency entry form are replaced.
- Admin contest creation/detail live in
  `lib/screens/admin_giveaway_screen.dart`; banner copy becomes a visible draft
  input and draft detail gains deletion.
- The client HTTP surface is exclusively
  `lib/services/backend_api_service.dart:3660-3865`; the new delete request must
  be added there rather than issuing HTTP from a widget.
- Backend contest entry is currently enforced in
  `src/modules/giveaways/services/giveawayService.js:226-267`, publication
  validation in `src/modules/giveaways/services/validation.js:72-177`, the data
  model in `prisma/schema.prisma:2130-2197`, and active Home copy in
  `src/modules/giveaways/queries/activeContestBanner.js:14-80`.
- Admin routing is in
  `src/modules/giveaways/routes/admin.js:7-38`; there is no delete route today.

## 3. Policy and legal posture

This is a product specification, not legal advice. It follows the current
platform and federal guidance reviewed on 2026-08-25:

- Apple App Review Guidelines 5.3.1–5.3.2 require the app developer to sponsor
  contests and require Official Rules in the app that say Apple is not involved:
  https://developer.apple.com/app-store/review/guidelines/
- Google Play's Real-Money Gambling, Games, and Contests policy still expects
  program terms and selection-method transparency for contest rewards, even
  though this implementation has no real-money prize or paid entry:
  https://support.google.com/googleplay/android-developer/answer/17190352
- FTC COPPA guidance says a general-audience app obtains additional obligations
  when it has actual knowledge it is collecting personal information from a
  child under 13. A child checking “I agree” is not verifiable parental consent:
  https://www.ftc.gov/business-guidance/resources/complying-coppa-frequently-asked-questions
- FTC endorsement guidance can require a clear contest disclosure when a public
  social post is incentivized. V1 keeps social follows/posts optional and gives
  them no scoring advantage:
  https://www.ftc.gov/business-guidance/resources/ftcs-endorsement-guides-what-people-are-asking

### Product conclusions

1. Remove contest-specific U.S. residency, state, 18+, ID, KYC, tax, and payout
   collection. They are unnecessary to deliver non-transferable, nonredeemable
   in-app coins and make entry materially worse.
2. Eligibility is `BARA_ACCOUNT`: the authenticated user row exists,
   `isReviewAccount != true`, the current display name passes Bara's existing
   display-name validator, and no entrant exists for the same contest +
   user/provider-identity HMAC. The contest does not create a new age policy or
   collect birth date. “Account in good standing” and “durable
   disqualification” are not separate invisible gates in v1.
3. Keep versioned Official Rules, explicit selection/tie method, fixed window,
   fixed coin prize, no-purchase language, fraud rules, and Apple/Google
   disclaimers in app. These are platform and truth-in-advertising safeguards,
   not cash-payout paperwork.
4. Sponsor display is standardized as **Bara**, the app/developer brand. No
   mailing-address field appears in the admin flow or customer UI. This does
   not replace any legal identity/contact disclosure Bara's global Terms or
   privacy policy independently requires.
5. Bara coins must remain non-transferable, non-sellable, non-withdrawable,
   nonredeemable for money or external goods, and not described with a dollar
   value. Entry and scoring cannot depend on IAP, subscriptions, ads, reviews,
   social follows, or social posts.
6. If Bara knowingly permits users under 13 or markets the app to children, a
   product-wide COPPA review is required outside this feature. The contest must
   not pretend that a checkbox solves that broader issue.

## 4. Scope and non-goals

### In scope

- Global, coin-only contest defaults for newly created contests.
- Rules-only entry acceptance for signed-in Bara users.
- Standard server-owned Official Rules with dates/prize interpolated safely.
- Configurable short Home-card message on create/edit draft.
- Solid, non-shimmer Home card using the configured message.
- Dedicated pre-entry rules/instructions experience and polished joined hub.
- Hard deletion of draft contests through an idempotent admin endpoint.
- Defensive compatibility for the already-shipped `US_18` contest shape.
- iOS and Android implementation and tests in lockstep.

### Non-goals

- Cash, gift cards, crypto, merchandise, or any externally valuable prize.
- Random selection, chance, sweepstakes, raffles, wagering, or paid entry.
- New account-age collection, parental-consent flow, KYC, location checks, or
  identity-document upload.
- Public-post/follow requirements or extra points for social actions.
- Changing completed-referral qualification or the ordinary 5-per-24-hour and
  25-per-30-day referral review holds. Contest review may strengthen, but never
  bypass or auto-approve, those controls.
- Changing the base rank order: highest verified count, then earliest time
  reaching that count, then stable entrant UUID ascending.
- Hard deletion of a published, cancelled, final, or archived contest. Those
  records retain their canonical rules and audit history; lifecycle controls
  remain cancel/archive.
- A runtime release flag, kill switch, or rollout percentage.

## 5. Standard rules and customer flow

### 5.1 Server-owned standard rules

New `BARA_ACCOUNT` contests do not accept arbitrary rules or sponsor fields
from the normal admin creation form. The backend generates and hashes these
sections from stored structured facts:

1. **Who can join** — any signed-in Bara user permitted under Bara's Terms; one
   entry per Bara account/provider identity; no purchase necessary. Duplicate
   accounts controlled by one person are subject to fraud review.
2. **Contest window** — exact UTC start/end and local display; referrals count
   only when they qualify after the entrant joins and within
   `[startsAt, endsAt)`.
3. **How to win** — join and accept; share the unique Bara invite; the friend
   signs up with it; the friend completes a qualifying race with another real
   player during the window; highest verified completed-referral count wins.
4. **Prize** — fixed configured coin amount; no cash value; cannot be sold,
   transferred, withdrawn, or redeemed outside Bara.
5. **Ranking and review** — leaderboard is provisional before final review;
   ties go first to the entrant who earliest reached the final verified count,
   then stable entrant ID as the deterministic fallback; if nobody has a
   verified completed referral there is no winner. Bots, self-referrals,
   duplicates, and dummy-account coordination are disallowed.
6. **Platforms and sponsor** — sponsored by Bara; Apple and Google are not
   sponsors, administrators, endorsers, or involved in the contest.

Rules versions are `bara-account-v1-` plus the first 24 lowercase hex characters
of SHA-256 over canonical JSON containing exactly `slug`, `title`, UTC
`startsAt`, UTC `endsAt`, `coinPrize`, `eligibilityMode`, and standard-template
version. The full SHA-256 over the generated rules payload remains `rulesHash`.
Any draft edit to one of those material facts regenerates both values;
`bannerMessage` does not. Publication freezes them.

### 5.2 First visit / not joined

Tapping Home **VIEW** or the Invite Friends contest card opens the same route.
After loading authenticated contest data, an `ACTION_REQUIRED` entrant sees:

1. a compact checker-roof header with Back and the contest title;
2. a prize/date hero using the exact configured coin amount and window;
3. a numbered **How to win** trail (the five steps in §5.1);
4. the complete standard Official Rules, including selection/tie and platform
   disclaimers, in the same scroll view;
5. a thin progress marker that reflects how far through the document the user
   has read;
6. a safe-area-aware sticky footer with one checkbox, “I agree to the contest
   rules,” and **JOIN CONTEST**.

The Join button is enabled only after the content has been scrolled to the end
and the checkbox is selected. No state picker, residency checkbox, age checkbox,
display-name confirmation, KYC, or ID request appears. The user's current Bara
display name is snapshotted server-side on join and described in the rules. If
none exists, the screen shows **SET DISPLAY NAME TO JOIN**, pushes the existing
`DisplayNameScreen`, and reloads this contest when that route returns; the
backend also returns `409 DISPLAY_NAME_REQUIRED` as the authoritative guard.

Scheduled contests show the same readable rules but replace Join with the exact
opening time. Ended/cancelled contests never offer Join.

### 5.3 Joined contest hub

After a successful join, the route transitions in place to a polished hub:

- status/remaining-time header and an editorial prize plaque;
- a single progress module pairing “Your verified referrals” with provisional
  rank, so score and place read as one fact rather than unrelated cards;
- a dominant **SHARE YOUR INVITE** action and one-sentence next-step copy;
- a compact top leaderboard with the current entrant pinned when outside it;
- a collapsible “What counts?” explanation;
- **OFFICIAL RULES** and optional social links at the end. Social links say
  “Optional — does not affect the contest.”

Loading uses the existing skeleton language. On load failure, ranking and Join
are hidden, Retry is offered, and only immutable rules loaded successfully by
this same screen instance may remain readable. Empty leaderboard copy tells
the entrant to share; it does not imply an error. Final/verification states keep
the same structure and replace action copy appropriately.

### 5.4 Mandatory contest fraud review

This policy applies only when `eligibilityMode == "BARA_ACCOUNT"`; historical
`US_18` contests retain the settlement policy frozen with their published
rules. Before global finalization, derive the outcome-relevant set as the current provisional
leader plus every entrant whose verified points plus unresolved reviewable
points can tie or overtake that leader. For that set, a qualifying fact requires
an explicit `GiveawayPointReview` approve/reject decision when it is already
held by the ordinary 5/24-hour or 25/30-day review system, or when evidence shows
any of:

- two or more of one entrant's referrals qualifying in the same race;
- a rapid qualification burst (two or more within 60 minutes);
- shared source-device evidence;
- synchronized-step evidence;
- repeated/deleted provider-identity evidence; or
- shared qualifying-race or network evidence.

These signals trigger review and are never automatic rejection. Rejected facts
do not count; approved facts keep their original qualification time. Recompute
the outcome-relevant set after each decision and block finalization with
`409 OUTCOME_REVIEW_REQUIRED` until no implicated fact in the set is unresolved.
Contest settlement never auto-approves or bypasses an ordinary referral hold.

The implicated referral-fact ID set is deterministic:

- ordinary hold: that `FLAGGED` fact ID;
- same-race cluster: every fact for the entrant sharing a non-null
  `qualifyingRaceId` whose entrant-local count is at least two;
- rapid cluster: the union of every fact participating in any closed 60-minute
  entrant-local window containing at least two facts;
- shared device: every fact whose referee user has a contest-window step sample
  with a `sourceDeviceId` used by at least two distinct referees in that
  entrant's facts;
- synchronized steps: every fact whose referee user participates in a
  `(periodStart, steps)` signature shared by at least two distinct referees in
  that entrant's facts;
- repeated/deleted identity: every fact in a repeated
  `refereeIdentityHash` group plus every fact whose snapshotted referee user is
  deleted/null;
- referrer-in-race: each fact whose qualifying race contains the entrant's own
  accepted participant row; and
- shared network: all of the entrant's facts when two or more contest-window
  referral link opens for that entrant's code share an exact or network HMAC.

Candidate review and finalization derive facts, correlation evidence, and prior
`GiveawayPointReview` decisions from Postgres in the same authoritative flow,
never Redis. Finalization may not use the candidate UI's 100-fact/500-sample
display caps. If evidence cannot be read completely, it fails closed with
`409 REVIEW_EVIDENCE_INCOMPLETE`.

## 6. Visual direction

### 6.1 Design thesis

The contest is a **Bara trail challenge**, not a casino promotion and not a
generic admin dashboard. It borrows the checker roof, trail signs, game-piece
depth, strong outlined typography, and compact information density already used
by Home, race, race-detail, and health-permission onboarding. The aesthetic is
playful editorial: one memorable “route to 5,000 coins” trail, surrounded by
quiet, disciplined surfaces.

### 6.2 Token plan

- `Trail Ink` — existing `textDark`/wood-dark for type and hard borders.
- `Checkpoint Gold` — existing `pillGold` for the one prize/progress accent.
- `Roof Terra` — existing roof tone for header continuity.
- `Parchment` — existing parchment for readable rules and leaderboard body.
- `Success Leaf` — existing positive green only for joined/completed states.
- Typography uses existing `PixelText.title` for display/utility moments and
  `PixelText.body` for readable rules. No new font dependency is introduced.

### 6.3 Layout sketches

Pre-entry:

```text
┌ checker header: Back · CONTEST ┐
│  5,000 COINS                   │
│  Aug 25 — Sep 25              │
├ ROUTE TO THE PRIZE ────────────┤
│ ① Join   ② Share   ③ Signup   │
│ ④ Friend finishes race        │
│ ⑤ Most verified referrals wins│
├ OFFICIAL RULES ────────────────┤
│ readable sections…            │
│ [scroll progress]             │
├ sticky safe-area footer ───────┤
│ □ I agree   [JOIN CONTEST]     │
└────────────────────────────────┘
```

Joined hub:

```text
┌ checker header + status ───────┐
│ CONTEST TRAIL      18D LEFT    │
│ 5,000 COINS                    │
├ YOUR RUN ──────────────────────┤
│  7 verified          #3       │
│  [ SHARE YOUR INVITE ]         │
├ LEADERS ───────────────────────┤
│ #1 Name  10  #2 Name 8 …      │
├ What counts? ▾                 │
│ Official rules · socials       │
└────────────────────────────────┘
```

### 6.4 Home card

The Home card is a compact solid game-piece with one hard shadow and no
gradient, shimmer, sweeping highlight, pulse, or ambient animation. The
configured `bannerMessage` is the visual headline. A small utility row shows
formatted coin prize and remaining time; **VIEW** is the explicit action. The
card grows vertically for text scaling and uses a bounded two/three-line
headline rather than clipping critical copy.

## 7. Data model and migrations

Add one backward-compatible migration:

```prisma
model GiveawayContest {
  eligibilityMode String @default("US_18") @map("eligibility_mode")
  minimumAge        Int?
  eligibleCountries Json?
  eligibleRegions   Json?
  // existing bannerMessage remains the configurable Home headline
}

model GiveawayEntrant {
  country              String?
  region               String?
  ageConfirmedAt       DateTime?
  residencyConfirmedAt DateTime?
}
```

The SQL migration adds `eligibility_mode TEXT NOT NULL DEFAULT 'US_18'`, drops
`NOT NULL` from all seven legacy contest/entrant eligibility columns, and drops
the `18` / `["US"]` defaults from `minimum_age` and `eligible_countries` so a
new compact global create cannot silently inherit false values. The old backend
remains rolling-deploy safe because its legacy create/entry paths explicitly
supply every old value.

- Existing contests backfill/default to `US_18`; their frozen rules and entry
  behavior do not change during deployment.
- Newly created contests from the refreshed admin use `BARA_ACCOUNT`.
- New global rows store `minimumAge`, `eligibleCountries`, and
  `eligibleRegions` as SQL `NULL`; they never invent U.S./18 values to satisfy
  a legacy schema.
- Nullability is additive and safe for an old backend during a rolling deploy;
  old code continues writing non-null values.
- Existing sponsor/rules columns remain for mixed versions and historical
  records. New global contests store standardized `{ "name": "Bara" }` sponsor
  JSON and generated sections/hash.
- No entrant rows are rewritten. No production contest is silently converted
  from `US_18` after publication.

## 8. API contract

All contest responses remain defensive/additive. Unknown response fields are
ignored. Global contest discovery is permanently capability-bound to
`referral_contest_global_v1`; this is a version contract, not a rollout flag.

### 8.1 Public/member contest shape

For a new global contest, the contest object includes:

```json
{
  "slug": "september-trail",
  "title": "September Referral Trail",
  "status": "ACTIVE",
  "startsAt": "2026-09-01T04:00:00.000Z",
  "endsAt": "2026-10-01T04:00:00.000Z",
  "governingTimeZone": "UTC",
  "prize": { "coins": 5000 },
  "eligibility": {
    "mode": "BARA_ACCOUNT",
    "summary": "Open to signed-in Bara users."
  },
  "sponsor": { "name": "Bara" },
  "rules": {
    "version": "bara-account-v1-0123456789abcdef01234567",
    "sha256": "...",
    "sections": [{ "heading": "Who can join", "body": "..." }]
  },
  "socialLinks": []
}
```

For historical `US_18` contests, the existing `minimumAge`,
`eligibleCountries`, `eligibleRegions`, and sponsor shape remain unchanged; no
new nested eligibility field is required in that legacy response. New clients
infer `US_18` only when the complete strict legacy shape is present. The
canonical HTML landing and rules renderers branch on `eligibilityMode` and use
the same generated rules as JSON. Global pages contain no U.S., age, cash,
payout, or mailing-address claim; legacy pages retain their material terms.

### 8.2 Enter contest

`POST /giveaways/:slug/entries`

New request:

```json
{ "rulesVersion": "bara-account-v1-0123456789abcdef01234567", "rulesAccepted": true }
```

Success `201` (or `200` for an exact retry):

```json
{
  "entry": {
    "status": "ELIGIBLE",
    "acceptedAt": "2026-09-01T12:00:00.000Z",
    "displayName": "TrailBara",
    "rulesVersion": "bara-account-v1-0123456789abcdef01234567"
  }
}
```

The backend ignores no unknown keys. It accepts the exact new shape for
`BARA_ACCOUNT` and retains the exact legacy request/validation path for
historical `US_18` contests. Errors:

- `400 INVALID_BODY` — unknown/malformed fields.
- `400 RULES_ACCEPTANCE_REQUIRED` — acceptance is not exactly `true`.
- `409 RULES_CHANGED` — supplied version is stale; include current version.
- `409 CONTEST_NOT_OPEN` — scheduled, ended, cancelled, final, or archived.
- `409 ENTRY_IMMUTABLE` — a non-identical prior entry exists.
- `409 ENTRY_INELIGIBLE` — review account.
- `409 DISPLAY_NAME_REQUIRED` — missing/invalid current Bara display name.

Entry is concurrency-idempotent. If two identical requests race and the losing
insert receives Prisma `P2002`, the service re-reads by contest + user/provider
identity, compares rules version/hash and immutable acceptance facts, and
returns the same entry with `200` for an exact match; otherwise it returns
`409 ENTRY_IMMUTABLE`.

### 8.3 Home payload

`GET /home/race-card` keeps its additive `homeGiveawayBanner` field and adds
the validated configured message:

```json
{
  "homeGiveawayBanner": {
    "type": "referral_contest",
    "contestSlug": "september-trail",
    "title": "September Referral Trail",
    "message": "Bring your crew. The referral trail is open.",
    "status": "ACTIVE",
    "endsAt": "2026-10-01T04:00:00.000Z",
    "coinPrize": 5000
  }
}
```

`message` is required for the refreshed UI, trimmed UTF-8 text of 12–96
characters, with no control/newline characters and no cash/currency/redemption
claims (`$`, `USD`, `cash`, `money`, `Venmo`, `PayPal`, `Cash App`, `withdraw`,
`redeem`). Filtering applies NFKC Unicode normalization plus case-insensitive
matching. These restrictions apply only to new `BARA_ACCOUNT` copy; frozen
legacy `US_18` copy keeps its existing validation. Invalid cached/DB data omits
the automatic banner; Home itself never fails. Both Home response assembly
paths must return the same field.

For a global contest, Home returns the banner only when the request advertises
both `referral_contest_v1` and `referral_contest_global_v1`. The authenticated
`/giveaways/current/me` route likewise returns the standard no-current shape
(`contest:null`, empty leaderboard, null entry/standing/share) unless the
global token is present. Historical `US_18` discovery keeps the existing
`referral_contest_v1` contract.

The Redis value remains `v1:home:giveaway-banner:active` with a 15-second TTL
and Postgres-on-miss/failure behavior; `eligibilityMode` and `message` join its
validated allowlist. The maximum stale window is 15 seconds. Publish, cancel,
finalize, archive, and published banner-correction invalidate it. Draft
edit/delete need no invalidation because drafts cannot populate the key.
Integration tests cover local Redis DB 15 and `REDIS_URL` unset.

### 8.4 Admin create/edit

The refreshed normal create body is:

```json
{
  "slug": "september-trail",
  "title": "September Referral Trail",
  "startsAt": "2026-09-01T04:00:00.000Z",
  "endsAt": "2026-10-01T04:00:00.000Z",
  "coinPrize": 5000,
  "bannerMessage": "Bring your crew. The referral trail is open.",
  "eligibilityMode": "BARA_ACCOUNT"
}
```

The backend assigns UTC governing timezone, zero cash, sponsor Bara, standard
rules/version/hash, and empty social links. `PATCH /admin/giveaways/:id` keeps
`{ "revision": N, "patch": { ...same editable fields... } }` for drafts and
regenerates standard rules after any material edit. Legacy full create bodies
remain accepted as `US_18` compatibility input; the new dashboard never sends
them. Compatibility input must also be coin-only (`cashMinor:0`); historical
published rows with cash remain readable but no new or draft contest containing
cash can publish.

The full admin response is mode-discriminated. A global row returns top-level
`eligibilityMode:"BARA_ACCOUNT"`, `minimumAge:null`,
`eligibleCountries:null`, `eligibleRegions:null`, `sponsor:{"name":"Bara"}`,
generated `rules`, and the existing lifecycle/count/timestamp fields. A legacy
row returns `eligibilityMode:"US_18"` plus its existing non-null legacy fields
and sponsor. Eligibility mode cannot change after create, even in draft.

Admin global data is capability-bound too. Without
`referral_contest_global_v1`, `GET /admin/giveaways` filters out global rows and
direct global detail/candidate/mutation requests return `404 CONTEST_NOT_FOUND`.
This prevents one unsupported global row from making a frozen admin client's
strict all-or-nothing list parser fail. With the token, list/detail return both
modes.

Global `PATCH` allows exactly `slug`, `title`, `startsAt`, `endsAt`,
`coinPrize`, and `bannerMessage`; every material field except `bannerMessage`
regenerates standard rules/version/hash.
It rejects `eligibilityMode`, `cashCurrency`, `cashMinor`, `minimumAge`,
`eligibleRegions`, `eligibleCountries`, `sponsor`, `rules`, and `socialLinks`.

Validation:

- title 1–120 characters; slug existing 1–80 lowercase-kebab rule;
- `startsAt < endsAt`; coin prize integer 1–25,000 (default 5,000); any higher
  amount requires a new economy review and code/spec change;
- banner validation from §8.3;
- global publication requires coin-only prize, `BARA_ACCOUNT`, generated
  unmodified standard rules, sponsor Bara, valid banner, future end, and all
  existing lifecycle invariants;
- legacy coin-only `US_18` create/PATCH/publish retains its current exact
  contract for frozen admin clients. New dashboard code never creates it.

### 8.5 Delete draft

`DELETE /admin/giveaways/:id`

Headers: `Authorization`, `Idempotency-Key: <UUIDv4>`

Request:

```json
{ "revision": 3 }
```

Success `200` and exact replay:

```json
{
  "deleted": {
    "id": "contest-uuid",
    "slug": "september-trail",
    "lifecycleStatus": "DRAFT"
  }
}
```

Implement the domain command in
`src/modules/giveaways/commands/deleteDraftContest.js`, called by a thin
dependency-injected route. Reuse/extract the existing independent
idempotency-receipt mechanism—do not create a second receipt algorithm. The
transaction locks the contest, verifies revision and `DRAFT`, verifies no
entrants, results, fulfillments, or point-review facts, and deletes the contest.
Only dependent draft audit rows may cascade; the independent receipt preserves
replay. Errors:

- `404 CONTEST_NOT_FOUND` — unknown id on a new key.
- `409 REVISION_CONFLICT` — stale revision.
- `409 CONTEST_DELETE_NOT_ALLOWED` — lifecycle is not `DRAFT` or dependent
  participation/result facts exist.
- existing idempotency errors retain their current contract.

## 9. Frontend implementation plan

1. Update `GiveawayContest`, `GiveawayEntry`, and admin DTOs to parse
   `eligibility.mode` and the global shape defensively while retaining legacy
   `US_18` parsing. Missing/malformed global fields hide only the contest.
2. Add the delete service method to the single API surface. The client creates
   one UUID per intended deletion and retains/reuses it after an ambiguous
   transport failure until a definitive response or changed body.
3. Replace Home banner animation/gradient code with a stateless solid card and
   parse `message` defensively (12–96 characters and valid contest facts).
4. Split `GiveawayScreen` presentation by entry state into focused private
   widgets or files: pre-entry rules journey and joined contest hub. Keep the
   route and network owner shared so a successful Join transitions without a
   route stack glitch.
5. Remove age/residency/state/display-name confirmation controls for
   `BARA_ACCOUNT`; retain a compatibility rendering path only for historical
   `US_18` contests.
6. Update the admin draft form to show title, dates, coin amount, and required
   Home-card message. Explain “Shown as the headline on Home” with a character
   counter and inline prohibited-value validation.
7. Add a DRAFT-only delete action on admin detail/list, confirmation dialog
   naming the contest, in-flight disabling, success pop/reload, and precise
   conflict/retry copy.
8. Preserve tutorial suppression in `HomeTab` and every shared ReferralScreen
   entry path.
9. Add `referral_contest_global_v1` to both duplicated feature-header branches.
10. Limit stale-rules fallback to rules loaded successfully by the current
    `GiveawayScreen` instance. A source route supplies no expected hash, so the
    old process-wide “any hash sharing this slug” cache is removed.

## 10. Backward compatibility and rollout

1. Apply the additive/nullability migration, deploy backend, then release iOS
   and Android together.
2. Existing `US_18` contests and entrants remain readable and enforce their
   frozen rules. No migration rewrites a published contest's eligibility.
3. New clients understand both eligibility modes and advertise
   `referral_contest_global_v1`. Frozen old clients receive no global Home/member
   discovery from the backend and cannot show false residency copy.
4. The entry endpoint retains legacy request handling for old contests. New
   request keys are not required for those clients.
5. `message` is additive in Home. Frozen clients ignore it and keep their
   existing behavior; refreshed clients require it before rendering the new
   card.
6. Draft delete is a new admin-only endpoint; old admin clients are unaffected.
7. No runtime flag is added. Eligibility mode is immutable published contest
   data, not an operational toggle.
8. The currently published production contest is not silently transformed. To
   use the global flow, an operator must create/publish a new `BARA_ACCOUNT`
   draft through the refreshed dashboard after the backend deploy.
9. Once a global contest is published, do not roll the backend back to a build
   whose HTML/service layer does not understand `eligibilityMode`. Forward-fix
   it, or cancel/archive the global contest before rollback.
10. Operators wait until both production HTTP workers report the new commit
    before creating or publishing the first global contest.

## 11. Tests-first plan

### Backend integration tests (dedicated `*_test` Postgres only)

Write and observe these fail before business logic:

1. Create a `BARA_ACCOUNT` draft with the compact body; assert standardized
   zero-cash sponsor/rules/eligibility and persisted configurable banner copy.
2. Reject missing/prohibited/too-long banner copy and publish if stored copy or
   generated rules are malformed.
3. Enter a live global contest with only rules version + acceptance; assert no
   age/country/region data is required or stored and exact retry is idempotent.
4. Reject false acceptance, stale rules, review account, pre-start/post-end,
   and unknown body fields through real HTTP.
5. Prove a historical `US_18` contest still accepts its legacy request and
   serializes legacy eligibility.
6. Assert `/current/me`, public data, and both Home response paths expose the
   global eligibility/configured message without cash or false U.S./18 copy.
7. Delete a draft through real HTTP; assert row/cascades disappear, list/detail
   return absent, exact key replays, reused key mismatch conflicts, and stale
   revision/non-draft/dependent-fact deletion is rejected.
8. Assert draft editing/deletion does not invalidate the active-banner cache,
   while publish/cancel/finalize/archive/banner-correction still does
   (published contests remain undeletable).
9. Existing ranking, referral qualification, finalization, and exactly-once
   coin-award integration suites stay green.
10. Two simultaneous identical global joins produce one entrant plus equivalent
    `201/200` payloads; a mismatched loser returns `ENTRY_IMMUTABLE` rather than
    leaking a Prisma error.
11. Old-token requests against a global contest receive no Home/member
    promotion; new-token requests receive it; U.S./18 old-token bytes and entry
    behavior remain compatible. Test mixed old-code/new-schema writes.
12. Global HTML/rules pages contain no U.S./18/cash/address copy and legacy
    HTML remains unchanged in material terms.
13. In a global contest, create high-risk same-race, rapid-burst, shared-source-device,
    synchronized-step, and repeated-identity facts. Assert finalization blocks
    until all implicated facts for the provisional leader and every entrant
    who could tie/overtake are explicitly approved/rejected. Shared race/network
    alone triggers review but never automatic rejection; existing 5/24h and
    25/30d holds remain unresolved until ordinary review resolves them.
14. Prove the same evidence does not retroactively change a published legacy
    `US_18` finalization policy, and prove old-token admin list/detail/mutations
    omit global rows while new-token admin requests receive both modes.

Unit tests are allowed only for banner string validation and deterministic
standard-rule hashing because those properties have large pure input matrices;
they do not replace the HTTP integration coverage.

### Frontend widget tests

Write and observe these fail before UI/business logic:

1. Home renders configured message, prize, countdown, and View on a solid card;
   source/widget assertions prove no `Gradient`, shimmer layer,
   `AnimationController`, or motion semantics remain.
2. Malformed/missing message or contest facts hide only the Home card; tutorial
   preview remains banner-free; tap opens the matching contest.
3. A global `ACTION_REQUIRED` user sees the numbered how-to and full rules, no
   age/state/residency/ID controls, and cannot Join until scrolled to end plus
   checked.
4. Joining sends the exact two-field request and transitions to the joined hub;
   stale-rules and network errors preserve user position and explain recovery.
5. Joined hub renders verified count/rank, pinned leaderboard row, share action,
   what-counts expansion, final/verifying/empty states, and social disclaimer.
6. Text scale, narrow viewport, keyboard, SafeArea, screen-reader semantics, and
   reduced-motion behavior have focused widget coverage where expressible.
7. Admin create/edit requires and previews the banner message; published
   records remain immutable.
8. Draft detail shows Delete, confirmation cancel does nothing, confirm sends
   the exact revision/key request once, and success removes it from the list.
   Non-draft detail never shows hard Delete.
9. Historical `US_18` fixtures remain defensively parseable; malformed global
   shapes hide without crashing.
10. Both feature-header branches advertise `referral_contest_global_v1`; a
    simulated old backend missing global fields hides the module without
    disturbing Home/referrals.
11. An ambiguous delete transport failure retains the same UUID for Retry; a
    changed/new deletion intent generates a new UUID.

## 12. Acceptance criteria and definition of done

- Any eligible signed-in Bara account can join a new global contest without
  contest-specific age, location, residency, ID, KYC, or payment prompts.
- Join is impossible until the user reaches the end of the rules and explicitly
  accepts the current version.
- In-app rules identify the deterministic winner method, fixed window/prize,
  no-purchase terms, coin restrictions, sponsor Bara, and Apple/Google
  non-involvement.
- Home uses the admin-configured catchy message and contains no gradient,
  shimmer, pulse, or ambient animation.
- The contest route clearly differs before/after joining and visually matches
  Bara's established Home/race/onboarding language rather than a generic card
  stack.
- Admins can hard-delete drafts only, with revision/idempotency protection and
  clear confirmation.
- Existing published `US_18` data is not rewritten or made inconsistent.
- Tests were added before logic, protected tests remain intact, backend
  integration tests use a dedicated test database, `flutter analyze` is clean,
  full relevant suites pass, and production iOS/Android builds both succeed.
- Architect, game-economy, UI-placement, and combined code reviews have no open
  blockers.
- Backend is committed/pushed and ready to deploy, but production is not
  touched without a new explicit in-the-moment deployment instruction.

## 13. Manual UI-placement test plan

**Manual UI-Placement Test Plan — Referral contest experience refresh**

*Elements under test:*

- The active-contest Home card stays in the single slot below the Home hero and above quick actions; its configured message becomes the headline, with prize/time beneath and **VIEW** as the action.
- The pre-entry contest route replaces the old mixed detail/eligibility stack with one ordered scroll: checker header, prize/window hero, numbered how-to trail, inline Official Rules, scroll marker, and a sticky acceptance footer.
- The joined contest route replaces the old repeated-card stack with an ordered hub: status/prize header, combined score-and-rank module, share action, leaderboard, “What counts?”, then rules/social links.
- The Invite Friends contest card remains once above **YOUR INVITES** and opens the same contest route from every live ReferralScreen entry path.
- The admin draft form adds the Home-card message field to the main form and removes the old U.S./18/sponsor-address block.
- Draft contest editing adds a separated destructive **DELETE DRAFT** action and a named confirmation dialog; non-draft contests have no hard-delete action.

*Checklist*

1. **Surface: Home tab — real screen**
   - **Get there:** Sign in with an account while a published active global contest exists → Home.
   - **Verify:** Exactly one contest card appears immediately below the Home hero and before the quick-actions row. Its internal order is configured headline, coin prize/remaining-time utility row, then **VIEW**. The old animated/title-led contest card is not also present, and the legacy service banner is not duplicated in the same slot.

2. **Surface: Home tab — tab tutorial preview**
   - **Get there:** Profile → admin/debug tutorial control → re-run the tab tutorial → Home preview.
   - **Verify:** No contest card or empty contest-sized gap appears between the hero and quick actions. The milestones/shop spotlight targets remain in their existing positions and do not ring a displaced element.

3. **Surface: Invite Friends — shared real ReferralScreen**
   - **Get there:** Check the same account through each quick path: Friends → **INVITE FRIENDS & EARN COINS**; Home coin balance **+** → Get Coins → **SHARE INVITE LINK**; and, with Home in its empty-races state, Home → Races card → **INVITE**.
   - **Verify:** Every path opens the same Invite Friends screen. The contest card appears exactly once after the share/code area and before **YOUR INVITES**; it is not duplicated above the share action or below the invite list. **VIEW CONTEST** opens the same contest route from all three paths.

4. **Surface: Friends tab — tab tutorial preview**
   - **Get there:** Re-run the tab tutorial → advance to the Friends invite step.
   - **Verify:** The spotlight still rings **INVITE FRIENDS & EARN COINS** in its existing position. No contest card appears directly on the Friends preview, and tapping/advancing the tutorial does not expose a live ReferralScreen or contest route over the tutorial.

5. **Surface: Contest route — not joined / active**
   - **Get there:** Use a signed-in account that has not joined the active contest → Home contest card **VIEW**.
   - **Verify:** From top to bottom there is one checker header with Back/title, one prize-and-window hero, the numbered how-to trail, and the complete Official Rules in the same scroll. The thin read-progress marker sits immediately above the sticky footer. The footer remains pinned above the device safe area while the document scrolls and contains only the agreement checkbox and **JOIN CONTEST**. The old standalone eligibility card/form, age checkbox, residency checkbox, state picker, display-name confirmation, and separate rules-page detour are absent.

6. **Surface: Contest route — joined hub**
   - **Get there:** Open the same contest with an already joined account, or complete Join and remain on the route.
   - **Verify:** The route changes in place without stacking a second contest screen. From top to bottom it shows status/prize, one combined verified-referrals-and-rank module, **SHARE YOUR INVITE**, the leaderboard, collapsible **What counts?**, then **OFFICIAL RULES** and any optional social links. Score and rank are not repeated as separate old cards, and no entry footer or legacy eligibility form remains.

7. **Surface: Contest route — narrow device / large text**
   - **Get there:** Repeat the not-joined and joined checks on the smallest supported phone with system text size increased.
   - **Verify:** The pre-entry sticky footer stays above the home indicator and does not cover the final rules lines or progress marker. Header, how-to steps, joined score/rank module, leaderboard rows, and share action remain in their intended order without horizontal clipping or overlapping adjacent sections.

8. **Surface: Admin contest create/edit**
   - **Get there:** Profile → Admin → Config → **GIVEAWAY DASHBOARD** → **CREATE CONTEST**; then open an existing draft to edit it.
   - **Verify:** The Home-card message field is visible in the main draft form alongside title, dates, and coin prize, with its helper/counter attached to that field; it is not hidden in an advanced/legal section. The old **18+ · United States only**, sponsor legal-name, and sponsor mailing-address controls are absent. Save and Publish remain at the bottom and are not duplicated.

9. **Surface: Admin draft deletion**
   - **Get there:** Giveaway Dashboard → open a draft with no entrants/results.
   - **Verify:** A visually separated **DELETE DRAFT** action appears after the normal draft actions, not among editable fields. Tapping it opens one confirmation dialog naming that contest, with Cancel and destructive confirm actions; no duplicate dialog/action remains after dismissal. Return to the dashboard and open a published, cancelled, final, or archived contest: no **DELETE DRAFT** action appears anywhere on its detail screen or list card.

*Surfaces confirmed unaffected:*

- Demo race tutorial and race-detail tutorial preview — grep confirms neither renders HomeGiveawayBanner, ReferralScreen, GiveawayScreen, or admin giveaway UI.
- Races, Boards, and Profile tab/tutorial content — no contest-experience element is hosted there; the hand-forked tutorial tab bar order and indices are unchanged.
- Create Race, Race Invite, case-opening, race-results, effect-tray, and inventory mirrors — no changed contest widget or placement reference is present.
- Admin dashboard’s compact and sectioned Config layouts — both route to the same AdminGiveawayScreen, so the giveaway form/detail is shared rather than hand-forked.
- GiveawayScreen itself has no demo/tutorial copy — Home and ReferralScreen both push the same production route.

*Risks found while planning:*

- Home tutorial suppression currently depends on both `HomeTab.isTutorialPreview` and fixture data without `homeGiveawayBanner`; keep the explicit suppression so future fixture additions cannot shift tutorial anchors.
- Friends tutorial renders the real FriendsTab, whose invite button currently pushes a live ReferralScreen and carries the `profile.invite` spotlight key. The refreshed implementation must prevent that tutorial tap from escaping while leaving the spotlight attached to the same button.
- ReferralScreen has three live callers—Home empty-races **INVITE**, Friends, and Get Coins—but no mirrored implementation. Change the shared screen once and verify all callers rather than adding caller-specific contest cards.
- A valid Home contest already suppresses the legacy service banner. The new message-based card must retain that single-slot precedence or two promotions can occupy the same location.
- The current contest route sends Official Rules to a separate screen and keeps entry controls lower in the main scroll. The refresh must remove that duplicate route from pre-entry and keep the complete rules above the sticky footer.
- Draft detail currently returns the draft form directly, while non-draft detail uses a separate screen. Place deletion inside the draft editor/detail path only; adding it to the non-draft detail action stack would leak hard delete to immutable contests.
- The sticky footer, inline rules, and progress marker share vertical space on small devices; the scroll view needs bottom inset equal to the footer so the final rules content is not hidden.

## 14. Revision log

- **Draft / exploration:** located the existing Home animation, combined
  entry/detail screen, strict client DTOs, admin form, backend US/18 validator,
  entrant non-null fields, active-banner resolver, and missing delete route.
- **Gap pass 1:** separated product contest eligibility from Bara's product-wide
  account/COPPA obligations; retained Official Rules and platform disclaimers;
  prohibited public/social actions from affecting score; made sponsor/address
  handling explicit.
- **Gap pass 2:** added immutable `eligibilityMode` for historical contest
  safety, nullable entrant fields for truthful global records, fail-closed old
  client behavior, server-owned standard rules, exact Home copy constraints,
  idempotent draft-only deletion, error contracts, cache behavior, scheduled /
  ended entry states, and exact tests-first evidence.
- **Game-analyst review:** capped configurable prizes at 25,000 (default 5,000),
  preserved ordinary velocity holds, and required outcome-relevant resolution
  of high-risk same-race/burst/device/synchronized/repeated-identity facts.
- **Architect review:** made legacy contest/entrant eligibility fields nullable
  for truthful global storage; added permanent global-client capability gating;
  required mode-aware HTML, exact admin response/PATCH contracts, concurrent
  join recovery, precise display-name eligibility, complete tie/no-winner
  rules, domain-command deletion with reused receipts, instance-local rules
  fallback, Redis/invalidation details, version-skew tests, and rollback safety.
- **UI-test-planner review:** inserted the checklist verbatim in §13 and made
  Home/Friends tutorial suppression, shared ReferralScreen callers, single-slot
  banner precedence, inline rules, draft-only deletion placement, and sticky
  footer bottom inset explicit implementation requirements.
