import SwiftUI

struct ShareConfirmationView: View {
    enum State {
        case saving
        case saved(String)
        case failed(String)
    }

    let state: State
    let close: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            switch state {
            case .saving:
                ProgressView("Saving to Yap…")
            case .saved(let title):
                Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(.green)
                Text(title).font(.headline).lineLimit(2)
                Button("Done", action: close).buttonStyle(.borderedProminent)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundStyle(.orange)
                Text(message).multilineTextAlignment(.center)
                Button("Close", action: close).buttonStyle(.bordered)
            }
        }
        .padding(28)
    }
}
