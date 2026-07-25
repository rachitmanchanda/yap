import XCTest
@testable import VoiceCards

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
}
