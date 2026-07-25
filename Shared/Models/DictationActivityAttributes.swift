import ActivityKit
import Foundation

struct DictationActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable, Hashable {
            case recording
            case transcribing
            case completed
            case failed
        }

        var phase: Phase
        var message: String
    }

    let sessionID: UUID
    let startedAt: Date
}
