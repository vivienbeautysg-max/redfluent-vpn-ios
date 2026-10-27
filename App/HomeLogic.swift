import Foundation

// Home screen ("01 Soft Landing"): appearance setting, the IPv4-only Wi-Fi hint and number formatting.
// Plain Foundation so Tests/SelfTest can run it.

/// Light / dark, chosen in the app and remembered. Never follows the system: light unless the user picked dark.
enum Appearance: String, CaseIterable, Identifiable {
    case light, dark

    static let storageKey = "rfv.appearance"

    var id: String { rawValue }
    var title: String { self == .light ? "Light" : "Dark" }

    /// What is stored (or nothing yet) -> the appearance to use; anything unknown is light.
    static func from(_ stored: String?) -> Appearance {
        stored.flatMap(Appearance.init(rawValue:)) ?? .light
    }
}

/// Tokyo's IPv4 address is blocked in China; only its IPv6 entry gets through. On a Wi-Fi without IPv6 a Tokyo
/// device therefore cannot connect, and the home screen says so in one line.
enum IPv6Hint {
    static let text = "Wi-Fi has no IPv6 \u{2014} switch to cellular"
    static let regionID = "tokyo"

    /// `onWiFi`: the Wi-Fi path is up. `wifiHasIPv6`: that path can route IPv6. `regionID`: the region in use.
    static func shows(onWiFi: Bool, wifiHasIPv6: Bool, regionID: String?) -> Bool {
        guard onWiFi, !wifiHasIPv6, let regionID else { return false }
        return RegionPolicy.matches(regionID, Self.regionID)
    }
}

enum HomeFormat {
    static let none = "\u{2014}"

    /// Bytes per second -> "18.4" (MB/s, 1 MB = 10^6 bytes); "—" when unknown.
    static func megabytesPerSecond(_ bytesPerSecond: Int64?) -> String {
        guard let bytesPerSecond, bytesPerSecond >= 0 else { return none }
        let value = Double(bytesPerSecond) / 1_000_000
        return value < 100 ? String(format: "%.1f", value) : String(format: "%.0f", value)
    }

    /// "38"; "—" when there is no measurement.
    static func ping(_ ms: Int?) -> String {
        guard let ms, ms >= 0 else { return none }
        return "\(ms)"
    }

    /// Connected time "01:24:37" (hours keep counting past 99).
    static func clock(_ seconds: TimeInterval) -> String {
        let s = seconds.isFinite ? max(0, Int(seconds)) : 0
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    /// Used GB: "12.4" (one decimal; "1024" from 1000 GB on); "—" when unknown or not a number.
    static func gigabytes(_ value: Double?) -> String {
        guard let value, value.isFinite else { return none }
        let v = max(value, 0)
        return v < 1000 ? String(format: "%.1f", v) : String(format: "%.0f", v)
    }

    /// A quota: "100", or "12.5" when it is not whole.
    static func quota(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }

    /// Bytes -> "1.8 GB" (binary GB, as the bandwidth card always counted them).
    static func bytesAsGB(_ bytes: Int64) -> String {
        "\(gigabytes(Double(max(bytes, 0)) / 1_073_741_824)) GB"
    }

    /// Bar position 0...1 of used against the monthly quota; nil without a usable quota.
    static func fraction(used: Double, quota: Double) -> Double? {
        guard quota.isFinite, quota > 0, used.isFinite else { return nil }
        return min(max(used / quota, 0), 1)
    }
}
