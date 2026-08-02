import SwiftData
import SwiftUI

struct CardDetailView: View {
    @Bindable var card: Card
    let context: ModelContext
    @State private var modes: [RewriteMode] = []
    @State private var isChoosingMode = false
    @State private var isRewriting = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            YapAuroraBackground(atmosphere: .rewrite)

            ScrollView {
                VStack(alignment: .leading, spacing: YapLayout.sectionSpacing) {
                    VStack(alignment: .leading, spacing: YapSpacing.small) {
                        Text(card.title)
                            .font(YapType.screenTitle)
                            .tracking(-1)
                        metadata
                    }

                    originalPanel

                    if let processed = card.processedText {
                        rewritePanel(title: modeName, text: processed)
                    } else if let enhanced = card.enhancedText {
                        rewritePanel(title: "smart cleanup", text: enhanced)
                    }

                    if isRewriting {
                        HStack {
                            ProgressView().tint(YapPalette.acid)
                            Text("rewriting that…")
                        }
                        .font(YapType.label)
                        .foregroundStyle(YapPalette.paper55)
                    }

                    HStack(spacing: YapSpacing.compact) {
                        Button {
                            UIPasteboard.general.string = card.preferredText
                            YapHaptics.success()
                        } label: {
                            Text("copy")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(YapPrimaryButtonStyle())

                        Button {
                            YapHaptics.selection()
                            isChoosingMode = true
                        } label: {
                            Image(yapIcon: .sparkles)
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: YapControlMetric.iconLarge, height: YapControlMetric.iconLarge)
                                .frame(width: 58, height: 58)
                                .background(.ultraThinMaterial, in: Circle())
                                .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 1))
                        }
                        .accessibilityLabel("Run in another mode")
                    }
                }
                .padding(.horizontal, YapSpacing.appHorizontal)
                .padding(.top, YapLayout.pushedContentTop)
                .padding(.bottom, YapControlMetric.prominent + YapSpacing.small)
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(YapPalette.paper)
        .preferredColorScheme(.dark)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .confirmationDialog("Choose another mode", isPresented: $isChoosingMode) {
            ForEach(modes) { mode in
                Button("\(mode.emoji) \(mode.name)") {
                    YapHaptics.selection()
                    Task { await rerun(mode) }
                }
            }
        }
        .task { modes = (try? ModeRepository(context: context).all()) ?? [] }
        .alert("Rewrite failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var originalPanel: some View {
        VStack(alignment: .leading, spacing: YapSpacing.compact) {
            Text("you said")
                .font(YapType.label)
                .foregroundStyle(YapPalette.paper55)
            Text(card.rawText)
                .font(YapType.body)
                .lineSpacing(5)
                .textSelection(.enabled)
        }
        .padding(YapSpacing.regular)
        .frame(maxWidth: .infinity, alignment: .leading)
        .yapPanel(cornerRadius: YapRadius.card, depth: .sunk)
    }

    private func rewritePanel(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: YapSpacing.compact) {
            Text(title)
                .font(YapType.label)
                .foregroundStyle(YapPalette.acid)
            Text(text)
                .font(YapType.sectionTitle)
                .tracking(-0.45)
                .lineSpacing(7)
                .textSelection(.enabled)
        }
        .padding(YapSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .yapPanel(cornerRadius: YapRadius.card)
    }

    private var metadata: some View {
        HStack(spacing: YapSpacing.small) {
            HStack(spacing: YapSpacing.xSmall) {
                Image(yapIcon: sourceIcon)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 12, height: 12)
                Text(sourceName)
            }
                .yapMetadataPill()
            Text(card.createdAt, style: .relative)
            if card.pinned {
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

    private var sourceName: String {
        switch card.sourceType {
        case .voice: "voice"
        case .share: "shared"
        case .manualPaste: "pasted"
        }
    }

    private var sourceIcon: YapIcon {
        switch card.sourceType {
        case .voice: .microphone
        case .share: .externalLink
        case .manualPaste: .clipboard
        }
    }

    private var modeName: String {
        guard let id = card.modeApplied else { return "rewrite" }
        return id == "formal" ? "boss mode" : "\(id) mode"
    }

    private func rerun(_ mode: RewriteMode) async {
        isRewriting = true
        defer { isRewriting = false }
        do {
            let result = try await SupabaseRewriteService().rewrite(
                text: card.enhancedText ?? card.rawText,
                mode: ModeDefinition(id: mode.id, name: mode.name, emoji: mode.emoji, prompt: mode.systemPrompt)
            )
            card.processedText = result.rewrittenText
            card.modeApplied = mode.id
            card.title = result.title
            try context.save()
            YapHaptics.success()
        } catch {
            errorMessage = error.localizedDescription
            YapHaptics.error()
        }
    }
}
