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
                        icon: .clipboard,
                        title: model.items.isEmpty ? "your clipboard lands here" : "nothing matched that",
                        detail: model.items.isEmpty
                            ? "yap remembers text, links and images it sees while the app or keyboard is active."
                            : "try another word or filter."
                    )
                } else {
                    List {
                        ForEach(model.visibleItems) { item in
                            ClipboardItemCard(item: item, thumbnail: model.thumbnail(for: item))
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
                                .swipeActions(edge: .leading) {
                                    Button {
                                        YapHaptics.selection()
                                        model.togglePin(item)
                                    } label: {
                                        Label {
                                            Text(item.pinned ? "Unpin" : "Pin")
                                        } icon: {
                                            Image(yapIcon: .pin)
                                                .renderingMode(.template)
                                        }
                                    }
                                    .tint(YapPalette.clay)
                                }
                                .swipeActions {
                                    Button(role: .destructive) {
                                        YapHaptics.warning()
                                        model.delete(item)
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
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .contentMargins(.vertical, 0, for: .scrollContent)
                    .mask {
                        YapTopScrollEdgeOpacityMask()
                    }
                }
            }
            // Keep branded content visually separate from the native navigation row.
            .padding(.top, YapLayout.pushedContentTop)
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
                YapHaptics.selection()
                model.setAutomaticCapture(!model.automaticCapture)
            } label: {
                Image(yapIcon: model.automaticCapture ? .pause : .play)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: YapControlMetric.iconSmall,
                        height: YapControlMetric.iconSmall
                    )
                    .foregroundStyle(model.automaticCapture ? YapPalette.ink : YapPalette.paper)
                    .frame(
                        width: YapControlMetric.minimumTouchTarget,
                        height: YapControlMetric.minimumTouchTarget
                    )
                    .background(model.automaticCapture ? YapPalette.acid : .white.opacity(0.08), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.42), lineWidth: 1))
                    .shadow(color: model.automaticCapture ? YapPalette.acid.opacity(0.4) : .clear, radius: 12)
            }
            .accessibilityLabel(model.automaticCapture ? "Pause clipboard capture" : "Resume clipboard capture")
            .accessibilityHint(
                model.automaticCapture
                    ? "Keeps existing items and stops Yap from saving newly copied content."
                    : "Starts saving newly copied content again."
            )
        }
        .padding(.horizontal, YapSpacing.appHorizontal)
    }

    private var searchField: some View {
        YapSearchBox(prompt: "search what you copied", text: $model.query)
            .padding(.horizontal, YapSpacing.appHorizontal)
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: YapSpacing.small) {
                ForEach(ClipboardModel.Filter.allCases) { filter in
                    YapChoiceChip(
                        title: filter.rawValue.lowercased(),
                        isSelected: model.filter == filter
                    ) {
                        YapHaptics.selection()
                        withAnimation(.snappy(duration: 0.22)) {
                            model.filter = filter
                        }
                    }
                }
            }
            .padding(.horizontal, YapSpacing.appHorizontal)
        }
    }
}

private struct ClipboardItemCard: View {
    let item: ClipboardItem
    let thumbnail: UIImage?

    var body: some View {
        HStack(spacing: YapSpacing.compact) {
            preview

            VStack(alignment: .leading, spacing: YapSpacing.small) {
                Text(item.kind == .image ? "image from clipboard" : item.displayText)
                    .font(YapType.bodyStrong)
                    .lineLimit(2)

                HStack(spacing: YapSpacing.small) {
                    Text(item.kind.title.lowercased())
                        .yapMetadataPill()
                    Text(item.createdAt, style: .relative)
                    if item.pinned {
                        Image(yapIcon: .pin)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 12, height: 12)
                            .foregroundStyle(YapPalette.acid)
                    }
                }
                .font(YapType.metadata)
                .foregroundStyle(YapPalette.paper55)
            }
            Spacer(minLength: 0)
        }
        .padding(YapSpacing.regular)
        .frame(maxWidth: .infinity, alignment: .leading)
        .yapPanel(cornerRadius: YapRadius.card)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var preview: some View {
        if let thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: YapRadius.input, style: .continuous))
        } else {
            Image(yapIcon: item.kind == .url ? .externalLink : item.kind == .image ? .image : .clipboard)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 25, height: 25)
                .foregroundStyle(YapPalette.ink)
                .frame(width: 72, height: 72)
                .background(item.kind == .url ? YapPalette.acid : YapPalette.clay)
                .clipShape(RoundedRectangle(cornerRadius: YapRadius.input, style: .continuous))
        }
    }
}
