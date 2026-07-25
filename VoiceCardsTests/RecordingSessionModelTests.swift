import SwiftData
import XCTest
@testable import VoiceCards

@MainActor
final class RecordingSessionModelTests: XCTestCase {
    func testKeyboardHandoffMovesFromPreparingToReturnedAndFinished() {
        var handoff = KeyboardHandoffLifecycle(isKeyboardCapture: true)
        XCTAssertEqual(handoff.state, .preparing)

        handoff.recordingReady(activityResult: .started)
        XCTAssertEqual(handoff.state, .ready)
        XCTAssertEqual(handoff.liveActivityResult, .started)

        handoff.markReturned()
        XCTAssertEqual(handoff.state, .returned)

        handoff.finish()
        XCTAssertEqual(handoff.state, .finished)
    }

    func testKeyboardHandoffReportsDisabledLiveActivitiesWithoutBlockingRecording() {
        var handoff = KeyboardHandoffLifecycle(isKeyboardCapture: true)
        handoff.recordingReady(activityResult: .disabled)

        XCTAssertEqual(handoff.state, .ready)
        XCTAssertEqual(handoff.liveActivityResult, .disabled)
    }

    func testRegularCaptureNeverEntersKeyboardHandoff() {
        var handoff = KeyboardHandoffLifecycle(isKeyboardCapture: false)
        handoff.prepare()
        handoff.recordingReady(activityResult: .started)
        handoff.markReturned()
        handoff.finish()

        XCTAssertEqual(handoff.state, .notApplicable)
        XCTAssertNil(handoff.liveActivityResult)
    }

    func testSavingPreservesVerbatimAndCopiesEnhancedText() async throws {
        let container = try SharedModelContainer.make(inMemory: true)
        let clipboard = ClipboardSpy()
        let model = RecordingSessionModel(
            recorder: AudioRecorder(),
            transcriptionService: StubRecordingTranscriber(),
            rewriteService: StubRewriteService(),
            context: container.mainContext,
            clipboard: clipboard
        )
        model.transcript = "meet rachit tomorow"
        model.enhancedTranscript = "Meet Rachit tomorrow."

        await model.saveAndCopy()

        let card = try CardRepository(context: container.mainContext).recent(limit: 1).first
        XCTAssertEqual(card?.rawText, "meet rachit tomorow")
        XCTAssertEqual(card?.enhancedText, "Meet Rachit tomorrow.")
        XCTAssertEqual(clipboard.value, "Meet Rachit tomorrow.")
        XCTAssertEqual(model.phase, .saved)
    }

    func testKeyboardCompletionPublishesTextForAutomaticInsertion() async throws {
        let container = try SharedModelContainer.make(inMemory: true)
        let clipboard = ClipboardSpy()
        let sessionURL = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString)-keyboard-session.json")
        let bridge = KeyboardDictationBridge(sessionURL: sessionURL)
        let session = bridge.begin()
        defer { try? FileManager.default.removeItem(at: sessionURL) }
        let model = RecordingSessionModel(
            recorder: AudioRecorder(),
            transcriptionService: StubRecordingTranscriber(),
            rewriteService: StubRewriteService(),
            context: container.mainContext,
            clipboard: clipboard,
            keyboardSessionID: session.id,
            dictationBridge: bridge
        )
        model.transcript = "नमस्ते Rachit 👋"

        await model.completeKeyboardInsertion(text: "नमस्ते Rachit 👋")

        XCTAssertEqual(bridge.load()?.phase, .completed)
        XCTAssertEqual(bridge.load()?.completedText, "नमस्ते Rachit 👋")
        XCTAssertEqual(clipboard.value, "नमस्ते Rachit 👋")
    }
}

@MainActor
private final class ClipboardSpy: ClipboardWriting {
    var value: String?
    func copy(_ text: String) { value = text }
}

private struct StubRecordingTranscriber: TranscriptionService {
    func transcribe(
        audioURL: URL,
        language: TranscriptionLanguage,
        outputStyle: TranscriptionOutputStyle,
        vocabularyHints: [String]
    ) async throws -> TranscriptionResult {
        .init(text: "unused", usedOnDeviceFallback: false)
    }
}

private struct StubRewriteService: RewriteService {
    func rewrite(text: String, mode: ModeDefinition) async throws -> RewriteResult {
        .init(rewrittenText: text, title: "Test title")
    }

    func title(for text: String) async throws -> String { "Tomorrow meeting" }

    func enhance(transcript: String, knownTerms: [String]) async throws -> TranscriptEnhancement {
        .init(text: transcript, changed: false)
    }
}
