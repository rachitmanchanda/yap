import Foundation

protocol APIKeyProviding: Sendable {
    func openAIKey() throws -> String?
    func anthropicKey() throws -> String?
    func sarvamKey() throws -> String?
    func deepSeekKey() throws -> String?
}

struct APIKeyStore: APIKeyProviding, Sendable {
    private let keychain = KeychainStore(service: "com.rachitmanchanda.yap.beta.api-keys")

    func openAIKey() throws -> String? { try keychain.string(for: "openai") }
    func anthropicKey() throws -> String? { try keychain.string(for: "anthropic") }
    func sarvamKey() throws -> String? { try keychain.string(for: "sarvam") }
    func deepSeekKey() throws -> String? { try keychain.string(for: "deepseek") }
    func setOpenAIKey(_ value: String?) throws { try keychain.set(value, for: "openai") }
    func setAnthropicKey(_ value: String?) throws { try keychain.set(value, for: "anthropic") }
    func setSarvamKey(_ value: String?) throws { try keychain.set(value, for: "sarvam") }
    func setDeepSeekKey(_ value: String?) throws { try keychain.set(value, for: "deepseek") }

    func removeAll() throws {
        try setOpenAIKey(nil)
        try setAnthropicKey(nil)
        try setSarvamKey(nil)
        try setDeepSeekKey(nil)
    }
}
