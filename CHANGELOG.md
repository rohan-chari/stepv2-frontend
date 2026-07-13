# Changelog

All notable changes to **Bara** (steps-tracker) are documented here.

This project ships an iOS app (App Store, native APNs) and an Android app
(Health Connect, Google Sign-In, Firebase/FCM) from the same Dart code — see
`CLAUDE.md`. Because shipped binaries are frozen and the backend is updated
independently, every entry below also had to keep working for users on older
app versions.

The format is loosely based on [Keep a Changelog](https://keepachangelog.com/).
Update this file after every major/minor change. Add new work under
**[Unreleased]**; on release, rename that section to the new version.

## How to update this file

- Log user-facing and notable technical changes under the current
  **[Unreleased]** heading, grouped as **Added / Changed / Fixed / Removed**.
- On version bump, rename **[Unreleased]** → `## [x.y.z] — YYYY-MM-DD` and start
  a fresh empty **[Unreleased]**.
- Keep iOS and Android notes together — the platforms release in lockstep.

---

## [Unreleased]

### Added
- New cosmetic accessories (cape, hydration pack) and additional accessory
  artwork, generated via the Codex `imagegen` pipeline and pre-tested.
- **App-wide "arcade" redesign.** Home hero is now a living pixel overworld
  (imagegen sky + course-crop ground, drifting clouds, count-up step HUD,
  capybara center stage). All five tabs plus shop and the invite-friends
  screen moved to parchment "game piece" cards on the checkered green with
  gold-tick section headers, staggered entrances, and selective glow/shine
  effects (`lib/widgets/arcade_fx.dart`, reusable). Shop Store/Inventory is a
  Clash-style tile grid; full item descriptions moved to a tap-through detail
  sheet. Bottom nav restyled (dark ledge, gold selected pill). Shared card
  primitives (`GameContainer`, `RetroCard`) upgraded in place so secondary
  screens/modals inherit the new look.
- Tutorial updated for the redesign: stale Ranked step/tab removed, Friends
  nav-tab and invite-friends (referral) steps added, spotlight measurement
  fixed (animations frozen during measurement).
- Shop thumbnails: content-cropped `_thumb.png` assets for padded/animated
  sprites; new imagegen beaver-tail shop icon; `AccessoryThumbnail` prefers
  bundled thumbs and no longer depends on backend `animationFrames`.

### Changed
- `PillButton` shadow is now a straight-down hard drop matching the press
  animation (was a diagonal smear on textured backgrounds).
- Accessory art downscaled to a 512px cap (rendered at <=150px everywhere;
  visually identical, verified at render size). Cuts bundled accessory
  assets from 22.5MB to 7.4MB (~15MB smaller installs). Animation sheets
  left untouched to preserve frame alignment.
- CLAUDE.md: new hard rule — never hand-draw shippable artwork; always use
  the Codex imagegen pipeline (or crop existing generated assets).

---

## [1.5.2]

### Added
- Rewarded-ad **extra daily box spin** (iOS, AdMob) with server-side
  verification (SSV) of the grant.
- Expanded ad placements: additional banner surfaces, an in-feed card, and a
  **Get Coins** hub (watch-an-ad-for-coins) with SSV-verified reward claims.
- iOS **Google Sign-In** alongside Apple Sign-In.

### Changed
- **Stopped collecting the Apple real name at sign-in** — display names are
  always randomly generated (`AdjectiveNoun##`), never sourced from the Apple or
  Google account name.
- Android release-track changes and configuration updates.

---

## [1.5.1]

### Added
- **Review prompt**: after a top-3 race finish, gate an "Enjoying Bara?" prompt
  into the native App Store / Play review sheet.
- **Corgi** character option — a selectable character slot with per-animal
  accessory placement.
- **Beaver tail** accessory, frame-sheet inventory thumbnails, and rainstorm
  powerup art.

### Changed
- Global event banner rework and assorted asset touch-ups.
- Cosmetic tuner passes render metadata (animation frames, render layer) through
  correctly.

---

## [1.5.0]

### Added
- New asset/artwork pass and the **rainstorm** area-of-effect powerup (slows
  other racers for a window).

### Fixed
- Minor bug fixes across races and cosmetics.

---

## [1.4.2]

### Added
- Public-races count surfaced on the races list.
- **Hide-from-leaderboard** toggle.

### Changed
- Queued-box styling refresh; ranked entry points redirect toward **friends**.
- Toast/notification styling updates.

### Removed
- Daily reward flow removed.

---

## [1.4.1]

### Added
- Races list shows a **queue slot** plus powerup sprites in the inventory row.

---

## [1.4.0]

### Added
- **Referral program** (frontend): invite UI, capture, and a referral dashboard;
  native auto-capture of invites, tailored onboarding welcome, and an in-app
  program-rules screen.
- **Pre-registration cards** — opt into an upcoming race before it starts.
- Mystery-box counts shown per race on the races list.
- Accessory **bobble** flag for animated cosmetics.
- **Profile-photo avatars** and finish-reward paid-places display.

---

## [1.3.9]

### Added
- **Live race placement** on the client with field-scaled payout presets
  (e.g. top-half / all-but-last, variable-length payout tiers).
- Per-race **mute toggle** for placement notifications.
- Confetti on wins.

---

## [1.3.8]

### Added
- Race **tutorial** screen and onboarding spotlight tour rewritten to match the
  real app; fixed onboarding dead-ends.
- Deep-link handling.

### Changed
- Home screen UI fixes.
- Races: renamed seeded daily/weekly challenges; dropped 10K/50K from labels.

### Removed
- Dead code cleanup: unused public widgets, orphaned widget files, and unused
  `TrailSign` / `showTopRightPin` fields.

---

## [1.3.x] — Android launch

### Added
- **Android app foundation**: Health Connect integration, Google Sign-In, and
  FCM push notifications, shipped from the shared Dart codebase.
- `MainActivity` extends `FlutterFragmentActivity` (required by Health Connect).

### Changed
- Android steps **exclude manually-entered steps** (anti-cheat) and de-duplicate
  across sources.

### Added (1.3.1–1.3.3)
- Daily reward flow.
- New cosmetic clothing items.
- Private races: **NO LIMIT** participant option and fixed toggle labels.

---

## [1.3.0]

### Added
- **Weekly-cohort ranked mode (v2)** — ranked tab with a version header.

---

## [1.2.0]

### Added
- Ranked game mode groundwork and UI consolidation.

---

## [1.1.8]

### Added
- New features and bug-testing pass ahead of the ranked/store expansion.

---

## [1.1.7]

### Added
- **Store + inventory** with the imposter/sneaky-swap mechanic and a sneaky-swap
  filter.
- **Scheduled races**.
- Global event banner.
- Hide-buffs and blocked-user modal.

### Changed
- Steps: trust HealthKit `cumulativeSum` source-merge and filter manual entries
  (dropped per-source dedup) to fix under/over-counting.
- Ranked cleanup.

---

## [1.1.6]

### Changed
- UI redesigns and fixes across tabs.

---

## [1.1.5]

### Added
- **Onboarding flow** and time-based race UI.
- **Featured Races** strip on the Races tab.
- Home **race-opportunity card**, profile-photo badge, and top-100 leaderboard.
- Race detail split into **Activity + Chat** tabs (IM-style chat ordering).
- Milestones, edit-race, kick modal, per-race mute badge.
- **App Reviewer** sign-in gesture (tap the Bara title 6 times) for App Store
  review.
- Invite countdown, challenge-back prefill, and a real App Store invite link.

### Changed
- Reverted to **time-based races**; dropped `targetSteps` from newly created
  races (step-goal races were briefly the default).
- Display-name validation: letters/numbers/underscores only, min 4 / max 30,
  no spaces.
- Home cleanup: streak chip, removed the HOW-TO and reward cards.
- Performance: parallel HealthKit reads, `skipRaceResolution` on `/steps`,
  de-duped multi-source steps in `getHourlySteps`.

### Fixed
- Surfaced previously-swallowed errors in step-fetch catch blocks.
- In-app notification styling.

---

## [1.1.4] and earlier — Foundations

The first phase of the app, built up across many iterations:

### Added
- Core **step tracking** via HealthKit with background sync (silent push +
  foreground timer, replace-policy polling).
- **Races / challenges**: race detail pages, weekly challenges, challenge logic,
  and race chat.
- **Powerups** flow and **mystery box** case-opening animation.
- **Shop** with the first cosmetics (e.g. cowboy hat, retro sunglasses) and
  skeleton loaders.
- **Leaderboard** and username validation.
- **Push notifications** and multiple UI/UX overhauls.
- App renamed to **Bara**.
- "The Hunt" design docs and a tuning simulator; background-sync architecture
  doc.

---

[Unreleased]: #unreleased
[1.5.2]: #152
[1.5.1]: #151
[1.5.0]: #150
[1.4.2]: #142
[1.4.1]: #141
[1.4.0]: #140
[1.3.9]: #139
[1.3.8]: #138
[1.3.0]: #130
[1.2.0]: #120
[1.1.8]: #118
[1.1.7]: #117
[1.1.6]: #116
[1.1.5]: #115
[1.1.4]: #114-and-earlier--foundations
