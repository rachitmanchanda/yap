import ActivityKit
import Foundation

struct DictationActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable, Hashable {
            case ready
            case recording
            case transcribing
            case completed
            case failed
            case expired
        }

        var phase: Phase
        var message: String
    }

    let sessionID: UUID
    let startedAt: Date
}
