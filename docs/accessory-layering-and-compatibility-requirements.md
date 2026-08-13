# Accessory layering, compatibility, and gold-chain refresh

## Status

**Approved and implemented — review follow-up remediation in progress.**

## Summary and user story

Players should be able to preview and render a deliberately large loadout of
compatible accessories at once, without visually nonsensical combinations such
as the Knight Helmet with 3D Glasses. The Gold Chain should have a slightly
thicker sprite. Existing and future accessory PNGs should be publishable
through the remote-art CDN when appropriate, without breaking frozen clients.

## Scope

1. Replace the Gold Chain art with an approved, slightly thicker version while
   preserving its right-facing pixel-art style, alpha, placement, and asset key.
2. Make every avatar renderer consistently layer all accessories returned by
   the server, in a deterministic order: behind-body art, body, then front art.
3. Add server-enforced accessory compatibility so an invalid combination cannot
   be persisted or returned to any client.
4. Expose a safe way to simulate a dense compatible loadout in the accessory
   preview/tuner and cover every render surface through the shared renderer.
5. Bring stale deployment documentation into line with the existing CDN asset
   system.
6. Make clients released after this feature **remote-first** for accessory art:
   a manifest entry wins over a same-key bundled PNG. Retain bundled art only
   as an offline/failure fallback until pre-CDN clients are retired, then plan a
   separate asset-bundle removal release.

## Non-goals

- No new shop currency, odds, pricing, or slot enum.
- No change to ownership or purchase rules.
- No arbitrary client-only rejection: the backend remains authoritative.
- No mutation of an already-published immutable CDN URL.
- No immediate removal of any bundled accessory PNG.

## Current behavior and cause

- The frontend shared renderer already loops over its accessory list in
  `lib/widgets/home_course_track.dart`; it puts `renderLayer: behind` items
  below the body and remaining items above it.
- The backend schema and equip command permit one item per slot, not one item
  per *visual region*. `knight_helmet` is `HEAD`, while `glasses_3d` is `FACE`,
  so the current upsert accepts both. `buildEquipmentMap` and
  `buildAccessoriesList` also reduce by slot.
- Therefore the reported helmet-plus-glasses look is an absent compatibility
  policy, rather than a renderer failure.

## Confirmed product decisions

1. Compatibility is a reusable policy, not a one-off Knight Helmet + 3D
   Glasses exception. The initial catalog must classify Knight Helmet as a
   full-face/eyewear-blocking item and 3D Glasses as eyewear.
2. Equipping a conflicting item is rejected. The app preserves the current
   loadout and shows an explanatory toast; it never silently unequips gear.
3. “A bunch of things” is a simulation fixture containing one compatible item
   per existing slot so it shows the same category of loadout end users can
   wear. Same-slot stacking is explicitly out of scope.

## Proposed API and data model (pending decisions)

### Compatible-loadout preview only

No public API or database change is required. The frontend supplies a fixture
list containing one compatible item per current slot; renderers continue to
accept an array.

### Reusable compatibility policy

Add nullable, additive `compatibility` JSON to `ShopItem`:

```json
{
  "tags": ["full_face"],
  "blocksTags": ["eyewear"]
}
```

`tags` and `blocksTags` are each optional arrays of distinct strings from a
small server-owned vocabulary. Unknown/non-string/duplicate values are rejected
by the admin create/PATCH API. An item conflicts when either candidate
`blocksTags` intersects an equipped item's `tags`, or an equipped item's
`blocksTags` intersects candidate `tags`. Initial data: Knight Helmet gets
`tags:["full_face"], blocksTags:["eyewear"]`; 3D Glasses gets
`tags:["eyewear"]`. Null/absent metadata means no tags and blocks nothing.

The endpoint remains **`PUT /shop/equipment/:slot`** with `{ "itemId": "…" }`.
On conflict it returns this additive response:

```json
{
  "error": "That accessory conflicts with Knight Helmet.",
  "code": "ACCESSORY_CONFLICT",
  "conflictingItemIds": ["..."],
  "conflictingSlots": ["HEAD"]
}
```

Old app versions see an ordinary error message and retain their existing
equipment; no response field becomes required. Every read serializer continues
to emit the established accessory list/object shape.

### Remote-first asset contract

Add nullable/default-false `remoteOnly` to `ShopItem`. `assetVersion != null,
remoteOnly:false` is remote-backed with bundled fallback and remains visible to
pre-CDN clients; only `remoteOnly:true` is filtered to `remote_assets` clients.
Add `remote_asset_preferred` to both client-feature header variants. It is
additive: old backends ignore it. With the capability, a current manifest entry
uses matching disk cache then download; a failed download, absent/malformed
manifest, or old backend falls back to the bundled file if present. Without the
capability, behavior stays bundled-first. A remote-only key with no fallback
uses the existing placeholder. Tests cover current/stale cache, failure,
malformed manifest, remote-only placeholder, and legacy bundled-first clients.

## Frontend plan

1. Add widget tests first for a dense, compatible array: all entries render,
   behind entries remain behind the body, and the ordering is deterministic.
   Normalize then sort by fixed canonical order `BACK, FEET, NECK, FACE, HEAD`;
   this same order applies within each behind/front group. `CHARACTER` remains
   a separate body/animal selection and is never an accessory overlay.
2. Keep `normalizedAccessoriesForAnimal` defensive: invalid server fields are
   omitted; missing compatibility fields change nothing and never crash.
3. Update the shop equip flow to surface `ACCESSORY_CONFLICT` in an
   explanatory toast and leave the current selection intact.
4. Add a `SIMULATE FULL LOADOUT` toggle to `AdminAccessoryTunerScreen`. When
   enabled, its current capybara preview receives this exact compatible
   accessory list through the actual shared renderer: `backpack` (BACK,
   behind), `shoes` (FEET), `gold_chain` (NECK), `sunglasses` (FACE), and
   `baseball_cap` (HEAD). It replaces—not supplements—the selected-item
   preview; disabling it restores exactly that selected-item preview. A missing
   fixture asset must use the ordinary placeholder, not crash.
5. Replace the Gold Chain PNG only after the accessory-art critique loop:
   side profile/right orientation, black outline, transparent corners, and
   on-capybara fit at its production metadata.

## Backend plan

1. Write an integration test first proving an invalid conflict returns 409 and
   leaves the previously equipped item untouched; prove compatible loadouts
   still equip and serialize correctly.
2. Add nullable `compatibility` JSON in an additive migration. Validate it in
   admin create/PATCH, serialize it only where admin management requires it,
   and add it to peer mirror, drift-repair, and clone field lists. Reads must
   treat absent/null metadata as no extra conflict.
3. Introduce default-off `accessoryCompatibilityEnforcement` in `KNOWN_FLAGS`.
   Backfill/seed the initial Helmet and Glasses metadata while the flag is off;
   run an idempotent cleanup that keeps the most recently updated compatible
   item and unequips the other for every pre-existing conflict, then enable the
   flag after deployed client toast handling is available.
4. When enforcement is on, serialize each equip transaction per user by
   locking that user row before loading all equipment; re-read the loadout,
   evaluate both conflict directions, then upsert only if compatible. The
   equip error object carries optional `code`, `conflictingItemIds`, and
   `conflictingSlots`; the route emits them alongside the longstanding required
   `{error}` property.
5. Preserve `user_equipped_accessories`' current uniqueness unless the user
   after an explicitly approved future migration. Invalidate presentation
   caches only after a successful equipment mutation.

## CDN and deployment assessment

The deployed asset endpoint is working: `GET /assets/manifest` is served by
Cloudflare with `Cache-Control: no-cache`, while fingerprinted PNGs under
`/assets/<category>/<key>@<sha>.png` are immutable and cacheable for one year.
The production manifest currently contains no entries, so existing accessory
art remains bundled today.

The current resolver intentionally prefers a bundled `gold_chain.png`. This
feature changes that for a new app capability, `remote_asset_preferred`:

1. A capable client loads the manifest and uses its immutable remote URL for an
   accessory whenever the manifest has an entry for that key, even if the
   binary bundles a same-key PNG. It first uses a matching disk-cached version;
   otherwise it downloads it. A failed/missing manifest or download falls back
   to the bundled PNG when present, so offline startup and an older backend are
   safe.
2. The current `remote_assets` clients that do not advertise the new capability
   retain bundled-first behavior. Pre-CDN clients retain a Gold Chain catalog
   row because it is `remoteOnly:false`; `assetVersion` alone no longer hides a
   catalog row. The backend must only publish its version after the
   fingerprinted PNG is deployed and verified.
3. For Gold Chain, publish the immutable filename emitted for the approved
   final PNG, then set its `assetVersion` with `remoteOnly:false` only after the
   paired remote-first iOS/Android build is available. The refreshed bundle PNG
   remains present as its safe fallback.

The remote-art system is Cloudflare edge caching of versioned files served from
backend `public/assets`, not a separate origin. A versioned URL's bytes never
change; a refresh creates a new hash and manifest row.

### Bundle-retirement gate (future release)

Do not remove bundled accessories merely because the remote-first build exists.
Before a separate removal release, establish from production version telemetry
that no supported active client is below the remote-assets floor for at least
the agreed retention window; preserve the app's critical/start-screen art and
each asset needed to render content visible to that remaining floor. The
backend must continue to serve the complete manifest, with every production
accessory fingerprint deployed and verified. Add a release checklist query and
an explicit minimum-supported-version policy before approving deletion.

## Rollout and backward compatibility

1. Deploy additive backend schema/code with `remoteOnly:false` defaults and
   remote-only catalog gating; seed,
   clean up legacy invalid equipment idempotently, and verify it.
2. Release the paired iOS/Android build with `remote_asset_preferred` and its
   thicker bundled Gold Chain fallback.
3. Publish and checksum-verify the immutable PNG; only after that production
   build is available, set Gold Chain `assetVersion` plus `remoteOnly:false`.
4. Enable enforcement. A
   new app gives an explanatory conflict toast; a frozen app receives the
   existing error shape and retains its equipment. A new app against an older
   backend can still equip because the new rule is absent.
5. Keep a new remote-only art row `testOnly: true` until the carrying app is
   available as required by the release policy. Never overwrite an existing
   fingerprinted CDN file; issue a new `assetVersion` instead.
6. Update `DEPLOYMENT.md` and `docs/adding-cosmetic-items.md`, both of which
   still incorrectly state that no CDN path exists.

## Acceptance criteria

- Gold Chain is visibly thicker and passes the art critique/on-capybara review.
- A remote-first client uses a cached/versioned CDN Gold Chain over its bundled
  same-key file, but falls back safely to the bundled file while offline or
  against a missing/old manifest; older client capabilities preserve their
  current behavior.
- Every real avatar surface uses the shared layered renderer and shows the
  compatible fixture without dropped layers or crashes.
- The selected helmet/glasses policy is enforced server-side and reflected in
  the shop interaction.
- All malformed/missing server fields degrade safely.
- Backend integration coverage includes nullable/malformed metadata, old and
  new feature headers, legacy cleanup, and parallel conflicting equips where
  exactly one request succeeds. Run it with Redis disabled and with catalog
  caching enabled; the equip invariant remains Postgres-authoritative.
- Frontend pumped-widget coverage proves the actual 409 shows the toast and
  retains existing equipped state; it also covers the simulation toggle,
  restoration, both themes, real shared renderer, and missing fixture art.
- The relevant frontend widget tests, backend integration tests, `flutter
  analyze`, and both iOS/Android release impacts are accounted for.

## Revision log

- **Gap pass 1:** Separated the already-working array renderer from the actual
  one-per-slot backend policy; added an explicit same-slot-stacking branch
  because it is a breaking-contract risk.
- **Gap pass 2:** Added version-skew behavior for remote art, atomic
  transaction requirements for conflicts, immutable CDN publishing, and the
  stale-documentation correction.
- **Architect review:** Corrected the endpoint/response contract; made tags and
  blocks bidirectional and validated; added flag-gated backfill/cleanup and
  per-user transaction serialization; fixed canonical layer order and exact
  tuner fixture; corrected the Gold Chain CDN conclusion; expanded
  mixed-version/cache/concurrency coverage.
- **Remote-first revision:** Changed the approved CDN model at product request:
  specified `remote_asset_preferred`, cache/download/bundled-fallback order,
  Gold Chain publication sequence, and telemetry-gated future bundle removal.
- **Remote-first gap pass 1:** Kept the current `remote_assets` capability
  separate from the new remote-first behavior, so older CDN-capable builds do
  not silently change their resolver semantics.
- **Remote-first gap pass 2:** Added explicit offline/old-backend fallback and
  required a distinct telemetry-backed deletion decision rather than treating a
  successful CDN rollout as authorization to remove bundled art.

## Manual UI-placement test plan

1. **Admin → Accessory Render Tuner:** Enable `SIMULATE FULL LOADOUT`. Verify
   the behind item is below the body and all four front layers are on the one
   capybara; no selected-item duplicate appears. Disable it and verify the
   single selected preview returns in the same location.
2. **Home:** With the same compatible five-slot loadout saved, verify the hero
   has every layer in one avatar location, with no duplicates.
3. **Races tab:** A race-card leader with the loadout has all layers only at
   their existing avatar location.
4. **Individual race detail:** Course and standings both show the complete
   loadout only on the intended participant.
5. **Team race:** Team lobby, scoreboard, and any moving handoff avatar retain
   all layers inside normal bounds; nothing is left at a source slot or cloned.
6. **Boards / ranked (where enabled):** The equipped user’s podium avatar has
   the full outfit in its existing position.
7. **Shop:** With Knight Helmet equipped, attempt 3D Glasses; verify the error
   toast overlays Shop without moving tiles, helmet remains equipped, and
   glasses do not. Repeat the reverse direction.
8. **Tab tutorial:** Verify Home, Races, and race-detail preview beats retain
   their configured compatible accessories; spotlight targets remain correct.
9. **Demo race tutorial:** Course and standings retain their normal fixture;
   dense tuner simulation never leaks in; coach rings/cards retain targets.

Risks/implementation checks: keep `tutorialPreviewAccessories` and
`DemoRaceEngine.myAccessories` compatible with the seeded policy; exercise all
race-detail renderer payload shapes; preserve existing `showErrorToast` use for
the decoded 409; no Shop or tuner tutorial mirror exists.
