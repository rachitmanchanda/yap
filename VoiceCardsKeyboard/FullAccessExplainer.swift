import SwiftUI

struct FullAccessExplainer: View {
    let fullAccessReported: Bool
    let diagnostic: String?
    let refreshAccess: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .font(.title2)
                .foregroundStyle(YapKeyboardPalette.acid)
            Text("allow full access to see your yaps")
                .font(.system(size: 16, weight: .black, design: .rounded))
            Text("It only lets this keyboard read Yap’s private shared storage. It never records audio or sends what you type.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(YapKeyboardPalette.paper.opacity(0.58))
            Text("Settings → General → Keyboard → Keyboards → Yap")
                .font(.caption2.weight(.medium))
                .multilineTextAlignment(.center)
            if fullAccessReported {
                Text("Full Access is on, but shared storage is unavailable. Switch keyboards once, then check again.")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.orange)
            }
            Button("I enabled it — check again", action: refreshAccess)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(YapKeyboardPalette.ink)
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(YapKeyboardPalette.acid, in: Capsule())
#if DEBUG
            if let diagnostic {
                Text(diagnostic)
                    .font(.system(size: 9, design: .monospaced))
                    .lineLimit(2)
                    .foregroundStyle(.tertiary)
            }
#endif
        }
        .padding()
        .foregroundStyle(YapKeyboardPalette.paper)
        .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.18), lineWidth: 1))
    }
}
