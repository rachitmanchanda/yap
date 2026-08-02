import AuthenticationServices
import Foundation
import Observation

@MainActor
@Observable
final class AuthModel {
    enum State: Equatable {
        case loading
        case signedOut
        case signingIn
        case signedIn(AuthSession)
    }

    private(set) var state: State = .loading
    private(set) var providers = AuthProviderAvailability(apple: true, google: false)
    private(set) var isBypassed = false
    var errorMessage: String?

    private let service = SupabaseAuthService()
    private let store = AuthSessionStore()
    #if DEBUG
    private let bypassDefaults = UserDefaults(suiteName: AppGroup.identifier)
    private static let bypassKey = "temporaryAuthenticationBypass"
    #endif

    var currentSession: AuthSession? {
        guard case .signedIn(let session) = state else { return nil }
        return session
    }

    var userEmail: String? {
        currentSession?.user?.email
    }

    func restore() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-resetLocalAuthentication") {
            bypassDefaults?.set(false, forKey: Self.bypassKey)
            AppPreferences.hasCompletedOnboarding = false
            state = .signedOut
            return
        } else if ProcessInfo.processInfo.arguments.contains("-uiTestBypassAuthentication") {
            bypassSignIn()
            return
        } else if bypassDefaults?.bool(forKey: Self.bypassKey) == true {
            bypassSignIn()
            return
        }
        #endif
        do {
            guard var session = try store.load() else {
                state = .signedOut
                return
            }
            if session.needsRefresh {
                session = try await service.refresh(session)
            } else if session.user == nil {
                let user = try await service.user(for: session)
                session = AuthSession(
                    accessToken: session.accessToken,
                    refreshToken: session.refreshToken,
                    tokenType: session.tokenType,
                    expiresAt: session.expiresAt,
                    user: user
                )
            }
            try store.save(session)
            state = .signedIn(session)
        } catch let error as KeychainStoreError where error.isUnavailableInCurrentProcess {
            // Unsigned Simulator and UI-test builds can lack Keychain entitlements. Treat that as
            // an empty session instead of presenting a misleading authentication failure.
            state = .signedOut
        } catch {
            try? store.save(nil)
            errorMessage = error.localizedDescription
            state = .signedOut
        }
    }

    func signIn(with provider: AuthProvider) async {
        guard providers.contains(provider) else {
            errorMessage = "\(provider.displayName) is not enabled in Supabase yet."
            return
        }
        state = .signingIn
        do {
            let session = try await service.signIn(with: provider)
            do {
                try store.save(session)
            } catch let error as KeychainStoreError where error.isUnavailableInCurrentProcess {
                #if DEBUG
                // Xcode can launch an unsigned Simulator build without a Keychain entitlement.
                // Keep that authenticated session in memory so UI work is not blocked; signed
                // device and release builds still require Keychain-backed persistence.
                state = .signedIn(session)
                return
                #else
                throw error
                #endif
            }
            state = .signedIn(session)
        } catch let error as ASWebAuthenticationSessionError
            where error.code == .canceledLogin {
            state = .signedOut
        } catch let error as ASAuthorizationError where error.code == .canceled {
            state = .signedOut
        } catch {
            errorMessage = error.localizedDescription
            state = .signedOut
        }
    }

    #if DEBUG
    /// This temporary local-only escape hatch keeps development unblocked while provider setup finishes.
    func bypassSignIn() {
        bypassDefaults?.set(true, forKey: Self.bypassKey)
        // Development bypasses exercise the product itself, not the production onboarding.
        AppPreferences.hasCompletedOnboarding = true
        isBypassed = true
        state = .signedIn(
            AuthSession(
                accessToken: "",
                refreshToken: "",
                tokenType: "bypass",
                expiresAt: .distantFuture,
                user: AuthUser(id: "local-bypass", email: nil)
            )
        )
    }
    #endif

    func signOut() async {
        if let session = currentSession, !isBypassed {
            try? await service.signOut(session)
        }
        clearLocalSession()
    }

    /// Deletes the remote account before erasing local data so a network failure is safely retryable.
    func deleteAccount(removingLocalData: () throws -> Void) async throws {
        guard let session = currentSession else { return }
        if !isBypassed {
            try await service.deleteAccount(session)
        }

        var cleanupError: Error?
        do {
            try removingLocalData()
        } catch {
            cleanupError = error
        }
        clearLocalSession()
        if let cleanupError {
            throw cleanupError
        }
    }

    private func clearLocalSession() {
        try? store.save(nil)
        #if DEBUG
        bypassDefaults?.set(false, forKey: Self.bypassKey)
        #endif
        isBypassed = false
        state = .signedOut
    }
}
