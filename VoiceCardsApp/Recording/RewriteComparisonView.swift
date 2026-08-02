import SwiftUI

struct RewriteComparisonView: View {
    let original: String
    let rewrite: String
    var originalTitle = "Original"
    var rewriteTitle = "Rewrite"

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: YapSpacing.compact) {
                panel(title: originalTitle, text: original)
                panel(title: rewriteTitle, text: rewrite)
            }
            VStack(spacing: YapSpacing.compact) {
                panel(title: originalTitle, text: original)
                panel(title: rewriteTitle, text: rewrite)
            }
        }
    }

    private func panel(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: YapSpacing.small) {
            Text(title.lowercased())
                .font(YapType.label)
                .foregroundStyle(YapPalette.acid)
            Text(text)
                .font(YapType.body)
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(YapSpacing.regular)
        .yapPanel(cornerRadius: YapRadius.card)
    }
}
