import SwiftUI

struct KeyboardCardButton: View {
    let card: Card
    let compact: Bool
    let insert: (String) -> Void

    var body: some View {
        Button {
            insert(card.preferredText)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(card.title)
                    .font(.system(size: compact ? 12 : 14, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                if !compact {
                    Text(card.preferredText)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(YapKeyboardPalette.paper.opacity(0.58))
                        .lineLimit(2)
                }
            }
            .foregroundStyle(YapKeyboardPalette.paper)
            .frame(width: compact ? 100 : 160, alignment: .leading)
            .padding(9)
            .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Paste \(card.title)")
    }
}
