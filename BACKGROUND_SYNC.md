# Background Step Sync — Implementation Plan

This document covers the architecture and implementation details for reliably syncing step data when the app is backgrounded on iOS.

## The Problem

iOS does not allow apps to run arbitrary background code on a fixed schedule. The OS decides *if* and *when* your app gets background execution time based on:

- **App usage frequency** — frequently opened apps get more background time
- **Battery level** — below ~20%, background execution is paused entirely
- **Device state** — charging + Wi-Fi + idle (overnight) = most opportunities
- **Past task performance** — tasks that complete quickly and reliably get scheduled more often

This means the current `workmanager` one-off task approach is unreliable on iOS — `initialDelay` is not honored, and execution timing is entirely OS-controlled.

## iOS Background Task Types

| | **BGAppRefreshTask** | **BGProcessingTask** | **BGContinuedProcessingTask** (iOS 26+) |
|---|---|---|---|
| **Time budget** | ~30 seconds | Several minutes | Finishes foreground work |
| **Scheduling** | OS-decided, based on usage patterns | Often overnight while charging | Immediately after backgrounding |
| **Best for** | Quick API syncs, content refresh | ML training, DB maintenance | Completing in-flight uploads |
| **Capability flag** | `Background fetch` | `Background processing` | New in iOS 26 |

Key constraints:
- Force-quitting the app prevents all background task delivery
- You *request* execution — Apple *might* grant it
- The time budget is **per launch, not per task**

## Multi-Layer Sync Strategy

No single mechanism is reliable enough on its own. The app should layer multiple strategies so foreground sync is the guaranteed baseline and background mechanisms improve freshness opportunistically.

```
User opens app
  └─> Layer 1: Foreground sync (immediate, guaranteed)
  └─> Layer 1: 5-minute foreground poll timer while app is active

User backgrounds app
  └─> Layer 2: Silent push notifications (server-triggered, ~30s window)
  └─> Layer 3: HealthKit background delivery (event-driven, ~30s window)
  └─> Layer 4: background_fetch / BGAppRefreshTask (OS-scheduled fallback)
  └─> Layer 5: workmanager one-off task (least reliable on iOS, last resort)

User opens app again
  └─> Layer 1: Foreground sync catches anything missed
```

---

## Layer 1 — Foreground Sync (implemented)

The most reliable layer. Steps are fetched from HealthKit and synced to the backend:

- Immediately on app launch after health authorization is confirmed
- On every app resume (`didChangeAppLifecycleState.resumed`)
- Every 5 minutes via a `Timer.periodic` while the app is in the foreground
- The timer is cancelled when the app is paused and restarted on resume

**Files:** `lib/screens/main_shell.dart`

---

## Layer 2 — Silent Push Notifications (proposed)

Server-initiated background wakeups that give the app ~30 seconds of execution time. Unlike OS-scheduled tasks, the **server controls the timing**.

### Trigger: Demand-Driven Sync via Friends List

When User A opens their friends tab and requests `GET /friends/steps`, the server checks which friends have stale step data. For any friend whose last sync exceeds the staleness threshold, the server sends a silent push to that friend's device to trigger a fresh HealthKit read and backend sync.

```
User A opens Friends tab
  └─> GET /friends/steps
       └─> Server returns cached step data immediately (never blocks on push)
       └─> For each friend with stale data and no recent push:
            └─> Server sends silent push to friend's device
            └─> Friend's app wakes (~30s), reads HealthKit, POSTs to /steps
            └─> Next time anyone views that friend's steps, data is fresh
```

### Silent Push Payload

Completely invisible to the receiving user — no alert, no badge, no sound:

```json
{"aps": {"content-available": 1}}
```

Silent pushes work even if the user denied visible notification permissions. They will **not** be delivered if the user force-quit the app or the device is in Low Power Mode.

### Rate Limiting and Cache Rules

Apple will throttle or drop silent pushes if you send too many. The server must enforce per-user cooldowns.

| Rule | Value | Rationale |
|------|-------|-----------|
| Staleness threshold | 30 minutes | Only push if the friend's last step sync is older than this |
| Per-user push cooldown | 15 minutes | Don't send another silent push to the same device within this window |
| Apple's unofficial safe rate | ~3–4 pushes/hour | Exceeding this risks throttling or silent drops |

### Server-Side Pseudocode

```
On GET /friends/steps:
  for each friend:
    if friend.last_step_sync > 30 minutes ago:
      if friend.last_silent_push_sent > 15 minutes ago:
        send silent push to friend's device token
        update friend.last_silent_push_sent = now
    return cached step data immediately
```

The response is **never blocked** by push delivery. This is a fire-and-forget pre-warming mechanism — User A sees cached data now, and the data will be fresh for the next viewer.

### Timing Expectation

This is **pre-warming for the next look**, not real-time synchronization. User A sees cached (possibly stale) data on the first request. The silent push triggers User B's device to sync in the background. The next time anyone views User B's steps, the data is fresh. This matches how fitness apps like Fitbit and Apple Fitness handle friend step data.

### Server-Side Requirements

| Requirement | Details |
|-------------|---------|
| Device token storage | Already implemented via `POST /notifications/device-token` |
| New column: `last_silent_push_sent_at` | Timestamp per user, used for cooldown enforcement |
| Staleness check | Use existing `last_step_sync_at` from `/steps` POST timestamps |
| Push logic in friends endpoint | Add to `GET /friends/steps` handler |
| APNs integration | Send silent pushes via APNs HTTP/2 API or a library like `apn` / `firebase-admin` |

### iOS Client Requirements

| Requirement | Details |
|-------------|---------|
| Handle silent push | Implement `application:didReceiveRemoteNotification:fetchCompletionHandler:` in `AppDelegate.swift` |
| Sync within time budget | Read HealthKit steps and POST to `/steps` within ~30 seconds |
| Completion handler | Call with `.newData`, `.noData`, or `.failed` so iOS can track task reliability |
| Background mode | `remote-notification` in `UIBackgroundModes` — **already configured** |

### Edge Cases

- **Popular users** (many friends viewing them) naturally stay fresh — the cooldown deduplicates pushes so only one fires per window regardless of how many friends look
- **Force-quit apps** won't receive silent pushes — foreground sync catches up when the user next opens the app
- **Low Power Mode** — iOS may defer or drop silent pushes entirely; other layers compensate
- **Invalid device tokens** — clean stale tokens from the push registry on APNs delivery failure (HTTP 410 response)
- **User uninstalled the app** — same as invalid token; APNs returns 410

---

## Layer 3 — HealthKit Background Delivery (proposed)

HealthKit can notify the app when new step data is written to the Health store — for example, after the user finishes a walk or when a paired Apple Watch syncs. This is **event-driven**: the app syncs when there is actually new data, not on an arbitrary timer.

### How It Works

1. Register an `HKObserverQuery` for `HKQuantityType.stepCount` during app launch
2. Enable **HealthKit Background Delivery** in Xcode capabilities
3. When new step data arrives, iOS wakes the app with ~30 seconds of execution time
4. The app reads the updated step count and POSTs to `/steps`

### Implementation Notes

- The Flutter `health` plugin does **not** expose `HKObserverQuery` or background delivery
- Requires either:
  - A small native iOS module (Swift) that registers the observer and calls back into Dart
  - The `background_fetch` plugin, which can hook into HealthKit observer callbacks
- The observer registration must happen early in `AppDelegate` to survive app restarts

### Advantages

- Fires only when there's new data — no wasted syncs
- Works well alongside silent push — covers the case where the user is walking but no friend has viewed their steps yet

---

## Layer 4 — `background_fetch` Plugin (proposed)

Maps directly to iOS `BGAppRefreshTask`. More reliable than `workmanager` for periodic iOS background tasks because it's designed specifically for the iOS background fetch API.

### How It Works

1. Add the `background_fetch` package to `pubspec.yaml`
2. Configure with a desired interval (iOS treats this as a **minimum**, not exact)
3. The OS schedules execution based on app usage patterns — typically 15 minutes to several hours
4. The callback reads HealthKit steps and POSTs to `/steps`

### Key Differences from Workmanager

| | `workmanager` | `background_fetch` |
|---|---|---|
| iOS task type | One-off (reschedules itself) | Native `BGAppRefreshTask` |
| `initialDelay` on iOS | Not honored | N/A (OS-scheduled) |
| Scheduling reliability | Lower | Higher for periodic tasks |
| Setup complexity | Already integrated | New dependency |

### Role in the Stack

This is a **passive fallback**. It keeps data reasonably fresh between app opens without requiring server involvement. It should not be relied on as the primary background sync mechanism.

---

## Layer 5 — Workmanager One-Off Tasks (implemented)

The current approach: a one-off task that reschedules itself after each execution via `ExistingWorkPolicy.replace`. This is the least reliable layer on iOS because `initialDelay` is not honored and iOS may defer or skip execution entirely. It remains as a last-resort fallback.

**Files:** `lib/services/background_sync_manager.dart`, `lib/services/background_sync_service.dart`

---

## Implementation Priority

Recommended order based on impact and effort:

| Priority | Layer | Impact | Effort | Notes |
|----------|-------|--------|--------|-------|
| 1 | Silent push notifications | High | Medium | Leverages existing APNs infra and device token registration |
| 2 | HealthKit background delivery | High | Medium | Ideal for step trackers — fires on actual data changes |
| 3 | `background_fetch` plugin | Medium | Low | Drop-in passive fallback |
| 4 | `BGContinuedProcessingTask` | Low | Low | Future consideration once iOS 26 adoption is widespread |

## References

- [BGAppRefreshTask — Apple Developer Documentation](https://developer.apple.com/documentation/backgroundtasks/bgapprefreshtask)
- [BGProcessingTask — Apple Developer Documentation](https://developer.apple.com/documentation/backgroundtasks/bgprocessingtask)
- [iOS 26 BGContinuedProcessingTask — WWDC 2025](https://developer.apple.com/videos/play/wwdc2025/227/)
- [workmanager — Flutter plugin](https://pub.dev/packages/workmanager)
- [background_fetch — Flutter plugin](https://pub.dev/packages/background_fetch)
- [Workmanager iOS one-off task issues](https://github.com/fluttercommunity/flutter_workmanager/issues/524)
