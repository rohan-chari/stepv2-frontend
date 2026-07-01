# Bara

Bara is an iOS Flutter app that turns your daily step count into a multiplayer race. Sign in with Apple, read steps from HealthKit, race friends or public lobbies in real time, earn and use powerups, customize your capybara with shop accessories, and check daily rewards and a global leaderboard — all wrapped in an arcade-themed UI.

---

## Features

### Auth & onboarding
- **Apple Sign-In** with backend session provisioning, session restore, and token refresh on app launch.
- **Display name flow** with availability checking, validation, and edit-from-settings.
- **Step goal onboarding** with validation (positive integer) and a dedicated edit screen.
- **Profile photo** upload with image picker + cropper, presigned S3 upload, prompt-dismiss flow, and account-delete handling.
- **Account deletion** path from settings (`DELETE /auth/account`).

### Step tracking
- **HealthKit read-only access** for `HealthDataType.STEPS`; reads today's total from local midnight through now.
- **Background step sync** scheduled hourly via Workmanager, with re-queue on each callback and 401-aware retry behavior.
- **Step samples upload** for granular intraday data (`POST /steps/samples`) in addition to the daily total (`POST /steps`).
- **Step calendar and stats** screens powered by `/steps/calendar` and `/steps/stats`.
- **Sync-stale chip** that visibly warns the user when the last sync is behind.
- **Resume refresh** on app foreground after Health access changes.

### Friends
- **Search by display name** with a 2-character minimum and 300 ms debounce.
- **Friend requests** — send, accept, decline, track outgoing.
- **Remove friend** action.
- **Friends' daily steps** loaded per-date for leaderboard and races.

### Races (head-to-head and multiplayer step races)
- **Create races** with friend pickers and target-step / duration configuration.
- **Public races** lobby — browse, join, and start matchmade races.
- **Race invites** — send, respond (accept/decline), and start when ready.
- **Live race progress** view with multi-participant track rendering, finishers banner, and live polling of `/races/:id/progress`.
- **Race chat** with messages, edit/delete, unread badges, mute toggle, and read receipts.
- **Race feed** showing in-race events (powerup earned, used, forfeited, etc).
- **Participant management** — kick participants from a race you own.

### Powerups (in-race)
- **Mystery box rolls** earned at step thresholds during a race, with three slots and one queue slot.
- **Box opening** screen with case-opening reveal animation and rarity tiers.
- **Use, discard, and queue management** with HELD / MYSTERY_BOX / QUEUED / USED / EXPIRED status flow.
- **Sneaky Swap** powerup with target-selection screen for stealing or swapping rivals' items.
- **Twelve powerup types** including Leg Cramp, Red Card, Shortcut, Compression Socks, Protein Shake, Runner's High, Second Wind, Stealth Mode, Wrong Turn, Fanny Pack, Trail Mix, and Detour Sign.
- **Live powerup inventory** synced via `/races/:id/inventory`.

### Shop & cosmetics
- **Accessory catalog** with ownership state, equipped slots, and live coin balance.
- **Purchase flow** using `Idempotency-Key` headers to prevent duplicate charges.
- **Equip/unequip** per slot (face, head, feet, etc); accessories render on the capybara in races and on the home track.
- **Coin balance badge** visible across the app.

### Daily rewards
- **Streak-based daily reward claims** with status check, claim flow, and a dedicated reward screen showing the current streak day.
- **Daily reward trigger button** surfaced when a claim is available.

### Leaderboard
- **Global leaderboard** with friend filter, period filter (week/all-time), and highlights row showing notable performers.

### Notifications
- **APNs push permission flow** with native iOS bridge over `MethodChannel`.
- **Device-token registration** with the backend and unregister on sign-out or denial.
- **Tap routing** for notification deep-links back into races.
- **Permission caching** so denied users aren't re-prompted automatically.

### Admin tools (signed-in admin users only)
- **Admin entry in Settings** behind `authService.isAdmin`.
- **Accessory render tuner** — live tweak of offsetX/Y, rotation, scale, price, and active flag on shop items, with save-to-backend that propagates to all users.
- **Powerup icon gallery** for visual QA of all 12 powerup sprite assets.
- **Powerup crate preview** for visual QA of the spinning crate animation.
- **Toast tests** for verifying info and error toast styling.

### UI system
- Custom arcade theme with reusable widgets: `pill_button`, `trail_sign`, `wooden_tab_bar`, `content_board`, `retro_card`, `arcade_page`, `game_background`, `game_container`, `game_toast`.
- **Capybara sprite system** with walk animation, equipped accessories, and per-race avatars.
- **Multi-race track** rendering for live races and the homepage goal track.
- **Skeleton loaders**, **spinning crate / coin / face** animations, **case-opening strip**, and themed loading states.
- **First-launch tutorial** with spotlight overlay and mock screens.

---

## Tech Stack

- **Dart 3.10.1**, **Flutter** (iOS-primary; Android/macOS/Web/Linux/Windows scaffolds present but not wired)
- **HealthKit** via `health` ^13.3.1
- **Apple Sign-In** via `sign_in_with_apple` ^7.0.1
- **Workmanager** ^0.5.2 for background sync
- **flutter_local_notifications** ^19.0.0 + native iOS APNs bridge
- **shared_preferences** ^2.5.4 for local persistence
- **google_fonts** ^6.2.1
- **image_picker** + **image_cropper** for profile photos
- **url_launcher** for support links

## Backend

Compile-time `BACKEND_BASE_URL` (default `http://127.0.0.1:3000`) points at the [steps-tracker-backend](https://github.com/rohan-chari/stepv2-backend) service. Set it via `--dart-define`.

## iOS setup

- Deployment target: iOS 14.0
- Entitlements: HealthKit, Apple Sign-In, APNs
- Background modes: `processing`, `remote-notification`
- `BGTaskSchedulerPermittedIdentifiers` includes `$(PRODUCT_BUNDLE_IDENTIFIER).periodicStepSync`
- Native bridge: `ios/Runner/AppDelegate.swift` registers Workmanager and routes notifications over `com.steptracker/notifications`
- `NSAllowsLocalNetworking` enabled for LAN dev backends

Open `ios/Runner.xcworkspace` in Xcode and verify the **HealthKit**, **Sign in with Apple**, and **Push Notifications** capabilities are enabled before the first build.

---

## Flutter commands

### First-time setup
```bash
flutter doctor
flutter pub get
```

### Run on a physical iPhone against staging
```bash
# Make sure your backend listens on 0.0.0.0:3000, not just localhost:3000
flutter run --debug --dart-define=BACKEND_BASE_URL=https://staging.steptracker-api.org
```

### Run on a physical iPhone against prod
```bash
# Make sure your backend listens on 0.0.0.0:3000, not just localhost:3000
flutter run -d 00008150-000171DE2638401C --device-connection=attached --debug --dart-define=BACKEND_BASE_URL=https://steptracker-api.org

### Run on a physical iPhone against local backend
```bash
flutter run -d <device-id> --dart-define=BACKEND_BASE_URL=http://<your-mac-lan-ip>:3000
```

### Run on simulator
```bash
flutter run -d ios
```

### Build production iOS
```bash
flutter build ios --dart-define=BACKEND_BASE_URL=https://steptracker-api.org
```

### Tests
```bash
flutter test
```

### Static analysis
```bash
flutter analyze
```

### Format
```bash
dart format lib test
```

### Clean
```bash
flutter clean && flutter pub get
```

### Regenerate pods (after native dependency changes)
```bash
cd ios && pod install --repo-update && cd ..
```

### List connected devices
```bash
flutter devices
```
