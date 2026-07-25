import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    enum Tab: Hashable {
        case stream
        case clipboard
        case search
        case modes
        case settings
    }

    var selectedTab: Tab = .stream
    var isCapturePresented = false
    var captureShouldAutoStart = false
    var keyboardSessionID: UUID?
    var startupError: String?

    init(startupError: String? = nil) {
        self.startupError = startupError
    }

    func presentCapture(autoStart: Bool, keyboardSessionID: UUID? = nil) {
        captureShouldAutoStart = autoStart
        self.keyboardSessionID = keyboardSessionID
        isCapturePresented = true
    }

    func handle(_ route: AppRoute) {
        switch route {
        case .capture(let autoStart, let keyboardSessionID):
            presentCapture(autoStart: autoStart, keyboardSessionID: keyboardSessionID)
        }
    }
}
