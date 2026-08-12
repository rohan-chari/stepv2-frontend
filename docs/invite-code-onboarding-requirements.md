# Invite-code setup prompt + referral-attribution observability

Status: **PARTIALLY SUPERSEDED**
Date: 2026-08-09
Repos: stepv2-frontend (this repo) + stepv2-backend (`/Users/rohan/repos/stepv2-backend`)

> **2026-08-11 product amendment:** Part A's blocking
> `OnboardingInviteCodeStep` is superseded by
> [`next-race-cta-requirements.md` §8.6](./next-race-cta-requirements.md). Remove
> the invite-code screen from onboarding v3. Manual entry now lives as a
> dismissible Home SETUP prompt plus a permanent Settings entry, both using one
> shared sheet. Parts B–D of this document remain active. Where any Part A text
> below conflicts with that amendment, the 2026-08-11 amendment wins.

## Summary & user story

Referral attribution currently depends on inference (iOS clipboard handoff at
provision, IP-correlated link_opens fallback). Real-world capture over the
2026-08-08/09 weekend was ~1 of 5–6 invites; the misses were silent and needed
manual prod repairs (dylanhuynh, emersonz incidents). Four parts:

**A. Home SETUP invite-code prompt (supersedes the original onboarding step).**
> As a new user who was invited by a friend, I want a dismissible setup prompt
> and permanent Settings entry for my invite code, so automatic-attribution
> failures can be repaired without blocking onboarding.

The prompt is explicit user intent — it captures clipboard failures, iCloud
Private Relay users, Wi-Fi↔cellular flips, and word-of-mouth invitees. **Both
sides are rewarded**: applying a code creates the standard PENDING referral;
when the referee finishes their first qualifying race, the referrer earns
`REFERRAL_REFERRER_COINS` (500) and the referee earns `REFERRAL_REFEREE_COINS`
(500), exactly like every other attribution path (settlement-driven grant,
`grantReferralReward.js`). No new reward mechanics.

**B. Attribution observability (backend).**
> As the operator, I want to know which mechanism attributed each referral and
> to see link-open bursts that produced no attribution, so failures surface
> without a user complaint.

- `referrals.source` column stamped by every write path.
- Log lines when the IP fallback resolves (or ambiguously declines) a code.
- A read-only audit script reporting unattributed link-open bursts and the
  attribution-source breakdown.

**C. Clipboard-handoff instrumentation + hardening (frontend).**
The iOS pasteboard handoff fails silently and we've never known at which
stage (nothing detected? read denied by the iOS paste-permission alert? code
extracted but expired before sign-in?). Instrument every stage of
`resolveOnFirstLaunch` with locally-stashed outcomes flushed as activation
events after sign-in, and handle read-denial explicitly. The dominant
suspected cause: `readClipboardUrl` performs a real pasteboard read at cold
start, which on iOS 16+ raises the system "Allow Paste?" alert outside any
user gesture — a denial is silent today. If instrumentation confirms it, the
fix direction is already documented in `REFERRAL_FEATURE_RESEARCH.md` §1
(defer the read behind an explicit user action / `UIPasteControl`); with
part A shipped, a denied read degrades to the Home SETUP prompt instead of a
lost referral.

**D. Coarse-network IP fallback matching (backend).**
The exact-IP fallback match breaks whenever the landing-page egress differs
from the app egress (IPv4↔IPv6 on the same network, Wi-Fi↔cellular flips,
NAT churn). Store an additional network-prefix hash (IPv4 /24, IPv6 /64) on
`link_opens` and let the fallback match on it as a second tier — same
single-distinct-code and hot-IP guards, env-tunable, logged and
source-stamped per tier. (iCloud Private Relay remains structurally
unmatchable by any IP scheme; parts A and C are the answer there.)

## Scope / non-goals

In scope:
- Remove `OnboardingInviteCodeStep` from onboarding v3; add the dismissible Home
  SETUP prompt, permanent Settings entry, and shared invite-code sheet defined
  by the 2026-08-11 amendment (both platforms, one Dart implementation).
- Backend: additive `referrals.source` column; `referredByCode` in the auth
  user payload; legacy `onboardingInviteCodeEnabled` and new
  `setupInviteCodePromptEnabled` flags; fallback log lines; audit script;
  analytics event-name allowlist additions.
- Google-provision parity for the one-shot welcome stash (today only the
  Apple path stashes `welcomeReferralCode`; Google clears only —
  `auth_service.dart:431-433`).
- Clipboard-handoff instrumentation across `resolveOnFirstLaunch`
  (`install_attribution_service.dart:37-73`) + explicit read-denial handling;
  `UIPasteControl`/deferred-read hardening **contingent on** what the
  instrumentation shows (spec'd as a bounded investigation task for the
  frontend agent, not an open-ended one).
- `link_opens.ip_net_hash` column + two-tier fallback matching (exact IP,
  then network prefix), with per-tier source stamping and logging.

Non-goals (explicitly out; tracked as follow-ups):
- Prod-network-path E2E verification of the IP fallback (ops task, not code;
  integration coverage exists and is extended here in
  `test/integration/referral_attribution_fallback.test.js`).
- Matching iCloud Private Relay traffic by IP (structurally impossible;
  parts A/C are the mitigation).
- Any change to reward amounts, qualifying rules, velocity caps, or the
  one-payout-per-provider-identity ceiling.
- Onboarding v1/v2 flows (v3 is ON in prod for fresh accounts; older flows
  don't get the step).
- Backfilling `source` for historical referrals (stays NULL = "pre-tracking").

## Existing behavior this builds on (citations)

- Manual redeem endpoint: `POST /referrals/redeem` →
  `src/modules/social/routes/referrals.js:98-109` →
  `redeemReferralCode.js`. Always HTTP 200 with
  `{ attributed: true }` or `{ attributed: false, reason }`, reasons:
  `no_user | invalid_code | no_identity | already_attributed | unknown_code |
  self_referral | already_raced`. The `already_raced` guard counts only
  **non-seeded** completed races (`redeemReferralCode.js:42-54`), so the
  window is open throughout onboarding (auto-enrolled dailies are seeded).
  Redeem writes the referral (PENDING) + `users.referredByCode` mirror +
  best-effort ACCEPTED auto-friendship.
- Rewards: settlement calls `grantReferralRewards({ race })`
  (`completeRace.js:472`); qualifying = seeded OR ≥2 real participants
  (`grantReferralReward.js:180-185`); amounts env-tunable, default 500/500
  (`referralRewards.js:11-14`); insert-first unique
  `[refereeSubHash, role]` grant ledger; `REFERRAL_REWARDED` push to the
  referrer only (`notificationHandlers.js:662-685`).
- Onboarding v3 flow is an ordered early-return chain in
  `lib/screens/onboarding_flow.dart` (v3 branch begins at :176: demo race
  :177-186, then inviter-race step with daily-intro fallback :187-196).
  Gate predicate: `lib/utils/onboarding_gate.dart:28-50` (v3 terms:
  health-or-escape, `tutorialOnboardingSeen`, `firstRaceOnboardingSeen`).
- Existing enter-code UI to mine for patterns: `_EnterCodeSheet`
  (`referral_screen.dart:719-783`) and its reason→copy map
  (`referral_screen.dart:169-183`); success copy `referralRedeemedCopy`
  (`referral_screen.dart:599`).
- Provision body carries `referralCode` when the clipboard/deep-link capture
  worked (`auth_service.dart:351-357` Apple, `:422-428` Google); on Apple
  success the code moves to the one-shot `welcomeReferralCode` slot
  (`auth_service.dart:363-366`) which drives step 0
  (`OnboardingReferralWelcomeStep`, `onboarding_flow.dart:132-141`).

## API contract

**No new endpoints. No changed request shapes.** Additive response fields only.

### 1. `referredByCode` in the auth user payload (backend)

**Already on the wire — no serialization change.** `withRuntimeFlags`
spreads the raw `users` row (`routes.js:161-163`), `/auth/me` passes
`...req.user` (a full `prisma.user.findUnique` row via `requireAuth.js:181-187`),
and only `lastAppVersion`/`lastSeenAt` are stripped — so
`referredByCode: string | null` already ships on `/auth/apple`,
`/auth/google`, `/auth/me` (and `/auth/session`) today. No Dart code reads
it yet. The client starts reading it as server truth for "was this account
already attributed by ANY path" (body code, IP fallback, prior redeem,
repair script) to hide the onboarding step.

**The only backend work here is the freshness fix (MUST, dedicated tests):**
`ensureAppleUser`/`ensureGoogleUser` return the in-memory `user` created
*before* `recordReferral` runs its `user.update({ referredByCode })`
(`ensureAppleUser.js:106-142`), so a just-attributed provision response
serializes `referredByCode: null` and defeats the hide logic on first
launch. Fix: **`recordReferral` returns `{ attributed, code, source }`**
(today it returns nothing), and the create branch merges `referredByCode`
into the returned user **only when `attributed === true`**. Do NOT blindly
merge the attempted code: `recordReferral` silently declines on unknown
code, review account, self-referral, and swallowed P2002
(`recordReferral.js:29-47, 92-102`), and reporting a declined code as
attributed would hide the step from exactly the users this feature exists
to catch. Tests: (positive) provision with a valid body code returns
`referredByCode` non-null; (negative) provision with an **unknown** body
code returns `referredByCode: null` and the account has no referral row.

Cache note: `/auth/me` may serve from `authMeCache` (TTL 10s,
`authMeCache.js:78`, only when `redisCacheAuthMeEnabled` is on).
`recordReferral`/`redeemReferralCode` are already listed there as raw-`tx`
writers riding the TTL (`authMeCache.js:63-65`). As part of this change, add
`referredByCode` to that file's "ACCEPTS ≤10s STALENESS" inventory with the
reason: the client acts on the redeem response plus its local done-flag,
never a read-back-after-write, so ≤10s of staleness is benign. Do not
invalidate the cache from the social module.

- Old app versions: ignore the unknown field — safe.
- New app on an older backend (staging lag, rollback): field absent → client
  treats as `null` → step may show for an already-attributed user → redeem
  returns `already_attributed` → friendly copy, step dismisses. Degrades
  safely; never crashes (`(json['referredByCode'] as String?)`).

### 2. `featureFlags.onboardingInviteCodeEnabled` (kill switch)

Add to `KNOWN_FLAGS` (`src/shared/config/appSettings.js`) with default
`true`, emitted from `withRuntimeFlags` alongside `onboardingV3Enabled`
(`routes.js:163-176`).

- Client parse rule: **absent or non-boolean ⇒ ON; only literal `false`
  disables.** (Kill switches must fail open on old backends; note this
  differs from `onboardingV3Enabled`'s literal-`true` parse at
  `auth_service.dart:718-728` — that one is an opt-in flag, this one is a
  kill switch.)
- Frozen old clients ignore the unknown key (established pattern,
  `appSettings.js:22-29`).

### 3. `POST /referrals/redeem` — unchanged wire shape

The onboarding step calls the existing endpoint via the existing
`BackendApiService.redeemReferralCode` wrapper
(`backend_api_service.dart:2168-2181`). Internally the command now stamps
`source: "redeem"` (see Data model); response body unchanged.

### 4. `POST /analytics/activation-events` — allowlist additions only

Add event **names** (no context-allowlist changes — see below) to
`ALLOWED_EVENT_NAMES` (`src/modules/analytics/routes.js:9-50`) and the
client mirror (`activation_analytics_service.dart:20-61`):

- `invite_code_step_shown`, `invite_code_applied`, `invite_code_skipped`
- Part C outcomes **encoded in the name, one per install**:
  `install_attr_deep_link`, `install_attr_detect_miss`,
  `install_attr_read_denied`, `install_attr_read_no_code`,
  `install_attr_code_captured`, `install_attr_install_referrer`,
  `install_attr_error`

**Why names, not a context key:** unknown event names soft-drop per event
(`analytics/routes.js:217-231`), but an unknown context key/value 400s the
**entire batch** (`:106-131, 240-243`) and the client retains failed batches
(`activation_analytics_service.dart:184-186`) — one bad event would poison
every subsequent flush until it rolls off the 50-event queue. Name-encoded
outcomes need no context change and are ordering-safe against an old
backend. Ship backend first anyway per deploy order.

## Data model / migrations

Two additive migrations in the backend repo (may ship as one deploy):

```sql
-- <ts>_add_referral_source
ALTER TABLE "referrals" ADD COLUMN "source" TEXT;
-- <ts>_add_ip_net_hash_to_link_opens
ALTER TABLE "link_opens" ADD COLUMN "ip_net_hash" TEXT;
CREATE INDEX "link_opens_ip_net_hash_created_at_idx"
  ON "link_opens" ("ip_net_hash", "created_at");
```

Schema: `source String? @map("source")` on `Referral`
(`schema.prisma:1351-1366`) — no enum (statuses are plain strings in this
table already), no backfill (NULL = "attributed before tracking"), no index.
`ipNetHash String? @map("ip_net_hash")` on `LinkOpen`
(`schema.prisma:1640-1655`) with the paired created_at index, mirroring the
existing `ipHash` column/index; old rows stay NULL and age out of the 48h
window within two days of deploy — no backfill.

`source` stamped values and their single write sites:

| value | write site | meaning |
|---|---|---|
| `provision_body` | `recordReferral` via `ensureAppleUser.js:128-136` / `ensureGoogleUser.js:131-139` when the body carried the code | clipboard/deep-link handoff worked |
| `ip_fallback_exact` | same call sites, code from `fallbackReferralCode()` tier 1 | exact-IP link_opens match |
| `ip_fallback_net` | same call sites, tier 2 | network-prefix link_opens match |
| `redeem` | `redeemReferralCode.js:56-71` | manual entry (onboarding step or referral screen) |
| `repair` | reserved for ops scripts (never set by app code) | manual prod repair |

Implementation: `recordReferral({ newUser, referralCode, source })` gains an
optional `source` param (default `null`, so every existing caller/test is
unaffected); `ensureAppleUser`/`ensureGoogleUser` pass `"provision_body"`
for a body code, or the tier label returned by the fallback (below).
`redeemReferralCode` sets `source: "redeem"` in its own create.

### Two-tier fallback matching (part D)

- `clientIp.js` gains `hashClientNet(req)`: resolve the client IP exactly as
  `resolveClientIp` does, then hash the network prefix — IPv4 first 3 octets
  (`/24`), IPv6 first 4 hextets (`/64`, computed on the expanded form so
  `2600:1:2:3::x` and `2600:0001:0002:0003:y` agree). IPv4-mapped IPv6
  (`::ffff:1.2.3.4`) normalizes to the v4 `/24`, not a `/64` of the mapped
  range. Unparseable → **null, and a null `ipNetHash` must skip tier 2
  entirely** — a Prisma `where: { ipNetHash: null }` would match every
  pre-deploy legacy row and attribute off whatever single code happens to
  be there (mirror the existing `if (!ipHash) return null` guard at
  `findLinkOpenReferralCode.js:31`; dedicated test).
- `logLinkOpen` (`app.js:163-168`) stores both `ipHash` and `ipNetHash`.
- `findLinkOpenReferralCode({ ipHash, ipNetHash })` becomes two-tier and
  returns `{ code, tier: "exact" | "net" } | null`. **This is a DI contract
  change** — today it returns a bare string and the thunk passes it straight
  into `recordReferral` (`routes.js:85-86` → `ensureAppleUser.js:129-136`);
  an unupdated call site would feed an object into `normalizeReferralCode`
  → null → silent organic signup. Both `ensure*User` call sites change in
  the same commit, tolerate a bare-string resolution from injected doubles,
  and `test/http/auth-flow.test.js:89-92` must still pass.
  - **Tier 1 (exact)**: today's logic, unchanged conditions.
  - **Tier 2 (net)**: only when tier 1 found **zero** opens; same window,
    same exactly-one-distinct-code rule, and its own cap
    `REFERRAL_IP_FALLBACK_NET_MAX_OPENS` (default 10; counts **opens**, not
    distinct devices). **Env switch `REFERRAL_IP_FALLBACK_NET_ENABLED`
    defaults OFF (`"0"`)** — the matching code, column, stamping, and tests
    all ship now, but tier 2 goes live only after `npm run referrals:audit`
    data (source breakdown by day) shows tier-1 volumes and lets us judge
    the false-positive surface. At flip time, restricting tier 2 to IPv6
    `/64` only (a real home LAN) while keeping IPv4 `/24` off is the
    fallback posture if /24 looks too hot.
  - Tier 1 declining for ambiguity/hot-IP does NOT fall through to tier 2
    (an ambiguous exact IP is strictly stronger evidence of a shared
    network; widening would only add noise).
- **Explicit intent beats tier 2 (pre-emption guard):** a wrong tier-2
  attribution would otherwise be permanent — `refereeSubHash` is unique and
  redeem answers `already_attributed` off it, so the genuine inviter would
  be lost and the onboarding step would tell the user "You're already
  connected to your inviter!" about a stranger. Therefore
  `redeemReferralCode` gains one rule: when the existing referral has
  `source = 'ip_fallback_net'` AND `status = 'PENDING'`, a manual redeem
  **replaces** it (delete + recreate in one transaction, new referrer, new
  code, `source: 'redeem'`; the old auto-friendship is left in place —
  harmless, and removing it risks deleting a real friendship). Safe only
  because `source` is stamped; applies to no other source value. Dedicated
  integration test both ways (replaces `ip_fallback_net`+PENDING; refuses
  for `provision_body`, `ip_fallback_exact`, or non-PENDING).
- Abuse cost note (why default-OFF): an IPv4 `/24` on carrier NAT is shared
  by thousands of strangers; the exactly-one-distinct-code rule does not
  protect against a farmer whose code is the only one opened from that /24
  in 48h. The residual safety net (PENDING-only, qualifying race required,
  one-payout-per-identity ceiling, velocity caps, per-tier `source`
  visibility, env off-switch) bounds the damage but does not make tier 2
  free — hence data before enablement.

Deployment: `npx prisma migrate deploy && npx prisma generate` per
`DEPLOYMENT.md` (staging `migrate dev` first, never `db push` on prod,
forward-only).

## Backend plan (order of operations)

1. **Migrations + schema** — `referrals.source`, `link_opens.ip_net_hash`
   (above). Regenerate client.
2. **`recordReferral` / `redeemReferralCode`** — thread and stamp `source`
   as per the table. No behavioral change otherwise; all guards untouched.
2b. **Two-tier fallback** — `hashClientNet`, dual-hash `logLinkOpen`,
   tiered `findLinkOpenReferralCode` with per-tier cap + env kill switch
   (design above); `ensureAppleUser`/`ensureGoogleUser` map the returned
   tier to `ip_fallback_exact` / `ip_fallback_net`.
3. **Fallback observability** — in `ensureAppleUser`/`ensureGoogleUser`'s
   attribution block (or in `findLinkOpenReferralCode` with the resolved
   context), log with the existing bare-console convention:
   - resolved: `console.log("[REFERRAL] ip-fallback (<tier>) resolved <code> for user <id>")`
   - declined-ambiguous (>1 distinct code) and declined-hot-IP (> max opens),
     per tier: `console.log("[REFERRAL] ip-fallback (<tier>) declined (<reason>) for signup <id>")`
   Zero-opens stays silent (that's the organic-signup common case; logging it
   is noise). Logging must never throw into the signup path — wrap or keep to
   plain string interpolation.
4. **`referredByCode` freshness fix** — no serialization change (the field
   already ships; see API contract §1). `recordReferral` returns
   `{ attributed, code, source }`; `ensure*User` create branches merge
   `referredByCode` into the returned user only when `attributed === true`.
   Add `referredByCode` to `authMeCache.js`'s "ACCEPTS ≤10s STALENESS"
   inventory with its reason.
5. **`onboardingInviteCodeEnabled`** — `KNOWN_FLAGS` entry, default `true`,
   emitted in `withRuntimeFlags`.
6. **Analytics allowlist** — the ten event names (three invite-code +
   seven `install_attr_*`); names only, no context changes.
7. **Audit script** — `scripts/referral-attribution-audit.js` +
   `package.json` script `referrals:audit`. Read-only (SELECTs; safe against
   prod like `powerups:store`). Reports, for a `--days N` window (default 7):
   - link-open "bursts" (≥1 referral-kind open) grouped by code where **no**
     `referrals` row for that code was created within 48h of the burst —
     candidate lost attributions;
   - attribution-source breakdown (`source` counts incl. NULL), **total and
     per-day** — the per-day series is what gates the tier-2 env flip
     (part D);
   - redeem-reason tallies are NOT available server-side (redeem reasons are
     response-only) — out of scope.
   Exit 0 always; it's a report, not a gate.

Steps 1–6 are one deploy. The contract the frontend needs is steps 4+5+6
(fields visible on staging) — lock that first.

## Frontend plan

### New widget: `OnboardingInviteCodeStep` (in `lib/screens/onboarding_flow.dart`)

One implementation, same file as every other step (no mirrored copies exist
for onboarding — verified; the tab tutorial and demo race mirror other
surfaces only).

**Placement (product decision, Rohan 2026-08-09): FIRST v3 step — right
after the health gate, before the demo race:**

```
if (onboardingV3Enabled) {
  if (_showInviteCodeStep)      → OnboardingInviteCodeStep      (NEW)
  if (!tutorialOnboardingSeen)  → OnboardingDemoRaceStep        (existing)
  ...                           → OnboardingInviterRaceStep /
                                  OnboardingDailyIntroStep      (existing)
}
```

Captures attribution intent at the earliest moment, and a successful apply
means the whole rest of onboarding (demo race, inviter-race step) already
knows the inviter. The step renders while `tutorialOnboardingSeen` and
`firstRaceOnboardingSeen` are still false, so `isOnboardingGate`
(`onboarding_gate.dart:28-50`) keeps onboarding open with **no predicate
change**. The redeem window is not at risk regardless — only non-seeded
completed races close it.

**Show condition** (`_showInviteCodeStep`), all must hold:
- `onboardingV3Enabled && onboardingInviteCodeEnabled`
- `authService.referredByCode == null` (server truth; defensively parsed,
  absent ⇒ null ⇒ show). **Deliberately NOT conditioned on
  `welcomeReferralCode`**: the welcome slot is stashed on provision success,
  not attribution success (`auth_service.dart:363-366`), so a body code the
  backend silently rejected (unknown/review-account) would set the slot while
  leaving the account unattributed — exactly a user this step must catch. An
  attributed-at-provision user is hidden via `referredByCode` (freshness fix
  above), never via the welcome slot.
- not locally marked done: SharedPreferences key `invite_code_step_done`
  (device-scoped, no userId suffix), unset. Set on **apply-success, terminal
  rejection (`already_attributed`/`already_raced` — `self_referral` is NOT
  terminal: the user typed their own code and can retype their friend's), or
  skip**
  — not on transient failure (network error / `unknown_code` typo lets the
  user see it again next launch if they backgrounded mid-flow; within one
  session the flow simply moves past it via local widget state).
  **Storage/cleanup (corrected in review — there is NO allKeys wildcard
  clear):** sign-out cleanup is an enumerated list
  (`auth_service.dart:791-816` + `OnboardingStateService.clearPersistedState`
  looping the static `allKeys` list, `onboarding_state_service.dart:49,
  268-273`). The new key follows the onboarding convention: add it to
  `OnboardingStateService.allKeys` so the existing sign-out path clears it
  (a different account on the same device gets its own chance;
  `referredByCode` server truth prevents re-prompting attributed accounts).
  Note the deliberate-exclusion pinning test at
  `onboarding_state_service.dart:38-47` — the new key must be added there
  too, not worked around.

**UI** (reuse `OnboardingScene` chrome + `PillButton`; mine `_EnterCodeSheet`
patterns rather than importing the sheet):
- Title: `GOT AN INVITE CODE?`
- Subtitle: `If a friend invited you, enter their code — you'll BOTH earn
  coins when you finish your first race.` When coin figures are available
  from the wire (`refereeCoins`/`referrerCoins` via `GET /referrals/me`,
  fetched fire-and-forget with graceful degradation exactly like
  `invite_copy_test.dart` expects), upgrade to `…you'll both earn 500 coins…`.
  Never hardcode the figure (env-tunable server-side).
- `TextField`: `TextCapitalization.characters`, autofocus off (don't shove a
  keyboard at the user), hint `BARA-XXXX`, trim on submit. No strict client
  format validation beyond non-empty (backend is the validator; codes are
  server-defined).
- Primary button `APPLY` (disabled while empty / in-flight; in-flight spinner
  state), and `I wasn't invited` (skip) with **near-equal visual weight** —
  this step fronts 100% of new users to serve roughly the invited fraction;
  the uninvited majority must exit in one obvious tap. Post-ship: compare
  `home_reached` activation conversion against the pre-change baseline
  before treating first-position placement as permanent.
- Keyboard safety: the step must remain scrollable/inset-padded when the
  keyboard opens (follow `test/onboarding_keyboard_access_test.dart`
  conventions).

**States:**
- idle → editing → submitting → success | error.
- Success (`attributed: true`): show `referralRedeemedCopy(refereeCoins: …)`
  toast (existing helper), mark done, then **re-fetch the inviter race**
  (`_fetchInviterRace`, `main_shell.dart:2146-2165` — it ran before the user
  was attributed, so its cached answer is empty) and advance the flow
  (setState so the early-return chain falls through). This lets a
  successfully-applied user land on `OnboardingInviterRaceStep` and join
  their inviter's race, matching the link-attributed experience.
- Error mapping (mirror `_reasonMessage`, `referral_screen.dart:169-183`):
  - `already_attributed` → "You're already connected to your inviter!" —
    terminal: mark done, advance.
  - `self_referral` → "You can't use your own code." — stay on step.
  - `already_raced` → "Invite codes only work before your first race." —
    terminal: mark done, advance (unreachable during onboarding in practice).
  - `unknown_code` / `invalid_code` → "That code doesn't look right — double
    check it." — stay on step.
  - thrown/network → "Couldn't apply that code. Check your connection and
    try again." — stay; skip remains available. **A backend outage must never
    trap the user in onboarding: skip is always tappable.**
- Loading: none on entry (the step renders instantly; the optional coin-figure
  fetch upgrades copy in place).

**Plumbing contract (architect-reviewed — this is where the state lives):**
`OnboardingFlow` is a `StatelessWidget` whose inputs are all props from
`MainShell` (`onboarding_flow.dart:14-44`, construction
`main_shell.dart:2584-2627`) — it cannot read SharedPreferences or
`setState`. Mirror the `welcomeReferralCode`/`onWelcomeDismissed` pattern
(`onboarding_flow.dart:117-125`, `main_shell.dart:2616-2624`):
- New props: `showInviteCodeStep` (bool, MainShell computes the full show
  condition), `onApplyInviteCode(String code)` (async, returns the redeem
  result for the step to render), `onInviteCodeResolved({required bool
  attributed})` (MainShell writes the done-flag, on success re-fetches the
  inviter race via `_fetchInviterRace`, `main_shell.dart:2150-2164`, then
  `setState` so the chain falls through).
- **Pre-load behavior:** `showInviteCodeStep` must be false until the auth
  payload has been applied (`referredByCode` known) — otherwise a fresh
  install flashes the step and hides it. Render the flow's existing
  loading/held state rather than the step while auth state is unresolved;
  widget test required.

**Auth/service plumbing:**
- `AuthService`: parse + persist `referredByCode` from the backend user
  envelope (nullable, defensive, cleared on sign-out like its peers at
  `auth_service.dart:786`); parse `onboardingInviteCodeEnabled` with the
  fail-open rule (only literal `false` disables).
- Google parity: `signInWithGoogle` stashes `welcomeReferralCode` on
  attributed provision the same way Apple does (`auth_service.dart:363-366`
  vs `:431-433`).
- `DemoAuthService` (`lib/demo/demo_auth_service.dart:76-115`): explicitly
  override the new members — `referredByCode => null`,
  `onboardingInviteCodeEnabled => false` — mirroring the existing
  `onboardingV3Enabled => false` pattern, so the demo host can never render
  or fetch for the step (ui-test-planner risk R1).
- Admin screen: add an `onboardingInviteCodeEnabled` toggle row next to the
  `onboardingV3Enabled` row (`admin_screen.dart:362-368`) so the kill switch
  is flippable from the device during staging verification (risk R2).
- Analytics: emit `invite_code_step_shown` (once per render-session),
  `invite_code_applied` (on `attributed: true`), `invite_code_skipped`; add
  the three names to `ActivationAnalyticsService.allowedEventNames`
  (`activation_analytics_service.dart:20-61`).

**Degradation matrix (new app, missing backend data):**

| missing | behavior |
|---|---|
| `referredByCode` field absent | treat as null → step shows; `already_attributed` handled gracefully |
| `featureFlags` absent entirely | kill switch defaults ON; `onboardingV3Enabled` stays false → step never renders (v3-only) |
| `/referrals/me` coin figures absent | generic "coins" copy |
| `/referrals/redeem` 404/500 | error state, skip always available |

### Part C: clipboard-handoff instrumentation + hardening

Scoped as a **bounded** task for the frontend agent: instrument first;
change behavior only where the denial path is provably broken today.

1. **Instrument `resolveOnFirstLaunch`**
   (`install_attribution_service.dart:37-73`): record the outcome of each
   stage to SharedPreferences at cold start (the service runs in `main()`
   before sign-in, so activation events cannot be posted yet), then flush
   once after sign-in via `ActivationAnalyticsService`. **One event per
   install, outcome encoded in the event NAME** (architect-required: a
   context key unknown to an older backend 400s and wedges the whole
   retained batch; unknown names soft-drop per event):
   - `install_attr_deep_link` (deferred to a link-captured code)
   - `install_attr_detect_miss` (iOS `detectPatterns` found no probable URL)
   - `install_attr_read_denied` (detect hit but the pasteboard read returned
     nothing/threw — the iOS paste-alert denial signature)
   - `install_attr_read_no_code` (read succeeded, no `BARA-` extractable)
   - `install_attr_code_captured` (success)
   - `install_attr_install_referrer` (Android install-referrer path)
   - `install_attr_error`
   Names go into both allowlists (`activation_analytics_service.dart:20-61`,
   backend `analytics/routes.js:9-50`). No context-allowlist change.
2. **Make read-denial explicit**: in `ios/Runner/AppDelegate.swift:130-165`,
   distinguish "read returned nil/denied" from "no URL on pasteboard" in the
   channel response so Dart can record `read_denied` vs `detect_miss`
   truthfully. No behavior change — classification only.
3. **Hardening (contingent)**: if `read_denied` dominates the funnel (check
   after a week of data), implement the deferred-read design from
   `REFERRAL_FEATURE_RESEARCH.md` §1: keep the prompt-free `detectPatterns`
   probe at launch; move the actual read behind a user tap (the onboarding
   invite-code step is the natural host — when a probable URL was detected
   but unread, the step offers a "Paste invite link" button whose tap is the
   user gesture the iOS paste alert wants). This sub-item ships only the
   plumbing that is safe to build now: the detect-but-unread state is passed
   through to the invite-code step, which shows the paste button whenever
   that state is present. Denied again → normal manual entry still works.
   Note: `resolveOnFirstLaunch` sets `install_attribution_checked`
   unconditionally at launch (`install_attribution_service.dart:40, 53`,
   "at most ONCE per install") — the deferred paste-button read necessarily
   happens AFTER that flag is set and must not add a second launch-time
   pasteboard read (the prompt-at-launch is the exact behavior being
   retired).

**Android + iOS:** same Dart widget; the part-C channel change touches
`AppDelegate.swift` (iOS) with a no-op-compatible Android channel (install
referrer path already returns distinct outcomes). Both builds produced and
smoke-checked per CLAUDE.md lockstep rule (Android `--flavor staging`
against staging backend; iOS staging build).

## Backward-compat & rollout

- **Deploy order: backend first** (migration + fields + flag + allowlist).
  All backend changes are additive; the prod backend continues serving every
  frozen client identically (new response fields are ignored; `source` is
  write-side only; redeem's wire shape is unchanged).
- Frontend ships in the next App Store/Play build. No `testOnly` gating
  needed (no new content old clients can't render); the runtime kill switch
  `onboardingInviteCodeEnabled=false` hides the step instantly across all
  new-build users if anything goes wrong, without a resubmission.
- Old app + new backend: unchanged behavior (fields ignored, no new
  endpoints required).
- New app + old/staging-lagged backend: degradation matrix above; worst case
  is a redundant prompt answered by `already_attributed`.
- Rollback: kill switch first; backend changes are safe to leave in place
  (additive column + logs). Migration is forward-only per `DEPLOYMENT.md`.

## Test plan (tests FIRST, then logic)

Backend (`test/integration/`, real HTTP + real test DB, never prod;
`npm run test:integration`, never bare `npm test`):
1. Extend `referral_attribution_fallback.test.js`: body-code provision stamps
   `source: "provision_body"`; exact-IP fallback stamps
   `source: "ip_fallback_exact"`; organic signup leaves no referral
   (unchanged). New tier-2 cases: same-/24 different-last-octet IPv4 open →
   attributes with `source: "ip_fallback_net"`; same for IPv6 same-/64
   (mixed compressed/expanded forms agree); different /24 → no attribution;
   tier-1 ambiguity does NOT fall through to tier 2; net cap exceeded → no
   attribution; `REFERRAL_IP_FALLBACK_NET_ENABLED` unset/off → tier 2 dead
   while tier 1 lives (default posture); enabled → tier 2 live; null
   `ipNetHash` skips tier 2 (never matches legacy NULL rows); IPv4-mapped
   IPv6 (`::ffff:1.2.3.4`) hashes as the v4 /24; body code always wins over
   both tiers.
1b. Redeem pre-emption guard: manual redeem **replaces** an existing
   referral iff `source='ip_fallback_net'` AND `status='PENDING'` (new
   referrer/code, `source:'redeem'`); refuses (returns
   `already_attributed`) for `provision_body`/`ip_fallback_exact`/any
   non-PENDING status. Companion test: redeem after a tier-2 attribution
   with tier 2 misconfigured off again still behaves per the same rule.
2. Extend redeem coverage: successful `POST /referrals/redeem` stamps
   `source: "redeem"`; every rejection reason still returns its exact
   `{ attributed: false, reason }` body (assert the full set — protects the
   frontend copy map).
3. Auth payload: `POST /auth/apple` (new + returning) and `GET /auth/me`
   include `referredByCode` (null for organic, code for attributed).
   **Including the freshness case**: a brand-new provision whose body carried
   a valid code returns `referredByCode` NON-null in that same provision
   response (guards against the stale in-memory-user trap).
4. Flags: `featureFlags.onboardingInviteCodeEnabled` emitted `true` by
   default; `false` when the app-setting override is set.
5. Analytics: all ten new event names (three invite-code + seven
   `install_attr_*`) are accepted (202, inserted); unknown names still
   soft-drop per event; no context-allowlist change exists in the diff.
6. Existing referral suites (`referral_reward_flow`,
   `referral_delete_reinstall_farm`, `onboarding-revamp`) pass **unmodified**
   except mechanical `recordReferral` signature accommodation if any test
   constructs it directly (optional param ⇒ likely zero edits).

Frontend (`flutter test`; every widget test that reaches
`BackendApiService`/analytics calls `PackageInfo.setMockInitialValues` +
`SharedPreferences.setMockInitialValues` in `setUp` — known hang trap):
7. New `test/onboarding_invite_code_step_test.dart`:
   - shown iff v3 ON + kill switch not false + `referredByCode` null +
     not marked done (deliberately NOT conditioned on `welcomeReferralCode`
     — the welcome step at `onboarding_flow.dart:135-141` is sequential
     before the v3 branch, not exclusive with this step);
   - hidden when `referredByCode` set; hidden when kill switch `false`;
   - not rendered before the auth payload is applied (no flash on fresh
     install);
   - apply success → toast copy, done-flag set, flow advances to the
     inviter/daily step;
   - each rejection reason renders its copy; terminal reasons advance,
     non-terminal stay;
   - network error keeps skip tappable;
   - skip → done-flag set, flow advances, `invite_code_skipped` emitted;
   - coin figures absent → generic copy (extend `invite_copy_test.dart`
     pattern).
8. Flow-order structural test: extend `tutorial_revamp_test.dart`'s v3-branch
   source assertion (`:311-323`) so the expected order is invite-code step →
   demo race → inviter-race step (mechanical update, strengthens — not
   weakens — the assertion).
8b. Part C: unit tests for the outcome classifier (pure Dart —
   `install_attribution_test.dart` pattern): each stage outcome maps to its
   context value; stash-then-flush emits exactly once per install; iOS
   channel's denied-vs-miss distinction surfaces correctly (mock channel).
   Widget test: invite-code step shows the "Paste invite link" button iff
   the detect-but-unread state is present, and its tap path falls back to
   manual entry on a second denial.
9. `AuthService` unit-style tests (SharedPreferences mock): `referredByCode`
   parse/persist/clear-on-signout; kill-switch fail-open parse (absent ⇒ ON,
   literal false ⇒ OFF).
10. Keyboard access: invite step obeys the keyboard-inset conventions of
    `onboarding_keyboard_access_test.dart`.

## Acceptance criteria / definition of done

- A fresh v3 account with no automatic attribution sees the step once, can
  apply `BARA-…` and both parties are rewarded at the referee's first
  qualifying settlement (500/500 defaults, referrer push fires) — verified
  end-to-end on staging.
- An account attributed at provision (body or IP fallback) never sees the
  step (`referredByCode` server truth).
- Skip is always available, including with the backend unreachable.
- Kill switch `onboardingInviteCodeEnabled=false` removes the step without an
  app release.
- Every `referrals` row created after deploy carries a non-NULL `source`;
  `npm run referrals:audit` reports source breakdown + unattributed bursts.
- IP-fallback resolutions/declines visible in pm2 logs (`[REFERRAL]` prefix),
  tier-labeled; tier 2 can be disabled by env alone.
- With `REFERRAL_IP_FALLBACK_NET_ENABLED=1` set on staging, a same-/24
  open→provision pair attributes via tier 2 end-to-end; with it unset
  (the prod default), the same pair does not attribute.
- A manual redeem replaces a PENDING `ip_fallback_net` attribution
  (staging), and refuses to replace a `provision_body` one.
- `install_attr_*` events arrive with truthful stage classification
  (verified on a staging device: deep link, empty clipboard, and
  code-on-clipboard runs each produce their expected context).
- All existing tests pass unmodified (except the sanctioned mechanical
  updates in items 6 and 8); new tests written first, seen failing for the
  right reason.
- iOS and Android builds both produced and verified.
- Manual UI-placement checklist (Phase 4 ui-test-planner output, appended
  below) executed by Rohan.

## Manual UI-placement test plan

(ui-test-planner output, 2026-08-09, verbatim.)

*Elements under test:* One NEW step inserted as the first branch inside the v3 chain of `lib/screens/onboarding_flow.dart` (after the health gate at :149, before `OnboardingDemoRaceStep` at :182). Contains: title, coin-upgrading subtitle, code TextField (hint `BARA-XXXX`, all-caps), APPLY pill with in-flight state, "I wasn't invited" skip text button, and a conditional "Paste invite link" button (detect-but-unread clipboard state only). Nothing else moves.

Code facts confirmed while planning: `OnboardingFlow` is hosted in exactly one place (`main_shell.dart:2584`); no onboarding step is mirrored in `lib/tutorial/tutorial_real_screens.dart` (zero onboarding references) or `lib/demo/` (`demo_auth_service.dart:84` hard-returns `onboardingV3Enabled => false`). So there are no propagating mirrors — the checklist is about step-order neighbors, flags, and the surfaces that *bound* the step.

### Checklist

**Fresh v3 account — the main path (iOS simulator or device; repeat 1–4 once on Android staging flavor)**
1. **Real onboarding, organic install** — Get there: fresh account (staging), empty clipboard, no invite link ever opened, v3 ON. Verify: after the HEALTH DATA gate passes, the FIRST screen is the invite-code step — title, subtitle, code field (hint `BARA-XXXX`), APPLY pill, "I wasn't invited" below it. The demo-race step must NOT be the first post-gate screen anymore.
2. **Gate ordering (negative)** — Same run: the invite step must NOT appear before or instead of the health gate. Deny/stall health → invite step never flashes.
3. **Skip path** — Tap "I wasn't invited". Verify: next screen is `OnboardingDemoRaceStep` (demo race intro), and the invite step does not reappear on back/foreground within the session. Force-quit + relaunch mid-onboarding after skip: invite step stays gone (done-flag).
4. **Apply-success path** — Second fresh account, enter a real friend's `BARA-…` code, tap APPLY. Verify: spinner appears in the pill (button not duplicated/replaced by a second button), success toast, flow advances; then after the demo race completes/skips, the flow lands on `OnboardingInviterRaceStep` (join-your-inviter's-race), not the generic daily-intro fallback. Invite step must NOT reappear anywhere later in the flow.
5. **Keyboard insets** — On a small device (iPhone SE-class sim), tap the code field. Verify: APPLY and "I wasn't invited" both remain visible/scroll-reachable above the keyboard; the capybara scene chrome doesn't push the buttons off-screen. Repeat once on Android (soft keyboard behaves differently).
6. **Non-terminal error keeps placement stable** — Enter garbage (`BARA-ZZZZ`) → error copy renders WITHOUT the step advancing; field + both buttons still in place. Airplane mode → APPLY errors, "I wasn't invited" still tappable (never trapped).

**Users who must NOT see the step**
7. **Link-attributed user (welcome step owns them)** — Get there: fresh account provisioned via an invite link/clipboard code that attributes successfully (or seed `welcomeReferralCode` per the referral E2E staging method). Verify: `OnboardingReferralWelcomeStep` shows as step 0 (`onboarding_flow.dart:135`); after dismissing it and passing health, the invite-code step does NOT appear (server `referredByCode` non-null). No double-prompt.
8. **Kill switch off** — Profile → admin → feature-flag panel (note: `admin_screen.dart:340-368` currently has no `onboardingInviteCodeEnabled` row — implementation must add one, or flip it via the backend app-setting on staging). With it OFF and v3 ON, fresh account: post-gate first screen is the demo race, invite step absent.
9. **v3 off** — Admin toggle `onboardingV3Enabled` OFF (row exists, `admin_screen.dart:363`) → fresh account runs the v2/legacy chain; invite step absent everywhere (it lives only inside the v3 branch).

**Mirrored / preview surfaces**
10. **Demo race tutorial** — Get there: fresh account → onboarding → demo race (after skipping/completing the invite step). Verify: the invite step never renders inside the demo (DemoAuthService forces v3 false), and the demo's real race-detail screen shows no invite-code chrome. Also confirm the demo still launches at all — see risk R1.
11. **Tab tutorial (Profile → re-run tutorial)** — Run the 5-step tutorial. Verify: no invite-code UI in any preview beat, and all spotlight beats still ring their targets (no anchor changes expected — this is a smoke pass, not a deep check).
12. **Referral screen enter-code sheet** — Friends/Profile → referral screen → "enter code" sheet (`_EnterCodeSheet`). Verify: sheet unchanged and still reachable; no duplicated invite UI, and after applying a code there the onboarding step (if somehow still pending) doesn't re-prompt.

**Part C conditional button**
13. **Paste-button state** — iOS only: put an invite URL on the clipboard, cold-start, DENY the "Allow Paste?" alert (or reach the detect-but-unread state per the new channel). Verify: "Paste invite link" button appears on the invite step, positioned with (not replacing) the manual field; tap it → iOS paste alert; deny again → button degrades, manual field + APPLY + skip all still present. With an empty clipboard: button absent (negative check).
14. **Dark mode** — Force dark (settings, or after 21:00). Verify: the step pins to the light onboarding palette like every `OnboardingScene` step (title screen convention) — no half-dark mix, buttons still visible.

### Surfaces confirmed unaffected
- `lib/tutorial/tutorial_real_screens.dart` — hosts the five tabs + race-detail previews only; zero onboarding references (grepped). No hand-copied onboarding chrome to mirror.
- `lib/demo/demo_race_host.dart` + `demo_auth_service.dart` — demo forces `onboardingV3Enabled == false` (:84) and never instantiates `OnboardingFlow`; step cannot render there by construction (checkpoint 10 verifies the compile-surface risk R1, not placement).
- Race detail, tabs, case-opening screens, `main_shell` tab bar — untouched by this change; no element moves on them.
- Tutorial spotlight anchors (`tutorialXKey` set) — the invite step carries no spotlight key and no keyed widget moves; `tutorial_screen.dart` string-id map unaffected.
- `tutorial_preview_data.dart` / `demo_race_engine.dart` fixtures — no race/tab payload field feeds the invite step; no fixture fabrication needed.

### Risks found while planning (now explicit implementation steps)
- **R1 — `DemoAuthService` compile/override surface**: `lib/demo/demo_auth_service.dart` overrides `AuthService` members (:76-115). If `AuthService` gains `referredByCode` / `onboardingInviteCodeEnabled` getters that the demo service must implement (or that fail-open getters read from prefs the demo never seeds), the demo host could break or leak a network fetch. Checkpoint 10 exists to catch it; implementers should mirror the `onboardingV3Enabled => false` pattern explicitly.
- **R2 — Admin panel has no kill-switch row**: `admin_screen.dart:340-368` lists five flags; `onboardingInviteCodeEnabled` isn't one. Without adding it, checkpoint 8 requires a backend app-setting flip — fine, but decide deliberately. **Spec decision: add the admin row** (one-line pattern next to the `onboardingV3Enabled` row).
- **R3 — Structural order test pins the v3 chain**: `test/tutorial_revamp_test.dart:311-323` asserts v3 branch order via source; the spec already sanctions a mechanical strengthen (invite → demo → inviter). Don't weaken it.
- **R4 — Coin-figure fetch is a live network call on the first onboarding screen**: `/referrals/me` fire-and-forget must degrade to generic copy; verify on-device with airplane mode (folded into checkpoint 6) that the subtitle doesn't render blank or shift layout when the upgrade lands (in-place text swap, no reflow that moves the buttons).
- **R5 — Welcome-slot vs server-truth split**: the step deliberately ignores `welcomeReferralCode` and keys off `referredByCode` (spec v2b). A silently-rejected body code means a user sees BOTH the welcome step and, later, the invite step — that is intended, but it will look like a double-ask in testing; don't file it as a bug (checkpoint 7 covers the attributed case only).
- **R6 — Done-flag is per-userId and wiped on sign-out** (`invite_code_step_done_<userId>`): sign-out clears allKeys (known rename-chip trap, home-setup spec). Re-sign-in on an *attributed* account must still hide the step via `referredByCode` — that's the checkpoint-7 negative worth re-running after a sign-out/sign-in cycle if you have 60 spare seconds.

## Revision log

- v1 (2026-08-09): initial draft from codebase exploration of both repos.
- v2 (gap pass 1): found and fixed (a) the stale in-memory-user trap —
  provision response would serialize `referredByCode: null` for an
  attributed signup because `ensureAppleUser` returns the pre-`recordReferral`
  object; now a MUST-fix with a dedicated test; (b) dropped the
  `welcomeReferralCode == null` show-condition — the welcome slot is stashed
  on provision success, not attribution success, so a silently-rejected body
  code would wrongly hide the step; server truth only; (c) added the
  post-apply inviter-race re-fetch so a manually-attributed referee still
  gets the join-your-inviter's-race step.
- v3 (gap pass 2): documented `/auth/me` payload-cache staleness as accepted
  (done-flag + `already_attributed` terminal handling make it benign) with an
  explicit instruction not to cross-module-invalidate; confirmed the
  onboarding gate predicate needs no change (step renders inside the
  `firstRaceOnboardingSeen == false` window); confirmed no mirrored
  onboarding copies exist (tab tutorial/demo race mirror other surfaces);
  noted the referee gets coins but no push at reward time (existing
  behavior, referrer-only push — unchanged).
- v4 (user interview, 2026-08-09): placement decided — invite-code step is
  the FIRST v3 step (before the demo race), not after it; scope widened to
  include part C (clipboard-handoff instrumentation + contingent
  deferred-read hardening) and part D (two-tier coarse-network IP fallback
  with `link_opens.ip_net_hash`, per-tier source stamping, env kill switch).
  Structural-order test expectation updated accordingly.
- v5 (gap pass 3, post-interview): tier-2 design hardened — no fall-through
  from an ambiguous/hot tier-1 (stronger evidence of a shared network);
  IPv6 prefix computed on the expanded form; part C ships classification
  and safe plumbing now, behavioral clipboard changes contingent on funnel
  data; `install_attr_*` flush is stash-locally-then-emit-after-auth
  because the service runs before sign-in.
- v6 (architect review, verdict REVISE, all 10 REQUIRED folded):
  (1) `referredByCode` already ships on every auth payload (raw-row spread,
  `routes.js:161-163`) — backend work reduced to the freshness fix only;
  (2) the "merge attributed code into returned object" option was a
  correctness bug (recordReferral declines silently) — replaced with
  `recordReferral` returning `{attributed, code, source}` + a negative
  unknown-code test; (3) part-C outcomes moved from a context key to
  name-encoded events (unknown context 400s and wedges the retained
  analytics batch; unknown names soft-drop); (4) tier 2 now defaults OFF
  pending per-day audit data, and manual redeem replaces a PENDING
  `ip_fallback_net` attribution so explicit intent can never be permanently
  pre-empted by an IP guess; (5) null `ipNetHash` skips tier 2 (legacy-NULL
  match hazard); (6) `findLinkOpenReferralCode`'s return-shape change
  documented as a DI contract break with both call sites updated in the
  same commit; (7) MainShell-owned plumbing contract specified (props,
  done-flag ownership, no-flash pre-load rule); (8) test-plan/show-condition
  contradiction on `welcomeReferralCode` resolved in favor of the show
  condition; (9) sign-out cleanup corrected — no allKeys wildcard exists;
  the done-flag joins `OnboardingStateService.allKeys` + its pinning test;
  (10) authMeCache staleness bounded correctly (≤10s, flag-gated) and
  `referredByCode` added to its inventory. Suggestions adopted: IPv4-mapped
  IPv6 normalization, once-per-install note for the deferred paste read,
  per-day audit breakdown, equal-weight skip button + `home_reached`
  baseline comparison, redeem-after-tier-2 and no-flash tests, citation
  fixes.
