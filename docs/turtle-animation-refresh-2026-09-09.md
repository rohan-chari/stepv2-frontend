# Turtle animation refresh — September 9, 2026

Replaced the bundled turtle walk sheet using the owner's `baraturtle.zip`,
frames `image0.png` through `image7.png` in numeric order. No artwork was drawn
or generated. `scripts/pack_turtle_frames.py` removes border-connected white,
applies one nearest-neighbor scale, centers each pose, and places the feet at
the existing y=69 ground line. Output remains eight 88×88 frames (704×88 RGBA).
An editable eight-frame Aseprite source and export entry were also installed
in the local art workspace; its export was verified pixel-identical.

## Published CDN and grant

- Backend asset commit: `cd46d1a`, pushed and published as a static-file update.
  No application restart, migration, or staging service start was needed.
- URL: https://steptracker-api.org/assets/characters/turtle@279671d5ad64.png
- SHA-256: `279671d5ad64a064877656247bb72d9f41748fbcea4f26790f614c863ca79225`.
- Public GET returned HTTP 200, `image/png`, and
  `public, max-age=31536000, immutable`; downloaded bytes match the repo file.
- Only after verifying the public PNG, the production admin API patched the
  existing turtle's `assetVersion` to `279671d5ad64`. Peer mirror returned OK.
  Existing eight-frame metadata, visibility, price, and placement were retained.
- Public `/assets/manifest` verified the new URL and `animationFrames: 8`.
- Exact display-name lookup uniquely identified Rohan. An idempotent ownership
  insert added the turtle; a transaction verified exactly one ownership row.
  No equip operation or coin mutation was performed.

## App compatibility and validation

The character resolver had remained bundled-first despite the app's existing
remote-art preference. It now uses current cached CDN character art, falls
back to the bundled species when unavailable, and preserves known frame counts
and baseline offsets when manifest metadata is absent. Unknown species retain
the existing capybara fallback. No new feature flag or API requirement.

Frozen binaries retain their compiled walking renderer and therefore still
use their old bundled turtle. CDN-backed shop thumbnails can update separately.
The walking-animation change requires a carrying app update. Shared Dart and
bundled assets cover both iOS and Android. The owner subsequently authorized
TestFlight build 2.3.13 (10); release source is `a22d435`.

Two new regressions were observed failing before their corresponding fixes:
cached turtle art ignored, and omitted geometry incorrectly cropping six frames.
Initial verification: 31 targeted tests passed. Release verification then ran
the full Flutter suite: all 3,139 tests passed, and `flutter analyze --no-pub`
was clean. Independent implementation and release reviews approved the change.
Physical device checks remain outstanding for TestFlight testing.

## Manual placement checklist (iOS and Android)

Repeat key checks online after a fresh launch and offline after download.

1. **Shop / Inventory → Characters:** select Turtle. Check one clean character
   in each tile and preview, with no adjacent-frame bleed or clipping; equip it.
2. **Accessory previews:** check head, face, neck, back, and feet items through
   the walk cycle. Confirm attachment points still fit the changed anatomy.
3. **Home:** feet meet the ground; character and accessories remain clear of
   the HUD throughout the animation.
4. **Individual race containing Rohan:** check lane containment, shadow/feet,
   accessories, and participant thumbnail.
5. **Team race with a turtle-equipped top scorer:** check hero-card containment,
   grass/feet and shadow alignment, and accessory placement.
6. **Shell icons:** inspect both Races inventory/effect rows and race-detail
   power-up inventory/details. Each icon must show exactly one turtle frame.
7. **Shop tutorial:** verify character previews where present and that spotlight
   targets remain aligned.
8. **Tab tutorial / demo race:** verify fixture characters remain correctly
   placed. Existing Home/demo fixtures do not inherit Rohan's equipped turtle;
   inspected race fixtures use capybara/corgi, so these are regression checks,
   not proof of turtle placement. A turtle fixture is needed for turtle-specific
   tutorial coverage.

Matching sheet geometry does not prove accessory fit: the supplied poses have
different head/leg positions, so the manual accessory check remains necessary.

## TestFlight release artifacts

Xcode confirmed `Upload succeeded` and `EXPORT SUCCEEDED` for 2.3.13 (10) on
September 9, 2026 at 17:58 UTC. The existing AppLovinSDK/FBAudienceNetwork dSYM
warnings remain nonblocking. Apple reports VALID / IN_BETA_TESTING, and build 10 is confirmed in the
internal “bara testers” group.

Artifacts and logs are retained in `build/release-candidates/2.3.13-10/`:

| Artifact | SHA-256 |
| --- | --- |
| `Bara-2.3.13-10.ipa` | `bb3dc5092c638bb607ac3ac107295326c6775e856c2683d5b68808dfe38b0c79` |
| `Bara-2.3.13-203140.aab` | `1386ea6000fc8dac5d94fa59dcbcd5f1fb52e303dc4d73d788777a8931ced6bf` |

Both signed packages contain the exact new turtle sheet. iOS signature, bundle,
team, production APNs, ten required public define values, and non-debuggable
entitlements verified. Android signature and trusted upload certificate verified;
compiled manifest reports version 2.3.13, code 203140 and Billing 8.3.0. All three
packaged native libraries match independently stripped fresh compiler output and
differ from build 9. README ad/backend values are present; inline native units
remain absent. Android code 203140 is the next monotonic code after 203139;
future Android releases must exceed it, including any 2.3.14 release.

The public Liftoff seller declaration and pinned iOS mediation SDKs were checked.
Consent dashboards, privacy labels and physical-device ad flows were not
re-audited for this artwork-only TestFlight update. The device checklist above
remains outstanding. No App Review/customer release or Play upload was performed.


Apple build ID: `1976208a-a1a5-4c39-80c7-873094b0e781`. The exempt-encryption
declaration matches build 9 (`usesNonExemptEncryption: false`). The internal
group acquired the build between checks; an explicit assignment attempt returned
422, and the subsequent group-membership GET confirmed it was already present.
Source commit/tag `a22d435` / `testflight/2.3.13-10` are pushed to origin.
