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
        XCTAssertTrue(multipart.contains("translit"))
        XCTAssertTrue(multipart.contains("hi-IN"))
        XCTAssertEqual(TranscriptionLanguage.hindi.displayName, "Hinglish")
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
