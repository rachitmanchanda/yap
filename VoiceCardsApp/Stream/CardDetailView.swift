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
                    VStack(alignment: .leading, spacing: 10) {
                        Text(card.title)
                            .font(.system(size: 31, weight: .black, design: .rounded))
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
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(YapPalette.paper55)
                    }

                    HStack(spacing: 12) {
                        Button {
                            UIPasteboard.general.string = card.preferredText
                        } label: {
                            Text("copy")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(YapPrimaryButtonStyle())

                        Button {
                            isChoosingMode = true
                        } label: {
                            Image(systemName: "wand.and.stars")
                                .frame(width: 58, height: 58)
                                .background(.ultraThinMaterial, in: Circle())
                                .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 1))
                        }
                        .accessibilityLabel("Run in another mode")
                    }
                }
                .padding(.horizontal, 20)
                .safeAreaPadding(.top, YapLayout.pushedContentTop)
                .padding(.bottom, 70)
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
        VStack(alignment: .leading, spacing: 11) {
            Text("you said")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(YapPalette.paper55)
            Text(card.rawText)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .lineSpacing(5)
                .textSelection(.enabled)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .yapPanel(cornerRadius: 25, depth: .sunk)
    }

    private func rewritePanel(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(title)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(YapPalette.acid)
            Text(text)
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .tracking(-0.45)
                .lineSpacing(7)
                .textSelection(.enabled)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .yapPanel(cornerRadius: 27)
    }

    private var metadata: some View {
        HStack(spacing: 8) {
            Label(sourceName, systemImage: card.sourceType.systemImage)
                .yapMetadataPill()
            Text(card.createdAt, style: .relative)
            if card.pinned {
                Image(systemName: "pin.fill")
                    .foregroundStyle(YapPalette.acid)
            }
        }
        .font(.system(size: 11, weight: .bold, design: .rounded))
        .foregroundStyle(YapPalette.paper55)
    }

    private var sourceName: String {
        switch card.sourceType {
        case .voice: "voice"
        case .share: "shared"
        case .manualPaste: "pasted"
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
