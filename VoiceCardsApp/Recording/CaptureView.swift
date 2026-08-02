import SwiftUI
import UIKit

struct CaptureView: View {
    @State var model: RecordingSessionModel
    @Environment(\.scenePhase) private var scenePhase
    let autoStart: Bool
    let dismiss: () -> Void

    var body: some View {
        GeometryReader { proxy in
            Group {
                if model.keyboardHandoff.state == .notApplicable {
                    standardCaptureSurface
                } else {
                    keyboardCaptureSurface
                }
            }
            // Sheets can ask their content for an intrinsic size before resolving the detent.
            // Pinning to the measured container prevents progress states from shrinking the
            // atmosphere to the spinner/title's narrow ideal width.
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(
            model.phase == .recording || model.phase == .transcribing || model.phase == .enhancing
        )
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-uiTestEnhancementProgress") {
                model.phase = .enhancing
                return
            }
            #endif
            if autoStart && model.phase == .idle { await model.start() }
        }
        .onChange(of: model.phase) { _, phase in
            switch phase {
            case .recording:
                // The snap confirms the microphone is actually live, not merely that Start was tapped.
                YapHaptics.snap()
            case .ready:
                YapHaptics.contact()
            case .saved:
                YapHaptics.success()
                if model.keyboardHandoff.state == .notApplicable {
                    Task {
                        try? await Task.sleep(for: .milliseconds(500))
                        dismiss()
                    }
                }
            case .failed:
                YapHaptics.error()
            default:
                break
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                model.markReturnedToPreviousApp()
            }
        }
    }

    @ViewBuilder
    private var standardCaptureSurface: some View {
        switch model.phase {
        case .idle:
            YapCaptureStatusScreen(
                icon: .waveform,
                title: "ready when you are",
                detail: "speak naturally. yap keeps the words and cleans up the rest.",
                buttonTitle: "start yapping",
                action: {
                    YapHaptics.prepareForCapture()
                    Task { await model.start() }
                },
                close: dismiss
            )
        case .requestingPermission:
            YapCaptureProgressScreen(title: "turning the mic on…", close: dismiss)
        case .recording:
            YapRecordingScreen(
                transcript: model.transcript,
                level: model.recorder.level,
                elapsedText: elapsedText,
                stop: {
                    YapHaptics.snap()
                    Task { await model.stopAndTranscribe() }
                }
            )
        case .transcribing:
            YapCaptureProgressScreen(title: "making sense of that…", close: nil)
        case .enhancing:
            YapCaptureProgressScreen(title: "fixing the little things…", close: nil)
        case .ready, .rewriting:
            YapRewriteRevealScreen(
                model: model,
                elapsedText: elapsedText,
                sayAgain: {
                    YapHaptics.prepareForCapture()
                    Task {
                        await model.cancel()
                        await model.start()
                    }
                }
            )
        case .saving:
            YapCaptureProgressScreen(title: "remembering that…", close: nil)
        case .saved:
            YapCaptureStatusScreen(
                icon: .check,
                title: "saved & copied",
                detail: "ready wherever you want to paste it.",
                buttonTitle: nil,
                action: {},
                close: nil
            )
        case .failed(let message):
            YapCaptureStatusScreen(
                icon: .warning,
                title: "couldn’t finish",
                detail: message,
                buttonTitle: model.microphonePermissionDenied ? "open settings" : "try again",
                action: {
                    if model.microphonePermissionDenied {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    } else {
                        Task { await model.retryTranscription() }
                    }
                },
                close: dismiss
            )
        }
    }

    private var keyboardCaptureSurface: some View {
        keyboardHandoffContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(YapPalette.base)
        .foregroundStyle(YapPalette.paper)
    }

    @ViewBuilder
    private var keyboardHandoffContent: some View {
        switch model.phase {
        case .idle:
            VStack(spacing: YapSpacing.regular) {
                Text("Yap Flow is on")
                    .font(YapType.screenTitle)
                Text("Swipe back and tap Yap whenever you want to speak.")
                    .font(YapType.body)
                    .foregroundStyle(YapPalette.paper55)
                    .multilineTextAlignment(.center)
                Button("Start recording now") {
                    YapHaptics.prepareForCapture()
                    Task { await model.start() }
                }
                    .buttonStyle(YapPrimaryButtonStyle())
                Button("Close") {
                    Task {
                        await model.cancel()
                        dismiss()
                    }
                }
                .buttonStyle(YapGhostButtonStyle())
            }
            .padding(YapSpacing.large)
        case .requestingPermission:
            VStack(spacing: YapLayout.sectionSpacing) {
                ProgressView()
                    .controlSize(.large)
                    .tint(YapPalette.clay)
                Text("turning the mic on…")
                    .font(YapType.sectionTitle)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .recording:
            switch model.keyboardHandoff.state {
            case .preparing:
                VStack(spacing: YapLayout.sectionSpacing) {
                    WaveformView(level: model.recorder.level)
                        .tint(YapPalette.paper)
                    Text("turning live status on…")
                        .font(YapType.sectionTitle)
                    ProgressView()
                        .tint(YapPalette.clay)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .ready, .returned:
                KeyboardReturnCoach(
                    level: model.recorder.level,
                    elapsedText: elapsedText,
                    liveActivityResult: model.keyboardHandoff.liveActivityResult,
                    stop: {
                        YapHaptics.snap()
                        Task { await model.stopAndTranscribe() }
                    }
                )
            case .finished:
                ProgressView("Finishing recording…")
            case .notApplicable:
                EmptyView()
            }
        case .transcribing:
            YapCaptureProgressScreen(title: "turning speech into text…", close: nil)
        case .enhancing:
            YapCaptureProgressScreen(title: "fixing typos…", close: nil)
        case .rewriting:
            YapCaptureProgressScreen(title: "rewriting…", close: nil)
        case .saving:
            YapCaptureProgressScreen(title: "saving…", close: nil)
        case .saved:
            YapCaptureStatusScreen(
                icon: .check,
                title: "pasted",
                detail: "your words are back in the text field.",
                buttonTitle: nil,
                action: {},
                close: nil
            )
        case .failed(let message):
            YapCaptureStatusScreen(
                icon: .warning,
                title: "couldn’t finish",
                detail: message,
                buttonTitle: model.microphonePermissionDenied ? "open settings" : "try again",
                action: {
                    if model.microphonePermissionDenied {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    } else {
                        Task { await model.retryTranscription() }
                    }
                },
                close: dismiss
            )
        case .ready:
            Text(model.enhancedTranscript ?? model.transcript)
                .textSelection(.enabled)
        }
    }

    private var elapsedText: String {
        let seconds = Int(model.recorder.elapsed)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct YapRecordingScreen: View {
    let transcript: String
    let level: Float
    let elapsedText: String
    let stop: () -> Void

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HStack {
                    HStack(spacing: YapSpacing.small) {
                        Image("YapLiveDot")
                            .resizable()
                            .frame(width: 13, height: 13)
                        Text("listening")
                    }
                    .font(YapType.button)
                    .padding(.horizontal, YapSpacing.regular)
                    .frame(height: 39)
                    .yapPanel(cornerRadius: YapRadius.input)

                    Spacer()
                    Text(elapsedText)
                        .font(YapType.label)
                        .foregroundStyle(YapPalette.paper55)
                        .monospacedDigit()
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        Text(transcript.nilIfBlank ?? "go on, i’m listening…")
                            .font(YapType.screenTitle)
                            .tracking(-0.75)
                            .lineSpacing(7)
                            .foregroundStyle(transcript.isEmpty ? YapPalette.paper55 : YapPalette.paper)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("liveTranscript")
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: transcript) {
                        proxy.scrollTo("liveTranscript", anchor: .bottom)
                    }
                }
                .frame(maxHeight: 175)
                .padding(.top, YapSpacing.xxLarge)

                Spacer()

                WaveformView(level: level, maximumHeight: 86)
                    .tint(YapPalette.paper)

                Spacer()

                Button(action: stop) {
                    RoundedRectangle(cornerRadius: YapRadius.sheet, style: .continuous)
                        .fill(YapPalette.clay)
                        .frame(width: 96, height: 96)
                        .overlay {
                            RoundedRectangle(cornerRadius: YapRadius.sheet, style: .continuous)
                                .stroke(.white.opacity(0.35), lineWidth: 1.5)
                        }
                        .shadow(color: YapPalette.clay.opacity(0.6), radius: 28, y: 12)
                }
                .accessibilityLabel("Stop recording")

                Text("tap to stop")
                    .font(YapType.caption)
                    .foregroundStyle(YapPalette.paper55)
                    .padding(.top, YapSpacing.regular)
                    .padding(.bottom, YapSpacing.regular)
            }
            .padding(.horizontal, YapSpacing.large)
            // Leave the sheet grabber and rounded shoulder visually untouched.
            .padding(.top, YapSpacing.large)
            .safeAreaPadding(.bottom, YapSpacing.medium)
        }
        // Capture surfaces must claim the clear sheet before drawing their atmosphere.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { YapAuroraBackground(atmosphere: .capture) }
        .foregroundStyle(YapPalette.paper)
    }
}

private struct YapRewriteRevealScreen: View {
    @Bindable var model: RecordingSessionModel
    let elapsedText: String
    let sayAgain: () -> Void

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: YapLayout.sectionSpacing) {
                    HStack {
                        Text("just now · voice")
                            .foregroundStyle(YapPalette.paper55)
                        Spacer()
                        Button("say it again", action: sayAgain)
                            .font(YapType.label)
                            .padding(.horizontal, YapSpacing.regular)
                            .frame(height: 38)
                            .background(.white.opacity(0.09), in: Capsule())
                            .overlay(Capsule().stroke(.white.opacity(0.38), lineWidth: 1))
                    }
                    .font(YapType.caption)

                    VStack(alignment: .leading, spacing: YapSpacing.compact) {
                        Text("you said")
                            .font(YapType.label)
                            .foregroundStyle(YapPalette.paper55)
                        Text(model.transcript)
                            .font(YapType.body)
                            .lineSpacing(5)
                            .textSelection(.enabled)
                    }
                    .padding(YapSpacing.regular)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .yapPanel(cornerRadius: YapRadius.card, depth: .sunk)

                    modePicker

                    VStack(alignment: .leading, spacing: YapSpacing.regular) {
                        Text(selectedModeTitle)
                            .font(YapType.label)
                            .foregroundStyle(YapPalette.acid)

                        if model.phase == .rewriting {
                            ProgressView()
                                .tint(YapPalette.acid)
                                .frame(maxWidth: .infinity, minHeight: 130)
                        } else {
                            HStack(alignment: .bottom, spacing: 3) {
                                Text(resultText)
                                    .font(YapType.sectionTitle)
                                    .tracking(-0.55)
                                    .lineSpacing(7)
                                    .textSelection(.enabled)
                                Capsule()
                                    .fill(YapPalette.acid)
                                    .frame(width: 3, height: 25)
                                    .shadow(color: YapPalette.acid, radius: 9)
                            }
                        }
                    }
                    .padding(YapSpacing.medium)
                    .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
                    .yapPanel(cornerRadius: YapRadius.card)

                    if let notice = model.notice {
                        Text(notice)
                            .font(YapType.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal, YapSpacing.appHorizontal)
                .padding(.top, YapSpacing.large)
                .padding(.bottom, YapLayout.sectionSpacing)
            }
            .scrollIndicators(.hidden)
        }
        .background { YapAuroraBackground(atmosphere: .rewrite) }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomDock
        }
        .foregroundStyle(YapPalette.paper)
    }

    private var modePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: YapSpacing.small) {
                ForEach(model.modes) { mode in
                    Button {
                        YapHaptics.selection()
                        Task { await model.apply(mode: mode) }
                    } label: {
                        Text(displayName(for: mode))
                            .font(YapType.button)
                            .foregroundStyle(model.selectedModeID == mode.id ? YapPalette.ink : YapPalette.paper)
                            .padding(.horizontal, YapSpacing.regular)
                            .frame(minHeight: YapControlMetric.minimumTouchTarget)
                            .background(
                                model.selectedModeID == mode.id ? YapPalette.acid : .white.opacity(0.08),
                                in: Capsule()
                            )
                            .overlay(Capsule().stroke(.white.opacity(0.42), lineWidth: 1))
                            .shadow(
                                color: model.selectedModeID == mode.id ? YapPalette.acid.opacity(0.55) : .clear,
                                radius: 16
                            )
                    }
                    .disabled(model.phase == .rewriting)
                }

                Button(action: {}) {
                    Image(yapIcon: .plus)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 17, height: 17)
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.08), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.42), lineWidth: 1))
                }
                .accessibilityLabel("Add custom mode")
            }
        }
        .contentMargins(.horizontal, 0, for: .scrollContent)
    }

    private var bottomDock: some View {
        YapBottomDock {
            VStack(spacing: YapSpacing.small) {
                Text("tap a mode to re-run · export the before/after")
                    .font(YapType.caption)
                    .foregroundStyle(YapPalette.paper55)

                HStack(spacing: YapSpacing.compact) {
                    Button {
                        YapHaptics.contact()
                        Task { await model.saveAndCopy() }
                    } label: {
                        Text("copy & save")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(YapPrimaryButtonStyle())
                    .disabled(model.phase == .rewriting)

                    ShareLink(item: exportText) {
                        Image("YapExportGlyph")
                            .resizable()
                            .scaledToFit()
                            .frame(width: YapControlMetric.iconLarge, height: YapControlMetric.iconLarge)
                            .frame(width: 58, height: 58)
                            .background(.black.opacity(0.32), in: Circle())
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.42), lineWidth: 1))
                    }
                    .accessibilityLabel("Export before and after")
                }
            }
        }
    }

    private var selectedModeTitle: String {
        guard let selected = model.modes.first(where: { $0.id == model.selectedModeID }) else {
            return model.enhancedTranscript == nil ? "clean transcript" : "smart cleanup"
        }
        return "\(displayName(for: selected)) mode"
    }

    private var resultText: String {
        model.rewrittenText ?? model.enhancedTranscript ?? model.transcript
    }

    private var exportText: String {
        "You said:\n\(model.transcript)\n\n\(selectedModeTitle.capitalized):\n\(resultText)"
    }

    private func displayName(for mode: RewriteMode) -> String {
        switch mode.id.lowercased() {
        case "formal": "boss"
        case "hindi", "hindi-household": "hindi"
        default: mode.name.lowercased()
        }
    }
}

private struct YapCaptureProgressScreen: View {
    let title: String
    let close: (() -> Void)?

    var body: some View {
        ZStack {
            VStack(spacing: YapSpacing.large) {
                ProgressView()
                    .controlSize(.large)
                    .tint(YapPalette.acid)
                Text(title)
                    .font(YapType.screenTitle)
            }
            if let close {
                VStack {
                    HStack {
                        Spacer()
                        Button(action: close) {
                            Image(yapIcon: .close)
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 18, height: 18)
                                .frame(width: 44, height: 44)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .accessibilityLabel("Close")
                    }
                    Spacer()
                }
                .padding(.horizontal, YapSpacing.appHorizontal)
                // A sheet's rounded top edge can clip controls placed at y = 0.
                .padding(.top, YapSpacing.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { YapAuroraBackground(atmosphere: .capture) }
        .foregroundStyle(YapPalette.paper)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("captureProgressScreen")
    }
}

private struct YapCaptureStatusScreen: View {
    let icon: YapIcon
    let title: String
    let detail: String
    let buttonTitle: String?
    let action: () -> Void
    let close: (() -> Void)?

    var body: some View {
        ZStack {
            VStack(spacing: YapSpacing.regular) {
                Image(yapIcon: icon)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 42, height: 42)
                    .foregroundStyle(YapPalette.acid)
                Text(title)
                    .font(YapType.screenTitle)
                Text(detail)
                    .font(YapType.body)
                    .foregroundStyle(YapPalette.paper55)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let buttonTitle {
                    Button(buttonTitle, action: action)
                        .buttonStyle(YapPrimaryButtonStyle())
                        .padding(.top, YapSpacing.compact)
                }
            }
            .padding(YapSpacing.xLarge)
            .frame(maxWidth: 420)

            if let close {
                VStack {
                    HStack {
                        Spacer()
                        Button(action: close) {
                            Image(yapIcon: .close)
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 18, height: 18)
                                .frame(width: 44, height: 44)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .accessibilityLabel("Close")
                    }
                    Spacer()
                }
                .padding(.horizontal, YapSpacing.appHorizontal)
                .padding(.top, YapSpacing.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { YapAuroraBackground(atmosphere: .capture) }
        .foregroundStyle(YapPalette.paper)
    }
}

private struct KeyboardReturnCoach: View {
    let level: Float
    let elapsedText: String
    let liveActivityResult: LiveActivityStartResult?
    let stop: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var demonstratesSwipe = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: YapSpacing.compact) {
                HStack(spacing: YapSpacing.small) {
                    Image("YapLiveDot")
                        .resizable()
                        .frame(width: 10, height: 10)

                    Text("listening")
                        .font(YapType.button)
                        .tracking(-0.16)
                }
                .padding(.horizontal, YapSpacing.compact)
                .frame(height: 42)
                .background(.white.opacity(0.1), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.3), lineWidth: 1))

                Spacer(minLength: YapSpacing.compact)

                Text(elapsedText)
                    .font(YapType.button)
                    .foregroundStyle(YapPalette.paper55)
                    .monospacedDigit()

                Button(action: stop) {
                    RoundedRectangle(cornerRadius: YapRadius.input, style: .continuous)
                        .fill(YapPalette.clay)
                        .frame(width: 56, height: 56)
                        .overlay {
                        RoundedRectangle(cornerRadius: YapRadius.input, style: .continuous)
                                .stroke(.white.opacity(0.4), lineWidth: 1)
                        }
                        .shadow(color: YapPalette.clay.opacity(0.6), radius: 16)
                }
                .accessibilityLabel("Stop recording")
            }
            .padding(.horizontal, YapSpacing.large)
            .padding(.top, YapSpacing.small)

            Spacer()

            CoachWaveform(level: level)
                .tint(YapPalette.paper)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 78)

            Spacer()

            VStack(spacing: YapSpacing.compact) {
                if liveStatusUnavailable {
                    Text("live status is unavailable, but the mic is still on")
                        .font(YapType.caption)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }

                BottomEdgeSwipeHint(reduceMotion: reduceMotion, animate: demonstratesSwipe)
                    .frame(height: 24)

                Text("swipe right along the bottom edge to go back")
                    .font(YapType.caption)
                    .tracking(0.24)
                    .foregroundStyle(YapPalette.paper55)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, YapSpacing.large)
            .padding(.bottom, YapSpacing.large)
            .frame(maxWidth: .infinity)
        }
        .onAppear { demonstratesSwipe = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "Microphone is on. Swipe right along the bottom edge to return to your previous app."
        )
        .accessibilityIdentifier("keyboardReturnCoach")
    }

    private var liveStatusUnavailable: Bool {
        switch liveActivityResult {
        case .disabled, .failed: true
        case .started, nil: false
        }
    }
}

private struct CoachWaveform: View {
    let level: Float

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.08)) { context in
            let tick = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 4) {
                ForEach(0..<27, id: \.self) { index in
                    let center = 1 - abs(Double(index) - 13) / 13
                    let pulse = (sin(tick * 7.5 + Double(index) * 0.68) + 1) / 2
                    let energy = CGFloat(max(level, 0.16))
                    let height = 7 + energy * 47 * CGFloat(0.28 + center * 0.72 + pulse * 0.42)

                    Capsule()
                        .fill(.tint)
                        .frame(width: 4, height: min(height, 54))
                }
            }
        }
        .frame(height: 54)
        .accessibilityLabel("Live recording level")
    }
}

private struct BottomEdgeSwipeHint: View {
    let reduceMotion: Bool
    let animate: Bool

    var body: some View {
        HStack {
            Spacer()
            Image(yapIcon: .arrowRight)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(YapPalette.paper)
                .offset(x: reduceMotion ? 0 : (animate ? 0 : -34))
                .opacity(reduceMotion ? 1 : (animate ? 1 : 0.35))
                .animation(
                    reduceMotion
                        ? nil
                        : .easeInOut(duration: 1.15).repeatForever(autoreverses: false),
                    value: animate
                )
        }
        .accessibilityHidden(true)
    }
}
