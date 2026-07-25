import SwiftData
import SwiftUI

struct SettingsView: View {
    @State private var model: SettingsModel
    @State private var showingKeyboardSetup = false
    @State private var keyboardTestText = ""
    @Environment(AuthModel.self) private var authModel
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
        _model = State(initialValue: SettingsModel(context: context))
    }

    var body: some View {
        ZStack {
            YapAuroraBackground(atmosphere: .stream)

            ScrollView {
                VStack(alignment: .leading, spacing: YapLayout.sectionSpacing) {
                    YapScreenHeading(title: "settings", subtitle: "make yap yours")

                    settingsSection("account") {
                        YapValueRow(label: "signed in as", value: authModel.userEmail ?? "Apple user")
                        Divider().overlay(.white.opacity(0.12))
                        Button(role: .destructive) {
                            Task { await authModel.signOut() }
                        } label: {
                            Label("sign out", systemImage: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 15, weight: .heavy, design: .rounded))
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    settingsSection("capture") {
                        NavigationLink {
                            ModesView(context: context)
                        } label: {
                            HStack {
                                Label("rewrite modes", systemImage: "wand.and.stars")
                                Spacer()
                                Text("\(model.modes.count)")
                                    .foregroundStyle(YapPalette.paper55)
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(YapPalette.paper55)
                            }
                            .foregroundStyle(YapPalette.paper)
                        }
                        Divider().overlay(.white.opacity(0.12))
                        HStack {
                            Text("default mode")
                            Spacer()
                            Picker("Default mode", selection: $model.defaultModeID) {
                                Text("none").tag(String?.none)
                                ForEach(model.modes) { mode in
                                    Text("\(mode.emoji) \(mode.name.lowercased())").tag(Optional(mode.id))
                                }
                            }
                            .labelsHidden()
                            .tint(YapPalette.acid)
                        }
                        Divider().overlay(.white.opacity(0.12))
                        YapValueRow(label: "microphone", value: model.microphoneStatus.lowercased())
                        Divider().overlay(.white.opacity(0.12))
                        YapValueRow(label: "offline speech", value: model.speechStatus.lowercased())
                    }

                    settingsSection("memory") {
                        Toggle("capture clipboard automatically", isOn: $model.automaticClipboardCapture)
                            .tint(YapPalette.acid)
                        Divider().overlay(.white.opacity(0.12))
                        HStack {
                            Text("keep history")
                            Spacer()
                            Picker("Keep history", selection: $model.retentionDays) {
                                Text("forever").tag(0)
                                Text("30 days").tag(30)
                                Text("90 days").tag(90)
                                Text("1 year").tag(365)
                            }
                            .labelsHidden()
                            .tint(YapPalette.acid)
                        }
                        Text("clipboard history stays local. iOS may ask before Yap reads content copied in another app.")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(YapPalette.paper55)
                    }

                    settingsSection("keyboard") {
                        Button {
                            showingKeyboardSetup = true
                        } label: {
                            HStack {
                                Label("set up the Yap keyboard", systemImage: "keyboard")
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(YapPalette.paper)
                        }
                        Divider().overlay(.white.opacity(0.12))
                        TextField("test the Yap keyboard here", text: $keyboardTestText, axis: .vertical)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .padding(14)
                            .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 17))
                    }

                    settingsSection("speed") {
                        YapValueRow(label: "last capture", value: model.latestLatency)
                        Text("measured from recorder start through transcription, rewrite and insertion.")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(YapPalette.paper55)
                    }

                    Button("save settings") {
                        model.save()
                    }
                    .buttonStyle(YapPrimaryButtonStyle())
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .padding(.horizontal, 20)
                .safeAreaPadding(.top, YapLayout.pushedContentTop)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(YapPalette.paper)
        .preferredColorScheme(.dark)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingKeyboardSetup) {
            KeyboardSetupView()
        }
        .alert("Yap", isPresented: Binding(
            get: { model.message != nil },
            set: { if !$0 { model.message = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.message ?? "")
        }
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(title)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(YapPalette.paper55)
            VStack(alignment: .leading, spacing: 13) {
                content()
            }
            .padding(17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .yapPanel(cornerRadius: 24)
        }
    }
}

private struct YapValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(YapPalette.paper55)
                .multilineTextAlignment(.trailing)
        }
    }
}
