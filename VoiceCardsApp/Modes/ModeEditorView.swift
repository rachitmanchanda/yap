import SwiftUI
import UIKit

struct ModeEditorView: View {
    let mode: RewriteMode?
    let model: ModesModel
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var emoji: String
    @State private var prompt: String
    @State private var sample = "I will be fifteen minutes late, please start without me."
    @State private var preview: String?
    @State private var isPreviewing = false
    @State private var errorMessage: String?
    @State private var aiImportMessage: String?

    init(mode: RewriteMode?, model: ModesModel) {
        self.mode = mode
        self.model = model
        _name = State(initialValue: mode?.name ?? "")
        _emoji = State(initialValue: mode?.emoji ?? "✨")
        _prompt = State(initialValue: mode?.systemPrompt ?? "")
    }

    var body: some View {
        ZStack {
            YapAuroraBackground(atmosphere: .rewrite)

            ScrollView {
                VStack(alignment: .leading, spacing: YapLayout.sectionSpacing) {
                    YapScreenHeading(
                        title: mode == nil ? "new mode" : "edit mode",
                        subtitle: "teach yap your voice"
                    )

                    HStack(spacing: YapSpacing.compact) {
                        TextField("✨", text: $emoji)
                            .font(.title2)
                            .multilineTextAlignment(.center)
                            .frame(width: 66, height: 58)
                            .yapPanel(cornerRadius: YapRadius.input)
                        TextField("mode name", text: $name)
                            .font(YapType.sectionTitle)
                            .accessibilityIdentifier("modeNameField")
                            .padding(.horizontal, YapSpacing.regular)
                            .frame(height: 58)
                            .yapPanel(cornerRadius: YapRadius.input, depth: .sunk)
                    }

                    editorPanel(title: "tell yap how to rewrite") {
                        TextEditor(text: $prompt)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 115)
                            .accessibilityIdentifier("modePromptEditor")
                    }

                    primarySaveButton

                    aiImportPanel

                    editorPanel(title: "try it live") {
                        TextEditor(text: $sample)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 78)
                        Button {
                            YapHaptics.contact()
                            Task { await generatePreview() }
                        } label: {
                            HStack {
                                Text(isPreviewing ? "writing…" : "generate preview")
                                if isPreviewing { ProgressView().tint(YapPalette.ink) }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(YapGhostButtonStyle())
                        .disabled(prompt.nilIfBlank == nil || sample.nilIfBlank == nil || isPreviewing)
                    }

                    if let preview {
                        VStack(alignment: .leading, spacing: YapSpacing.small) {
                            Text("preview")
                                .foregroundStyle(YapPalette.acid)
                            Text(preview)
                                .font(YapType.body)
                                .lineSpacing(5)
                                .textSelection(.enabled)
                        }
                        .padding(YapSpacing.regular)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .yapPanel(cornerRadius: YapRadius.card)
                    }
                }
                .padding(.horizontal, YapSpacing.appHorizontal)
                // This screen is pushed, so its content starts beneath the native back control.
                .padding(.top, YapLayout.pushedContentTop)
                .padding(.bottom, YapSpacing.xxLarge + YapControlMetric.prominent)
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(YapPalette.paper)
        .preferredColorScheme(.dark)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(action: save) {
                    Text(mode == nil ? "save mode" : "save changes")
                        .font(YapType.button)
                }
                .disabled(!canSave)
                .accessibilityIdentifier("keyboardSaveModeButton")
            }
        }
        .alert("Couldn’t continue", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var primarySaveButton: some View {
        Button {
            save()
        } label: {
            HStack(spacing: YapSpacing.small) {
                Image(yapIcon: .check)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: YapControlMetric.iconRegular, height: YapControlMetric.iconRegular)
                Text(mode == nil ? "save mode" : "save changes")
            }
        }
        .buttonStyle(YapPrimaryButtonStyle())
        .disabled(!canSave)
        .opacity(canSave ? 1 : 0.45)
        .accessibilityIdentifier("saveModeButton")
        .accessibilityHint(canSave ? "Saves this rewrite mode" : "Add a mode name and rewrite instruction first")
    }

    private var canSave: Bool {
        name.nilIfBlank != nil && prompt.nilIfBlank != nil
    }

    private var aiImportPanel: some View {
        VStack(alignment: .leading, spacing: YapSpacing.compact) {
            VStack(alignment: .leading, spacing: YapSpacing.xSmall) {
                Text("build it with your ai")
                    .font(YapType.sectionTitle)
                Text("we’ll copy a prompt. paste it into your preferred app, then paste its final instruction above.")
                    .font(YapType.caption)
                    .foregroundStyle(YapPalette.paper55)
                    .lineSpacing(3)
            }

            HStack(spacing: YapSpacing.small) {
                aiProviderButton(
                    title: "ChatGPT",
                    icon: .openAI,
                    tint: YapPalette.paper
                ) {
                    openAIProvider(
                        named: "ChatGPT",
                        appURL: URL(string: "chatgpt://"),
                        webURL: URL(string: "https://chatgpt.com/")
                    )
                }

                aiProviderButton(
                    title: "Claude",
                    icon: .ai,
                    tint: YapPalette.clay
                ) {
                    openAIProvider(
                        named: "Claude",
                        appURL: URL(string: "claude://"),
                        webURL: URL(string: "https://claude.ai/new")
                    )
                }
            }

            if let aiImportMessage {
                HStack(spacing: YapSpacing.small) {
                    Image(yapIcon: .check)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: YapControlMetric.iconSmall, height: YapControlMetric.iconSmall)
                    Text(aiImportMessage)
                        .lineLimit(2)
                    Spacer(minLength: YapSpacing.small)
                    Button(action: pasteAIResult) {
                        HStack(spacing: YapSpacing.xSmall) {
                            Image(yapIcon: .clipboard)
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 13, height: 13)
                            Text("paste result")
                        }
                        .padding(.horizontal, YapSpacing.small)
                        .frame(height: 32)
                        .background(YapPalette.acid, in: Capsule())
                        .foregroundStyle(YapPalette.ink)
                    }
                    .buttonStyle(.plain)
                }
                .font(YapType.label)
                .foregroundStyle(YapPalette.acid)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(YapSpacing.regular)
        .yapPanel(cornerRadius: YapRadius.card)
    }

    private func aiProviderButton(
        title: String,
        icon: YapIcon,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: YapSpacing.small) {
                Image(yapIcon: icon)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 21, height: 21)
                Text(title)
                    .font(YapType.button)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(minHeight: YapControlMetric.compact)
            .background(.white.opacity(0.08), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.48), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Import a mode from \(title)")
        .accessibilityIdentifier("importModeFrom\(title)")
    }

    private func openAIProvider(
        named providerName: String,
        appURL: URL?,
        webURL: URL?
    ) {
        UIPasteboard.general.string = aiModeBuilderPrompt
        YapHaptics.success()
        withAnimation(.snappy(duration: 0.2)) {
            aiImportMessage = "prompt copied — paste it into \(providerName)"
        }

        guard let appURL else {
            if let webURL { UIApplication.shared.open(webURL) }
            return
        }

        UIApplication.shared.open(appURL) { opened in
            guard !opened, let webURL else { return }
            UIApplication.shared.open(webURL)
        }
    }

    private var aiModeBuilderPrompt: String {
        """
        I use Yap, a dictation app. It lets me set a custom rewrite prompt. Write me a \
        one-paragraph prompt that describes my writing style so Yap can rewrite my dictation \
        to match. Requirements: output only the rewritten text, no prefix or suffix. Keep it \
        reusable across contexts.
        """
    }

    private func pasteAIResult() {
        guard let pasted = UIPasteboard.general.string?.nilIfBlank else {
            aiImportMessage = "copy the AI’s final instruction first"
            return
        }
        guard pasted != aiModeBuilderPrompt else {
            aiImportMessage = "copy the AI’s final instruction first"
            return
        }

        prompt = pasted
        YapHaptics.success()
        withAnimation(.snappy(duration: 0.2)) {
            aiImportMessage = "imported — ready to save"
        }
    }

    private func editorPanel<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: YapSpacing.small) {
            Text(title)
                .font(YapType.label)
                .foregroundStyle(YapPalette.paper55)
            content()
        }
        .padding(YapSpacing.regular)
        .yapPanel(cornerRadius: YapRadius.card)
    }

    private func save() {
        do {
            try model.save(id: mode?.id, name: name, emoji: emoji, prompt: prompt)
            YapHaptics.success()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            YapHaptics.error()
        }
    }

    private func generatePreview() async {
        isPreviewing = true
        defer { isPreviewing = false }
        do {
            let result = try await SupabaseRewriteService().rewrite(
                text: sample,
                mode: ModeDefinition(id: mode?.id ?? "preview", name: name, emoji: emoji, prompt: prompt)
            )
            preview = result.rewrittenText
            YapHaptics.contact()
        } catch {
            errorMessage = error.localizedDescription
            YapHaptics.error()
        }
    }
}
