import XCTest
@testable import VoiceCards

final class ServiceResponseTests: XCTestCase {
    func testEnhancementPayloadPreservesChangedFlag() throws {
        let result = try TranscriptEnhancementPrompt.decode(
            #"{"text":"Meet Shreya tomorrow.","changed":true}"#,
            original: "Meet Shreya tomorow."
        )
        XCTAssertEqual(result.text, "Meet Shreya tomorrow.")
        XCTAssertTrue(result.changed)
    }

    func testMalformedEnhancementThrows() {
        XCTAssertThrowsError(
            try TranscriptEnhancementPrompt.decode("not json", original: "Keep me")
        )
    }

    func testEnhancementPromptDoesNotInventExpressivePunctuation() {
        let prompt = TranscriptEnhancementPrompt.system(knownTerms: "")
        XCTAssertTrue(prompt.contains("Never add an exclamation mark"))
        XCTAssertTrue(prompt.contains("including lowercase i"))
        XCTAssertTrue(prompt.contains("Never add terminal punctuation"))
        XCTAssertTrue(prompt.contains("aadat lag gayi"))
        XCTAssertTrue(prompt.contains("Output Latin script only"))
        XCTAssertTrue(prompt.contains("mam'mi"))
        XCTAssertTrue(prompt.contains("Hinglish signals include do cheezein"))
        XCTAssertTrue(prompt.contains("preserve grantiyan rather than changing it to gland"))
        XCTAssertTrue(prompt.contains("normalization is not cleanup"))
        XCTAssertTrue(prompt.contains("Phir, uske baad, ek toh"))
        XCTAssertTrue(prompt.contains("recording-chunk boundary"))
        XCTAssertTrue(prompt.contains("naya paragraph"))
        XCTAssertTrue(prompt.contains("A list needs at least two genuine items"))
        XCTAssertTrue(prompt.contains("When uncertain, use prose"))
        XCTAssertTrue(prompt.contains("Never add, remove, or change the meaning"))
    }

    func testEnhancementPromptInjectsLearnedTermsAsConservativeHints() {
        let prompt = TranscriptEnhancementPrompt.system(knownTerms: "Ritika, Stola")
        XCTAssertTrue(prompt.contains("Ritika, Stola"))
        XCTAssertTrue(prompt.contains("strong phonetic match"))
        XCTAssertTrue(prompt.contains("Never insert a merely similar term"))
    }

    func testFallbackUsesOfflineWhenOnlineFails() async throws {
        let service = FallbackTranscriptionService(
            online: StubTranscriber(result: .failure(URLError(.notConnectedToInternet))),
            offline: StubTranscriber(result: .success(.init(text: "नमस्ते", usedOnDeviceFallback: true)))
        )
        let result = try await service.transcribe(
            audioURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            language: .hindi,
            outputStyle: .romanHinglish,
            vocabularyHints: []
        )
        XCTAssertEqual(result.text, "नमस्ते")
        XCTAssertTrue(result.usedOnDeviceFallback)
    }

    func testManagedTranscriptionRequestsStableRomanHinglish() async throws {
        let client = RequestCapturingClient()
        let service = SupabaseTranscriptionService(client: client)
        let audioURL = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).wav")
        try Data([0, 1, 2, 3]).write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        _ = try await service.transcribe(
            audioURL: audioURL,
            language: .hindi,
            outputStyle: .romanHinglish,
            vocabularyHints: ["Rachit"]
        )

        let capturedBody = await client.requestBody()
        let body = try XCTUnwrap(capturedBody)
        let multipart = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(multipart.contains("name=\"mode\""))
        XCTAssertTrue(multipart.contains("codemix"))
        XCTAssertTrue(multipart.contains("hi-IN"))
        XCTAssertEqual(TranscriptionLanguage.hindi.displayName, "Hinglish")
    }

    func testRomanHinglishUsesCodeMixRecognitionBeforeCleanup() {
        XCTAssertEqual(TranscriptionOutputStyle.romanHinglish.sarvamMode, "codemix")
    }

    func testStreamingTranscriptMergerPreservesOrderedHinglishContext() {
        let result = StreamingTranscriptMerger.merge([
            "i was thinking ki kal",
            "hum pitch deck finish kar sakte hain",
            "and then send it to Rachit"
        ])

        XCTAssertEqual(
            result,
            "i was thinking ki kal hum pitch deck finish kar sakte hain and then send it to Rachit"
        )
    }

    func testStreamingTranscriptMergerRemovesReconnectOverlap() {
        let result = StreamingTranscriptMerger.merge([
            "mujhe lagta hai pitch deck kal ready ho jayegi",
            "pitch deck kal ready ho jayegi, phir papa ko bhej dena"
        ])

        XCTAssertEqual(
            result,
            "mujhe lagta hai pitch deck kal ready ho jayegi phir papa ko bhej dena"
        )
    }

    func testQualityGateRetriesPhoneticApostropheArtifacts() {
        XCTAssertTrue(
            TranscriptionQualityGate.shouldRetryCompletedAudio(
                "neksta ta'ima mam'mi apa acchi kolda kophi"
            )
        )
        XCTAssertFalse(
            TranscriptionQualityGate.shouldRetryCompletedAudio(
                "i'm sure that's the cold coffee Ritika mentioned"
            )
        )
        XCTAssertTrue(
            TranscriptionQualityGate.shouldRetryCompletedAudio(
                "yara a'i ki ipha disa isa varka"
            )
        )
    }

    func testManagedEnhancementUsesDedicatedHinglishCleanupWithinQualityBudget() async throws {
        let client = RewriteRequestCapturingClient()
        let service = SupabaseRewriteService(client: client)

        let result = try await service.enhance(
            transcript: "hey kya scene hai",
            knownTerms: ["Rachit"]
        )

        XCTAssertEqual(result.text, "hey, kya scene hai?")
        XCTAssertTrue(result.changed)

        let capturedBody = await client.requestBody()
        let body = try XCTUnwrap(capturedBody)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        XCTAssertEqual(json["operation"] as? String, "enhance")
        XCTAssertNil(json["mode"])
        XCTAssertEqual(json["knownTerms"] as? [String], ["Rachit"])
        let capturedTimeout = await client.timeoutInterval()
        let timeout = try XCTUnwrap(capturedTimeout)
        XCTAssertEqual(timeout, 15, accuracy: 0.01)
    }
}

private struct StubTranscriber: TranscriptionService {
    let result: Result<TranscriptionResult, Error>

    func transcribe(
        audioURL: URL,
        language: TranscriptionLanguage,
        outputStyle: TranscriptionOutputStyle,
        vocabularyHints: [String]
    ) async throws -> TranscriptionResult {
        try result.get()
    }
}

private actor RequestCapturingClient: HTTPClient {
    private var body: Data?

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        body = request.httpBody
        return HTTPResponse(
            data: Data(#"{"transcript":"mujhe message karna hai"}"#.utf8),
            statusCode: 200
        )
    }

    func requestBody() -> Data? { body }
}

private actor RewriteRequestCapturingClient: HTTPClient {
    private var body: Data?
    private var timeout: TimeInterval?

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        body = request.httpBody
        timeout = request.timeoutInterval
        return HTTPResponse(
            data: Data(
                #"{"text":"hey, kya scene hai?","title":"Casual message","provider":"deepseek","latencyMs":120}"#.utf8
            ),
            statusCode: 200
        )
    }

    func requestBody() -> Data? { body }
    func timeoutInterval() -> TimeInterval? { timeout }
}
