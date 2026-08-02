@preconcurrency import AVFoundation
import SwiftUI
import UIKit

enum YapOnboardingStep: Int, Equatable {
    case welcome
    case microphone
    case modes
    case keyboard
}

struct YapOnboardingFlowView: View {
    @Bindable var authModel: AuthModel
    let initiallyAuthenticated: Bool
    let completion: () -> Void

    @State private var step: YapOnboardingStep
    @State private var microphoneDenied = false

    init(
        authModel: AuthModel,
        initiallyAuthenticated: Bool,
        completion: @escaping () -> Void
    ) {
        self.authModel = authModel
        self.initiallyAuthenticated = initiallyAuthenticated
        self.completion = completion
        _step = State(initialValue: Self.initialStep(initiallyAuthenticated: initiallyAuthenticated))
    }

    var body: some View {
        ZStack {
            switch step {
            case .welcome:
                YapWelcomeScreen(
                    isSigningIn: authModel.state == .signingIn,
                    signIn: { Task { await authModel.signIn(with: .apple) } },
                    bypass: {
                        #if DEBUG
                        authModel.bypassSignIn()
                        #endif
                    }
                )
            case .microphone:
                YapMicrophoneScreen(
                    permissionDenied: microphoneDenied,
                    requestPermission: requestMicrophonePermission,
                    skip: { advance(to: .modes) }
                )
            case .modes:
                YapModePreviewScreen {
                    advance(to: .keyboard)
                }
            case .keyboard:
                YapKeyboardSetupScreen(
                    openSettings: openSettings,
                    continueFlow: finish
                )
            }
        }
        .id(step)
        .transition(
            .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        )
        .animation(.spring(response: 0.48, dampingFraction: 0.86), value: step)
        .onChange(of: authModel.state) { _, state in
            if case .signedIn = state, step == .welcome {
                if AppPreferences.hasCompletedOnboarding {
                    completion()
                } else {
                    advance(to: .microphone)
                }
            }
        }
    }

    private func requestMicrophonePermission() {
        Task {
            let granted = await AVAudioApplication.requestRecordPermission()
            await MainActor.run {
                if granted {
                    advance(to: .modes)
                } else {
                    microphoneDenied = true
                }
            }
        }
    }

    private func advance(to nextStep: YapOnboardingStep) {
        YapHaptics.selection()
        withAnimation {
            step = nextStep
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func finish() {
        AppPreferences.hasCompletedOnboarding = true
        completion()
    }

    private static func initialStep(initiallyAuthenticated: Bool) -> YapOnboardingStep {
        #if DEBUG
        let prefix = "-onboardingStep="
        if let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }) {
            switch argument.dropFirst(prefix.count) {
            case "welcome": return .welcome
            case "microphone": return .microphone
            case "modes": return .modes
            case "keyboard": return .keyboard
            default: break
            }
        }
        #endif
        return initiallyAuthenticated ? .microphone : .welcome
    }
}

private struct YapWelcomeScreen: View {
    let isSigningIn: Bool
    let signIn: () -> Void
    let bypass: () -> Void
    @State private var bypassTapCount = 0

    var body: some View {
        YapAtmosphereScreen(atmosphere: .welcome, contentRespectsSafeArea: false) {
            GeometryReader { proxy in
                VStack(alignment: .leading, spacing: 0) {
                    YapWelcomeMemoryRain()
                        .frame(height: min(458, proxy.size.height * 0.54))
                        // The pile still clips horizontally, but dissolves into the pitch instead
                        // of ending at a sharp exported-frame boundary.
                        .mask {
                            LinearGradient(
                                stops: [
                                    .init(color: .black, location: 0),
                                    .init(color: .black, location: 0.80),
                                    .init(color: .black.opacity(0.82), location: 0.88),
                                    .init(color: .black.opacity(0.28), location: 0.96),
                                    .init(color: .clear, location: 1)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(YapPalette.base.opacity(0.32))
                                .frame(height: 42)
                                .blur(radius: 22)
                                .allowsHitTesting(false)
                        }

                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 16) {
                            Image("YapMark")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 64, height: 46)
                                .foregroundStyle(YapPalette.paper)
                                .accessibilityLabel("Yap")
                                .accessibilityIdentifier("Yap logo")
                                .onTapGesture {
                                    #if DEBUG
                                    bypassTapCount += 1
                                    if bypassTapCount >= 10 {
                                        bypassTapCount = 0
                                        bypass()
                                    }
                                    #endif
                                }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("yappers yap. not type.")
                                    .font(.system(size: 38, weight: .black, design: .rounded))
                                    .tracking(-1.14)
                                    .lineSpacing(0)

                                Text("yap, roast, inform 5x faster.")
                                    .font(.system(size: 29, weight: .black, design: .rounded))
                                    .tracking(-0.87)
                                    .foregroundStyle(YapPalette.paper55)
                                    .lineSpacing(0)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 18)

                        VStack(spacing: 10) {
                            Button(action: signIn) {
                                Group {
                                    if isSigningIn {
                                        ProgressView()
                                            .tint(YapPalette.paper)
                                    } else {
                                        Text("continue with apple")
                                    }
                                }
                            }
                            .buttonStyle(YapDarkButtonStyle())
                            .disabled(isSigningIn)
                            .accessibilityIdentifier("onboardingSignInWithApple")

                            YapMetaText(
                                text: "by continuing you agree to the terms and privacy policy.",
                                color: YapPalette.paper55
                            )
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                    // Match the homepage dock: preserve the real home-indicator inset, then add
                    // Yap's shared comfort spacing so the legal copy never hugs the screen edge.
                    .safeAreaPadding(.bottom, YapLayout.dockBottomInset)
                    .frame(maxHeight: .infinity)
                }
            }
        }
    }
}

/// The cards keep the exact Figma pile at rest, then fall on staggered loops to make Yap's
/// remembered thoughts feel alive. Reduce Motion freezes the pile instead of removing context.
private struct YapWelcomeMemoryRain: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt = Date()

    private let messages = YapWelcomeMessage.samples

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            GeometryReader { proxy in
                let elapsed = reduceMotion ? 10 : timeline.date.timeIntervalSince(startedAt)
                let horizontalScale = proxy.size.width / 393
                let verticalScale = proxy.size.height / 458
                let cardScale = min(horizontalScale, 1.08)

                ZStack(alignment: .topLeading) {
                    ForEach(messages) { message in
                        let progress = message.settlingProgress(after: elapsed)
                        let startY = -115 - CGFloat(message.id % 3) * 34
                        let targetY = message.initialY + 35
                        let settledFloat = progress >= 0.995
                            ? sin(elapsed * 0.48 + message.phase * 8) * 3
                            : 0
                        let y = (startY + (targetY - startY) * progress + settledFloat) * verticalScale
                        let x = (message.leading + message.width / 2) * horizontalScale
                            + sin(elapsed * 0.42 + message.phase * 9) * (progress >= 0.995 ? 4 : 1.5)

                        YapWelcomeMessageCard(message: message)
                            .frame(width: message.width)
                            .scaleEffect(cardScale)
                            .rotationEffect(.degrees(
                                message.rotation
                                    + (1 - progress) * message.entryRotation
                                    + sin(elapsed * 0.35 + message.phase * 7) * (progress >= 0.995 ? 0.7 : 0)
                            ))
                            .position(x: x, y: y)
                            .opacity(message.opacity * min(1, max(0, progress * 2)))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: startedAt) {
            guard !reduceMotion else { return }
            YapHaptics.prepareForLandings()

            // The visual fall is staggered by 60 ms. Mirroring that cadence with light impacts
            // makes the pile feel as though it is collecting on the glass, not merely animating.
            var previousLandingTime: TimeInterval = 0
            for message in messages {
                let landingTime = message.delay + 0.24
                let wait = max(0, landingTime - previousLandingTime)
                try? await Task.sleep(for: .seconds(wait))
                guard !Task.isCancelled else { return }
                YapHaptics.landing(intensity: message.landingIntensity)
                previousLandingTime = landingTime
            }
        }
    }
}

private struct YapWelcomeMessageCard: View {
    let message: YapWelcomeMessage

    var body: some View {
        VStack(alignment: .leading, spacing: message.isAccent ? 2 : 3) {
            if message.isAccent {
                Text(message.metadata)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .tracking(0.24)
                Text(message.title)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .tracking(-0.15)
                    .lineLimit(2)
            } else {
                HStack(spacing: 8) {
                    Text(message.title)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .tracking(-0.15)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    if let dotColor = message.dotColor {
                        Circle()
                            .fill(dotColor)
                            .frame(width: 8, height: 8)
                    }
                }
                Text(message.metadata)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .tracking(0.24)
                    .foregroundStyle(YapPalette.paper55)
            }
        }
        .foregroundStyle(message.isAccent ? YapPalette.ink : YapPalette.paper)
        .padding(.horizontal, message.isAccent ? 18 : 14)
        .padding(.vertical, message.isAccent ? 12 : 11)
        .background {
            if message.isAccent {
                Capsule()
                    .fill(YapPalette.acid)
                    .shadow(color: YapPalette.acid.opacity(0.4), radius: 15, y: 8)
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.black.opacity(0.24))
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 8)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(.white.opacity(0.5), lineWidth: 1)
                    }
            }
        }
    }
}

private struct YapWelcomeMessage: Identifiable {
    let id: Int
    let title: String
    let metadata: String
    let width: CGFloat
    let leading: CGFloat
    let initialY: CGFloat
    let rotation: Double
    let opacity: Double
    let delay: Double
    let dotColor: Color?
    var isAccent = false

    var phase: Double {
        Double((initialY + 76) / 550)
    }

    var entryRotation: Double {
        id.isMultiple(of: 2) ? -10 : 10
    }

    var landingIntensity: CGFloat {
        isAccent ? 0.68 : 0.22 + CGFloat(opacity) * 0.28
    }

    func settlingProgress(after elapsed: TimeInterval) -> CGFloat {
        let normalized = min(1, max(0, (elapsed - delay) / 1.15))
        guard normalized < 1 else { return 1 }
        // A damped fall gives each card a small, physical landing without an endless loop.
        let spring = 1 - exp(-6.4 * normalized) * cos(9.5 * normalized)
        return CGFloat(min(1.06, spring))
    }

    static let samples = [
        YapWelcomeMessage(id: 0, title: "ritika's upi id", metadata: "2d · shared", width: 178, leading: -42, initialY: 40, rotation: 8, opacity: 1, delay: 0.00, dotColor: YapPalette.clay),
        YapWelcomeMessage(id: 1, title: "rent delay message", metadata: "4h · voice", width: 196, leading: 178, initialY: 2, rotation: -7, opacity: 1, delay: 0.06, dotColor: YapPalette.acid),
        YapWelcomeMessage(id: 2, title: "kal mat aana", metadata: "yesterday", width: 158, leading: 44, initialY: 105, rotation: -4, opacity: 1, delay: 0.12, dotColor: .orange),
        YapWelcomeMessage(id: 3, title: "karan's haircut, roasted", metadata: "2d · voice", width: 208, leading: 146, initialY: 150, rotation: 6, opacity: 0.95, delay: 0.18, dotColor: .pink),
        YapWelcomeMessage(id: 4, title: "wifi at amma's place", metadata: "3d · shared", width: 180, leading: -48, initialY: 168, rotation: -9, opacity: 0.90, delay: 0.24, dotColor: nil),
        YapWelcomeMessage(id: 5, title: "leave request for monday", metadata: "4h · voice", width: 204, leading: 118, initialY: 239, rotation: -3, opacity: 0.85, delay: 0.30, dotColor: YapPalette.acid),
        YapWelcomeMessage(id: 6, title: "goa split screenshot", metadata: "5d · shared", width: 172, leading: 1, initialY: 306, rotation: 5, opacity: 0.72, delay: 0.36, dotColor: nil),
        YapWelcomeMessage(id: 7, title: "landlord follow-up", metadata: "1w · voice", width: 188, leading: 196, initialY: 310, rotation: -8, opacity: 0.60, delay: 0.42, dotColor: YapPalette.clay),
        YapWelcomeMessage(id: 8, title: "naina's address", metadata: "2w · shared", width: 160, leading: 205, initialY: 430, rotation: 7, opacity: 0.42, delay: 0.48, dotColor: nil),
        YapWelcomeMessage(id: 9, title: "sharma ji, the rent will be a week late.", metadata: "boss mode", width: 292, leading: 45, initialY: 358, rotation: 4, opacity: 1, delay: 0.56, dotColor: nil, isAccent: true)
    ]
}

private struct YapMicrophoneScreen: View {
    let permissionDenied: Bool
    let requestPermission: () -> Void
    let skip: () -> Void

    private let promises = [
        "idle audio is discarded on-device and never sent.",
        "the orange iOS microphone indicator stays visible while Flow is on.",
        "turn Flow off anytime by opening Yap from its Live Activity."
    ]

    var body: some View {
        YapAtmosphereScreen(atmosphere: .microphone) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 16) {
                    YapStepPill(current: 1)
                    YapOnboardingHeading(text: "let yap\nhear you", size: 40)
                    Text(
                        "the keyboard never accesses your mic. start Flow once in Yap, then its armed audio session can listen on demand for up to four hours."
                    )
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(YapPalette.paper82)
                    .lineSpacing(1)
                }
                .padding(.horizontal, 2)

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(promises, id: \.self) { promise in
                        HStack(alignment: .top, spacing: 11) {
                            Image("OnboardingAcidDot")
                                .resizable()
                                .frame(width: 8, height: 8)
                                .padding(.top, 6)
                            Text(promise)
                                .font(.system(size: 15, weight: .regular, design: .rounded))
                                .foregroundStyle(YapPalette.paper82)
                                .lineSpacing(1)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 18)
                .yapPanel()
                .padding(.top, 24)

                Spacer(minLength: 24)

                VStack(spacing: 10) {
                    Button(
                        permissionDenied ? "open microphone settings" : "allow microphone",
                        action: permissionDenied ? openSettings : requestPermission
                    )
                    .buttonStyle(YapPrimaryButtonStyle())

                    Button("not now", action: skip)
                        .buttonStyle(YapGhostButtonStyle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 2)
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private enum YapPreviewMode: String, CaseIterable, Identifiable {
    case boss
    case casual
    case roast
    case rizz
    case hindi

    var id: String { rawValue }

    var storedModeID: String {
        switch self {
        case .boss: "formal"
        case .casual: "casual"
        case .roast: "roast"
        case .rizz: "rizz"
        case .hindi: "hindi-household"
        }
    }

    var output: String {
        switch self {
        case .boss:
            "hello sir, i wanted to let you know in advance that this month's rent will be delayed by about a week.\n\ni'll transfer it by the 8th."
        case .casual:
            "hey, just a heads-up — rent will be about a week late this month. i'll send it by the 8th, sorry!"
        case .roast:
            "my bank account has chosen suspense this month. rent is arriving fashionably late — by the 8th."
        case .rizz:
            "tiny plot twist: rent will be a week late this month, but i'll make it right by the 8th."
        case .hindi:
            "sir, is mahine rent ek hafte late ho jayega. main 8 tareekh tak transfer kar dunga, sorry."
        }
    }
}

private struct YapModePreviewScreen: View {
    let continueFlow: () -> Void
    @State private var selectedMode = YapPreviewMode.boss

    var body: some View {
        YapAtmosphereScreen(atmosphere: .modes) {
            VStack(alignment: .leading, spacing: 0) {
                YapOnboardingHeading(text: "nice. now pick\na voice for it.")
                    .padding(.horizontal, 2)

                VStack(alignment: .leading, spacing: 8) {
                    YapMetaText(text: "you said")
                    Text(
                        "yo tell the landlord i'm gonna be late with the rent this month, like a week late, sorry"
                    )
                    .font(.system(size: 17, weight: .regular, design: .rounded))
                    .foregroundStyle(YapPalette.paper82)
                    .lineSpacing(2)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 16)
                .yapPanel(cornerRadius: 26, depth: .sunk)
                .padding(.top, 20)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(YapPreviewMode.allCases) { mode in
                            YapModePreviewChip(
                                title: mode.rawValue,
                                isSelected: selectedMode == mode
                            ) {
                                selectedMode = mode
                            }
                        }
                    }
                    .padding(.vertical, 1)
                }
                .contentMargins(.horizontal, 0, for: .scrollContent)
                .padding(.top, 16)

                VStack(alignment: .leading, spacing: 12) {
                    YapMetaText(
                        text: "\(selectedMode.rawValue) mode",
                        color: YapPalette.acid
                    )
                    Text(selectedMode.output)
                        .font(.system(size: 22, weight: .medium, design: .rounded))
                        .tracking(-0.22)
                        .lineSpacing(2)
                        .id(selectedMode)
                        .transition(.opacity.combined(with: .blurReplace))
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .yapPanel(cornerRadius: 28)
                .shadow(color: .black.opacity(0.35), radius: 17, y: 14)
                .padding(.top, 16)

                Spacer(minLength: 18)

                VStack(spacing: 12) {
                    YapMetaText(text: "tap any mode to hear it again")
                    Button("keep going") {
                        AppPreferences.defaultModeID = selectedMode.storedModeID
                        continueFlow()
                    }
                    .buttonStyle(YapPrimaryButtonStyle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 2)
            .sensoryFeedback(.selection, trigger: selectedMode)
            .animation(.easeOut(duration: 0.2), value: selectedMode)
        }
    }
}

private struct YapModePreviewChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .tracking(-0.15)
                .foregroundStyle(isSelected ? YapPalette.ink : YapPalette.paper)
                .padding(.horizontal, 17)
                .frame(height: 40)
                .background(
                    isSelected ? YapPalette.acid : .white.opacity(0.1),
                    in: Capsule()
                )
                .overlay {
                    if !isSelected {
                        Capsule().stroke(.white.opacity(0.5), lineWidth: 1)
                    }
                }
                .shadow(
                    color: isSelected ? YapPalette.acid.opacity(0.55) : .clear,
                    radius: 13
                )
        }
        .buttonStyle(.plain)
    }
}

private struct YapKeyboardSetupScreen: View {
    let openSettings: () -> Void
    let continueFlow: () -> Void

    private let instructions = [
        "settings → general → keyboard",
        "tap keyboards, then add new keyboard",
        "choose yap from the list",
        "tap yap again and turn on full access"
    ]

    var body: some View {
        YapAtmosphereScreen(atmosphere: .keyboard) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    YapStepPill(current: 2)
                    YapOnboardingHeading(text: "put yap on\nyour keyboard")
                    Text(
                        "this is the annoying part and we can't do it for you. four taps in settings, once."
                    )
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(YapPalette.paper82)
                    .lineSpacing(1)
                }
                .padding(.horizontal, 2)

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(instructions.enumerated()), id: \.offset) { index, instruction in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(YapPalette.ink)
                                .frame(width: 24, height: 24)
                                .background(YapPalette.acid, in: Circle())
                            Text(instruction)
                                .font(.system(size: 15, weight: .regular, design: .rounded))
                                .padding(.top, 2)
                        }
                    }
                }
                .padding(18)
                .yapPanel()
                .padding(.top, 22)

                VStack(alignment: .leading, spacing: 8) {
                    YapMetaText(text: "about full access")
                    Text(
                        "full access is how the keyboard reads the cards you saved. it is not how we read what you type — yap has no keys, so there is nothing to log."
                    )
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(YapPalette.paper82)
                    .lineSpacing(1)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 16)
                .yapPanel(cornerRadius: 22, depth: .sunk)
                .padding(.top, 16)

                Spacer(minLength: 16)

                VStack(spacing: 10) {
                    Button("open settings") {
                        openSettings()
                        continueFlow()
                    }
                    .buttonStyle(YapPrimaryButtonStyle())

                    Button("i'll do it later", action: continueFlow)
                        .buttonStyle(YapGhostButtonStyle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 2)
        }
    }
}
