import Foundation

struct AuthUser: Codable, Equatable, Sendable {
    let id: String
    let email: String?
}

struct AuthSession: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresAt: Date
    let user: AuthUser?

    var needsRefresh: Bool {
        expiresAt.timeIntervalSinceNow < 60
    }
}

enum AuthProvider: String, CaseIterable, Sendable {
    case apple
    case google

    var displayName: String {
        rawValue.capitalized
    }
}
