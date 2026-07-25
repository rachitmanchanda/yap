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
                            .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .leading) {
                                Button {
                                    model.togglePin(card)
                                } label: {
                                    Label(card.pinned ? "Unpin" : "Pin", systemImage: card.pinned ? "pin.slash" : "pin")
                                }
                                .tint(.orange)
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    model.delete(card)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.plain)
                    .refreshable { model.reload() }
                    .contentMargins(.vertical, 0, for: .scrollContent)
                }
            }
            // The atmosphere draws under system chrome; content uses the real device inset so
            // notches and Dynamic Island sizes never require a hard-coded offset.
            .safeAreaPadding(.top, YapLayout.screenTopInset + 24)
            .padding(.bottom, 116)
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
        VStack(alignment: .leading, spacing: YapLayout.sectionSpacing) {
            HStack(alignment: .center) {
                Text("yap")
                    .font(.system(size: 56, weight: .black, design: .rounded))
                    .tracking(-3.3)
                    .overlay(alignment: .bottomTrailing) {
                        Circle()
                            .fill(YapPalette.acid)
                            .frame(width: 14, height: 14)
                            .offset(x: 13, y: -10)
                    }

                Spacer()

                NavigationLink {
                    SettingsView(context: modelContext)
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(YapPalette.paper)
                        .frame(width: 48, height: 48)
                        .background(.black.opacity(0.3), in: Circle())
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 1))
                }
                .accessibilityLabel("Open settings")
            }

            Text("\(model.cards.count) things remembered")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(YapPalette.paper55)
                .padding(.horizontal, 15)
                .frame(height: 36)
                .yapPanel(cornerRadius: 18, depth: .sunk)
        }
        .padding(.horizontal, 24)
        .padding(.top, 0)
    }

    private var searchField: some View {
        HStack(spacing: 13) {
            Image("YapSearchGlyph")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 19, height: 19)

            TextField("what did i say about…", text: $model.searchText)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .foregroundStyle(YapPalette.paper82)
        .padding(.horizontal, 24)
        .frame(height: 54)
        .yapPanel(cornerRadius: 27, depth: .sunk)
        .padding(.horizontal, 20)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: model.searchText.isEmpty ? "waveform" : "magnifyingglass")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(YapPalette.acid)
            Text(model.searchText.isEmpty ? "say something worth remembering" : "nothing matched that")
                .font(.system(size: 21, weight: .heavy, design: .rounded))
            Text(model.searchText.isEmpty ? "tap yap below and start talking." : "try a different word.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(YapPalette.paper55)
        }
        .multilineTextAlignment(.center)
        .padding(32)
    }

    private var bottomDock: some View {
        HStack(spacing: 14) {
            NavigationLink {
                SearchView(context: modelContext)
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(YapPalette.paper)
                    .frame(width: 58, height: 58)
                    .background(.black.opacity(0.32), in: Circle())
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.42), lineWidth: 1))
            }
            .accessibilityLabel("Search")

            Button(action: capture) {
                Text("yap")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(YapPrimaryButtonStyle())
            .accessibilityLabel("Start recording")

            NavigationLink {
                ClipboardView(context: modelContext)
            } label: {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(YapPalette.ink)
                    .frame(width: 58, height: 58)
                    .background(YapPalette.acid, in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.58), lineWidth: 1))
                    .shadow(color: YapPalette.acid.opacity(0.48), radius: 16, y: 5)
            }
            .accessibilityLabel("Clipboard")
        }
        .padding(.horizontal, 24)
        .padding(.top, YapLayout.dockTopInset)
        // Extra space above the device inset keeps controls away from the home gesture edge.
        .safeAreaPadding(.bottom, YapLayout.dockBottomInset)
        .background(.ultraThinMaterial)
        .background(.black.opacity(0.34))
        .overlay(alignment: .top) {
            Rectangle().fill(.white.opacity(0.23)).frame(height: 1)
        }
    }

    @Environment(\.modelContext) private var modelContext
}

private struct YapStreamCard: View {
    let card: Card

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(card.title)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
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
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(card.pinned ? YapPalette.ink.opacity(0.78) : YapPalette.paper82)
                .lineLimit(2)

            HStack(spacing: 8) {
                Text(card.createdAt, style: .relative)
                badge(sourceLabel)
                if let mode = modeLabel {
                    badge(mode, highlighted: true)
                }
            }
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(card.pinned ? YapPalette.ink.opacity(0.72) : YapPalette.paper55)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if card.pinned {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(YapPalette.clay)
                    .shadow(color: YapPalette.clay.opacity(0.32), radius: 22, y: 10)
            } else {
                Color.clear
                    .yapPanel(cornerRadius: 28, depth: .lifted)
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
        case "roast": Color(red: 1, green: 0.16, blue: 0.43)
        case "hindi", "hinglish": Color(red: 1, green: 0.49, blue: 0.10)
        default: YapPalette.acid
        }
    }
}
