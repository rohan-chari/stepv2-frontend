# Frontend Deployment

Two iOS app listings in App Store Connect, each pointed at a different backend. Both built from this same repo with different `--dart-define` and `--flavor` flags.

| App           | Bundle ID                                  | Distribution | Backend                                |
| ------------- | ------------------------------------------ | ------------ | -------------------------------------- |
| Bara          | `com.rohanchari.steptracker`               | App Store + TestFlight | `https://api.steptracker-api.org` (prod) |
| Bara Staging  | `com.rohanchari.steptracker.staging`       | TestFlight only        | `https://staging.steptracker-api.org` (staging) |

The same `--dart-define=BACKEND_BASE_URL=…` value is baked at build time; a built binary cannot accidentally hit the wrong env.

---

## Branch model

- **`main` = what's submitted to the App Store.** Never push speculative work directly here.
- **Release branches** (`1.1.5`, `1.1.6`, …) are where in-progress work lives. The matching branch on the backend repo (`steps-tracker-backend`) runs on staging.
- **`pubspec.yaml` version stays at the last-released version until you're cutting a new release.**

---

## Local dev (Xcode debug build, fastest iteration)

```bash
flutter run --dart-define=BACKEND_BASE_URL=https://staging.steptracker-api.org
```

Or, if you want to test against a backend running on your laptop:

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

flutter build ipa --flavor staging --release \
  --dart-define=BACKEND_BASE_URL=https://staging.steptracker-api.org
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
flutter build ipa --flavor prod --release \
  --dart-define=BACKEND_BASE_URL=https://api.steptracker-api.org
```

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

## Common gotchas

- **`--dart-define` is compile-time.** Hot reload doesn't pick up changes. After changing the flag, `flutter clean && flutter run …` to be sure.
- **Bundle ID determines which app the build goes to.** A "staging flavor" build with `com.rohanchari.steptracker` (not `.staging`) would land in the prod TestFlight. Always confirm in App Store Connect that the build appeared under the expected app.
- **APNS device tokens are bound to bundle ID and APNS environment.** Tokens from "Bara Staging" (sandbox host) won't work against prod APNS, and vice versa. The `sync-prod-to-local` script handles this by truncating device_tokens after every sync.
- **App Store Connect remembers screenshots per language.** If you mark something localized in error, you can spend an hour fixing it. Stick to English unless you mean to localize.
