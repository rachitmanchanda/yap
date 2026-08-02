import XCTest
@testable import VoiceCards

final class KeyboardModelTests: XCTestCase {
    func testDictationBridgeSharesSessionThroughPhysicalFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sessionURL = directory.appending(path: "session.json")
        let keyboardBridge = KeyboardDictationBridge(sessionURL: sessionURL)
        let appBridge = KeyboardDictationBridge(sessionURL: sessionURL)

        let session = keyboardBridge.begin()
        XCTAssertEqual(appBridge.load()?.id, session.id)
        XCTAssertEqual(appBridge.load()?.phase, .launching)

        appBridge.update(id: session.id, phase: .recording, startedAt: .now)
        XCTAssertEqual(keyboardBridge.load()?.phase, .recording)
    }

    func testPreferredTextUsesModeThenCleanupThenVerbatim() {
        let card = Card(
            sourceType: .voice,
            rawText: "raw",
            enhancedText: "clean",
            processedText: "rewritten",
            title: "Priority"
        )
        XCTAssertEqual(card.preferredText, "rewritten")
        card.processedText = nil
        XCTAssertEqual(card.preferredText, "clean")
        card.enhancedText = nil
        XCTAssertEqual(card.preferredText, "raw")
    }

    func testFlowReadyStatePreservesExpiryAcrossProcesses() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let bridge = KeyboardDictationBridge(
            sessionURL: directory.appending(path: "flow-session.json")
        )
        let session = bridge.begin()
        let expiry = Date.now.addingTimeInterval(4 * 60 * 60)

        bridge.update(id: session.id, phase: .readyForCapture, flowExpiresAt: expiry)

        XCTAssertEqual(bridge.load()?.phase, .readyForCapture)
        XCTAssertEqual(bridge.load()?.flowExpiresAt?.timeIntervalSince1970 ?? 0,
                       expiry.timeIntervalSince1970,
                       accuracy: 0.001)
    }

    func testUnicodeTextIsNotAlteredBeforeInsertion() {
        let text = "घर पहुँचकर message करना 😊"
        let card = Card(sourceType: .voice, rawText: text, title: "Unicode")
        XCTAssertEqual(card.preferredText, text)
    }

    func testUniversalCaptureRoutePreservesKeyboardSession() throws {
        let sessionID = UUID()
        let url = try XCTUnwrap(
            URL(string: "https://gottayap.com/capture?keyboardSession=\(sessionID.uuidString)")
        )

        XCTAssertEqual(
            AppRoute.parse(url),
            .capture(autoStart: true, keyboardSessionID: sessionID)
        )
    }

    func testUniversalCaptureRouteRejectsUntrustedHosts() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/capture"))
        XCTAssertNil(AppRoute.parse(url))
    }
}
