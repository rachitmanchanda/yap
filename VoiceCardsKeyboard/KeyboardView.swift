import AppIntents
import SwiftUI
import UIKit

/// Keyboard extensions are separate processes, so they keep their own lightweight haptic
/// generators instead of depending on the main app's design-system target.
@MainActor
enum YapKeyboardHaptics {
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let contactGenerator = UIImpactFeedbackGenerator(style: .soft)
    private static let snapGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private static let notificationGenerator = UINotificationFeedbackGenerator()

    static func selection() {
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
    }

    static func contact() {
        contactGenerator.impactOccurred(intensity: 0.62)
        contactGenerator.prepare()
    }

    static func snap() {
        snapGenerator.impactOccurred(intensity: 0.86)
        snapGenerator.prepare()
    }

    static func success() {
        notificationGenerator.notificationOccurred(.success)
        notificationGenerator.prepare()
    }

    static func error() {
        notificationGenerator.notificationOccurred(.error)
        notificationGenerator.prepare()
    }
}

enum YapKeyboardPalette {
    static let base = Color(red: 0.043, green: 0.039, blue: 0.035)
    static let paper = Color(red: 0.98, green: 0.96, blue: 0.92)
    static let clay = Color(red: 0.89, green: 0.31, blue: 0.13)
    static let acid = Color(red: 0.84, green: 1.0, blue: 0.08)

    /// Keyboard extensions inherit the host's appearance. Dynamic UIKit colors let the
    /// surface follow that appearance without maintaining two separate SwiftUI trees.
    static let ink = adaptive(
        light: UIColor(red: 0.04, green: 0.04, blue: 0.035, alpha: 1),
        dark: UIColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1)
    )
    // These values sit close to the system keyboard surfaces, removing the bright seam
    // between Yap and iOS-owned keyboard chrome in either appearance.
    static let keyboardBackground = adaptive(
        light: UIColor(red: 221.0 / 255.0, green: 224.0 / 255.0, blue: 228.0 / 255.0, alpha: 1),
        dark: UIColor(red: 23.0 / 255.0, green: 23.0 / 255.0, blue: 25.0 / 255.0, alpha: 1)
    )
    static let keyboardPanel = adaptive(
        light: UIColor(red: 249.0 / 255.0, green: 249.0 / 255.0, blue: 252.0 / 255.0, alpha: 1),
        dark: UIColor(red: 44.0 / 255.0, green: 44.0 / 255.0, blue: 46.0 / 255.0, alpha: 1)
    )
    static let mutedInk = adaptive(
        light: UIColor(red: 0.431, green: 0.424, blue: 0.4, alpha: 1),
        dark: UIColor(red: 0.66, green: 0.66, blue: 0.69, alpha: 1)
    )
    static let strongFill = adaptive(light: .black, dark: .white)
    static let onStrongFill = adaptive(light: .white, dark: .black)
    static let outline = adaptive(
        light: UIColor.white.withAlphaComponent(0.5),
        dark: UIColor.white.withAlphaComponent(0.14)
    )

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

/// The keyboard ships a deliberately small subset of Yap's solid Figma icon library to keep
/// extension launch time and memory use low.
enum YapKeyboardIcon: String {
    case chat
    case clipboard
    case close
    case globe
    case image
    case externalLink
    case lock
    case microphone
    case search
    case stop
    case warning
    case waveform

    var assetName: String {
        "YapIcon\(rawValue.prefix(1).uppercased())\(rawValue.dropFirst())"
    }
}

struct KeyboardView: View {
    @Bindable var model: KeyboardModel
    let insert: (String) -> Void
    let requestStart: () -> Void
    let requestStop: () -> Void
    let cancelDictation: () -> Void
    let insertOriginal: () -> Void
    let applyMode: (String) -> Void
    let requestForegroundHandoff: () -> Void
    let refreshAccess: () -> Void

    @State private var selectedKind: ClipboardItemKind = .text

    private var filteredClipboardItems: [ClipboardItem] {
        let source = model.query.isEmpty ? model.clipboardItems : model.clipboardSearchResults
        return source.filter { $0.kind == selectedKind }
    }

    private var filteredCards: [Card] {
        guard selectedKind == .text else { return [] }
        return model.query.isEmpty ? model.cards : model.searchResults
    }

    var body: some View {
        Group {
            if let session = model.dictationSession {
                if session.phase == .readyForCapture {
                    cardsSurface
                } else {
                    sessionSurface(session)
                }
            } else {
                // Clipboard recall must remain useful even before Flow is armed. The orange Yap
                // button communicates the one foreground handoff without replacing this surface.
                cardsSurface
            }
        }
        // Fill whatever height iOS grants the extension. A fixed 329-point child could
        // leave the rounded UIInputView host visible as a differently tinted cap.
        .frame(maxWidth: .infinity, minHeight: 329, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(YapKeyboardPalette.ink)
        .background(YapKeyboardPalette.keyboardBackground)
        .task { refreshAccess() }
        .onChange(of: model.dictationSession) { _, session in
            guard let phase = session?.phase else { return }
            switch phase {
            case .recording:
                // Confirm the recorder is live rather than buzzing optimistically on launch.
                YapKeyboardHaptics.snap()
            case .awaitingMode:
                YapKeyboardHaptics.contact()
            case .completed:
                YapKeyboardHaptics.success()
            case .failed:
                YapKeyboardHaptics.error()
            default:
                break
            }
        }
    }

    private var cardsSurface: some View {
        VStack(alignment: .leading, spacing: YapSpacing.small) {
            HStack(alignment: .center, spacing: YapSpacing.compact) {
                Text("start yapping.")
                    .font(YapType.screenTitle)
                    .tracking(-0.55)
                    .foregroundStyle(YapKeyboardPalette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)

                captureButton
            }
            .frame(minHeight: YapControlMetric.minimumTouchTarget)

            HStack(spacing: YapSpacing.small) {
                keyboardFilterChip(title: "text", kind: .text)
                keyboardFilterChip(title: "image", kind: .image)
                keyboardFilterChip(title: "link", kind: .url)
            }

            Text(model.query.isEmpty ? "recent" : "results")
                .font(YapType.metadata)
                .tracking(0.24)
                .foregroundStyle(YapKeyboardPalette.mutedInk)

            ScrollView(.vertical, showsIndicators: false) {
                keyboardRecentRows
            }
            // The list meets iOS-owned keyboard chrome below us. Fading the final rows
            // makes that boundary feel continuous instead of clipping content sharply.
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.82),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .padding(.horizontal, YapSpacing.keyboardHorizontal)
        .padding(.top, YapSpacing.regular)
        .padding(.bottom, YapSpacing.compact)
        .overlay(alignment: .bottom) {
            if let notice = model.clipboardNotice?.nilIfBlank {
                Text(notice)
                    .font(YapType.label)
                    .foregroundStyle(YapKeyboardPalette.onStrongFill)
                    .padding(.horizontal, YapSpacing.compact)
                    .frame(minHeight: 34)
                    .background(YapKeyboardPalette.strongFill.opacity(0.92), in: Capsule())
                    .overlay(Capsule().stroke(YapKeyboardPalette.outline, lineWidth: 1))
                    .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
                    .padding(.bottom, YapSpacing.compact)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private var captureButton: some View {
        if model.isFlowReady {
            Button {
                YapKeyboardHaptics.snap()
                requestStart()
            } label: {
                captureButtonLabel
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start Yap dictation")
        } else {
            if #available(iOS 26.0, *) {
                Button(intent: StartKeyboardDictationForegroundIntent()) {
                    captureButtonLabel
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open Yap and start recording")
            } else if #available(iOS 18.0, *) {
                Button(intent: StartKeyboardDictationIntent()) {
                    captureButtonLabel
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open Yap and start Flow")
            } else {
                Button(action: requestForegroundHandoff) {
                    captureButtonLabel
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open Yap and start Flow")
            }
        }
    }

    private var captureButtonLabel: some View {
        Image("YapMark")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(YapKeyboardPalette.paper)
            .frame(width: YapControlMetric.iconLarge, height: YapControlMetric.iconRegular)
            .frame(
                width: YapControlMetric.minimumTouchTarget,
                height: YapControlMetric.minimumTouchTarget
            )
            .background(YapKeyboardPalette.clay, in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.45), lineWidth: 1))
            .shadow(color: YapKeyboardPalette.clay.opacity(0.55), radius: 10, y: 6)
    }

    @ViewBuilder
    private var keyboardRecentRows: some View {
        if !model.canReadSharedStorage {
            FullAccessExplainer(
                fullAccessReported: model.hasFullAccess,
                diagnostic: model.errorMessage,
                refreshAccess: refreshAccess
            )
        } else if filteredClipboardItems.isEmpty && filteredCards.isEmpty {
            Text(
                model.query.isEmpty
                    ? "your recent \(selectedKind.title.lowercased()) will appear here"
                    : "nothing matched that"
            )
            .font(YapType.caption)
            .foregroundStyle(YapKeyboardPalette.mutedInk)
            .frame(maxWidth: .infinity, minHeight: 72)
        } else {
            LazyVStack(spacing: YapSpacing.small) {
                ForEach(filteredClipboardItems.prefix(6)) { item in
                    keyboardClipboardRow(item)
                }
                ForEach(filteredCards.prefix(6)) { card in
                    keyboardCardRow(card)
                }
            }
        }
    }

    private func keyboardFilterChip(title: String, kind: ClipboardItemKind) -> some View {
        Button {
            YapKeyboardHaptics.selection()
            selectedKind = kind
        } label: {
            Text(title)
                .font(YapType.button)
                .tracking(-0.15)
                .foregroundStyle(
                    selectedKind == kind
                        ? YapKeyboardPalette.onStrongFill
                        : YapKeyboardPalette.mutedInk
                )
                .padding(.horizontal, YapSpacing.regular)
                .frame(minHeight: YapControlMetric.minimumTouchTarget)
                .background(
                    selectedKind == kind
                        ? YapKeyboardPalette.strongFill
                        : YapKeyboardPalette.keyboardPanel,
                    in: Capsule()
                )
                .overlay(Capsule().stroke(YapKeyboardPalette.outline, lineWidth: 1))
                .shadow(
                    color: selectedKind == kind
                        ? YapKeyboardPalette.acid.opacity(0.3)
                        : .clear,
                    radius: 10
                )
        }
        .buttonStyle(.plain)
    }

    private func keyboardClipboardRow(_ item: ClipboardItem) -> some View {
        Button {
            model.useClipboardItem(item, insert: insert)
            YapKeyboardHaptics.success()
        } label: {
            HStack(spacing: YapSpacing.small) {
                if let thumbnail = model.thumbnail(for: item) {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 42, height: 38)
                        .clipShape(RoundedRectangle(cornerRadius: YapRadius.chip, style: .continuous))
                }
                VStack(alignment: .leading, spacing: YapSpacing.xSmall) {
                    Text(item.kind == .image ? "copied image" : item.displayText)
                        .font(YapType.bodyStrong)
                        .tracking(-0.15)
                        .lineLimit(1)
                    if item.kind != .image {
                        Text(item.displayText)
                            .font(YapType.metadata)
                            .tracking(0.24)
                            .foregroundStyle(YapKeyboardPalette.mutedInk)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(YapKeyboardPalette.ink)
            .padding(.horizontal, YapSpacing.compact)
            .frame(maxWidth: .infinity, minHeight: YapControlMetric.compact, alignment: .leading)
            .background(YapKeyboardPalette.keyboardPanel, in: RoundedRectangle(cornerRadius: YapRadius.chip))
            .overlay(
                RoundedRectangle(cornerRadius: YapRadius.chip)
                    .stroke(YapKeyboardPalette.outline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func keyboardCardRow(_ card: Card) -> some View {
        Button {
            insert(card.preferredText)
            YapKeyboardHaptics.success()
        } label: {
            VStack(alignment: .leading, spacing: YapSpacing.xSmall) {
                Text(card.title)
                    .font(YapType.bodyStrong)
                    .tracking(-0.15)
                    .lineLimit(1)
                Text(card.preferredText)
                    .font(YapType.metadata)
                    .tracking(0.24)
                    .foregroundStyle(YapKeyboardPalette.mutedInk)
                    .lineLimit(1)
            }
            .foregroundStyle(YapKeyboardPalette.ink)
            .padding(.horizontal, YapSpacing.compact)
            .frame(maxWidth: .infinity, minHeight: YapControlMetric.compact, alignment: .leading)
            .background(YapKeyboardPalette.keyboardPanel, in: RoundedRectangle(cornerRadius: YapRadius.chip))
            .overlay(
                RoundedRectangle(cornerRadius: YapRadius.chip)
                    .stroke(YapKeyboardPalette.outline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Paste \(card.title)")
    }

    @ViewBuilder
    private func sessionSurface(_ session: KeyboardDictationSession) -> some View {
        switch session.phase {
        case .launching:
            statusSurface(title: "Starting microphone…", icon: .waveform)
        case .startRequested:
            statusSurface(title: "listening…", icon: .waveform)
        case .readyForCapture:
            cardsSurface
        case .recording:
            recordingSurface(session)
        case .stopRequested:
            statusSurface(title: "finishing your words…", icon: .waveform)
        case .cancelRequested:
            cardsSurface
        case .endFlowRequested:
            cardsSurface
        case .transcribing:
            statusSurface(title: "turning speech into text…", icon: .chat)
        case .enhancing:
            statusSurface(title: "fixing typos…", icon: .chat)
        case .awaitingMode:
            modeSurface(session)
        case .insertRequested:
            statusSurface(title: "inserting…", icon: .clipboard)
        case .modeRequested, .rewriting:
            rewritingSurface(session)
        case .completed:
            statusSurface(title: "pasted", icon: .clipboard)
        case .failed:
            errorSurface(session)
        case .flowExpired:
            cardsSurface
        case .consumed:
            cardsSurface
        }
    }

    private var flowExpiredSurface: some View {
        cardsSurface
    }

    private func recordingSurface(_ session: KeyboardDictationSession) -> some View {
        VStack(spacing: 0) {
            KeyboardTranscriptViewport(text: session.transcriptPreview)
                .padding(.horizontal, YapSpacing.keyboardHorizontal)
                .padding(.top, YapSpacing.large)

            Spacer(minLength: YapSpacing.small)

            KeyboardWaveform(level: session.audioLevel ?? 0.18)
                .frame(height: 60)

            Spacer(minLength: YapSpacing.small)

            Button {
                YapKeyboardHaptics.snap()
                requestStop()
            } label: {
                RoundedRectangle(cornerRadius: YapRadius.sheet, style: .continuous)
                    .fill(YapKeyboardPalette.clay)
                    .frame(width: 96, height: 96)
                    .overlay {
                        ZStack {
                            RoundedRectangle(cornerRadius: YapRadius.sheet, style: .continuous)
                                .stroke(.white.opacity(0.45), lineWidth: 1.5)
                            Image(YapKeyboardIcon.stop.assetName)
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(.white)
                                .frame(width: YapControlMetric.iconLarge, height: YapControlMetric.iconLarge)
                        }
                    }
                    .shadow(color: YapKeyboardPalette.clay.opacity(0.55), radius: 26)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop Yap dictation")
            .padding(.bottom, YapSpacing.medium)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(YapKeyboardPalette.keyboardBackground)
    }

    private func modeSurface(_ session: KeyboardDictationSession) -> some View {
        VStack(alignment: .leading, spacing: YapSpacing.small) {
            HStack {
                Button {
                    YapKeyboardHaptics.contact()
                    cancelDictation()
                } label: {
                    Image(YapKeyboardIcon.close.assetName)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: YapControlMetric.iconSmall, height: YapControlMetric.iconSmall)
                        .frame(
                            width: YapControlMetric.minimumTouchTarget,
                            height: YapControlMetric.minimumTouchTarget
                        )
                }
                Spacer()
                Text("paste it your way")
                    .font(YapType.sectionTitle)
                Spacer()
                Color.clear.frame(
                    width: YapControlMetric.minimumTouchTarget,
                    height: YapControlMetric.minimumTouchTarget
                )
            }

            VStack(alignment: .leading, spacing: YapSpacing.xSmall) {
                Text("cleaned up")
                    .font(YapType.metadata)
                    .foregroundStyle(YapKeyboardPalette.mutedInk)
                ScrollView {
                    Text(session.transcriptPreview ?? "")
                        .font(YapType.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .frame(maxHeight: 92)
            .padding(YapSpacing.compact)
            .background(YapKeyboardPalette.keyboardPanel, in: RoundedRectangle(cornerRadius: YapRadius.input))
            .overlay(
                RoundedRectangle(cornerRadius: YapRadius.input)
                    .stroke(YapKeyboardPalette.outline, lineWidth: 1)
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: YapSpacing.small) {
                    modeButton(
                        title: "clean",
                        emoji: nil,
                        isSelected: session.selectedModeID == nil,
                        action: insertOriginal
                    )
                    ForEach(model.modes) { mode in
                        modeButton(
                            title: mode.name,
                            emoji: mode.emoji,
                            isSelected: session.selectedModeID == mode.id
                        ) {
                            applyMode(mode.id)
                        }
                    }
                }
            }

            if let error = session.errorMessage?.nilIfBlank {
                Text(error)
                    .font(YapType.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, YapSpacing.keyboardHorizontal)
        .padding(.top, YapSpacing.regular)
        .padding(.bottom, YapSpacing.compact)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(YapKeyboardPalette.ink)
        .background(YapKeyboardPalette.keyboardBackground)
    }

    private func modeButton(
        title: String,
        emoji: String?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            YapKeyboardHaptics.selection()
            action()
        } label: {
            HStack(spacing: YapSpacing.xSmall) {
                if let emoji { Text(emoji) }
                Text(title).font(YapType.button)
            }
            .padding(.horizontal, YapSpacing.compact)
            .frame(minHeight: YapControlMetric.minimumTouchTarget)
            .foregroundStyle(isSelected ? YapKeyboardPalette.ink : YapKeyboardPalette.mutedInk)
            .background(
                isSelected ? YapKeyboardPalette.acid : YapKeyboardPalette.keyboardPanel,
                in: Capsule()
            )
            .overlay(Capsule().stroke(YapKeyboardPalette.outline, lineWidth: 1))
            .shadow(
                color: isSelected ? YapKeyboardPalette.acid.opacity(0.32) : .clear,
                radius: 9
            )
        }
        .buttonStyle(.plain)
    }

    private func rewritingSurface(_ session: KeyboardDictationSession) -> some View {
        VStack(spacing: YapSpacing.regular) {
            ProgressView()
                .controlSize(.large)
            Text("Writing in \(selectedModeName(session))…")
                .font(YapType.sectionTitle)
            Text(session.transcriptPreview ?? "")
                .font(YapType.body)
                .foregroundStyle(YapKeyboardPalette.mutedInk)
                .lineLimit(3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(YapKeyboardPalette.ink)
        .background(YapKeyboardPalette.keyboardBackground)
    }

    private func statusSurface(title: String, icon: YapKeyboardIcon) -> some View {
        VStack(spacing: YapSpacing.compact) {
            Image(icon.assetName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: YapControlMetric.iconLarge, height: YapControlMetric.iconLarge)
                .foregroundStyle(YapKeyboardPalette.clay)
            Text(title)
                .font(YapType.sectionTitle)
            ProgressView().tint(YapKeyboardPalette.clay)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(YapKeyboardPalette.ink)
        .background(YapKeyboardPalette.keyboardBackground)
    }

    @ViewBuilder
    private func errorSurface(_ session: KeyboardDictationSession) -> some View {
        if session.transcriptPreview?.nilIfBlank == nil {
            // Activation failures should never hide clipboard recall. The orange Yap button on
            // the normal keyboard remains the retry/open action.
            cardsSurface
        } else {
            transcriptRecoverySurface(session)
        }
    }

    private func startFlowSurface(message: String) -> some View {
        VStack(spacing: YapSpacing.large) {
            Image("YapMark")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(YapKeyboardPalette.clay)
                .frame(width: 52, height: 38)

            if #available(iOS 26.0, *) {
                Button(intent: StartKeyboardDictationForegroundIntent()) {
                    startFlowButtonLabel
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Start yapping in Yap")
            } else if #available(iOS 18.0, *) {
                Button(intent: StartKeyboardDictationIntent()) {
                    startFlowButtonLabel
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Start yapping in Yap")
            } else {
                Button(action: requestForegroundHandoff) {
                    startFlowButtonLabel
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Start yapping in Yap")
            }

            Text(message)
                .font(YapType.caption)
                .foregroundStyle(YapKeyboardPalette.mutedInk)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 290)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(YapKeyboardPalette.ink)
        .background(YapKeyboardPalette.keyboardBackground)
    }

    private var startFlowButtonLabel: some View {
        HStack(spacing: YapSpacing.small) {
            Text("Start yapping")
            Image(YapKeyboardIcon.waveform.assetName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: YapControlMetric.iconRegular, height: YapControlMetric.iconRegular)
        }
        .font(YapType.sectionTitle)
        .foregroundStyle(YapKeyboardPalette.paper)
        .frame(maxWidth: 280, minHeight: 58)
        .background(YapKeyboardPalette.clay, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 1))
        .shadow(color: YapKeyboardPalette.clay.opacity(0.4), radius: 12, y: 6)
    }

    private func transcriptRecoverySurface(_ session: KeyboardDictationSession) -> some View {
        VStack(spacing: YapSpacing.compact) {
            HStack(spacing: YapSpacing.small) {
                Image(YapKeyboardIcon.warning.assetName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: YapControlMetric.iconRegular, height: YapControlMetric.iconRegular)
                Text("Couldn’t finish")
            }
                .font(.headline)
            Text(session.errorMessage ?? "Try again, or insert the original transcript.")
                .font(YapType.caption)
                .foregroundStyle(YapKeyboardPalette.mutedInk)
                .multilineTextAlignment(.center)

            Button("Insert original", action: insertOriginal)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(YapKeyboardPalette.ink)
        .background(YapKeyboardPalette.keyboardBackground)
    }

    private func selectedModeName(_ session: KeyboardDictationSession) -> String {
        model.modes.first(where: { $0.id == session.selectedModeID })?.name ?? "your mode"
    }

}

private struct KeyboardWaveform: View {
    let level: Float

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.08)) { context in
            let tick = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<27, id: \.self) { index in
                    let pulse = (sin(tick * 8 + Double(index) * 0.72) + 1) / 2
                    let envelope = 0.45 + sin(Double(index) * 0.78) * 0.22
                    let height = 7 + CGFloat(max(level, 0.12)) * 48
                        * CGFloat(max(0.2, envelope + pulse * 0.4))
                    Capsule()
                        .fill(YapKeyboardPalette.ink)
                        .frame(width: 3, height: min(height, 54))
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
                    Text(text?.nilIfBlank ?? "go on, i’m listening…")
                        .font(YapType.body)
                        .tracking(-0.2)
                        .lineSpacing(3)
                        .foregroundStyle(
                            text?.nilIfBlank == nil
                                ? YapKeyboardPalette.mutedInk
                                : YapKeyboardPalette.ink
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                    Color.clear.frame(height: 1).id(bottomAnchor)
                }
            }
            .frame(height: 78)
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
        .accessibilityLabel(text?.nilIfBlank ?? "Go on, I’m listening.")
    }
}
