import SwiftData
import XCTest
@testable import VoiceCards

@MainActor
final class CardRepositoryTests: XCTestCase {
    func testCardsPersistNewestFirstAndSearchAllTextFields() throws {
        let container = try SharedModelContainer.make(inMemory: true)
        let repository = CardRepository(context: container.mainContext)
        let older = Card(
            createdAt: Date(timeIntervalSince1970: 1),
            sourceType: .manualPaste,
            rawText: "Home address is 12 Lake Road",
            title: "Home address"
        )
        let newer = Card(
            createdAt: Date(timeIntervalSince1970: 2),
            sourceType: .voice,
            rawText: "Call Rachit",
            enhancedText: "Call Rachit tomorrow",
            title: "Call reminder"
        )
        try repository.insert(older)
        try repository.insert(newer)

        XCTAssertEqual(try repository.recent().map(\.id), [newer.id, older.id])
        XCTAssertEqual(try repository.search("address").first?.id, older.id)
        XCTAssertEqual(try repository.search("tomorrow").first?.id, newer.id)
    }

    func testPinAndDelete() throws {
        let container = try SharedModelContainer.make(inMemory: true)
        let repository = CardRepository(context: container.mainContext)
        let card = Card(sourceType: .share, rawText: "https://example.com", title: "Example link")
        try repository.insert(card)
        try repository.togglePinned(card)
        XCTAssertTrue(card.pinned)
        try repository.delete(card)
        XCTAssertTrue(try repository.recent().isEmpty)
    }
}
