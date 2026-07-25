import SwiftData
import SwiftUI

struct ModesView: View {
    @State private var model: ModesModel
    @State private var editorMode: RewriteMode?
    @State private var isCreating = false

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
                        Button {
                            isCreating = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 17, weight: .black))
                                .foregroundStyle(YapPalette.ink)
                                .frame(width: 48, height: 48)
                                .background(YapPalette.acid, in: Circle())
                                .shadow(color: YapPalette.acid.opacity(0.45), radius: 14)
                        }
                        .accessibilityLabel("New mode")
                    }

                    modeSection("built in", modes: model.modes.filter(\.isBuiltIn))
                    modeSection("yours", modes: model.modes.filter { !$0.isBuiltIn })
                }
                .padding(.horizontal, 20)
                .safeAreaPadding(.top, YapLayout.pushedContentTop)
                .padding(.bottom, 110)
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(YapPalette.paper)
        .preferredColorScheme(.dark)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(isPresented: $isCreating) {
            ModeEditorView(mode: nil, model: model)
        }
        .sheet(item: $editorMode) { mode in
            ModeEditorView(mode: mode, model: model)
        }
    }

    @ViewBuilder
    private func modeSection(_ title: String, modes: [RewriteMode]) -> some View {
        if !modes.isEmpty {
            Text(title)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(YapPalette.paper55)
                .padding(.top, 8)

            ForEach(modes) { mode in
                Button {
                    if !mode.isBuiltIn { editorMode = mode }
                } label: {
                    YapModeCard(mode: mode)
                }
                .buttonStyle(.plain)
                .swipeActions {
                    if !mode.isBuiltIn {
                        Button(role: .destructive) { model.delete(mode) } label: {
                            Label("Delete", systemImage: "trash")
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
        HStack(spacing: 15) {
            Text(mode.emoji)
                .font(.system(size: 28))
                .frame(width: 58, height: 58)
                .background(modeAccent.opacity(0.9), in: RoundedRectangle(cornerRadius: 18))

            VStack(alignment: .leading, spacing: 6) {
                Text(displayName)
                    .font(.system(size: 19, weight: .heavy, design: .rounded))
                Text(mode.systemPrompt)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(YapPalette.paper55)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            if !mode.isBuiltIn {
                Image(systemName: "pencil")
                    .foregroundStyle(YapPalette.paper55)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .yapPanel(cornerRadius: 24)
    }

    private var displayName: String {
        mode.id.lowercased() == "formal" ? "boss" : mode.name.lowercased()
    }

    private var modeAccent: Color {
        switch mode.id.lowercased() {
        case "formal": YapPalette.acid
        case "roast": Color(red: 1, green: 0.16, blue: 0.43)
        case "hindi", "hindi-household": Color.orange
        case "rizz": Color.pink
        default: YapPalette.clay
        }
    }
}
