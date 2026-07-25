import SwiftUI

struct CardRow: View {
    let card: Card

    var body: some View {
        CardPreview(card: card)
            .padding(.vertical, 5)
    }
}
