import SwiftData
import SwiftUI

struct SearchView: View {
    @State private var model: SearchModel
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
        _model = State(initialValue: SearchModel(context: context))
    }

    var body: some View {
        ZStack {
            YapAuroraBackground(atmosphere: .stream)

            VStack(alignment: .leading, spacing: YapLayout.sectionSpacing) {
                YapScreenHeading(title: "find it", subtitle: "every yap, instantly")
                    .padding(.horizontal, 20)

                YapSearchBox(prompt: "what did i say about…", text: $model.query)
                    .padding(.horizontal, 20)

                Group {
                    if model.query.isEmpty {
                        YapEmptyState(
                            symbol: "sparkle.magnifyingglass",
                            title: "ask your memory",
                            detail: "search names, places, phrases, or any word you remember."
                        )
                    } else if model.results.isEmpty && !model.isSearching {
                        YapEmptyState(
                            symbol: "magnifyingglass",
                            title: "nothing matched that",
                            detail: "try a shorter phrase or a different word."
                        )
                    } else {
                        List(model.results) { card in
                            NavigationLink {
                                CardDetailView(card: card, context: context)
                            } label: {
                                YapSearchResultCard(card: card)
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(.init(top: 6, leading: 20, bottom: 6, trailing: 20))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if model.isSearching {
                        ProgressView()
                            .tint(YapPalette.acid)
                            .padding(.trailing, 28)
                    }
                }
            }
            // The custom heading belongs to the content, beneath the native back control.
            .safeAreaPadding(.top, YapLayout.pushedContentTop)
        }
        .foregroundStyle(YapPalette.paper)
        .preferredColorScheme(.dark)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

private struct YapSearchResultCard: View {
    let card: Card

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(card.title)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(YapPalette.paper55)
            }
            Text(card.preferredText)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(YapPalette.paper82)
                .lineLimit(3)
            HStack(spacing: 8) {
                Text(card.sourceType.rawValue.lowercased()).yapMetadataPill()
                Text(card.createdAt, style: .relative)
            }
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(YapPalette.paper55)
        }
        .padding(17)
        .yapPanel(cornerRadius: 24)
    }
}
