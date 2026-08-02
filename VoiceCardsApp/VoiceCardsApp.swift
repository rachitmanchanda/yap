import SwiftData
import SwiftUI

@main
struct VoiceCardsApp: App {
    private let container: ModelContainer
    @State private var appModel: AppModel
    @State private var authModel: AuthModel

    init() {
        let bootstrap: (container: ModelContainer, error: String?)
        do {
            let shared = try SharedModelContainer.make()
            try ModeRepository(context: shared.mainContext).seedBuiltInsIfNeeded()
            bootstrap = (shared, nil)
        } catch {
            // Keep the UI usable for diagnosis instead of crashing when signing or the shared store is broken.
            #if DEBUG
            // `CODE_SIGNING_ALLOWED=NO` builds cannot resolve App Groups by definition. Falling
            // back is expected there and should not cover the design with a false alarm.
            let startupError: String? = error is AppGroupError
                ? nil
                : "Yap opened temporary storage because shared persistence failed: \(error.localizedDescription)"
            #else
            let startupError = "Yap opened temporary storage because shared persistence failed: \(error.localizedDescription)"
            #endif
            bootstrap = (
                try! SharedModelContainer.make(inMemory: true),
                startupError
            )
        }
        container = bootstrap.container
        _appModel = State(initialValue: AppModel(startupError: bootstrap.error))
        _authModel = State(initialValue: AuthModel())
    }

    var body: some Scene {
        WindowGroup {
            AuthGateView(model: authModel) {
                RootView(appModel: appModel)
            }
                .environment(authModel)
                .onOpenURL { url in
                    if let route = AppRoute.parse(url) {
                        appModel.handle(route)
                    }
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    guard let url = activity.webpageURL,
                          let route = AppRoute.parse(url) else { return }
                    appModel.handle(route)
                }
        }
        .modelContainer(container)
    }
}
