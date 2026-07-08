# Frontend Deployment

Two iOS app listings in App Store Connect, each pointed at a different backend. Both built from this same repo with different `--dart-define` and `--flavor` flags.

| App           | Bundle ID                                  | Distribution | Backend                                |
| ------------- | ------------------------------------------ | ------------ | -------------------------------------- |
| Bara          | `com.rohanchari.steptracker`               | App Store + TestFlight | `https://steptracker-api.org` (prod) |
| Bara Staging  | `com.rohanchari.steptracker.staging`       | TestFlight only        | `https://staging.steptracker-api.org` (staging) |

The same `--dart-define=BACKEND_BASE_URL=…` value is baked at build time; a built binary cannot accidentally hit the wrong env.

---

## Branch model

- **`main` = what's submitted to the App Store.** Never push speculative work directly here.
- **Release branches** (`1.1.5`, `1.1.6`, …) are where in-progress work lives. The matching branch on the backend repo (`steps-tracker-backend`) runs on staging.
- **`pubspec.yaml` version stays at the last-released version until you're cutting a new release.**

---

## Local dev (Xcode debug build, fastest iteration)

Full staging run command (iPhone over cable; ad units fall back to Google's
test ads in debug, and GOOGLE_IOS_CLIENT_ID enables the Google sign-in button
— use the STAGING client since this hits the staging backend):

```bash
flutter run -d 00008150-000171DE2638401C --device-connection=attached --debug \
  --dart-define=BACKEND_BASE_URL=https://staging.steptracker-api.org \
  --dart-define=ADMOB_EXTRA_SPIN_AD_UNIT_ID=ca-app-pub-4538901002392200/8833390717 \
  --dart-define=ADMOB_BANNER_AD_UNIT_ID=ca-app-pub-4538901002392200/5308967309 \
  --dart-define=GOOGLE_IOS_CLIENT_ID=784756906133-m1bdl17qk10afve110og6m7adte1q9n0.apps.googleusercontent.com
```

To run against PROD instead, swap the backend URL and the Google client id
(prod backend only accepts the prod iOS client):

```bash
  --dart-define=BACKEND_BASE_URL=https://steptracker-api.org \
  --dart-define=GOOGLE_IOS_CLIENT_ID=784756906133-iod9c45m7guhnpkv8svbdbmb27nctagl.apps.googleusercontent.com
```

Or, if you want to test against a backend running on your laptop (omit the
Google define — the local backend's allowlist doesn't include the iOS
clients unless you add them to your local `.env`):

```bash
flutter run --dart-define=BACKEND_BASE_URL=http://127.0.0.1:3000
```

The colored top banner in non-prod builds tells you which env you're hitting.

---

## Working on a new release (e.g., 1.1.5)

### 1. Create the branch

```bash
git checkout main && git pull
git checkout -b 1.1.5
git push -u origin 1.1.5
```

Do the same on `steps-tracker-backend`. Branch names match so frontend and backend pair cleanly.

### 2. Iterate, commit to `1.1.5`

Never commit directly to `main`.

### 3. Ship to TestFlight (Bara Staging)

When you have something worth testing on a real phone:

```bash
# Increment build number in pubspec.yaml (e.g., 1.1.4+5 → 1.1.4+6)
# DO NOT bump the version name (1.1.4) until cutting a prod release.

# NOTE: no --flavor on iOS — the Xcode project defines no flavor schemes
# (passing one fails with "You must specify a --flavor option").
# No ADMOB_EXTRA_SPIN_AD_UNIT_ID here: the ad unit's SSV callback points at
# PROD, so a staging-backend build can't verify rewards — omitting the define
# keeps the extra-spin offer out of staging builds entirely.
# GOOGLE_IOS_CLIENT_ID enables the "Sign in with Google" button on iOS
# (STAGING iOS OAuth client — the one registered for the .staging bundle id).
# Omitting it is safe: the button is hidden and sign-in stays Apple-only.
flutter build ipa --release \
  --dart-define=BACKEND_BASE_URL=https://staging.steptracker-api.org \
  --dart-define=GOOGLE_IOS_CLIENT_ID=784756906133-m1bdl17qk10afve110og6m7adte1q9n0.apps.googleusercontent.com
```

Then upload `build/ios/ipa/*.ipa` via Transporter or `xcrun altool`. Apple processes it (~10 min) and pushes to your "Bara Staging" TestFlight internal testers — no Beta App Review needed since they're internal.

Friends update their Bara Staging app. The Bara (prod) app on their phone is untouched.

### 4. Iterate

For each fix, bump the build number (`pubspec.yaml`'s `+N` suffix), rebuild, re-upload. The `1.1.5` version name stays the same; only the build number ticks up.

---

## Cutting the prod release

Only do this when 1.1.5 has been stable on staging for the changes and you're ready to ship.

### 1. Merge `1.1.5` → `main`

```bash
git checkout main && git pull
git merge --ff-only 1.1.5    # use --ff-only for linear history
git push origin main
```

Do the same on the backend repo.

### 2. Bump version name in `pubspec.yaml`

```yaml
version: 1.1.5+1
```

Commit that to `main`.

### 3. Deploy backend to prod first

Follow the backend's `DEPLOYMENT.md`. Critical: backend should be **on the new code before App Store users update**, because the new app may rely on new backend endpoints.

Wait — that's actually backwards from what we do here. Re-read:

**Actual order for safety with iOS auto-update lag:**

- If the new release only **adds** backend endpoints (new app needs them, old app ignores them): deploy backend first, App Store second.
- If the new release **removes** backend endpoints: App Store first (so old clients get updated and stop calling them), backend second.
- If both: deploy backend additions first, then App Store, then backend removals.

For most releases, you can deploy backend first because the old App Store binary doesn't call the new endpoints.

### 4. Build the Bara (prod) release

```bash
# NOTE: no --flavor on iOS (no flavor schemes in the Xcode project).
# ADMOB_EXTRA_SPIN_AD_UNIT_ID is REQUIRED: it bakes in the rewarded ad unit
# for the extra daily spin (iOS-only feature; see AD_REWARD_DESIGN.md).
# ADMOB_BANNER_AD_UNIT_ID bakes in the display banner shown at the bottom of
# the shop/inventory and the race mystery-box overlay (iOS-only, display-only:
# no reward, no backend). Both define are safe to forget — the app just ships
# without that ad — but a prod release should carry both.
# GOOGLE_IOS_CLIENT_ID enables the "Sign in with Google" button on iOS
# (PROD iOS OAuth client, registered for com.rohanchari.steptracker). The
# backend's GOOGLE_AUTH_CLIENT_ID allowlist must already include this client
# id in prod BEFORE this build ships (iOS Google ID tokens carry it as `aud`).
flutter build ipa --release \
  --dart-define=BACKEND_BASE_URL=https://steptracker-api.org \
  --dart-define=ADMOB_EXTRA_SPIN_AD_UNIT_ID=ca-app-pub-4538901002392200/8833390717 \
  --dart-define=ADMOB_BANNER_AD_UNIT_ID=ca-app-pub-4538901002392200/5308967309 \
  --dart-define=GOOGLE_IOS_CLIENT_ID=784756906133-iod9c45m7guhnpkv8svbdbmb27nctagl.apps.googleusercontent.com
```

> The banner unit (`/5308967309`) lives under the iOS AdMob app (`~5288861983`).
> Omit the define on dev/staging to fall back to Google's public test banner;
> new units can take up to an hour to start filling live ads.

Upload via Transporter to "Bara" in App Store Connect.

### 5. Submit for App Store review

- App Store Connect → Bara → App Store → "+ Version" → set to `1.1.5`
- Upload screenshots if changed
- Set release notes (user-facing "What's New")
- Set Phased Release ON (rolls out 1%/2%/5%/10%/etc over 7 days; pauseable if anything breaks)
- Submit for review

Review usually 24–48h.

### 6. Same binary to TestFlight (Bara prod)

While App Store review runs, push the same `1.1.5` binary to TestFlight on the Bara app for your own pre-release validation against prod. This is internal testing — no review.

### 7. Once App Store approves

Release to the App Store. Phased rollout starts.

### 8. Tag the released commit

```bash
git tag -a v1.1.5-released -m "Released to App Store"
git push origin v1.1.5-released
```

---

## Android (Google Play)

Same Dart code, two Gradle flavors instead of two bundle ids. Ship Android in
lockstep with iOS (CLAUDE.md): whenever you cut an iOS release, build and
upload the matching Android release.

| App           | Application ID                         | Flavor    | Backend  |
| ------------- | -------------------------------------- | --------- | -------- |
| Bara          | `com.rohanchari.steptracker`           | `prod`    | prod     |
| Bara Staging  | `com.rohanchari.steptracker.staging`   | `staging` | staging  |

### versionCode scheme

Play requires a globally increasing integer `versionCode` — unlike iOS build
numbers, it must NOT reset when the version name bumps. Derive it from the
version so it stays monotonic, and pass it explicitly:

```
versionCode = major*100000 + minor*1000 + patch*10 + upload#   (upload# = 0–9)
1.5.2 first upload  → 105020
1.5.2 second upload → 105021
1.5.3 first upload  → 105030
```

`--build-number` also sets iOS's CFBundleVersion, so pass it only on the
Android build command; the iOS build keeps the pubspec `+N`.

### Build

```bash
# Staging (internal testing against staging backend)
flutter build appbundle --release --flavor staging \
  --dart-define=BACKEND_BASE_URL=https://staging.steptracker-api.org \
  --build-number=<versionCode>

# Prod
flutter build appbundle --release --flavor prod \
  --dart-define=BACKEND_BASE_URL=https://steptracker-api.org \
  --build-number=<versionCode>
```

Output: `build/app/outputs/bundle/<flavor>Release/app-<flavor>-release.aab`.
Release signing needs `android/key.properties` (gitignored; template in
`android/key.properties.example`) pointing at the upload keystore
(`~/keys/bara-upload-key.jks`). Without it Gradle silently falls back to
debug signing and Play rejects the bundle — check the signature if unsure:
`keytool -printcert -jarfile <aab>`.

No ad defines on Android: ads are iOS-only (AdService gates on Platform.isIOS),
and the manifest carries Google's public test AdMob app id only so the SDK's
startup provider doesn't crash. Replace it with a real Android AdMob app id
before ever enabling ads on Android.

### First-upload checklist (Play Console, one-time)

- [ ] Create the Play app (com.rohanchari.steptracker) and enroll in Play App Signing with the upload key.
- [ ] Register BOTH SHA-1s (upload key + Play App Signing key, from Play Console → App integrity) on the prod Android app in Firebase (`bara-590e1`) and re-download `google-services.json` — Google Sign-In fails with DEVELOPER_ERROR otherwise.
- [ ] Data safety form: steps/health data (app functionality, not shared), account identifiers, device IDs (AD_ID is declared in the merged manifest via google_mobile_ads even though Android shows no ads).
- [ ] Health apps declaration + Health Connect access request (Play Console policy section) — cite the privacy policy's Health Data section (barastep.com / steptracker-api.org `/privacy.html`, includes background reads).
- [ ] Background health-data access justification (READ_HEALTH_DATA_IN_BACKGROUND).
- [ ] Store listing (screenshots, icon, descriptions) + content rating questionnaire.
- [ ] Internal testing track first; promote to production only after Google Sign-In, Health Connect sync, FCM push, and deep links are verified on a real device install from Play.

---

## Rollback

The App Store binary cannot be rolled back — once a version is live, users who updated keep it until they update to something else. So your rollback path is:

1. **If the bug is in the backend:** revert the backend (see backend `DEPLOYMENT.md`). The deployed App Store binary now talks to the previous backend.
2. **If the bug is in the iOS binary:** prepare a hotfix on `1.1.5` (or `1.1.6`), bump build number, submit. Optionally Request Expedited Review (App Store Connect → Contact Us). Phased Release can be paused to stop further rollout while you fix.

**Backend rollback is fast (~30 seconds). App rollback requires a new submission. Sequence deploys so the backend is the thing you can revert if something breaks.**

---

## Version numbering

- **Version name** (`1.1.5`): user-visible. Matches the release branch name. Bump only when cutting a new App Store release.
- **Build number** (`+N`): increments with every TestFlight upload, even within the same version. Required by Apple — each binary must have a unique build number for a given version.

Example sequence on `1.1.5`:

```
1.1.4+12  ← last 1.1.4 release  (DO NOT EDIT)
1.1.5+1   ← first 1.1.5 TestFlight build
1.1.5+2   ← second TestFlight build (fix from feedback)
1.1.5+3   ← third TestFlight build
1.1.5+4   ← final, submitted to App Store
```

---

## Shop accessory assets

Accessory PNGs (`assets/images/accessories/{assetKey}.png`) are **baked into
the binary** — there is no image upload or CDN, so a new accessory only reaches
users via a TestFlight/App Store build. The catalog entry (price, slot,
positioning, `testOnly` flag) lives in the backend DBs and deploys
independently. The full add → tune-on-staging → TestFlight → flip-`testOnly`
flow is documented in the backend repo's `DEPLOYMENT.md` under "Deploying shop
accessories (cosmetics)". Two app-side notes:

- A newly added PNG needs a full `flutter run` (or at least hot restart), not
  hot reload, to land in the asset bundle.
- Old binaries that lack a PNG render a placeholder icon via `errorBuilder`
  rather than crashing — which is why new items ship `testOnly: true` until the
  binary containing them is broadly adopted.

---

## Common gotchas

- **`--dart-define` is compile-time.** Hot reload doesn't pick up changes. After changing the flag, `flutter clean && flutter run …` to be sure.
- **Bundle ID determines which app the build goes to.** A "staging flavor" build with `com.rohanchari.steptracker` (not `.staging`) would land in the prod TestFlight. Always confirm in App Store Connect that the build appeared under the expected app.
- **APNS device tokens are bound to bundle ID and APNS environment.** Tokens from "Bara Staging" (sandbox host) won't work against prod APNS, and vice versa. The `sync-prod-to-local` script handles this by truncating device_tokens after every sync.
- **App Store Connect remembers screenshots per language.** If you mark something localized in error, you can spend an hour fixing it. Stick to English unless you mean to localize.
