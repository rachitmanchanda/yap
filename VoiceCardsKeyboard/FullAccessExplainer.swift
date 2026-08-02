import SwiftUI

struct FullAccessExplainer: View {
    let fullAccessReported: Bool
    let diagnostic: String?
    let refreshAccess: () -> Void

    var body: some View {
        VStack(spacing: YapSpacing.small) {
            Image(YapKeyboardIcon.lock.assetName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: YapControlMetric.iconLarge, height: YapControlMetric.iconLarge)
                .foregroundStyle(YapKeyboardPalette.clay)
            Text("allow full access to see your yaps")
                .font(YapType.sectionTitle)
            Text("It only lets this keyboard read Yap’s private shared storage. It never records audio or sends what you type.")
                .font(YapType.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(YapKeyboardPalette.mutedInk)
            Text("Settings → General → Keyboard → Keyboards → Yap")
                .font(YapType.metadata)
                .multilineTextAlignment(.center)
            if fullAccessReported {
                Text("Full Access is on, but shared storage is unavailable. Switch keyboards once, then check again.")
                    .font(YapType.metadata)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.orange)
            }
            Button("I enabled it — check again", action: refreshAccess)
                .font(YapType.button)
                .foregroundStyle(YapKeyboardPalette.onStrongFill)
                .padding(.horizontal, YapSpacing.regular)
                .frame(minHeight: YapControlMetric.minimumTouchTarget)
                .background(YapKeyboardPalette.strongFill, in: Capsule())
#if DEBUG
            if let diagnostic {
                Text(diagnostic)
                    .font(.system(.caption2, design: .monospaced))
                    .lineLimit(2)
                    .foregroundStyle(.tertiary)
            }
#endif
        }
        .padding(YapSpacing.regular)
        .foregroundStyle(YapKeyboardPalette.ink)
        .background(YapKeyboardPalette.keyboardPanel, in: RoundedRectangle(cornerRadius: YapRadius.input))
        .overlay(
            RoundedRectangle(cornerRadius: YapRadius.input)
                .stroke(YapKeyboardPalette.outline, lineWidth: 1)
        )
    }
}
