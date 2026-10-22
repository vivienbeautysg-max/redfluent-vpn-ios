import Foundation

/// Request/response rules for `GET /device/runtime-config`, kept free of NetworkExtension
/// so they can be exercised by Tests/SelfTest.
enum RuntimeConfigRequest {
    static let defaultRegion = "tokyo"

    static func isDefault(region: String) -> Bool { region == defaultRegion }

    private static let idCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")

    /// `base` + path, plus `?region=<id>` for a non-default region. Built by string concatenation:
    /// URL.appendingPathComponent would percent-escape the "?" (same trap as APIClient.apiURL).
    /// The default region sends today's request unchanged.
    static func url(base: String, region: String) -> URL? {
        var s = base + "/device/runtime-config"
        if !isDefault(region: region) {
            guard let id = region.addingPercentEncoding(withAllowedCharacters: idCharacters) else { return nil }
            s += "?region=" + id
        }
        return URL(string: s)
    }

    /// A non-default region must be confirmed by the server. A backend that predates regions
    /// ignores the query and returns the Tokyo config; accepting that would connect to Tokyo
    /// while the app says otherwise.
    static func confirms(region: String, in response: [String: Any]) -> Bool {
        guard let echoed = response["region"] as? String else { return false }
        return echoed.lowercased() == region.lowercased()
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
