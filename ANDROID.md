# ANDROID.md — Android release plan for steps-tracker (Bara)

Status: **planning / not started.** The app ships iOS-only today. This document is the
plan of record for bringing it to the Google Play Store. Every claim below was verified
against the actual frontend (`/Users/rohan/Documents/steps-tracker`) and backend
(`/Users/rohan/Documents/steps-tracker-backend`) source; file:line citations are in the
[Evidence](#evidence-appendix) section.

> **Prime directive (from `CLAUDE.md`):** a shipped app binary is frozen and the prod
> backend serves *all* app versions at once. Every backend change here must keep existing
> iOS clients working unchanged. Backend changes deploy **first** (defaulted, fail-soft,
> verified on prod against an iOS client) — *then* the Android app ships.

---

## 0. Locked decisions

| # | Decision | Choice |
|---|----------|--------|
| 1 | Android auth provider | **Google Sign-In only** (iOS keeps Sign in with Apple) |
| 2 | `applicationId` (permanent on Play) | **`com.rohanchari.steptracker`** |
| 3 | Background step sync for v1 | **Foreground-only.** Defer WorkManager background sync to a fast-follow |
| 4 | Push notifications in v1 | **Yes — FCM (workstreams E + G2 are in v1).** Only the *background step sync* is deferred; race-invite/chat push ships in v1 |
| 5 | Privacy-policy URL | Exists: `https://steptracker-api.org/privacy` — **content needs an Android/Health Connect section added before submission** |
| 6 | Step-count accuracy on Android | **Android uses `includeManualEntry: true`** (Health Connect's de-duplicated `aggregate()` path); iOS stays at `false`. See §C-5 — this is the most accurate option the `health` package supports |

The app display name is already `Bara` (`android:label`), so no rename of the user-facing
name is needed — only the placeholder `applicationId`/`namespace`.

---

## Progress log

**Branch `android-release`.** Done so far (Workstream A foundation + the critical manifest fix):

- ✅ `applicationId` + `namespace` → `com.rohanchari.steptracker` (`android/app/build.gradle.kts`);
  `MainActivity.kt` moved to `…/kotlin/com/rohanchari/steptracker/` with matching `package`. No
  `com.example.step_tracker` references remain anywhere in source/config.
- ✅ `prod` / `staging` Gradle product flavors added to mirror the iOS two-listing model
  (`staging` → `.staging` suffix). **Android builds/runs now require `--flavor prod|staging`.**
- ✅ Release signing wired to a gitignored `android/key.properties` with a debug fallback;
  template committed at `android/key.properties.example`.
- ✅ `<uses-permission android:name="android.permission.INTERNET"/>` added to the **main**
  manifest (release builds would otherwise have no network).

**Not yet done / prerequisites:**

- ⛔ **Android SDK is not installed on the dev machine** (`flutter doctor` → no Android toolchain;
  only Xcode). Install Android Studio + SDK and run `flutter config --android-sdk <path>` before
  any Android build can compile. **None of the changes above have been compiled/validated** —
  first build will also surface plugin manifest-merge issues (expected).
- ◻️ Upload keystore not generated (create per `key.properties.example`; needed for a Play `.aab`).
- ◻️ `versionCode`: left to the existing release flow. `pubspec.yaml` version (shared with iOS) was
  **not** touched; Android builds need a `+N` build number or `--build-number=<N>` (see §A).
- ◻️ Workstreams B (remaining manifest/plugin config), C, D, E and backend G1/G2 not started.

Nothing here touches the backend or affects existing iOS users. Changes are uncommitted on the
`android-release` branch.

---

## 1. Executive summary

**Feasibility: high.** The Dart business logic and UI are platform-agnostic, and the
step-read package (`health: ^13.3.1`) maps to **Health Connect** on Android with the same
Dart API — so `health_service.dart` barely changes at the code level. There are **no in-app
purchases** anywhere (the coin economy is all backend), so there is **no Play Billing work**.

But it is a real multi-workstream port, not a config flip. Three things stand out:

1. **The Android project has never been built.** It carries Flutter scaffold placeholders:
   `applicationId = com.example.step_tracker`, release build signed with **debug** keys, and
   — critically — the **main `AndroidManifest.xml` declares no `INTERNET` permission** (Flutter
   only injects it into the debug/profile manifests), so a *release* build would have no
   networking and the whole app would fail.
2. **Auth and push are iOS-native today** and must be built for Android (Google Sign-In; FCM).
3. **Step values must not double-count on Android (resolved — a 2-line fix).** The app calls
   `getTotalStepsInInterval(includeManualEntry: false)` today. On Android that flag silently
   forces the `health` package off Health Connect's de-duplicated `aggregate()` path and onto a
   raw read-and-sum across *all* step-writing apps with **no cross-source dedup**
   (`HealthDataReader.kt:554`) — so a user with phone + watch (or Google Fit + Samsung Health)
   gets the same steps counted once per app, inflating totals vs. iOS. Fix: branch on
   `Platform.isAndroid` to use `includeManualEntry: true` (the deduplicated aggregate, the only
   path that matches HealthKit's "counted once" property). Details + validation test in §C-5.
   **Client-side read fix only — no backend normalization.**

**Existing iOS users:** zero frontend impact (separate Play binary, native iOS bridge
untouched). The only risk to them lives in the **shared backend** — the Google-auth schema
change and the FCM push-routing change — and both are designed here to be strictly additive
and defaulted.

**Effort by workstream:**

| Workstream | Effort |
|---|---|
| A. Android project foundation (identity, signing, versionCode, flavors) | M |
| B. Plugin / manifest config (INTERNET, UCrop, FileProvider, icon, channels) | M |
| C. Health Connect step pipeline | M |
| D. Auth — Google Sign-In (frontend) | M |
| E. Push — FCM client stack | L |
| F. Background step sync (WorkManager) — **deferred to fast-follow** | XL |
| G1. Backend — Google auth provider (route + verifier + schema) | L |
| G2. Backend — FCM sender + platform routing | L |

---

## 2. Critical path & blockers

In dependency order:

1. **Android project foundation (A).** Real `applicationId`/`namespace`, upload keystore +
   release signing, `versionCode` (pubspec is `1.3.5` with **no `+N`** → `flutter.versionCode`
   resolves to `1`). Firebase + Google OAuth clients are keyed to the final `applicationId`,
   so this must be settled first.
2. **`INTERNET` permission in the main manifest (B).** Without it, release builds have no
   network. Hard blocker for *anything* working.
3. **Backend, deployed first & defaulted (G1, G2).** Google `/auth/google` route + verifier +
   additive schema; FCM sender + platform routing on the two push fan-out paths. The Android
   app cannot log in or receive push until these are live in prod.
4. **Health Connect step pipeline (C).** Without `android.permission.health.READ_STEPS` and the
   rationale activity, the entire step pipeline is dead.
5. **Auth on Android (D)** and **Push client (E)** — parallelizable once 1–3 are done.

Background sync (F) is explicitly **out of v1** per decision #3.

---

## 3. Frontend workstreams

### A. Android project foundation — **M**

- Set `namespace` and `applicationId` to `com.rohanchari.steptracker` (replace
  `com.example.step_tracker` in `android/app/build.gradle.kts:9,24`); rename the Kotlin
  package directory + `MainActivity` package accordingly. **Irreversible on Play once published.**
- Create an upload keystore + `android/key.properties` (gitignored) and a real release
  `signingConfig`; enroll in **Play App Signing**. Today the release build uses
  `signingConfigs.getByName("debug")` (`build.gradle.kts:34-37`) — a debug-signed `.aab` is rejected.
- Fix `versionCode`: restore a `+N` build number in `pubspec.yaml:19` (e.g. `1.3.5+1`) or pass
  `--build-number=<monotonic int>`. Android rejects reused/decreasing `versionCode` (unlike iOS).
- Pin `compileSdk`/`targetSdk` explicitly (currently inherited via `flutter.compileSdkVersion`/
  `flutter.targetSdkVersion`); confirm `targetSdk >= 35` to meet Play's current target-API floor.
  Keep `minSdk = 28`.
- (Optional, mirrors iOS two-listing model) add Gradle `productFlavors` `prod`/`staging` with
  `applicationIdSuffix ".staging"`. `String.fromEnvironment('BACKEND_BASE_URL')` works unchanged
  on Android (`lib/config/backend_config.dart:4-7`), so no Dart change for config injection.

### B. Plugin / manifest config — **M**

- **Add `<uses-permission android:name="android.permission.INTERNET"/>` to the MAIN manifest.**
  (Today the main `AndroidManifest.xml` has *no* permission tags; Flutter only adds INTERNET to
  debug/profile.) Without this, release networking — and thus the whole app — fails.
- Add `POST_NOTIFICATIONS` (Android 13+ runtime push permission).
- `image_cropper`: register `<activity android:name="com.yalantis.ucrop.UCropActivity"
  android:theme="@style/Theme.AppCompat.Light.NoActionBar"/>` + provide an AppCompat/Material
  app theme, or it crashes at runtime (used at `main_shell.dart:920`).
- `image_picker` camera path: add a `FileProvider` + `res/xml/file_paths.xml` and `CAMERA`
  permission (`main_shell.dart:914`).
- `url_launcher`: add `<queries>` entries (http/https/mailto/tel).
- Branded launcher icon (currently default `@mipmap/ic_launcher`) + a monochrome
  `@drawable/ic_notification` small icon for FCM.
- Expect manifest-merge errors on the **first-ever** Android build — budget time; `android/` has
  never compiled.
- Add ProGuard/R8 keep rules before enabling minify (`flutter_local_notifications` ships one).
- Cleartext note: `backend_config`'s dev fallback is `http://127.0.0.1:3000`; Android 9+ blocks
  cleartext. Prod release points at the `https` URL (fine); only local/staging http dev needs a
  `network-security-config` cleartext exception.

### C. Health Connect step pipeline — **M**

Keep `health: ^13.3.1` — `HealthDataType.STEPS` / `HealthDataAccess.READ` /
`getTotalStepsInInterval` map to Health Connect transparently. Add:

1. `<uses-permission android:name="android.permission.health.READ_STEPS"/>` (**blocker** —
   without it the pipeline reads nothing).
2. Health Connect **rationale plumbing** (Play requirement): an `<activity-alias>` exporting
   `android.intent.action.VIEW_PERMISSION_USAGE` + category
   `android.intent.category.HEALTH_PERMISSIONS`, and a `MainActivity` intent-filter for
   `androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE`, both routing to the privacy policy.
3. `<queries><package android:name="com.google.android.apps.healthdata"/></queries>` to
   detect/launch the Health Connect app.
4. In `HealthService`, **gated behind `Platform.isAndroid`** (there are currently zero
   `Platform.isAndroid` guards in `lib/`): before `requestAuthorization`, call
   `getHealthConnectSdkStatus()` and handle `sdkUnavailable` /
   `sdkUnavailableProviderUpdateRequired` via `installHealthConnect()`; on Android use the *real*
   `hasPermissions()` grant state instead of the iOS "always-true, hidden read status" assumption
   (`health_service.dart:35-39`). Leave the iOS `health_authorized` path untouched.
5. **Step de-duplication — use the aggregate path on Android (decided).** The app passes
   `includeManualEntry: false` at both read sites (`health_service.dart:78-82,121-125`). Verified
   against the `health` v13.3.1 Kotlin source: that flag routes Android off Health Connect's
   `aggregate()`/`StepsRecord.COUNT_TOTAL` path (which de-duplicates overlapping steps across
   apps, keeping the highest-priority source — not summing) and onto `getStepCountFiltered` →
   raw `readRecords` over **all** data origins → `filteredRecords.sumOf { it.count }`
   (`HealthDataReader.kt:476-486,498-513,549-554`) with **no cross-app reconciliation**. So with
   multiple step writers (phone sensor + watch is the common case) the same steps are summed once
   per app → totals inflate upward vs. iOS, where `HKStatisticsQuery`/`cumulativeSum` stays
   de-duplicated even with manual entries excluded.

   **Decision (implemented on `android-release`):** a `bool get _includeManualEntry =>
   Platform.isAndroid;` getter feeds both read sites (`import 'dart:io' show Platform;`). iOS is
   left exactly as-is (`false`, proven accurate); Android moves onto the de-duplicated aggregate
   (`true`). Keyed on `isAndroid` (not `!isIOS`) on purpose: the host test runner is neither, so
   the existing `health_service_test.dart` assertion that manual entries are excluded stays green
   **unmodified** (`Platform.isAndroid` is `false` on the test host). This is the **only** accurate
   option the pinned package supports without forking — the method exposes **no `dataOriginFilter`
   / source-priority lever** to the app (Health Connect's steps priority list is end-user-
   controlled only), so "read raw + pin to one source" is not implementable here. The accepted
   trade-off: Android re-includes manually-typed steps (small, rare, bounded) to eliminate the
   unbounded multi-app double-count — the exact inflation vector an anti-cheat-sensitive coin
   economy must close. No extra permission needed (same `READ_STEPS`, same `StepsRecord` type).

   **Pre-launch validation (real devices — Health Connect dedup is a platform guarantee fakes
   don't reproduce):** one person carries an iPhone (current build) + an Android device (new
   build) for a full local-midnight day, with **2+ step apps** (e.g. Google Fit + Samsung Health)
   + a wearable installed on Android so overlapping records exist. Accept if the Android daily
   total is within **±3%** of iOS (never bit-identical — HealthKit gap-fills, HC only priority-
   picks) **and does not grow as step-writing apps are added/removed.** Run a control with
   `includeManualEntry:false` on Android to observe the inflation being avoided. Note: both
   Android paths return `null` on a Health Connect read exception — don't *persist/sync* a `0`
   that came from a thrown read (transient failure should not record "walked nothing").

> Note: `StepSampleData`'s source fields (`sourceName`/`recordingMethod`) are dead on all
> platforms today (`getHourlySteps` never populates them). Health Connect *origin* metadata
> could populate them for anti-cheat later — optional, out of v1 scope.

### D. Auth — Google Sign-In (frontend) — **M**

Sign-in funnels through **one** method and **one** button, so the branch is clean and the iOS
Apple flow is untouched:

- `pubspec.yaml`: add `google_sign_in` (latest 6.x).
- `BackendApiService`: add `provisionGoogleUser({required String idToken, String? email,
  String? name})` that POSTs `/auth/google` with `{idToken, email, name}` and returns the same
  `{user, sessionToken}` envelope — a near-copy of `provisionAppleUser`
  (`backend_api_service.dart:98-123`). **No `userIdentifier`** — the backend derives the stable
  Google `sub` from the verified token.
- `AuthService`: add `signInWithGoogle()` modeled on `signInWithApple` (`auth_service.dart:81`)
  and the existing `signInAsReviewer` precedent (`auth_service.dart:138`). On success set
  `_identityToken = googleIdToken` and **`_userIdentifier = account.id`** (the Google stable id)
  so `isSignedIn` (`auth_service.dart:56`, requires both non-null) and `restoreSession` keep
  working on next launch; then `_sessionToken = response['sessionToken']`,
  `applyBackendUser(response['user'])`, `_persist()`. **Do not reuse `signInWithApple`** — it hard-
  requires `credential.userIdentifier` (`auth_service.dart:100-104`). Reuse all existing
  SharedPreferences keys verbatim.
- Optionally call `GoogleSignIn.signOut()/disconnect()` inside `AuthService.signOut` on Android.
- `start_screen.dart`: add `import 'dart:io';`; in `_onStart` (`start_screen.dart:107`) branch
  `Platform.isAndroid ? signInWithGoogle() : signInWithApple()`, and render a Google button when
  `Platform.isAndroid`, the existing `SignInWithAppleButton` otherwise (`start_screen.dart:265-270`).
- Request plumbing needs **no change**: `authToken` prefers `_sessionToken`
  (`auth_service.dart:46`) and is attached as `Authorization: Bearer` on every request
  (`backend_api_service.dart:1297-1302`), so once the Google login stores the session token,
  steps/races/everything authenticate identically.
- The `signInAsReviewer` 6-tap bypass is harmless on Android; leave as-is.

**Android OAuth config:** create a **Web OAuth client** in Google Cloud and pass its id as
`serverClientId` to `GoogleSignIn` — this makes the returned `idToken.aud` equal the web client
id, which the backend verifies. Also create an **Android OAuth client** registered with package
`com.rohanchari.steptracker` and the debug **and** release SHA-1/SHA-256 fingerprints (sign-in
won't work without it). If using Firebase for FCM anyway, drop `google-services.json` into
`android/app/`.

### E. Push — FCM client stack — **L**

The device-token *source* is an iOS-native `MethodChannel('com.steptracker/notifications')`
callback today; there is **no** `firebase_messaging` in Dart. So Android push is real work, not a
string flip:

- Add `firebase_core` + `firebase_messaging`; add `google-services.json` under `android/app`;
  apply the `com.google.gms.google-services` Gradle plugin (keyed to the final `applicationId`).
- Get the token via `FirebaseMessaging.instance.getToken()` + `onTokenRefresh` and register it
  with the backend. **Fix the hardcoded `platform: 'ios'`** at `notification_service.dart:75` →
  `Platform.isAndroid ? 'android' : 'ios'`. The backend endpoint already whitelists `'android'`
  (see G2), so no new field is needed.
- Use `flutter_local_notifications` (already in `pubspec.yaml:41`, currently unused) for
  foreground display: create an `AndroidNotificationChannel` at startup, request
  `POST_NOTIFICATIONS` at runtime on Android 13+.
- Feed FCM data into the **existing** `payload['type'] → NotificationRoute` map
  (`notification_service.dart:101-144`) — already platform-agnostic. Implement the
  Android-native side of the notifications channel, or move it to Dart via `firebase_messaging`.

### F. Background step sync — **XL — DEFERRED (not in v1)**

Per decision #3, v1 is **foreground-only**. For the fast-follow: Health Connect has **no
observer/immediate-delivery analog** to the iOS `HKObserverQuery` path
(`AppDelegate.swift:340-479`), so reimplement with the `workmanager` package (periodic task,
15-min Android floor) reading Health Connect and POSTing the **existing** `/steps` +
`/steps/samples` shapes (so it coexists with iOS clients), optionally triggered by FCM data
messages. `enableHealthKitBackgroundDelivery()` already swallows `PlatformException` on non-iOS
(`background_sync_bootstrap_service.dart:20-22`), so it's a no-op on Android until then.

---

## 4. Backend changes (compat-safe, deploy FIRST)

> All additive and defaulted. Deploy and verify on prod against an iOS client **before** the
> Android binary ships. Treat the onboarding-grant change with game-economy-grade caution per
> `CLAUDE.md` and prior incidents: **do not backfill or hand-set any ledger column** that feeds
> the box-roll gate. Author the schema migration as **additive hand-written SQL + `psql` +
> `prisma migrate resolve`** (the dev DB drifts from history — never `migrate dev`).

### G1. Google auth provider — **L**

Verified identity model: accounts key on the **verified token `sub`**, stored as
`User.appleId @unique` (`routes/auth.js:88-95`, `appleIdentityToken.js`). `User.email` is
**nullable and NOT unique** and only opportunistically populated — so **email cannot reliably
link Google→Apple accounts**; treat Google as an independent identity keyed on `googleSub`. Do
**not** auto-merge by email (risks false merges + private-relay mismatches).

1. **Schema (additive):**
   - Add `googleSub String? @unique @map("google_sub")` to `User`.
   - **Relax `appleId` to nullable** (`DROP NOT NULL`) while **keeping** its unique index —
     Postgres allows multiple NULLs, so many Google-only users (null `appleId`) coexist. Existing
     Apple rows keep their values and remain unique. **Do not** add `NOT NULL` to `googleSub`.
   - This is the one non-trivial relaxation; it is backward-compatible with every iOS client.
2. **Verifier:** new `src/services/googleIdentityToken.js` mirroring `appleIdentityToken.js`:
   fetch Google JWKS (`https://www.googleapis.com/oauth2/v3/certs`, honor `Cache-Control` — Google
   rotates keys), verify RS256, `iss ∈ {accounts.google.com, https://accounts.google.com}`,
   `aud == GOOGLE_CLIENT_ID` (the **Web** OAuth client id used as `serverClientId`), check `exp`,
   require `sub`.
3. **Route:** new `POST /auth/google` mirroring `/auth/apple`: verify token → key account on
   `googleSub` → provision/find user → return `{user, sessionToken}` (the session JWT is already
   provider-agnostic, keyed on `userId` — `sessionToken.js:21-27` — so no session change).
4. **Onboarding welcome-box grant — provider-neutral key (critical):** the grant is gated by the
   `OnboardingBoxGrant` ledger whose PK is `appleSubHash = SHA-256(user.appleId)`
   (`joinPublicRace.js:58-75`). For a Google user `appleId` is null →
   `hashSub(null)` returns null → `joinPublicRace.js:59` **silently skips the grant**, so Google
   users would get **no welcome boxes**. Fix at the call site only:
   `hashSub(user.appleId || user.googleSub)`. This is purely additive, never writes/backfills the
   ledger for existing users (no re-grants), and keeps the abuse-proof insert-first-in-transaction
   roll path intact — satisfying the high-risk game-economy rule.
5. Leave `/auth/apple`, `findByAppleId`, the Apple `appleSubHash` enforcement, and the
   `/auth/review` bypass 100% unchanged. `requireAuth` Strategy 1 (session token) already
   authenticates purely on `userId`; only Strategy 2 (raw Apple identity-token fallback) is
   Apple-specific and the Android app simply won't use it.

### G2. FCM sender + platform routing — **L**

Verified risk: both push fan-out paths — `sendNotificationToUser` (`notificationHandlers.js:48`)
and the `RACE_MESSAGE_SENT` loop (`notificationHandlers.js:352`) — load **all** of a user's
tokens via `findByUserId` with **no platform filter** and send every one to APNs; a `410`
triggers `deleteToken`. An Android FCM token sent to APNs gets rejected (and possibly churned).

- New `src/services/fcm.js` mirroring `apns.js`'s interface (`sendNotification` /
  `sendSilentNotification` returning the same `{success, unregistered, statusCode, reason}`
  shape). Map title/body → `message.notification`, custom keys (`type`/`route`/`params`) →
  `message.data` (stringified), silent → data-only. Map FCM
  `registration-token-not-registered` → `unregistered:true` so cleanup still works.
- Add `firebase-admin`, init from a service-account secret, **wrapped in try/catch so a missing
  FCM cred can never break the existing APNs path**.
- **Add a platform branch to both fan-out paths** — there is already a working precedent to copy:
  `stepSyncPush.js:38-39` does `.filter((t) => t.platform === 'ios')`. Route
  `platform === 'android' → fcm`, else `apns`. Ensure the 410→delete churn logic stays
  **iOS-only**.
- **No schema/endpoint migration needed for device tokens:** `DeviceToken.platform` is already a
  required column (`schema.prisma:285`) and `POST /notifications/device-token` already validates
  `platform ∈ {ios, android}` (`routes/notifications.js:18-34`). All shipped iOS clients send
  `'ios'` and keep working.

**Deploy order:** G1 (schema → verifier → route → grant key) and G2 (fcm service → routing),
each defaulted/fail-soft, **verified on prod against an iOS client**, *before* the Android binary
reaches users. These are the only iOS-user-impacting deploys.

---

## 5. Store / release logistics

- **`applicationId`** `com.rohanchari.steptracker` — permanent on Play; set before any Firebase/
  OAuth registration and first upload.
- **Play App Signing:** generate upload keystore, replace debug `signingConfig`, enroll.
- **`versionCode`:** strictly increasing integer per upload; restore `+N` in `pubspec.yaml:19`
  or pass `--build-number`.
- **Health Connect data declaration:** Play requires the Health Apps / health-data permissions
  form for `READ_STEPS` with a hosted privacy-policy URL + the in-app rationale activity (C-2).
- **Privacy policy:** `https://steptracker-api.org/privacy` (served via `src/app.js:52-53` →
  `public/privacy.html`; `/privacy.html` is an equivalent alias). **Its content is iOS/HealthKit-
  only** (`public/privacy.html:302,307,313`) — before submission, edit `public/privacy.html` to
  add a Health Connect section (read-only daily step count via Android Health Connect, same
  no-sell/no-share guarantees, Android revocation via the Health Connect app / Settings) and bump
  the effective date. It's a static file → update + redeploy the page to the droplet (no app
  release needed), but it must be live before the Play reviewer opens the URL. A data-deletion
  path already exists (email to support, 30-day SLA).
- **Firebase/FCM:** create a Firebase project, `google-services.json` keyed to the final
  `applicationId`, apply the `google-services` Gradle plugin; assign service-account secret
  injection on the droplet (parallel to the existing `APNS_*` secrets).
- **Builds:** `flutter build appbundle --dart-define=BACKEND_BASE_URL=https://steptracker-api.org
  --build-number=<N>` (plus a staging variant → internal track if flavors are added).
- **Sign-in-with-Apple policy:** Apple's App Store guideline 4.8 (must offer SIWA when other
  social logins exist) is an **iOS** rule; **Play has no equivalent**, so Android may ship
  Google-only. (Accepted trade-off: Apple-on-iOS and Google-on-Android users are distinct
  accounts; no cross-provider linking — see §4 G1.)

---

## 6. Recommended sequencing (zero → Play Store)

1. **Android foundation (A):** identity, keystore/signing, `versionCode`, SDK pinning,
   (optional) flavors. *Parallelizable with #2.*
2. **Backend deploys (G1 → G2):** Google auth (schema → verifier → route → provider-neutral grant
   key) and FCM sender + routing — defaulted, fail-soft, **verified on prod against an iOS
   client.** This is the iOS-user-impacting gate; must precede Android auth/push shipping.
3. **Manifest/plugin config (B):** **INTERNET first**, UCrop, FileProvider, icons → first
   successful Android build. *Depends on #1.*
4. **Health Connect (C)** ∥ **Auth (D)** ∥ **Push client (E)** — parallel once #1–#3 are done.
5. **Privacy policy:** add Android/Health Connect content to `public/privacy.html`, deploy.
6. **Internal testing track build:** validate end-to-end on real devices — Google login → steps
   read → push received → routing correct.
7. **Cross-platform validation:** Health Connect step totals reconcile with HealthKit for the
   same user (race/leaderboard fairness); confirm no APNs↔FCM cross-delivery or token churn.
8. **Play submission:** Health-data declaration + privacy URL + store assets + branded icon;
   closed → open track; phased rollout.
9. **(Fast-follow)** Background step sync (F): WorkManager + optional FCM trigger.

---

## 7. Open questions

1. **Health Connect unavailability** (no HC app — common pre-Android-14): block onboarding, or
   degrade gracefully to a no-steps state with an install prompt?
2. **Token storage:** keep SharedPreferences (`auth_session_token`) on Android, or move to
   `flutter_secure_storage` for the rooted/backup threat model?
3. **Firebase project ownership** + where the FCM service-account secret is injected on the
   droplet.

---

## Evidence appendix

Key file:line citations behind the claims above (verified by reading source):

**Frontend**
- Step pipeline: `lib/services/health_service.dart:23-30` (only `STEPS`/`READ` requested),
  `:78-82,121-125` (`getTotalStepsInInterval` totals), `:35-39,96` (iOS-only auth/dedup
  assumptions); `lib/services/background_sync_bootstrap_service.dart:17-23` (iOS-native bg
  delivery, swallows on non-iOS).
- Auth: `lib/services/auth_service.dart:46,56,81,98-104,138-153`;
  `lib/screens/start_screen.dart:107,265-270`;
  `lib/services/backend_api_service.dart:98-123,1297-1302`.
- Push: `lib/services/notification_service.dart:75` (`platform: 'ios'` hardcoded),
  `:101-144` (route map).
- Config: `lib/config/backend_config.dart:4-7` (`String.fromEnvironment`).
- Android project: `android/app/build.gradle.kts:9,24,27,34-37` (placeholders, `minSdk 28`,
  debug-signed release); main `AndroidManifest.xml` (no `<uses-permission>`, `android:label`
  already `Bara`); `pubspec.yaml:19` (`1.3.5`, no `+N`), `:37-47` (deps).

**Backend**
- Auth/identity: `src/routes/auth.js:88-95`; `src/services/appleIdentityToken.js:4,60,68,72,84,121`;
  `prisma/schema.prisma:11-12` (`appleId @unique`, `email String?`); `src/models/user.js:12,16`;
  `src/services/sessionToken.js:21-27`; `src/middleware/requireAuth.js:47,76-80`.
- Onboarding grant: `src/commands/joinPublicRace.js:58-75,117`; `src/utils/appleSubHash.js:12`;
  `prisma/schema.prisma:773` (`apple_sub_hash @id`); migration `20260527010000`.
- Push: `src/handlers/notificationHandlers.js:45-51,341-360,66-70,377-382`;
  `src/services/apns.js:109`; `src/services/stepSyncPush.js:38-39` (existing platform filter to
  copy); `src/models/deviceToken.js:4-9,16-18`; `prisma/schema.prisma:285` (`platform String`);
  `src/routes/notifications.js:18-34` (validates `ios`/`android`).
- Privacy: `src/app.js:48-53` (routes → `public/privacy.html`); `public/privacy.html:302,307,313`
  (iOS-only content); prod host `https://steptracker-api.org` (`DEPLOYMENT.md:11`).
