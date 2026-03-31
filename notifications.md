# Push Notifications - Complete Inventory

## Architecture Overview

- **iOS only** (Android scaffolded, not implemented)
- **Native APNs** via Flutter MethodChannel bridge (no FCM/Firebase/third-party)
- **Event-driven** backend: commands emit events -> notification handlers send pushes
- **Silent push** support for background step sync

---

## Backend

### Core Services

| File | Purpose |
|------|---------|
| `src/services/apns.js` | APNs HTTP/2 client - JWT auth, alert + silent push, sandbox/prod fallback |
| `src/services/stepSyncPush.js` | Silent push to request step sync (1-hour cooldown per user) |

### Event -> Notification Mapping

| Event | Recipient | Title | Deep Link Route |
|-------|-----------|-------|-----------------|
| CHALLENGE_INITIATED | challenged friend | "New Challenge" | challenge_detail |
| FRIEND_REQUEST_SENT | request recipient | "New Friend Request" | friends |
| FRIEND_REQUEST_ACCEPTED | request sender | "Friend Request Accepted" | friends |
| STAKE_ACCEPTED | stake proposer | "Challenge Accepted" | challenge_detail |
| RACE_INVITE_SENT | invitee | "Race Invite" | race_detail |
| RACE_INVITE_ACCEPTED | race creator | "Race Update" | race_detail |
| RACE_STARTED | participants (except creator) | "Race Started" | race_detail |
| RACE_COMPLETED | all participants | "Race Finished" | race_detail |
| RACE_CANCELLED | all participants | "Race Cancelled" | races |
| POWERUP_USED | target player | Attack-specific message | race_detail |
| POWERUP_BLOCKED | attacker & defender | "Powerup Blocked!" / "Shield Activated!" | race_detail |
| CHALLENGE_DROPPED | ALL users (broadcast) | "New Competition" | challenges |

**Handler file:** `src/handlers/notificationHandlers.js`

### Powerup Attack Messages

| Powerup | Message |
|---------|---------|
| LEG_CRAMP | "{name} used Leg Cramp on you! Your steps are frozen for 2 hours." |
| RED_CARD | "{name} used Red Card! You lost steps." |
| SHORTCUT | "{name} stole steps from you with Shortcut!" |
| WRONG_TURN | "{name} sent you on a Wrong Turn! Your steps are reversed for 1 hour." |

### Event Emission Sources

| Event | Emitted From |
|-------|-------------|
| CHALLENGE_INITIATED | `src/commands/initiateChallenge.js` |
| FRIEND_REQUEST_SENT | `src/commands/sendFriendRequest.js` |
| FRIEND_REQUEST_ACCEPTED | `src/handlers/eventHandlers.js` |
| STAKE_ACCEPTED | `src/commands/respondToStake.js` |
| RACE_INVITE_SENT | `src/commands/inviteToRace.js` |
| RACE_INVITE_ACCEPTED | `src/commands/respondToRaceInvite.js` |
| POWERUP_USED | `src/commands/usePowerup.js` |
| POWERUP_BLOCKED | `src/commands/usePowerup.js` |
| CHALLENGE_DROPPED | `src/jobs/weeklyChallenge.js` (scheduled) |

### API Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/notifications/device-token` | Register device token (body: `{ deviceToken, platform }`) |
| DELETE | `/notifications/device-token` | Unregister device token (body: `{ deviceToken }`) |

**Route file:** `src/routes/notifications.js`

### Database

**DeviceToken table** (`prisma/schema.prisma`):
- `id`, `userId`, `token`, `platform`, `createdAt`, `updatedAt`
- Unique constraint on `[userId, token]`

**User fields for silent push:**
- `lastStepSyncAt` - when user last synced steps
- `lastSilentPushSentAt` - cooldown tracking for silent push

### Step Sync Push Flow

1. Friend requests step data via `GET /friends/steps` for today
2. Backend sends silent push (`STEP_SYNC_REQUEST`) to all friends
3. Cooldown: skips if user synced or was pushed within last hour
4. iOS only (filters by platform)

**Integration:** `src/routes/friends.js` lines 77-82

### Environment Variables

```
APNS_KEY_PATH or APNS_SIGNING_KEY  # .p8 signing key
APNS_KEY_ID                         # Key ID from Apple
APNS_TEAM_ID                        # Team ID from Apple
APNS_BUNDLE_ID                      # App bundle identifier
APNS_PRODUCTION                     # true = production, false = sandbox
```

### Tests

| File | Coverage |
|------|----------|
| `test/services/apns.test.js` | 11 tests - payload construction, success/error handling, sandbox fallback |
| `test/services/stepSyncPush.test.js` | 4 tests - cooldown logic, stale token cleanup |
| `test/handlers/notificationHandlers.test.js` | 18+ tests - all event types, multi-token, 410 cleanup |
| `test/http/notifications.test.js` | 9 tests - register/unregister endpoints, validation |

---

## Frontend (Flutter/iOS)

### Core Files

| File | Purpose |
|------|---------|
| `lib/services/notification_service.dart` | Permission management, token registration, tap routing |
| `ios/Runner/AppDelegate.swift` | Native APNs bridge, token handling, foreground display, background sync |

### Notification Service (`notification_service.dart`)

- **MethodChannel:** `com.steptracker/notifications`
- **Permission flow:** `requestPermission()` -> native iOS prompt -> stores result in SharedPreferences
- **Token flow:** Native `onDeviceToken` callback -> stores locally -> POST to backend
- **Tap routing:** Native `onNotificationTap` callback -> parses payload -> sets `pendingAction` ValueNotifier

### Tap -> Route Mapping

| Notification Type | Route |
|-------------------|-------|
| CHALLENGE_INITIATED | challengeDetail |
| RACE_INVITE_SENT | raceDetail |
| RACE_INVITE_ACCEPTED | raceDetail |
| RACE_STARTED | raceDetail |
| RACE_COMPLETED | raceDetail |
| RACE_CANCELLED | races |

### iOS Native Bridge (`AppDelegate.swift`)

- Requests `.alert`, `.badge`, `.sound` permissions
- Converts APNs token to hex string, sends to Flutter via method channel
- Shows banners for foreground notifications
- Handles `STEP_SYNC_REQUEST` for background step sync
- Background modes: `fetch`, `remote-notification`
- Entitlement: `aps-environment: development`

### UI Integration

| Screen | What it does |
|--------|-------------|
| `lib/main.dart` | Initializes NotificationService at startup |
| `lib/screens/main_shell.dart` | Checks permission state, silently re-registers granted users, shows onboarding for new users |
| `lib/screens/tabs/home_tab.dart` | Shows notification prompt banner when never prompted |
| `lib/screens/tabs/profile_tab.dart` | Notification toggle in settings (enable/disable) |
| `lib/screens/display_name_screen.dart` | Passes through NotificationService |
| `lib/screens/start_screen.dart` | Passes through NotificationService |
| `lib/screens/step_goal_onboarding_screen.dart` | Passes through NotificationService |

### Backend API Integration (`backend_api_service.dart`)

- `registerDeviceToken()` (line 504) - POST `/notifications/device-token`
- `unregisterDeviceToken()` (line 716) - DELETE `/notifications/device-token`

### Local Storage Keys

| Key | Purpose |
|-----|---------|
| `notif_device_token` | Cached APNs device token |
| `notif_permission_granted` | Permission state (null = never asked, true/false) |

### Permission Flow

1. After health onboarding, user sees notification prompt
2. If granted: registers for APNs, stores token, sends to backend
3. If denied: stores false, never re-prompts
4. On subsequent launches: granted users silently re-register, denied users skipped

---

## Not Implemented

- **Android push** (FCM) - tokens stored but no native bridge
- **macOS/Web/Linux/Windows** - no notification support
- **flutter_local_notifications** - declared in pubspec.yaml but not actively used (native bridge used instead)
