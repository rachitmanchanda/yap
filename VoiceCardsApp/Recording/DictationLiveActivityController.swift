// ActivityKit's iOS 17 async APIs are not fully Sendable-annotated yet.
@preconcurrency import ActivityKit
import Foundation

enum LiveActivityStartResult: Equatable, Sendable {
    case started
    case disabled
    case failed(String)
}

/// Keeps ActivityKit replaceable in tests and prevents recording UI from depending on framework types.
@MainActor
protocol DictationActivityControlling: AnyObject {
    func start(sessionID: UUID, startedAt: Date) async -> LiveActivityStartResult
    func markReady() async
    func markProcessing() async
    func endCancelled() async
    func endFailed(message: String) async
    func endExpired() async
}

@MainActor
final class DictationLiveActivityController: DictationActivityControlling {
    private var activity: Activity<DictationActivityAttributes>?
    private var sessionID: UUID?

    func start(sessionID: UUID, startedAt: Date = .now) async -> LiveActivityStartResult {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return .disabled }
        if let existing = Activity<DictationActivityAttributes>.activities.first(where: {
            $0.attributes.sessionID == sessionID
        }) {
            activity = existing
            self.sessionID = sessionID
            await update(phase: .recording, message: "Listening…", staleDate: startedAt.addingTimeInterval(4 * 60 * 60))
            return .started
        }
        // A previous app process can disappear before ending its activity. Retire those orphaned
        // surfaces before starting a new capture so cancel/retry always shows one truthful state.
        for existing in Activity<DictationActivityAttributes>.activities {
            let content = ActivityContent(
                state: DictationActivityAttributes.ContentState(
                    phase: .completed,
                    message: "Previous recording ended"
                ),
                staleDate: nil
            )
            await existing.end(content, dismissalPolicy: .immediate)
        }

        self.sessionID = sessionID
        let attributes = DictationActivityAttributes(sessionID: sessionID, startedAt: startedAt)
        let content = ActivityContent(
            state: DictationActivityAttributes.ContentState(
                phase: .recording,
                message: "Listening…"
            ),
            staleDate: startedAt.addingTimeInterval(4 * 60 * 60)
        )
        do {
            activity = try Activity.request(attributes: attributes, content: content)
            return .started
        } catch {
            self.sessionID = nil
            return .failed(error.localizedDescription)
        }
    }

    func markReady() async {
        await update(
            phase: .ready,
            message: "Yap Flow is on",
            staleDate: .now.addingTimeInterval(4 * 60 * 60)
        )
    }

    func markProcessing() async {
        await update(
            phase: .transcribing,
            message: "Cleaning up your words…",
            staleDate: .now.addingTimeInterval(4 * 60 * 60)
        )
    }

    func endCompleted() async {
        await end(phase: .completed, message: "Inserted into your app")
    }

    func endCancelled() async {
        await end(phase: .completed, message: "Recording cancelled")
    }

    func endFailed(message: String) async {
        await end(phase: .failed, message: message)
    }

    func endExpired() async {
        let content = ActivityContent(
            state: DictationActivityAttributes.ContentState(
                phase: .expired,
                message: "Open Yap to restart Flow"
            ),
            staleDate: nil
        )
        guard let currentActivity = resolvedActivity else { return }
        activity = nil
        sessionID = nil
        await currentActivity.end(
            content,
            dismissalPolicy: .after(.now.addingTimeInterval(4 * 60 * 60))
        )
    }

    private func update(
        phase: DictationActivityAttributes.ContentState.Phase,
        message: String,
        staleDate: Date?
    ) async {
        guard let currentActivity = resolvedActivity else { return }
        await currentActivity.update(
            ActivityContent(
                state: DictationActivityAttributes.ContentState(phase: phase, message: message),
                staleDate: staleDate
            )
        )
    }

    private func end(
        phase: DictationActivityAttributes.ContentState.Phase,
        message: String
    ) async {
        let content = ActivityContent(
            state: DictationActivityAttributes.ContentState(phase: phase, message: message),
            staleDate: nil
        )
        guard let currentActivity = resolvedActivity else { return }
        activity = nil
        sessionID = nil
        await currentActivity.end(
            content,
            dismissalPolicy: .after(.now.addingTimeInterval(3))
        )
    }

    private var resolvedActivity: Activity<DictationActivityAttributes>? {
        if let activity { return activity }
        guard let sessionID else { return nil }
        return Activity<DictationActivityAttributes>.activities.first {
            $0.attributes.sessionID == sessionID
        }
    }
}
