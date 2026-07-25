import SwiftUI

struct RewriteComparisonView: View {
    let original: String
    let rewrite: String
    var originalTitle = "Original"
    var rewriteTitle = "Rewrite"

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                panel(title: originalTitle, text: original)
                panel(title: rewriteTitle, text: rewrite)
            }
            VStack(spacing: 12) {
                panel(title: originalTitle, text: original)
                panel(title: rewriteTitle, text: rewrite)
            }
        }
    }

    private func panel(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.lowercased())
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(YapPalette.acid)
            Text(text)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .yapPanel(cornerRadius: 20)
    }
}
