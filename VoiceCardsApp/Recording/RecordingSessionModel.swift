import Foundation
import Observation
import SwiftData
import UIKit

struct KeyboardHandoffLifecycle: Equatable {
    enum State: Equatable {
        case notApplicable
        case preparing
        case ready
        case returned
        case finished
    }

    private(set) var state: State
    private(set) var liveActivityResult: LiveActivityStartResult?

    init(isKeyboardCapture: Bool) {
        state = isKeyboardCapture ? .preparing : .notApplicable
    }

    mutating func prepare() {
        guard state != .notApplicable else { return }
        liveActivityResult = nil
        state = .preparing
    }

    mutating func recordingReady(activityResult: LiveActivityStartResult) {
        guard state != .notApplicable else { return }
        liveActivityResult = activityResult
        state = .ready
    }

    mutating func markReturned() {
        guard state == .ready else { return }
        state = .returned
    }

    mutating func finish() {
        guard state != .notApplicable else { return }
        state = .finished
    }
}

@MainActor
@Observable
final class RecordingSessionModel {
    enum Phase: Equatable {
        case idle
        case requestingPermission
        case recording
        case transcribing
        case ready
        case rewriting
        case saving
        case saved
        case failed(String)
    }

    var phase: Phase = .idle
    var transcript = ""
    var enhancedTranscript: String?
    var rewrittenText: String?
    var selectedModeID: String?
    var modes: [RewriteMode] = []
    var language: TranscriptionLanguage = .automatic
    let outputStyle: TranscriptionOutputStyle = .romanHinglish
    var didUseOfflineTranscription = false
    var notice: String?
    private(set) var keyboardHandoff: KeyboardHandoffLifecycle
    private(set) var microphonePermissionDenied = false
    private var generatedTitle: String?
    private var activeLanguage: TranscriptionLanguage = .automatic
    private var activeOutputStyle: TranscriptionOutputStyle = .romanHinglish

    let recorder: AudioRecorder
    private let transcriptionService: any TranscriptionService
    private let rewriteService: any RewriteService
    private let cardRepository: CardRepository
    private let modeRepository: ModeRepository
    private let retryQueue: RetryQueue
    private let lexicon: PersonalLexiconRepository
    private let clipboard: any ClipboardWriting
    private let keyboardSessionID: UUID?
    private let streamingClient: SarvamStreamingTranscriptionClient?
    private let dictationBridge: KeyboardDictationBridge
    private let liveActivity: any DictationActivityControlling
    private let latency = CaptureLatencyTracker()
    private var audioURL: URL?
    private var keyboardMonitorTask: Task<Void, Never>?
    private var streamingTranscriptTask: Task<Void, Never>?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    init(
        recorder: AudioRecorder,
        transcriptionService: any TranscriptionService,
        rewriteService: any RewriteService,
        context: ModelContext,
        clipboard: any ClipboardWriting,
        keyboardSessionID: UUID? = nil,
        streamingClient: SarvamStreamingTranscriptionClient? = nil,
        dictationBridge: KeyboardDictationBridge = KeyboardDictationBridge(),
        liveActivity: any DictationActivityControlling = DictationLiveActivityController()
    ) {
        self.recorder = recorder
        self.transcriptionService = transcriptionService
        self.rewriteService = rewriteService
        cardRepository = CardRepository(context: context)
        modeRepository = ModeRepository(context: context)
        retryQueue = RetryQueue(context: context)
        lexicon = PersonalLexiconRepository(context: context)
        self.clipboard = clipboard
        self.keyboardSessionID = keyboardSessionID
        self.streamingClient = streamingClient
        self.dictationBridge = dictationBridge
        self.liveActivity = liveActivity
        keyboardHandoff = KeyboardHandoffLifecycle(isKeyboardCapture: keyboardSessionID != nil)
        if keyboardSessionID != nil {
            // The keyboard path fixes Roman Hinglish for the whole recording.
            language = .hindi
        }
        if let streamingClient {
            recorder.onPCMData = { data in
                Task { await streamingClient.send(pcm16: data) }
            }
        }
        recorder.onMaximumDuration = { [weak self] in
            Task { await self?.stopAndTranscribe(maximumReached: true) }
        }
        modes = (try? modeRepository.all()) ?? []
    }

    static func production(
        context: ModelContext,
        keyboardSessionID: UUID? = nil
    ) -> RecordingSessionModel {
        return RecordingSessionModel(
            recorder: AudioRecorder(),
            transcriptionService: FallbackTranscriptionService(
                online: SupabaseTranscriptionService(),
                offline: OnDeviceSpeechService()
            ),
            rewriteService: SupabaseRewriteService(),
            context: context,
            clipboard: SystemClipboardWriter(),
            keyboardSessionID: keyboardSessionID,
            streamingClient: SarvamStreamingTranscriptionClient()
        )
    }

    func start() async {
        guard phase == .idle || isFailure else { return }
        latency.captureRequested()
        activeLanguage = language
        activeOutputStyle = outputStyle
        microphonePermissionDenied = false
        keyboardHandoff.prepare()
        phase = .requestingPermission
        do {
            await beginStreaming()
            try await recorder.requestPermissionAndStart()
            latency.recordingStarted()
            phase = .recording
            if let keyboardSessionID {
                let startedAt = Date.now
                dictationBridge.update(
                    id: keyboardSessionID,
                    phase: .recording,
                    startedAt: startedAt
                )
                let activityResult = await liveActivity.start(
                    sessionID: keyboardSessionID,
                    startedAt: startedAt
                )
                keyboardHandoff.recordingReady(activityResult: activityResult)
                startKeyboardSessionMonitor()
            }
        } catch {
            await streamingClient?.cancel()
            if let recorderError = error as? AudioRecorderError,
               case .permissionDenied = recorderError {
                microphonePermissionDenied = true
            }
            keyboardHandoff.finish()
            failKeyboardSession(error)
            phase = .failed(error.localizedDescription)
        }
    }

    func stopAndTranscribe(maximumReached: Bool = false) async {
        guard phase == .recording else { return }
        latency.recordingStopped()
        do {
            audioURL = try recorder.stop()
            if maximumReached { notice = "Three-minute recording limit reached." }
            phase = .transcribing
            if let keyboardSessionID {
                dictationBridge.update(id: keyboardSessionID, phase: .transcribing)
                keyboardHandoff.finish()
                await liveActivity.endRecording()
                beginBackgroundWork()
            }
            try await transcribeCurrentAudio()
            endBackgroundWork()
        } catch {
            endBackgroundWork()
            await streamingClient?.cancel()
            failKeyboardSession(error)
            phase = .failed(error.localizedDescription)
        }
    }

    /// Cancellation must tear down every resource because dismissing a SwiftUI sheet does not
    /// guarantee the recording model is deallocated immediately.
    func cancel() async {
        recorder.cancel()
        await streamingClient?.cancel()
        streamingTranscriptTask?.cancel()
        streamingTranscriptTask = nil
        endBackgroundWork()
        if let keyboardSessionID {
            dictationBridge.update(id: keyboardSessionID, phase: .consumed)
            keyboardHandoff.finish()
            await liveActivity.endCancelled()
        }
        keyboardMonitorTask?.cancel()
        keyboardMonitorTask = nil
        phase = .idle
    }

    func retryTranscription() async {
        guard audioURL != nil else {
            phase = .idle
            await start()
            return
        }
        phase = .transcribing
        do {
            try await transcribeCurrentAudio()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func transcribeCurrentAudio() async throws {
        guard let audioURL else { throw AudioRecorderError.unableToStart }
        do {
            let knownTerms = (try? lexicon.hints()) ?? []
            let result: TranscriptionResult
            if let streamedText = await streamingClient?.finish()?.nilIfBlank {
                result = TranscriptionResult(text: streamedText, usedOnDeviceFallback: false)
            } else {
                result = try await transcriptionService.transcribe(
                    audioURL: audioURL,
                    language: activeLanguage,
                    outputStyle: activeOutputStyle,
                    vocabularyHints: knownTerms
                )
            }
            transcript = RomanScriptNormalizer.normalize(result.text, for: activeOutputStyle)
            latency.transcriptReady()
            didUseOfflineTranscription = result.usedOnDeviceFallback
            // Keyboard dictation skips this optional LLM pass: "None" must be the instant path.
            if keyboardSessionID == nil,
               let enhancement = try? await rewriteService.enhance(
                transcript: result.text,
                knownTerms: knownTerms
            ), enhancement.changed {
                enhancedTranscript = enhancement.text
            }
            phase = .ready
            if keyboardSessionID == nil,
               let defaultModeID = AppPreferences.defaultModeID,
               let defaultMode = modes.first(where: { $0.id == defaultModeID }) {
                await apply(mode: defaultMode)
            }
            if keyboardSessionID != nil {
                await completeKeyboardInsertion(text: enhancedTranscript ?? transcript)
            }
        } catch {
            try? retryQueue.enqueueTranscription(audioURL: audioURL, error: error)
            throw error
        }
    }

    func apply(mode: RewriteMode?) async {
        selectedModeID = mode?.id
        rewrittenText = nil
        generatedTitle = nil
        guard let mode else { return }
        phase = .rewriting
        do {
            let result = try await rewriteService.rewrite(
                text: enhancedTranscript ?? transcript,
                mode: ModeDefinition(id: mode.id, name: mode.name, emoji: mode.emoji, prompt: mode.systemPrompt)
            )
            rewrittenText = result.rewrittenText
            generatedTitle = result.title
            notice = nil
            phase = .ready
        } catch {
            notice = error.localizedDescription
            phase = .ready
        }
    }

    func saveAndCopy() async {
        guard transcript.nilIfBlank != nil else {
            phase = .failed(TranscriptionError.emptyResult.localizedDescription)
            return
        }
        phase = .saving
        let title: String
        if let generatedTitle {
            title = generatedTitle
        } else {
            title = (try? await rewriteService.title(for: enhancedTranscript ?? transcript))
                ?? (enhancedTranscript ?? transcript).firstWordsTitle()
        }

        let card = Card(
            sourceType: .voice,
            rawText: transcript,
            enhancedText: enhancedTranscript,
            processedText: rewrittenText,
            modeApplied: rewrittenText == nil ? nil : selectedModeID,
            title: title
        )
        do {
            try cardRepository.insert(card)
            try? lexicon.learn(from: card.preferredText)
            clipboard.copy(card.preferredText)
            if let audioURL { try? FileManager.default.removeItem(at: audioURL) }
            phase = .saved
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private var isFailure: Bool {
        if case .failed = phase { true } else { false }
    }

    private func startKeyboardSessionMonitor() {
        keyboardMonitorTask?.cancel()
        keyboardMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, let keyboardSessionID else { return }
                switch dictationBridge.load()?.phase {
                case .stopRequested:
                    await stopAndTranscribe()
                case .cancelRequested:
                    await cancel()
                    return
                case .insertRequested:
                    await completeKeyboardInsertion(text: enhancedTranscript ?? transcript)
                    return
                case .modeRequested:
                    await applyKeyboardMode()
                    if dictationBridge.load()?.phase == .completed { return }
                case .recording:
                    dictationBridge.update(
                        id: keyboardSessionID,
                        phase: .recording,
                        audioLevel: recorder.level
                    )
                case .completed, .consumed, .failed:
                    return
                default:
                    break
                }
            }
        }
    }

    private func applyKeyboardMode() async {
        guard let keyboardSessionID,
              let session = dictationBridge.load(),
              session.id == keyboardSessionID,
              let modeID = session.selectedModeID,
              let mode = modes.first(where: { $0.id == modeID }) else {
            return
        }

        dictationBridge.update(
            id: keyboardSessionID,
            phase: .rewriting,
            selectedModeID: modeID
        )
        phase = .rewriting
        latency.rewriteStarted()
        do {
            let result = try await rewriteService.rewrite(
                text: enhancedTranscript ?? transcript,
                mode: ModeDefinition(
                    id: mode.id,
                    name: mode.name,
                    emoji: mode.emoji,
                    prompt: mode.systemPrompt
                )
            )
            selectedModeID = modeID
            rewrittenText = result.rewrittenText
            generatedTitle = result.title
            latency.rewriteFinished()
            await completeKeyboardInsertion(text: result.rewrittenText)
        } catch {
            latency.rewriteFinished()
            phase = .ready
            dictationBridge.update(
                id: keyboardSessionID,
                phase: .awaitingMode,
                error: error.localizedDescription,
                transcript: enhancedTranscript ?? transcript,
                selectedModeID: modeID
            )
        }
    }

    /// Publishes before title generation so the active keyboard can paste without waiting on another API call.
    func completeKeyboardInsertion(text: String) async {
        guard let keyboardSessionID, text.nilIfBlank != nil else { return }
        // This is also the recovery path when iOS replaces our keyboard before insertion.
        clipboard.copy(text)
        latency.textInserted()
        dictationBridge.update(id: keyboardSessionID, phase: .completed, text: text)
        await saveAndCopy()
    }

    private func beginStreaming() async {
        guard let streamingClient else { return }
        streamingTranscriptTask?.cancel()
        let updates = await streamingClient.start(
            language: activeLanguage,
            outputStyle: activeOutputStyle
        )
        streamingTranscriptTask = Task { [weak self] in
            for await partial in updates {
                guard let self else { return }
                let stablePartial = RomanScriptNormalizer.normalize(partial, for: activeOutputStyle)
                transcript = stablePartial
                guard let keyboardSessionID,
                      dictationBridge.load()?.phase == .recording else {
                    continue
                }
                dictationBridge.update(
                    id: keyboardSessionID,
                    phase: .recording,
                    transcript: stablePartial,
                    audioLevel: recorder.level
                )
            }
        }
    }

    private func failKeyboardSession(_ error: Error) {
        guard let keyboardSessionID else { return }
        keyboardHandoff.finish()
        dictationBridge.update(
            id: keyboardSessionID,
            phase: .failed,
            error: error.localizedDescription
        )
        Task { await liveActivity.endFailed(message: "Dictation failed") }
    }

    func markReturnedToPreviousApp() {
        guard phase == .recording else { return }
        keyboardHandoff.markReturned()
    }

    private func beginBackgroundWork() {
        guard backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "Finish dictation") {
            self.endBackgroundWork()
        }
    }

    private func endBackgroundWork() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }
}
