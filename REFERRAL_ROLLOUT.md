# Referral program — rollout runbook

Everything code-complete for the friend-referral feature lives on the
`referral-program` branch in **both** repos. This is the turnkey checklist to
ship it. Order matters (CLAUDE.md: backend-first, never break older app builds).

- **Backend branch:** `stepv2-backend` `referral-program`
  - `Referral program backend: attribution + double-sided rewards`
  - `Referral anti-abuse: velocity caps + review-account exclusion`
  - `CoinTransaction: enforce (userId,reason,refId) idempotency at the DB`
- **Frontend branch:** `stepv2-frontend` `referral-program`
  - `Referral program frontend: capture, invite UI, dashboard`
  - `Referral: native auto-capture + tailored onboarding welcome`
  - `Referral: in-app program rules screen`

---

## 1. Values only you can supply (set, then everything works)

### a. Universal/App-Link verification — `src/config/sharing.js` (via env on the server)
Without these, AASA/assetlinks don't verify and **every** invite link falls back
to the browser, even for already-installed users.

| Env var | What | Where to get it |
|---|---|---|
| `IOS_APP_ID` | `<AppleTeamID>.com.rohanchari.steptracker` | Apple Developer → Membership → Team ID |
| `ANDROID_SHA256_FINGERPRINTS` | comma-separated SHA-256 cert fingerprints | Play Console → App integrity → App signing (include BOTH the Play app-signing key and the upload key) |

Set on the prod (pm2) and staging hosts, restart, then confirm:
```
curl -s https://steptracker-api.org/.well-known/apple-app-site-association | jq .
curl -s https://steptracker-api.org/.well-known/assetlinks.json | jq .
```
Both must show the real app id / fingerprints (no `TEAMID…`, non-empty array).

> Note: the native configs already claim both `barastep.com` and
> `steptracker-api.org`. The backend only serves `/r/` + the AASA files on
> `steptracker-api.org`, which is what the invite links use — so that host is
> the one that must verify. `barastep.com` only matters if/when you point it at
> the backend; until then it harmlessly falls back to the browser.

### b. Product sign-off on the shipped defaults (all env-tunable, no redeploy of app)
| Knob | Default (env var) | |
|---|---|---|
| Referrer reward | 300 (`REFERRAL_REFERRER_COINS`) | confirm |
| Referee reward | 100 (`REFERRAL_REFEREE_COINS`) | confirm |
| Qualify window | 30 days (`REFERRAL_QUALIFY_WINDOW_DAYS`) | confirm |
| Daily cap | 20 (`REFERRAL_DAILY_CAP`) | confirm |
| Monthly cap | 100 (`REFERRAL_MONTHLY_CAP`) | confirm |
| Qualifying race | seeded OR ≥2 real finishers | confirm predicate |

---

## 2. Backend deploy (FIRST — before any app build references the endpoints)

1. **Dedupe scan (required before the CoinTransaction unique migration):**
   ```
   node scripts/dedupe-coin-transactions.js --db=prod        # dry run, read-only
   node scripts/dedupe-coin-transactions.js --db=prod --fix  # only if dupes found
   ```
2. **Apply migrations to prod** (the referral tables + the CoinTransaction unique):
   ```
   npx prisma migrate deploy
   ```
   Migrations: `20260626000000_add_referral_program`,
   `20260628000000_coin_transaction_unique_refid`.
   (Watch the advisory-lock footgun — see the backend deploy notes.)
3. Deploy the backend code (pm2 reload) and smoke-check:
   ```
   curl -s https://steptracker-api.org/referrals/BARA-XXXX   # 404 for unknown code = route live
   ```
   Old app binaries are unaffected — every change is additive (new tables/columns,
   new endpoints they never call, an optional `referralCode` they never send).

## 3. App release (iOS + Android in LOCKSTEP)
- The Android Play Install Referrer dep and the iOS clipboard channel are new
  native code — **build and run both platforms** to confirm they compile/link
  (the Dart side is unit-tested; native couldn't be compiled in CI here).
- Confirm `PrivacyInfo.xcprivacy` declares the `UIPasteboard` Required-Reason API
  before the App Store build (clipboard read).
- Bump version/build numbers in sync; build with the prod `--dart-define`.

## 4. Verify on staging end-to-end
Generate a link → install on a device → sign in → finish a qualifying race →
confirm: referrer + referee both credited, referrer push fires, dashboard shows
the friend as "completed", and a delete+reinstall does NOT re-pay.

---

## PR descriptions (paste when opening)

**Backend PR — "Referral program (backend)"**
> Server side of friend referrals. Existing users share a `/r/BARA-<code>` link;
> a new friend who installs, signs in, and finishes their first *qualifying* race
> earns coins for both sides (Apple 3.2.2-compliant — gated on a real in-app
> action). Additive end-to-end: new tables/columns, new `/referrals/*` endpoints,
> an optional `referralCode` on `/auth/*`. Anti-abuse: provider-sub-hash dedup
> (survives reinstall), qualifying-race gate (blocks solo farming), attribution
> window, velocity caps (hold → manual review), review-account exclusion, and a
> DB-level `CoinTransaction` idempotency unique. Reward fires from the single
> `completeRace` settlement point; `REFERRAL_REWARDED` pushes the referrer.
> Migrations deploy before any app build depends on them. Live-tested + settlement
> regression green. See `REFERRAL_ROLLOUT.md` for the deploy order (run the
> CoinTransaction dedupe scan first).

**Frontend PR — "Referral program (frontend)"**
> Client side of friend referrals. Capture: `pendingReferralCode` (first-capture-
> wins, 30-day expiry) from deep links (`BARA-` prefix), plus first-launch native
> auto-capture (Android Play Install Referrer / iOS `detectPatterns`→clipboard).
> Threaded as an optional field into provisioning; post-sign-in codes attach via
> `/referrals/redeem`. UI: invite CTA (profile + home), referral dashboard with
> stage badges, manual-code entry, a tailored onboarding welcome for referees,
> and an in-app program-rules screen. `REFERRAL_REWARDED` routes to home. All
> additive/back-compat. 40+ referral tests pass; zero new failures vs baseline.
> Ship iOS + Android in lockstep (new native code).
