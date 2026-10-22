import Foundation

// Account expiry (what /profile says) and per-invite region + access duration (Owner Admin).
// Everything here is plain Foundation so Tests/SelfTest can run it.

enum ISODate {
    /// ISO-8601 with or without fractional seconds, or a bare date.
    static func parse(_ s: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let d = plain.date(from: s) { return d }
        let dateOnly = ISO8601DateFormatter()
        dateOnly.formatOptions = [.withFullDate]
        return dateOnly.date(from: s)
    }

    /// "3 Nov 2026" in `timeZone` (the device's by default).
    static func dayText(_ iso: String?, timeZone: TimeZone = .current) -> String? {
        guard let iso, let date = parse(iso) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "d MMM yyyy"
        return f.string(from: date)
    }

    static func daysPhrase(_ n: Int) -> String { n == 1 ? "1 day left" : "\(max(n, 0)) days left" }
}

// MARK: - The signed-in account (GET /profile)

/// Account expiry as /profile reports it. All of it is absent on a backend that predates expiry.
struct ExpiryInfo: Codable, Equatable {
    var expired: Bool = false
    var expiresAt: String?
    var daysLeft: Int?

    static let none = ExpiryInfo()
}

enum ExpiryDisplay {
    /// "N days left" is shown only inside the last week.
    static let warnWithinDays = 7

    /// "Expired · 3 Nov 2026" (just "Expired" without a date); nil when the account is not expired.
    static func expiredText(_ info: ExpiryInfo, timeZone: TimeZone = .current) -> String? {
        guard info.expired else { return nil }
        guard let day = ISODate.dayText(info.expiresAt, timeZone: timeZone) else { return "Expired" }
        return "Expired \u{00B7} \(day)"
    }

    /// "29 days left" — only when not expired and at most a week is left; nothing otherwise.
    static func daysLeftText(_ info: ExpiryInfo) -> String? {
        guard !info.expired, let left = info.daysLeft, left <= warnWithinDays else { return nil }
        return ISODate.daysPhrase(left)
    }
}

/// The last expiry seen, kept so a cold start shows the right state before /profile answers.
enum ExpiryStore {
    static let key = "rfv.expiry"

    static func load(_ d: UserDefaults? = RegionStore.sharedDefaults()) -> ExpiryInfo {
        guard let data = d?.data(forKey: key),
              let info = try? JSONDecoder().decode(ExpiryInfo.self, from: data) else { return .none }
        return info
    }

    static func save(_ info: ExpiryInfo, to d: UserDefaults? = RegionStore.sharedDefaults()) {
        if let data = try? JSONEncoder().encode(info) { d?.set(data, forKey: key) }
    }
}

// MARK: - Owner Admin: one invite's region + access

enum StatusTone: Equatable {
    case neutral, warning, danger
}

struct InviteStatus: Equatable {
    let text: String
    let tone: StatusTone
}

/// The 1.2 fields of an invite from GET /owner/invites. All optional, and a wrong-typed value reads as
/// missing: a backend that predates 1.2 sends none of them, and a malformed one must not break the list.
struct InviteAccess: Equatable {
    var region: String?
    var durationDays: Int?
    var activatedAt: String?
    var effectiveExpiresAt: String?
    var daysLeft: Int?
    var expired: Bool?

    /// Does the backend know about region / access at all?
    var isPresent: Bool {
        region != nil || durationDays != nil || activatedAt != nil
            || effectiveExpiresAt != nil || daysLeft != nil || expired != nil
    }
}

extension InviteAccess: Decodable {
    private enum CodingKeys: String, CodingKey {
        case region, durationDays, activatedAt, effectiveExpiresAt, daysLeft, expired
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            region: try? c.decodeIfPresent(String.self, forKey: .region),
            durationDays: try? c.decodeIfPresent(Int.self, forKey: .durationDays),
            activatedAt: try? c.decodeIfPresent(String.self, forKey: .activatedAt),
            effectiveExpiresAt: try? c.decodeIfPresent(String.self, forKey: .effectiveExpiresAt),
            daysLeft: try? c.decodeIfPresent(Int.self, forKey: .daysLeft),
            expired: try? c.decodeIfPresent(Bool.self, forKey: .expired)
        )
    }
}

enum InviteStatusLine {
    /// "Expired 3 Nov 2026" | "Starts on activation" | "Expires 21 Nov 2026 · 29 days left"; nil for no limit.
    static func status(_ access: InviteAccess?, timeZone: TimeZone = .current) -> InviteStatus? {
        guard let access else { return nil }
        if access.expired == true {
            let day = ISODate.dayText(access.effectiveExpiresAt, timeZone: timeZone)
            return InviteStatus(text: day.map { "Expired \($0)" } ?? "Expired", tone: .danger)
        }
        if access.durationDays != nil, access.effectiveExpiresAt == nil {
            return InviteStatus(text: "Starts on activation", tone: .neutral)
        }
        guard let day = ISODate.dayText(access.effectiveExpiresAt, timeZone: timeZone) else { return nil }
        var text = "Expires \(day)"
        if let left = access.daysLeft { text += " \u{00B7} \(ISODate.daysPhrase(left))" }
        let soon = (access.daysLeft ?? Int.max) <= ExpiryDisplay.warnWithinDays
        return InviteStatus(text: text, tone: soon ? .warning : .neutral)
    }
}

enum AccessPreset: Equatable, CaseIterable, Identifiable {
    case noLimit, d7, d30, d90, d180, d365, custom

    var id: AccessPreset { self }

    var label: String {
        switch self {
        case .noLimit: return "No limit"
        case .d7:      return "7 days"
        case .d30:     return "30 days"
        case .d90:     return "90 days"
        case .d180:    return "180 days"
        case .d365:    return "365 days"
        case .custom:  return "Custom"
        }
    }

    /// nil for "No limit" and "Custom".
    var days: Int? {
        switch self {
        case .d7:   return 7
        case .d30:  return 30
        case .d90:  return 90
        case .d180: return 180
        case .d365: return 365
        case .noLimit, .custom: return nil
        }
    }
}

/// The Access picker's state: a preset, or "Custom" with its own number of days.
struct AccessChoice: Equatable {
    static let maxDays = 3650

    var preset: AccessPreset
    var customDays: Int

    init(preset: AccessPreset = .noLimit, customDays: Int = 30) {
        self.preset = preset
        self.customDays = Self.clamp(customDays)
    }

    /// The choice that shows a stored duration (nil = no limit).
    init(durationDays: Int?) {
        guard let days = durationDays else {
            self.init()
            return
        }
        if let preset = AccessPreset.allCases.first(where: { $0.days == days }) {
            self.init(preset: preset, customDays: days)
        } else {
            self.init(preset: .custom, customDays: days)
        }
    }

    /// What goes to the server: nil = no limit, else 1...3650.
    var durationDays: Int? {
        switch preset {
        case .noLimit: return nil
        case .custom:  return Self.clamp(customDays)
        default:       return preset.days
        }
    }

    /// "No limit" / "30 days" — how a chosen duration reads once saved.
    var summary: String { durationDays.map { "\($0) days" } ?? "No limit" }

    static func clamp(_ days: Int) -> Int { min(max(days, 1), maxDays) }
}

/// Region choices for an invite: the owner's own regions (Singapore only when the owner can use it), plus the
/// invite's current one so an existing assignment is still shown.
enum InviteRegionOptions {
    static func options(ownerRegions: [VPNRegion], current: String?) -> [VPNRegion] {
        var out = RegionPolicy.offered(from: ownerRegions)
        if !out.contains(where: { RegionPolicy.isDefault($0.id) }) { out.insert(.tokyo, at: 0) }
        if let current, !current.isEmpty, !out.contains(where: { RegionPolicy.matches($0.id, current) }) {
            out.append(VPNRegion(id: current.lowercased(), name: current.capitalized))
        }
        return out
    }
}

// MARK: - Request bodies

enum JSONValue: Encodable, Equatable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case null

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .int(let v):    try c.encode(v)
        case .bool(let v):   try c.encode(v)
        case .null:          try c.encodeNil()
        }
    }
}

/// What the Edit / Create sheets hand back. `region` / `access` are nil when those controls are not shown.
struct InviteEdit: Equatable {
    var code: String
    var label: String
    var maxDevices: Int
    var monthlyQuotaGB: Int
    var enabled: Bool
    var region: String?
    var access: AccessChoice?
}

enum InviteBody {
    /// POST /owner/invites/update. The existing fields go as before; `region` and `durationDays` only when
    /// they changed (`durationDays: null` clears the limit), so a field that was not touched is never clobbered.
    static func update(original: OwnerInvite, originalAccess: InviteAccess?, edit: InviteEdit) -> [String: JSONValue] {
        var body: [String: JSONValue] = [
            "code": .string(original.code),
            "newCode": .string(edit.code),
            "label": .string(edit.label),
            "maxDevices": .int(edit.maxDevices),
            "monthlyQuotaGB": .int(edit.monthlyQuotaGB),
            "enabled": .bool(edit.enabled),
        ]
        guard originalAccess?.isPresent == true else { return body }
        if let region = edit.region,
           !RegionPolicy.matches(region, originalAccess?.region ?? RegionPolicy.defaultID) {
            body["region"] = .string(region)
        }
        if let access = edit.access, access.durationDays != originalAccess?.durationDays {
            body["durationDays"] = access.durationDays.map { JSONValue.int($0) } ?? .null
        }
        return body
    }

    /// POST /owner/invites. `region` goes only when it is not Tokyo, `durationDays` only when there is a limit.
    static func create(code: String, label: String?, maxDevices: Int, monthlyQuotaGB: Int,
                       region: String?, access: AccessChoice?) -> [String: JSONValue] {
        var body: [String: JSONValue] = [
            "code": .string(code),
            "maxDevices": .int(maxDevices),
            "monthlyQuotaGB": .int(monthlyQuotaGB),
        ]
        if let label { body["label"] = .string(label) }
        if let region, !RegionPolicy.isDefault(region) { body["region"] = .string(region) }
        if let days = access?.durationDays { body["durationDays"] = .int(days) }
        return body
    }
}
