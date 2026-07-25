import Foundation
import XCTest
@testable import VoiceCards

final class AuthSessionTests: XCTestCase {
    func testSessionRefreshesBeforeItActuallyExpires() {
        let expiringSession = AuthSession(
            accessToken: "access",
            refreshToken: "refresh",
            tokenType: "bearer",
            expiresAt: .now.addingTimeInterval(30),
            user: nil
        )
        let freshSession = AuthSession(
            accessToken: "access",
            refreshToken: "refresh",
            tokenType: "bearer",
            expiresAt: .now.addingTimeInterval(3_600),
            user: nil
        )

        XCTAssertTrue(expiringSession.needsRefresh)
        XCTAssertFalse(freshSession.needsRefresh)
    }
}
