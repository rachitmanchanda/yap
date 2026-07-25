import SwiftUI

struct AuthGateView<Content: View>: View {
    @Bindable var model: AuthModel
    @ViewBuilder let content: () -> Content

    @State private var hasCompletedOnboarding = AppPreferences.hasCompletedOnboarding

    var body: some View {
        Group {
            switch model.state {
            case .loading:
                YapAtmosphereScreen(atmosphere: .welcome) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(YapPalette.paper)
                        .accessibilityLabel("Connecting securely")
                }
            case .signedIn where hasCompletedOnboarding || model.isBypassed:
                content()
            case .signedOut, .signingIn, .signedIn:
                YapOnboardingFlowView(
                    authModel: model,
                    initiallyAuthenticated: model.currentSession != nil
                ) {
                    hasCompletedOnboarding = true
                }
            }
        }
        .task {
            hasCompletedOnboarding = AppPreferences.hasCompletedOnboarding
            if model.state == .loading {
                await model.restore()
            }
        }
        .alert("Sign in failed", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}
