# Home SETUP section — placement + persistence

**Status:** implemented (backend + frontend), not committed, not deployed
**Date:** 2026-07-27
**Owner decisions folded in:** server-side persistence, SETUP directly above races, rename-chip-only scope

---

## 1. Summary & user story

Two changes to the home tab's `SETUP` section:

1. **Placement.** `SETUP` currently renders *below* the race card
   (`lib/screens/tabs/home_tab.dart:250` race, `:258` setup). Setup work is a
   prerequisite for everything else on the page — a user with no display name or
   no photo is worse off in every race they join — so it must render *above* the
   race card.

2. **Persistence bug.** The section re-appears after every sign-out →
   sign-in cycle. Root cause is the rename chip (§3). Its "seen"/"dismissed"
   state is device-scoped `SharedPreferences`, and `AuthService.signOut()`
   deliberately wipes it. Fix: move that state onto the user row, mirroring the
   existing `profilePhotoPromptDismissedAt`.

> **User story.** As a returning user who signs out and back in (new device, account
> switch, support step), I don't want to be re-taught things I've already
> dismissed — and when SETUP *does* have something for me, I want to see it
> before I scroll past a race card.

---

## 2. Root-cause analysis (the "why does it come back" question)

`_SetupPromptsSection` (`lib/screens/tabs/home_tab.dart:998`) renders up to four
things. Only one of them is not durably persisted:

| Prompt | Condition | Persistence | Survives sign-out? |
| --- | --- | --- | --- |
| Display-name prompt | `displayName == null` | server (`User.displayName`) | ✅ yes |
| Profile-photo prompt | no photo && not dismissed | server (`User.profilePhotoPromptDismissedAt`, `prisma/schema.prisma:22`) | ✅ yes |
| "You can add one anytime" confirmation | transient, 3s timer | in-memory | n/a |
| **Rename chip** | `shouldShowRenameChip()` | **device `SharedPreferences`** | ❌ **no** |

### 2.1 The defect

- `OnboardingStateService` stores `rename_chip_shown_count` and
  `rename_chip_dismissed` in `SharedPreferences`
  (`lib/services/onboarding_state_service.dart:30-31`).
- Both keys are listed in `allKeys` (`:33-45`).
- `AuthService.signOut()` calls `OnboardingStateService.clearPersistedState()`
  (`lib/services/auth_service.dart:723`), which removes every key in `allKeys`
  (`lib/services/onboarding_state_service.dart:205-210`).
- The clear is **intentional and correct for its stated purpose** — the comment
  at `auth_service.dart:719-722` says these are device-scoped and "must not leak
  across accounts". The health-gate ladder and notification-ask counters genuinely
  are device-scoped.
- But the rename chip is *not* device-scoped intent. "This account has been told
  its generated name is changeable" is a property of the **account**, not the
  handset. Storing it device-side puts it in the blast radius of a clear that
  exists for a different reason.

Net effect: sign out → `rename_chip_shown_count` = 0, `rename_chip_dismissed` =
absent → sign back in → chip is eligible again, for another 3 appearances.

### 2.2 A second, compounding defect (in scope)

`_resolveRenameChip()` calls `recordRenameChipShown()` from `initState`
(`home_tab.dart:1033-1046`). The home tab lives in a `PageView` **without**
keep-alive (`main_shell.dart:2493`; see the comment at `main_shell.dart:1824`
acknowledging "home page disposed by the PageView"). So swiping to Races and back
disposes and re-creates `_SetupPromptsSection`, burning one of the three
allowed shows.

The `maxRenameChipShows = 3` budget is therefore consumed in roughly three tab
swipes inside a single session, not across three meaningful visits. Combined with
§2.1 this produces exactly the reported experience: the chip burns out fast, then
a sign-out cycle refills it.

**Fix:** count a "show" at most once per app session.

### 2.3 Explicitly NOT the bug

- The **profile-photo prompt** re-appearing is not a bug. `/auth/apple`,
  `/auth/google` and `/auth/me` all return the full user row
  (`src/modules/users/routes.js:184`, `:227`, `:295`; `ensureAppleUser.js:150`
  returns the raw Prisma row), so `profilePhotoPromptDismissedAt` round-trips and
  `applyBackendUser` restores it (`auth_service.dart:559-562`). If the user never
  tapped "NO THANKS" and still has no photo, the prompt is *supposed* to show.
- The **display-name prompt** never fires on `onboardingV3Enabled` accounts —
  `ensureAppleUser` always generates `AdjNoun##`, so `displayName` is never null.

---

## 3. Scope / non-goals

**In scope**

- Move `_SetupPromptsSection` above the race card / race skeleton on home.
- Persist rename-chip state on the user row; read it back on sign-in.
- Stop double-counting rename-chip shows across `PageView` disposal.

**Non-goals**

- Coach-tip seen-set, notification-ask counters, health-gate ladder, session
  counter — these keep resetting on sign-out, as today (owner decision).
- No visual redesign of the SETUP rows, the chip, or the section header.
- No change to the profile-photo prompt's logic or copy.
- No change to `maxRenameChipShows` (stays 3) or to who is eligible
  (`onboardingV3Enabled` only).
- No new home sections, no reordering of quick-actions / global-event / milestones.

---

## 4. API contract (pinned — backend implements first)

### 4.1 Data added to the user payload

Two additive fields on the user object returned by **every** endpoint that
already returns a user: `POST /auth/apple`, `POST /auth/google`,
`POST /auth/review`, `GET /auth/me`, and the `{ user }` envelopes from
`/auth/me/display-name`, `/auth/me/profile-photo*`, `/auth/me/leaderboard-visibility`,
`/auth/me/featured-auto-join`.

```jsonc
{
  "user": {
    "id": "…",
    "displayName": "SwiftCapybara07",
    "profilePhotoPromptDismissedAt": null,

    // NEW — both additive
    "renameChipShownCount": 1,               // integer, >= 0, never null
    "renameChipDismissedAt": null            // ISO-8601 string or null
  },
  "sessionToken": "…"
}
```

These ride the existing `...user` spread, so no serializer changes are needed
beyond the migration — but the backend agent **must** add an integration test
asserting both keys are present on `/auth/me`, because a future `select:`
whitelist would silently drop them.

### 4.2 New endpoint — record a show

```
POST /auth/me/rename-chip/shown
Authorization: Bearer <sessionToken>
Body: {}   (empty)
```

**200**
```jsonc
{ "user": { …full user…, "renameChipShownCount": 2, "renameChipDismissedAt": null } }
```

Semantics: `renameChipShownCount = renameChipShownCount + 1`. Idempotency is
**not** required at the API layer — the client guarantees at-most-once per app
session (§6.3). Server clamps at `renameChipShownCount <= 99` so a
misbehaving/looping client can't unbounded-increment the column.

If `renameChipDismissedAt` is already set, the increment is a **no-op** and the
unchanged user is returned 200 (the chip should never have been shown; don't
error, just don't count it).

**401** if unauthenticated. **500** on unexpected error, matching every
neighboring route's shape `{ "error": "Internal server error" }`.

### 4.3 New endpoint — dismiss

```
POST /auth/me/rename-chip/dismiss
Authorization: Bearer <sessionToken>
Body: {}   (empty)
```

**200**
```jsonc
{ "user": { …full user…, "renameChipShownCount": 2, "renameChipDismissedAt": "2026-07-27T18:03:11.442Z" } }
```

Semantics: sets `renameChipDismissedAt = now()` if currently null; **idempotent**
— a second call returns the existing timestamp unchanged (does not re-stamp).

**401** / **500** as above.

Both routes live in `src/modules/users/routes.js`, immediately after
`/me/profile-photo/prompt-dismiss` (`:542`), and use the identical
`res.json({ user: await withRuntimeFlags(user, req.headers["x-app-version"]) })`
response shape so `applyBackendUser` consumes them with no new parsing.

### 4.4 Backward compatibility with app versions in the wild

**Old app (≤ 2.0.1) against the new backend.**
Frozen binaries never call the two new routes and never read the two new fields.
They keep using their local `rename_chip_*` prefs and keep clearing them on
sign-out. Their behavior is byte-for-byte unchanged. The new columns simply sit
unread. ✅

**New app against an older backend** (possible during the phased rollout window,
and permanently for anyone pointed at a stale staging box).
- `applyBackendUser` uses `containsKey` guards, so absent keys leave the fields
  at their defaults.
- The client MUST treat "server fields absent" as *fall back to the existing
  local prefs path*, not as "count = 0, never dismissed". Concretely:
  `AuthService.renameChipStateFromServer` returns `null` when neither key was
  present, and `_SetupPromptsSection` then uses `OnboardingStateService`
  exactly as today.
- The two new POSTs must fail **silently** (fire-and-forget, catch-and-ignore) —
  an older backend 404s them, and a 404 must never surface an error toast or
  block the chip from working locally.

**Account deletion.** The columns live on `User` and are dropped with the row by
the existing cascade; `deleteUserAccount` needs no change.

---

## 5. Data model / migration

`prisma/schema.prisma`, on `model User`, adjacent to the existing
`profilePhotoPromptDismissedAt` (line 22):

```prisma
  renameChipShownCount          Int                  @default(0) @map("rename_chip_shown_count")
  renameChipDismissedAt         DateTime?            @map("rename_chip_dismissed_at")
```

Migration (`prisma migrate dev --name add_rename_chip_state`):

```sql
ALTER TABLE "users"
  ADD COLUMN "rename_chip_shown_count" INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN "rename_chip_dismissed_at" TIMESTAMP(3);
```

- **No backfill.** Every existing row starts at `0 / NULL`, i.e. "eligible".
  That is a deliberate, accepted regression: users who already dismissed the chip
  locally will see it up to 3 more times, once. The alternative (backfilling
  `dismissedAt = now()` for everyone) would silently retire the nudge for the
  entire base including users who never saw it. Three impressions of a small chip
  is the cheaper error.
- `NOT NULL DEFAULT 0` makes the count safe to read without a null guard. The
  `DateTime?` mirrors `profilePhotoPromptDismissedAt` exactly.
- Deploy note: `ADD COLUMN … DEFAULT` on Postgres 11+ does not rewrite the table,
  so this is a fast, non-locking migration on the prod `users` table.
- ⚠️ Run against the local/test DB first. **Never** point migrations or
  integration tests at the prod DB (CLAUDE.md).

Model surface in `src/modules/users/models/user.js`:

```js
  async recordRenameChipShown(id) { … }   // clamped increment, no-op if dismissed
  async dismissRenameChip(id) { … }       // idempotent stamp
```

Command layer in a new `src/modules/users/commands/renameChip.js`, following the
`buildX(dependencies)` factory pattern of `commands/profilePhoto.js` (injectable
`User` and `now`, so the integration tests can pin time).

---

## 6. Frontend plan

### 6.1 Placement (owner decision: directly above races)

In `lib/screens/tabs/home_tab.dart`, inside the `Column` at `:195`, the new order is:

| Stagger index | Section |
| --- | --- |
| 0 | soil shadow + quick-actions row (streak / shop) |
| 1 | global event banner (`2x STEPS`), if live |
| **2** | **`_SetupPromptsSection`** ← moved up |
| **3** | race card (`_buildRaceSection`) or `_buildRaceSkeletonSection` |
| 4 | `StepMilestonesSection` |

Mechanically: move the `StaggerIn(index: 3, child: _SetupPromptsSection(…))` block
(`:256-269`) to sit before the `if (raceCard != null) … else if (raceCardLoading) …`
block (`:249-255`), and swap the two `index:` values so the cascade still runs
top-to-bottom. **The `index:` values must match visual order** or the bounce-in
animation plays out of sequence.

`_SetupPromptsSection` already returns `SizedBox.shrink()` when it has nothing to
say (`:1134-1138`), so a fully-set-up user sees no gap and no shifted layout.
The `StaggerIn` wrapper around an empty child must not introduce padding —
verify with the golden/widget test in §7.

### 6.2 Reading server state

`AuthService`:
- New private fields `_renameChipShownCount` (`int?`) and
  `_renameChipDismissedAt` (`String?`), both persisted to `SharedPreferences`
  under `auth_rename_chip_shown_count` / `auth_rename_chip_dismissed_at`
  alongside the other `auth_*` keys, and both cleared in `signOut()` **with**
  the other `auth_*` keys (that clear is correct — they're a cache of server
  state, and the server restores them on the next sign-in).
- `applyBackendUser` gains two `containsKey`-guarded reads, matching the existing
  style at `:559-562`. Read defensively: `as int?`, `as String?`; a garbled type
  leaves the previous value.
- Public getters `renameChipShownCount`, `renameChipDismissedAt`, plus
  `bool get hasServerRenameChipState` — true only when at least one of the two
  keys was present in a backend payload this session. This is the flag that
  selects the server path vs. the legacy local path (§4.4).

### 6.3 The chip's decision logic

`_SetupPromptsSection._resolveRenameChip()` becomes:

```
if (!widget.showRenameChip) return;                       // onboardingV3 gate, unchanged
if (displayName is null/empty) return;                    // unchanged

if (authService.hasServerRenameChipState) {
  if (authService.renameChipDismissedAt != null) return;
  if ((authService.renameChipShownCount ?? 0) >= maxRenameChipShows) return;
  show the chip;
  if (!OnboardingStateService.renameChipCountedThisSession) {
    OnboardingStateService.markRenameChipCountedThisSession();
    unawaited(authService.recordRenameChipShown());       // fire-and-forget, errors swallowed
  }
} else {
  …existing OnboardingStateService path, verbatim…        // old-backend fallback
}
```

- `renameChipCountedThisSession` is a **static in-memory** bool on
  `OnboardingStateService` (not a pref) — it resets on process death, which is
  the definition of "session" we want, and it fixes §2.2 without a new key.
- Tapping the chip calls `authService.dismissRenameChip()` (server path) or
  `OnboardingStateService.dismissRenameChip()` (fallback), then opens
  `DisplayNameScreen` as today. The dismissal is optimistic: hide the chip
  immediately, POST in the background, and if the POST fails do **not** re-show
  it this session (a network blip must not un-dismiss the UI).

### 6.4 States

- **Loading** — the chip simply doesn't render until `_resolveRenameChip`
  resolves. No skeleton; a spinner for a nudge chip is worse than its absence.
- **Empty** — `SizedBox.shrink()`, unchanged.
- **Error** — every new network call is fire-and-forget; there is no error state.
  A failed "shown" POST means at worst one extra impression later. A failed
  "dismiss" POST means the chip may return on a later launch — acceptable, and
  the next successful dismiss fixes it.
- **Missing fields (old backend)** — falls back to local prefs, §4.4.

### 6.5 iOS + Android

Pure Dart; no platform channels, no new plugins, no manifest/entitlement changes.
Both platforms get it from the same code. Per CLAUDE.md the release that carries
this must build **iOS `flutter build ipa` and Android `flutter build appbundle
--flavor prod` in lockstep**, with matching `--dart-define=BACKEND_BASE_URL` and
version/build numbers.

---

## 7. Test plan (written FIRST, before the logic)

Integration-first, per CLAUDE.md. Neither agent may modify or delete an existing
test; if one looks wrong, surface it.

### Backend — `test/integration/` (real HTTP, real test DB)

1. `GET /auth/me` returns `renameChipShownCount: 0` and
   `renameChipDismissedAt: null` for a freshly provisioned user.
2. `POST /auth/apple` (new user) → the `user` envelope contains both new keys.
3. `POST /auth/me/rename-chip/shown` → 200, count 0→1; call again → 2.
4. Count clamps: 99 → `shown` → still 99, still 200.
5. `POST /auth/me/rename-chip/dismiss` → 200, `renameChipDismissedAt` is a
   parseable ISO timestamp; a second call returns the **same** timestamp.
6. `shown` after `dismiss` is a no-op: 200, count unchanged.
7. Both routes 401 without a bearer token.
8. Sign-out/sign-in simulation: dismiss, then re-`POST /auth/apple` with the same
   Apple sub → the returned user still carries the dismissal. **This is the
   regression test for the reported bug** and must go through the real endpoint,
   not the model.
9. Existing `/auth/me` payload assertions still pass (no field removed).

### Frontend — `test/` (`testWidgets`, pump the real `HomeTab`)

1. **Order:** pump `HomeTab` with a race card *and* an eligible rename chip;
   assert the `SETUP` header's `dy` is less than the race section's `dy`.
2. **No gap:** pump a fully-set-up user (name set, photo set, chip dismissed);
   assert no `SETUP` header renders and the race card's `dy` is unchanged versus
   a control pump without the setup widget in the tree.
3. **Server dismissal wins:** `authService` with
   `renameChipDismissedAt != null` → no chip, even with empty local prefs.
   This is the unit-of-behavior the bug report is about.
4. **Server count wins:** `renameChipShownCount = 3` → no chip.
5. **Old-backend fallback:** payload omitting both keys → chip renders and the
   local `OnboardingStateService` path is used (assert via the prefs value).
6. **Once per session:** pump `HomeTab`, dispose, pump again → the "shown" POST
   fires exactly once (assert on a fake `BackendApiService` call count). This is
   the §2.2 regression test.
7. **Dismiss is optimistic:** tap the chip with a `BackendApiService` that throws
   → chip disappears and stays gone on rebuild; no error toast.
8. Existing `test/onboarding_revamp_test.dart` rename-chip cases still pass.

⚠️ `PackageInfo.setMockInitialValues` in `setUp` for any widget test that touches
activation events — `PackageInfo.fromPlatform()` never resolves under
`testWidgets`' fake-async zone and hangs silently.

---

## 8. Backward-compat & rollout

**Deploy order — backend first, always.**

1. **Backend.** Migration + model + commands + routes + the §7 backend tests.
   Deploy to staging, verify, then prod (`pm2 reload`, cluster mode). At this
   point every shipped app version is unaffected: the columns are unread and the
   routes are uncalled.
2. **Frontend.** Ship the new build to TestFlight / internal Android track.
   Because the prod backend already serves the fields, the client takes the
   server path immediately.
3. **App Store / Play rollout** is phased over ~a week. Throughout that window,
   old and new binaries coexist against the same backend. Old ones use local
   prefs; new ones use the server. There is no shared state between the two paths
   and no way for them to conflict — the worst case is a user who upgrades
   mid-window sees the chip up to 3 more times (§5, no backfill).

**No feature flag / `testOnly` gate is required.** The change is invisible to
frozen clients by construction, and the frontend degrades to today's exact
behavior against a backend without the columns. Adding a flag would gate a
behavior that has no failure mode worth killing.

**Rollback.** Reverting the backend deploy leaves the columns in place and unread —
new clients fall back to the local path via `hasServerRenameChipState == false`.
Safe in both directions; the migration never needs to be reversed.

---

## 9. Acceptance criteria / definition of done

- [ ] `SETUP` renders directly above the race card on home; `StaggerIn` indices
      match visual order; a user with nothing to set up sees no gap.
- [ ] Sign out and sign back in on a real device: the rename chip does **not**
      re-appear once dismissed. (The profile-photo prompt correctly still shows
      if the user has no photo and never dismissed it.)
- [ ] Swiping Home → Races → Home does not consume more than one of the three
      allowed chip impressions per app launch.
- [ ] New build against a backend *without* the migration behaves exactly as
      2.0.1 does today (verify against a pinned staging box or a stubbed API).
- [ ] Old build (2.0.1) against the migrated backend behaves exactly as today.
- [ ] All §7 tests written before their implementation and passing; backend run
      via `npm run test:unit` / `npm run test:integration` against the **test**
      DB, never bare `npm test`, never prod.
- [ ] No existing test modified or deleted.
- [ ] iOS `ipa` and Android `appbundle` both build, same version/build number,
      same `BACKEND_BASE_URL`.

---

## 10. Revision log

**Pass 1 (fresh-eyes gap review).**
- The original draft treated "SETUP comes back" as one bug. Split it into the
  four prompts and proved only the rename chip is non-durable (§2, table) —
  the profile-photo prompt is server-backed and re-appearing is correct behavior
  (§2.3). Without this, an implementer would have "fixed" a working prompt.
- Found and added the second, compounding defect: the home tab lives in a
  non-keep-alive `PageView`, so `initState` re-fires on every tab swipe and burns
  the 3-show budget (§2.2). The placement fix alone would have left the chip still
  behaving erratically.
- Added the explicit no-backfill decision and its rationale (§5) — the first draft
  left the migration's backfill unstated, which is exactly the kind of gap that
  gets decided badly at 2am.
- Pinned the exact response envelope for both new routes to the existing
  `{ user: withRuntimeFlags(...) }` shape (§4.2/4.3) so `applyBackendUser` needs
  no new parsing.

**Pass 2 (second independent gap review).**
- Hard rule check: the first draft did not say what a **new client against an old
  backend** does. Added §4.4's `hasServerRenameChipState` tri-state — absent keys
  must mean "use the legacy local path", not "count = 0, never dismissed", which
  would have re-shown the chip to everyone on a stale staging build. Added test 5.
- Added the clamp (`<= 99`) and the dismissed-then-shown no-op to §4.2 — without
  them a looping client could unbounded-increment a prod column.
- Made the dismiss endpoint explicitly **idempotent** (don't re-stamp), so a
  double-tap doesn't move the timestamp.
- Specified that both new POSTs are fire-and-forget with swallowed errors (§6.3,
  §6.4) — a 404 from an old backend must never toast.
- Made the dismissal optimistic and non-reverting on failure; the original
  "optimistic then revert" pattern copied from `updateLeaderboardVisibility` is
  wrong here, because reverting would un-dismiss a nudge the user explicitly
  retired.
- Called out that `renameChipCountedThisSession` must be **in-memory static**, not
  a new pref — a pref would land back in `allKeys` and get wiped by the very
  `signOut()` clear this spec is working around.
- Added the deploy note that `ADD COLUMN … DEFAULT` is non-rewriting on PG 11+,
  and the reminder that the `auth_rename_chip_*` client keys *should* still be
  cleared on sign-out (they're a cache, and the server refills them).
- Added acceptance criterion for the old-build-against-new-backend direction,
  which pass 1 only covered in prose.

**Pass 3 (corrections found during implementation — spec was wrong, code is right).**
- **§6.2 `hasServerRenameChipState` was defined wrong.** "At least one key present in a
  backend payload *this session*" means a cold start takes the legacy path until
  `/auth/me` answers — and because the server path never writes the local
  `rename_chip_*` prefs, the chip would flash back on **every launch**. Corrected:
  the getter is also true when a cached `auth_rename_chip_*` pref exists, since a
  cached value can only have come from a backend that sends the fields.
- **§6.3's "verbatim" was ambiguous** and was read as preserving the §2.2
  double-count on the old-backend fallback path. Intent was the *storage* path only.
  Corrected: `renameChipCountedThisSession` gates the impression on **both**
  branches, via a shared `_countOneImpression()`.
- **§5 left concurrency unspecified.** "Clamped increment" / "idempotent stamp" is
  satisfied by a read-modify-write that still lets two in-flight requests
  double-increment past 99 or re-stamp a dismissal — and §6.3 makes concurrent
  `shown` calls plausible (fire-and-forget from `initState` in a disposing
  `PageView`). Implemented instead as a conditional `updateMany` + re-read:
  `shown` → `where: { id, renameChipDismissedAt: null, renameChipShownCount: { lt: 99 } }`,
  `dismiss` → `where: { id, renameChipDismissedAt: null }`. Race-safe, not merely
  serially correct. **Pin this if it is ever reimplemented.**
- **§4.1's endpoint list over-promises relative to §7.** The fields do ride the
  `{ user }` envelope from `/auth/me/display-name`, `/auth/me/profile-photo*`,
  `/auth/me/leaderboard-visibility` and `/auth/me/featured-auto-join` (same
  `withRuntimeFlags(user, …)` spread), but only `/auth/me` and `/auth/apple` are
  asserted. Accepted as-is: the client's `containsKey` guards mean an omission on
  those five endpoints is a no-op, not a bug.
- **§7 frontend test 2's "control pump without the setup widget"** is not
  expressible — `_SetupPromptsSection` is private and unconditionally in the
  `Column`. Replaced with the stronger direct assertion: `StaggerIn(index: 2)`
  measures exactly `0.0` height for a fully set-up user.

**Open questions:** none.
