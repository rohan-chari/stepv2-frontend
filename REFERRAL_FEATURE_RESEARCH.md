# Friend Referral Program — Research & Design

**Status:** Research / pre-implementation. Deliverable is a design, not code.
**App:** Bara (iOS, native APNs) + Android (Health Connect, Google Sign-In, FCM), single Flutter codebase, Node/Express + Prisma backend (`steptracker-api.org`).
**Governing constraint:** CLAUDE.md core rule — *never break users on older app versions*. The prod backend serves all app versions at once; reads must be defensive; do not depend on brand-new fields old clients won't send; iOS and Android ship in lockstep.

---

## 1. Executive summary

Build a **server-authoritative, single-sided-first referral program** where an existing user shares an invite link, a new friend installs and signs in, and **the referrer earns coins only once that friend completes their first *qualifying* race**. Reuse the infrastructure that already exists almost end-to-end:

- **Attribution:** Do **not** adopt a paid MMP for the MVP. Use a **self-hosted `/r/<code>` web landing page** (the one already serving race share links via `src/web/raceLandingPage.js`) with **platform-native auto-resolution first, and a manual referral-code field shown *only* when auto-resolution finds nothing**:
  - **Android** — Play Install Referrer returns the code **silently and deterministically**; the user is never asked.
  - **iOS** — on first launch, `UIPasteboard.detectPatterns(for:[.probableWebURL])` **silently** checks whether the invite URL is on the clipboard (no permission prompt); if present, a single **`UIPasteControl`** button (iOS 16+, one tap, **no "Allow Paste?" alert**) reads and applies it. Only if nothing auto-resolves does the manual field appear.
  - The landing page copies the **full invite URL** (not a bare code) so `detectPatterns` can sense it silently.
  - **App Clips were evaluated and rejected** — the only truly prompt-free iOS path, but the Flutter engine (~13–15 MB) exceeds Apple's 10 MB (15 MB on iOS 16+) App Clip limit, so it would require a separate native-Swift target (breaks one-codebase / lockstep). See §3.

  The manual code remains the guaranteed source of truth for the long tail deferred matching misses (~20–40% on iOS). Branch is the documented upgrade path if match rates disappoint.
- **Capture pattern:** Mirror the existing `pendingShareToken` machinery (`auth_service.dart` `setPendingShareToken` → `MainShell._maybeDrainPendingSharedRace`) with a sibling `pendingReferralCode` (with a **capture timestamp + max-age**), threaded into `provisionAppleUser` / `provisionGoogleUser` only when present.
- **Reward trigger:** Hook the **single settlement convergence point `src/commands/completeRace.js`**, gated by an **insert-ledger-row-first `ReferralRewardGrant`** mirroring `OnboardingBoxGrant` (`joinRaceCore.js`), whose **enforced dedup key is the provider-sub hash** (`appleSubHash.js`) so it survives delete+reinstall.
- **Coins:** Granted via the canonical idempotent `awardCoins({userId, amount, reason:'referral_reward', refId})`.
- **Notify:** New `REFERRAL_REWARDED` event → notification subscriber pushing the referrer via the existing `sendNotificationToUser` primitive. Old binaries show the alert but do **not** deep-link unknown `type` strings; only updated apps route.
- **Policy:** Reward the friend too **only if** their reward is gated on *their own* first race (never install/registration), to satisfy Apple 3.2.2 and Google Play. MVP ships single-sided (referrer-only) to de-risk; double-sided is a fast follow.

Everything is purely additive on the backend; no existing response shape changes; older frozen binaries are unaffected.

> **Hard prerequisite before any link works (see §3 and §11.10):** the backend's Universal/App-Link verification config (`src/config/sharing.js`) still ships placeholder `IOS_APP_ID` (`TEAMID…`) and empty `ANDROID_SHA256_FINGERPRINTS`. Until those are set to real prod values, AASA/assetlinks won't verify and *even the already-installed easy case* falls to the browser. This is a blocker, not an open question.

---

## 2. End-to-end flow

Two qualifying milestones matter: **(M1) friend signs up** (attribution recorded, no coins yet) and **(M2) friend completes their first *qualifying* race** (referrer — and optionally friend — paid). "Qualifying" is defined precisely in §5C/§8 to defeat trivial-race farming.

### 2A. Referrer perspective

1. **Discover the program.** Entry points (best-converting first):
   - Post-race **win/results** moment — a CTA on the dismiss path of `RaceResultsSummaryScreen` / `_maybeShowRaceResults` (`main_shell.dart`).
   - Permanent **"Invite friends"** row in the profile/account tab.
   - Optional home-screen card.
2. **Tap "Invite friends."** App calls `createReferralLink` (new, modeled on `createRaceShareLink` POST `/races/<id>/share-link`). Backend lazily mints/returns the user's stable `referralCode` + a backend-built `url` (`https://steptracker-api.org/r/<code>`). Client never builds the URL.
3. **Share.** App opens the native share sheet via `shareText()` (`lib/utils/share_helper.dart`) with benefit-framed, editable copy embedding **both the link and the raw code**:
   > "I'm racing on Bara — bet you can't out-step me. Use my code **BARA-7F3K** — I earn coins when you finish your first race: https://steptracker-api.org/r/BARA-7F3K"

   User picks SMS/WhatsApp/etc. (90%+ of referral traffic).
4. **Track status.** A referral dashboard (new screen, fed by `fetchReferralStatus` GET `/referrals/me`) shows per-friend stage badges **Invited → Joined → Completed first race** plus coins earned and a "X away from your next reward" meter.
5. **Get paid + notified.** When a referred friend hits **M2**, backend grants coins via `awardCoins` and pushes "Your friend completed their first race — you earned N coins!" The next `fetchMe` / session refresh (`applyBackendUser`, `auth_service.dart`) reflects the new `coins` balance.

### 2B. Invited friend perspective

**Case A — app NOT installed (the hard, common case):**
1. Friend taps `https://steptracker-api.org/r/<code>` in SMS.
2. OS finds no app matching the Universal/App Link → browser loads the backend-rendered landing page (`raceLandingPage.js`, plus a new referral sibling — see §5A). Page shows who invited them + store CTAs.
   - **iOS:** the page surfaces an explicit **"Use my invite & continue to App Store"** tap (a user gesture is required for a Safari clipboard write — see §3) that copies the **full invite URL** (`https://steptracker-api.org/r/<code>`, *not* a bare code — so iOS `detectPatterns` can later sense it silently), then routes to the App Store.
   - **Android:** landing page redirects to the Play Store URL with `&referrer=<code>` baked in.
3. Friend installs, opens app → `StartScreen` → Sign in with Apple (iOS) / Google (Android).
4. **Code recovery on first launch — automatic when present, manual *only* as fallback:**
   - **Android:** Play Install Referrer API returns `referrer=<code>` **silently and deterministically** → attributed automatically; the user is never asked.
   - **iOS:** `UIPasteboard.detectPatterns(for:[.probableWebURL])` runs **silently (no prompt)**; if an invite URL is present, show a single **`UIPasteControl`** button (iOS 16+) — one tap reads it **without the "Allow Paste?" alert** (the tap *is* consent) → validate domain/code → attributed automatically. (iOS <16 falls back to the one-time system prompt or manual.)
   - **Manual referral-code field** is shown **only when nothing auto-resolves** (organic installer, or iOS user who didn't copy) — ideally a low-key "Have an invite code?" entry, not a forced blank field. It is the guaranteed fallback and the source of truth for crediting.
5. Referral code persisted immediately (sibling of `setPendingShareToken`, with capture timestamp) so it survives sign-in/onboarding gap, then threaded into `provisionAppleUser`/`provisionGoogleUser` body as `referralCode`. **(M1)** Backend records attribution in the new-user create branch only, deduped on the referee's provider-sub hash.
6. Tailored welcome: "X invited you — finish your first race and you both earn coins." Skip redundant onboarding.
7. Friend joins + runs a qualifying race. On settlement **(M2)**, `completeRace.js` detects this is their first qualifying completed race, fires the referrer reward (and, if double-sided, the friend's reward). Friend sees their own confirmation; pending code is cleared.

**Case B — app ALREADY installed:**
1. Friend taps the link → Universal Link (iOS) / App Link (Android) opens the app directly with the referral context (the easy case, handled by `DeepLinkService` — **once AASA/assetlinks actually verify in prod**, §3/§11.10).
2. But: an existing user already has an account; attribution is only written in the **new-user create branch**, so an already-onboarded user cannot be (re)attributed (self-referral / re-attribution guard). A delete-and-reinstall human creating a "new" account is caught by the **provider-sub-hash attribution guard** (§4B/§8), not just by `refereeId`.

---

## 3. The attribution problem and recommended solution

### The crux
A friend **without the app** taps an SMS link → installs from the store → on first launch we must know **who referred them**. This is deferred deep linking + install attribution, and the two platforms are **fundamentally asymmetric**.

### Options from the research

| Option | iOS | Android | Reliability | Cost | Verdict |
|---|---|---|---|---|---|
| **Play Install Referrer API** | n/a | Deterministic; reads `referrer=<code>` baked into Play URL on first launch | High (Play installs only; not sideload/OEM) | $0 but **net-new** plugin + native dep | **Adopt (Android)** |
| **iOS clipboard handoff** (`detectPatterns` + `UIPasteControl`) | Landing page copies the *invite URL* on a tap → app silently `detectPatterns` for a URL (no prompt) → one-tap `UIPasteControl` reads it (no scary alert, iOS 16+) | n/a | **Medium** — Safari needs a gesture to write; one user tap to read; iOS <16 falls back to prompt | $0 | **Adopt (iOS convenience)** |
| **App Clips** (native deferred, no clipboard) | Tap → App Clip launches, passes referral to full app via shared Keychain / App-Group | n/a | High *if it fit* | $0 SDK, large native build effort | **Reject — Flutter engine (~13–15 MB) exceeds the 10/15 MB App Clip limit; needs a separate native-Swift target (breaks one-codebase/lockstep)** |
| **Manual referral code on first launch** | ✓ | ✓ | ~100% of users who type it; the only guaranteed path | $0 | **Adopt (both, source of truth)** |
| **Probabilistic IP/fingerprint match** | Degraded badly (ATT, iOS 17 manifest, Private Relay) — 20–40% miss | n/a | Low on iOS | varies | **Reject** |
| **SKAdNetwork / SKAN** | Aggregated, non-user-specific by design | n/a | Cannot do per-user referral | $0 | **Reject** |
| **Apple Custom Product Pages / campaign tokens** | Channel-level analytics only; no per-referrer payload | n/a | N/A for friend-to-friend | $0 | **Reject** |
| **Firebase Dynamic Links** | **Dead — 404 since Aug 25, 2025** | dead | — | — | **Forbidden** |
| **Branch / AppsFlyer / Adjust (MMP)** | One SDK abstracts both; NativeLink best-in-class deferred | ✓ | High | Branch free ≤10K MAU then ~$300+/mo; AF/Adjust enterprise | **Defer — documented upgrade path** |

### Recommendation: DIY landing page + manual code, with platform-native auto-fill

**Lowest-complexity-that-works for a research/MVP:**

1. **Own the redirect.** SMS links point to **a `/r/<code>` web landing page on a domain we control** (already live: `src/app.js:81` `GET /r/:token`, `raceLandingPage.js`, served for host `steptracker-api.org` per `src/config/sharing.js`). This indirection means we can swap vendors later without breaking links already in the wild — exactly what Firebase Dynamic Links used to give us, and the lock-in we avoid by not letting an MMP own the share domain.
   - ⚠️ **This is not free reuse.** `GET /r/:token`, `getSharedRacePreview.js`, and the client `parseShareToken` are all *race-share-token* specific (they resolve a `Race` via `findByShareToken`). Referral codes need their own resolution path **and a concrete disambiguation scheme**, because race tokens and referral codes both satisfy the same `^[A-Za-z0-9_-]{1,128}$` regex. **Use a reserved prefix** (e.g. all referral codes start with `BARA-`/`r_`) so `/r/:token` and `parseShareToken` can branch deterministically. Budget this as real backend + client build work, not reuse.
2. **Android = Play Install Referrer.** Landing page redirects to Play Store with `&referrer=<code>`; app reads it deterministically on first launch via a **net-new** Flutter plugin + Android native dependency. Free, reliable on genuine Play installs, ~1–2 days. **Lockstep footgun (CLAUDE.md):** even an Android-only dependency links into the iOS build, so build and verify **both** platforms after adding it.
3. **iOS = silent `detectPatterns` → one-tap `UIPasteControl`, manual only as fallback.** Two real constraints, handled rather than glossed: (a) a web landing page **cannot** write the iOS clipboard on load — Safari blocks clipboard writes without a user gesture — so the landing page needs an explicit **"Use my invite & continue"** tap that copies the **full invite URL** (not a bare code); (b) we must **not** blind-read the clipboard on every launch (fires the "Allow Paste?" alert for everyone, including organic installers). Instead, on first launch call **`UIPasteboard.detectPatterns(for:[.probableWebURL])`** — this **silently** (no prompt) reports whether a URL is on the clipboard. **If present**, render a single **`UIPasteControl`** button (iOS 16+): the user taps once and the value is read **without the permission alert** (the tap *is* consent). Parse the `/r/<code>` code from the URL and validate it's our domain, then attribute. **If `detectPatterns` finds nothing**, skip straight to the manual field. Net: the friend sees *at most one tap* and *only when a code actually exists*; organic users are never prompted. (iOS <16, which lacks `UIPasteControl`, falls back to the one-time system prompt or manual entry.)
4. **Both = manual code field** in onboarding, **pre-filled** from (2)/(3) when available. Treat the **manual code as the source of truth for crediting**; auto-fill is convenience that means most users never type.
5. **Universal Links / App Links** (configured in `Runner.entitlements`, `AndroidManifest.xml`, AASA/assetlinks via `deepLinkFiles.js`) handle the **already-installed** case directly — **but only once verification actually passes in prod** (see prerequisite below).

**iOS vs Android asymmetry to internalize:** Android gives you a first-party, deterministic, *silent* referrer string; iOS gives you **nothing** at the OS level for per-user referral, so iOS leans on a clipboard handoff (reduced to a single `UIPasteControl` tap behind the silent `detectPatterns` gate) + manual code (guaranteed). **App Clips** are the only native prompt-free alternative but are **not viable in Flutter** (engine size exceeds the App Clip limit; would need a separate Swift target) — evaluated and rejected. Budget iOS engineering for the gap specifically.

**Prerequisite — Universal/App-Link verification must be fixed first (blocker):** `src/config/sharing.js` still has placeholder `IOS_APP_ID` (`TEAMID…`) and empty `ANDROID_SHA256_FINGERPRINTS`. Until real values are set, AASA/assetlinks won't verify and the **already-installed** case silently falls to the browser. Also reconcile hosts: the native configs list `barastep.com` as *primary*, but the backend only mints/serves for `steptracker-api.org` (`buildShareUrl(token)` → `steptracker-api.org/r/<token>`). This design uses `steptracker-api.org` throughout (correct); **confirm whether `barastep.com` AASA/assetlinks are actually served and verifying** before relying on that host.

**Reuse-vs-new for the link namespace:** Keep referral links under the **existing `/r/*` path** that AASA/assetlinks already claim. A distinct `/i/<code>` namespace would require new AASA components entries (`deepLinkFiles.js`), new client App-Link intent filters (all three native configs), and fresh universal-link verification. **Recommendation: reuse `/r/*`**, disambiguating referral codes from race share tokens via the reserved prefix above. (Open question 11.7.)

**Firebase note:** Do **not** build on Dynamic Links or `*.page.link` — dead and 404ing since Aug 25, 2025. Any legacy `page.link` SMS links already sent are permanently broken; nothing to migrate, just don't reintroduce.

**ATT note:** None of the chosen methods (Play Install Referrer, clipboard, manual code) require ATT consent — they're for referral UX, not cross-app IDFA tracking. Confirm a `PrivacyInfo.xcprivacy` privacy manifest already ships declaring the Required-Reason APIs we touch (`UserDefaults`, and `UIPasteboard` for the clipboard read); if not, add it — it is mandatory for App Store approval.

**Upgrade path:** If DIY iOS match rates prove too low, adopt **Branch** (free ≤10K MAU, NativeLink clipboard DDL, one Flutter SDK across both platforms). Because our share domain stays ours, switching is non-breaking. Avoid AppsFlyer/Adjust unless we also need paid-acquisition measurement.

---

## 4. Data model changes

All additions are **nullable/defaulted and additive** — old rows and old clients unaffected; migration deploys to prod *before* any app build depends on them.

### 4A. `User` model additions (`prisma/schema.prisma`, near `rankedTierV2` ~line 56)

Attribution is recorded **only** in the dedicated `Referral` table (single source of truth). On `User` we keep just a unique `referralCode` and an **audit-only** `referredByCode`. We deliberately **do not** add a `referrerId` self-relation — that would be a second copy of who-referred-whom that can diverge from `Referral`.

```prisma
// --- referral attribution (all nullable/additive) ---
referralCode    String?  @unique @map("referral_code")   // this user's own shareable code
referredByCode  String?  @map("referred_by_code")        // code they signed up with (AUDIT ONLY)

// back-relations for the new tables (Referral is the single source of truth for who→whom)
referralsMade     Referral[]            @relation("ReferralsMade")
referralReceived  Referral?             @relation("ReferralReceived")
referralGrants    ReferralRewardGrant[]
```

### 4B. `Referral` table — attribution ledger (mirrors `StepMilestoneClaim` / `OnboardingBoxGrant` dedicated-ledger pattern)

The enforced dedup is on the **referee's provider-sub hash**, not on the freshly-minted `refereeId` — so a delete-and-reinstall human cannot be re-referred for a second attribution.

```prisma
model Referral {
  id              String   @id @default(uuid())
  referrerId      String   @map("referrer_id")
  refereeId       String   @unique @map("referee_id")
  refereeSubHash  String   @map("referee_sub_hash")   // hashAppleSub(referee appleId||googleSub)
  code            String?                              // code used, if any
  status          String   @default("PENDING")        // PENDING -> QUALIFIED -> REWARDED
  createdAt       DateTime @default(now()) @map("created_at")

  referrer User @relation("ReferralsMade",   fields: [referrerId], references: [id], onDelete: SetNull)
  referee  User @relation("ReferralReceived", fields: [refereeId],  references: [id], onDelete: Cascade)

  @@unique([refereeSubHash])     // each HUMAN referred at most once, EVER (survives reinstall)
  @@index([referrerId])
  @@map("referrals")
}
```

> **`onDelete` choice (critique #11):** `referrer` uses `SetNull` (not `Cascade`) so that a referrer deleting their account does **not** silently destroy the `Referral` row and, in double-sided mode, does **not** also wipe the referee's pending reward. The reward-granting code must tolerate a null `referrerId` (skip the referrer payout, still grant the referee). If Prisma requires `referrerId` non-null for `SetNull`, make `referrerId` nullable. Document the chosen policy explicitly — see §11.5.

### 4C. `ReferralRewardGrant` table — payout ledger (mirrors `OnboardingBoxGrant` insert-first idempotency)

The **enforced** exactly-once key is the **provider-sub hash + role**, so the referrer can be paid at most once per real human per role even across reinstall/new-account farming. `referralId` is recorded for joins but is **not** the dedup key (it derives from a reinstallable `refereeId`).

```prisma
model ReferralRewardGrant {
  id            String   @id @default(uuid())
  referralId    String?  @map("referral_id")    // nullable so a SetNull'd referral doesn't cascade-delete the audit row
  userId        String?  @map("user_id")        // who received the reward; nullable + SetNull (see note) — null once that account is deleted
  role          String                          // "REFERRER" | "REFEREE"
  refereeSubHash String  @map("referee_sub_hash") // abuse key: provider-sub hash of the REFEREE
  coins         Int?
  grantedAt     DateTime @default(now()) @map("granted_at")

  referral Referral? @relation(fields: [referralId], references: [id], onDelete: SetNull)
  user     User?     @relation(fields: [userId],     references: [id], onDelete: SetNull)

  @@unique([refereeSubHash, role])   // EXACTLY-ONCE PER HUMAN PER ROLE — the real anti-farming guard
  @@index([refereeSubHash])          // velocity / abuse queries keyed to a stable human
  @@index([userId])
  @@map("referral_reward_grants")
}
```

> **`onDelete` for `userId` (anti-farm survival — corrected during build):** `userId` is **nullable + `SetNull`**, *not* `Cascade`. The abuse-dedup row must **outlive the account** (exactly like `OnboardingBoxGrant`, which has no user FK at all). If a referee's `REFEREE`-role grant were cascade-deleted when they delete their account, a delete+reinstall referee would land in a fresh `refereeSubHash` slot and could **re-farm their own reward** (§8.2) — a *live* exploit now that we ship double-sided. `SetNull` keeps only the hash + role (no PII), preserving the exactly-once guard forever. Because every referencing FK then resolves to Cascade or SetNull, `tx.user.delete()` in `deleteUserAccount.js` needs no change.

> **Critique #1 fix (required, not optional):** The enforced unique is `@@unique([refereeSubHash, role])`. Inserting this row **first** inside the grant `$transaction` is what makes the payout exactly-once across delete+reinstall — the previous `@@unique([referralId, role])` did NOT, because `referralId` is regenerated on every reinstall (new account → new `Referral` → new `referralId`), so the unique never collided and the referrer was paid again. `appleSubHash` (here `refereeSubHash`) must be the *enforced* key, exactly as `OnboardingBoxGrant.appleSubHash @id` is.

**Why both a `Referral` row and a `ReferralRewardGrant` row:** `Referral` records *attribution* (who referred whom — captured at signup, M1). `ReferralRewardGrant` records *payment* (which side was paid — minted at first-race completion, M2). The coin ledger `CoinTransaction` (`reason='referral_reward'`, `refId`) only prevents double-pay; it does **not** record attribution or survive reinstall.

### 4D. `CoinTransaction` — **no schema change required for `reason`**, but add a unique guard
`reason` is free-form (no enum), so `reason='referral_reward'` needs no migration. **However**, the existing `@@index([userId, reason, refId])` is **non-unique**, so `awardCoins`' app-level findFirst-then-create can double-grant under concurrency. **Recommended migration: add `@@unique([userId, reason, refId])`** as defense-in-depth. The `ReferralRewardGrant` insert-first `@@unique([refereeSubHash, role])` is the primary guard.

> **Critique #13 (mandatory, scoped to Phase 0):** the historical non-unique index may already have produced duplicate `(userId,reason,refId)` rows in prod; the unique migration **will error** on them. A pre-apply dedupe/backfill check against prod data is **required**, not advisory, before the constraint can be added.

---

## 5. Backend implementation

### 5A. New endpoints (additive; old backends 404, clients degrade)

| Method | Route | Auth | Purpose | Modeled on |
|---|---|---|---|---|
| POST | `/referrals/link` | Bearer | Lazily mint/return `{ code, url }` | `createRaceShareLink.js` |
| POST | `/referrals/redeem` | Bearer | Attach a referrer **after** signup (the iOS-`UIPasteControl`-tap / manual-entry path, where the code wasn't in the provision body). Guarded: only if not already attributed, within the attribution window, and **before the user's first completed race** | new (mirrors `joinRaceByShareToken`) |
| GET | `/referrals/me` | Bearer | `{ code, url, referredCount, coinsEarned, friends:[{stage,…}] }` | `fetchMe` / `fetchDailyRewardStatus` |
| GET | `/referrals/:code` | **none** | Public preview `{ inviterName, inviterAvatar, rewardCoins }` (allowlist, HTML-escaped, no PII) | `getSharedRacePreview.js` |

- The public `GET /referrals/:code` **must be declared before `requireAuth`** in its router (mirror the `races.js` ordering where `GET /races/share/:token` is registered before the auth middleware and before `GET /:raceId`) or it 401s / is mis-parsed.
- Public preview **must** follow the display-safe allowlist of `getSharedRacePreview.js`: never leak `referrerId`, internal ids, or coin internals; HTML-escape all user-controlled fields (inviter display name) exactly like `raceLandingPage.js`.

### 5B. Attribution capture (M1) — at account creation only

- `src/routes/auth.js`: `POST /auth/apple` (~line 90) and `POST /auth/google` (~line 130) read `referralCode` off `req.body` (alongside `identityToken`/`idToken`), pass it into the provisioners. **Edit both in lockstep.**
- `src/services/ensureAppleUser.js` and `src/services/ensureGoogleUser.js`: **only inside the `if (!user) { … userModel.create() }` new-user branch** (~lines 79–95):
  1. Resolve the referrer via `userModel.findByReferralCode(referralCode)`.
  2. Compute `refereeSubHash = hashAppleSub(newUser.appleId || newUser.googleSub)` (`src/utils/appleSubHash.js`).
  3. Write `referredByCode` (audit) on the user, and **create a `Referral` row** (`referrerId`, `refereeId=newUser.id`, `refereeSubHash`, `code`, `status:'PENDING'`). The `@@unique([refereeSubHash])` makes this a no-op (catch P2002, swallow) if this human was already referred under a prior account — closing the reinstall re-attribution hole.
- Writing only in the create branch guarantees attribution can't be overwritten on later re-sign-ins (provisioners run on **every** sign-in) and existing users can't be re-attributed.
- **Guards (signup must NEVER fail on a bad code):**
  - `findByReferralCode` null → skip silently.
  - resolved `referrerId === newUser.id` → reject (self-referral).
  - Identities are never linked by email (nullable, Apple private relay) — key everything on user id / provider sub.
- **Multiple invites to the same person (critique #9):** because attribution is written exactly once (first create that wins the `refereeSubHash` unique), the policy is **first-capture-wins at account creation**. The captured code is whatever `pendingReferralCode` holds at provision time; make capture deterministic by **not overwriting an already-persisted, non-expired `pendingReferralCode`** with a later tap (first link tapped wins). Document this.
- **Generate `referralCode`:** lazily on first `/referrals/link` call (or in the create branch), collision-retry against `findByReferralCode`, using the existing `pickUniqueDisplayName` random-pick pattern in `ensureAppleUser.js` as the model, with the reserved `BARA-`/`r_` prefix from §3. Backfill existing users lazily on first request rather than a big migration.
- **Decoupled alternative:** process attribution in the `USER_REGISTERED` listener (`src/handlers/eventHandlers.js`) — but that requires adding `referralCode` to the emitted payload. The create-branch approach is simpler and synchronous; prefer it for MVP.
- **Two capture timings (both converge on the same `Referral` write):** (1) a code captured **before sign-in** (deep link / Play Install Referrer / an iOS `UIPasteControl` tap that completed pre-provision) rides the `provisionApple/GoogleUser` body and is written in the create branch as above; (2) a code resolved **after** account creation (iOS tap or manual entry during onboarding) is attached via `POST /referrals/redeem`, which writes the same `Referral` row under the same guards (`refereeSubHash @unique`, self-referral check, attribution window, and **only if the user has no completed race yet**). Both are idempotent on `refereeSubHash`, so a code that arrives via both paths cannot double-attribute.

### 5C. First-qualifying-race trigger (M2) — the reward fire

**The single convergence point is `src/commands/completeRace.js`** — both settlement paths funnel through it: `raceExpiry.js` (deadline cron, `:131`) and `raceStateResolution.js` (target-reached, `:679`). (`getRaceProgress.js` imports `completeRace` and assigns it but **never calls it** — a leftover, *not* a third caller; verified 2026-06-26.) `raceModel.updateIfActive` (`src/models/race.js:127`) makes the settlement body run **exactly once per race**. **Hook here once; never hook the individual callers.** (Cancelled/refunded races go through a *separate* `RACE_CANCELLED`/buy-in-refund path, not `completeRace`, so they correctly never fire a referral reward.)

After placements are settled (the eligible loop, `completeRace.js:109–122`), loop participants and call a new best-effort `maybeGrantReferralReward({ participant, race })`, mirroring `maybeGrantOnboardingBoxes`:

1. **Per-participant settlement eligibility:** `status==='ACCEPTED'`, `placement != null`, `totalSteps > 0` (a settled finisher, not a no-show).
2. **Qualifying-race legitimacy (critique #2 — closes trivial-race farming):** `totalSteps > 0` alone does **not** stop a referee from spinning up a solo throwaway race and "winning" it to mint the referrer payout. Require the race to be a **genuine multi-party contest**, e.g.:
   - the race is **public/seeded** (not a self-created private 1-person race), **and/or**
   - it had **≥2 distinct ACCEPTED human participants** who actually accrued steps.

   Define the exact predicate with product (§11.3); without it, the "complete a real race" gate is the highest-ROI abuse vector.
3. **Is this their first *qualifying* completed race?** The `ReferralRewardGrant` insert-first `@@unique([refereeSubHash, role])` *is* the first-completion gate — a second qualifying race for the same human collides and aborts before any coin mints. (`updateIfActive` only guarantees once-per-*race*; a human completes many races, so first-completion gating must be its own check — and it must be keyed to the **human**, not `userId`.)
4. **Look up the referral:** `Referral` where `refereeId === participant.userId && status==='PENDING'`. None ⇒ this user wasn't referred; return.
5. **Attribution-window check (critique #10):** optionally require `now - Referral.createdAt <= QUALIFY_WINDOW` (e.g. 30 days) so a stale attribution doesn't pay out indefinitely. If outside the window, mark `Referral.status='EXPIRED'` and skip.
6. **Grant — insert ledger FIRST (`joinRaceCore.js:93–98` pattern), with independent transactions per role (critique #12):**
   - **Referrer (only if `Referral.referrerId` is non-null — referrer may have deleted their account, §4B):** in its own `$transaction`,
     `tx.referralRewardGrant.create({ referralId, userId: referrerId, role:'REFERRER', refereeSubHash, coins: BONUS })` — a P2002 means *already rewarded*; catch and swallow. Then `awardCoins({ userId: referrerId, amount: BONUS, reason:'referral_reward', refId: 'referral:'+referral.id+':REFERRER' })`. On success, emit `REFERRAL_REWARDED { referrerId, refereeId, coins }`.
   - **Referee (double-sided only):** in a **separate** `$transaction`, `role:'REFEREE'`, `refId: 'referral:'+referral.id+':REFEREE'`, `userId: refereeId`. Independent so a P2002 on one role never aborts the other's grant.
   - Update `Referral.status` to `'REWARDED'` once the applicable side(s) are paid.
7. **Wrap everything in try/catch** so a failure never breaks payouts/settlement (settlement correctness is priority; `joinRaceCore.js:67`).
8. Use `user.appleId || user.googleSub` for the hash — a null-only-appleId path silently skips Android users (the exact bug previously fixed in `joinRaceCore.js:80`).

### 5D. Notify the referrer (push)

`RACE_COMPLETED` carries only `{raceId, winnerUserId, participantUserIds}` — no per-user first-race info — so emit a **dedicated `REFERRAL_REWARDED` event from `completeRace` after the grant tx commits** (mirrors `joinRaceCore`'s deferred emit-after-commit), carrying `{referrerId, refereeId, coins}`, gated on the grant having actually fired (no row already existed).

Add an `events.on('REFERRAL_REWARDED', …)` subscriber alongside `notificationHandlers.js:251`, calling the canonical `sendNotificationToUser({ recipientUserId: referrerId, actorUserId: refereeId, title, buildBody: name => name + ' completed their first race — you earned ' + coins + ' coins!', payload:{ type:'REFERRAL_REWARDED' } })`. This reuses the device-token fan-out → APNs/FCM routing → audit row.

> **Critique #3 fix — notification routing, stated correctly:** The client maps the payload **`type`** string in `_routeFromType` (notification_service.dart:293–324), **not** a separate `route` field. `REFERRAL_REWARDED` is a **brand-new `type`**, so **already-shipped binaries cannot deep-link it** — their `_routeFromType` returns null for an unknown `type`, which means the alert still **displays** but tapping it does **not** navigate (per the `PLACEMENT_CHANGED` precedent). This is acceptable and forward-compatible. To make *updated* apps deep-link, add a `case 'REFERRAL_REWARDED' → NotificationRoute.home` (an existing route) in the shared `_routeFromType`, handling both iOS (nested `params`) and Android (flat/stringified `params`) payload shapes **in lockstep**. We do **not** claim old binaries deep-link — only that they harmlessly show the alert.

> **Critique #14 — copy correctness:** the reward fires on the referee's first *qualifying settled* race, which may not be literally their first race ever (e.g. a prior DNF). Word the push as "completed their first race" (the first one that qualifies/settled with a placement) and keep server-side the source of truth for what qualifies.

---

## 6. Frontend implementation

### 6A. Invite-link generation + share
- New `createReferralLink()` in `lib/services/backend_api_service.dart` (POST `/referrals/link` → `{code, url}`), following the `_sendJsonRequest` pattern of `createRaceShareLink` (`:802`). Client shares **only the backend-returned `url`** plus the code text — never builds the host/path itself.
- Share via existing `shareText()` (`lib/utils/share_helper.dart`) — the single share-sheet entry point — modeled on `race_detail_screen.dart` `_shareRace()` (`:2543`), with benefit-framed, editable copy embedding link + code.
- Entry points: post-win CTA on `RaceResultsSummaryScreen` dismiss (`main_shell.dart` `_maybeShowRaceResults` `:657–678`), a permanent profile row, optional home card. (The existing hard-coded App Store invite in `home_tab.dart:434` is the precedent for a generic "invite a friend" CTA — upgrade it to a real referral link.)

### 6B. Capture the referral token on first launch (mirror `pendingShareToken`)
- **Capture:** extend `DeepLinkService.parseShareToken` / `handleLink` (`deep_link_service.dart:37–103`) to recognize a referral link by the **reserved code prefix** under `/r/` (so it is unambiguously distinguished from a race share token, which matches the same regex). `main.dart:38–40` already captures the cold-start link before `runApp`, so tap-then-install is covered.
- **Auto-resolution sources (platform-specific, new):**
  - **Android:** Play Install Referrer plugin read on first launch → parse `referrer=<code>`, **silent**, attributed automatically. (Net-new Android native dep — verify the iOS build too, §3.)
  - **iOS:** via a platform channel, call `UIPasteboard.detectPatterns(for:[.probableWebURL])` — **silent, no prompt**. If a URL is present, render a **`UIPasteControl`** button; one tap reads it **without the "Allow Paste?" alert**, then parse the `/r/<code>` code from the URL and validate. **Never blind-read** the clipboard. (iOS <16 → one-time prompt or manual.)
- **Persist with expiry:** add a sibling to `pendingShareToken` in `auth_service.dart` — `_keyPendingReferralCode` + `_keyPendingReferralCapturedAt` + `setPendingReferralCode()` writing to `SharedPreferences` **immediately** (independent of `_persist`, which only runs on sign-in — mirror `:377–387`), so it survives the pre-account gap. **First-capture-wins:** do not overwrite an existing non-expired pending code with a later tap. **Max-age:** ignore/clear a captured code older than the configured window (critique #10). Ensure `signOut()` (`:354–368`) doesn't wipe it before consumption if an incidental sign-out occurs pre-attribution.
- **Manual field — conditional (the requested behavior):** show the referral-code input **only when no code auto-resolves** (Android install-referrer empty, or iOS `detectPatterns` found nothing / user didn't copy). When auto-resolution succeeds, attribution is silent (Android) or one-tap (iOS) and **no manual screen is shown at all**. Placement: a dedicated step right after `DisplayNameScreen` (pre-filled if a code is in hand), plus a permanent low-key "Enter invite code" affordance in the profile/account tab for users still inside the attribution window who skipped onboarding entry.

### 6C. Thread into provisioning
- In `signInWithApple` / `signInWithGoogle` (`auth_service.dart`), read the persisted (non-expired) referral code and pass it into `provisionAppleUser` (`backend_api_service.dart:98–123`) / `provisionGoogleUser` (`:129–148`), adding a `referralCode` field to the POST bodies (`:107–112`, `:137`) — **only when present** (mirror `joinPublicRace`'s `body: onboarding ? {...} : const {}` `:793`) so older backends ignore it.
- **Clear after a successful provision** (mirror `setPendingShareToken(null)` / drain consume-on-every-outcome `main_shell.dart:243`) so it isn't re-applied on a later re-login.
- **Codes resolved *after* sign-in** (an iOS `UIPasteControl` tap or manual entry during onboarding) won't be in the provision body — send them to `POST /referrals/redeem` instead (§5A/§5B). Same guards; both routes converge on one `Referral` row deduped by `refereeSubHash`.

### 6D. New-user welcome
- Tailored first-launch welcome fed by the public `fetchReferralPreview` (GET `/referrals/<code>`): show inviter name + avatar, the reward, and the qualifying action ("finish your first race — you both earn coins"). Skip redundant onboarding steps. After M2, show a confirmation.

### 6E. Referrer reward/status UI
- New referral dashboard screen fed by `fetchReferralStatus` (GET `/referrals/me`), read **defensively** (`decoded['friends'] as List? ?? []`, default all fields). Per-friend stage badges Invited → Joined → Completed-first-race + coins meter.
- Reflect granted coins: no new client work needed — the balance flows back via `applyBackendUser` `coins` (`auth_service.dart:298–303`) on the next `_refreshMe` (`main_shell.dart:319–329`). Reuse the existing coin-reward UI (`SpinningCoin`, the tutorial-reward grant flow `auth_service.dart:438–462`, `RaceResultsSummaryScreen` "+N" payout treatment).

---

## 7. Old-client compatibility

This is the **first** thing to verify, per CLAUDE.md. The feature is **purely backend-additive**:

1. **New tables/columns only** (`Referral`, `ReferralRewardGrant`, nullable `User.referralCode`/`referredByCode`). No change to any JSON shape an old client reads. Old rows: `referralCode`/`referredByCode` null ⇒ "no attribution," never an error.
2. **New endpoints 404 on old backends; clients tolerate it.** All referral calls degrade gracefully like `fetchFeaturedRaces` (`:770–780`) and best-effort `markRaceResultsSeen` (`:898–914`). Old app binaries simply never call them.
3. **Additive request fields sent only when present.** `referralCode` on `provisionApple/GoogleUser` is omitted by older binaries (which never send it) and ignored by older backends (which never read it). Conditional-body pattern (`:793`).
4. **Defensive reads.** `fetchReferralStatus` consumers default safely on missing/null (the backend may be a different version than the running app). `applyBackendUser` already only overrides `coins` when the key is present (`:281–315`).
5. **Backend-first deploy ordering.** The migration adding columns/tables ships to prod **before** any app build depends on them. Prod serves all versions at once.
6. **Reward works with zero client cooperation.** Server-enforced first-qualifying-race detection in `completeRace.js` (like `OnboardingBoxGrant`, which never trusts a client flag) means even already-shipped binaries that know nothing about referrals still trigger referrer payouts when their referred friend finishes a qualifying race.
7. **New notification `type` is forward-compatible — but does NOT deep-link on old apps.** `REFERRAL_REWARDED` is unknown to shipped binaries; their `_routeFromType` returns null, so the alert **displays** but the tap does not navigate (the `PLACEMENT_CHANGED` precedent). Only updated apps that add the new `case` deep-link. Edit the shared `_routeFromType` for both iOS (nested `params`) and Android (flat/stringified `params`) — **lockstep**.
8. **No new native verification work** if referral links stay under `/r/*` (existing AASA/assetlinks claim) — *contingent on the placeholder `IOS_APP_ID`/`ANDROID_SHA256_FINGERPRINTS` actually being set in prod (§3 prerequisite)*. Legacy host `steptracker-api.org` and `bara://` scheme handling must remain — links already in the wild.
9. **Idempotency-Key** header on any client-initiated coin-claim calls, via the `headers` param (`:1308`/`:1345`), so reinstalls/replays never double-grant.

---

## 8. Fraud / abuse prevention

The single most effective control is already in the design: **reward only on a real, qualifying, completed first race, server-validated** — never on link-click, install, or signup. Layered defenses:

1. **Gate on genuine M2.** Eligibility = settled `ACCEPTED` participant with `placement != null`, `totalSteps > 0`, **AND** the qualifying-race legitimacy predicate (§5C.2: public/seeded and/or ≥2 distinct real participants) — this closes the **self-created/solo throwaway-race** vector that `totalSteps>0` alone leaves open. Client cannot self-report completion; `completeRace.js` is server-authoritative.
2. **Provider-sub-hash keying is the ENFORCED dedup key, NOT userId.** Both the attribution row (`Referral.refereeSubHash @unique`) and the payout row (`ReferralRewardGrant @@unique([refereeSubHash, role])`, inserted first) are keyed on `hashAppleSub(appleId || googleSub)` (`appleSubHash.js`), so a delete-account+reinstall referee can be neither re-attributed nor re-farmed for a second payout. Keying on `userId`/`referralId` (which reset on reinstall) would be farmable — the exact anti-pattern the research warned against, and the reason `OnboardingBoxGrant` keys on `appleSubHash`.
3. **One attribution + one reward per human, ever.** `Referral.refereeSubHash @unique` + `ReferralRewardGrant @@unique([refereeSubHash, role])`, with the ledger row inserted **first inside the `$transaction`** so concurrent/duplicate attempts collide and abort before any coin mints (`joinRaceCore.js:98`).
4. **CoinTransaction race condition — fix it.** The coin ledger's `@@index([userId, reason, refId])` is **non-unique**, so two concurrent `awardCoins` with the same `refId` can both pass the findFirst check and double-grant. Add `@@unique([userId, reason, refId])` (with the **mandatory** prod dedupe/backfill check, §4D/§10), and always pass a **stable, deterministic `refId`** (`referral:${referralId}:${role}`) — `awardCoins` idempotency only fires when `refId` is non-null. The `ReferralRewardGrant` unique remains the primary guard.
5. **Self-referral guard.** Reject when resolved `referrerId === newUser.id`; attribution written only in the new-user create branch so existing users can't self-attribute.
6. **Attribution expiry / qualifying window.** Pending codes expire client-side (max-age, §6B); server enforces an optional signup→first-race qualifying window (§5C.5) so stale attributions don't pay out indefinitely.
7. **Velocity caps.** Cap rewarded referrals per referrer (e.g. flag/queue beyond ~20/day, ~100/month); the `ReferralRewardGrant @@index([refereeSubHash])` and per-referrer queries support this. Route outliers and high cumulative payouts to a manual-review queue before coins become spendable.
8. **Referral-ring detection.** Flag reciprocal referrals and clusters of low-engagement accounts (created → ran exactly one minimal race → never returned); withhold/claw back. The qualifying-race predicate + "first *qualifying* completed race" gate already filter trivial no-shows and solo races.
9. **Per-user referral-earnings cap per period** to bound downside from any undetected abuse.
10. **Exclude review/demo accounts.** `isReviewAccount` users excluded from referral counting/payout.
11. **Email is not a key.** Disposable domains and plus-addressing defeat email dedup; we key on provider sub + user id only (and email is nullable/non-unique anyway via Apple private relay).

**Note on device fingerprint/IP:** the app currently sends **no deviceId/fingerprint** (only OAuth sub + `X-Timezone`/`X-Release-Channel`/`X-App-Version`). The provider-sub-hash dedup + qualifying-race gate + velocity caps cover the MVP without it. Introducing a deviceId would be a new client+backend contract — defer to v2 if abuse data justifies it.

---

## 9. Reward economics and policy

### Single vs double-sided
- **Double-sided converts materially better** (~2.3× shares, ~1.8× conversion; ~91% of successful programs are double-sided).
- **But Apple 3.2.2 forbids rewarding the *recipient* for downloading or registering.** The friend may be rewarded **only for their own subsequent in-app action** — which in our design is *completing their first qualifying race*. That gating makes a friend reward compliant.
- **Google Play** allows loyalty/reward programs (rewards subordinate to a genuine qualifying transaction, documented rules) but bans incentivized installs and review manipulation.

**Recommendation:** Ship **MVP single-sided** (referrer-only, reward on referee's first qualifying-race completion) to de-risk and observe abuse. **Fast-follow double-sided** — add a `role:'REFEREE'` grant **gated on the same M2 (friend's first qualifying race)**, never on install/signup, in an independent transaction (§5C.6). Both sides' rewards stated identically across share message, dashboard, and welcome.

### Suggested coin amounts (relative to existing grants)
Calibrate against the existing reason taxonomy (`tutorial_complete`, `daily_reward`, `race_finish_reward`, etc.). A referral is higher-effort and rarer than a daily reward but should be bounded:
- **Referrer:** roughly **2–4× the tutorial/onboarding grant** (a referral that produces a retained, race-completing user is worth more than self-onboarding), subject to the per-period cap (§8).
- **Referee (v2):** roughly the **onboarding/tutorial grant size** — a welcome nudge, gated on their first qualifying race.

Final numbers are a product-owner call (open question 11.2).

### Compliance must-dos
- **Never** tie the reward to leaving an App Store review/rating — independently prohibited by both stores, up to developer expulsion.
- **Never** reward the friend for install/registration — only their own first qualifying race.
- **No cross-app "install this other app for coins"** mechanics (Google Play ban).
- **Publish official program rules in-app** (eligibility, what counts as a qualifying first race, caps) — Google Play expects documented reward-program rules and it reduces dispute ambiguity.
- **Server-authoritative** coin grants — client cannot forge completion.

---

## 10. Phased rollout plan

### Phase 0 — Backend foundation + prerequisites (deploy first, no client dependency)
- **Prerequisite (blocker):** set real `IOS_APP_ID` and `ANDROID_SHA256_FINGERPRINTS` in `src/config/sharing.js`; confirm AASA/assetlinks verify in prod for `steptracker-api.org` (and decide on `barastep.com`). Without this, no link works.
- **Mandatory data check:** prod dedupe scan of `CoinTransaction (userId, reason, refId)` before adding `@@unique` — the migration errors if historical duplicates exist.
- Migration: `User.referralCode`/`referredByCode`, `Referral` (with `refereeSubHash @unique`, `referrer onDelete: SetNull`), `ReferralRewardGrant` (with `@@unique([refereeSubHash, role])`), `@@unique([userId,reason,refId])` on `CoinTransaction`.
- `awardCoins` reason `referral_reward`; `maybeGrantReferralReward` hook in `completeRace.js` with the qualifying-race predicate; `REFERRAL_REWARDED` event + notification subscriber.
- Attribution capture in `ensureApple/GoogleUser` create branch (provider-sub-hash deduped); lazy prefixed `referralCode` generation; endpoints `/referrals/link`, `/referrals/redeem` (post-signin attach), `/referrals/me`, `/referrals/:code` (public route declared before `requireAuth`).
- **Deploy and verify in prod before any app build references these.** Frozen older binaries are unaffected (additive).

### Phase 1 — MVP (research stage)
- **Single-sided** (referrer-only) reward on referee's first qualifying completed race.
- Attribution via: **Android Play Install Referrer** (silent) + **iOS `detectPatterns` → `UIPasteControl`** (one tap, no scary prompt; landing page copies the *URL* not a bare code) + **manual code field shown only when auto-resolution fails** (source of truth) + Universal/App Links for already-installed. **App Clips rejected** (Flutter size limit). Post-signin codes attach via `POST /referrals/redeem`.
- Reuse `/r/*` landing page (extend `raceLandingPage.js` for referral preview; Safari clipboard write behind an explicit tap; reserved code prefix for disambiguation).
- Frontend: invite CTA at post-win + profile row; `pendingReferralCode` capture/persist-with-expiry/thread/clear; tailored welcome; referrer dashboard with stage badges.
- Referrer push on payout (alert shows on old apps; deep-links on updated apps only).
- Velocity caps + self-referral guard + provider-sub-hash dedup + qualifying-race predicate live from day one.
- iOS + Android built in lockstep (incl. the Android-only Play Install Referrer dep, which still links into the iOS build).

### Phase 2 (fast follow)
- **Double-sided** friend reward (gated on friend's own first qualifying race; Apple-compliant; independent transaction per role).
- Richer dashboard (progress meter, "check referrals" re-engagement), home-screen card.
- Anti-abuse v2: ring detection, manual-review queue UI, per-period earnings cap tuning.

### Deferred / v3+
- **Branch** (or MMP) only if DIY iOS match rates prove too low — non-breaking swap since we own the share domain.
- DeviceId/fingerprint contract (new client+backend) only if abuse data justifies.
- Distinct `/i/<code>` link namespace (requires native AASA/assetlinks + intent-filter work) only if `/r/*` coexistence proves problematic.
- Backfill `referralCode` eagerly for all users (vs lazy).

---

## 11. Open questions for the product owner

1. **Single vs double-sided at launch?** Recommended single-sided MVP; double-sided fast-follow. Confirm appetite and that the friend reward is acceptable to gate on *their* first qualifying race (Apple 3.2.2).
2. **Coin amounts** for referrer (and referee, v2) relative to tutorial/daily/race-finish grants? And the per-period referral-earnings cap value?
3. **What is a "qualifying" first race?** Recommended: first COMPLETED race that is public/seeded and/or had ≥2 distinct real ACCEPTED participants with steps (not a self-created solo race). Confirm the exact predicate — it is the primary anti-farming gate.
4. **Velocity thresholds** — what daily/monthly referral count triggers flag/manual review? Acceptable hold period before coins are spendable?
5. **Account-deletion policy, both sides:** Referee deletion — recommended the `refereeSubHash`-keyed ledgers make dedup survive deletion (anti-farming). Referrer deletion before M2 — recommended `onDelete: SetNull` so the referee can still be rewarded and the `Referral` isn't silently dropped; confirm whether a referrer who deleted their account should still be paid on return.
6. **`@@unique([userId,reason,refId])` migration** on `CoinTransaction` — confirm the prod dedupe scan and that removing/merging any historical duplicates is acceptable before applying.
7. **Link namespace + disambiguation:** confirm reusing `/r/*` (no native changes) and the reserved referral-code prefix (`BARA-`/`r_`) that lets `parseShareToken` and `GET /r/:token` separate referral codes from race share tokens.
8. **iOS attribution UX (largely resolved — confirm):** approach is (a) landing page copies the **full invite URL** behind an explicit "Use my invite & continue" tap; (b) app uses silent `detectPatterns(.probableWebURL)` + a one-tap `UIPasteControl` (iOS 16+) so there is **no "Allow Paste?" alert** and organic users are never prompted; (c) the **manual field appears only when auto-resolution finds nothing**. Confirm: the minimum iOS version (is an iOS 16 floor for `UIPasteControl` OK, or do we need the legacy prompt fallback for older iOS?), and that `PrivacyInfo.xcprivacy` declares the `UIPasteboard` Required-Reason API. **App Clips were evaluated and rejected** (Flutter engine exceeds the App Clip size limit; would need a separate native-Swift target) — confirm we're OK not pursuing them.
9. **`referralCode` generation:** lazy on first `/referrals/link` (recommended) vs eager backfill for all existing users?
10. **Universal/App-Link prerequisite:** confirm real `IOS_APP_ID`/`ANDROID_SHA256_FINGERPRINTS` are set and AASA/assetlinks verify in prod for `steptracker-api.org` (and whether `barastep.com` is also served), since `autoVerify` silently falls back to browser otherwise. This blocks even the already-installed case.
11. **Program rules copy:** product to provide the in-app official rules text (eligibility, qualifying action, caps) required for Google Play reward-program compliance, and confirm `PrivacyInfo.xcprivacy` already declares the `UIPasteboard`/`UserDefaults` Required-Reason APIs.
12. **Multiple/competing invites & attribution window:** confirm **first-capture-wins** (don't overwrite a non-expired pending code) and the max-age / signup→first-race qualifying window values.