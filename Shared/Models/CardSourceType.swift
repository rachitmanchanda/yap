import Foundation

enum CardSourceType: String, Codable, CaseIterable, Sendable {
    case voice
    case share
    case manualPaste

    var systemImage: String {
        switch self {
        case .voice: "waveform"
        case .share: "square.and.arrow.down"
        case .manualPaste: "doc.on.clipboard"
        }
    }
}
