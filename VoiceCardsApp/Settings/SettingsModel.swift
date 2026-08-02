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
    private(set) var learnedTermCount = 0
    private(set) var yapCount = 0
    var message: String?

    private let modeRepository: ModeRepository
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
        modeRepository = ModeRepository(context: context)
        defaultModeID = AppPreferences.defaultModeID
        retentionDays = AppPreferences.retentionDays
        automaticClipboardCapture = AppPreferences.automaticClipboardCapture
        reloadModes()
        reloadMemory()
    }

    /// Settings remains alive while the mode editor is pushed, so refresh on return instead of
    /// keeping the snapshot captured when the screen was first created.
    func reloadModes() {
        do {
            try modeRepository.seedBuiltInsIfNeeded()
            modes = try modeRepository.all()
            if let defaultModeID,
               !modes.contains(where: { $0.id == defaultModeID }) {
                self.defaultModeID = nil
                AppPreferences.defaultModeID = nil
            }
        } catch {
            message = error.localizedDescription
        }
    }

    func reloadMemory() {
        do {
            yapCount = try context.fetchCount(FetchDescriptor<Card>())
            learnedTermCount = try context.fetch(FetchDescriptor<PersonalTerm>())
                .lazy
                .filter { $0.kind == .name || $0.useCount >= 3 }
                .count
        } catch {
            message = error.localizedDescription
        }
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

    /// Settings are expected to take effect as soon as a picker closes; requiring a separate
    /// save button made the selected mode look active while capture still read the old value.
    func setDefaultMode(_ id: String?) {
        defaultModeID = id
        AppPreferences.defaultModeID = id
    }

    func setRetentionDays(_ days: Int) {
        retentionDays = days
        AppPreferences.retentionDays = days
    }

    func setAutomaticClipboardCapture(_ enabled: Bool) {
        automaticClipboardCapture = enabled
        AppPreferences.automaticClipboardCapture = enabled
    }
}
