import SwiftData
import SwiftUI

struct SettingsView: View {
    @State private var model: SettingsModel
    @State private var showingKeyboardSetup = false
    @State private var keyboardTestText = ""
    @State private var showingDeleteAccountConfirmation = false
    @State private var isDeletingAccount = false
    @State private var accountDeletionError: String?
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

                    yapCountLockup

                    settingsSection("capture") {
                        NavigationLink {
                            ModesView(context: context)
                        } label: {
                            HStack {
                                Image(yapIcon: .sparkles)
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 19, height: 19)
                                Text("rewrite modes")
                                Spacer()
                                Text("\(model.modes.count)")
                                    .foregroundStyle(YapPalette.paper55)
                                Image(yapIcon: .chevronRight)
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 14, height: 14)
                                    .foregroundStyle(YapPalette.paper55)
                            }
                            .foregroundStyle(YapPalette.paper)
                        }
                        Divider().overlay(.white.opacity(0.12))
                        HStack {
                            Text("default mode")
                            Spacer()
                            Picker(
                                "Default mode",
                                selection: Binding(
                                    get: { model.defaultModeID },
                                    set: {
                                        YapHaptics.selection()
                                        model.setDefaultMode($0)
                                    }
                                )
                            ) {
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
                        NavigationLink {
                            YapMemoryView()
                        } label: {
                            HStack {
                                Image(yapIcon: .ai)
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 20, height: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Yap memory")
                                    Text("names and phrases Yap has learned")
                                        .font(YapType.caption)
                                        .foregroundStyle(YapPalette.paper55)
                                }
                                Spacer()
                                Text("\(model.learnedTermCount)")
                                    .foregroundStyle(YapPalette.paper55)
                                Image(yapIcon: .chevronRight)
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 14, height: 14)
                                    .foregroundStyle(YapPalette.paper55)
                            }
                            .foregroundStyle(YapPalette.paper)
                        }
                        Divider().overlay(.white.opacity(0.12))
                        Toggle(
                            "capture clipboard automatically",
                            isOn: Binding(
                                get: { model.automaticClipboardCapture },
                                set: {
                                    YapHaptics.selection()
                                    model.setAutomaticClipboardCapture($0)
                                }
                            )
                        )
                            .tint(YapPalette.acid)
                        Divider().overlay(.white.opacity(0.12))
                        HStack {
                            Text("keep history")
                            Spacer()
                            Picker(
                                "Keep history",
                                selection: Binding(
                                    get: { model.retentionDays },
                                    set: {
                                        YapHaptics.selection()
                                        model.setRetentionDays($0)
                                    }
                                )
                            ) {
                                Text("forever").tag(0)
                                Text("30 days").tag(30)
                                Text("90 days").tag(90)
                                Text("1 year").tag(365)
                            }
                            .labelsHidden()
                            .tint(YapPalette.acid)
                        }
                        Text("clipboard history stays local. iOS may ask before Yap reads content copied in another app.")
                            .font(YapType.caption)
                            .foregroundStyle(YapPalette.paper55)
                    }

                    settingsSection("keyboard") {
                        Button {
                            YapHaptics.contact()
                            showingKeyboardSetup = true
                        } label: {
                            HStack {
                                Image(yapIcon: .keyboard)
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 20, height: 20)
                                Text("set up the Yap keyboard")
                                Spacer()
                                Image(yapIcon: .chevronRight)
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 14, height: 14)
                            }
                            .font(YapType.button)
                            .foregroundStyle(YapPalette.paper)
                        }
                        Divider().overlay(.white.opacity(0.12))
                        TextField("test the Yap keyboard here", text: $keyboardTestText, axis: .vertical)
                            .font(YapType.body)
                            .padding(YapSpacing.compact)
                            .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: YapRadius.input))
                    }

                    settingsSection("speed") {
                        YapValueRow(label: "last capture", value: model.latestLatency)
                        Text("measured from recorder start through transcription, rewrite and insertion.")
                            .font(YapType.caption)
                            .foregroundStyle(YapPalette.paper55)
                    }

                    settingsSection("account") {
                        YapValueRow(label: "signed in as", value: authModel.userEmail ?? "Apple user")
                        Divider().overlay(.white.opacity(0.12))
                        Button(role: .destructive) {
                            YapHaptics.warning()
                            Task { await authModel.signOut() }
                        } label: {
                            HStack(spacing: 10) {
                                Image(yapIcon: .arrowRight)
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 18, height: 18)
                                Text("sign out")
                            }
                            .font(YapType.button)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Divider().overlay(.white.opacity(0.12))
                        Button(role: .destructive) {
                            YapHaptics.warning()
                            showingDeleteAccountConfirmation = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(yapIcon: .trash)
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 18, height: 18)
                                Text(isDeletingAccount ? "deleting account…" : "delete account")
                                Spacer()
                                if isDeletingAccount {
                                    ProgressView()
                                        .tint(.red)
                                }
                            }
                            .font(YapType.button)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .disabled(isDeletingAccount)
                    }
                }
                .font(YapType.body)
                .padding(.horizontal, YapSpacing.appHorizontal)
                .padding(.top, YapLayout.pushedContentTop)
                .padding(.bottom, YapSpacing.xLarge)
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(YapPalette.paper)
        .preferredColorScheme(.dark)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            model.reloadModes()
            model.reloadMemory()
        }
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
        .alert("delete your account?", isPresented: $showingDeleteAccountConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete account", role: .destructive) {
                deleteAccount()
            }
        } message: {
            Text(
                "This permanently deletes your Yap account and erases your yaps, clipboard history, custom modes, and learned terms. This can’t be undone.\n\nYou can also remove Yap under Apple Account > Sign in with Apple in Settings."
            )
        }
        .alert("account deletion failed", isPresented: Binding(
            get: { accountDeletionError != nil },
            set: { if !$0 { accountDeletionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(accountDeletionError ?? "")
        }
    }

    private var yapCountLockup: some View {
        let countSize: CGFloat = 58

        return HStack(alignment: .firstTextBaseline, spacing: YapSpacing.small) {
            Text(model.yapCount.formatted())
                .font(YapType.identityMetric(size: countSize))
                .monospacedDigit()
                .tracking(-1.4)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: true, vertical: false)

            Text("yaps")
                .font(.system(size: countSize * 0.55, weight: .bold, design: .rounded))
                .tracking(-0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 124, alignment: .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(model.yapCount) yaps")
    }

    private func deleteAccount() {
        guard !isDeletingAccount else { return }
        isDeletingAccount = true
        Task {
            do {
                try await authModel.deleteAccount {
                    try removeLocalAccountData()
                }
                YapHaptics.success()
            } catch {
                YapHaptics.error()
                accountDeletionError = error.localizedDescription
            }
            isDeletingAccount = false
        }
    }

    /// SwiftData stays open while the app runs, so erase records instead of deleting its store file.
    private func removeLocalAccountData() throws {
        let cards = try context.fetch(FetchDescriptor<Card>())
        let clipboardItems = try context.fetch(FetchDescriptor<ClipboardItem>())
        let pendingOperations = try context.fetch(FetchDescriptor<PendingOperation>())
        let personalTerms = try context.fetch(FetchDescriptor<PersonalTerm>())
        let modes = try context.fetch(FetchDescriptor<RewriteMode>())

        let assetStore = ClipboardAssetStore()
        clipboardItems.forEach(assetStore.removeAssets(for:))

        if let audioDirectory = try? AppGroup.audioDirectory() {
            for operation in pendingOperations {
                if let filename = operation.audioFilename {
                    try? FileManager.default.removeItem(at: audioDirectory.appending(path: filename))
                }
            }
        }

        cards.forEach(context.delete)
        clipboardItems.forEach(context.delete)
        pendingOperations.forEach(context.delete)
        personalTerms.forEach(context.delete)
        modes.filter { !$0.isBuiltIn }.forEach(context.delete)
        try context.save()

        KeyboardDictationBridge().save(nil)
        try? APIKeyStore().removeAll()
        AppPreferences.resetForAccountDeletion()
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: YapSpacing.compact) {
            Text(title)
                .font(YapType.label)
                .tracking(0.8)
                .foregroundStyle(YapPalette.paper55)
            VStack(alignment: .leading, spacing: YapSpacing.compact) {
                content()
            }
            .padding(YapSpacing.regular)
            .frame(maxWidth: .infinity, alignment: .leading)
            .yapPanel(cornerRadius: YapRadius.card)
        }
    }
}

private struct YapValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: YapSpacing.compact) {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(YapPalette.paper55)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct YapMemoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PersonalTerm.useCount, order: .reverse) private var storedTerms: [PersonalTerm]
    @State private var editingTerm: PersonalTerm?
    @State private var showingEditor = false
    @State private var showingClearConfirmation = false
    @State private var errorMessage: String?

    private var terms: [PersonalTerm] {
        storedTerms.filter { $0.kind == .name || $0.useCount >= 3 }
    }

    private var names: [PersonalTerm] {
        terms.filter { $0.kind == .name }
    }

    private var phrases: [PersonalTerm] {
        terms.filter { $0.kind == .phrase }
    }

    var body: some View {
        ZStack {
            YapAuroraBackground(atmosphere: .stream)

            ScrollView {
                VStack(alignment: .leading, spacing: YapLayout.sectionSpacing) {
                    YapScreenHeading(
                        title: "Yap memory",
                        subtitle: "the private vocabulary behind your dictation"
                    )

                    memorySummary

                    if terms.isEmpty {
                        emptyMemory
                    } else {
                        if !names.isEmpty {
                            memorySection("names", terms: names)
                        }
                        if !phrases.isEmpty {
                            memorySection("phrases", terms: phrases)
                        }

                        Button(role: .destructive) {
                            YapHaptics.warning()
                            showingClearConfirmation = true
                        } label: {
                            Label {
                                Text("forget everything")
                            } icon: {
                                Image(yapIcon: .trash)
                                    .renderingMode(.template)
                            }
                            .font(YapType.button)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                        }
                        .yapPanel(cornerRadius: YapRadius.card, depth: .sunk)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, YapLayout.pushedContentTop)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(YapPalette.paper)
        .preferredColorScheme(.dark)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            Button {
                editingTerm = nil
                showingEditor = true
                YapHaptics.contact()
            } label: {
                Label {
                    Text("add a term")
                } icon: {
                    Image(yapIcon: .plus)
                        .renderingMode(.template)
                }
            }
            .buttonStyle(YapPrimaryButtonStyle())
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(YapPalette.base.opacity(0.94))
        }
        .sheet(isPresented: $showingEditor) {
            YapMemoryTermEditor(term: editingTerm) { value, kind in
                try save(value: value, kind: kind)
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .alert("forget Yap’s memory?", isPresented: $showingClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Forget everything", role: .destructive) {
                clearMemory()
            }
        } message: {
            Text("Yap will stop using every learned name and phrase. Your saved yaps will not be deleted.")
        }
        .alert("Yap memory", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var memorySummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(terms.count)")
                    .font(YapType.display)
                    .tracking(-1)
                Text(terms.count == 1 ? "term learned" : "terms learned")
                    .font(YapType.label)
                    .foregroundStyle(YapPalette.paper55)
                Spacer()
                Image(yapIcon: .lock)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(YapPalette.acid)
            }

            Text("Yap stores these spellings on this device and uses them only as context for your transcription and cleanup. They are never sent as analytics.")
                .font(YapType.caption)
                .foregroundStyle(YapPalette.paper82)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(YapSpacing.regular)
        .yapPanel(cornerRadius: YapRadius.card)
    }

    private var emptyMemory: some View {
        VStack(spacing: YapSpacing.compact) {
            Image(yapIcon: .sparkles)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)
                .foregroundStyle(YapPalette.acid)
            Text("Yap is listening for your language")
                .font(YapType.sectionTitle)
            Text("Names are remembered after one saved use. Frequent phrases become hints after they recur.")
                .font(YapType.body)
                .foregroundStyle(YapPalette.paper55)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, YapSpacing.large)
        .padding(.vertical, YapSpacing.xxLarge)
        .yapPanel(cornerRadius: YapRadius.card, depth: .sunk)
    }

    private func memorySection(_ title: String, terms: [PersonalTerm]) -> some View {
        VStack(alignment: .leading, spacing: YapSpacing.small) {
            Text(title)
                .font(YapType.label)
                .tracking(0.8)
                .foregroundStyle(YapPalette.paper55)

            VStack(spacing: 0) {
                ForEach(Array(terms.enumerated()), id: \.element.persistentModelID) { index, term in
                    memoryRow(term)
                    if index < terms.count - 1 {
                        Divider()
                            .overlay(.white.opacity(0.12))
                            .padding(.leading, YapSpacing.regular)
                    }
                }
            }
            .yapPanel(cornerRadius: YapRadius.card)
        }
    }

    private func memoryRow(_ term: PersonalTerm) -> some View {
        HStack(spacing: YapSpacing.small) {
            Button {
                editingTerm = term
                showingEditor = true
                YapHaptics.selection()
            } label: {
                HStack(spacing: YapSpacing.compact) {
                    VStack(alignment: .leading, spacing: YapSpacing.xSmall) {
                        Text(term.value)
                            .font(YapType.bodyStrong)
                            .foregroundStyle(YapPalette.paper)
                            .lineLimit(2)
                        HStack(spacing: 4) {
                            Text("used \(term.useCount)×")
                            Text("·")
                            Text(term.lastUsedAt, style: .relative)
                        }
                        .font(YapType.metadata)
                        .foregroundStyle(YapPalette.paper55)
                    }

                    Spacer()

                    Image(yapIcon: .edit)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 17, height: 17)
                        .foregroundStyle(YapPalette.paper55)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Edit this learned term")

            Button(role: .destructive) {
                delete(term)
            } label: {
                Image(yapIcon: .trash)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 17, height: 17)
                    .foregroundStyle(.red)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Forget \(term.value)")
        }
        .padding(.horizontal, YapSpacing.regular)
        .padding(.vertical, YapSpacing.compact)
    }

    private func save(value: String, kind: PersonalTermKind) throws {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count >= 2 else {
            throw YapMemoryError.termTooShort
        }
        let normalized = cleaned.searchNormalized
        if let duplicate = storedTerms.first(where: { $0.normalized == normalized }),
           duplicate !== editingTerm {
            throw YapMemoryError.duplicateTerm
        }

        if let editingTerm {
            editingTerm.value = cleaned
            editingTerm.normalized = normalized
            editingTerm.kind = kind
            if kind == .phrase {
                editingTerm.useCount = max(editingTerm.useCount, 3)
            }
            editingTerm.lastUsedAt = .now
        } else {
            context.insert(
                PersonalTerm(
                    value: cleaned,
                    kind: kind,
                    useCount: kind == .phrase ? 3 : 1
                )
            )
        }
        do {
            try context.save()
            YapHaptics.success()
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    private func delete(_ term: PersonalTerm) {
        context.delete(term)
        do {
            try context.save()
            YapHaptics.contact()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func clearMemory() {
        storedTerms.forEach(context.delete)
        do {
            try context.save()
            YapHaptics.success()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct YapMemoryTermEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var value: String
    @State private var kind: PersonalTermKind
    @State private var errorMessage: String?
    let term: PersonalTerm?
    let save: (String, PersonalTermKind) throws -> Void

    init(
        term: PersonalTerm?,
        save: @escaping (String, PersonalTermKind) throws -> Void
    ) {
        self.term = term
        self.save = save
        _value = State(initialValue: term?.value ?? "")
        _kind = State(initialValue: term?.kind ?? .name)
    }

    var body: some View {
        ZStack {
            YapAuroraBackground(atmosphere: .stream)

            VStack(alignment: .leading, spacing: YapSpacing.regular) {
                Text(term == nil ? "add to Yap memory" : "edit Yap memory")
                    .font(YapType.screenTitle)

                TextField(kind == .name ? "name, place, or brand" : "phrase you say often", text: $value)
                    .font(YapType.body)
                    .padding(.horizontal, YapSpacing.regular)
                    .frame(height: 54)
                    .yapPanel(cornerRadius: YapRadius.input, depth: .sunk)
                    .textInputAutocapitalization(kind == .name ? .words : .never)

                Picker("Term type", selection: $kind) {
                    Text("name").tag(PersonalTermKind.name)
                    Text("phrase").tag(PersonalTermKind.phrase)
                }
                .pickerStyle(.segmented)

                Text("Yap will prioritize this exact spelling while transcribing and cleaning up your speech.")
                    .font(YapType.caption)
                    .foregroundStyle(YapPalette.paper55)

                Spacer()

                Button {
                    do {
                        try save(value, kind)
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                        YapHaptics.error()
                    }
                } label: {
                    Text("save to memory")
                }
                .buttonStyle(YapPrimaryButtonStyle())
                .disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
            }
            .padding(.horizontal, YapSpacing.appHorizontal)
            .padding(.top, YapSpacing.large)
            .padding(.bottom, YapSpacing.regular)
        }
        .foregroundStyle(YapPalette.paper)
        .preferredColorScheme(.dark)
        .alert("Couldn’t save term", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }
}

private enum YapMemoryError: LocalizedError {
    case termTooShort
    case duplicateTerm

    var errorDescription: String? {
        switch self {
        case .termTooShort:
            "Enter at least two characters."
        case .duplicateTerm:
            "Yap already remembers that term."
        }
    }
}
