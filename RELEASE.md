# Bara Release Workflow

This is the canonical release workflow for the Flutter app.

Exact Flutter run/build commands and required `--dart-define` values live in
[README.md](README.md). Do not duplicate those commands here. If configuration
changes, update the README first.

Historical release/TestFlight notes live under `docs/archive/` and are not
current instructions.

## Authority and safety

- Production build/upload/release actions require explicit user instruction for
  the requested action.
- Building a release artifact does not authorize uploading it.
- Uploading to App Store Connect does not authorize submitting for review.
- Submitting for review does not authorize releasing to customers.
- Backend-dependent releases ship backend-compatible changes first.
- A shipped app binary cannot be rolled back. Design backend compatibility so
  the server remains the fast rollback surface.
- Never put secret RevenueCat server keys, webhook secrets, Meta secrets, or App
  Store Connect private-key contents into a Flutter build, commit, or chat.

## Sources of truth

- Exact iOS/Android build commands: `README.md`
- Agent engineering policy: `AGENTS.md`
- Billing/store setup: `docs/bara-billing-store-setup.md`
- Backend production operations: backend repo `OPERATIONS.md`
- Historical release evidence: `docs/archive/releases/`

## Environment map

| App | Bundle/application identity | Distribution | Backend |
| --- | --- | --- | --- |
| Bara | production identity | App Store + TestFlight | `https://steptracker-api.org` |
| Bara Staging | staging identity | TestFlight/internal only | `https://staging.steptracker-api.org` |

Build-time backend configuration is baked into the binary. Verify it before
upload.

## Pre-release checklist

1. Confirm the intended frontend commit/branch.
2. Confirm the backend contract required by the build is already deployed or is
   backward-compatible with the currently deployed backend.
3. Confirm old app versions remain supported by the backend.
4. Run:
   ```bash
   flutter pub get
   flutter analyze
   flutter test
   ```
5. Review known baseline failures before treating any failure as unrelated.
6. Confirm the intended version/build number.
7. Load the local ignored release configuration/secrets required by the README.
8. Re-read the **current** production build command in `README.md`.
9. Confirm the production backend URL and OAuth/RevenueCat/AdMob/Meta values are
   the intended production values.
10. Confirm no staging-only value is present in a production artifact.

## Backend/frontend release order

Default rule: backend first, app second.

Use additive backend compatibility so old App Store builds continue working
while the new app rolls out.

If a backend removal is ever required, do not remove an endpoint/field while
shipped binaries still depend on it. Prefer a compatibility shim and remove it
only after old clients are no longer supported.

## Build production artifacts

Use the exact current commands in `README.md`:

- **Build production iOS**
- **Build production Android**

Do not copy an old command from a dated release note.

For iOS, verify the signed archive itself, not just source configuration. In
particular confirm:

- bundle identity;
- version/build number;
- production backend URL;
- required RevenueCat public SDK key;
- Google OAuth client;
- expected retained AdMob units;
- Meta App ID/client token configuration without printing the token;
- release channel/capability assumptions.

For Android, verify the production flavor/application id, backend URL, version
code, and currently provisioned Android ad/billing configuration.

## Upload to App Store Connect

Only after explicit upload authorization.

Prefer the existing locally configured App Store Connect API key. Its path/key
id/issuer id belong in ignored local configuration. Never print the private key.

The upload must use the already-verified production archive. Do not rebuild with
different defines between verification and upload.

Success means the upload command itself succeeded. For a TestFlight request,
also confirm Apple processing reaches a valid state and the build is available
to the intended existing internal group.

Uploading does **not** authorize App Review submission or customer release.

## TestFlight

Use production TestFlight when the goal is to validate the production package
against production services.

Use the staging app only when an explicitly authorized staging workflow is
required. The staging backend is stopped by default on the server; coordinate
with the backend operations handbook before relying on it.

Do not enable production SSV-backed rewarded placements in a staging-backend
build unless a staging-specific callback/unit is intentionally configured.

## Submit for App Review

Requires explicit instruction.

Before submission:

- select the already-verified build;
- verify screenshots/metadata if changed;
- verify privacy nutrition labels and other store declarations affected by the
  release;
- provide user-facing release notes;
- confirm phased-release settings intentionally.

Submitting for review does not authorize manual release if the release mode
requires a separate action.

## Release to customers

Requires explicit instruction.

After release:

1. Confirm the App Store version/build.
2. Monitor backend health and relevant product metrics.
3. Keep backend compatibility for prior app versions throughout phased rollout.
4. Tag the released frontend commit when the release is confirmed.

## Android release

Build the matching Android artifact for customer releases unless the user
explicitly scopes the release to iOS only.

Use the production Android command in `README.md`. Missing optional Android ad
units should disable only the corresponding placement; never invent or reuse an
iOS unit.

Use an internal testing track before production for platform-specific Google
Sign-In, Health Connect, FCM, deep links, billing, and ad mediation verification.

## Rollback

A live App Store binary cannot be rolled back for users who already installed
it.

Rollback options are therefore:

1. backend-compatible mitigation/rollback;
2. backend policy/content changes that old and new clients both understand;
3. a new frontend build/submission.

Never solve a frontend incident by making a destructive backend change that
breaks users on older app versions.

## Historical documentation

`docs/archive/releases/` and `docs/archive/research/` are retained for
archaeology and evidence only. They may contain old version numbers, ad units,
build flags, rollout decisions, or one-time verification steps.

Do not use them as current build/release instructions.
