import XCTest

@MainActor
final class VoiceCardsUITests: XCTestCase {
    func testAuthenticationGateAppears() {
        let app = XCUIApplication()
        app.launchArguments.append("-resetLocalAuthentication")
        app.launch()
        XCTAssertTrue(app.staticTexts["yappers yap. not type."].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["continue with apple"].exists)
        XCTAssertTrue(app.staticTexts["yap, roast, inform 5x faster."].exists)
    }

    func testTenLogoTapsBypassAuthentication() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-resetLocalAuthentication",
            "-uiTestTenTapBypass"
        ]
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
        XCTAssertTrue(app.staticTexts["listening"].exists)
        XCTAssertTrue(
            app.staticTexts["swipe right along the bottom edge to go back"].exists
        )

        app.buttons["Stop recording"].tap()
    }

    func testModeEditorKeepsSaveActionVisible() {
        let app = XCUIApplication()
        app.launchArguments.append("-uiTestBypassAuthentication")
        app.launch()

        XCTAssertTrue(app.buttons["Open settings"].waitForExistence(timeout: 8))
        app.buttons["Open settings"].tap()

        XCTAssertTrue(app.staticTexts["rewrite modes"].waitForExistence(timeout: 5))
        app.staticTexts["rewrite modes"].tap()

        XCTAssertTrue(app.buttons["New mode"].waitForExistence(timeout: 5))
        app.buttons["New mode"].tap()

        let saveButton = app.buttons["saveModeButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["importModeFromChatGPT"].exists)
        XCTAssertTrue(app.buttons["importModeFromClaude"].exists)

        app.textFields["modeNameField"].tap()
        app.textFields["modeNameField"].typeText("clearer")
        app.textViews["modePromptEditor"].tap()
        app.textViews["modePromptEditor"].typeText("Fix typos while preserving my meaning and tone.")

        XCTAssertTrue(saveButton.isEnabled)
        XCTAssertTrue(app.buttons["keyboardSaveModeButton"].isHittable)
    }

    func testEnhancementProgressFillsCaptureSheet() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-uiTestBypassAuthentication",
            "-uiTestEnhancementProgress"
        ]
        app.launch()

        let progress = app.otherElements["captureProgressScreen"]
        XCTAssertTrue(progress.waitForExistence(timeout: 8))
        XCTAssertGreaterThan(
            progress.frame.width,
            app.frame.width * 0.9,
            "The aurora must fill the capture sheet instead of using its portrait intrinsic size."
        )
    }

    func testDesignSystemGallerySupportsLargeText() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-uiTestBypassAuthentication",
            "-uiTestDesignSystemGallery",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityL"
        ]
        app.launch()

        let gallery = app.scrollViews["yapComponentGallery"]
        XCTAssertTrue(gallery.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["ui quality"].exists)

        let primaryAction = app.buttons["primary action"]
        XCTAssertTrue(primaryAction.exists)
        for _ in 0..<4 where !primaryAction.isHittable {
            gallery.swipeUp()
        }
        XCTAssertTrue(primaryAction.isHittable)

        let secondaryAction = app.buttons["secondary action"]
        XCTAssertTrue(secondaryAction.exists)
        XCTAssertTrue(secondaryAction.isHittable)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Yap component gallery — accessibility large"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
