import ActivityKit
import SwiftUI
import WidgetKit

struct VoiceCardsDictationActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DictationActivityAttributes.self) { context in
            HStack(spacing: 14) {
                Image(systemName: statusSymbol(context.state.phase))
                    .font(.title2)
                    .foregroundStyle(statusColor(context.state.phase))

                VStack(alignment: .leading, spacing: 3) {
                    Text(context.state.message)
                        .font(.headline)
                    if context.state.phase == .recording {
                        Text(timerInterval: context.attributes.startedAt...Date.distantFuture, countsDown: false)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding()
            .activityBackgroundTint(Color(uiColor: .secondarySystemBackground))
            .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: statusSymbol(context.state.phase))
                        .foregroundStyle(statusColor(context.state.phase))
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.message)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.phase == .recording {
                        Text(
                            timerInterval: context.attributes.startedAt...Date.distantFuture,
                            countsDown: false
                        )
                        .font(.caption.monospacedDigit())
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Return to your text field when dictation finishes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: statusSymbol(context.state.phase))
                    .foregroundStyle(statusColor(context.state.phase))
            } compactTrailing: {
                if context.state.phase == .recording {
                    Text(
                        timerInterval: context.attributes.startedAt...Date.distantFuture,
                        countsDown: false
                    )
                    .font(.caption2.monospacedDigit())
                    .frame(width: 38)
                } else {
                    Image(systemName: context.state.phase == .failed ? "exclamationmark" : "ellipsis")
                }
            } minimal: {
                Image(systemName: statusSymbol(context.state.phase))
                    .foregroundStyle(statusColor(context.state.phase))
            }
            .keylineTint(.blue)
        }
    }

    private func statusSymbol(_ phase: DictationActivityAttributes.ContentState.Phase) -> String {
        switch phase {
        case .recording: "waveform"
        case .transcribing: "text.bubble"
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private func statusColor(_ phase: DictationActivityAttributes.ContentState.Phase) -> Color {
        switch phase {
        case .recording: .red
        case .transcribing: .blue
        case .completed: .green
        case .failed: .orange
        }
    }
}
