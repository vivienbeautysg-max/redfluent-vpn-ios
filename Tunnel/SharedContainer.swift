import Foundation

/// Bridge to the App Group container that both the main app and the
/// Packet Tunnel extension can read/write.
enum SharedContainer {
    static let appGroupID = "group.com.redfluent.vpn"
    static let statsFileName = "stats.json"

    static var containerURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    static var statsURL: URL? {
        containerURL?.appendingPathComponent(statsFileName)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Write the snapshot atomically. Failures are silent — stats writing
    /// must never destabilise the tunnel extension.
    static func writeStats(_ snapshot: StatsSnapshot) {
        guard let url = statsURL else { return }
        do {
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: [.atomic])
        } catch {
            // Intentionally swallowed; stats are best-effort.
        }
    }

    /// Read the latest snapshot, or `nil` if absent / unreadable.
    static func readStats() -> StatsSnapshot? {
        guard let url = statsURL,
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? decoder.decode(StatsSnapshot.self, from: data)
    }
}
