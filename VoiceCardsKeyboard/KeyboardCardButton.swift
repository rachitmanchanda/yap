import SwiftUI

struct KeyboardCardButton: View {
    let card: Card
    let compact: Bool
    let insert: (String) -> Void

    var body: some View {
        Button {
            insert(card.preferredText)
        } label: {
            VStack(alignment: .leading, spacing: YapSpacing.xSmall) {
                Text(card.title)
                    .font(compact ? YapType.metadata : YapType.label)
                    .lineLimit(1)
                if !compact {
                    Text(card.preferredText)
                        .font(YapType.metadata)
                        .foregroundStyle(YapKeyboardPalette.paper.opacity(0.58))
                        .lineLimit(2)
                }
            }
            .foregroundStyle(YapKeyboardPalette.paper)
            .frame(width: compact ? 100 : 160, alignment: .leading)
            .padding(YapSpacing.small)
            .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: YapRadius.chip))
            .overlay(RoundedRectangle(cornerRadius: YapRadius.chip).stroke(.white.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Paste \(card.title)")
    }
}
