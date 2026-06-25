import ActivityKit
import SwiftUI
import WidgetKit

// Phase 4 SCAFFOLD — the Live Activity UI (Lock Screen + Dynamic Island). Belongs to
// the widget-extension target only. Updated entirely by server APNs pushes
// (apns-push-type: liveactivity, apns-priority: 5 for routine updates), so the user's
// placement stays live on the Lock Screen / Dynamic Island without the app running.
// See ios/RaceLiveActivity/README.md.
struct RaceLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RaceActivityAttributes.self) { context in
            // Lock Screen / banner presentation.
            VStack(alignment: .leading, spacing: 6) {
                Text(context.attributes.raceName)
                    .font(.headline)
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline) {
                    Text(ordinal(context.state.placement))
                        .font(.title2).bold()
                    Text("of \(context.state.totalParticipants)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(context.state.mySteps) steps")
                        .monospacedDigit()
                }
                Text("Ends \(context.state.endsAt, style: .relative)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.6))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(ordinal(context.state.placement)).font(.title3).bold()
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.mySteps)").monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.attributes.raceName).font(.caption)
                }
            } compactLeading: {
                Text("#\(context.state.placement)")
            } compactTrailing: {
                Text("\(context.state.mySteps)").monospacedDigit()
            } minimal: {
                Text("#\(context.state.placement)")
            }
        }
    }
}

private func ordinal(_ n: Int) -> String {
    let suffix: String
    switch (n % 100, n % 10) {
    case (11, _), (12, _), (13, _): suffix = "th"
    case (_, 1): suffix = "st"
    case (_, 2): suffix = "nd"
    case (_, 3): suffix = "rd"
    default: suffix = "th"
    }
    return "\(n)\(suffix)"
}
