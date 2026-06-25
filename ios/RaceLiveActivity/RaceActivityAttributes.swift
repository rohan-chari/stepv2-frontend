import ActivityKit
import Foundation

// Phase 4 SCAFFOLD (iOS Live Activities) — NOT yet wired into an Xcode target.
// See ios/RaceLiveActivity/README.md for the target-creation steps.
//
// Shared attribute type for the race-placement Live Activity. It must belong to
// BOTH the Runner app target (which starts/ends the activity and registers the push
// token) AND the widget-extension target (which renders it). In Xcode: select this
// file -> File Inspector -> Target Membership -> check both.
//
// `ContentState` is the live-updating payload the backend pushes via APNs
// (apns-push-type: liveactivity) so placement stays current while the app is closed.
struct RaceActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var placement: Int          // live rank; 1 == leading
        var totalParticipants: Int
        var mySteps: Int
        var leaderSteps: Int
        var endsAt: Date
    }

    // Static for the life of the activity.
    var raceId: String
    var raceName: String
}
