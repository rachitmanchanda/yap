import SwiftUI
import UIKit

/// A small, causal haptic vocabulary keeps Yap tactile without making routine navigation noisy.
///
/// Feedback is emitted by the action that commits a change (or by the state transition that
/// confirms it), rather than by every button press. Reusing prepared generators also removes the
/// tiny first-use delay that can otherwise make touch and feedback feel disconnected.
@MainActor
enum YapHaptics {
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let landingGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let contactGenerator = UIImpactFeedbackGenerator(style: .soft)
    private static let snapGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private static let notificationGenerator = UINotificationFeedbackGenerator()

    static func prepareForCapture() {
        snapGenerator.prepare()
    }

    static func prepareForLandings() {
        landingGenerator.prepare()
    }

    static func landing(intensity: CGFloat) {
        landingGenerator.impactOccurred(intensity: min(max(intensity, 0.15), 0.72))
        landingGenerator.prepare()
    }

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

    static func warning() {
        notificationGenerator.notificationOccurred(.warning)
        notificationGenerator.prepare()
    }

    static func error() {
        notificationGenerator.notificationOccurred(.error)
        notificationGenerator.prepare()
    }
}

enum YapPalette {
    static let base = Color("YapBase")
    static let paper = Color("YapPaper")
    static let clay = Color("YapClay")
    static let acid = Color("YapAcid")
    static let ink = Color("YapInk")
    static let roast = Color(red: 1, green: 0.16, blue: 0.43)
    static let hinglish = Color(red: 1, green: 0.49, blue: 0.10)
    static let paper82 = paper.opacity(0.82)
    static let paper55 = paper.opacity(0.55)
}

/// Typed access to Yap's solid Pika icon set keeps every screen on the same visual language.
/// The SVGs are exact Figma exports and render as templates so each surface controls color.
enum YapIcon: String, CaseIterable {
    case ai
    case apple
    case arrowLeft
    case arrowRight
    case bookmark
    case chat
    case check
    case chevronLeft
    case chevronRight
    case clipboard
    case close
    case copy
    case edit
    case externalLink
    case filter
    case globe
    case home
    case image
    case keyboard
    case lock
    case microphone
    case more
    case openAI
    case pause
    case pin
    case play
    case plus
    case search
    case settings
    case sparkles
    case stop
    case trash
    case user
    case warning
    case waveform

    var assetName: String {
        "YapIcon\(rawValue.prefix(1).uppercased())\(rawValue.dropFirst())"
    }
}

extension Image {
    /// Prefer this initializer over SF Symbols for branded Yap controls.
    init(yapIcon: YapIcon) {
        self.init(yapIcon.assetName)
    }
}

/// Shared spacing keeps every surface on the same 4-point rhythm.
enum YapLayout {
    static let screenTopInset = YapSpacing.belowSafeArea
    static let navigationRowHeight = YapControlMetric.compact
    /// The title begins just below the native back-button row. Keeping this positive avoids
    /// collisions while preserving a compact visual relationship between navigation and content.
    static let pushedContentTop = YapSpacing.small
    static let sectionSpacing = YapSpacing.section
    static let dockTopInset = YapSpacing.medium
    static let dockBottomInset = YapSpacing.large
}

/// Fades scrolling rows as they approach fixed controls without introducing another surface.
struct YapTopScrollEdgeOpacityMask: View {
    var fadeHeight: CGFloat = 28

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.clear, .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: fadeHeight)

            Color.black
        }
        .accessibilityHidden(true)
    }
}

enum YapAtmosphere: String {
    case welcome = "OnboardingWelcomeAtmosphere"
    case microphone = "OnboardingMicrophoneAtmosphere"
    case modes = "OnboardingModesAtmosphere"
    case keyboard = "OnboardingKeyboardAtmosphere"
}

enum YapMainAtmosphere: String {
    case stream = "YapStreamAtmosphere"
    case capture = "YapCaptureAtmosphere"
    case rewrite = "YapRewriteAtmosphere"
}

/// Figma's atmosphere is deliberately softened again at runtime so its blobs feel like colored
/// light behind frosted glass. A second, slower layer creates depth without distracting motion.
struct YapAuroraBackground: View {
    let atmosphere: YapMainAtmosphere

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            YapPalette.base

            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate

                ZStack {
                    atmosphereLayer(time: time, phase: 0)
                        .opacity(reduceTransparency ? 0.72 : 0.88)
                        .blur(radius: reduceTransparency ? 4 : 24)

                    atmosphereLayer(time: time, phase: .pi * 0.72)
                        .scaleEffect(1.14)
                        .opacity(reduceTransparency ? 0.08 : 0.25)
                        .blur(radius: reduceTransparency ? 8 : 58)
                        .blendMode(.plusLighter)

                    if !reduceTransparency {
                        YapAmbientOrbs(colors: ambientColors, time: time)
                            .opacity(0.58)
                            .blendMode(.plusLighter)
                    }
                }
                .compositingGroup()
            }

            if !reduceTransparency {
                YapGrainOverlay()
                    .opacity(0.16)
                    .blendMode(.softLight)
            }

            Color.black.opacity(0.06)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func atmosphereLayer(time: TimeInterval, phase: Double) -> some View {
        // A roughly 25–35 second orbit is visible at a glance but still reads as ambient light.
        let horizontal = sin(time * 0.22 + phase) * 42
        let vertical = cos(time * 0.17 + phase) * 54
        let breathing = 1.09 + sin(time * 0.12 + phase) * 0.028

        // The exported atmosphere has a portrait intrinsic size. GeometryReader makes it adopt the
        // presentation's actual dimensions; the overscan keeps its slow drift from exposing an edge.
        return GeometryReader { proxy in
            Image(atmosphere.rawValue)
                .resizable()
                .scaledToFill()
                .frame(
                    width: proxy.size.width + 180,
                    height: proxy.size.height + 220
                )
                .clipped()
                .scaleEffect(breathing)
                .position(
                    x: proxy.size.width / 2 + horizontal,
                    y: proxy.size.height / 2 + vertical
                )
        }
        .clipped()
    }

    private var ambientColors: [Color] {
        switch atmosphere {
        case .stream:
            [YapPalette.clay, Color(red: 0.78, green: 0.03, blue: 0.32), YapPalette.acid]
        case .capture:
            [YapPalette.clay, Color(red: 0.92, green: 0.16, blue: 0.35), Color.orange]
        case .rewrite:
            [Color(red: 0.80, green: 0.03, blue: 0.31), YapPalette.clay, YapPalette.acid]
        }
    }
}

/// Independent light fields make the baked Figma blobs drift at different speeds instead of
/// moving as one flat image. Canvas keeps the continuous animation inexpensive.
private struct YapAmbientOrbs: View {
    let colors: [Color]
    let time: TimeInterval

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let longestEdge = max(size.width, size.height)
            let definitions: [(CGPoint, CGFloat, Color)] = [
                (
                    CGPoint(
                        x: size.width * (0.18 + sin(time * 0.28) * 0.16),
                        y: size.height * (0.24 + cos(time * 0.21) * 0.10)
                    ),
                    longestEdge * 0.38,
                    colors[0]
                ),
                (
                    CGPoint(
                        x: size.width * (0.78 + cos(time * 0.23 + 1.4) * 0.17),
                        y: size.height * (0.45 + sin(time * 0.26 + 0.8) * 0.12)
                    ),
                    longestEdge * 0.34,
                    colors[1]
                ),
                (
                    CGPoint(
                        x: size.width * (0.42 + sin(time * 0.19 + 2.2) * 0.20),
                        y: size.height * (0.82 + cos(time * 0.24 + 1.1) * 0.09)
                    ),
                    longestEdge * 0.30,
                    colors[2]
                )
            ]

            for (center, diameter, color) in definitions {
                let rect = CGRect(
                    x: center.x - diameter / 2,
                    y: center.y - diameter / 2,
                    width: diameter,
                    height: diameter
                )
                context.fill(
                    Path(ellipseIn: rect),
                    with: .radialGradient(
                        Gradient(colors: [color.opacity(0.56), color.opacity(0.12), .clear]),
                        center: center,
                        startRadius: 0,
                        endRadius: diameter / 2
                    )
                )
            }
        }
        .blur(radius: 28)
        .ignoresSafeArea()
    }
}

/// A deterministic Canvas avoids bundling a bitmap texture and keeps the grain resolution-independent.
private struct YapGrainOverlay: View {
    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            var generator = YapNoiseGenerator(seed: 0x59A9_2026)
            let count = max(900, Int(size.width * size.height / 350))

            for _ in 0..<count {
                let x = generator.nextUnit() * size.width
                let y = generator.nextUnit() * size.height
                let diameter = 0.35 + generator.nextUnit() * 0.9
                let opacity = 0.08 + generator.nextUnit() * 0.24
                let rect = CGRect(x: x, y: y, width: diameter, height: diameter)
                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(.white.opacity(opacity))
                )
            }
        }
        .ignoresSafeArea()
    }
}

private struct YapNoiseGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func nextUnit() -> CGFloat {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return CGFloat(Double(state >> 11) / 9_007_199_254_740_992)
    }
}

/// The Figma backgrounds are exported vectors, so the colored atmosphere remains crisp on
/// every iPhone size instead of approximating the designer's layered blur in SwiftUI.
struct YapAtmosphereScreen<Content: View>: View {
    let atmosphere: YapAtmosphere
    var contentRespectsSafeArea = true
    @ViewBuilder let content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    var body: some View {
        Group {
            if contentRespectsSafeArea {
                content()
                    .background { atmosphericBackground }
            } else {
                ZStack {
                    atmosphericBackground
                    content()
                }
            }
        }
        .foregroundStyle(YapPalette.paper)
        .preferredColorScheme(.dark)
    }

    private var atmosphericBackground: some View {
        ZStack {
            YapPalette.base

            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate

                ZStack {
                    onboardingAtmosphereLayer(time: time, phase: 0)
                        .opacity(0.86)
                        .blur(radius: reduceTransparency ? 5 : 26)

                    onboardingAtmosphereLayer(time: time, phase: .pi)
                        .scaleEffect(1.13)
                        .opacity(reduceTransparency ? 0.06 : 0.22)
                        .blur(radius: reduceTransparency ? 8 : 62)
                        .blendMode(.plusLighter)

                    if !reduceTransparency {
                        YapAmbientOrbs(colors: onboardingAmbientColors, time: time)
                            .opacity(0.50)
                            .blendMode(.plusLighter)
                    }
                }
                .compositingGroup()
            }

            if !reduceTransparency {
                YapGrainOverlay()
                    .opacity(0.16)
                    .blendMode(.softLight)
            }

            Color.black.opacity(0.08)
        }
        .ignoresSafeArea()
    }

    private func onboardingAtmosphereLayer(time: TimeInterval, phase: Double) -> some View {
        Image(atmosphere.rawValue)
            .resizable()
            .scaledToFill()
            .scaleEffect(1.10 + sin(time * 0.12 + phase) * 0.028)
            .offset(
                x: sin(time * 0.22 + phase) * 42,
                y: cos(time * 0.17 + phase) * 54
            )
    }

    private var onboardingAmbientColors: [Color] {
        switch atmosphere {
        case .welcome:
            [YapPalette.clay, Color(red: 0.75, green: 0.03, blue: 0.30), YapPalette.acid]
        case .microphone:
            [Color.red, YapPalette.clay, Color.orange]
        case .modes:
            [Color.pink, YapPalette.clay, YapPalette.acid]
        case .keyboard:
            [YapPalette.clay, Color.purple, YapPalette.acid]
        }
    }
}

struct YapPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(YapType.prominentButton)
            .tracking(-0.44)
            .foregroundStyle(YapPalette.ink)
            .frame(maxWidth: .infinity)
            .frame(height: YapControlMetric.prominent)
            .background(YapPalette.clay, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.42), lineWidth: 1.5)
                    .mask(
                        LinearGradient(
                            colors: [.white, .clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            }
            .shadow(color: YapPalette.clay.opacity(0.55), radius: 17, y: 10)
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(YapMotion.press, value: configuration.isPressed)
    }
}

struct YapDarkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(YapType.prominentButton)
            .tracking(-0.44)
            .foregroundStyle(YapPalette.paper)
            .frame(maxWidth: .infinity)
            .frame(height: YapControlMetric.prominent)
            .background(YapPalette.base, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.42), lineWidth: 1.5)
                    .mask(
                        LinearGradient(
                            colors: [.white, .clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            }
            .shadow(color: YapPalette.clay.opacity(0.55), radius: 17, y: 10)
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(YapMotion.press, value: configuration.isPressed)
    }
}

struct YapGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(YapType.button)
            .tracking(-0.15)
            .foregroundStyle(YapPalette.paper)
            .frame(maxWidth: .infinity)
            .frame(height: YapControlMetric.compact)
            .background(.ultraThinMaterial, in: Capsule())
            .background(.white.opacity(0.06), in: Capsule())
            .overlay {
                Capsule().stroke(.white.opacity(0.5), lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

struct YapPanelModifier: ViewModifier {
    enum Depth {
        case lifted
        case sunk
    }

    let cornerRadius: CGFloat
    let depth: Depth

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(depth == .lifted ? .black.opacity(0.24) : .black.opacity(0.3))
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        .white.opacity(depth == .lifted ? 0.5 : 0.1),
                        lineWidth: 1
                    )
            }
    }
}

extension View {
    func yapPanel(cornerRadius: CGFloat = YapRadius.card, depth: YapPanelModifier.Depth = .lifted) -> some View {
        modifier(YapPanelModifier(cornerRadius: cornerRadius, depth: depth))
    }

    func yapMetadataPill() -> some View {
        padding(.horizontal, 9)
            .frame(height: 23)
            .background(.white.opacity(0.08), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.26), lineWidth: 1))
    }
}

struct YapScreenHeading: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: YapSpacing.small) {
            Text(title)
                .font(YapType.display)
                .tracking(-1.8)
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(YapPalette.acid)
                        .frame(width: 9, height: 9)
                        .offset(x: 11, y: -6)
                }
            Text(subtitle)
                .font(YapType.caption)
                .foregroundStyle(YapPalette.paper55)
        }
    }
}

struct YapSearchBox: View {
    let prompt: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: YapSpacing.compact) {
            Image(yapIcon: .search)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: YapControlMetric.iconSmall, height: YapControlMetric.iconSmall)
            TextField(prompt, text: $text)
                .font(YapType.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(yapIcon: .close)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: YapControlMetric.iconRegular, height: YapControlMetric.iconRegular)
                        .foregroundStyle(YapPalette.paper55)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .foregroundStyle(YapPalette.paper82)
        .padding(.horizontal, YapSpacing.regular)
        .frame(height: YapControlMetric.compact)
        .yapPanel(cornerRadius: YapRadius.input, depth: .sunk)
    }
}

struct YapChoiceChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(YapType.label)
                .foregroundStyle(isSelected ? YapPalette.ink : YapPalette.paper)
                .padding(.horizontal, YapSpacing.regular)
                .frame(minHeight: YapControlMetric.minimumTouchTarget)
                .background(isSelected ? YapPalette.acid : .white.opacity(0.08), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.38), lineWidth: 1))
                .shadow(color: isSelected ? YapPalette.acid.opacity(0.38) : .clear, radius: 12)
        }
        .buttonStyle(.plain)
    }
}

struct YapEmptyState: View {
    let icon: YapIcon
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: YapSpacing.compact) {
            Image(yapIcon: icon)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: YapSpacing.xLarge, height: YapSpacing.xLarge)
                .foregroundStyle(YapPalette.acid)
            Text(title)
                .font(YapType.sectionTitle)
            Text(detail)
                .font(YapType.body)
                .foregroundStyle(YapPalette.paper55)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(YapSpacing.xLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct YapStepPill: View {
    let current: Int

    var body: some View {
        Text("step \(current) of 3")
            .font(YapType.caption)
            .tracking(0.24)
            .padding(.horizontal, 13)
            .frame(height: 28)
            .background(.ultraThinMaterial, in: Capsule())
            .background(.white.opacity(0.08), in: Capsule())
            .overlay { Capsule().stroke(.white.opacity(0.5), lineWidth: 1) }
    }
}

struct YapOnboardingHeading: View {
    let text: String
    var size: CGFloat = 38

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .black, design: .rounded))
            .tracking(size == 40 ? -1.2 : -1.14)
            .lineSpacing(0)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct YapMetaText: View {
    let text: String
    var color = YapPalette.paper55

    var body: some View {
        Text(text)
            .font(YapType.caption)
            .tracking(0.24)
            .foregroundStyle(color)
    }
}

/// Canonical full-screen scaffold: atmosphere, safe-area-aware content, and shared margins.
struct YapScreen<Content: View>: View {
    let atmosphere: YapMainAtmosphere
    private let content: Content

    init(
        atmosphere: YapMainAtmosphere = .stream,
        @ViewBuilder content: () -> Content
    ) {
        self.atmosphere = atmosphere
        self.content = content()
    }

    var body: some View {
        ZStack {
            YapAuroraBackground(atmosphere: atmosphere)
            content
                .padding(.horizontal, YapSpacing.appHorizontal)
                .padding(.top, YapSpacing.belowSafeArea)
        }
        .foregroundStyle(YapPalette.paper)
        .preferredColorScheme(.dark)
    }
}

/// Pushed screens use one navigation row so titles never collide with the system safe area.
struct YapNavigationHeader<Trailing: View>: View {
    let title: String?
    let backAction: () -> Void
    private let trailing: Trailing

    init(
        title: String? = nil,
        backAction: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.backAction = backAction
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: YapSpacing.compact) {
            Button(action: backAction) {
                Image(yapIcon: .chevronLeft)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: YapControlMetric.iconRegular,
                        height: YapControlMetric.iconRegular
                    )
                    .frame(
                        width: YapControlMetric.minimumTouchTarget,
                        height: YapControlMetric.minimumTouchTarget
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            if let title {
                Text(title)
                    .font(YapType.sectionTitle)
            }

            Spacer(minLength: YapSpacing.small)
            trailing
        }
        .frame(minHeight: YapControlMetric.minimumTouchTarget)
    }
}

extension YapNavigationHeader where Trailing == EmptyView {
    init(title: String? = nil, backAction: @escaping () -> Void) {
        self.init(title: title, backAction: backAction) { EmptyView() }
    }
}

/// Fixed action chrome remains visually separate from scrolling content and owns the safe area.
struct YapBottomDock<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, YapSpacing.appHorizontal)
            .padding(.top, YapSpacing.medium)
            .padding(.bottom, YapSpacing.large)
            .frame(maxWidth: .infinity)
            .background {
                ZStack {
                    YapPalette.base.opacity(0.94)
                    LinearGradient(
                        colors: [.white.opacity(0.08), .black.opacity(0.08)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .ignoresSafeArea(edges: .bottom)
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(.white.opacity(0.22))
                    .frame(height: 1)
            }
    }
}

struct YapSheetSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(YapSpacing.medium)
            .background {
                RoundedRectangle(cornerRadius: YapRadius.sheet, style: .continuous)
                    .fill(YapPalette.base.opacity(0.9))
                    .background(
                        .regularMaterial,
                        in: RoundedRectangle(cornerRadius: YapRadius.sheet, style: .continuous)
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: YapRadius.sheet, style: .continuous))
    }
}

extension View {
    func yapSheetSurface() -> some View {
        modifier(YapSheetSurfaceModifier())
    }
}

#if DEBUG
/// A deterministic visual fixture used by designers and UI tests to catch system-wide drift.
struct YapComponentGallery: View {
    @State private var searchText = ""
    @State private var selectedChip = "clean"

    var body: some View {
        YapScreen(atmosphere: .stream) {
            ScrollView {
                VStack(alignment: .leading, spacing: YapSpacing.large) {
                    YapScreenHeading(
                        title: "ui quality",
                        subtitle: "the shared Yap components in one place"
                    )

                    gallerySection("type") {
                        Text("Say it once. Send it right.")
                            .font(YapType.display)
                        Text("Section heading")
                            .font(YapType.sectionTitle)
                        Text("Body copy stays readable at every Dynamic Type size.")
                            .font(YapType.body)
                            .foregroundStyle(YapPalette.paper82)
                    }

                    gallerySection("inputs") {
                        YapSearchBox(prompt: "what did i say about…", text: $searchText)
                        HStack(spacing: YapSpacing.small) {
                            ForEach(["clean", "casual", "boss"], id: \.self) { chip in
                                YapChoiceChip(title: chip, isSelected: selectedChip == chip) {
                                    selectedChip = chip
                                }
                            }
                        }
                    }

                    gallerySection("actions") {
                        Button("primary action") {}
                            .buttonStyle(YapPrimaryButtonStyle())
                        Button("secondary action") {}
                            .buttonStyle(YapGhostButtonStyle())
                    }

                    gallerySection("states") {
                        YapEmptyState(
                            icon: .search,
                            title: "nothing matched that",
                            detail: "try a different word."
                        )
                        .frame(height: 180)
                        .yapPanel(cornerRadius: YapRadius.card)
                    }
                }
                .padding(.bottom, YapSpacing.xLarge)
            }
            .scrollIndicators(.hidden)
        }
        .accessibilityIdentifier("yapComponentGallery")
    }

    private func gallerySection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: YapSpacing.compact) {
            Text(title)
                .font(YapType.label)
                .foregroundStyle(YapPalette.paper55)
            VStack(alignment: .leading, spacing: YapSpacing.regular) {
                content()
            }
            .padding(YapSpacing.regular)
            .frame(maxWidth: .infinity, alignment: .leading)
            .yapPanel(cornerRadius: YapRadius.card)
        }
    }
}
#endif
