> Released backend and uploaded iOS on 2026-09-10; see
> [release audit](meta-batch-release-2026-09-10.md) for actual results.

# Meta, Shop, artwork and Red Card production handoff

Status: preparation in progress; not production authorization. See
`meta-batch-validation.md` for test/build evidence and remaining gates.

## Backend and asset publication order

After explicit production authorization, deploy the reviewed backend revision
containing the Red Card cap, privacy page and both immutable PNGs. No schema
migration is required. Retain exactly two production PM2 workers and leave staging
stopped. Follow the backend deployment runbook; preserve its production configuration.

1. Verify the new public privacy page at both `/privacy` and `/privacy.html`.
   The amended source/compiled page uses September10,2026 as its effective date;
   adjust before publication if the actual publication date changes.
2. Fetch and hash both new public PNGs before updating either catalog record:

   | Public path | SHA-256 |
   | --- | --- |
   | `/assets/characters/turtle@a87ad177f0a0.png` | `a87ad177f0a048147465f127de10db147d036c9a4f1fbd7d2a0a67fd3ad6fccd` |
   | `/assets/powerups/hitchhike@6fbfe79192cf.png` | `6fbfe79192cf33da51b4ef14c49ee81bcea0d3f6cc9b5f6206c72a500a0d55c7` |

3. Re-read the existing catalog records before writes and retain their full
   metadata for comparison. The bounded read-only preparation found:

   | Record | Existing ID | Previous version | New version |
   | --- | --- | --- | --- |
   | Turtle character | `fa5ea940-ac91-4db3-bade-8248d31f6d2b` | `f3410027eade` | `a87ad177f0a0` |
   | Hitchhike powerup | `5924f3ed-425e-45bd-860c-8f86a294c1da` | `41ae2b8a805a` | `6fbfe79192cf` |

   Stop for unexpected identity/version changes; do not overwrite concurrent art
   updates. Change only `assetVersion` through the existing admin contracts:

   - `PATCH /admin/shop/items/<turtle-id>` with `{"assetVersion":"a87ad177f0a0"}`.
   - `PATCH /admin/powerup-shop/items/<hitchhike-id>` with `{"assetVersion":"6fbfe79192cf"}`.

   Use existing authorized admin credentials without putting them in documents
   or logs. Preserve the Turtle's eight-frame geometry and all transforms, prices,
   visibility, identity, and other metadata. Retain old immutable URLs. Follow the
   existing peer-mirroring result for the character update; verify its outcome.
4. Verify `/assets/manifest` exposes both new versions and the eight-frame Turtle,
   then verify newly downloaded bytes and the app's cached/offline behavior.
   This Hitchhike step is necessary: current clients prefer its remote icon over
   the new bundled fallback. Updating only the app bundle would leave the old
   diagonal-thumb icon visible online. Both old/new full icons are128×128.
5. Follow the backend's `docs/red-card-cap-goodwill-deployment.md` to preview and
   apply the reviewed Red Card copy change and the one-time Soch +500 grant.
   Keep the fixed `admin_grant` reference `red-card-goodwill-2026-09-10`; verify
   exactly one matching +500 ledger row. No message, notification or historical
   step reversal is part of that operation.

These asset changes retain existing APIs and content identities. Older remote
clients can render the unchanged geometry; older bundled-only binaries retain
their original art until updated. No rollout flag or new rendering capability.

## Mobile release checks

Use README's current build commands, including the two Meta Dart defines.
Xcode transfers only those values into the derived native plist automatically.
Verify matching iOS/Android release artifacts, the actual iOS packaged Meta plist,
all seven retained iOS ad-unit defines, backend/OAuth/RevenueCat settings, and
platform signatures. No app upload, review submission or customer release has
been performed by preparing this handoff.

The scoped Meta events are installation/activation and SDK session metadata,
onboarding completion, explicit race join, Shop view, membership view, coin offers
view, and purchase intent. Signup and completed purchase/revenue are excluded.
The new privacy page must be public before the measurement-enabled app reaches
users. Review App Store privacy answers against these actual data flows before
submitting the binary; Android has no new Meta App Events integration.

The isolated pinned-SDK simulator harness verifies actual serialized SDK requests,
not a Meta dashboard. After installing the carrying build, verify live Events
Manager receipt and diagnose AEM eligibility separately; SDK integration alone
does not guarantee campaign eligibility or remove the dashboard warning instantly.

Manual placement checks for both platforms, including all mirrored surfaces, are
in `meta-app-events-requirements.md` and `shop-sectioned-frontend-validation.md`.
Turtle visual evidence/reproduction is in
`artifacts/turtle-cleanup-2026-09-10/`; Shop evidence is in
`artifacts/shop-sectioned-2026-09-10/`.

## Store disclosure check

The [public App Store listing](https://apps.apple.com/us/app/bara-step-challenges/id6760504694)
was inspected during preparation. It already lists Device ID, Product Interaction
and Advertising Data under Third-Party Advertising, with Identifiers and Usage
Data used for tracking. These are the relevant existing categories for the scoped
advertising-measurement integration; no health/step payload is added. The public
listing showed2.3.11, so the existing2.3.13candidate version was retained. This
read-only check is not an App Store Connect metadata edit or submission.
