import Foundation

// Owner Admin "People": one invite code = one person, with that person's devices on their own page.
// Plain Foundation so Tests/SelfTest can run it.

// MARK: - Monthly quota input

/// The monthly quota field: any whole number of GB from 1 to 2000 (e.g. 48), plus quick values.
enum QuotaInput {
    static let range = 1...2000
    static let presets = [10, 50, 100, 200]

    enum Problem: Error, Equatable {
        case empty, notWholeNumber, notANumber, outOfRange

        var message: String {
            switch self {
            case .empty, .outOfRange: return "1\u{2013}2000 GB"
            case .notWholeNumber:     return "Whole GB only"
            case .notANumber:         return "Numbers only"
            }
        }
    }

    static func parse(_ text: String) -> Result<Int, Problem> {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return .failure(.empty) }
        let isDigit: (Character) -> Bool = { $0.isASCII && $0.isNumber }
        if t.allSatisfy(isDigit) {
            guard let value = Int(t), range.contains(value) else { return .failure(.outOfRange) }
            return .success(value)
        }
        // "48.5", "48,5", "48.": a number, but not a whole one.
        let separator: Character = t.contains(".") ? "." : ","
        let parts = t.split(separator: separator, omittingEmptySubsequences: false)
        if parts.count == 2,
           parts.allSatisfy({ $0.allSatisfy(isDigit) }), parts.contains(where: { !$0.isEmpty }) {
            return .failure(.notWholeNumber)
        }
        return .failure(.notANumber)
    }
}

// MARK: - IPv6 entry of a device

/// How a device's IPv6 entry reads: the shared /64 half faint, the device half dark; no entry = "IPv4 only".
enum IPv6Display: Equatable {
    case ipv4Only
    /// `prefix + host` is the full address. `prefix` is empty when the text is not an IPv6 address.
    case address(prefix: String, host: String)

    static let ipv4OnlyText = "IPv4 only"

    static func make(_ entry: String?) -> IPv6Display {
        guard let raw = entry?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return .ipv4Only }
        guard let groups = groups(of: raw) else { return .address(prefix: "", host: raw) }
        let hex = groups.map { String($0, radix: 16) }
        let prefix = hex[0..<4].joined(separator: ":") + ":"
        return .address(prefix: prefix, host: compressedHost(Array(groups[4..<8])))
    }

    /// The eight 16-bit groups, or nil when this is not a plain IPv6 address.
    static func groups(of text: String) -> [UInt16]? {
        var s = text
        if s.hasPrefix("[") && s.hasSuffix("]") { s = String(s.dropFirst().dropLast()) }
        if let zone = s.firstIndex(of: "%") { s = String(s[..<zone]) }
        if let slash = s.firstIndex(of: "/") { s = String(s[..<slash]) }
        guard !s.contains("."), s.contains(":") else { return nil }

        func hexGroups(_ part: Substring) -> [UInt16]? {
            if part.isEmpty { return [] }
            var out: [UInt16] = []
            for piece in part.split(separator: ":", omittingEmptySubsequences: false) {
                guard (1...4).contains(piece.count), let v = UInt16(piece, radix: 16) else { return nil }
                out.append(v)
            }
            return out
        }

        let halves = s.components(separatedBy: "::")
        switch halves.count {
        case 1:
            guard let all = hexGroups(Substring(s)), all.count == 8 else { return nil }
            return all
        case 2:
            guard let head = hexGroups(Substring(halves[0])), let tail = hexGroups(Substring(halves[1])),
                  head.count + tail.count <= 7 else { return nil }
            return head + Array(repeating: 0, count: 8 - head.count - tail.count) + tail
        default:
            return nil
        }
    }

    /// The device half (last four groups), RFC 5952 style: the longest run of two or more zero groups becomes
    /// "::". The prefix already ends in ":", so a run at the start is written as a single ":".
    static func compressedHost(_ groups: [UInt16]) -> String {
        let hex = groups.map { String($0, radix: 16) }
        var best: (start: Int, length: Int)?
        var i = 0
        while i < groups.count {
            guard groups[i] == 0 else { i += 1; continue }
            var j = i
            while j < groups.count && groups[j] == 0 { j += 1 }
            if j - i >= 2, j - i > (best?.length ?? 0) { best = (i, j - i) }
            i = j
        }
        guard let run = best else { return hex.joined(separator: ":") }
        let left = hex[..<run.start].joined(separator: ":")
        let right = hex[(run.start + run.length)...].joined(separator: ":")
        if run.start == 0 { return ":" + right }
        return left + "::" + right
    }
}

// MARK: - People

struct PersonDevice: Equatable, Identifiable {
    var id: String { device.profileId }
    let device: OwnerDevice
    /// This period; nil when the backend sent no usable usage for the device.
    let usedGB: Double?
    let lastUsedAt: Date?
    /// Connected right now (a signed-out device never is).
    let online: Bool
    let ipv6: IPv6Display
    /// The device dials an IPv6 entry of its own rather than the shared one.
    let dedicated: Bool

    var signedIn: Bool { device.enabled }

    /// "Now" | "2h ago" | "Never"; nil when the backend does not report last use.
    func activity(reported: Bool, now: Date, timeZone: TimeZone = .current) -> String? {
        if online { return "Now" }
        guard reported else { return nil }
        guard let lastUsedAt else { return "Never" }
        return RelativeTime.text(from: lastUsedAt, now: now, timeZone: timeZone)
    }

    /// "v1.2 (43) · 2h ago" (+ "Signed out").
    func detail(reported: Bool, now: Date, timeZone: TimeZone = .current) -> String {
        let version = device.appVersion?.trimmingCharacters(in: .whitespaces).nilIfEmpty.map { "v" + $0 }
        return [version, activity(reported: reported, now: now, timeZone: timeZone), signedIn ? nil : "Signed out"]
            .compactMap { $0 }
            .joined(separator: " \u{00B7} ")
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

struct Person: Equatable, Identifiable {
    var id: String { invite.code }
    let invite: OwnerInvite
    let access: InviteAccess?
    let devices: [PersonDevice]
    /// The owner's own invite: never paused from here, deleted or logged out.
    let isOwner: Bool
    /// Does the backend report last use at all (otherwise no "Never" / "2h ago").
    let lastUsedReported: Bool

    var code: String { invite.code }
    var label: String { invite.label }
    var paused: Bool { !invite.enabled }
    /// Devices still signed in.
    var devicesInUse: Int { devices.filter(\.signedIn).count }
    var online: Bool { devices.contains { $0.online } }
    /// Everything this person used this period (signed-out devices included); nil when nothing was reported.
    var usedGB: Double? {
        let values = devices.compactMap(\.usedGB)
        return values.isEmpty ? nil : values.reduce(0, +)
    }
    var lastUsedAt: Date? { devices.compactMap(\.lastUsedAt).max() }

    /// "Now" | "2h ago" | "Never"; nil when the backend does not report last use.
    func activity(now: Date, timeZone: TimeZone = .current) -> String? {
        if online { return "Now" }
        guard lastUsedReported else { return nil }
        guard let last = lastUsedAt else { return "Never" }
        return RelativeTime.text(from: last, now: now, timeZone: timeZone)
    }

    /// "2/3 devices": signed in / device limit.
    var devicesText: String { "\(devicesInUse)/\(invite.maxDevices) device" + (invite.maxDevices == 1 ? "" : "s") }

    /// The region the person is on, where the backend reports it (not for the owner, who uses all of them).
    var regionName: String? {
        guard !isOwner, access?.isPresent == true, let region = access?.region, !region.isEmpty else { return nil }
        return region.capitalized
    }

    /// "Tokyo · 2/3 devices · 2h ago" — the second line of a People row.
    func summary(now: Date, timeZone: TimeZone = .current) -> String {
        [regionName, devicesText, activity(now: now, timeZone: timeZone)]
            .compactMap { $0 }
            .joined(separator: " \u{00B7} ")
    }
}

enum PeopleDirectory {
    /// One person per invite code, with the devices activated from that code. Paused invites stay listed; devices
    /// whose invite is not in the list (a deleted invite) belong to nobody here and are not shown.
    /// Order: most used this period first, then the most recent use, then the name.
    static func people(invites: [OwnerInvite], access: [String: InviteAccess], devices: [OwnerDevice],
                       usage: [String: DeviceUsage], lastUsed: [String: DeviceLastUsed],
                       ownerCodes: Set<String>) -> [Person] {
        let byCode = Dictionary(grouping: devices, by: \.inviteCode)
        let reported = !lastUsed.isEmpty
        return invites
            .map { invite in
                let rows = (byCode[invite.code] ?? []).map { device in
                    PersonDevice(
                        device: device,
                        usedGB: usage[device.profileId]?.usedGB.flatMap { $0.isFinite ? max($0, 0) : nil },
                        lastUsedAt: lastUsed[device.profileId]?.date,
                        online: device.enabled && (device.online ?? device.inUse),
                        ipv6: IPv6Display.make(device.ipv6Entry),
                        dedicated: device.ipv6EntryDedicated == true && IPv6Display.make(device.ipv6Entry) != .ipv4Only
                    )
                }
                return Person(invite: invite, access: access[invite.code], devices: rows.sorted(by: deviceBefore),
                              isOwner: ownerCodes.contains(invite.code), lastUsedReported: reported)
            }
            .sorted(by: personBefore)
    }

    static func personBefore(_ a: Person, _ b: Person) -> Bool {
        let ua = a.usedGB ?? -1, ub = b.usedGB ?? -1
        if ua != ub { return ua > ub }
        switch (a.lastUsedAt, b.lastUsedAt) {
        case let (x?, y?) where x != y: return x > y
        case (_?, nil):                 return true
        case (nil, _?):                 return false
        default:                        break
        }
        return a.label.localizedCaseInsensitiveCompare(b.label) == .orderedAscending
    }

    /// Signed-in devices first, online first, then the most used, then the name.
    static func deviceBefore(_ a: PersonDevice, _ b: PersonDevice) -> Bool {
        if a.signedIn != b.signedIn { return a.signedIn }
        if a.online != b.online { return a.online }
        let ua = a.usedGB ?? -1, ub = b.usedGB ?? -1
        if ua != ub { return ua > ub }
        return a.device.displayName.localizedCaseInsensitiveCompare(b.device.displayName) == .orderedAscending
    }
}

/// What the person page edits. Save sends it through InviteBody.update (all six fields, plus region /
/// durationDays only when they changed).
struct PersonDraft: Equatable {
    static let deviceLimit = 1...100

    var code: String
    var label: String
    var quotaText: String
    var maxDevices: Int
    var enabled: Bool
    var region: String
    var access: AccessChoice

    init(invite: OwnerInvite, access: InviteAccess?, regionOptions: [VPNRegion]) {
        code = invite.code
        label = invite.label
        // No quota on record: the field starts empty and must be filled before saving (never a silent default).
        quotaText = invite.monthlyQuotaGB.map(String.init) ?? ""
        maxDevices = invite.maxDevices
        enabled = invite.enabled
        let current = access?.region ?? RegionPolicy.defaultID
        region = regionOptions.first(where: { RegionPolicy.matches($0.id, current) })?.id ?? current
        self.access = AccessChoice(durationDays: access?.durationDays)
    }

    var quota: Result<Int, QuotaInput.Problem> { QuotaInput.parse(quotaText) }

    /// What Save sends, or nil while something is not valid (quota, or an empty code / name).
    func edit(showsRegion: Bool, showsAccess: Bool) -> InviteEdit? {
        let c = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let l = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard case .success(let gb) = quota, !c.isEmpty, !l.isEmpty, Self.deviceLimit.contains(maxDevices) else { return nil }
        return InviteEdit(code: c, label: l, maxDevices: maxDevices, monthlyQuotaGB: gb, enabled: enabled,
                          region: showsRegion ? region : nil, access: showsAccess ? access : nil)
    }
}

// MARK: - Recently Deleted

/// One entry of GET /owner/invites/deleted. Only `code` is required; anything else of the wrong type reads as missing.
struct DeletedInvite: Equatable, Identifiable {
    var id: String { code + "|" + (deletedAt ?? "") }
    let code: String
    let label: String
    let deletedAt: String?
    var maxDevices: Int?
    var monthlyQuotaGB: Int?
    var region: String?
    var deviceCount: Int?
}

extension DeletedInvite: Decodable {
    private enum CodingKeys: String, CodingKey { case code, label, deletedAt, maxDevices, monthlyQuotaGB, region, deviceCount }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decode(String.self, forKey: .code)
        let label = (try? c.decodeIfPresent(String.self, forKey: .label)) ?? nil
        self.label = label.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } ?? code
        deletedAt = (try? c.decodeIfPresent(String.self, forKey: .deletedAt)) ?? nil
        maxDevices = (try? c.decodeIfPresent(Int.self, forKey: .maxDevices)) ?? nil
        monthlyQuotaGB = (try? c.decodeIfPresent(Int.self, forKey: .monthlyQuotaGB)) ?? nil
        region = (try? c.decodeIfPresent(String.self, forKey: .region)) ?? nil
        deviceCount = (try? c.decodeIfPresent(Int.self, forKey: .deviceCount)) ?? nil
    }
}

struct DeletedInvitesResponse: Decodable {
    let ok: Bool
    let error: String?
    let invites: [DeletedInvite]

    private enum CodingKeys: String, CodingKey { case ok, error, invites }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = try c.decode(Bool.self, forKey: .ok)
        error = try? c.decodeIfPresent(String.self, forKey: .error)
        invites = (try? c.decodeIfPresent(LossyArray<DeletedInvite>.self, forKey: .invites))?.elements ?? []
    }
}

enum RecentlyDeleted {
    static let keepDays = 30
    static let restoredNote = "Devices need to sign in again"
    static let deleteMessage = "Restorable from Recently Deleted for 30 days."

    /// A backend without GET /owner/invites/deleted answers 404: the entry is hidden, no error is shown.
    static func isUnsupported(_ error: Error) -> Bool {
        if case APIError.status(404, _) = error { return true }
        return false
    }

    /// Newest deletion first (entries without a readable date last).
    static func sorted(_ invites: [DeletedInvite]) -> [DeletedInvite] {
        invites.sorted { a, b in
            switch (a.deletedAt.flatMap(ISODate.parse), b.deletedAt.flatMap(ISODate.parse)) {
            case let (x?, y?): return x > y
            case (_?, nil):    return true
            default:           return false
            }
        }
    }

    /// "Deleted 3d ago · 1 device · 100 GB · Tokyo".
    static func detail(_ invite: DeletedInvite, now: Date, timeZone: TimeZone = .current) -> String {
        var parts: [String] = []
        if let date = invite.deletedAt.flatMap(ISODate.parse) {
            parts.append("Deleted " + RelativeTime.text(from: date, now: now, timeZone: timeZone))
        }
        if let n = invite.deviceCount { parts.append(n == 1 ? "1 device" : "\(n) devices") }
        if let gb = invite.monthlyQuotaGB { parts.append("\(gb) GB") }
        if let region = invite.region, !region.isEmpty { parts.append(region.capitalized) }
        return parts.joined(separator: " \u{00B7} ")
    }

    /// What a failed restore says.
    static func restoreMessage(_ error: Error) -> String {
        if case APIError.status(let code, _) = error {
            switch code {
            case 404: return "No longer in Recently Deleted"
            case 409: return "This code is in use by another invite"
            case 403: return "The owner invite cannot be restored"
            default:  break
            }
        }
        return error.localizedDescription
    }
}
