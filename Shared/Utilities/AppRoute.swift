import Foundation

enum AppRoute: Hashable {
    case capture(autoStart: Bool, keyboardSessionID: UUID?)

    static func parse(_ url: URL) -> AppRoute? {
        guard ["voicecards", "app"].contains(url.scheme), url.host == "capture" else { return nil }
        let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "keyboardSession" })?
            .value
            .flatMap(UUID.init(uuidString:))
        return .capture(autoStart: true, keyboardSessionID: id)
    }
}
