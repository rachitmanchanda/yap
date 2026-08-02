import SwiftUI
import UIKit

struct KeyboardClipboardButton: View {
    let item: ClipboardItem
    let thumbnail: UIImage?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: YapSpacing.xSmall) {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 142, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: YapRadius.chip))
                } else {
                    HStack(spacing: YapSpacing.xSmall) {
                        Image(kindIcon.assetName)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 12, height: 12)
                        Text(item.kind.title)
                    }
                        .font(YapType.metadata)
                    Text(item.displayText)
                        .font(YapType.metadata)
                        .foregroundStyle(YapKeyboardPalette.paper.opacity(0.58))
                        .lineLimit(2)
                }
            }
            .foregroundStyle(YapKeyboardPalette.paper)
            .frame(width: 142, height: 70, alignment: .leading)
            .padding(YapSpacing.small)
            .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: YapRadius.chip))
            .overlay(RoundedRectangle(cornerRadius: YapRadius.chip).stroke(.white.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.kind == .image ? "Copy image" : "Paste \(item.displayText)")
    }

    private var kindIcon: YapKeyboardIcon {
        switch item.kind {
        case .text: .clipboard
        case .url: .externalLink
        case .image: .image
        }
    }
}
