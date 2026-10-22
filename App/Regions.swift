import Foundation

/// A server region this device may use (`regions` in GET /profile).
struct VPNRegion: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let isDefault: Bool

    static let tokyo = VPNRegion(id: RegionPolicy.defaultID, name: "Tokyo", isDefault: true)

    init(id: String, name: String, isDefault: Bool = false) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(String.self, forKey: .id).trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = id
        self.name = try c.decodeIfPresent(String.self, forKey: .name) ?? id.capitalized
        self.isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
    }
}

/// Decodes a JSON array and silently drops elements that do not decode (a wrong shape
/// becomes an empty list). Used for fields added by newer backends, so a malformed new
/// field can never make an existing response fail to decode.
struct LossyArray<Element: Decodable>: Decodable {
    let elements: [Element]

    private struct Skip: Decodable {}

    init(from decoder: Decoder) throws {
        guard var c = try? decoder.unkeyedContainer() else {
            elements = []
            return
        }
        var out: [Element] = []
        while !c.isAtEnd {
            if let element = try? c.decode(Element.self) {
                out.append(element)
            } else {
                _ = try? c.decode(Skip.self)   // advance past the bad element
            }
        }
        elements = out
    }
}

enum RegionPolicy {
    static let defaultID = "tokyo"

    /// Region ids are compared case-insensitively everywhere.
    static func matches(_ a: String, _ b: String) -> Bool {
        a.lowercased() == b.lowercased()
    }

    static func isDefault(_ id: String) -> Bool { matches(id, defaultID) }

    /// Regions offered by a /profile response. Regions without an id and repeated ids are
    /// ignored; a backend that sends none usable (older server) means Tokyo only.
    static func offered(from decoded: [VPNRegion]?) -> [VPNRegion] {
        var seen = Set<String>()
        let usable = (decoded ?? []).filter { region in
            let key = region.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !key.isEmpty && seen.insert(key).inserted
        }
        return usable.isEmpty ? [.tokyo] : usable
    }

    /// Where the selection goes when the stored one is not offered: the server's default
    /// region, else the first one offered.
    static func fallback(in offered: [VPNRegion]) -> VPNRegion {
        offered.first(where: { $0.isDefault }) ?? offered.first ?? .tokyo
    }

    /// The offered region that matches the stored selection (written the way the server writes
    /// it), otherwise the fallback, so the picker always has a selection.
    static func resolveSelection(stored: String?, offered: [VPNRegion]) -> String {
        if let stored, let hit = offered.first(where: { matches($0.id, stored) }) { return hit.id }
        return fallback(in: offered).id
    }

    static func name(of id: String, in offered: [VPNRegion]) -> String {
        offered.first(where: { matches($0.id, id) })?.name ?? id.capitalized
    }

    static func serverAddress(for region: VPNRegion) -> String { "RedFluent \(region.name)" }

    /// providerConfiguration with this region, keeping everything else (token, apiBase, ...).
    static func providerConfiguration(_ existing: [String: Any]?, region: VPNRegion) -> [String: Any] {
        var config = existing ?? [:]
        config["region"] = region.id
        return config
    }

    /// A failed start of a non-default region must not leave on-demand retrying it for ever.
    static func disablesOnDemandAfterFailure(regionID: String) -> Bool { !isDefault(regionID) }

    /// Region name for the Server row. Several regions: what the tunnel really started with while
    /// connected ("—" when that cannot be read), otherwise the selection. One region: the profile's.
    static func serverDisplayName(regions: [VPNRegion], selectedID: String, connected: Bool,
                                  active: ActiveRegion?, profileRegion: String?) -> String? {
        guard regions.count > 1 else { return profileRegion }
        if connected { return active?.name ?? "—" }
        return name(of: selectedID, in: regions)
    }

    /// "In use" line under the picker: only while connected, only when the tunnel's region is
    /// unknown ("—") or differs from the picker.
    static func inUseCaption(connected: Bool, active: ActiveRegion?, selectedID: String) -> String? {
        guard connected else { return nil }
        guard let active else { return "—" }
        return matches(active.id, selectedID) ? nil : active.name
    }
}

/// The region the tunnel extension actually started with (see SharedContainer.writeActiveRegion).
struct ActiveRegion: Equatable {
    let id: String
    let name: String
}

/// Region state shared with the tunnel extension through the App Group defaults.
enum RegionStore {
    static let appGroupID = "group.com.redfluent.vpn"
    static let selectedKey = "rfv.region.selected"
    static let offeredKey = "rfv.region.offered"
    /// Written by the extension on every start: ["id": ..., "name": ...].
    /// Must stay identical to SharedContainer.activeRegionKey in the tunnel target.
    static let activeKey = "rfv.region.active"

    /// nil when the App Group suite is unavailable. The extension uses the very same suite and
    /// there is no fallback to private defaults, so the two sides can never silently disagree:
    /// without the suite the active region is simply unknown.
    static func sharedDefaults() -> UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func selectedID(_ d: UserDefaults? = sharedDefaults()) -> String {
        d?.string(forKey: selectedKey) ?? RegionPolicy.defaultID
    }

    static func saveSelected(_ id: String, to d: UserDefaults? = sharedDefaults()) {
        d?.set(id, forKey: selectedKey)
    }

    /// Last region list the server sent, so the picker is right on a cold start.
    static func offered(_ d: UserDefaults? = sharedDefaults()) -> [VPNRegion] {
        guard let data = d?.data(forKey: offeredKey),
              let regions = try? JSONDecoder().decode([VPNRegion].self, from: data)
        else { return [.tokyo] }
        return RegionPolicy.offered(from: regions)
    }

    static func saveOffered(_ regions: [VPNRegion], to d: UserDefaults? = sharedDefaults()) {
        if let data = try? JSONEncoder().encode(regions) {
            d?.set(data, forKey: offeredKey)
        }
    }

    /// The region to put in the tunnel configuration: the saved selection, validated
    /// against the cached server list.
    static func selectedRegion(_ d: UserDefaults? = sharedDefaults()) -> VPNRegion {
        let regions = offered(d)
        let id = RegionPolicy.resolveSelection(stored: selectedID(d), offered: regions)
        return regions.first(where: { $0.id == id }) ?? .tokyo
    }

    static func active(_ d: UserDefaults? = sharedDefaults()) -> ActiveRegion? {
        guard let dict = d?.dictionary(forKey: activeKey) as? [String: String],
              let id = dict["id"], let name = dict["name"] else { return nil }
        return ActiveRegion(id: id, name: name)
    }
}

/// Why the last tunnel start failed. The extension writes it just before it throws and the app reads
/// it: a file in the App Group container, so it does not depend on the order of NetworkExtension
/// status changes or on a preferences cache.
enum TunnelStartError {
    /// Must stay identical to SharedContainer.startErrorFileName in the tunnel target.
    static let fileName = "start-error.json"

    private struct Record: Decodable {
        let message: String
        let at: Double
    }

    static func fileURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: RegionStore.appGroupID)?
            .appendingPathComponent(fileName)
    }

    /// The message of a stored record, but only if it is not older than `since` (1 s of slack):
    /// an error from an earlier attempt must never be shown for a newer one.
    static func message(from data: Data?, since: Date) -> String? {
        guard let data,
              let record = try? JSONDecoder().decode(Record.self, from: data),
              !record.message.isEmpty,
              record.at >= since.timeIntervalSince1970 - 1
        else { return nil }
        return record.message
    }

    static func read(since: Date) -> String? {
        message(from: fileURL().flatMap { try? Data(contentsOf: $0) }, since: since)
    }

    static func clear() {
        if let url = fileURL() { try? FileManager.default.removeItem(at: url) }
    }
}
