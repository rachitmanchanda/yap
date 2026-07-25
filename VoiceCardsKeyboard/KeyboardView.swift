import AppIntents
import SwiftUI

enum YapKeyboardPalette {
    static let base = Color(red: 0.043, green: 0.039, blue: 0.035)
    static let paper = Color(red: 0.98, green: 0.96, blue: 0.92)
    static let clay = Color(red: 0.89, green: 0.31, blue: 0.13)
    static let acid = Color(red: 0.84, green: 1.0, blue: 0.08)
    static let ink = Color(red: 0.04, green: 0.04, blue: 0.035)
}

struct KeyboardView: View {
    @Bindable var model: KeyboardModel
    let insert: (String) -> Void
    let nextKeyboard: () -> Void
    let requestStop: () -> Void
    let cancelDictation: () -> Void
    let insertOriginal: () -> Void
    let applyMode: (String) -> Void
    let refreshAccess: () -> Void

    @State private var surface: Surface = .launcher

    private enum Surface {
        case launcher
        case cards
    }

    var body: some View {
        Group {
            if let session = model.dictationSession {
                sessionSurface(session)
            } else {
                switch surface {
                case .launcher: launcher
                case .cards: cardsSurface
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 270, maxHeight: 320)
        .foregroundStyle(YapKeyboardPalette.paper)
        .background { YapKeyboardAtmosphere() }
        .preferredColorScheme(.dark)
        .task { refreshAccess() }
    }

    private var launcher: some View {
        HStack(spacing: 10) {
            launcherButton(
                title: "Clipboard\nItems",
                symbol: "rectangle.stack.fill",
                isPrimary: false
            ) {
                surface = .cards
            }

            Button(intent: StartKeyboardDictationIntent()) {
                launcherLabel(
                    title: "Tap to\nSpeak",
                    symbol: "waveform",
                    isPrimary: true
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start Yap dictation")
        }
    }

    private func launcherButton(
        title: String,
        symbol: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            launcherLabel(title: title, symbol: symbol, isPrimary: isPrimary)
        }
        .buttonStyle(.plain)
    }

    private func launcherLabel(title: String, symbol: String, isPrimary: Bool) -> some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 29, weight: .semibold))
                .foregroundStyle(isPrimary ? YapKeyboardPalette.ink : YapKeyboardPalette.acid)
            Text(title)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(isPrimary ? YapKeyboardPalette.ink : YapKeyboardPalette.paper)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            isPrimary ? YapKeyboardPalette.clay : .black.opacity(0.28),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(isPrimary ? 0.42 : 0.28), lineWidth: 1)
        }
        .shadow(color: isPrimary ? YapKeyboardPalette.clay.opacity(0.35) : .clear, radius: 16, y: 8)
    }

    private var cardsSurface: some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                Button {
                    surface = .launcher
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.08), in: Circle())
                }
                .accessibilityLabel("Back to Yap")

                TextField("Search cards", text: $model.query)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(.black.opacity(0.28), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.24), lineWidth: 1))

                Button(action: nextKeyboard) {
                    Image(systemName: "globe")
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.08), in: Circle())
                }
                .accessibilityLabel("Next keyboard")
            }

            ScrollView(.vertical, showsIndicators: false) {
                if !model.canReadSharedStorage {
                    FullAccessExplainer(
                        fullAccessReported: model.hasFullAccess,
                        diagnostic: model.errorMessage,
                        refreshAccess: refreshAccess
                    )
                } else if model.cards.isEmpty && model.clipboardItems.isEmpty {
                    ContentUnavailableView(
                        "No saved items",
                        systemImage: "rectangle.stack",
                        description: Text("Copy something or capture a thought, then return here.")
                    )
                } else if !model.query.isEmpty {
                    clipboardStrip(title: "Clipboard results", items: model.clipboardSearchResults)
                    cardStrip(title: "Results", cards: model.searchResults, compact: false)
                } else {
                    if !model.pinnedClipboard.isEmpty {
                        clipboardStrip(title: "Pinned clipboard", items: model.pinnedClipboard)
                    }
                    clipboardStrip(title: "Recent clipboard", items: model.recentClipboard)
                    if !model.pinned.isEmpty {
                        cardStrip(title: "Pinned Yaps", cards: model.pinned, compact: false)
                    }
                    cardStrip(title: "Saved Yaps", cards: model.recent, compact: false)
                }
            }

            if let notice = model.clipboardNotice {
                Text(notice)
                    .font(.caption2)
                    .foregroundStyle(YapKeyboardPalette.paper.opacity(0.58))
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private func sessionSurface(_ session: KeyboardDictationSession) -> some View {
        switch session.phase {
        case .launching:
            statusSurface(title: "Starting microphone…", symbol: "waveform")
        case .recording:
            recordingSurface(session)
        case .stopRequested:
            statusSurface(title: "Finishing your words…", symbol: "waveform")
        case .cancelRequested:
            launcher
        case .transcribing:
            statusSurface(title: "Transcribing and pasting…", symbol: "text.bubble")
        case .awaitingMode:
            modeSurface(session)
        case .insertRequested:
            statusSurface(title: "Inserting…", symbol: "arrow.down.doc")
        case .modeRequested, .rewriting:
            rewritingSurface(session)
        case .completed:
            statusSurface(title: "Pasted", symbol: "checkmark.circle.fill")
        case .failed:
            errorSurface(session)
        case .consumed:
            launcher
        }
    }

    private func recordingSurface(_ session: KeyboardDictationSession) -> some View {
        VStack(spacing: 15) {
            HStack {
                Button(action: cancelDictation) {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .frame(width: 42, height: 42)
                        .background(.white.opacity(0.08), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 1))
                }
                .accessibilityLabel("Cancel dictation")

                Spacer()
                VStack(spacing: 2) {
                    Text("Listening")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                    if let startedAt = session.startedAt {
                        Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(YapKeyboardPalette.paper.opacity(0.58))
                    }
                }
                Spacer()

                Button(action: requestStop) {
                    Image(systemName: "stop.fill")
                        .font(.headline)
                        .foregroundStyle(YapKeyboardPalette.ink)
                        .frame(width: 46, height: 46)
                        .background(YapKeyboardPalette.clay, in: RoundedRectangle(cornerRadius: 15))
                        .shadow(color: YapKeyboardPalette.clay.opacity(0.45), radius: 12)
                }
                .accessibilityLabel("Stop Yap dictation")
            }

            KeyboardWaveform(level: session.audioLevel ?? 0.18)
                .frame(height: 82)

            KeyboardTranscriptViewport(text: session.transcriptPreview)
        }
        .padding(.horizontal, 8)
    }

    private func modeSurface(_ session: KeyboardDictationSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(action: cancelDictation) {
                    Image(systemName: "xmark").frame(width: 34, height: 34)
                }
                Spacer()
                Text("How should this sound?")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                Spacer()
                Color.clear.frame(width: 34, height: 34)
            }

            ScrollView {
                Text(session.transcriptPreview ?? "")
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 92)
            .padding(10)
            .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.18), lineWidth: 1))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    modeButton(title: "None", emoji: nil, action: insertOriginal)
                    ForEach(model.modes) { mode in
                        modeButton(title: mode.name, emoji: mode.emoji) {
                            applyMode(mode.id)
                        }
                    }
                }
            }

            if let error = session.errorMessage?.nilIfBlank {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
        }
    }

    private func modeButton(
        title: String,
        emoji: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let emoji { Text(emoji) }
                Text(title).font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .foregroundStyle(YapKeyboardPalette.paper)
            .background(.white.opacity(0.09), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.24), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func rewritingSurface(_ session: KeyboardDictationSession) -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Writing in \(selectedModeName(session))…")
                .font(.headline)
            Text(session.transcriptPreview ?? "")
                .font(.callout)
                .foregroundStyle(YapKeyboardPalette.paper.opacity(0.58))
                .lineLimit(3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func statusSurface(title: String, symbol: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(YapKeyboardPalette.acid)
            Text(title)
                .font(.system(size: 17, weight: .black, design: .rounded))
            ProgressView().tint(YapKeyboardPalette.acid)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorSurface(_ session: KeyboardDictationSession) -> some View {
        VStack(spacing: 11) {
            Label("Couldn’t finish", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
            Text(session.errorMessage ?? "Try again, or insert the original transcript.")
                .font(.caption)
                .foregroundStyle(YapKeyboardPalette.paper.opacity(0.58))
                .multilineTextAlignment(.center)

            if session.transcriptPreview?.nilIfBlank != nil {
                Button("Insert original", action: insertOriginal)
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Try again", intent: StartKeyboardDictationIntent())
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func selectedModeName(_ session: KeyboardDictationSession) -> String {
        model.modes.first(where: { $0.id == session.selectedModeID })?.name ?? "your mode"
    }

    private func cardStrip(title: String, cards: [Card], compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.lowercased())
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundStyle(YapKeyboardPalette.paper.opacity(0.55))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(cards) { card in
                        KeyboardCardButton(card: card, compact: compact, insert: insert)
                    }
                }
            }
        }
    }

    private func clipboardStrip(title: String, items: [ClipboardItem]) -> some View {
        Group {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title.lowercased())
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(YapKeyboardPalette.paper.opacity(0.55))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(items) { item in
                                KeyboardClipboardButton(
                                    item: item,
                                    thumbnail: model.thumbnail(for: item)
                                ) {
                                    model.useClipboardItem(item, insert: insert)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct YapKeyboardAtmosphere: View {
    var body: some View {
        ZStack {
            YapKeyboardPalette.base
            LinearGradient(
                colors: [
                    Color(red: 0.38, green: 0.13, blue: 0.06),
                    Color(red: 0.26, green: 0.02, blue: 0.14),
                    YapKeyboardPalette.base
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(YapKeyboardPalette.clay.opacity(0.18))
                .frame(width: 220, height: 220)
                .blur(radius: 42)
                .offset(x: -120, y: 90)
            Circle()
                .fill(Color.pink.opacity(0.12))
                .frame(width: 180, height: 180)
                .blur(radius: 48)
                .offset(x: 140, y: -80)
        }
        .allowsHitTesting(false)
    }
}

private struct KeyboardWaveform: View {
    let level: Float

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.08)) { context in
            let tick = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<25, id: \.self) { index in
                    let pulse = (sin(tick * 8 + Double(index) * 0.72) + 1) / 2
                    let height = 10 + CGFloat(max(level, 0.12)) * 46 * CGFloat(0.35 + pulse * 0.65)
                    Capsule()
                        .fill(
                            index.isMultiple(of: 3)
                                ? YapKeyboardPalette.acid
                                : YapKeyboardPalette.acid.opacity(0.5)
                        )
                        .frame(width: 4, height: height)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct KeyboardTranscriptViewport: View {
    let text: String?
    private let bottomAnchor = "transcript-bottom"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    Text(text?.nilIfBlank ?? "Speak naturally — Hinglish is welcome.")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(
                            text?.nilIfBlank == nil
                                ? YapKeyboardPalette.paper.opacity(0.55)
                                : YapKeyboardPalette.paper
                        )
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                    Color.clear.frame(height: 1).id(bottomAnchor)
                }
            }
            .frame(height: 48)
            .onChange(of: text) {
                // Partial transcripts arrive rapidly; an unanimated move avoids visible fighting
                // while still keeping the newest words continuously in view.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    proxy.scrollTo(bottomAnchor, anchor: .bottom)
                }
            }
        }
        .accessibilityLabel(text?.nilIfBlank ?? "Speak naturally. Hinglish is welcome.")
    }
}
