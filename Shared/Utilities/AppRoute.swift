import Foundation

enum AppRoute: Hashable {
    case capture(autoStart: Bool, keyboardSessionID: UUID?)

    static func parse(_ url: URL) -> AppRoute? {
        let isLegacyCaptureURL = ["voicecards", "app"].contains(url.scheme?.lowercased())
            && url.host?.lowercased() == "capture"
        let isUniversalCaptureURL = url.scheme?.lowercased() == "https"
            && url.host?.lowercased() == "gottayap.com"
            && url.path == "/capture"
        guard isLegacyCaptureURL || isUniversalCaptureURL else { return nil }
        let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "keyboardSession" })?
            .value
            .flatMap(UUID.init(uuidString:))
        return .capture(autoStart: true, keyboardSessionID: id)
    }
}
