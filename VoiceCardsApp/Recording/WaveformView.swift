import SwiftUI

struct WaveformView: View {
    let level: Float
    var maximumHeight: CGFloat = 140

    var body: some View {
        HStack(alignment: .center, spacing: 5) {
            ForEach(0..<28, id: \.self) { index in
                let variation = 0.35 + Float((index * 17) % 10) / 14
                Capsule()
                    .fill(.tint)
                    .frame(
                        width: 5,
                        height: min(
                            maximumHeight,
                            max(8, CGFloat(level * variation) * maximumHeight)
                        )
                    )
                    .animation(.smooth(duration: 0.12), value: level)
            }
        }
        .frame(height: maximumHeight)
        .accessibilityLabel("Live recording level")
    }
}
