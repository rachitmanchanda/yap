import SwiftData
import SwiftUI

struct RootView: View {
    @Bindable var appModel: AppModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var networkMonitor = NetworkMonitor()
    @State private var handledKeyboardSessionID: UUID?
    @State private var didPrepareUITestHandoff = false
    @State private var clipboardCaptureService: ClipboardCaptureService?
    private let dictationBridge = KeyboardDictationBridge()

    var body: some View {
        NavigationStack {
            StreamView(
                context: modelContext,
                capture: { appModel.presentCapture(autoStart: true) }
            )
        }
        .tint(YapPalette.acid)
        .sheet(isPresented: $appModel.isCapturePresented) {
            CaptureView(
                model: RecordingSessionModel.production(
                    context: modelContext,
                    keyboardSessionID: appModel.keyboardSessionID
                ),
                autoStart: appModel.captureShouldAutoStart
            ) {
                appModel.isCapturePresented = false
                appModel.keyboardSessionID = nil
            }
            // A fresh keyboard session must replace any expired capture sheet and its old model.
            .id(appModel.keyboardSessionID)
            .presentationDetents([.fraction(0.9)])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(38)
            .presentationBackground(.clear)
            .presentationContentInteraction(.scrolls)
        }
        .task {
            #if DEBUG
            if shouldShowUITestHandoffCoach,
               !didPrepareUITestHandoff {
                didPrepareUITestHandoff = true
                let session = dictationBridge.begin()
                handledKeyboardSessionID = session.id
                // Present before any network retry work so the microphone coach is deterministic.
                appModel.presentCapture(autoStart: true, keyboardSessionID: session.id)
            }
            #endif
            // UI tests validate capture and navigation independently; reading the host pasteboard
            // here would place an unrelated system permission alert over every launch.
            if !isUITesting {
                clipboardCaptureService = ClipboardCaptureService(context: modelContext)
                _ = try? clipboardCaptureService?.captureIfChanged(force: true)
            }
            try? HistoryRetentionService(context: modelContext).apply(days: AppPreferences.retentionDays)
            if networkMonitor.isConnected {
                await RetryProcessor(context: modelContext).processPending()
            }
            presentPendingCaptureIfNeeded()
        }
        .task {
            // When the keyboard is used inside Yap itself, the app is already active, so
            // neither a deep link nor scenePhase changes. Polling this tiny App Group flag makes
            // that path feel immediate while avoiding any microphone access in the extension.
            while !Task.isCancelled {
                // The App Intent transition can temporarily report `.inactive` even though the
                // containing app is visible. Preparing the sheet is safe; AVFoundation remains
                // the authority for whether recording may actually begin.
                presentPendingCaptureIfNeeded()
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
        .task {
            while !Task.isCancelled {
                if scenePhase == .active {
                    _ = try? clipboardCaptureService?.captureIfChanged()
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .onChange(of: networkMonitor.isConnected) { _, isConnected in
            guard isConnected else { return }
            Task { await RetryProcessor(context: modelContext).processPending() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                presentPendingCaptureIfNeeded()
                _ = try? clipboardCaptureService?.captureIfChanged(force: true)
            }
        }
        .alert("Storage needs attention", isPresented: Binding(
            get: { appModel.startupError != nil },
            set: { if !$0 { appModel.startupError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(appModel.startupError ?? "")
        }
    }

    private func presentPendingCaptureIfNeeded() {
        // The keyboard and app are different processes. Read the request from an atomic file in
        // their App Group instead of CFPreferences, whose process caches can diverge.
        if let session = dictationBridge.load(),
           session.phase == .launching,
           handledKeyboardSessionID != session.id {
            handledKeyboardSessionID = session.id
            appModel.presentCapture(autoStart: true, keyboardSessionID: session.id)
            return
        }

        // Retained for CaptureThoughtIntent, which launches without a keyboard session.
        guard AppPreferences.shouldStartCapture else { return }
        let keyboardSessionID = AppPreferences.pendingKeyboardSessionID
        AppPreferences.shouldStartCapture = false
        AppPreferences.pendingKeyboardSessionID = nil
        appModel.presentCapture(
            autoStart: true,
            keyboardSessionID: keyboardSessionID
        )
    }

    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-uiTest") }
            || ProcessInfo.processInfo.environment["YAP_UI_TEST_KEYBOARD_HANDOFF"] == "1"
    }

    private var shouldShowUITestHandoffCoach: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTestKeyboardHandoffCoach")
            || ProcessInfo.processInfo.environment["YAP_UI_TEST_KEYBOARD_HANDOFF"] == "1"
    }
}
