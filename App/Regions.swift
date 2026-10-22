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
        let id = try c.decode(String.self, forKey: .id)
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

    /// Regions offered by a /profile response. A backend that sends none (older server)
    /// or an empty list means Tokyo only.
    static func offered(from decoded: [VPNRegion]?) -> [VPNRegion] {
        guard let decoded, !decoded.isEmpty else { return [.tokyo] }
        return decoded
    }

    /// The stored selection if the server still offers it, otherwise Tokyo.
    static func resolveSelection(stored: String?, offered: [VPNRegion]) -> String {
        guard let stored, offered.contains(where: { $0.id == stored }) else { return defaultID }
        return stored
    }

    static func name(of id: String, in offered: [VPNRegion]) -> String {
        offered.first(where: { $0.id == id })?.name ?? id.capitalized
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

    static func defaults() -> UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static func selectedID(_ d: UserDefaults = defaults()) -> String {
        d.string(forKey: selectedKey) ?? RegionPolicy.defaultID
    }

    static func saveSelected(_ id: String, to d: UserDefaults = defaults()) {
        d.set(id, forKey: selectedKey)
    }

    /// Last region list the server sent, so the picker is right on a cold start.
    static func offered(_ d: UserDefaults = defaults()) -> [VPNRegion] {
        guard let data = d.data(forKey: offeredKey),
              let regions = try? JSONDecoder().decode([VPNRegion].self, from: data)
        else { return [.tokyo] }
        return RegionPolicy.offered(from: regions)
    }

    static func saveOffered(_ regions: [VPNRegion], to d: UserDefaults = defaults()) {
        if let data = try? JSONEncoder().encode(regions) {
            d.set(data, forKey: offeredKey)
        }
    }

    /// The region to put in the tunnel configuration: the saved selection, validated
    /// against the cached server list.
    static func selectedRegion(_ d: UserDefaults = defaults()) -> VPNRegion {
        let regions = offered(d)
        let id = RegionPolicy.resolveSelection(stored: d.string(forKey: selectedKey), offered: regions)
        return VPNRegion(id: id, name: RegionPolicy.name(of: id, in: regions), isDefault: id == RegionPolicy.defaultID)
    }

    static func active(_ d: UserDefaults = defaults()) -> ActiveRegion? {
        guard let dict = d.dictionary(forKey: activeKey) as? [String: String],
              let id = dict["id"], let name = dict["name"] else { return nil }
        return ActiveRegion(id: id, name: name)
    }
}
