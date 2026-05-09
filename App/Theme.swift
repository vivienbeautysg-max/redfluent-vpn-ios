import SwiftUI

enum Theme {
    enum Color {
        static let brandPrimary    = SwiftUI.Color(red: 0.83, green: 0.18, blue: 0.18)
        static let brandSecondary  = SwiftUI.Color(red: 0.62, green: 0.10, blue: 0.10)
        static let brandTertiary   = SwiftUI.Color(red: 0.95, green: 0.40, blue: 0.40)
        static let surfaceCard     = SwiftUI.Color(.secondarySystemBackground)
        static let surfaceElevated = SwiftUI.Color(.tertiarySystemBackground)
        static let textPrimary     = SwiftUI.Color(.label)
        static let textSecondary   = SwiftUI.Color(.secondaryLabel)
        static let textOnBrand     = SwiftUI.Color.white
        static let success         = SwiftUI.Color(red: 0.20, green: 0.65, blue: 0.30)
        static let warning         = SwiftUI.Color(red: 0.95, green: 0.55, blue: 0.10)
        static let danger          = SwiftUI.Color(red: 0.85, green: 0.15, blue: 0.15)
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 14
        static let lg: CGFloat = 20
        static let xl: CGFloat = 28
        static let pill: CGFloat = 999
    }

    enum Font {
        static let displayLarge   = SwiftUI.Font.system(size: 36, weight: .bold,    design: .rounded)
        static let displayMedium  = SwiftUI.Font.system(size: 28, weight: .semibold,design: .rounded)
        static let titleLarge     = SwiftUI.Font.system(size: 22, weight: .semibold,design: .rounded)
        static let bodyLarge      = SwiftUI.Font.system(size: 17, weight: .regular)
        static let body           = SwiftUI.Font.system(size: 15, weight: .regular)
        static let caption        = SwiftUI.Font.system(size: 13, weight: .medium)
        static let micro          = SwiftUI.Font.system(size: 11, weight: .medium)
        static let monoBody       = SwiftUI.Font.system(size: 14, weight: .regular, design: .monospaced)
    }
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Color.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }
}
