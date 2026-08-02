import ActivityKit
import AppIntents
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
                if canTurnOff(context.state.phase) {
                    Button(intent: TurnOffYapFlowIntent(sessionID: context.attributes.sessionID)) {
                        Image(systemName: "power")
                            .font(.headline)
                            .frame(width: 40, height: 40)
                            .background(.secondary.opacity(0.18), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Turn off Yap Flow")
                }
            }
            .padding()
            .activityBackgroundTint(Color(uiColor: .secondarySystemBackground))
            .activitySystemActionForegroundColor(.primary)
            .widgetURL(captureURL(for: context.attributes.sessionID))
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
                    HStack(spacing: 8) {
                        if context.state.phase == .recording {
                            Text(
                                timerInterval: context.attributes.startedAt...Date.distantFuture,
                                countsDown: false
                            )
                            .font(.caption.monospacedDigit())
                        }
                        if canTurnOff(context.state.phase) {
                            Button(intent: TurnOffYapFlowIntent(sessionID: context.attributes.sessionID)) {
                                Image(systemName: "power")
                                    .font(.headline)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Turn off Yap Flow")
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.phase == .ready
                        ? "Tap the Yap keyboard microphone whenever you want to speak."
                        : "Return to your text field when dictation finishes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                HStack(spacing: 5) {
                    Circle()
                        .fill(context.state.phase == .recording ? YapActivityPalette.clay : statusColor(context.state.phase))
                        .frame(width: 7, height: 7)
                    if context.state.phase == .recording {
                        YapActivityMiniWaveform()
                    }
                }
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
                Circle()
                    .fill(context.state.phase == .recording ? YapActivityPalette.clay : statusColor(context.state.phase))
                    .frame(width: 8, height: 8)
            }
            .keylineTint(YapActivityPalette.clay)
            .widgetURL(captureURL(for: context.attributes.sessionID))
        }
    }

    private func statusSymbol(_ phase: DictationActivityAttributes.ContentState.Phase) -> String {
        switch phase {
        case .ready: "mic.circle.fill"
        case .recording: "waveform"
        case .transcribing: "text.bubble"
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .expired: "arrow.up.forward.app.fill"
        }
    }

    private func canTurnOff(_ phase: DictationActivityAttributes.ContentState.Phase) -> Bool {
        phase == .ready || phase == .recording || phase == .transcribing
    }

    private func captureURL(for sessionID: UUID) -> URL? {
        URL(string: "app://capture?keyboardSession=\(sessionID.uuidString)")
    }

    private func statusColor(_ phase: DictationActivityAttributes.ContentState.Phase) -> Color {
        switch phase {
        case .ready: YapActivityPalette.clay
        case .recording: .red
        case .transcribing: .blue
        case .completed: .green
        case .failed: .orange
        case .expired: .orange
        }
    }
}

/// ActivityKit controls cannot own the recorder. This intent writes a durable command into the
/// App Group so the already-running main app releases audio and ends the activity immediately.
struct TurnOffYapFlowIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Turn Off Yap Flow"
    static let description = IntentDescription("Stop Yap's active microphone session.")

    @Parameter(title: "Session")
    var sessionID: String

    init(sessionID: UUID) {
        self.sessionID = sessionID.uuidString
    }

    init() {
        sessionID = ""
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: sessionID) else { return .result() }
        KeyboardDictationBridge().update(id: id, phase: .endFlowRequested)
        return .result()
    }
}

private enum YapActivityPalette {
    static let clay = Color(red: 0.847, green: 0.353, blue: 0.188)
}

private struct YapActivityMiniWaveform: View {
    private let heights: [CGFloat] = [6, 11, 16, 9, 13, 7, 10]

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(Array(heights.enumerated()), id: \.offset) { _, height in
                Capsule()
                    .fill(.white.opacity(0.86))
                    .frame(width: 2.5, height: height)
            }
        }
        .accessibilityHidden(true)
    }
}
