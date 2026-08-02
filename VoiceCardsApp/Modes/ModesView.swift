import SwiftData
import SwiftUI

struct ModesView: View {
    @State private var model: ModesModel

    init(context: ModelContext) {
        _model = State(initialValue: ModesModel(context: context))
    }

    var body: some View {
        ZStack {
            YapAuroraBackground(atmosphere: .rewrite)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: YapLayout.sectionSpacing) {
                    HStack(alignment: .bottom) {
                        YapScreenHeading(title: "modes", subtitle: "same thought, different energy")
                        Spacer()
                        NavigationLink {
                            ModeEditorView(mode: nil, model: model)
                        } label: {
                            Image(yapIcon: .plus)
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: YapControlMetric.iconRegular, height: YapControlMetric.iconRegular)
                                .foregroundStyle(YapPalette.ink)
                                .frame(width: YapControlMetric.compact, height: YapControlMetric.compact)
                                .background(YapPalette.acid, in: Circle())
                                .shadow(color: YapPalette.acid.opacity(0.45), radius: 14)
                        }
                        .accessibilityLabel("New mode")
                    }

                    modeSection("built in", modes: model.modes.filter(\.isBuiltIn))
                    modeSection("yours", modes: model.modes.filter { !$0.isBuiltIn })
                }
                .padding(.horizontal, YapSpacing.appHorizontal)
                .padding(.top, YapLayout.pushedContentTop)
                .padding(.bottom, YapSpacing.xxLarge + YapControlMetric.prominent)
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(YapPalette.paper)
        .preferredColorScheme(.dark)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private func modeSection(_ title: String, modes: [RewriteMode]) -> some View {
        if !modes.isEmpty {
            Text(title)
                .font(YapType.label)
                .tracking(0.8)
                .foregroundStyle(YapPalette.paper55)
                .padding(.top, YapSpacing.small)

            ForEach(modes) { mode in
                if mode.isBuiltIn {
                    YapModeCard(mode: mode)
                } else {
                    NavigationLink {
                        ModeEditorView(mode: mode, model: model)
                    } label: {
                        YapModeCard(mode: mode)
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button(role: .destructive) {
                            YapHaptics.warning()
                            model.delete(mode)
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
        }
    }
}

private struct YapModeCard: View {
    let mode: RewriteMode

    var body: some View {
        HStack(spacing: YapSpacing.regular) {
            Text(mode.emoji)
                .font(.title2)
                .frame(width: 58, height: 58)
                .background(modeAccent.opacity(0.9), in: RoundedRectangle(cornerRadius: YapRadius.input))

            VStack(alignment: .leading, spacing: YapSpacing.xSmall) {
                Text(displayName)
                    .font(YapType.sectionTitle)
                Text(mode.systemPrompt)
                    .font(YapType.caption)
                    .foregroundStyle(YapPalette.paper55)
                    .lineLimit(2)
            }
            Spacer(minLength: YapSpacing.xSmall)
            if !mode.isBuiltIn {
                Image(yapIcon: .edit)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: YapControlMetric.iconRegular, height: YapControlMetric.iconRegular)
                    .foregroundStyle(YapPalette.paper55)
            }
        }
        .padding(YapSpacing.regular)
        .frame(maxWidth: .infinity, alignment: .leading)
        .yapPanel(cornerRadius: YapRadius.card)
    }

    private var displayName: String {
        mode.id.lowercased() == "formal" ? "boss" : mode.name.lowercased()
    }

    private var modeAccent: Color {
        switch mode.id.lowercased() {
        case "formal": YapPalette.acid
        case "roast": YapPalette.roast
        case "hindi", "hindi-household": Color.orange
        case "rizz": Color.pink
        default: YapPalette.clay
        }
    }
}
