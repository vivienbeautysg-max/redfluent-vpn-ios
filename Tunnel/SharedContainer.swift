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
    /// Must stay identical to LastGoodTunnelConfig.fileName in the app target.
    static let lastGoodFileName = "last-good-config.json"
    /// Must stay identical to DeviceTokenMirror.fileName in the app target.
    static let deviceTokenFileName = "device-token"
    /// Must stay identical to RegionStore.ipv4BlockedKey in the app target.
    static let ipv4BlockedKey = "rfv.region.ipv4Blocked"

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

    /// [region id (lowercased): runtimeMeta.ipv4Blocked of that region's last runtime config]. A region whose last
    /// config did not say (older backend) has no entry, so the app keeps its old rule for it.
    static func updatedIPv4Blocked(_ current: [String: Bool], region: String, blocked: Bool?) -> [String: Bool] {
        var next = current
        next[region.lowercased()] = blocked
        return next
    }

    /// After every runtime config the server answered with (start and follow checks), for the app's Wi-Fi hint.
    static func writeIPv4Blocked(_ blocked: Bool?, region: String) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        let current = defaults.dictionary(forKey: ipv4BlockedKey) as? [String: Bool] ?? [:]
        defaults.set(updatedIPv4Blocked(current, region: region, blocked: blocked), forKey: ipv4BlockedKey)
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

    // MARK: Last good config

    /// The last runtime config the server issued to this device (before the clash API is injected).
    struct LastGood: Equatable {
        let config: Data
        /// The region it was fetched for.
        let region: String
        let serverRegion: String?
        let fetchedAt: Date
    }

    static var lastGoodURL: URL? {
        containerURL?.appendingPathComponent(lastGoodFileName)
    }

    /// {"fetchedAt": epoch seconds, "region": id, "serverRegion": name, "runtimeConfig": {...}}. Nil unless
    /// `config` is a JSON object.
    static func encodeLastGood(config: Data, region: String, serverRegion: String?, fetchedAt: Date) -> Data? {
        guard let object = try? JSONSerialization.jsonObject(with: config) as? [String: Any] else { return nil }
        var record: [String: Any] = [
            "fetchedAt": fetchedAt.timeIntervalSince1970,
            "region": region,
            "runtimeConfig": object,
        ]
        if let serverRegion { record["serverRegion"] = serverRegion }
        return try? JSONSerialization.data(withJSONObject: record)
    }

    static func decodeLastGood(_ data: Data?) -> LastGood? {
        guard let data,
              let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let at = record["fetchedAt"] as? Double, at.isFinite,
              let region = record["region"] as? String, !region.isEmpty,
              let object = record["runtimeConfig"] as? [String: Any],
              let config = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return nil }
        return LastGood(config: config, region: region, serverRegion: record["serverRegion"] as? String,
                        fetchedAt: Date(timeIntervalSince1970: at))
    }

    /// Keep `config` as this device's last good one. Atomic; readable from the first unlock after boot, so an
    /// on-demand start while the phone is locked can still use it; not in backups. False when it could not be written.
    @discardableResult
    static func writeLastGood(config: Data, region: String, serverRegion: String?, at: Date = Date()) -> Bool {
        guard let url = lastGoodURL,
              let data = encodeLastGood(config: config, region: region, serverRegion: serverRegion, fetchedAt: at)
        else { return false }
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            return false
        }
        do {
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var target = url
            try target.setResourceValues(values)
            return true
        } catch {
            // Credentials never stay in a file that a backup would carry off.
            try? FileManager.default.removeItem(at: url)
            return false
        }
    }

    static func readLastGood() -> LastGood? {
        decodeLastGood(lastGoodURL.flatMap { try? Data(contentsOf: $0) })
    }

    static func clearLastGood() {
        guard let url = lastGoodURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: Device token (written by the app, see DeviceTokenMirror)

    static var deviceTokenURL: URL? {
        containerURL?.appendingPathComponent(deviceTokenFileName)
    }

    /// The token text, nil when absent or blank.
    static func decodeDeviceToken(_ data: Data?) -> String? {
        guard let data, let text = String(data: data, encoding: .utf8) else { return nil }
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    static func readDeviceToken() -> String? {
        decodeDeviceToken(deviceTokenURL.flatMap { try? Data(contentsOf: $0) })
    }
}
