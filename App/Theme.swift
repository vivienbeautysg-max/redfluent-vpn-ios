import SwiftUI
import UIKit

/// "01 Soft Landing": Paper / Ink / Red / Stone, Fraunces + Archivo + IBM Plex Mono.
/// Colours are dynamic (light / dark resolve from the trait collection), so the in-app appearance switch
/// (Appearance, applied with preferredColorScheme at the root) reaches SwiftUI and UIKit alike.
enum Theme {
    enum Palette {
        static let paper = dynamic(light: 0xF6F3EE, dark: 0x141414)
        static let ink   = dynamic(light: 0x141414, dark: 0xF6F3EE)
        static let stone = dynamic(light: 0x8A867E, dark: 0x9C988F)
        static let rule  = dynamic(light: 0x141414, dark: 0xF6F3EE, lightAlpha: 0.11, darkAlpha: 0.12)
        static let soft  = dynamic(light: 0x141414, dark: 0xF6F3EE, lightAlpha: 0.06, darkAlpha: 0.08)
        static let red   = UIColor(rgb: 0xC62A22)
        static let glow  = dynamic(light: 0xC62A22, dark: 0xD6342B, lightAlpha: 0.16, darkAlpha: 0.30)

        static func dynamic(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> UIColor {
            UIColor { traits in
                traits.userInterfaceStyle == .dark ? UIColor(rgb: dark, alpha: darkAlpha) : UIColor(rgb: light, alpha: lightAlpha)
            }
        }
    }

    enum Color {
        static let paper = SwiftUI.Color(uiColor: Palette.paper)
        static let ink   = SwiftUI.Color(uiColor: Palette.ink)
        static let stone = SwiftUI.Color(uiColor: Palette.stone)
        static let rule  = SwiftUI.Color(uiColor: Palette.rule)
        static let soft  = SwiftUI.Color(uiColor: Palette.soft)
        static let red   = SwiftUI.Color(uiColor: Palette.red)
        static let glow  = SwiftUI.Color(uiColor: Palette.glow)
        static let onRed = SwiftUI.Color.white
    }

    enum Weight { case regular, medium, semibold }

    enum Font {
        /// Fraunces display cut (titles, big figures). Fixed size: these are drawn to the layout.
        static func display(_ size: CGFloat) -> SwiftUI.Font { .custom(AppFonts.frauncesDisplay, fixedSize: size) }
        /// Fraunces small cut (wordmark, row figures).
        static func serif(_ size: CGFloat) -> SwiftUI.Font { .custom(AppFonts.frauncesText, fixedSize: size) }
        /// Archivo, the text face. Scales with Dynamic Type.
        static func text(_ size: CGFloat, _ weight: Weight = .regular) -> SwiftUI.Font {
            .custom(archivo(weight), size: size)
        }
        /// IBM Plex Mono for codes, ids and addresses.
        static func mono(_ size: CGFloat, medium: Bool = false) -> SwiftUI.Font {
            .custom(medium ? AppFonts.plexMonoMedium : AppFonts.plexMono, size: size)
        }

        static func archivo(_ weight: Weight) -> String {
            switch weight {
            case .regular:  return AppFonts.archivoRegular
            case .medium:   return AppFonts.archivoMedium
            case .semibold: return AppFonts.archivoSemiBold
            }
        }
    }

    static let gutter: CGFloat = 24
}

extension UIColor {
    convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255,
                  alpha: alpha)
    }
}

extension Appearance {
    var colorScheme: ColorScheme { self == .dark ? .dark : .light }
}

/// Runtime check that every bundled font is registered (Info.plist UIAppFonts) under the name the app asks for.
enum FontCheck {
    static func missing() -> [AppFonts.Entry] {
        AppFonts.all.filter { UIFont(name: $0.postScriptName, size: 12) == nil }
    }

    #if DEBUG
    /// `-RFVFontSelfTest`: print one line per font and exit 0 (all loaded) or 1. Run on a simulator with
    /// `xcrun simctl launch --console-pty <device> com.redfluent.vpn -RFVFontSelfTest`.
    static func runIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-RFVFontSelfTest") else { return }
        let missing = Set(missing().map(\.postScriptName))
        for entry in AppFonts.all {
            let loaded = UIFont(name: entry.postScriptName, size: 12)
            let ok = !missing.contains(entry.postScriptName) && loaded?.fontName == entry.postScriptName
            print("FONTCHECK \(ok ? "ok  " : "FAIL") \(entry.postScriptName) (\(entry.file)) -> \(loaded?.fontName ?? "nil")")
        }
        print("FONTCHECK \(AppFonts.all.count - missing.count)/\(AppFonts.all.count) fonts loaded")
        fflush(stdout)
        exit(missing.isEmpty ? 0 : 1)
    }
    #endif
}

// MARK: - Type helpers

extension View {
    /// CSS letter-spacing in em.
    func tracking(em: CGFloat, size: CGFloat) -> some View { tracking(em * size) }

    /// Small uppercase label: Archivo 600 10.5, tracked .14em, Stone.
    func rfLabelStyle(size: CGFloat = 10.5) -> some View {
        self.font(Theme.Font.text(size, .semibold))
            .tracking(0.14 * size)
            .textCase(.uppercase)
            .foregroundStyle(Theme.Color.stone)
    }

    /// Full-bleed Paper page.
    func rfPage() -> some View {
        background(Theme.Color.paper.ignoresSafeArea())
    }

    /// A sheet in the theme: solid Paper (no system glass) and the app's chosen appearance.
    func rfSheet() -> some View {
        modifier(SheetTheme())
    }
}

private struct SheetTheme: ViewModifier {
    @AppStorage(Appearance.storageKey) private var appearanceRaw = Appearance.light.rawValue

    func body(content: Content) -> some View {
        content
            .rfPage()
            .presentationBackground(Theme.Color.paper)
            .preferredColorScheme(Appearance.from(appearanceRaw).colorScheme)
            .tint(Theme.Color.red)
    }
}
