import SwiftUI

struct KeyboardSetupView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            YapAuroraBackground(atmosphere: .stream)

            ScrollView {
                VStack(alignment: .leading, spacing: YapLayout.sectionSpacing) {
                    HStack(alignment: .top) {
                        YapScreenHeading(title: "keyboard", subtitle: "yap anywhere you type")
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(yapIcon: .close)
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 18, height: 18)
                                .frame(width: 44, height: 44)
                                .background(.ultraThinMaterial, in: Circle())
                                .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1))
                        }
                    }

                    VStack(spacing: 0) {
                        setupStep(1, "open Settings → General → Keyboard")
                        setupStep(2, "choose Keyboards → Add New Keyboard")
                        setupStep(3, "select Yap")
                        setupStep(4, "turn on Allow Full Access", isLast: true)
                    }
                    .padding(.horizontal, YapSpacing.regular)
                    .yapPanel(cornerRadius: YapRadius.card)

                    infoPanel(
                        title: "why full access?",
                        icon: .lock,
                        text: "It lets the keyboard read Yap’s private shared memory. Yap never records from the keyboard, monitors typing, or sends what you type."
                    )

                    infoPanel(
                        title: "speaking while typing",
                        icon: .waveform,
                        text: "Tap the speak half of the keyboard. Yap opens with the microphone already on; swipe back and keep talking."
                    )

                    Button("open iOS settings") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    }
                    .buttonStyle(YapPrimaryButtonStyle())
                }
                .padding(.horizontal, YapSpacing.appHorizontal)
                .safeAreaPadding(.top, YapLayout.screenTopInset)
                .padding(.bottom, YapSpacing.medium)
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(YapPalette.paper)
        .preferredColorScheme(.dark)
    }

    private func setupStep(_ number: Int, _ text: String, isLast: Bool = false) -> some View {
        HStack(spacing: YapSpacing.compact) {
            Text("\(number)")
                .font(YapType.label)
                .foregroundStyle(YapPalette.ink)
                .frame(width: 30, height: 30)
                .background(YapPalette.acid, in: Circle())
            Text(text)
                .font(YapType.label)
            Spacer()
        }
        .padding(.vertical, YapSpacing.compact)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
            }
        }
    }

    private func infoPanel(title: String, icon: YapIcon, text: String) -> some View {
        VStack(alignment: .leading, spacing: YapSpacing.compact) {
            HStack(spacing: YapSpacing.small) {
                Image(yapIcon: icon)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 19, height: 19)
                Text(title)
            }
            .font(YapType.sectionTitle)
            .foregroundStyle(YapPalette.acid)
            Text(text)
                .font(YapType.body)
                .foregroundStyle(YapPalette.paper82)
                .lineSpacing(4)
        }
        .padding(YapSpacing.regular)
        .frame(maxWidth: .infinity, alignment: .leading)
        .yapPanel(cornerRadius: YapRadius.card)
    }
}
