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
                    .padding(.horizontal, YapSpacing.appHorizontal)

                YapSearchBox(prompt: "what did i say about…", text: $model.query)
                    .padding(.horizontal, YapSpacing.appHorizontal)

                Group {
                    if model.query.isEmpty {
                        YapEmptyState(
                            icon: .sparkles,
                            title: "ask your memory",
                            detail: "search names, places, phrases, or any word you remember."
                        )
                    } else if model.results.isEmpty && !model.isSearching {
                        YapEmptyState(
                            icon: .search,
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
                            .listRowInsets(
                                .init(
                                    top: YapSpacing.small,
                                    leading: YapSpacing.appHorizontal,
                                    bottom: YapSpacing.small,
                                    trailing: YapSpacing.appHorizontal
                                )
                            )
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
                            .padding(.trailing, YapSpacing.xLarge)
                    }
                }
            }
            // The custom heading belongs to the content, beneath the native back control.
            .padding(.top, YapLayout.pushedContentTop)
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
        VStack(alignment: .leading, spacing: YapSpacing.small) {
            HStack {
                Text(card.title)
                    .font(YapType.sectionTitle)
                    .lineLimit(1)
                Spacer()
                Image(yapIcon: .chevronRight)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 13, height: 13)
                    .foregroundStyle(YapPalette.paper55)
            }
            Text(card.preferredText)
                .font(YapType.body)
                .foregroundStyle(YapPalette.paper82)
                .lineLimit(3)
            HStack(spacing: YapSpacing.small) {
                Text(card.sourceType.rawValue.lowercased()).yapMetadataPill()
                Text(card.createdAt, style: .relative)
            }
            .font(YapType.metadata)
            .foregroundStyle(YapPalette.paper55)
        }
        .padding(YapSpacing.regular)
        .yapPanel(cornerRadius: YapRadius.card)
    }
}
