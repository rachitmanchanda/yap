import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

struct AuthProviderAvailability: Sendable {
    let apple: Bool
    let google: Bool

    func contains(_ provider: AuthProvider) -> Bool {
        switch provider {
        case .apple: apple
        case .google: google
        }
    }
}

enum SupabaseAuthError: LocalizedError {
    case invalidCallback
    case providerError(String)
    case missingRefreshToken
    case missingWindow
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .invalidCallback: "Supabase returned an invalid authentication callback."
        case .providerError(let message): message
        case .missingRefreshToken: "The saved session cannot be refreshed. Please sign in again."
        case .missingWindow: "Yap could not present the sign-in window."
        case .malformedResponse: "Supabase returned an unexpected authentication response."
        }
    }
}

@MainActor
final class SupabaseAuthService: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var webSession: ASWebAuthenticationSession?
    private var appleContinuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?

    func providerAvailability() async throws -> AuthProviderAvailability {
        var request = URLRequest(url: SupabaseConfiguration.authURL.appending(path: "settings"))
        request.setValue(SupabaseConfiguration.publishableKey, forHTTPHeaderField: "apikey")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let settings = try JSONDecoder().decode(AuthSettingsResponse.self, from: data)
        return AuthProviderAvailability(
            apple: settings.external.apple,
            google: settings.external.google
        )
    }

    func signIn(with provider: AuthProvider) async throws -> AuthSession {
        if provider == .apple {
            return try await signInWithApple()
        }
        return try await signInWithOAuth(provider)
    }

    /// Native Sign in with Apple avoids the rotating OAuth secret required by Apple's web flow.
    private func signInWithApple() async throws -> AuthSession {
        let nonce = UUID().uuidString
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = SHA256.hash(data: Data(nonce.utf8))
            .map { String(format: "%02x", $0) }
            .joined()

        let credential = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>) in
            appleContinuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
        guard let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8) else {
            throw SupabaseAuthError.malformedResponse
        }
        return try await exchangeAppleToken(identityToken, nonce: nonce)
    }

    private func signInWithOAuth(_ provider: AuthProvider) async throws -> AuthSession {
        var components = URLComponents(
            url: SupabaseConfiguration.authURL.appending(path: "authorize"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "provider", value: provider.rawValue),
            URLQueryItem(name: "redirect_to", value: SupabaseConfiguration.callbackURL.absoluteString)
        ]
        guard let url = components.url else { throw SupabaseAuthError.invalidCallback }

        let callbackURL = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: SupabaseConfiguration.callbackScheme
            ) { [weak self] callbackURL, error in
                Task { @MainActor in
                    self?.webSession = nil
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let callbackURL {
                        continuation.resume(returning: callbackURL)
                    } else {
                        continuation.resume(throwing: SupabaseAuthError.invalidCallback)
                    }
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            webSession = session
            guard session.start() else {
                webSession = nil
                continuation.resume(throwing: SupabaseAuthError.missingWindow)
                return
            }
        }
        return try await session(from: callbackURL)
    }

    private func exchangeAppleToken(_ identityToken: String, nonce: String) async throws -> AuthSession {
        var components = URLComponents(
            url: SupabaseConfiguration.authURL.appending(path: "token"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "grant_type", value: "id_token")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        addStandardHeaders(to: &request)
        request.httpBody = try JSONEncoder().encode(
            IDTokenRequest(provider: "apple", idToken: identityToken, nonce: nonce)
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try decodeTokenResponse(data)
    }

    func refresh(_ session: AuthSession) async throws -> AuthSession {
        guard session.refreshToken.nilIfBlank != nil else { throw SupabaseAuthError.missingRefreshToken }
        var components = URLComponents(
            url: SupabaseConfiguration.authURL.appending(path: "token"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        addStandardHeaders(to: &request)
        request.httpBody = try JSONEncoder().encode(RefreshRequest(refreshToken: session.refreshToken))
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try decodeTokenResponse(data)
    }

    func user(for session: AuthSession) async throws -> AuthUser {
        var request = URLRequest(url: SupabaseConfiguration.authURL.appending(path: "user"))
        request.setValue(SupabaseConfiguration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(AuthUser.self, from: data)
    }

    func signOut(_ session: AuthSession) async throws {
        var request = URLRequest(url: SupabaseConfiguration.authURL.appending(path: "logout"))
        request.httpMethod = "POST"
        request.setValue(SupabaseConfiguration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
    }

    /// Account deletion stays on the server because only Supabase's service role may remove users.
    func deleteAccount(_ session: AuthSession) async throws {
        var request = URLRequest(url: SupabaseConfiguration.functionURL(named: "delete-account"))
        request.httpMethod = "POST"
        request.setValue(SupabaseConfiguration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }

    private func session(from callbackURL: URL) async throws -> AuthSession {
        let values = callbackValues(from: callbackURL)
        if let message = values["error_description"] ?? values["error"] {
            throw SupabaseAuthError.providerError(message.replacingOccurrences(of: "+", with: " "))
        }
        guard let accessToken = values["access_token"],
              let refreshToken = values["refresh_token"] else {
            throw SupabaseAuthError.invalidCallback
        }
        let expiresIn = TimeInterval(values["expires_in"] ?? "") ?? 3_600
        let partial = AuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            tokenType: values["token_type"] ?? "bearer",
            expiresAt: .now.addingTimeInterval(expiresIn),
            user: nil
        )
        let user = try await user(for: partial)
        return AuthSession(
            accessToken: partial.accessToken,
            refreshToken: partial.refreshToken,
            tokenType: partial.tokenType,
            expiresAt: partial.expiresAt,
            user: user
        )
    }

    private func callbackValues(from url: URL) -> [String: String] {
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let fragmentItems = URLComponents(string: "?\(url.fragment ?? "")")?.queryItems ?? []
        return (queryItems + fragmentItems).reduce(into: [:]) { values, item in
            if let value = item.value {
                values[item.name] = value
            }
        }
    }

    private func decodeTokenResponse(_ data: Data) throws -> AuthSession {
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        return AuthSession(
            accessToken: token.accessToken,
            refreshToken: token.refreshToken,
            tokenType: token.tokenType,
            expiresAt: .now.addingTimeInterval(TimeInterval(token.expiresIn)),
            user: token.user
        )
    }

    private func addStandardHeaders(to request: inout URLRequest) {
        request.setValue(SupabaseConfiguration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw SupabaseAuthError.malformedResponse }
        guard (200..<300).contains(http.statusCode) else {
            let error = try? JSONDecoder().decode(AuthErrorResponse.self, from: data)
            throw SupabaseAuthError.providerError(
                error?.message ?? error?.errorDescription ?? "Authentication failed (HTTP \(http.statusCode))."
            )
        }
    }
}

extension SupabaseAuthService:
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding
{
    nonisolated func presentationAnchor(
        for controller: ASAuthorizationController
    ) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task { @MainActor in
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                appleContinuation?.resume(throwing: SupabaseAuthError.malformedResponse)
                appleContinuation = nil
                return
            }
            appleContinuation?.resume(returning: credential)
            appleContinuation = nil
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            appleContinuation?.resume(throwing: error)
            appleContinuation = nil
        }
    }
}

private struct AuthSettingsResponse: Decodable {
    struct External: Decodable {
        let apple: Bool
        let google: Bool
    }
    let external: External
}

private struct RefreshRequest: Encodable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

private struct IDTokenRequest: Encodable {
    let provider: String
    let idToken: String
    let nonce: String

    enum CodingKeys: String, CodingKey {
        case provider, nonce
        case idToken = "id_token"
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Int
    let user: AuthUser?

    enum CodingKeys: String, CodingKey {
        case user
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
    }
}

private struct AuthErrorResponse: Decodable {
    let message: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case message
        case errorDescription = "error_description"
    }
}
