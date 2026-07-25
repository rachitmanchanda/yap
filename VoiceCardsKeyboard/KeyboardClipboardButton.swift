import SwiftUI
import UIKit

struct KeyboardClipboardButton: View {
    let item: ClipboardItem
    let thumbnail: UIImage?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 142, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Label(item.kind.title, systemImage: item.kind.systemImage)
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                    Text(item.displayText)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(YapKeyboardPalette.paper.opacity(0.58))
                        .lineLimit(2)
                }
            }
            .foregroundStyle(YapKeyboardPalette.paper)
            .frame(width: 142, height: 70, alignment: .leading)
            .padding(8)
            .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.kind == .image ? "Copy image" : "Paste \(item.displayText)")
    }
}
