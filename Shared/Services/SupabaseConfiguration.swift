import Foundation

enum SupabaseConfiguration {
    static let projectURL = URL(string: "https://pqbnigrqvihazlpvslqd.supabase.co")!

    /// Supabase publishable keys are designed to ship in clients; privileged keys remain server-only.
    static let publishableKey = "sb_publishable_nMN-4E-hdhtJygbV2p9fEQ_hq3_8BOS"
    static let callbackURL = URL(string: "voicecards://auth-callback")!
    static let callbackScheme = "voicecards"

    static var authURL: URL {
        projectURL.appending(path: "auth/v1")
    }

    static func functionURL(named name: String) -> URL {
        projectURL.appending(path: "functions/v1/\(name)")
    }
}
