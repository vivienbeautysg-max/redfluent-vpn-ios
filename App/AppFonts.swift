import Foundation

/// The fonts in App/Fonts (built by scripts/build-fonts.py, all SIL OFL 1.1) and listed under UIAppFonts in
/// Supporting/RedFluentVPN-Info.plist. Plain Foundation so Tests/SelfTest can check that every file is in the
/// plist and really carries the PostScript name the app asks for.
enum AppFonts {
    /// Fraunces at the design's display settings (opsz 48, SOFT 30, WONK 1, weight 400): titles and big figures.
    static let frauncesDisplay = "FrauncesRF-Display"
    /// Fraunces at opsz 21 (SOFT 30, WONK 1, weight 400): wordmark and small serif figures.
    static let frauncesText = "FrauncesRF-Text"
    static let archivoRegular = "ArchivoRF-Regular"
    static let archivoMedium = "ArchivoRF-Medium"
    static let archivoSemiBold = "ArchivoRF-SemiBold"
    static let plexMono = "IBMPlexMono-Regular"
    static let plexMonoMedium = "IBMPlexMono-Medium"

    struct Entry: Equatable {
        let file: String
        let postScriptName: String
    }

    static let all: [Entry] = [
        Entry(file: "FrauncesRF-Display.ttf", postScriptName: frauncesDisplay),
        Entry(file: "FrauncesRF-Text.ttf", postScriptName: frauncesText),
        Entry(file: "ArchivoRF-Regular.ttf", postScriptName: archivoRegular),
        Entry(file: "ArchivoRF-Medium.ttf", postScriptName: archivoMedium),
        Entry(file: "ArchivoRF-SemiBold.ttf", postScriptName: archivoSemiBold),
        Entry(file: "IBMPlexMono-Regular.ttf", postScriptName: plexMono),
        Entry(file: "IBMPlexMono-Medium.ttf", postScriptName: plexMonoMedium),
    ]
}
