# Bara

Bara is a Flutter app for iOS-focused daily step competition. It signs users in with Apple, reads the current day's steps from HealthKit, syncs them to a backend API, supports friend discovery and weekly challenge matchups with negotiated stakes, and includes admin tools for weekly challenge operations. The app boots background sync and push-notification plumbing at launch, all wrapped in a custom hiking-game themed UI built from reusable Flutter widgets, Google Fonts typography, and an animated capybara sprite.

## Tech Stack

| Layer | Technology |
|-------|------------|
| Language | Dart 3.10.1 |
| App framework | Flutter |
| Health data | `health` 13.3.1 |
| Authentication | `sign_in_with_apple` 7.0.1 |
| Background work | `workmanager` 0.5.2 |
| Notifications | iOS `MethodChannel` bridge, APNs registration, `flutter_local_notifications` 19.0.0 |
| Local persistence | `shared_preferences` 2.5.4 |
| Typography | `google_fonts` 6.2.1 |
| Testing | `flutter_test` |
| Linting | `flutter_lints` 6.0.0 |
| Native shells | iOS, Android, macOS, Linux, Windows, web |

## Features

- **Session bootstrap and token refresh** - `main.dart` initializes Workmanager and notifications, restores cached auth state, refreshes the backend session via `GET /auth/session`, and routes users into the start, display-name, or tabbed shell flow.
- **Apple sign-in and backend provisioning** - `AuthService` requires an Apple identity token and user identifier, provisions the backend user through `POST /auth/apple`, and persists the backend session token, profile basics, and admin flag.
- **HealthKit daily steps** - `HealthService` requests read-only access for `HealthDataType.STEPS` and reads today's total from local midnight through the current time.
- **Hourly background sync** - `BackgroundSyncManager` and `background_sync_service.dart` schedule a connected-network sync every hour and post today's steps to `POST /steps` when a session token and cached health authorization are present.
- **Notification opt-in and device-token registration** - `NotificationService` uses an iOS method channel to request push permission, capture APNs device tokens, register and unregister them with the backend, and route challenge notification taps back into the app.
- **Home dashboard and goal progress** - the Home tab shows today's steps, optional daily-goal progress, pull-to-refresh loading, and setup prompts for missing display names, missing step goals, health access, or notifications.
- **Friends workflow** - users can search by display name with a 2-character minimum and 300 ms debounce, send requests, accept or decline incoming requests, track outgoing requests, and load friends' current-day step totals.
- **Weekly challenges and stakes** - the app loads the current weekly challenge, initiates friend matchups, lets users propose, edit, accept, or counter stakes, and shows live head-to-head progress for active challenge instances.
- **Admin challenge tools** - admin users get a Settings entry for loading weekly challenge state and running ensure, resolve, and reset actions against the backend admin endpoints.
- **Hiking-game UI system** - reusable trail signs, parchment boards, pill buttons, a custom wooden tab bar, overlay toasts, and an animated capybara give the app its hiking-game presentation.

## Platform Support

| Platform | Status | Notes |
|----------|--------|-------|
| iOS | Configured | iOS 14.0 target with HealthKit usage strings, HealthKit entitlement, Apple Sign-In entitlement, APNs entitlement, background processing, and local-network development access. |
| Android | Scaffolded | Flutter host project exists, but there is no Android Health Connect, Apple sign-in, or notification bridge integration in app code yet. |
| macOS | Scaffolded | Host project and CocoaPods setup exist, but there is no macOS health-data or notification integration matching the iOS flow. |
| Web | Scaffolded | Default Flutter web shell exists, but there is no browser health-data integration. |
| Linux | Scaffolded | Default Flutter Linux runner only. |
| Windows | Scaffolded | Default Flutter Windows runner only. |

## Project Structure

```text
assets/
  images/capybara_walk_right.png   # 6-frame walking sprite used across screens

lib/
  main.dart                        # App entry point, Workmanager init, notification init, session gate
  styles.dart                      # Shared color palette and Google Fonts text styles
  config/
    backend_config.dart            # `BACKEND_BASE_URL` compile-time config
  models/
    step_data.dart                 # Immutable daily step-count model
  services/                        # 6 service modules
    auth_service.dart              # Apple auth, session persistence, admin flag persistence
    backend_api_service.dart       # HTTP client for auth, steps, friends, challenges, admin, notifications
    background_sync_manager.dart   # One-off hourly sync scheduling via Workmanager
    background_sync_service.dart   # Background task dispatcher and `/steps` sync callback
    health_service.dart            # HealthKit authorization and same-day step reads
    notification_service.dart      # Permission state, APNs device-token registration, tap routing
  screens/                         # 10 screen files across onboarding, tabs, and challenge flows
    admin_challenge_screen.dart    # Admin-only weekly challenge control panel
    challenge_detail_screen.dart   # Stake negotiation and live challenge progress
    display_name_screen.dart       # Display-name creation and editing flow
    main_shell.dart                # Tab shell and app lifecycle refresh logic
    stake_picker_screen.dart       # Stake catalog selection and counter-proposal flow
    start_screen.dart              # Landing screen and Apple sign-in trigger
    tabs/
      challenges_tab.dart          # Current weekly challenge and instance list
      friends_tab.dart             # Friend search, requests, and challenge actions
      home_tab.dart                # Health/notification onboarding and daily step dashboard
      settings_tab.dart            # Profile edits, notifications, admin tools, sign-out
  widgets/                         # 9 reusable themed widgets/layout primitives
    capybara.dart                  # Animated sprite-sheet capybara
    content_board.dart             # Large parchment content container
    error_toast.dart               # Overlay error banner
    game_background.dart           # Shared sky and island background
    pill_button.dart               # Primary/secondary/accent CTA button component
    pill_icon_button.dart          # Compact icon action button
    tab_layout.dart                # Shared tab content chrome
    trail_sign.dart                # Swaying billboard-style panel
    wooden_tab_bar.dart            # Bottom tab navigation with badges

test/
  admin_challenge_screen_test.dart # Admin tool reset flow widget coverage
  auth_service_test.dart           # Session restore and auth failure helpers
  backend_api_service_test.dart    # Backend connection error messaging
  background_sync_manager_test.dart # Workmanager scheduling behavior
  widget_test.dart                 # Smoke test for app boot

ios/                               # iOS host app, entitlements, background modes, notification bridge
  Runner/AppDelegate.swift         # Registers Workmanager task and notification method channel
  Runner/Info.plist                # HealthKit strings, local networking, background modes
  Runner/Runner.entitlements       # HealthKit, Apple Sign-In, APNs entitlements
  RunnerTests/                     # Default iOS XCTest target
android/                           # Android Flutter host app
macos/                             # macOS Flutter host app
  RunnerTests/                     # Default macOS XCTest target
linux/                             # Linux Flutter host app
windows/                           # Windows Flutter host app
web/                               # Flutter web shell and manifest
pubspec.yaml                       # Dependencies, assets, and app version
analysis_options.yaml              # Flutter lints configuration
```

## API Endpoints

The Flutter app expects the following backend routes to exist at `BACKEND_BASE_URL`.

### Auth and Profile

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/auth/apple` | - | Exchanges Apple credentials for the backend user payload and optional initial profile data. |
| GET | `/auth/session` | Required | Refreshes the app session token and returns current user metadata during bootstrap. |
| GET | `/auth/me` | Required | Fetches the current user, including `stepGoal`, `displayName`, and `incomingFriendRequests`. |
| PUT | `/auth/me/step-goal` | Required | Stores the user's positive daily step goal. |
| PUT | `/auth/me/display-name` | Required | Creates or updates the user's public display name. |

### Steps

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/steps` | Required | Uploads a daily step total with a `YYYY-MM-DD` date after a successful local HealthKit read. |

### Friends

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/friends` | Required | Loads accepted friends plus pending incoming and outgoing requests. |
| GET | `/friends/search?q=...` | Required | Searches users by display name. The UI only sends this request once the query has at least 2 characters. |
| POST | `/friends/request` | Required | Sends a friend request using an `addresseeId`. |
| PUT | `/friends/request/:friendshipId` | Required | Accepts or declines a pending request with `{ "accept": true | false }`. |
| GET | `/friends/steps?date=YYYY-MM-DD` | Required | Returns friends' step totals for the selected date. |

### Challenges

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/challenges/current` | Required | Returns the current weekly challenge plus the signed-in user's challenge instances. |
| POST | `/challenges/initiate` | Required | Starts a challenge instance against a friend using `friendUserId` and an initial `stakeId`. |
| GET | `/challenges/:instanceId/progress` | Required | Returns live step totals for the active challenge detail view. |
| POST | `/challenges/:instanceId/propose-stake` | Required | Sends the initial stake proposal for a challenge instance. |
| PUT | `/challenges/:instanceId/respond-stake` | Required | Accepts a proposal or counters it with `{ "accept": true | false, "counterStakeId"?: string }`. |

### Stakes

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/stakes` | Required | Loads the stake catalog used when initiating or countering challenge stakes. |
| GET | `/stakes?relationship_type=...` | Required | Optionally filters the stake catalog by relationship type before stake selection. |

### Notifications

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/notifications/device-token` | Required | Registers an iOS APNs device token for challenge notifications. |
| DELETE | `/notifications/device-token` | Required | Unregisters the current device token when notifications are disabled or the user signs out. |

### Admin

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/admin/weekly-challenge` | Admin | Loads the current weekly challenge, instance counts, and instance list for admin tools. |
| POST | `/admin/weekly-challenge/ensure-current` | Admin | Ensures the current week's challenge exists. |
| POST | `/admin/weekly-challenge/resolve-current` | Admin | Resolves the current week's challenge. |
| POST | `/admin/weekly-challenge/reset-current` | Admin | Resets the current week's challenge state for testing or recovery. |

## Environment Variables

### Required

No required environment variables are defined in source.

### Optional

| Variable | Default | Description |
|----------|---------|-------------|
| `BACKEND_BASE_URL` | `http://127.0.0.1:3000` | Compile-time API base URL used by `BackendApiService`, background step sync, challenge flows, admin tools, and notification-token registration. |

### Local

```bash
# Make sure your backend listens on 0.0.0.0:3000, not just localhost:3000

  flutter run --dart-define=BACKEND_BASE_URL=http://172.20.10.2:3000      
    
### Production

```bash
flutter build ios --dart-define=BACKEND_BASE_URL=https://steptracker-api.org
```

## Local Persistence

| Key | Owner | Purpose |
|-----|-------|---------|
| `auth_identity_token` | `AuthService` | Caches the Apple identity token and acts as a fallback auth token before session refresh. |
| `auth_user_identifier` | `AuthService` | Stores the Apple user identifier returned during sign-in. |
| `auth_backend_user_id` | `AuthService` | Caches the backend user id returned by `/auth/apple`. |
| `auth_step_goal` | `AuthService` | Persists the latest selected step goal. |
| `auth_display_name` | `AuthService` | Persists the latest saved display name. |
| `auth_session_token` | `AuthService` | Stores the refreshed backend session token returned by `/auth/apple` and `/auth/session`. |
| `auth_is_admin` | `AuthService` | Caches whether the signed-in user should see admin challenge controls. |
| `health_authorized` | `HealthService` | Remembers that the user has already gone through the Health authorization flow. |
| `notif_device_token` | `NotificationService` | Persists the last APNs device token received from the native iOS bridge. |
| `notif_permission_granted` | `NotificationService` | Caches whether notifications were granted or denied so the app can avoid re-prompting automatically. |

On iOS, the app treats `health_authorized` as a cached best-effort flag because the Health API does not expose read-permission status after the prompt. Notification permission state is also cached locally so already-denied users are not nagged every launch.

## Runtime Rules

- **Session restore requirement** - `AuthService.restoreSession()` only restores an active session when the Apple identity token, Apple user identifier, and backend session token are all present.
- **Bootstrap refresh** - the main shell calls `GET /auth/session` on load; a `401` signs the user out and sends them back to the start screen.
- **Health access scope** - only read access for `HealthDataType.STEPS` is requested.
- **Step window** - today's steps are computed from local midnight through the current time.
- **Background sync cadence** - the app schedules a connected-network one-off sync every hour and re-queues the next sync from the background callback because the installed iOS Workmanager flow is not true periodic scheduling.
- **Background sync guardrails** - background step uploads only run when `auth_session_token` and `health_authorized` exist; `401` responses stop retries, while connectivity or server failures can retry later.
- **Backend timeout** - HTTP requests use a 15-second timeout in `BackendApiService`.
- **Notification prompt policy** - users are prompted for notifications after health onboarding; granted users are silently re-registered later, while denied users are not auto-prompted again.
- **Friend search threshold** - queries shorter than 2 characters do not hit the backend.
- **Friend search debounce** - the search box waits 300 ms after typing stops before sending a request.
- **Display-name validation** - the client rejects empty display names before calling the backend.
- **Step-goal validation** - step goals are only accepted when they parse to an integer greater than zero.
- **Challenge notification routing** - the native notification bridge currently routes `CHALLENGE_INITIATED` taps into the challenge-detail flow.
- **Resume refresh** - when the app returns to the foreground after health access was granted, it refreshes steps, profile data, friends' progress, and the current challenge.

## Dependencies

### Production

| Package | Purpose |
|---------|---------|
| `flutter` | UI runtime and cross-platform app framework. |
| `cupertino_icons` | iOS-style icon set. |
| `health` | HealthKit authorization and step-count reads. |
| `sign_in_with_apple` | Native Apple ID authentication flow. |
| `shared_preferences` | Local storage for session, display-name, step-goal, and health-auth state. |
| `google_fonts` | Loads the Russo One and Chakra Petch fonts used by the UI system. |
| `workmanager` | Schedules the app's hourly background step-sync task. |
| `flutter_local_notifications` | Declared notification-support dependency; the current permission and APNs token bridge is implemented natively in `ios/Runner/AppDelegate.swift`. |

### Development

| Package | Purpose |
|---------|---------|
| `flutter_test` | Widget testing framework. |
| `flutter_lints` | Static analysis and lint rules via `analysis_options.yaml`. |

## Testing

```bash
flutter test
```

Current automated coverage includes 12 Dart tests across auth/session behavior, backend error messaging, background sync scheduling, admin challenge tooling, and app boot. The repository also still contains 2 placeholder native XCTest files in the iOS and macOS host projects. `flutter test` passed during this documentation refresh.

### Test Coverage

#### Auth service unit tests - 5 tests (`test/auth_service_test.dart`)

| Group | Tests | What's covered |
|-------|-------|----------------|
| `top-level` | 5 | Restore fails without session token, restore succeeds with session token, admin flag persistence, 401 auth-failure detection, non-401 auth-failure rejection. |

#### Backend transport unit tests - 3 tests (`test/backend_api_service_test.dart`)

| Group | Tests | What's covered |
|-------|-------|----------------|
| `describeBackendConnectionError` | 3 | Clear messages for LAN socket failures, iOS App Transport Security HTTP failures, and request timeouts. |

#### Background sync manager tests - 2 tests (`test/background_sync_manager_test.dart`)

| Group | Tests | What's covered |
|-------|-------|----------------|
| `top-level` | 2 | Successful Workmanager one-off scheduling with expected arguments, and graceful failure when native scheduling throws. |

#### Admin challenge tools widget test - 1 test (`test/admin_challenge_screen_test.dart`)

| Group | Tests | What's covered |
|-------|-------|----------------|
| `top-level` | 1 | Loading admin challenge state, showing the reset action, and reloading state after resetting the current week. |

#### Widget smoke test - 1 test (`test/widget_test.dart`)

| Group | Tests | What's covered |
|-------|-------|----------------|
| `top-level` | 1 | `StepTrackerApp` pumps successfully and builds the root `MaterialApp`. |

#### iOS host XCTest placeholder - 1 test (`ios/RunnerTests/RunnerTests.swift`)

| Group | Tests | What's covered |
|-------|-------|----------------|
| `RunnerTests` | 1 | Default `testExample()` placeholder generated by the Flutter iOS scaffold. |

#### macOS host XCTest placeholder - 1 test (`macos/RunnerTests/RunnerTests.swift`)

| Group | Tests | What's covered |
|-------|-------|----------------|
| `RunnerTests` | 1 | Default `testExample()` placeholder generated by the Flutter macOS scaffold. |

### Test Directory Structure

```text
test/
  admin_challenge_screen_test.dart  # Loads admin tools and verifies reset-current flow (1 test)
  auth_service_test.dart            # Session restore and admin/auth helper coverage (5 tests)
  backend_api_service_test.dart    # Verifies backend transport failures map to actionable user-facing messages
  background_sync_manager_test.dart # Verifies Workmanager task scheduling behavior (2 tests)
  widget_test.dart                 # Boots `StepTrackerApp` and verifies the root app widget builds
ios/
  RunnerTests/
    RunnerTests.swift              # Default iOS XCTest placeholder
macos/
  RunnerTests/
    RunnerTests.swift              # Default macOS XCTest placeholder
```

## Getting Started

1. Make sure Flutter is installed (`flutter doctor` to verify)
2. Clone this repo and run `flutter pub get`
3. Open `ios/Runner.xcworkspace` in Xcode and enable the **HealthKit** capability
4. Run the app with `flutter run`

## iOS Setup Notes

The iOS host project is the only platform configured for live step tracking, background step sync scheduling, and push-permission handling today.

- **Deployment target**: `platform :ios, '14.0'` in `ios/Podfile`
- **Info.plist usage strings**: `NSHealthShareUsageDescription` and `NSHealthUpdateUsageDescription` are present in `ios/Runner/Info.plist`
- **Entitlements**: `com.apple.developer.healthkit`, `com.apple.developer.applesignin`, and `aps-environment` are enabled in `ios/Runner/Runner.entitlements`
- **Background modes**: `UIBackgroundModes` includes `processing` and `remote-notification`, and `BGTaskSchedulerPermittedIdentifiers` includes `$(PRODUCT_BUNDLE_IDENTIFIER).periodicStepSync`
- **Notification bridge**: `ios/Runner/AppDelegate.swift` registers the Workmanager identifier, requests notification permission, forwards APNs device tokens, and forwards notification taps over `com.steptracker/notifications`
- **Local backend access**: `NSAllowsLocalNetworking` is enabled in `ios/Runner/Info.plist` so development builds can call a LAN HTTP backend from a physical iPhone
- **CocoaPods setup**: `use_frameworks!` is enabled in `ios/Podfile`
- **Orientation support**: portrait and landscape on iPhone, plus portrait upside-down on iPad, are declared in `ios/Runner/Info.plist`

## Roadmap

- [x] Apple Sign-In session restore and backend user provisioning
- [x] HealthKit authorization plus same-day step reads
- [x] Backend sync for steps, display names, step goals, challenge state, and friends data
- [x] Friends search, requests, acceptance flow, and daily progress preview
- [x] Weekly challenge initiation, stake negotiation, and active challenge progress views
- [x] Admin weekly challenge tools
- [x] Notification permission flow and device-token registration for challenge alerts
- [x] Custom hiking-game UI system with reusable widgets and animated capybara art
- [ ] Historical step views and real stats screens
- [ ] Challenge history and past-week results
- [ ] Android Health Connect support
- [ ] Cross-platform notification and health integrations beyond iOS
- [ ] Broader automated coverage for services, networking, and platform behavior
