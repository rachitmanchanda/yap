import SwiftUI

struct ModeChip: View {
    let title: String
    let emoji: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let emoji { Text(emoji) }
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
