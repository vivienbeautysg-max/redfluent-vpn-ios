import Foundation

/// Bridge to the App Group container that both the main app and the
/// Packet Tunnel extension can read/write.
enum SharedContainer {
    static let appGroupID = "group.com.redfluent.vpn"
    static let statsFileName = "stats.json"
    /// Must stay identical to RegionStore.activeKey in the app target.
    static let activeRegionKey = "rfv.region.active"
    /// Must stay identical to TunnelStartError.fileName in the app target.
    static let startErrorFileName = "start-error.json"

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

    /// Record which region this run of the tunnel really started with, for the app to show.
    static func writeActiveRegion(id: String, name: String) {
        UserDefaults(suiteName: appGroupID)?.set(["id": id, "name": name], forKey: activeRegionKey)
    }

    static func clearActiveRegion() {
        UserDefaults(suiteName: appGroupID)?.removeObject(forKey: activeRegionKey)
    }

    static var startErrorURL: URL? {
        containerURL?.appendingPathComponent(startErrorFileName)
    }

    /// {"message": ..., "at": epoch seconds, "kind": ...} — the format TunnelStartError (app target) reads.
    /// kind "start" is a failed start; "expired" / "revoked" is the server ending this device's access.
    static func encodeStartError(message: String, at: Date, kind: String = "start") -> Data? {
        try? JSONSerialization.data(withJSONObject: [
            "message": String(message.prefix(500)),
            "at": at.timeIntervalSince1970,
            "kind": kind,
        ] as [String: Any])
    }

    /// The server-side stop a stored record carries, nil for a plain start failure or garbage.
    static func stopKind(in data: Data?) -> StopKind? {
        guard let data,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let kind = object["kind"] as? String else { return nil }
        return StopKind(rawValue: kind)
    }

    /// Why this start failed, written just before the extension throws. Best effort like the stats file:
    /// the app then falls back to the error iOS recorded.
    static func writeStartError(_ message: String) {
        write(encodeStartError(message: message, at: Date()))
    }

    /// The server ended this device's access (expired / revoked). While this record stands, starts the app
    /// did not ask for (on-demand, Settings) are refused; the app clears it once its profile says it is fine.
    static func writeStopReason(_ kind: StopKind) {
        write(encodeStartError(message: kind.message, at: Date(), kind: kind.rawValue))
    }

    /// The stop record currently stored, if any.
    static func readStopReason() -> StopKind? {
        guard let url = startErrorURL else { return nil }
        return stopKind(in: try? Data(contentsOf: url))
    }

    /// Clear the record of an earlier failed start. A stop record is the lock described above and stays.
    static func clearStartError() {
        guard let url = startErrorURL, readStopReason() == nil else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func write(_ data: Data?) {
        guard let url = startErrorURL, let data else { return }
        try? data.write(to: url, options: [.atomic])
    }
}
