import XCTest
@testable import VoiceCards

final class ShareItemExtractorTests: XCTestCase {
    func testSharedURLIsStoredVerbatim() {
        let url = "https://example.com/path?q=voice%20card"
        let card = Card(sourceType: .share, rawText: url, title: url.firstWordsTitle())
        XCTAssertEqual(card.rawText, url)
        XCTAssertEqual(card.sourceType, .share)
    }
}
