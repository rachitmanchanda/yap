import SwiftUI

/// Yap uses a four-point grid. Semantic aliases keep layout intent readable in screen code.
enum YapSpacing {
    static let xSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let compact: CGFloat = 12
    static let regular: CGFloat = 16
    static let medium: CGFloat = 20
    static let large: CGFloat = 24
    static let xLarge: CGFloat = 32
    static let xxLarge: CGFloat = 40

    static let appHorizontal: CGFloat = medium
    static let keyboardHorizontal: CGFloat = regular
    static let belowSafeArea: CGFloat = compact
    static let section: CGFloat = regular
}

enum YapRadius {
    static let chip: CGFloat = 12
    static let input: CGFloat = 18
    static let card: CGFloat = 24
    static let sheet: CGFloat = 30
}

enum YapControlMetric {
    static let minimumTouchTarget: CGFloat = 44
    static let compact: CGFloat = 52
    static let prominent: CGFloat = 64

    static let iconSmall: CGFloat = 16
    static let iconRegular: CGFloat = 20
    static let iconLarge: CGFloat = 24
}

/// Semantic type roles preserve Yap's rounded voice while respecting Dynamic Type.
enum YapType {
    static let display = Font.system(.largeTitle, design: .rounded, weight: .black)
    static let screenTitle = Font.system(.title, design: .rounded, weight: .black)
    static let sectionTitle = Font.system(.title3, design: .rounded, weight: .heavy)
    static let body = Font.system(.body, design: .rounded, weight: .medium)
    static let bodyStrong = Font.system(.body, design: .rounded, weight: .bold)
    static let button = Font.system(.headline, design: .rounded, weight: .heavy)
    static let prominentButton = Font.system(.title3, design: .rounded, weight: .black)
    static let label = Font.system(.subheadline, design: .rounded, weight: .bold)
    static let caption = Font.system(.caption, design: .rounded, weight: .semibold)
    static let metadata = Font.system(.caption2, design: .rounded, weight: .semibold)

    /// Stream identity is intentionally numeric and animated, so it needs a scalable size while
    /// retaining the same rounded family as every other semantic role.
    static func identityMetric(size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
}

enum YapMotion {
    /// Controls acknowledge touch immediately without an ornamental bounce.
    static let press = Animation.spring(response: 0.22, dampingFraction: 0.9)
    /// Sheets carry a little physicality because they are directly manipulated.
    static let sheet = Animation.spring(response: 0.32, dampingFraction: 0.82)
    static let selection = Animation.spring(response: 0.24, dampingFraction: 1)
}
