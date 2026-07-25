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
                            Image(systemName: "xmark")
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
                    .padding(.horizontal, 17)
                    .yapPanel(cornerRadius: 26)

                    infoPanel(
                        title: "why full access?",
                        symbol: "lock.shield.fill",
                        text: "It lets the keyboard read Yap’s private shared memory. Yap never records from the keyboard, monitors typing, or sends what you type."
                    )

                    infoPanel(
                        title: "speaking while typing",
                        symbol: "waveform",
                        text: "Tap the speak half of the keyboard. Yap opens with the microphone already on; swipe back and keep talking."
                    )

                    Button("open iOS settings") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    }
                    .buttonStyle(YapPrimaryButtonStyle())
                }
                .padding(.horizontal, 20)
                .safeAreaPadding(.top, YapLayout.screenTopInset)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(YapPalette.paper)
        .preferredColorScheme(.dark)
    }

    private func setupStep(_ number: Int, _ text: String, isLast: Bool = false) -> some View {
        HStack(spacing: 13) {
            Text("\(number)")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(YapPalette.ink)
                .frame(width: 30, height: 30)
                .background(YapPalette.acid, in: Circle())
            Text(text)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            Spacer()
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
            }
        }
    }

    private func infoPanel(title: String, symbol: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(YapPalette.acid)
            Text(text)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(YapPalette.paper82)
                .lineSpacing(4)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .yapPanel(cornerRadius: 24)
    }
}
