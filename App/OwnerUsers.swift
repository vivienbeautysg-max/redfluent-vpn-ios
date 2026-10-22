import Foundation

// Owner Admin "Usage" as a list of users: last use, logging devices / users out, and the signed-out landing.
// Plain Foundation so Tests/SelfTest can run it.

/// `lastUsedAt` of one device from GET /owner/devices. An entry exists only when the backend sent the field
/// (null = never used); no entry at all means the backend does not report last use.
struct DeviceLastUsed: Equatable {
    let iso: String?

    var date: Date? { iso.flatMap { ISODate.parse($0) } }
}

enum RelativeTime {
    /// "just now" | "5m ago" | "2h ago" | "3d ago" | "3 Oct 2026" (a month or more).
    static func text(from date: Date, now: Date, timeZone: TimeZone = .current) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        if seconds < 3_600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600))h ago" }
        if seconds < 30 * 86_400 { return "\(Int(seconds / 86_400))d ago" }
        return ISODate.dayText(date: date, timeZone: timeZone)
    }
}

enum ActivityText {
    /// "Online" | "Last used 2h ago" | "Never"; nil when the backend does not report last use.
    static func text(online: Bool, lastUsedAt: Date?, reported: Bool, now: Date,
                     timeZone: TimeZone = .current) -> String? {
        if online { return "Online" }
        guard reported else { return nil }
        guard let lastUsedAt else { return "Never" }
        return "Last used " + RelativeTime.text(from: lastUsedAt, now: now, timeZone: timeZone)
    }
}

extension UsageGroup {
    /// Devices still signed in; signed-out devices only keep their usage in the total.
    var devicesText: String {
        let n = activeDevices
        return n == 1 ? "1 device" : "\(n) devices"
    }
}

enum LogoutPlan {
    /// A backend without POST /owner/users/logout answers 404.
    static func needsFallback(_ error: Error) -> Bool {
        if case APIError.status(404, _) = error { return true }
        return false
    }

    /// The fallback signs the user out device by device, with the per-device revoke the backend always had:
    /// every enabled device of these invites.
    static func fallbackTargets(devices: [OwnerDevice], codes: [String]) -> [OwnerDevice] {
        devices.filter { $0.enabled && codes.contains($0.inviteCode) }
    }

    static func deviceTitle(_ name: String) -> String { "Log out \(name)?" }

    static let deviceMessage = "It will need the invite code to reconnect."

    static let allMessage = "Each device will need the invite code to reconnect."

    static func allTitle(count: Int, label: String) -> String {
        count == 1 ? "Log out 1 device of \(label)?" : "Log out all \(count) devices of \(label)?"
    }
}

enum OwnerSectionTitle {
    /// "Invites · 6", "Activation Events · 0".
    static func counted(_ title: String, _ n: Int) -> String { "\(title) \u{00B7} \(n)" }

    /// "Devices · 2 online", or just "Devices" when none is online.
    static func devices(online n: Int) -> String { n > 0 ? "Devices \u{00B7} \(n) online" : "Devices" }
}

enum SignedOut {
    /// Shown on the activation screen when the server signed this device out.
    static let notice = "Signed out. Enter your invite code to reconnect."
}
