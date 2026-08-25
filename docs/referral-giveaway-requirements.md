# Bara Referral Contest — Requirements

Status: **IMPLEMENTED — post-review remediation complete; promotions-counsel
approval remains required before public publication**

## 1. Summary and user story

Bara will run a fixed-term, sponsor-funded referral contest. The eligible user
with the most **verified completed referrals during the contest window** wins a
cash prize with an advertised value of **US$50** plus **5,000 non-transferable
Bara coins**.

As a Bara user, I can open the contest from the Home announcement or referral
screen, understand the official rules before participating, see my verified
contest score and provisional place, see a privacy-safe leaderboard, and share
my existing referral link. Social follows may be promoted, but they do not
affect eligibility, score, or odds.

This is a deterministic contest, not a random drawing. The final winner is the
eligible entrant with the highest verified score; ties use the deterministic
rule in §4.4. Apple is not a sponsor and is not involved.

## 2. Product decisions and legal posture

### 2.1 Recommended v1 posture

- Sponsor: the same legal person/entity shown as the app developer, with legal
  name and mailing address inserted into counsel-reviewed Official Rules.
- One contest, one winner, one combined prize: US$50 plus 5,000 Bara coins.
- No purchase, subscription, review, rating, social follow, social post, or
  contact permission is required.
- Entrants must be at least 18 and be legal residents of the 50 United States
  or District of Columbia. Puerto Rico, U.S. territories/possessions, overseas
  military addresses, and non-U.S. jurisdictions are excluded unless the final
  counsel-reviewed rules expressly say otherwise.
- Referral invitations remain user-initiated through the existing native share
  sheet; Bara does not upload contacts or send messages on the user's behalf.
- The competition and prize do not modify the ordinary 500/500 referral reward.
- All leaderboard results are provisional until Bara's fraud review finishes.
- Final Official Rules must be reviewed by promotions counsel before launch.

### 2.2 U.S.-only cash fulfillment

V1 is U.S.-only. A resident of India or any other excluded jurisdiction cannot
enter, appear on the contest leaderboard, or win, even if Bara is available
there or the user completes ordinary referrals there. The ordinary referral
program and ordinary referral coin rewards remain available and unchanged.

The Official Rules must state that Bara pays US$50 through a supported U.S.
payment method and covers the sender-side fee; the winner remains responsible
for taxes and recipient-bank charges. They must list supported payout methods,
a reasonable claim/verification deadline, the next-ranked-winner procedure if
the potential winner cannot lawfully receive payment, and that the 5,000 Bara
coins have no cash value and cannot be transferred or withdrawn.

Marketing must say "Open to legal residents of the 50 United States and D.C.,
age 18+." It must never say or imply "worldwide."

### 2.3 Apple/platform requirements

- Official Rules are readable inside the iOS and Android apps, even if the
  public canonical copy also lives at `https://barastep.com/giveaways/<slug>`.
- Rules state that Apple and Google are not sponsors, administrators, endorsers,
  or otherwise involved.
- Bara/the registered developer sponsors the contest.
- Neither IAP nor purchased coins can enter, improve score, break a tie, or
  unlock contest functionality.
- Social links are optional outbound links only. App Store/Play reviews and
  ratings are never requested as a contest action.
- If a social post is ever added later, it is a separate scoped feature and
  must require a clear `#BaraContest` disclosure; it is not part of v1.

## 3. Scope and non-goals

### In scope

- One public web landing page and Official Rules page per contest.
- An in-app contest detail screen containing the material rules, leaderboard,
  personal standing, countdown, share CTA, and Official Rules link/content.
- A tappable Home service announcement for carrying clients.
- A contest entry point on the existing referral screen.
- Server-authoritative scoring from existing referral qualification facts.
- Privacy-safe provisional leaderboard and deterministic final ranking.
- Admin create/edit-before-start, publish, close, verify, disqualify, select,
  coin-award, and fulfillment-record workflow.
- Manual cash payout outside the app, with an auditable non-sensitive record.

### Non-goals

- Random winner selection, lottery, raffle, paid entry, or wagering.
- Automated cash transfer from Bara's backend.
- Collecting banking, PAN, tax ID, government ID, or PayPal credentials in Bara.
- Public full names, email addresses, referral codes, or social handles.
- Social follows/posts as entry requirements or score.
- Recurring contests or a generic promotion engine in v1.
- A runtime rollout flag. Contest visibility follows permanent lifecycle and
  client-compatibility rules, not a feature flag.

## 4. Rules and scoring

### 4.1 Contest window and authoritative point fact

Each published contest stores immutable `startsAt` and `endsAt` UTC instants.
The UI renders local time while Official Rules show exact instants and the
governing timezone. Attribution/signup may precede the contest, but a point
counts only when immutable `Referral.qualifiedAt` falls within
`[max(contest.startsAt, entrant.acceptedAt), contest.endsAt)`; entry never gains
retroactive points.

Race completion cannot rely on the existing best-effort post-settlement reward
call for scoring durability. In the same Postgres transaction that commits a
qualifying race completion, insert an idempotent `ReferralQualificationIntent`
for each eligible pending referral, stamped with the authoritative race
completion instant and race id. This insertion is part of settlement
correctness; failure rolls back/retries settlement rather than disappearing.
The existing fenced post-task runner consumes intents, sets
`Referral.qualifiedAt`/`qualifyingRaceId` to the earliest durable intent exactly
once, then runs velocity/reward logic. A bounded recovery pass reprocesses
unconsumed intents after crashes. The scorer never uses
`ReferralRewardGrant.grantedAt`, because review may happen after contest end.
Finalization reads Postgres facts, never cached/materialized leaderboard output.
Before snapshotting results it synchronously drains eligible qualification
intents or returns `409 QUALIFICATION_PROCESSING_PENDING` while any unprocessed
intent stamped before `endsAt` could affect an entrant. Recovery can never add
a point after the final snapshot.

### 4.2 Completed referral and review

Ordinary approved/rewarded referrals count as verified. Velocity-held
`FLAGGED` referrals remain reviewable and nonpublic; approval preserves their
original `qualifiedAt`, mints ordinary grants idempotently, and then counts the
point. `EXPIRED`, `EXCLUDED`, rejected, and contest-excluded facts do not count.
A contest-specific exclusion audit row removes a point without destructively
rewriting the referral ledger.

The implementation never infers completion from display-only
`friends[].stage`. Existing provider-sub, self-referral, reinstall, and review-
account guards remain authoritative. Velocity limits trigger review but do not
create a 25-point contest ceiling. Referees may live anywhere the ordinary Bara
referral program is lawfully available; only the entrant/referrer enters this
U.S.-only contest.

### 4.3 Eligibility and public identity

An entrant must be signed in, 18+, a legal resident of the 50 United States or
D.C., not the sponsor/employee/contractor or immediate family, and capable of
receiving the prize lawfully. Participation is never automatic: the user taps
**ENTER CONTEST**, checks separate 18+ and U.S.-residency attestations, selects
state/D.C., accepts the versioned Official Rules, and confirms the exact current
Bara display name the server will snapshot. The backend stores acceptance time,
rules version/hash, region, attestations, and the validated display-name
snapshot. V1 shows no public avatar and never exposes user ID, legal name,
email, referral code, state, or social handle.

Do **not** gate by timezone. IP country, storefront, locale, and timezone may be
lawful non-dispositive review signals, but none silently enters, excludes, or
disqualifies. Conflicts place a potential winner under manual verification.
Ineligible users may read public contest content but never enter, score, or
appear; ordinary referrals and rewards remain unchanged.

### 4.4 Ranking, fraud review, and no-winner case

Rank by verified count descending, then earliest UTC time the entrant reached
that final count, then stable entrant UUID ascending as a non-random technical
fallback. Before finalization, resolve every flagged fact where
`verified + reviewable` could change first place, recording approve/reject
reason, actor, and timestamp.

Candidate review aggregates shared qualifying races, lawful hashed provider/
device/network correlations, synchronized race/step behavior, attribution
source, delete/reinstall history, and velocity. A shared race alone never
auto-disqualifies a legitimate group; Official Rules prohibit bots,
entrant-controlled/reimbursed accounts, and coordinated dummy-account rings.

The leaderboard says "Provisional—positions may change after fraud review"
until `FINAL`. If no eligible entrant has at least one verified point, there is
no winner; UUID order never selects a zero-point winner.

### 4.5 Lifecycle and current contest

Persist `DRAFT|PUBLISHED|FINAL|CANCELLED|ARCHIVED`. A published record derives
`SCHEDULED` before `startsAt`, `ACTIVE` within `[startsAt,endsAt)`, and
`VERIFYING` at/after `endsAt` until winner verification. `endsAt` does not
snapshot anything; idempotent `POST .../finalize` later drains intents,
transactionally reads/reviews Postgres, and writes ranked results. If there is
no winner it transitions to `FINAL`; otherwise it remains `VERIFYING` with a
potential winner. Only verifying that winner (or exhausting alternates into a
no-winner outcome) transitions to `FINAL`.

Only one non-final published contest may exist and published windows may never
overlap. Publish rejects `409 CONTEST_WINDOW_CONFLICT`. `/current/me` selects
the sole non-archived record in this order: `ACTIVE`, `VERIFYING`, `SCHEDULED`,
then `FINAL`. A final contest remains current until an admin archives it or a
new draft is published; new publication may atomically archive only a prior
`FINAL` or `CANCELLED` contest.

- `SCHEDULED`: web/detail/current visible with countdown; banner may show;
  entry returns `409 CONTEST_NOT_OPEN`; leaderboard empty.
- `ACTIVE`: entry, scoring, banner, web, current, and provisional leaderboard.
- `VERIFYING`: no entry/new scoring; banner/current/web say results under
  review and leaderboard remains provisional.
- `FINAL`: final web/current/results and winner copy; promotional Home banner
  is omitted.
- `CANCELLED`: Home/current omit it; canonical web/rules remain accessible with
  cancellation reason and no winner.
- `ARCHIVED`: omitted from Home/current, retained at canonical historical URL.

## 5. User experience

### 5.1 Visual direction

Extend the existing playful arcade/referral language rather than introducing a
generic Material page: checker-roof header, parchment rules cards, wooden
leaderboard planks, coin glyphs, and a compact prize-podium hero. Motion is
limited to the existing stagger/coin treatments and respects reduced-motion
settings. All content supports text scaling, screen readers, contrast, safe
areas, narrow Android devices, and both light/night palettes.

### 5.2 Home announcement

Add client capability `referral_contest_v1` to both feature-header branches.
Store an optional validated contest slug alongside the existing banner settings;
operators never supply an arbitrary URL/action. Only when the client advertises
the capability and the slug resolves to a published contest does the backend
derive this additive action:

```json
{
  "enabled": true,
  "message": "Bara Referral Contest: win US$50 + 5,000 coins. Ends Sep 30.",
  "action": { "type": "contest", "contestSlug": "bara-referral-2026-09" }
}
```

New clients render a tap affordance and open in-app detail. For a contest-linked
banner, the backend omits the **entire banner** when capability is absent, so a
frozen client never sees advertising it cannot enter or rules it cannot read.
An ordinary service banner with no contest slug retains today's behavior for
all clients. Invalid/unpublished slug also omits the contest-linked banner.

### 5.3 Contest detail screen

`GiveawayScreen` (route name retained in code only if product chooses that
wording; user-facing title is "Referral Contest") renders:

1. prize hero, exact end time/countdown, and `PROVISIONAL`/`VERIFYING`/`FINAL`;
2. eligibility status and material "No purchase necessary" disclosure;
3. current user's verified count and provisional rank;
4. top leaderboard rows plus the user's row if outside the displayed range;
5. exact definition of a completed referral and anti-fraud note;
6. existing "Share your invite" action;
7. optional Bara social links labelled "Optional — does not affect contest";
8. Official Rules, privacy notice, and Apple/Google disclaimer.

Loading uses a board-shaped skeleton. Empty state says no referrals have
qualified yet and retains Share. Error state may retain only the last
successfully loaded immutable rules keyed by contest slug + rules hash,
hides potentially stale ranking, and offers Retry. Ended/verification states
disable no ordinary referral functionality. An unavailable/malformed contest
response hides the contest module without affecting Home or referrals.

### 5.4 Existing referral screen

When `GET /giveaways/current/me` returns a published contest, insert a card above
`YOUR INVITES`, showing prize, remaining time, the user's contest count, and a
details CTA. `contest:null`, 404 old-backend, malformed, or ended data means no
card. Existing referral
reward copy and `ReferralRulesScreen` remain unchanged; contest Official Rules
are a separate screen/document.

### 5.5 Public web page

`GET /giveaways/:slug` serves a crawlable, mobile-responsive page with the same
server-owned contest facts, material terms, leaderboard, optional social links,
and canonical Official Rules. `GET /giveaways` redirects to the currently
published contest or renders "No active contest." The page never exposes a
participant's account identifier or accepts banking/identity documents.

### 5.6 Admin dashboard

Add `AdminGiveawayScreen`, opened once from the existing Admin `CONFIG`
section. Its list shows lifecycle, dates, entrants, and review count. A draft
opens a scrollable create/edit form and immutable preview; published records
open read-only terms plus separate candidate review/finalization and winner/
fulfillment panels. Candidate review and fulfillment are sections/routes within
the selected contest—not duplicate destructive buttons on the list.

Because v1 is legally/economically pinned, the cash and coin fields render
read-only as US$50 and 5,000 coins. Changing those values is not a dashboard
operation; it requires a revised spec plus economy/legal review.

Publish, cancel, reject winner, select next, mark cash delivered, and award
coins require explicit consequence-specific confirmations. Disable controls
during requests but rely on server idempotency for retries/double taps. A 404
from an older backend shows "Giveaway tools require the latest server" without
affecting other Admin tools. Defensive models reject malformed required fields,
preserve the last valid screen state on errors, surface revision conflicts with
a reload action, redact provider references, and never cache sensitive data.

## 6. API contract

Create `src/modules/giveaways/` and mount it at `/giveaways`. Giveaway code uses
an exported social-module query for immutable referral qualification facts; it
does not Prisma-query social-owned tables directly. Existing referral endpoints
remain byte-compatible. All JSON errors use the existing standard shape
`{"error":"Human message","code":"STABLE_CODE",...meta}` through `AppError`.

### 6.1 Public detail, rules, and web

`GET /giveaways/:slug/data?limit=25` returns at most 25 rows (allowed limits
1–50), ordered by §4.4. Zero-score entrants do not appear. Public responses use
`Cache-Control: public, max-age=30`, `ETag`, and `updatedAt`.

```json
{
  "contest": {
    "slug": "bara-referral-2026-09",
    "title": "Bara Referral Contest",
    "status": "ACTIVE",
    "startsAt": "2026-09-01T04:00:00.000Z",
    "endsAt": "2026-10-01T04:00:00.000Z",
    "governingTimeZone": "America/New_York",
    "prize": { "cashCurrency": "USD", "cashMinor": 5000, "coins": 5000 },
    "minimumAge": 18,
    "eligibleCountries": ["US"],
    "eligibleRegions": [
      "US-AL", "US-AK", "US-AZ", "US-AR", "US-CA", "US-CO", "US-CT",
      "US-DE", "US-DC", "US-FL", "US-GA", "US-HI", "US-ID", "US-IL",
      "US-IN", "US-IA", "US-KS", "US-KY", "US-LA", "US-ME", "US-MD",
      "US-MA", "US-MI", "US-MN", "US-MS", "US-MO", "US-MT", "US-NE",
      "US-NV", "US-NH", "US-NJ", "US-NM", "US-NY", "US-NC", "US-ND",
      "US-OH", "US-OK", "US-OR", "US-PA", "US-RI", "US-SC", "US-SD",
      "US-TN", "US-TX", "US-UT", "US-VT", "US-VA", "US-WA", "US-WV",
      "US-WI", "US-WY"
    ],
    "sponsor": { "legalName": "Bara LLC", "mailingAddress": "1 Trail Way" },
    "rules": {
      "version": "2026-09-v1",
      "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
      "sections": [{ "heading": "How to enter", "body": "Plain text..." }],
      "url": "https://barastep.com/giveaways/bara-referral-2026-09/rules"
    },
    "socialLinks": [{ "platform": "instagram", "label": "Instagram", "url": "https://www.instagram.com/bara" }]
  },
  "leaderboard": [{ "rank": 1, "displayName": "Rohan", "completedCount": 7 }],
  "winner": null,
  "updatedAt": "2026-09-14T12:00:00.000Z"
}
```

`GET /giveaways/:slug/rules` serves escaped, crawlable HTML generated from the
same immutable section data. `GET /giveaways/:slug` serves the dynamic marketing
page; `GET /giveaways` redirects to current published contest or renders no
active contest. Integrate via `src/modules/web/index.js` and explicit Express
routes, not the static Vite bundle alone. Escape/sanitize title, rules, and
display names; cap title/section/count/total bytes; social URLs accept only
configured HTTPS hosts for Instagram, TikTok, X, Facebook, and YouTube.

Unknown/unpublished is `404 CONTEST_NOT_FOUND`; invalid limit is
`400 INVALID_LIMIT`; infrastructure failure is `500 INTERNAL_ERROR`.

### 6.2 Current discovery and member detail

`GET /giveaways/current/me` is authenticated and returns `200
{"contest":null,"leaderboard":[],"entry":null,"standing":null,"share":null}`
when no current contest exists. Exact populated response:

```json
{
  "contest": {
    "slug": "bara-referral-2026-09",
    "title": "Bara Referral Contest",
    "status": "ACTIVE",
    "startsAt": "2026-09-01T04:00:00.000Z",
    "endsAt": "2026-10-01T04:00:00.000Z",
    "governingTimeZone": "America/New_York",
    "prize": { "cashCurrency": "USD", "cashMinor": 5000, "coins": 5000 },
    "minimumAge": 18,
    "eligibleCountries": ["US"],
    "eligibleRegions": [
      "US-AL", "US-AK", "US-AZ", "US-AR", "US-CA", "US-CO", "US-CT",
      "US-DE", "US-DC", "US-FL", "US-GA", "US-HI", "US-ID", "US-IL",
      "US-IN", "US-IA", "US-KS", "US-KY", "US-LA", "US-ME", "US-MD",
      "US-MA", "US-MI", "US-MN", "US-MS", "US-MO", "US-MT", "US-NE",
      "US-NV", "US-NH", "US-NJ", "US-NM", "US-NY", "US-NC", "US-ND",
      "US-OH", "US-OK", "US-OR", "US-PA", "US-RI", "US-SC", "US-SD",
      "US-TN", "US-TX", "US-UT", "US-VT", "US-VA", "US-WA", "US-WV",
      "US-WI", "US-WY"
    ],
    "sponsor": { "legalName": "Bara LLC", "mailingAddress": "1 Trail Way" },
    "rules": {
      "version": "2026-09-v1",
      "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
      "sections": [{ "heading": "How to enter", "body": "Complete verified referrals during the contest window." }]
    },
    "socialLinks": []
  },
  "leaderboard": [{ "rank": 1, "displayName": "Rohan", "completedCount": 7 }],
  "winner": null,
  "entry": {
    "status": "ACTION_REQUIRED",
    "acceptedAt": null,
    "region": null,
    "displayName": "Current validated Bara name"
  },
  "standing": {
    "verifiedCount": 0,
    "reviewableCount": 0,
    "provisionalRank": null,
    "reachedCountAt": null
  },
  "share": { "code": "BARA-ABCD", "url": "https://barastep.com/r/BARA-ABCD" }
}
```

`entry.status`: `ACTION_REQUIRED|ELIGIBLE|UNDER_REVIEW|INELIGIBLE|WITHDRAWN`.
`reviewableCount` is returned only to the entrant and remains present through
`VERIFYING`; it becomes zero in `FINAL`. A deleted account's retained provider-
subject HMAC matches the re-created identity and returns `WITHDRAWN`, null
standing/share, and no re-entry; the public snapshot stays removed. Member
responses are `Cache-Control: private, no-store`. `401 UNAUTHORIZED` and
`500 INTERNAL_ERROR` follow the standard envelope. The Flutter client treats a
404 from an older backend, `contest:null`, or any wrong-typed required field as
contest unavailable while ordinary referral UI remains functional.

`winner` is always `null` before `FINAL` and for a final no-winner outcome. For
a verified winner it is exactly
`{"displayName":"Rohan","originalRank":2}`; `originalRank` preserves the
ranked snapshot when an earlier potential winner was rejected. No potential
winner identity is exposed publicly.

### 6.3 Enter contest

`POST /giveaways/:slug/entries` request:

```json
{
  "rulesVersion": "2026-09-v1",
  "country": "US",
  "region": "US-NY",
  "ageConfirmed": true,
  "residencyConfirmed": true,
  "rulesAccepted": true
}
```

The server snapshots `req.user.displayName`; the client never supplies it.
First success is `201` and exact replay is `200`:

```json
{
  "entry": {
    "status": "ELIGIBLE",
    "acceptedAt": "2026-09-02T15:00:00.000Z",
    "country": "US",
    "region": "US-NY",
    "displayName": "Rohan",
    "rulesVersion": "2026-09-v1"
  }
}
```

Errors: `400 INVALID_REGION|AGE_CONFIRMATION_REQUIRED|
RESIDENCY_CONFIRMATION_REQUIRED|RULES_ACCEPTANCE_REQUIRED|INVALID_DISPLAY_NAME`;
`404 CONTEST_NOT_FOUND`; `409 RULES_CHANGED` with `currentRulesVersion`,
`CONTEST_NOT_OPEN`, or `ENTRY_IMMUTABLE`. Do not accept DOB, ID, tax, payment,
or bank fields.

### 6.4 Home compatibility

`/home/race-card` may add the §5.2 typed action only for
`referral_contest_v1`. Implement this in both current banner assembly paths or
consolidate them. Contest-linked banner settings store only validated slug;
ordinary service-banner behavior is unchanged.

### 6.5 Admin state and endpoints

Persist `DRAFT|PUBLISHED|FINAL|CANCELLED|ARCHIVED`; derive
`SCHEDULED|ACTIVE|VERIFYING` as in §4.5, so no lifecycle cron is required.
Every mutation writes actor, idempotency key/request id, old/new state, reason,
and timestamp to an audit table. All mutations use monotonic `revision`, not an
`updatedAt` timestamp, for optimistic concurrency.

Every admin `POST` mutation requires HTTP header `Idempotency-Key: <UUIDv4>`;
the key is scoped to admin id + method + contest id and retained with the audit
record. Missing/invalid is `400 INVALID_IDEMPOTENCY_KEY`; reusing a key with a
different body is `409 IDEMPOTENCY_CONFLICT`. JSON bodies are exact:

| Endpoint | Body | Legal transition |
|---|---|---|
| `publish` | `{"revision":2}` | `DRAFT -> PUBLISHED` |
| `cancel` | `{"revision":3,"publicReason":"...","amendedRulesVersion":"2026-09-v2"}` | `PUBLISHED -> CANCELLED` |
| `reviews` | `{"revision":4,"referralFactId":"uuid","decision":"APPROVE","reasonCode":"LEGITIMATE","privateNote":"..."}` | unresolved fact -> approved/rejected |
| `finalize` | `{"revision":5}` | `VERIFYING` -> ranked snapshot; stays `VERIFYING` unless no-winner |
| `winner` | `{"revision":6,"entrantId":"uuid","decision":"VERIFY","reasonCode":"ELIGIBILITY_VERIFIED"}` | potential -> verified and `FINAL`, or rejected and still `VERIFYING` |
| `select-next` | `{"revision":7}` | rejected/forfeited winner -> next potential |
| `fulfillment` | `{"revision":8,"transition":"CASH_SENT","provider":"ACH","providerReference":"secret-ref"}` | `UNCLAIMED -> CLAIMED -> CASH_SENT -> CASH_DELIVERED` one step/request |
| `award-coins` | `{"revision":9}` | verified + `CASH_DELIVERED` -> `COINS_AWARDED` |
| `archive` | `{"revision":10}` | `FINAL|CANCELLED -> ARCHIVED` |
| `banner-correction` | `{"revision":8,"bannerMessage":"Corrected copy","reason":"Audited correction reason"}` | `PUBLISHED` only; banner copy changes without changing frozen material terms |

`winner` never conflates verify and reject: `decision` is required and
`reasonCode` must belong to the server allowlist for that decision. Fulfillment
requires `providerReference` for cash transitions and forbids it otherwise.

Create request (the same field types form the full admin contest response,
which additionally includes `id`, `revision`, derived `status`, lifecycle/audit
timestamps, and aggregate counts):

```json
{
  "slug": "bara-referral-2026-09",
  "title": "Bara Referral Contest",
  "governingTimeZone": "America/New_York",
  "startsAt": "2026-09-01T04:00:00.000Z",
  "endsAt": "2026-10-01T04:00:00.000Z",
  "cashCurrency": "USD",
  "cashMinor": 5000,
  "coinPrize": 5000,
  "minimumAge": 18,
  "eligibleRegions": [
    "US-AL", "US-AK", "US-AZ", "US-AR", "US-CA", "US-CO", "US-CT",
    "US-DE", "US-DC", "US-FL", "US-GA", "US-HI", "US-ID", "US-IL",
    "US-IN", "US-IA", "US-KS", "US-KY", "US-LA", "US-ME", "US-MD",
    "US-MA", "US-MI", "US-MN", "US-MS", "US-MO", "US-MT", "US-NE",
    "US-NV", "US-NH", "US-NJ", "US-NM", "US-NY", "US-NC", "US-ND",
    "US-OH", "US-OK", "US-OR", "US-PA", "US-RI", "US-SC", "US-SD",
    "US-TN", "US-TX", "US-UT", "US-VT", "US-VA", "US-WA", "US-WV",
    "US-WI", "US-WY"
  ],
  "sponsor": { "legalName": "PLACEHOLDER", "mailingAddress": "PLACEHOLDER" },
  "rules": { "version": "2026-09-v1", "sections": [{ "heading": "How to enter", "body": "..." }] },
  "socialLinks": [{ "platform": "instagram", "label": "Instagram", "url": "https://www.instagram.com/bara" }],
  "bannerMessage": "Bara Referral Contest: win US$50 + 5,000 coins."
}
```

Add authenticated/admin-authorized contest lifecycle endpoints under
`/admin/giveaways`:

- `GET /admin/giveaways?cursor=<opaque>&limit=25` lists by
  `(createdAt DESC,id DESC)` and returns an opaque cursor encoding that tuple as
  `{"records":[],"nextCursor":null}`; limit is 1–100.
- `POST /admin/giveaways` creates a draft with title/slug, governing timezone,
  local start/end values normalized to UTC, cash and coin prizes, eligible U.S.
  regions, minimum age, rules content/version, social links, and banner copy.
- `PATCH /admin/giveaways/:id` accepts `{"revision":N,"patch":{...}}` and edits
  a draft only; stale revision is `409 REVISION_CONFLICT`, and published
  contests return `409 CONTEST_IMMUTABLE`.
- `POST /admin/giveaways/:id/publish` requires the body revision and header key,
  validates/freezes terms, and is replay-safe; invalid legal/content fields are
  `400 PUBLISH_VALIDATION_FAILED` with a bounded `fields` list.
- `POST /admin/giveaways/:id/cancel` is exceptional, requires body revision,
  header key, a public reason
  and counsel-authorized amended-rules record; normal closure is automatic.
- `GET /admin/giveaways/:id/candidates?cursor=<opaque>&limit=25` orders by
  `(verifiedCount DESC,reachedCountAt ASC NULLS LAST,entrantId ASC)` using an
  opaque tuple cursor and returns bounded
  verified/reviewable totals and restricted audit signals, never raw IP,
  provider subject, government ID, or payment credentials.
- `POST /admin/giveaways/:id/reviews` accepts body revision/header key,
  referral-fact id, `APPROVE|REJECT`, stable reason, and private note. Exact
  replay is safe; conflicting second decision is `409 REVIEW_CONFLICT`.
- `POST /admin/giveaways/:id/finalize` reads Postgres, rejects
  `409 OUTCOME_REVIEW_REQUIRED` if any reviewable fact can alter first place,
  and `409 QUALIFICATION_PROCESSING_PENDING` while any pre-deadline intent could
  affect results. It freezes ranks and returns no-winner `FINAL` or a potential
  winner while the contest stays `VERIFYING`.
- `POST /admin/giveaways/:id/winner` verifies/rejects a potential winner with a
  reason. `VERIFY` transitions to `FINAL`; rejection stays `VERIFYING` and does
  not silently replace them. Idempotent
  `POST .../select-next` selects the next ranked eligible entrant.
- `POST /admin/giveaways/:id/fulfillment` records one transition among
  `CLAIMED|CASH_SENT|CASH_DELIVERED`, provider, and a write-only/redacted
  provider reference.
- `POST /admin/giveaways/:id/award-coins` requires verified winner and
  `CASH_DELIVERED`. In one Postgres transaction it locks fulfillment, calls
  `awardCoins({tx, reason:"giveaway_winner", refId:"giveaway:<id>:<entrant>"})`,
  stores the ledger reference/time, and advances fulfillment. Replay never
  mints twice.
- `POST /admin/giveaways/:id/archive` removes final/cancelled contest from
  `/current` and Home but preserves canonical historical pages.
- `POST /admin/giveaways/:id/banner-correction` requires revision and an
  idempotency key plus exact `bannerMessage` and `reason` fields. It updates
  only published banner copy, audits the reason, and returns `{ "contest":
  AdminContest }`; invalid corrections return `INVALID_BANNER_CORRECTION`.

Create/edit validation covers unique slug, `start < end`, supported USD value,
minimum age 18, state/D.C. region codes, HTTPS social URLs, sponsor legal name
and address, and mandatory Apple/Google/no-purchase rules clauses. V1 accepts
exactly USD 5,000 minor units and 5,000 coins; a higher/different prize requires
a new economy/legal review, never an uncapped admin mint input. No endpoint
stores bank or identity-document data. Published dates, territory, prize,
scoring/tie rules, eligibility, and rules version are immutable. Banner copy
may be corrected only if materially consistent with the frozen rules and every
change is audited.

Mutation responses return the full admin contest, next `revision`, and relevant
result data. Errors use `400 INVALID_*|PUBLISH_VALIDATION_FAILED`,
`401 UNAUTHORIZED`, `403 FORBIDDEN`, `404 CONTEST_NOT_FOUND`, the `409` codes
above, and `500 INTERNAL_ERROR` in the standard envelope.

The canonical coin reference is `giveaway:<contestId>:<entrantId>`. Because
`awardCoins` currently returns no ledger id, extend its return additively with
`transactionId` (existing callers ignore it), or select the unique reason/ref
row inside the same transaction after the idempotent call; persist that exact
`CoinTransaction.id` on fulfillment. All admin responses use `Cache-Control:
private, no-store`. Enforce bounded 32 KiB JSON bodies; public detail allows 60
requests/minute per lawful hashed network key and entry 10 attempts/hour/user.

## 7. Data model and migrations

Add additive tables in the backend Prisma schema:

- `GiveawayContest`: UUID, unique slug, title, lifecycle status, start/end UTC,
  cash currency/minor amount, coin prize, minimum age, eligible-country JSON,
  immutable rules version, section content, and hash (canonical URL is derived),
  social-links JSON,
  published/frozen/finalized timestamps, created/updated timestamps.
- `GiveawayEntrant`: contest/user unique pair, eligibility status, asserted
  country/state, age/residency-confirmed timestamps, snapshotted public display
  name and consent, accepted rules version/hash, non-reversible
  `entrantIdentityHash = HMAC(provider,providerSubject)` using the existing
  versioned server-secret pattern, eligibility
  and disqualification audit fields, created/updated timestamps. On user delete,
  retain only the minimum pseudonymous audit key counsel approves.
- `GiveawayResult`: contest/entrant unique pair, frozen count, reached-count time,
  final rank, result status, verification notes, selected timestamp.
- `GiveawayFulfillment`: contest/winner unique pair, cash status/provider,
  provider transaction reference (not credentials), cash sent/delivered minor
  amounts/currencies, exchange rate/timestamps, coin ledger reference, claimed/
  fulfilled timestamps. Restrict to admins and retention policy.

Add nullable immutable `Referral.qualifiedAt` and `qualifyingRaceId`; existing
rows are not backfilled and therefore cannot score in a future contest. Add
`ReferralQualificationIntent` with unique `(referralId,qualifyingRaceId)`, the
original race completion instant, processed/attempt timestamps, and last error;
the earliest durable intent wins and recovery is idempotent. Add
`GiveawayPointReview` keyed by contest + referral fact with decision, stable
reason, note, actor, and timestamps; this is the exclusion/approval audit, not a
mutable source-of-truth score table. Add `GiveawayAuditEvent` for admin actions.

All entrant/result/fulfillment records reference stable `GiveawayEntrant.id`.
`GiveawayEntrant.userId` is nullable with `onDelete:SetNull`; no giveaway FK may
block account deletion. Deleting an account withdraws an active entrant,
removes public display snapshot immediately, and retains only versioned
acceptance, score/audit, and legally required financial fields for the
retention period. Non-winner acceptance/audit records are purged three years
after final/cancelled; winner fulfillment/tax records are retained seven years;
counsel must approve or replace these periods before production publication.
The existing cleanup/job-run framework performs purges. Update the ordered
delete-account transaction explicitly.

Enforce `@@unique([contestId, entrantIdentityHash])`. Retain the HMAC after
`userId` becomes null, never serialize it, and match it during entry/current
lookup so a deleted/recreated provider identity remains `WITHDRAWN` and cannot
enter the same contest twice.

Postgres is source of truth for configuration, entry acceptance, qualified
facts, reviews/exclusions, final results, fulfillment, and coins. V1 leaderboard
reads indexed Postgres, has no automatic client polling, and may use only the
30-second public HTTP/CDN cache from §6.1. Member detail is uncached. Finalize
and award always bypass caches. Add indexes on referral
`(referrerId,qualifiedAt)`, contest lifecycle timestamps, entrant uniqueness,
review lookup, and final rank. Migrations are additive and default-safe.

## 8. Fulfillment workflow

1. At `endsAt`, derived state becomes `VERIFYING`; no automatic snapshot occurs.
2. Admin reviews flagged referrals and top candidates; every adjustment needs a
   reason and audit timestamp.
3. Finalize ranked results and designate a potential winner.
4. Contact the potential winner using existing verified account contact data.
5. Collect eligibility/tax/payment information outside Bara through a secure
   sponsor process; never through support chat or the public page.
6. Pay cash manually via a counsel-approved U.S. payout method; record only the
   redacted provider reference, amount, and sent/delivered timestamps.
7. After cash is recorded delivered, award 5,000 coins through the centralized
   `awardCoins` seam with canonical ref
   `giveaway:<contestId>:<entrantId>`, exactly once after winner verification.
8. Mark fulfilled and publish the permitted winner identification/results.
9. If the potential winner misses the deadline, is ineligible, or cannot
   lawfully receive a supported payout, record the reason and repeat with the
   next ranked eligible entrant as the Official Rules prescribe.

## 9. Backward compatibility and rollout

1. Deploy additive database migration and backend endpoints first.
2. Publish only a draft/unlisted test contest; do not enable the Home banner.
3. Ship both iOS and Android carrying clients together. A missing endpoint or
   field yields no contest card/action and leaves ordinary referrals intact.
4. Wait for the carrying App Store/Play build to roll out before publishing.
   Backend capability-gates the complete contest banner/action; frozen clients
   never receive it and ordinary service notices remain unaffected.
5. Publish immutable contest rules and contest record, then enable the existing
   operational Home service banner. This is content lifecycle, not a release
   flag.
6. At end time, close automatically based on the immutable timestamp; no manual
   staging/prod capacity change is part of this feature.

Frozen clients keep reading all existing responses and never receive contest
promotion. The backend requires no new field on existing endpoints. A newer
client against an older backend treats the giveaways 404 as no contest and
retains ordinary referral behavior.

## 10. Tests-first plan

### Backend integration tests (dedicated local/test Postgres only)

Write and observe these fail before business logic:

1. public contest HTML/JSON includes exact immutable terms; unpublished/unknown
   contests are not exposed;
2. authenticated eligibility is idempotent and never accepts/stores payment or
   ID data;
3. referrals qualifying just before/at/after boundaries count correctly;
4. signup before window is allowed, but qualification before entry never counts;
5. pending, expired, excluded, flagged, review, self, reinstall, and reversed
   referrals do not score;
6. immutable qualification fact is written before velocity review; approved
   flagged facts retain original time; inject one intent-processing failure and
   prove recovery preserves the first qualifying race/time; ranking/tie-break
   is deterministic;
7. public rows mask identity and non-opted-in entrants;
8. ordinary `GET /referrals/me` remains byte-compatible and giveaway discovery
   stays on `/giveaways/current/me`;
9. Home banner returns optional typed action while the legacy message remains;
10. finalize blocks until every outcome-changing reviewable fact is resolved;
    lifecycle/revision/idempotent replay is audited and published terms cannot
    be mutated;
11. concurrent coin fulfillment creates exactly one 5,000-coin ledger entry;
12. account deletion and data-retention behavior preserves required abuse/audit
    protection without retaining unnecessary PII or blocking deletion;
13. HTML/rules/display names are escaped, social-host/content bounds enforced,
    public cache headers/ETag work, member/finalization reads bypass cache;
14. contest banner is entirely absent without `referral_contest_v1`, while an
    ordinary service banner remains present;
15. zero verified scores produce no winner; cash-delivered plus coin award is
    transactionally idempotent; alternate-winner history is preserved;
16. overlapping publication is rejected; scheduled/active/verifying/final/
    cancelled/archived `/current`, banner, and canonical-web behavior matches
    §4.5; both admin cursor orders remain stable under concurrent inserts;
17. finalize fails while an outcome-relevant pre-deadline intent is unprocessed,
    recovery preserves its original time, then retry includes it in snapshot;
18. rank snapshot remains `VERIFYING`; winner reject/select-next stays private;
    only verified winner or exhausted no-winner becomes `FINAL` with exact
    public `winner`; deletion/recreation matches entrant HMAC and cannot reenter.

### Frontend widget/integration tests

Write and observe these fail before UI logic:

1. pump real Home with legacy, valid contest, malformed action, and missing
   banner payloads; a present malformed action hides the entire banner, an
   absent action preserves the legacy static banner, and only a valid contest
   action navigates;
2. pump real Referral screen with absent/old-backend, active, ended, malformed,
   loading, and error contest summaries;
3. pump contest detail for eligible/action-required/ineligible, empty, ranked,
   outside-top-list, verifying, final, malformed, and retry states;
4. rules and Apple/Google/no-purchase disclosures are reachable without an
   external browser;
5. optional social links are labelled non-scoring and no review/rating CTA
   exists;
6. large text, narrow Android, iPhone safe-area, light/night, screen-reader
   semantics, and reduced motion remain usable;
7. share action uses the existing referral share path and contest failure never
   blocks ordinary referral sharing;
8. admin dashboard covers malformed/404, revision conflict, publish validation,
   destructive confirmations, double taps/retries, candidate pagination,
   winner verification, cash delivery, and exactly-once award state;
9. tutorial Home fixture suppresses contest banners/actions, and every live
   ReferralScreen entry path renders the same single contest-card placement.

## 11. Acceptance criteria and definition of done

- Counsel-approved immutable Official Rules exactly match server scoring,
  territory, timing, prize, tie, verification, and fulfillment behavior.
- Apple/Google disclaimers and no-purchase terms are accessible in-app.
- Every score is explainable by durable referral facts; no display-only state
  or client clock determines results.
- Public leaderboard reveals only the entrant-consented, snapshotted display
  name and score.
- Only legal residents of the 50 United States and D.C. can enter or appear;
  timezone/storefront/IP never silently determines eligibility.
- Coin award is server-authoritative and exactly once.
- Ordinary referral rewards and all old clients remain compatible.
- Tests were written first and pass; `flutter analyze`, relevant Flutter tests,
  backend unit tests, and backend integration tests pass.
- Both iOS and Android are verified together.
- Architect, game-economy, UI-placement, and final code reviews complete.

## 12. Operator-configured values and publication requirements

The admin dashboard supplies exact start/end timestamps, governing timezone,
cash/coin values, social links, and banner copy while the contest is a draft.
Defaults are one calendar month, Eastern Time, US$50, 5,000 coins, 18+, and all
50 states plus D.C. The dashboard does not invent legal text: sponsor legal
name/address and counsel-approved Official Rules are required before Publish.
They may be placeholders during implementation/local tests, but a production
contest cannot publish with placeholders.

## 13. Manual UI-placement test plan

**Manual UI-Placement Test Plan — Bara Referral Contest**

*Elements under test:* Home service banner gains a tap affordance in its existing position directly below the Home hero and above quick actions; no second contest banner is added elsewhere on Home.

*Elements under test:* Active-contest card is added to the existing Invite Friends screen above `YOUR INVITES`; it is absent when no active summary is available.

*Elements under test:* New Referral Contest detail screen adds the prize/status hero, eligibility or entry panel, personal standing, leaderboard, referral explanation, Share action, optional social links, and rules/privacy/platform links in that order.

*Elements under test:* New contest-entry surface adds the 18+, U.S.-residency, state/D.C., rules-acceptance, and display-name confirmation controls before participation.

*Elements under test:* New in-app Official Rules surface is separate from the existing ordinary referral `Program rules` screen.

*Elements under test:* Admin → `CONFIG` gains a Giveaway dashboard entry leading to contest list, draft editor, candidate review/finalization, and fulfillment surfaces.

*Checklist*

1. **Home tab — real screen, iOS**
   - **Get there:** Sign in on an iPhone with the active contest service banner enabled → Home.
   - **Verify:** The single tappable banner remains directly below the hero and above quick actions; it does not duplicate below quick actions, the global-event banner, SETUP, or race content. Tap it and confirm the contest detail screen is pushed above Home, with its back control clear of the status bar/Dynamic Island.

2. **Home tab — real screen, narrow Android**
   - **Get there:** Sign in on a narrow Android device with the same active banner → Home.
   - **Verify:** The banner occupies the same below-hero/above-quick-actions position and remains wholly above the bottom navigation area. Confirm there is no duplicate in its former plain-text position. Repeat with maximum system text size: the banner grows vertically instead of clipping, overlapping quick actions, or moving behind system insets.

3. **Invite Friends — every live entry path**
   - **Get there:** Open Friends → `INVITE`; then separately Get Coins → `INVITE FRIENDS`; if Home shows the empty-races Invite action, open it there too.
   - **Verify:** Every path reaches the same real `ReferralScreen`. The contest card appears once after the referral stats/share area and immediately above `YOUR INVITES`; `YOUR INVITES` is not still occupying the card’s new position or duplicated. With no active/valid contest summary, the card and its spacing disappear and `YOUR INVITES` returns to its prior position.

4. **Referral Contest detail and entry**
   - **Get there:** Open the contest from both the Home banner and the Invite Friends contest card; use an account that has not entered.
   - **Verify:** Both routes land on the same detail screen. From top to bottom, verify hero/status, eligibility/entry, personal standing, leaderboard, completed-referral explanation, Share, optional social links, and legal links. Open `ENTER CONTEST` and confirm all attestations, state/D.C. selection, rules acceptance, display name, and confirmation action are reachable without overlapping the keyboard, bottom safe area, or each other; there is no entry control on Home or the ordinary Invite Friends body.

5. **Referral Contest detail — long and ranked content**
   - **Get there:** Open seeded/test states for a long leaderboard with the user outside the displayed top rows, then an empty leaderboard.
   - **Verify:** The extra personal row appears once with the leaderboard rather than detached elsewhere; long content scrolls through Share and all legal links. In the empty state, the leaderboard rows disappear but Share and legal links remain in their established lower-page positions rather than jumping into the hero.

6. **Official Rules versus ordinary referral rules**
   - **Get there:** Contest detail → `Official Rules`; then back → Invite Friends → existing `Program rules`.
   - **Verify:** Contest Official Rules open as their own in-app surface with a safe-area-cleared back control and scrollable content. The existing `Program rules` link remains at the bottom of Invite Friends and still opens only the ordinary referral rules; neither rules document replaces or duplicates the other.

7. **Admin hub and giveaway dashboard**
   - **Get there:** Sign in as an admin → Settings → Admin Tools → expand `CONFIG` → open the new Giveaway control.
   - **Verify:** The Giveaway control appears once in `CONFIG`, alongside the existing Accessory Render Tuner, Balance Config, and Powerup Shop controls, not in Growth/Engagement/Revenue. Confirm the contest list leads to the draft create/edit form; published contest rows lead to candidate review/finalization and fulfillment controls. On a narrow phone and with large text, every form section and bottom action remains scroll-reachable above the safe area/keyboard, with no duplicate Publish, Finalize, Award Coins, or fulfillment action left on the list screen.

8. **Tab tutorial — real Home mirror**
   - **Get there:** Profile → admin/re-run tutorial → advance to every Home preview beat.
   - **Verify:** The tutorial’s seeded Home remains free of the live service/contest banner, so it does not push the existing Home spotlight targets or appear as a tappable escape route. Confirm each Home spotlight still rings its intended element and no contest detail can be opened behind the tutorial.

9. **Tab tutorial — Friends mirror and demo-race tutorial**
   - **Get there:** Continue to the Friends preview beat, then run the onboarding demo race through its invite-friends beat.
   - **Verify:** The Friends spotlight still rings the existing Invite control; no contest card is injected into the tab preview. In the demo race’s invite-friends beat, confirm no contest card/detail/rules UI appears—the demo uses `RaceInviteScreen`, not `ReferralScreen`—and its bottom Invite action remains in its prior position above the coach chrome.

*Surfaces confirmed unaffected:* Tutorial Home is the real `HomeTab`, but `tutorialPreviewHomeRaceCard()` currently provides no `homeServiceBanner`; the contest announcement should therefore remain absent from the tutorial fixture.

*Surfaces confirmed unaffected:* Tutorial Friends is the real `FriendsTab`, but its copied tab host absorbs navigation; it does not render `ReferralScreen` or the new contest card.

*Surfaces confirmed unaffected:* Demo race tutorial uses `RaceInviteScreen` for selecting racers, not the ordinary `ReferralScreen`; no giveaway placement should propagate there.

*Surfaces confirmed unaffected:* Races, Boards, Profile, race detail, case opening, onboarding referral welcome, and the hand-copied tutorial tab bar do not host any specified giveaway element.

*Risks found while planning:* `HomeTab` is shared by production and the tab tutorial. If the tutorial fixture ever gains `homeServiceBanner`, the new typed action could shift spotlight targets or escape the tutorial unless it is explicitly suppressed or its navigation is inert.

*Risks found while planning:* `ReferralScreen` has at least three live entry paths—Friends, Get Coins, and the Home empty-races Invite action—so placement must be implemented in the shared screen rather than one caller.

*Risks found while planning:* The current service banner is a plain `Container` directly below the hero. Adding a tap target must preserve that single slot; wrapping it while also rendering a new contest banner would create an easy duplicate.

*Risks found while planning:* The spec does not yet define the precise admin dashboard information architecture. The architect/implementers must lock whether candidate review and fulfillment are separate routes or sections before placement can be tested unambiguously.

## 14. Exact implementation path

1. **Backend tests and schema:** in the backend repo, write integration tests
   under `test/integration/` against a confirmed test Postgres; add Prisma
   migration/models in `prisma/schema.prisma`, including nullable referral
   qualification fields, giveaway tables/indexes/FKs, and deletion behavior.
2. **Social fact seam:** update
   race completion to insert durable qualification intents in its settlement
   transaction; update `src/modules/social/commands/grantReferralReward.js` and
   the fenced post-task/recovery runner to consume them into immutable facts
   before velocity review; expose a bounded giveaway fact query through
   `src/modules/social/index.js`.
3. **Giveaway backend:** add directory-based
   `src/modules/giveaways/models/`, `queries/`, `commands/`, `services/`, and
   thin `routes/public.js` + `routes/admin.js`, plus `index.js` assembled with
   routes last. Add `jobs/` only for the qualification-intent recovery/retention
   tasks integrated into existing fenced runners. Mount public `/giveaways` and
   admin `/admin/giveaways` routers separately with DI in `src/app.js`; use
   standard `AppError`, Postgres ranking/review/finalization, and admin
   idempotency. Add dynamic escaped web/rules renderers through
   `src/modules/web/index.js` and explicit routes.
4. **Banner compatibility:** extend admin banner settings with validated contest
   slug; capability-gate both Home response assembly paths; never alter ordinary
   service-banner behavior.
5. **Account deletion/retention:** extend
   `src/modules/users/commands/deleteUserAccount.js` and the existing scheduled
   cleanup/job-run framework; do not create a standalone unfenced cron.
6. **Frontend tests:** first add/extend real-widget tests for Home,
   `ReferralScreen`, contest/rules/entry screens, Admin CONFIG/dashboard, and
   tutorial fixtures described in §§10/13.
7. **Frontend contract:** add `referral_contest_v1` to both feature-header
   branches and defensive giveaway/admin service methods/models in
   `lib/services/backend_api_service.dart` plus `lib/models/`.
8. **Frontend UI:** preserve the single banner slot in
   `lib/screens/tabs/home_tab.dart`; add the shared contest card in
   `lib/screens/referral_screen.dart`; add `giveaway_screen.dart`,
   `giveaway_rules_screen.dart`, and `admin_giveaway_screen.dart`; add one Admin
   CONFIG entry in `lib/screens/admin_screen.dart`. Reuse existing referral share
   logic, theme pieces, and defensive parsing.
9. **Verify/roll out:** run backend integration/unit suites (never prod DB),
   `flutter analyze`, relevant then full Flutter tests, and account for both iOS
   and Android. Deploy backend first, release both apps, wait for adoption, then
   publish through the dashboard. No staging start without explicit user
   authorization.

## 15. Revision log

- Initial exploration: reused the existing referral dashboard and durable
  reward ledger; identified the current text-only Home service banner as the
  version-skew seam; separated ordinary referral rules from contest rules.
- Gap pass 1: added immutable lifecycle, deterministic tie-break, provisional
  verification, ineligible-user behavior, payout fallback, privacy masking,
  and explicit no-flag rollout.
- Gap pass 2: added exact boundary semantics, qualification-time proof/backfill
  guard, frozen-client banner/rules handling, exactly-once coin fulfillment,
  deletion/retention requirements, and tests for malformed/older responses.
- Mobile-design pass: specified a restrained extension of Bara's existing
  arcade/parchment/wood visual language, accessibility, night palette, narrow
  Android, safe areas, and reduced motion rather than generic Material UI.
- User interview: selected U.S.-only; explicit 18+/residency/rules entry;
  qualification during the window regardless of signup time; snapshotted Bara
  display names; operator dashboard for dates/prizes/content; one combined
  winner; optional non-scoring social follows; deterministic reached-count tie.
- Gap pass 3 after interview: rejected timezone gating; specified state/D.C.
  attestation, display-name consent/snapshot, exact eligibility request/errors,
  immutable-after-publish admin contract, exceptional early-close audit, and
  sponsor/rules publication validation.
- Architect review (REVISE): capability-gated contest promotion for frozen
  clients; dedicated giveaway discovery/domain; exact entry/public/admin
  contracts and errors; immutable qualification fact; Postgres-only finalization;
  revision/idempotency lifecycle; deletion/FK/retention rules; safe dynamic web
  renderer; and concrete admin UI were added. India fulfillment was removed.
- Game-analyst review (`SOUND WITH CHANGES`): added pre-velocity
  `qualifiedAt`/race fact, no retroactive pre-entry points, outcome-changing flag
  review, ring signals/rules, exact v1 prize cap, provisional-score warning,
  and clarified non-U.S. referees. Production EV and referral baselines were
  recorded in `docs/economy.md` §11.
- UI-test-planner review: checklist inserted verbatim in §13; the admin
  information architecture risk is resolved by §5.6 (candidate and fulfillment
  are selected-contest sections/routes, not list-level duplicate actions).
- Post-review gap pass 1: removed the stale additive `/referrals/me` test,
  removed public avatar references from requirements, made no-zero-score winner
  explicit, and aligned cash-before-coins fulfillment.
- Post-review gap pass 2: added exact draft JSON, concrete retention periods,
  social/content sanitization, cache bounds, and explicit old-backend admin/UI
  behavior. No unresolved product requirement remains; sponsor identity and
  counsel-approved rules are publication inputs, not implementation blockers.
- Architect re-check (REVISE) and gap passes 3–4: made qualification durable in
  the race-settlement transaction with recovery preserving original time;
  completed lifecycle/current/archive and overlap rules; pinned UUID header
  idempotency, mutation bodies/transitions/cursors, canonical coin reference and
  ledger id; pinned module/router layout and immutable rule storage; completed
  member JSON/deleted-entrant behavior; and added recovery/lifecycle tests.
- Architect second re-check (REVISE) and gap passes 5–6: finalization now drains
  or blocks on applicable qualification intents; rank snapshot stays verifying
  until winner verification/no-winner; public/member winner shape represents
  alternates safely; entrant identity HMAC prevents delete/recreate re-entry.
