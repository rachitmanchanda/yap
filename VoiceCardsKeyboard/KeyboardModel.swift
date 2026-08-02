import Foundation
import Observation
import SwiftData
import UIKit
import UniformTypeIdentifiers

@MainActor
@Observable
final class KeyboardModel {
    private(set) var cards: [Card] = []
    private(set) var clipboardItems: [ClipboardItem] = []
    private(set) var hasFullAccess = false
    private(set) var canReadSharedStorage = false
    private(set) var dictationSession: KeyboardDictationSession?
    private(set) var modes: [RewriteMode] = []
    var query = ""
    var errorMessage: String?
    var clipboardNotice: String?
    private let dictationBridge = KeyboardDictationBridge()
    private let clipboardAssets = ClipboardAssetStore()
    private var sharedContainer: ModelContainer?
    private var clipboardCaptureService: ClipboardCaptureService?
    private var didInitialLoad = false

    init() {}

    var recent: [Card] { Array(cards.prefix(12)) }
    var quickThree: [Card] { Array(cards.prefix(3)) }
    var pinned: [Card] { cards.filter(\.pinned) }
    var recentClipboard: [ClipboardItem] { Array(clipboardItems.prefix(12)) }
    var pinnedClipboard: [ClipboardItem] { clipboardItems.filter(\.pinned) }
    var isFlowReady: Bool { dictationSession?.phase == .readyForCapture }

    var searchResults: [Card] {
        guard let query = query.nilIfBlank else { return [] }
        let needle = query.searchNormalized
        return cards.filter {
            [$0.title, $0.rawText, $0.enhancedText ?? "", $0.processedText ?? ""]
                .contains { $0.searchNormalized.localizedStandardContains(needle) }
        }
    }

    var clipboardSearchResults: [ClipboardItem] {
        guard let query = query.nilIfBlank else { return [] }
        let needle = query.searchNormalized
        return clipboardItems.filter {
            $0.displayText.searchNormalized.localizedStandardContains(needle)
        }
    }

    func updateAccess(_ hasFullAccess: Bool) {
        let accessChanged = self.hasFullAccess != hasFullAccess
        self.hasFullAccess = hasFullAccess
        guard !didInitialLoad || accessChanged else {
            refreshDictationSession()
            return
        }
        didInitialLoad = true
        reload()
    }

    func reload() {
        refreshDictationSession()
        // The system flag can lag after Settings changes, so the App Group itself is authoritative.
        do {
            let container = try retainedContainer()
            cards = try CardRepository(context: container.mainContext).recent(limit: 100)
            clipboardItems = try ClipboardRepository(context: container.mainContext).recent(limit: 100)
            modes = try ModeRepository(context: container.mainContext).all()
            canReadSharedStorage = true
            errorMessage = nil
        } catch {
            cards = []
            clipboardItems = []
            canReadSharedStorage = false
            errorMessage = error.localizedDescription
        }
    }

    func captureClipboardIfChanged(force: Bool = false) {
        guard hasFullAccess, AppPreferences.automaticClipboardCapture else { return }
        do {
            let container = try retainedContainer()
            if clipboardCaptureService == nil {
                clipboardCaptureService = ClipboardCaptureService(context: container.mainContext)
            }
            if try clipboardCaptureService?.captureIfChanged(force: force) ?? 0 > 0 {
                clipboardItems = try ClipboardRepository(context: container.mainContext).recent(limit: 100)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func useClipboardItem(_ item: ClipboardItem, insert: (String) -> Void) {
        do {
            let container = try retainedContainer()
            let repository = ClipboardRepository(context: container.mainContext)
            switch item.kind {
            case .text, .url:
                guard let text = item.text?.nilIfBlank else { return }
                insert(text)
                try repository.markUsed(item)
            case .image:
                guard let data = clipboardAssets.imageData(fileName: item.imageFileName),
                      let typeIdentifier = item.originalUTType else {
                    throw ClipboardAssetError.invalidImage
                }
                UIPasteboard.general.setData(data, forPasteboardType: typeIdentifier)
                ClipboardWriteMarker.mark(
                    hash: ClipboardFingerprint.make(kind: .image, data: data),
                    changeCount: UIPasteboard.general.changeCount
                )
                try repository.markUsed(item)
                clipboardNotice = "Image copied — touch and hold the text field, then Paste."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func thumbnail(for item: ClipboardItem) -> UIImage? {
        clipboardAssets.thumbnail(fileName: item.thumbnailFileName)
    }

    private func retainedContainer() throws -> ModelContainer {
        if let sharedContainer { return sharedContainer }
        let container = try SharedModelContainer.make()
        sharedContainer = container
        return container
    }

    func refreshDictationSession() {
        let previousSession = dictationSession
        let refreshedSession = currentDictationSession()
        dictationSession = refreshedSession

        // A keyboard extension can stay resident while the user creates a custom mode in Yap.
        // Refresh once when the picker arrives so it reflects the latest shared mode library
        // without reloading SwiftData on every 250 ms dictation poll.
        if refreshedSession?.phase == .awaitingMode,
           previousSession?.phase != .awaitingMode || previousSession?.id != refreshedSession?.id {
            reloadModesForPicker()
        }
    }

    private func reloadModesForPicker() {
        do {
            let container = try retainedContainer()
            modes = try ModeRepository(context: container.mainContext).all()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Extension processes are frequently killed mid-handoff, so abandoned sessions must not
    /// permanently replace the keyboard's microphone button with a stale recording state.
    private func currentDictationSession(now: Date = .now) -> KeyboardDictationSession? {
        guard let session = dictationBridge.load() else { return nil }

        // Cancellation is a command for the app, not a screen the keyboard should wait on.
        // Keep the command on disk for the app to consume, but recover the keyboard immediately.
        if session.phase == .cancelRequested || session.phase == .endFlowRequested {
            return nil
        }

        let age = now.timeIntervalSince(session.updatedAt)
        let isStale: Bool
        switch session.phase {
        case .consumed:
            // Give the armed host process time to acknowledge insertion and return Flow to ready.
            isStale = age > 3
        case .cancelRequested:
            isStale = true
        case .endFlowRequested:
            isStale = true
        case .readyForCapture:
            // The armed host app writes a heartbeat while its audio engine is alive. A stale
            // marker must fall back to the normal app handoff instead of pretending Flow is on.
            isStale = (session.flowExpiresAt.map { $0 <= now } ?? false) || age > 3
        case .startRequested:
            // If the armed app process was evicted, recover to the normal foreground handoff.
            isStale = age > 4
        case .launching:
            // A normal handoff reaches `.recording` almost immediately. Recover quickly if iOS
            // declines to foreground the app instead of trapping the keyboard on a spinner.
            isStale = age > 6
        case .recording, .stopRequested, .transcribing, .enhancing,
             .awaitingMode, .insertRequested, .modeRequested, .rewriting:
            isStale = age > 4 * 60
        case .completed:
            isStale = age > 10 * 60
        case .failed:
            isStale = age > 30
        case .flowExpired:
            isStale = age > 4 * 60 * 60
        }

        if isStale {
            dictationBridge.save(nil)
            return nil
        }
        return session
    }

    func requestStop() {
        guard let session = dictationSession else { return }
        dictationBridge.update(id: session.id, phase: .stopRequested)
        reload()
    }

    func requestStart() {
        guard let session = dictationSession, session.phase == .readyForCapture else { return }
        dictationBridge.update(id: session.id, phase: .startRequested)
        refreshDictationSession()
    }

    func failHandoff(sessionID: UUID) {
        dictationBridge.update(
            id: sessionID,
            phase: .failed,
            error: "Yap could not open. Tap the orange Yap button to try again."
        )
        refreshDictationSession()
    }

    func cancelDictation() {
        guard let session = dictationSession else { return }
        dictationBridge.update(id: session.id, phase: .cancelRequested)
        // Do not leave the extension waiting for an acknowledgement from a process iOS may
        // suspend. The durable file remains for the main app's monitor to consume.
        dictationSession = nil
    }

    func insertOriginal() {
        guard let session = dictationSession else { return }
        dictationBridge.update(id: session.id, phase: .insertRequested)
        refreshDictationSession()
    }

    func requestMode(_ modeID: String) {
        guard let session = dictationSession else { return }
        dictationBridge.update(
            id: session.id,
            phase: .modeRequested,
            selectedModeID: modeID
        )
        refreshDictationSession()
    }

    func takeCompletedText() -> String? {
        guard let session = dictationBridge.load(),
              session.phase == .completed,
              let text = session.completedText?.nilIfBlank else {
            return nil
        }
        dictationBridge.update(id: session.id, phase: .consumed)
        dictationSession = dictationBridge.load()
        return text
    }
}
