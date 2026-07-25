import SwiftUI

struct CardPreview: View {
    let card: Card

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: card.sourceType.systemImage)
                    .foregroundStyle(.tint)
                Text(card.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if card.pinned {
                    Image(systemName: "pin.fill")
                        .foregroundStyle(.orange)
                }
            }
            Text(card.preferredText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack {
                Text(RelativeDateFormatter.string(from: card.createdAt))
                if let mode = card.modeApplied {
                    Text(mode.replacingOccurrences(of: "-", with: " ").capitalized)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.tint.opacity(0.12), in: Capsule())
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
