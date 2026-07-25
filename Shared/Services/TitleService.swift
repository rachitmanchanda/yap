import Foundation

struct TitleService: Sendable {
    let rewriteService: any RewriteService

    func title(for text: String) async -> String {
        (try? await rewriteService.title(for: text))?.nilIfBlank ?? text.firstWordsTitle()
    }
}
