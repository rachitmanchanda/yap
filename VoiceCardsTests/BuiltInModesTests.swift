import XCTest
@testable import VoiceCards

@MainActor
final class BuiltInModesTests: XCTestCase {
    func testStableUniqueBuiltInIdentifiers() {
        let definitions = BuiltInModes.definitions
        XCTAssertEqual(definitions.count, 5)
        XCTAssertEqual(Set(definitions.map(\.id)).count, definitions.count)
        XCTAssertEqual(
            Set(definitions.map(\.id)),
            ["formal", "casual", "roast", "rizz", "hindi-household"]
        )
    }

    func testPromptsDemandRewriteOnlyAndPreservation() {
        for mode in BuiltInModes.definitions {
            XCTAssertTrue(mode.prompt.localizedCaseInsensitiveContains("return only"))
            XCTAssertTrue(
                mode.prompt.localizedCaseInsensitiveContains("preserve")
                    || mode.id == "hindi-household"
            )
        }
    }

    func testSettingsRefreshIncludesNewCustomModeAndDeletionClearsDefault() throws {
        let previousDefaultModeID = AppPreferences.defaultModeID
        defer { AppPreferences.defaultModeID = previousDefaultModeID }

        let container = try SharedModelContainer.make(inMemory: true)
        let settings = SettingsModel(context: container.mainContext)
        let modes = ModesModel(context: container.mainContext)

        try modes.save(
            id: nil,
            name: "My voice",
            emoji: "✨",
            prompt: "Preserve my tone while fixing obvious mistakes."
        )
        settings.reloadModes()

        let customMode = try XCTUnwrap(settings.modes.first { !$0.isBuiltIn })
        XCTAssertEqual(customMode.name, "My voice")

        settings.setDefaultMode(customMode.id)
        XCTAssertEqual(AppPreferences.defaultModeID, customMode.id)
        XCTAssertEqual(
            SettingsModel(context: container.mainContext).defaultModeID,
            customMode.id
        )

        modes.delete(customMode)

        XCTAssertNil(AppPreferences.defaultModeID)
    }
}
