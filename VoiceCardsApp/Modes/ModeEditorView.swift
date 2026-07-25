import SwiftUI

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
                    HStack {
                        Button("cancel") { dismiss() }
                            .foregroundStyle(YapPalette.paper55)
                        Spacer()
                        Text(mode == nil ? "new mode" : "edit mode")
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                        Spacer()
                        Button("save", action: save)
                            .foregroundStyle(YapPalette.acid)
                            .disabled(name.nilIfBlank == nil || prompt.nilIfBlank == nil)
                    }
                    .font(.system(size: 14, weight: .heavy, design: .rounded))

                    HStack(spacing: 12) {
                        TextField("✨", text: $emoji)
                            .font(.system(size: 28))
                            .multilineTextAlignment(.center)
                            .frame(width: 66, height: 58)
                            .yapPanel(cornerRadius: 18)
                        TextField("mode name", text: $name)
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .padding(.horizontal, 17)
                            .frame(height: 58)
                            .yapPanel(cornerRadius: 18, depth: .sunk)
                    }

                    editorPanel(title: "tell yap how to rewrite") {
                        TextEditor(text: $prompt)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 115)
                    }

                    editorPanel(title: "try it live") {
                        TextEditor(text: $sample)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 78)
                        Button {
                            Task { await generatePreview() }
                        } label: {
                            HStack {
                                Text(isPreviewing ? "writing…" : "generate preview")
                                if isPreviewing { ProgressView().tint(YapPalette.ink) }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(YapPrimaryButtonStyle())
                        .disabled(prompt.nilIfBlank == nil || sample.nilIfBlank == nil || isPreviewing)
                    }

                    if let preview {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("preview")
                                .foregroundStyle(YapPalette.acid)
                            Text(preview)
                                .font(.system(size: 19, weight: .medium, design: .rounded))
                                .lineSpacing(5)
                                .textSelection(.enabled)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .yapPanel(cornerRadius: 24)
                    }
                }
                .padding(.horizontal, 20)
                .safeAreaPadding(.top, YapLayout.screenTopInset)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(YapPalette.paper)
        .preferredColorScheme(.dark)
        .alert("Couldn’t continue", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func editorPanel<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(YapPalette.paper55)
            content()
        }
        .padding(18)
        .yapPanel(cornerRadius: 24)
    }

    private func save() {
        do {
            try model.save(id: mode?.id, name: name, emoji: emoji, prompt: prompt)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
