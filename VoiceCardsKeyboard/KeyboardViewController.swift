import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController {
    private var hostingController: UIHostingController<KeyboardView>?
    private let model = KeyboardModel()
    private var dictationPollingTask: Task<Void, Never>?

    override func viewDidLoad() {
        super.viewDidLoad()
        // Tells iOS this keyboard supplies its own dictation handoff instead of presenting a
        // second, visually competing system dictation affordance.
        hasDictationKey = true
        let root = KeyboardView(
            model: model,
            insert: { [weak self] text in self?.textDocumentProxy.insertText(text) },
            nextKeyboard: { [weak self] in self?.advanceToNextInputMode() },
            requestStop: { [weak self] in self?.model.requestStop() },
            cancelDictation: { [weak self] in self?.model.cancelDictation() },
            insertOriginal: { [weak self] in self?.model.insertOriginal() },
            applyMode: { [weak self] modeID in self?.model.requestMode(modeID) },
            refreshAccess: { [weak self] in self?.refreshAccess() }
        )
        let hosting = UIHostingController(rootView: root)
        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 270)
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
}
