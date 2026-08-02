import SwiftData
import SwiftUI

struct StreamView: View {
    @State private var model: StreamModel
    let capture: () -> Void

    init(
        context: ModelContext,
        capture: @escaping () -> Void
    ) {
        _model = State(initialValue: StreamModel(context: context))
        self.capture = capture
    }

    var body: some View {
        ZStack {
            YapAuroraBackground(atmosphere: .stream)

            VStack(alignment: .leading, spacing: 0) {
                streamHeader
                searchField
                    .padding(.vertical, YapLayout.sectionSpacing)

                if model.visibleCards.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(model.visibleCards) { card in
                            NavigationLink {
                                CardDetailView(card: card, context: modelContext)
                            } label: {
                                YapStreamCard(card: card)
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(
                                EdgeInsets(
                                    top: YapSpacing.small,
                                    leading: YapSpacing.appHorizontal,
                                    bottom: YapSpacing.small,
                                    trailing: YapSpacing.appHorizontal
                                )
                            )
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .leading) {
                                Button {
                                    YapHaptics.selection()
                                    model.togglePin(card)
                                } label: {
                                    Label {
                                        Text(card.pinned ? "Unpin" : "Pin")
                                    } icon: {
                                        Image(yapIcon: .pin)
                                            .renderingMode(.template)
                                    }
                                }
                                .tint(.orange)
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    YapHaptics.warning()
                                    model.delete(card)
                                } label: {
                                    Label {
                                        Text("Delete")
                                    } icon: {
                                        Image(yapIcon: .trash)
                                            .renderingMode(.template)
                                    }
                                }
                            }
                        }

                        // The stream continues beneath the floating dock, while this tail lets
                        // the final card still scroll fully above its controls when needed.
                        Color.clear
                            .frame(height: 132)
                            .listRowInsets(.init())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.plain)
                    .refreshable { model.reload() }
                    .contentMargins(.vertical, 0, for: .scrollContent)
                    .mask {
                        YapTopScrollEdgeOpacityMask()
                    }
                }
            }
            // The atmosphere draws under system chrome; content uses the real device inset so
            // notches and Dynamic Island sizes never require a hard-coded offset.
            .safeAreaPadding(.top, YapLayout.screenTopInset + 24)
        }
        .foregroundStyle(YapPalette.paper)
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        // Search should summon the keyboard as an overlay; shifting the entire voice-first
        // surface makes the header disappear and breaks spatial continuity.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .overlay(alignment: .bottom) {
            bottomDock
        }
        .environment(\.modelContext, modelContext)
        .alert("Couldn’t update stream", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .onAppear { model.reload() }
    }

    private var streamHeader: some View {
        HStack(alignment: .center, spacing: YapSpacing.regular) {
            Image("YapMark")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(YapPalette.paper)
                .frame(width: 84, height: 60)
                .accessibilityLabel("Yap")

            Spacer()

            NavigationLink {
                SettingsView(context: modelContext)
            } label: {
                Image(yapIcon: .settings)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(YapPalette.paper)
                    .frame(
                        width: YapControlMetric.iconRegular,
                        height: YapControlMetric.iconRegular
                    )
                    .frame(
                        width: YapControlMetric.compact,
                        height: YapControlMetric.compact
                    )
                    .background(.black.opacity(0.3), in: Circle())
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 1))
            }
            .accessibilityLabel("Open settings")
        }
        .padding(.horizontal, YapSpacing.large)
        .padding(.top, 0)
    }

    private var searchField: some View {
        HStack(spacing: YapSpacing.compact) {
            Image("YapSearchGlyph")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 19, height: 19)

            TextField("what did i say about…", text: $model.searchText)
                .font(YapType.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .foregroundStyle(YapPalette.paper82)
        .padding(.horizontal, YapSpacing.large)
        .frame(height: 54)
        .yapPanel(cornerRadius: YapRadius.card, depth: .sunk)
        .padding(.horizontal, YapSpacing.appHorizontal)
    }

    private var emptyState: some View {
        VStack(spacing: YapSpacing.compact) {
            Image(yapIcon: model.searchText.isEmpty ? .waveform : .search)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 38, height: 38)
                .foregroundStyle(YapPalette.acid)
            Text(model.searchText.isEmpty ? "say something worth remembering" : "nothing matched that")
                .font(YapType.sectionTitle)
            Text(model.searchText.isEmpty ? "tap yap below and start talking." : "try a different word.")
                .font(YapType.body)
                .foregroundStyle(YapPalette.paper55)
        }
        .multilineTextAlignment(.center)
        .padding(YapSpacing.xLarge)
    }

    private var bottomDock: some View {
        YapBottomDock {
            HStack(spacing: YapSpacing.compact) {
                NavigationLink {
                    SearchView(context: modelContext)
                } label: {
                    Image(yapIcon: .search)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: YapControlMetric.iconLarge, height: YapControlMetric.iconLarge)
                        .foregroundStyle(YapPalette.paper)
                        .frame(width: 58, height: 58)
                        .background(.black.opacity(0.32), in: Circle())
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.42), lineWidth: 1))
                }
                .accessibilityLabel("Search")

                Button {
                    YapHaptics.prepareForCapture()
                    capture()
                } label: {
                    Image("YapMark")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(YapPalette.paper)
                        .frame(width: 42, height: 30)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(YapPrimaryButtonStyle())
                .accessibilityLabel("Start recording")

                NavigationLink {
                    ClipboardView(context: modelContext)
                } label: {
                    Image(yapIcon: .clipboard)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: YapControlMetric.iconLarge, height: YapControlMetric.iconLarge)
                        .foregroundStyle(YapPalette.ink)
                        .frame(width: 58, height: 58)
                        .background(YapPalette.acid, in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.58), lineWidth: 1))
                        .shadow(color: YapPalette.acid.opacity(0.48), radius: 16, y: 5)
                }
                .accessibilityLabel("Clipboard")
            }
        }
    }

    @Environment(\.modelContext) private var modelContext
}

private struct YapStreamCard: View {
    let card: Card

    var body: some View {
        VStack(alignment: .leading, spacing: YapSpacing.compact) {
            HStack(alignment: .firstTextBaseline, spacing: YapSpacing.small) {
                Text(card.title)
                    .font(YapType.sectionTitle)
                    .tracking(-0.35)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if card.pinned {
                    Image("YapPin")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 15, height: 15)
                }
            }

            Text(card.preferredText)
                .font(YapType.body)
                .foregroundStyle(card.pinned ? YapPalette.ink.opacity(0.78) : YapPalette.paper82)
                .lineLimit(2)

            HStack(spacing: YapSpacing.small) {
                Text(card.createdAt, style: .relative)
                badge(sourceLabel)
                if let mode = modeLabel {
                    badge(mode, highlighted: true)
                }
            }
            .font(YapType.caption)
            .foregroundStyle(card.pinned ? YapPalette.ink.opacity(0.72) : YapPalette.paper55)
        }
        .padding(.horizontal, YapSpacing.regular)
        .padding(.vertical, YapSpacing.regular)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if card.pinned {
                RoundedRectangle(cornerRadius: YapRadius.card, style: .continuous)
                    .fill(YapPalette.clay)
                    .shadow(color: YapPalette.clay.opacity(0.32), radius: 22, y: 10)
            } else {
                Color.clear
                    .yapPanel(cornerRadius: YapRadius.card, depth: .lifted)
            }
        }
        .foregroundStyle(card.pinned ? YapPalette.ink : YapPalette.paper)
    }

    private func badge(_ title: String, highlighted: Bool = false) -> some View {
        Text(title)
            .foregroundStyle(
                highlighted
                    ? (card.pinned ? YapPalette.ink : YapPalette.base)
                    : (card.pinned ? YapPalette.ink.opacity(0.76) : YapPalette.paper82)
            )
            .padding(.horizontal, 10)
            .frame(height: 25)
            .background {
                Capsule()
                    .fill(
                        highlighted
                            ? modeColor
                            : (card.pinned ? .black.opacity(0.12) : .white.opacity(0.08))
                    )
            }
            .overlay {
                if !highlighted {
                    Capsule().stroke(.white.opacity(card.pinned ? 0.18 : 0.35), lineWidth: 1)
                }
            }
    }

    private var sourceLabel: String {
        switch card.sourceType {
        case .voice: "voice"
        case .share: "shared"
        case .manualPaste: "pasted"
        }
    }

    private var modeLabel: String? {
        guard let id = card.modeApplied else { return nil }
        return id == "formal" ? "boss" : id
    }

    private var modeColor: Color {
        switch card.modeApplied?.lowercased() {
        case "formal": YapPalette.acid
        case "roast": YapPalette.roast
        case "hindi", "hinglish": YapPalette.hinglish
        default: YapPalette.acid
        }
    }
}
