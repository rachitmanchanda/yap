@preconcurrency import AVFoundation
import SwiftUI
import UIKit

enum YapOnboardingStep: Int, Equatable {
    case welcome
    case microphone
    case modes
    case keyboard
    case actionButton
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
                    continueFlow: { advance(to: .actionButton) }
                )
            case .actionButton:
                YapActionButtonSetupScreen(
                    setUp: finishAndOpenShortcuts,
                    skip: finish
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
        withAnimation {
            step = nextStep
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func finishAndOpenShortcuts() {
        finish()
        guard let url = URL(string: "shortcuts://") else { return }
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
            case "action": return .actionButton
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
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 120)

                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("yap")
                            .foregroundStyle(YapPalette.paper)
                        Text(".")
                            .foregroundStyle(YapPalette.acid)
                    }
                    .font(.system(size: 96, weight: .black, design: .rounded))
                    .tracking(-2.88)
                    .accessibilityElement(children: .combine)
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

                    Text("say it once.\npaste it anywhere.")
                        .font(.system(size: 27, weight: .medium, design: .rounded))
                        .tracking(-0.27)
                        .lineSpacing(0)

                    Text("your clipboard, but it has ears.")
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundStyle(YapPalette.paper82)
                }
                .padding(.horizontal, 2)

                Spacer(minLength: 90)

                VStack(spacing: 14) {
                    Button(action: signIn) {
                        Group {
                            if isSigningIn {
                                ProgressView()
                                    .tint(YapPalette.paper)
                            } else {
                                Text("sign in with apple")
                            }
                        }
                    }
                    .buttonStyle(YapDarkButtonStyle())
                    .disabled(isSigningIn)
                    .accessibilityIdentifier("onboardingSignInWithApple")

                    YapMetaText(
                        text: "no account. no signup. just talk.",
                        color: YapPalette.paper82
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 34)
        }
    }
}

private struct YapMicrophoneScreen: View {
    let permissionDenied: Bool
    let requestPermission: () -> Void
    let skip: () -> Void

    private let promises = [
        "audio is transcribed, then thrown away.",
        "nothing leaves your phone until you save a card.",
        "no recording indicator surprises — the whole screen turns black when we are listening."
    ]

    var body: some View {
        YapAtmosphereScreen(atmosphere: .microphone) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 16) {
                    YapStepPill(current: 1)
                    YapOnboardingHeading(text: "let yap\nhear you", size: 40)
                    Text(
                        "capture only happens in the app, so the mic opens when you press the button — never in the background, never on the keyboard."
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

private struct YapActionButtonSetupScreen: View {
    let setUp: () -> Void
    let skip: () -> Void

    var body: some View {
        YapAtmosphereScreen(atmosphere: .action) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    YapStepPill(current: 3)
                    YapOnboardingHeading(text: "one press.\nalready recording.")
                    Text(
                        "the whole loop only wins if it is nearly free. so the button skips the app icon, the tap, and the wait for the mic."
                    )
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(YapPalette.paper82)
                    .lineSpacing(1)
                }
                .padding(.horizontal, 2)

                HStack(spacing: 16) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.black.opacity(0.3))
                        .frame(width: 30, height: 66)
                        .overlay {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(YapPalette.clay)
                                .frame(width: 7, height: 44)
                                .shadow(color: YapPalette.clay.opacity(0.7), radius: 16, x: -2)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(.white.opacity(0.12), lineWidth: 1)
                        }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("action button → yap")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                        YapMetaText(
                            text: "opens straight into a recording. the only control on screen is stop."
                        )
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .yapPanel()
                .padding(.top, 24)

                VStack(alignment: .leading, spacing: 8) {
                    YapMetaText(text: "no action button?")
                    Text(
                        "add yap to control centre, the lock screen, or back tap. any of them beats opening the app."
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

                Spacer(minLength: 18)

                VStack(spacing: 10) {
                    Button("set up action button", action: setUp)
                        .buttonStyle(YapPrimaryButtonStyle())
                    Button("skip for now", action: skip)
                        .buttonStyle(YapGhostButtonStyle())
                    YapMetaText(text: "that's everything. go yap.")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 2)
        }
    }
}
