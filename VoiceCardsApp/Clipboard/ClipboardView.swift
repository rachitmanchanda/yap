import SwiftData
import SwiftUI

struct ClipboardView: View {
    @State private var model: ClipboardModel

    init(context: ModelContext) {
        _model = State(initialValue: ClipboardModel(context: context))
    }

    var body: some View {
        ZStack {
            YapAuroraBackground(atmosphere: .stream)

            VStack(alignment: .leading, spacing: YapLayout.sectionSpacing) {
                header
                searchField
                filters

                if model.visibleItems.isEmpty {
                    YapEmptyState(
                        symbol: "doc.on.clipboard",
                        title: model.items.isEmpty ? "your clipboard lands here" : "nothing matched that",
                        detail: model.items.isEmpty
                            ? "yap remembers text, links and images it sees while the app or keyboard is active."
                            : "try another word or filter."
                    )
                } else {
                    List {
                        ForEach(model.visibleItems) { item in
                            ClipboardItemCard(item: item, thumbnail: model.thumbnail(for: item))
                                .listRowInsets(.init(top: 6, leading: 20, bottom: 6, trailing: 20))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .swipeActions(edge: .leading) {
                                    Button {
                                        model.togglePin(item)
                                    } label: {
                                        Label(item.pinned ? "Unpin" : "Pin", systemImage: "pin")
                                    }
                                    .tint(YapPalette.clay)
                                }
                                .swipeActions {
                                    Button(role: .destructive) {
                                        model.delete(item)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .contentMargins(.vertical, 0, for: .scrollContent)
                }
            }
            // Keep branded content visually separate from the native navigation row.
            .safeAreaPadding(.top, YapLayout.pushedContentTop)
        }
        .foregroundStyle(YapPalette.paper)
        .preferredColorScheme(.dark)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            while !Task.isCancelled {
                model.reload()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .alert("Clipboard unavailable", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            YapScreenHeading(title: "clipboard", subtitle: "\(model.items.count) things copied")
            Spacer()
            Button {
                model.setAutomaticCapture(!model.automaticCapture)
            } label: {
                Image(systemName: model.automaticCapture ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(model.automaticCapture ? YapPalette.ink : YapPalette.paper)
                    .frame(width: 46, height: 46)
                    .background(model.automaticCapture ? YapPalette.acid : .white.opacity(0.08), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.42), lineWidth: 1))
                    .shadow(color: model.automaticCapture ? YapPalette.acid.opacity(0.4) : .clear, radius: 12)
            }
            .accessibilityLabel(model.automaticCapture ? "Pause clipboard capture" : "Resume clipboard capture")
        }
        .padding(.horizontal, 20)
    }

    private var searchField: some View {
        YapSearchBox(prompt: "search what you copied", text: $model.query)
            .padding(.horizontal, 20)
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ClipboardModel.Filter.allCases) { filter in
                    YapChoiceChip(
                        title: filter.rawValue.lowercased(),
                        isSelected: model.filter == filter
                    ) {
                        withAnimation(.snappy(duration: 0.22)) {
                            model.filter = filter
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

private struct ClipboardItemCard: View {
    let item: ClipboardItem
    let thumbnail: UIImage?

    var body: some View {
        HStack(spacing: 14) {
            preview

            VStack(alignment: .leading, spacing: 8) {
                Text(item.kind == .image ? "image from clipboard" : item.displayText)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .lineLimit(2)

                HStack(spacing: 7) {
                    Text(item.kind.title.lowercased())
                        .yapMetadataPill()
                    Text(item.createdAt, style: .relative)
                    if item.pinned {
                        Image(systemName: "pin.fill")
                            .foregroundStyle(YapPalette.acid)
                    }
                }
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(YapPalette.paper55)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .yapPanel(cornerRadius: 24)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var preview: some View {
        if let thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        } else {
            Image(systemName: item.kind.systemImage)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(YapPalette.ink)
                .frame(width: 72, height: 72)
                .background(item.kind == .url ? YapPalette.acid : YapPalette.clay)
                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
    }
}
