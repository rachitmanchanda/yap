import AVFoundation
import Foundation
import Observation
import Speech
import SwiftData

@MainActor
@Observable
final class SettingsModel {
    var defaultModeID: String?
    var retentionDays = 0
    var automaticClipboardCapture = true
    private(set) var modes: [RewriteMode] = []
    var message: String?

    init(context: ModelContext) {
        defaultModeID = AppPreferences.defaultModeID
        retentionDays = AppPreferences.retentionDays
        automaticClipboardCapture = AppPreferences.automaticClipboardCapture
        modes = (try? ModeRepository(context: context).all()) ?? []
    }

    var microphoneStatus: String {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: "Allowed"
        case .denied: "Denied"
        case .undetermined: "Not requested"
        @unknown default: "Unknown"
        }
    }

    var speechStatus: String {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: "Allowed"
        case .denied, .restricted: "Denied"
        case .notDetermined: "Not requested"
        @unknown default: "Unknown"
        }
    }

    var latestLatency: String {
        CaptureLatencySnapshot.latest?.summary.nilIfBlank ?? "Record once to measure"
    }

    func save() {
        AppPreferences.defaultModeID = defaultModeID
        AppPreferences.retentionDays = retentionDays
        AppPreferences.automaticClipboardCapture = automaticClipboardCapture
        message = "Settings saved."
    }
}
