import Foundation

/// Per-device usage for the current period, from GET /owner/devices (`usage`).
/// Every field is optional and a field of the wrong type is read as missing, so a malformed
/// value cannot break the Owner Admin device list (see OwnerDevicesResponse).
struct DeviceUsage: Equatable {
    var usedGB: Double?
    var quotaGB: Double?
    var percent: Double?
    var uploadGB: Double?
    var downloadGB: Double?
}

extension DeviceUsage: Decodable {
    private enum CodingKeys: String, CodingKey { case usedGB, quotaGB, percent, uploadGB, downloadGB }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            usedGB: try? c.decodeIfPresent(Double.self, forKey: .usedGB),
            quotaGB: try? c.decodeIfPresent(Double.self, forKey: .quotaGB),
            percent: try? c.decodeIfPresent(Double.self, forKey: .percent),
            uploadGB: try? c.decodeIfPresent(Double.self, forKey: .uploadGB),
            downloadGB: try? c.decodeIfPresent(Double.self, forKey: .downloadGB)
        )
    }
}

/// `period` from GET /owner/devices: ISO-8601 start / end of the usage period.
struct UsagePeriod: Equatable {
    var start: String?
    var end: String?
}

extension UsagePeriod: Decodable {
    private enum CodingKeys: String, CodingKey { case start, end }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            start: try? c.decodeIfPresent(String.self, forKey: .start),
            end: try? c.decodeIfPresent(String.self, forKey: .end)
        )
    }
}

enum UsageLevel: Equatable {
    case ok        // < 70 %
    case warning   // 70 % ..< 90 %
    case critical  // >= 90 %

    init(percent: Double) {
        switch percent {
        case ..<70: self = .ok
        case ..<90: self = .warning
        default:    self = .critical
        }
    }
}

struct UsageRow: Equatable, Identifiable {
    let id: String
    let displayName: String
    /// "deviceName · app version", nil when the backend sent neither.
    let detail: String?
    let usedGB: Double
    let quotaGB: Double?
    /// nil when there is no quota (unlimited): no bar is drawn.
    let percent: Double?
    let enabled: Bool

    var level: UsageLevel { UsageLevel(percent: percent ?? 0) }

    /// Bar fill, clamped to 0...1 (usage can exceed the quota). Never NaN or infinite: it becomes a width.
    var fraction: Double? { percent.map { $0.isFinite ? min(max($0 / 100, 0), 1) : 0 } }

    var amountText: String { UsageFormat.amount(used: usedGB, quota: quotaGB) }
    var percentText: String? { percent.map(UsageFormat.percent) }
}

struct UsageGroup: Equatable, Identifiable {
    var id: String { label }
    let label: String
    let totalGB: Double
    let rows: [UsageRow]
}

enum UsageFormat {
    /// "12.3" (one decimal, no grouping, locale independent).
    static func gb(_ value: Double) -> String { String(format: "%.1f", value) }

    private static func quota(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0f", value) : gb(value)
    }

    /// "12.3 / 1000 GB", or "12.3 GB" when there is no quota.
    static func amount(used: Double, quota q: Double?) -> String {
        if let q, q > 0 { return "\(gb(used)) / \(quota(q)) GB" }
        return "\(gb(used)) GB"
    }

    static func total(_ value: Double) -> String { "\(gb(value)) GB" }

    static func percent(_ value: Double) -> String { String(format: "%.1f%%", value) }
}

enum UsageMetrics {
    /// Groups devices by invite label (= user). Users by total used GB descending, devices by
    /// used GB descending. Devices without a `usage` object are left out, so an older backend
    /// yields no groups and the section stays hidden.
    static func groups(devices: [OwnerDevice], usage: [String: DeviceUsage]) -> [UsageGroup] {
        var byLabel: [String: [UsageRow]] = [:]
        for device in devices {
            // A usage figure that is not a finite number is unusable; a negative one counts as 0.
            guard let u = usage[device.profileId], let reported = u.usedGB, reported.isFinite else { continue }
            let used = max(reported, 0)
            let quota: Double? = u.quotaGB.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            let percent: Double? = quota.flatMap { quota in
                let value = u.percent.flatMap { $0.isFinite ? $0 : nil } ?? used / quota * 100
                return value.isFinite ? max(value, 0) : nil
            }
            let detail = [device.deviceName, device.appVersion]
                .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " \u{00B7} ")
            let row = UsageRow(
                id: device.profileId,
                displayName: device.displayName,
                detail: detail.isEmpty ? nil : detail,
                usedGB: used,
                quotaGB: quota,
                percent: percent,
                enabled: device.enabled
            )
            byLabel[label(for: device), default: []].append(row)
        }
        return byLabel
            .map { label, rows in
                UsageGroup(
                    label: label,
                    totalGB: rows.reduce(0) { $0 + $1.usedGB },
                    rows: rows.sorted {
                        $0.usedGB != $1.usedGB ? $0.usedGB > $1.usedGB : $0.displayName < $1.displayName
                    }
                )
            }
            .sorted {
                $0.totalGB != $1.totalGB ? $0.totalGB > $1.totalGB : $0.label < $1.label
            }
    }

    private static func label(for device: OwnerDevice) -> String {
        for candidate in [device.inviteLabel, device.ownerLabel] {
            if let text = candidate?.trimmingCharacters(in: .whitespaces), !text.isEmpty { return text }
        }
        return "Unknown"
    }

    /// "since 1 Oct" from the period start (UTC); nil when the backend sent no usable start.
    static func periodText(_ period: UsagePeriod?) -> String? {
        guard let start = period?.start, let date = parseISO(start) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "d MMM"
        return "since " + f.string(from: date)
    }

    private static func parseISO(_ s: String) -> Date? {
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
}
