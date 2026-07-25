import UIKit

@MainActor
protocol ClipboardWriting {
    func copy(_ text: String)
}

struct SystemClipboardWriter: ClipboardWriting {
    func copy(_ text: String) {
        UIPasteboard.general.string = text
        let hash = ClipboardFingerprint.make(kind: .text, data: Data(text.utf8))
        ClipboardWriteMarker.mark(hash: hash, changeCount: UIPasteboard.general.changeCount)
    }
}
