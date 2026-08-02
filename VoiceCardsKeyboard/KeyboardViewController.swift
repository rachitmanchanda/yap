import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController {
    private var hostingController: UIHostingController<KeyboardView>?
    private let model = KeyboardModel()
    private var dictationPollingTask: Task<Void, Never>?

    private let yapSurface = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 23.0 / 255.0, green: 23.0 / 255.0, blue: 25.0 / 255.0, alpha: 1)
        }
        return UIColor(red: 221.0 / 255.0, green: 224.0 / 255.0, blue: 228.0 / 255.0, alpha: 1)
    }

    private let systemShelfSurface = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 20.0 / 255.0, green: 20.0 / 255.0, blue: 22.0 / 255.0, alpha: 1)
        }
        return UIColor(red: 217.0 / 255.0, green: 220.0 / 255.0, blue: 226.0 / 255.0, alpha: 1)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Tells iOS this keyboard supplies its own dictation handoff instead of presenting a
        // second, visually competing system dictation affordance.
        hasDictationKey = true
        // iOS lays a light material over the rounded keyboard host. This slightly darker
        // backing compensates for that material in light mode; the dynamic counterpart
        // blends into the system shelf in dark mode.
        view.backgroundColor = systemShelfSurface
        inputView?.backgroundColor = systemShelfSurface
        let root = KeyboardView(
            model: model,
            insert: { [weak self] text in self?.textDocumentProxy.insertText(text) },
            requestStart: { [weak self] in self?.model.requestStart() },
            requestStop: { [weak self] in self?.model.requestStop() },
            cancelDictation: { [weak self] in self?.model.cancelDictation() },
            insertOriginal: { [weak self] in self?.model.insertOriginal() },
            applyMode: { [weak self] modeID in self?.model.requestMode(modeID) },
            requestForegroundHandoff: { [weak self] in self?.startUniversalLinkHandoff() },
            refreshAccess: { [weak self] in self?.refreshAccess() }
        )
        let hosting = UIHostingController(rootView: root)
        hosting.view.backgroundColor = yapSurface
        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting.view)
        let preferredHeight = view.heightAnchor.constraint(equalToConstant: 329)
        preferredHeight.priority = .defaultHigh
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 270),
            preferredHeight
        ])
        hosting.didMove(toParent: self)
        hostingController = hosting
        refreshAccess()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshAccess()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        refreshAccess()
        model.captureClipboardIfChanged(force: true)
        startDictationPolling()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        dictationPollingTask?.cancel()
        dictationPollingTask = nil
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        refreshAccess()
    }

    private func refreshAccess() {
        model.updateAccess(hasFullAccess)
        insertCompletedDictationIfNeeded()
    }

    /// App Group defaults have no cross-process notification, so a lightweight poll lets a
    /// transcription insert itself while the user remains in the same text field.
    private func startDictationPolling() {
        dictationPollingTask?.cancel()
        dictationPollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self else { return }
                model.refreshDictationSession()
                model.captureClipboardIfChanged()
                insertCompletedDictationIfNeeded()
            }
        }
    }

    private func insertCompletedDictationIfNeeded() {
        if let text = model.takeCompletedText() {
            textDocumentProxy.insertText(text)
        }
    }

    /// iOS 17 predates `OpenURLIntent`, but an extension context can still ask the system to
    /// open the same verified universal link. Custom URL schemes remain deliberately unused.
    private func startUniversalLinkHandoff() {
        let session = KeyboardDictationBridge().begin()
        model.refreshDictationSession()
        let url = KeyboardDictationLink.captureURL(sessionID: session.id)
        guard let extensionContext else {
            model.failHandoff(sessionID: session.id)
            return
        }
        extensionContext.open(url) { [weak self] didOpen in
            guard !didOpen else { return }
            Task { @MainActor [weak self] in
                self?.model.failHandoff(sessionID: session.id)
            }
        }
    }
}
