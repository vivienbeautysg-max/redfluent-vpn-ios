import Foundation

/// Request/response rules for `GET /device/runtime-config`, kept free of NetworkExtension
/// so they can be exercised by Tests/SelfTest.
enum RuntimeConfigRequest {
    static let defaultRegion = "tokyo"
    /// One request, no retries. Generous: from mainland China the API answers in 1-7 s, sometimes 15.
    static let timeout: TimeInterval = 15

    /// The device token to send: the one the app mirrors into the App Group (always the freshest, it follows
    /// renewals), else the one saved in the tunnel configuration at the last Connect (an app updated from 1.2
    /// that has not run yet has no mirror).
    static func token(appGroup: String?, saved: String?) -> String? {
        for candidate in [appGroup, saved] {
            if let token = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty { return token }
        }
        return nil
    }

    /// Region ids are compared case-insensitively (same rule as RegionPolicy in the app target).
    static func isDefault(region: String) -> Bool { region.lowercased() == defaultRegion }

    private static let idCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")

    /// The `region` query value to send, or nil for no parameter. A device whose region the server decides
    /// (everyone but the owner) never sends one; the default region (Tokyo) sends today's request unchanged.
    static func regionParameter(region: String, serverDecides: Bool) -> String? {
        if serverDecides || isDefault(region: region) { return nil }
        return region
    }

    /// `base` + path, plus `?region=<id>` for a non-default region. Built by string concatenation:
    /// URL.appendingPathComponent would percent-escape the "?" (same trap as APIClient.apiURL).
    /// `region` nil or the default region sends today's request unchanged.
    static func url(base: String, region: String?) -> URL? {
        var s = base + "/device/runtime-config"
        if let region, !isDefault(region: region) {
            guard let id = region.addingPercentEncoding(withAllowedCharacters: idCharacters) else { return nil }
            s += "?region=" + id
        }
        return URL(string: s)
    }

    /// A non-default region that was asked for explicitly must be confirmed by the server. A backend that
    /// predates regions ignores the query and returns the Tokyo config; accepting that would connect to
    /// Tokyo while the app says otherwise.
    static func confirms(region: String, in response: [String: Any]) -> Bool {
        guard let echoed = response["region"] as? String else { return false }
        return echoed.lowercased() == region.lowercased()
    }

    /// `runtimeMeta.ipv4Blocked` of a 200 answer: the region's IPv4 entry is blocked in China right now. nil when
    /// the backend does not say (an older backend), or says it with anything but a JSON true / false.
    static func ipv4Blocked(in response: [String: Any]) -> Bool? {
        guard let meta = response["runtimeMeta"] as? [String: Any],
              let value = meta["ipv4Blocked"] as? NSNumber,
              CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
        return value.boolValue
    }

    /// The server's reason from an error body such as {"ok":false,"error":"region not allowed"}.
    static func serverReason(from body: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let reason = object["error"] as? String, !reason.isEmpty else { return nil }
        return reason
    }

    /// Text of the error shown in the app when a non-default region cannot be loaded.
    static func failureMessage(region: String, detail: String) -> String {
        "\(region.capitalized) server unavailable: \(detail)"
    }
}
