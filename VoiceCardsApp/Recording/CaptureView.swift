import SwiftUI
import UIKit

struct CaptureView: View {
    @State var model: RecordingSessionModel
    @Environment(\.scenePhase) private var scenePhase
    let autoStart: Bool
    let dismiss: () -> Void

    var body: some View {
        Group {
            if model.keyboardHandoff.state == .notApplicable {
                standardCaptureSurface
            } else {
                keyboardCaptureSurface
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(model.phase == .recording || model.phase == .transcribing)
        .task {
            if autoStart && model.phase == .idle { await model.start() }
        }
        .onChange(of: model.phase) { _, phase in
            if phase == .saved {
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    dismiss()
                }
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
                icon: "waveform",
                title: "ready when you are",
                detail: "speak naturally. yap keeps the words and cleans up the rest.",
                buttonTitle: "start yapping",
                action: { Task { await model.start() } },
                close: dismiss
            )
        case .requestingPermission:
            YapCaptureProgressScreen(title: "turning the mic on…", close: dismiss)
        case .recording:
            YapRecordingScreen(
                transcript: model.transcript,
                level: model.recorder.level,
                elapsedText: elapsedText,
                stop: { Task { await model.stopAndTranscribe() } }
            )
        case .transcribing:
            YapCaptureProgressScreen(title: "making sense of that…", close: nil)
        case .ready, .rewriting:
            YapRewriteRevealScreen(
                model: model,
                elapsedText: elapsedText,
                sayAgain: {
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
                icon: "checkmark",
                title: "saved & copied",
                detail: "ready wherever you want to paste it.",
                buttonTitle: nil,
                action: {},
                close: nil
            )
        case .failed(let message):
            YapCaptureStatusScreen(
                icon: "exclamationmark.triangle.fill",
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
        ZStack {
            ScrollView {
                VStack(spacing: YapLayout.sectionSpacing) {
                    keyboardCaptureHeader
                    keyboardHandoffContent
                    if let notice = model.notice {
                        Text(notice)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 20)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, YapLayout.dockBottomInset)
            }
            .scrollIndicators(.hidden)
        }
        .background { YapAuroraBackground(atmosphere: .capture) }
        .foregroundStyle(YapPalette.paper)
    }

    private var keyboardCaptureHeader: some View {
        HStack {
            Button {
                Task {
                    await model.cancel()
                    dismiss()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .black))
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.28), in: Circle())
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.36), lineWidth: 1))
            }
            .accessibilityLabel(model.phase == .recording ? "Cancel" : "Close")

            Spacer()

            HStack(spacing: 8) {
                Circle()
                    .fill(model.phase == .recording ? Color.red : YapPalette.paper55)
                    .frame(width: 8, height: 8)
                Text(model.phase == .recording ? "listening" : "keyboard capture")
            }
            .font(.system(size: 14, weight: .heavy, design: .rounded))
            .padding(.horizontal, 14)
            .frame(height: 36)
            .yapPanel(cornerRadius: 18)

            Spacer()

            Color.clear
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.black.opacity(0.24))
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.28), lineWidth: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.16))
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var keyboardHandoffContent: some View {
        switch model.phase {
        case .idle:
            ScrollView {
                Button("Start recording") { Task { await model.start() } }
                    .buttonStyle(YapPrimaryButtonStyle())
            }
        case .requestingPermission:
            VStack(spacing: YapLayout.sectionSpacing) {
                ProgressView()
                    .controlSize(.large)
                    .tint(YapPalette.acid)
                Text("turning the mic on…")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
            }
            .frame(maxWidth: .infinity, minHeight: 320)
        case .recording:
            switch model.keyboardHandoff.state {
            case .preparing:
                VStack(spacing: YapLayout.sectionSpacing) {
                    WaveformView(level: model.recorder.level)
                        .tint(YapPalette.acid)
                    Label("mic is on", systemImage: "mic.fill")
                        .font(.system(size: 21, weight: .heavy, design: .rounded))
                    ProgressView("preparing live status…")
                        .tint(YapPalette.acid)
                }
                .frame(maxWidth: .infinity, minHeight: 360)
            case .ready, .returned:
                KeyboardReturnCoach(
                    transcript: model.transcript,
                    level: model.recorder.level,
                    elapsedText: elapsedText,
                    liveActivityResult: model.keyboardHandoff.liveActivityResult,
                    stop: { Task { await model.stopAndTranscribe() } }
                )
            case .finished:
                ProgressView("Finishing recording…")
            case .notApplicable:
                EmptyView()
            }
        case .transcribing:
            ProgressView("Transcribing…")
        case .rewriting:
            ProgressView("Rewriting…")
        case .saving:
            ProgressView("Saving…")
        case .saved:
            Label("Inserted", systemImage: "checkmark.circle.fill")
        case .failed(let message):
            ContentUnavailableView("Couldn’t finish", systemImage: "exclamationmark.triangle", description: Text(message))
            if model.microphonePermissionDenied {
                Button("Open Microphone Settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
            } else {
                Button("Try again") { Task { await model.retryTranscription() } }
            }
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
                    HStack(spacing: 10) {
                        Image("YapLiveDot")
                            .resizable()
                            .frame(width: 13, height: 13)
                        Text("listening")
                    }
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .padding(.horizontal, 15)
                    .frame(height: 39)
                    .yapPanel(cornerRadius: 20)

                    Spacer()
                    Text(elapsedText)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(YapPalette.paper55)
                        .monospacedDigit()
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        Text(transcript.nilIfBlank ?? "go on, i’m listening…")
                            .font(.system(size: 27, weight: .medium, design: .rounded))
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
                .padding(.top, 42)

                Spacer()

                WaveformView(level: level, maximumHeight: 86)
                    .tint(YapPalette.paper)

                Spacer()

                Button(action: stop) {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(YapPalette.clay)
                        .frame(width: 96, height: 96)
                        .overlay {
                            RoundedRectangle(cornerRadius: 30, style: .continuous)
                                .stroke(.white.opacity(0.35), lineWidth: 1.5)
                        }
                        .shadow(color: YapPalette.clay.opacity(0.6), radius: 28, y: 12)
                }
                .accessibilityLabel("Stop recording")

                Text("tap to stop")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(YapPalette.paper55)
                    .padding(.top, 17)
                    .padding(.bottom, 18)
            }
            .padding(.horizontal, 22)
            // Leave the sheet grabber and rounded shoulder visually untouched.
            .padding(.top, 24)
            .safeAreaPadding(.bottom, 20)
        }
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
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .padding(.horizontal, 17)
                            .frame(height: 38)
                            .background(.white.opacity(0.09), in: Capsule())
                            .overlay(Capsule().stroke(.white.opacity(0.38), lineWidth: 1))
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))

                    VStack(alignment: .leading, spacing: 12) {
                        Text("you said")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(YapPalette.paper55)
                        Text(model.transcript)
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .lineSpacing(5)
                            .textSelection(.enabled)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .yapPanel(cornerRadius: 27, depth: .sunk)

                    modePicker

                    VStack(alignment: .leading, spacing: 16) {
                        Text(selectedModeTitle)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(YapPalette.acid)

                        if model.phase == .rewriting {
                            ProgressView()
                                .tint(YapPalette.acid)
                                .frame(maxWidth: .infinity, minHeight: 130)
                        } else {
                            HStack(alignment: .bottom, spacing: 3) {
                                Text(resultText)
                                    .font(.system(size: 22, weight: .medium, design: .rounded))
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
                    .padding(20)
                    .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
                    .yapPanel(cornerRadius: 28)

                    if let notice = model.notice {
                        Text(notice)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 28)
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
            HStack(spacing: 10) {
                ForEach(model.modes) { mode in
                    Button {
                        Task { await model.apply(mode: mode) }
                    } label: {
                        Text(displayName(for: mode))
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(model.selectedModeID == mode.id ? YapPalette.ink : YapPalette.paper)
                            .padding(.horizontal, 18)
                            .frame(height: 44)
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
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
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
        VStack(spacing: 10) {
            Text("tap a mode to re-run · export the before/after")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(YapPalette.paper55)

            HStack(spacing: 12) {
                Button {
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
                        .frame(width: 23, height: 23)
                        .frame(width: 58, height: 58)
                        .background(.black.opacity(0.32), in: Circle())
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.42), lineWidth: 1))
                }
                .accessibilityLabel("Export before and after")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, YapLayout.dockTopInset)
        .safeAreaPadding(.bottom, YapLayout.dockBottomInset)
        .background(.black.opacity(0.34))
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(.white.opacity(0.2)).frame(height: 1)
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
            VStack(spacing: 24) {
                ProgressView()
                    .controlSize(.large)
                    .tint(YapPalette.acid)
                Text(title)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
            }
            if let close {
                VStack {
                    HStack {
                        Spacer()
                        Button(action: close) {
                            Image(systemName: "xmark")
                                .frame(width: 44, height: 44)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .accessibilityLabel("Close")
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                // A sheet's rounded top edge can clip controls placed at y = 0.
                .padding(.top, 24)
            }
        }
        .background { YapAuroraBackground(atmosphere: .capture) }
        .foregroundStyle(YapPalette.paper)
    }
}

private struct YapCaptureStatusScreen: View {
    let icon: String
    let title: String
    let detail: String
    let buttonTitle: String?
    let action: () -> Void
    let close: (() -> Void)?

    var body: some View {
        ZStack {
            VStack(spacing: 18) {
                Image(systemName: icon)
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(YapPalette.acid)
                Text(title)
                    .font(.system(size: 28, weight: .black, design: .rounded))
                Text(detail)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(YapPalette.paper55)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let buttonTitle {
                    Button(buttonTitle, action: action)
                        .buttonStyle(YapPrimaryButtonStyle())
                        .padding(.top, 12)
                }
            }
            .padding(30)
            .frame(maxWidth: 420)

            if let close {
                VStack {
                    HStack {
                        Spacer()
                        Button(action: close) {
                            Image(systemName: "xmark")
                                .frame(width: 44, height: 44)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .accessibilityLabel("Close")
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
            }
        }
        .background { YapAuroraBackground(atmosphere: .capture) }
        .foregroundStyle(YapPalette.paper)
    }
}

private struct KeyboardReturnCoach: View {
    let transcript: String
    let level: Float
    let elapsedText: String
    let liveActivityResult: LiveActivityStartResult?
    let stop: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var demonstratesSwipe = false

    var body: some View {
        VStack(spacing: YapLayout.sectionSpacing) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("mic is on")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .tracking(-0.7)
                    Text("keep talking naturally")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(YapPalette.paper55)
                }

                Spacer()

                Text(elapsedText)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(YapPalette.paper82)
                    .monospacedDigit()

                Button(action: stop) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.red)
                        .frame(width: 48, height: 48)
                        .overlay {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.white)
                                .frame(width: 14, height: 14)
                        }
                }
                .accessibilityLabel("Stop recording")
            }

            WaveformView(level: level, maximumHeight: 48)
                .tint(YapPalette.acid)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)

            ScrollViewReader { proxy in
                ScrollView {
                    Text(transcript.nilIfBlank ?? "your words will appear here as you speak…")
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .foregroundStyle(transcript.isEmpty ? YapPalette.paper55 : YapPalette.paper)
                        .lineSpacing(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("keyboardCoachTranscript")
                }
                .scrollIndicators(.hidden)
                .onChange(of: transcript) {
                    proxy.scrollTo("keyboardCoachTranscript", anchor: .bottom)
                }
            }
            .frame(height: 116)
            .padding(18)
            .yapPanel(cornerRadius: 24, depth: .sunk)

            VStack(spacing: 12) {
                BottomEdgeSwipeHint(reduceMotion: reduceMotion, animate: demonstratesSwipe)
                    .frame(height: 44)

                Text("Swipe right along the bottom edge")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.center)

                Text("go back to where you were typing — yap keeps listening for up to 3 minutes.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(YapPalette.paper55)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .yapPanel(cornerRadius: 26)

            activityStatus

            Text("if another keyboard appears, hold the globe key and choose yap again.")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(YapPalette.paper55)
                .multilineTextAlignment(.center)
        }
        .onAppear { demonstratesSwipe = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "Microphone is on. Swipe right along the bottom edge to return to your previous app."
        )
        .accessibilityIdentifier("keyboardReturnCoach")
    }

    @ViewBuilder
    private var activityStatus: some View {
        switch liveActivityResult {
        case .started:
            Label("live recording status is active", systemImage: "waveform.circle.fill")
                .foregroundStyle(YapPalette.acid)
        case .disabled:
            Label(
                "live status is unavailable, but your mic is recording.",
                systemImage: "waveform.slash"
            )
            .foregroundStyle(.orange)
        case .failed:
            Label(
                "live status couldn’t start, but your mic is recording.",
                systemImage: "exclamationmark.circle"
            )
            .foregroundStyle(.orange)
        case nil:
            EmptyView()
        }
    }
}

private struct BottomEdgeSwipeHint: View {
    let reduceMotion: Bool
    let animate: Bool

    var body: some View {
        ZStack {
            Capsule()
                .fill(YapPalette.paper.opacity(0.16))
                .frame(height: 4)
                .padding(.horizontal, 26)

            HStack(spacing: 7) {
                Image(systemName: "hand.point.up.left.fill")
                Image(systemName: "arrow.right")
                    .fontWeight(.bold)
            }
            .font(.system(size: 21, weight: .bold))
            .foregroundStyle(YapPalette.acid)
            .offset(x: reduceMotion ? 0 : (animate ? 70 : -64))
            .opacity(reduceMotion ? 1 : (animate ? 0.04 : 1))
            .animation(
                reduceMotion
                    ? nil
                    : .easeOut(duration: 1.35).repeatForever(autoreverses: false),
                value: animate
            )
        }
        .accessibilityHidden(true)
    }
}
