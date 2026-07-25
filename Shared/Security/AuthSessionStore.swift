import Foundation

struct AuthSessionStore: Sendable {
    private let keychain = KeychainStore(service: "com.APP.VoiceCards.supabase-auth")
    private let account = "current-session"

    func load() throws -> AuthSession? {
        guard let encoded = try keychain.string(for: account),
              let data = Data(base64Encoded: encoded) else {
            return nil
        }
        return try JSONDecoder().decode(AuthSession.self, from: data)
    }

    func save(_ session: AuthSession?) throws {
        guard let session else {
            try keychain.set(nil, for: account)
            return
        }
        let data = try JSONEncoder().encode(session)
        try keychain.set(data.base64EncodedString(), for: account)
    }
}
