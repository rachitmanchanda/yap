import XCTest

@MainActor
final class VoiceCardsUITests: XCTestCase {
    func testAuthenticationGateAppears() {
        let app = XCUIApplication()
        app.launchArguments.append("-resetLocalAuthentication")
        app.launch()
        XCTAssertTrue(app.staticTexts["say it once.\npaste it anywhere."].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["sign in with apple"].exists)
        XCTAssertTrue(app.staticTexts["your clipboard, but it has ears."].exists)
    }

    func testTenLogoTapsBypassAuthentication() {
        let app = XCUIApplication()
        app.launchArguments.append("-resetLocalAuthentication")
        app.launch()
        let logo = app.descendants(matching: .any)["Yap logo"]
        XCTAssertTrue(logo.waitForExistence(timeout: 8))

        for _ in 0..<10 where !app.buttons["Start recording"].exists {
            logo.tap()
        }

        XCTAssertTrue(app.buttons["Start recording"].waitForExistence(timeout: 5))
    }

    func testKeyboardCaptureShowsReturnCoachAfterMicrophoneStarts() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-uiTestBypassAuthentication",
            "-uiTestKeyboardHandoffCoach"
        ]
        app.launchEnvironment["YAP_UI_TEST_KEYBOARD_HANDOFF"] = "1"

        addUIInterruptionMonitor(withDescription: "Microphone permission") { alert in
            let allowButton = alert.buttons["Allow"]
            guard allowButton.exists else { return false }
            allowButton.tap()
            return true
        }
        addUIInterruptionMonitor(withDescription: "Paste permission") { alert in
            let denyButton = alert.buttons["Don’t Allow Paste"]
            guard denyButton.exists else { return false }
            denyButton.tap()
            return true
        }

        app.launch()
        // The first tap lets XCTest service a paste prompt; the second does the same for mic.
        app.tap()
        app.tap()

        XCTAssertTrue(
            app.otherElements["keyboardReturnCoach"].waitForExistence(timeout: 8)
        )
        XCTAssertTrue(app.staticTexts["mic is on"].exists)
        XCTAssertTrue(app.staticTexts["Swipe right along the bottom edge"].exists)

        app.buttons["Cancel"].tap()
    }
}
