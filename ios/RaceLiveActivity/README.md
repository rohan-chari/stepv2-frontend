# Phase 4 — iOS Live Activities (SCAFFOLD, not yet wired)

Lock-screen / Dynamic Island live race placement, updated by server APNs pushes so
it stays current with the app closed. **Optional / deferred** (see `URGENT-TODO.md`
P3 #6). These files are inert until added to an Xcode target — they do **not** affect
the current build.

## Files here
- `RaceActivityAttributes.swift` — shared `ActivityAttributes` (static race info +
  live `ContentState`). Must be in **both** the Runner app target and the widget
  extension target.
- `RaceLiveActivityWidget.swift` — the Lock Screen + Dynamic Island UI. Widget
  extension target only.

## Xcode steps to wire it (cannot be done by editing text files)
1. **Add a Widget Extension target**: Xcode → File → New → Target → *Widget Extension*
   (name e.g. `RaceLiveActivity`, "Include Live Activity" checked, embed in Runner).
   Keep the bundle id `com.rohanchari.steptracker.RaceLiveActivity`.
2. **Add these two files** to the project; set Target Membership:
   - `RaceActivityAttributes.swift` → Runner **and** RaceLiveActivity.
   - `RaceLiveActivityWidget.swift` → RaceLiveActivity only.
3. **Info.plist (Runner)**: add `NSSupportsLiveActivities = YES` (and
   `NSSupportsLiveActivitiesFrequentUpdates = YES` only if you need >~hourly priority-10
   updates).
4. **Min iOS**: ActivityKit 16.1+; push-to-start 17.2+. Gate all usage on availability.

## App-side wiring (Runner target — to write)
- A `LiveActivityManager` that, when the user opens an ACTIVE race, calls
  `Activity.request(...)` with `RaceActivityAttributes` and the initial `ContentState`,
  then reads `activity.pushToken` updates and `POST`s the hex token to the backend
  (new `DeviceToken`-style table or a `liveActivityPushToken` column keyed by race+user).
- End the activity on race finish / when the user leaves.

## Backend wiring (to write — keep OFF until tested)
Reuse the existing HTTP/2 APNs client (`src/services/apns.js`). A Live Activity update is
an APNs push with:
- header `apns-push-type: liveactivity`
- header `apns-topic: com.rohanchari.steptracker.push-type.liveactivity`
- header `apns-priority: 5` for routine updates (10 only for dramatic swings; it draws
  down an hourly budget)
- payload:
  ```json
  {
    "aps": {
      "timestamp": 1700000000,
      "event": "update",
      "content-state": { "placement": 2, "totalParticipants": 6, "mySteps": 8231, "leaderSteps": 9004, "endsAt": 1700050000 },
      "alert": { "title": "You've been passed", "body": "Now 2nd" }
    }
  }
  ```
Drive these from the **same** placement-change detection as Phase 0
(`placementRecompute` → `PLACEMENT_CHANGED`): when a participant with an active Live
Activity changes rank, send an `event:"update"`; send `event:"end"` at race finish.

## Constraints (set expectations)
- ~8h active window (~12h with stale state) → multi-day races need restart (push-to-start, 17.2+).
- iOS only — Android has no equivalent (it gets the Phase 3 notification/refresh path).
- If the widget extension needs the auth token (e.g., to fetch), that's when the
  deferred Keychain/App-Group token migration becomes necessary (it isn't for this push-only design).
