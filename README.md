# Step Tracker

Step Tracker is a Flutter app that signs users in with Apple, reads the current day's step count from Apple HealthKit, syncs that data to a backend API, and adds lightweight social features such as display names, daily step goals, friend requests, and friends' daily progress. The UI is a custom hiking-game themed interface built from reusable Flutter widgets, Google Fonts typography, and a sprite-based animated capybara.

## Tech Stack

| Layer | Technology |
|-------|------------|
| Language | Dart 3.10.1 |
| App framework | Flutter |
| Health data | `health` 13.3.1 |
| Authentication | `sign_in_with_apple` 7.0.1 |
| Local persistence | `shared_preferences` 2.5.4 |
| Typography | `google_fonts` 6.2.1 |
| Testing | `flutter_test` |
| Linting | `flutter_lints` 6.0.0 |
| Native shells | iOS, Android, macOS, Linux, Windows, web |

## Features

- **Session gate** - `main.dart` restores cached auth state and routes users to the start, display-name, or home flow without redoing onboarding every launch.
- **Apple sign-in and backend provisioning** - `AuthService` requests Apple credentials, validates the identity token and user identifier, then provisions the backend user through `POST /auth/apple`.
- **HealthKit step tracking** - `HealthService` requests read access for `HealthDataType.STEPS` only and reads total steps from local midnight to the current time.
- **Daily sync to backend** - `HomeScreen` uploads successful step reads to `POST /steps`, but keeps the local result visible even if network sync fails.
- **Profile settings** - users can set and update a display name plus a positive integer step goal, with local persistence and backend sync.
- **Friends workflow** - the app supports searching by display name, sending requests, accepting or declining incoming requests, viewing outgoing pending requests, and loading friends' daily step totals.
- **Game-themed UI kit** - reusable trail signs, parchment boards, gold buttons, toast overlays, and an animated capybara create the app's hiking-game presentation.
- **Challenge entry point** - the home screen already exposes a `START A CHALLENGE` CTA, but its handler is still marked `TODO`.

## Platform Support

| Platform | Status | Notes |
|----------|--------|-------|
| iOS | Configured | iOS 14.0 target with HealthKit usage strings, HealthKit entitlement, and Apple Sign-In entitlement. |
| Android | Scaffolded | Flutter host project exists, but there is no Android health or sign-in integration in app code yet. |
| macOS | Scaffolded | Host project and CocoaPods setup exist, but the step data flow is built around HealthKit on iOS. |
| Web | Scaffolded | Default Flutter web shell exists, but there is no browser health-data integration. |
| Linux | Scaffolded | Default Flutter Linux runner only. |
| Windows | Scaffolded | Default Flutter Windows runner only. |

## Project Structure

```text
assets/
  images/capybara_walk_right.png   # 6-frame walking sprite used across screens

lib/
  main.dart                        # App entry point and session gate
  styles.dart                      # Shared color palette and Google Fonts text styles
  config/
    backend_config.dart            # `BACKEND_BASE_URL` compile-time config
  models/
    step_data.dart                 # Immutable daily step-count model
  screens/                         # 5 app screens
    start_screen.dart              # Landing screen and Apple sign-in trigger
    display_name_screen.dart       # Display-name creation and editing flow
    home_screen.dart               # Step dashboard, health permission flow, friends preview
    settings_screen.dart           # Account settings and step-goal editor
    friends_screen.dart            # Friend search and request management
  services/                        # 3 service classes
    auth_service.dart              # Apple auth plus persisted session state
    health_service.dart            # HealthKit authorization and daily steps
    backend_api_service.dart       # HTTP client for auth, profile, steps, and friends APIs
  widgets/                         # 8 reusable themed widgets
    capybara.dart                  # Animated sprite-sheet capybara
    content_board.dart             # Large parchment content container
    error_toast.dart               # Overlay error banner
    game_background.dart           # Shared sky and island background
    game_button.dart               # Large CTA button
    game_icon_button.dart          # Icon-sized action button
    step_count_card.dart           # Step summary card with refresh/settings controls
    trail_sign.dart                # Swaying billboard-style panel

test/
  widget_test.dart                 # Smoke test for app boot

ios/                               # iOS host app, entitlements, HealthKit and Apple Sign-In config
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

## Environment Variables

### Required

No required environment variables are defined in source.

### Optional

| Variable | Default | Description |
|----------|---------|-------------|
| `BACKEND_BASE_URL` | `http://127.0.0.1:3000` | Compile-time API base URL used by `BackendApiService` for all auth, steps, and friends requests. |

### Local

```bash
# Make sure your backend listens on 0.0.0.0:3000, not just localhost:3000
# Your iPhone and Mac must be on the same Wi-Fi network
flutter run --dart-define=BACKEND_BASE_URL=http://<YOUR_LAN_IP>:3000
flutter run --dart-define=BACKEND_BASE_URL=http://192.168.1.188:3000
flutter run --profile --dart-define=BACKEND_BASE_URL=http://192.168.1.188:3000                                                      

```

### Production

```bash
flutter build ios --dart-define=BACKEND_BASE_URL=https://steptracker-api.org
```

## Local Persistence

| Key | Owner | Purpose |
|-----|-------|---------|
| `auth_identity_token` | `AuthService` | Restores the backend bearer token between launches. |
| `auth_user_identifier` | `AuthService` | Stores the Apple user identifier returned during sign-in. |
| `auth_backend_user_id` | `AuthService` | Caches the backend user id returned by `/auth/apple`. |
| `auth_step_goal` | `AuthService` | Persists the latest selected step goal. |
| `auth_display_name` | `AuthService` | Persists the latest saved display name. |
| `health_authorized` | `HealthService` | Remembers that the user has already gone through the Health authorization flow. |

On iOS, the app treats `health_authorized` as a cached best-effort flag because the Health API does not expose read-permission status after the prompt.

## Runtime Rules

- **Health access scope** - only read access for `HealthDataType.STEPS` is requested.
- **Step window** - today's steps are computed from local midnight through the current time.
- **Friend search threshold** - queries shorter than 2 characters do not hit the backend.
- **Friend search debounce** - the search box waits 300 ms after typing stops before sending a request.
- **Display-name validation** - the client rejects empty display names before calling the backend.
- **Step-goal validation** - step goals are only accepted when they parse to an integer greater than zero.
- **Resume refresh** - when the app returns to the foreground after health access was granted, it refreshes steps, profile data, and friends' progress.
- **Zero-step hint** - a successful `0` read shows a hint directing the user to Health data-access settings.

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

### Development

| Package | Purpose |
|---------|---------|
| `flutter_test` | Widget testing framework. |
| `flutter_lints` | Static analysis and lint rules via `analysis_options.yaml`. |

## Testing

```bash
flutter test
```

Current automated coverage is still light, but now includes a small Dart unit test file for backend transport-error messaging alongside the widget smoke test and the 2 scaffold XCTest placeholders in the native Apple host projects. There are still no backend-contract or platform integration tests in this repository.

### Test Coverage

#### Backend transport unit tests - 3 tests (`test/backend_api_service_test.dart`)

| Group | Tests | What's covered |
|-------|-------|----------------|
| `describeBackendConnectionError` | 3 | Clear messages for LAN socket failures, iOS App Transport Security HTTP failures, and request timeouts. |

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
  backend_api_service_test.dart    # Verifies backend transport failures map to actionable user-facing messages
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

The iOS host project is the only platform configured for live step tracking today.

- **Deployment target**: `platform :ios, '14.0'` in `ios/Podfile`
- **Info.plist usage strings**: `NSHealthShareUsageDescription` and `NSHealthUpdateUsageDescription` are present in `ios/Runner/Info.plist`
- **Entitlements**: `com.apple.developer.healthkit` and `com.apple.developer.applesignin` are enabled in `ios/Runner/Runner.entitlements`
- **Local backend access**: `NSAllowsLocalNetworking` is enabled in `ios/Runner/Info.plist` so development builds can call a LAN HTTP backend from a physical iPhone
- **CocoaPods setup**: `use_frameworks!` is enabled in `ios/Podfile`
- **Orientation support**: portrait and landscape on iPhone, plus portrait upside-down on iPad, are declared in `ios/Runner/Info.plist`

## Roadmap

- [x] Apple Sign-In session restore and backend user provisioning
- [x] HealthKit authorization plus same-day step reads
- [x] Backend sync for steps, display names, step goals, and friends data
- [x] Friends search, requests, acceptance flow, and daily progress preview
- [x] Custom hiking-game UI system with reusable widgets and animated capybara art
- [ ] `START A CHALLENGE` flow implementation
- [ ] Step history views beyond "today"
- [ ] Android Health Connect support
- [ ] Broader automated coverage for services, networking, and platform behavior
