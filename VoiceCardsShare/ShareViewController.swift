import SwiftData
import SwiftUI
import UIKit

@MainActor
final class ShareViewController: UIViewController {
    private var host: UIHostingController<ShareConfirmationView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        show(.saving)
        Task { await ingest() }
    }

    private func ingest() async {
        do {
            let payload = try await SharedItemExtractor().extract(from: extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            let text = payload.rawText
            let card = Card(
                sourceType: .share,
                rawText: text,
                title: text.firstWordsTitle()
            )
            let container = try SharedModelContainer.make()
            try CardRepository(context: container.mainContext).insert(card)
            show(.saved(card.title))
        } catch {
            show(.failed(error.localizedDescription))
        }
    }

    private func show(_ state: ShareConfirmationView.State) {
        let view = ShareConfirmationView(state: state) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
        if let host {
            host.rootView = view
            return
        }
        let host = UIHostingController(rootView: view)
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: self.view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        ])
        host.didMove(toParent: self)
        self.host = host
    }
}
