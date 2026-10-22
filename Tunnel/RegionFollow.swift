import Foundation

/// What one `GET /device/runtime-config` round trip came back with.
enum RuntimeConfigOutcome: Equatable {
    /// 200 with a runtimeConfig. `region` is the region the server says it answered with, when it says.
    case config(region: String?)
    /// The server answered with an error; `error` is its JSON `error` text when there was one.
    case http(status: Int, error: String?)
    /// No usable answer (offline, timeout, not an HTTP response).
    case network
}

/// Why the server ended this device's access.
enum StopKind: String, Equatable {
    case expired
    case revoked

    /// Text for the app (Diagnostics / Last error).
    var message: String { self == .expired ? "Invite expired" : "Access revoked" }
}

enum FollowAction: Equatable {
    /// Nothing to do (same region, or no usable answer).
    case keep
    /// The server now assigns another region: hot-reload the engine with the new config.
    case reload(region: String)
    /// Expired / revoked: stop the tunnel and tell the app.
    case stop(StopKind)
}

/// The rules of the "follow" check the tunnel runs while connected (pure, no I/O).
enum FollowPolicy {
    /// One timer, every 5 minutes.
    static let interval: TimeInterval = 300
    /// After a network change, wait this long for the network to settle before checking.
    static let pathDebounce: TimeInterval = 15
    /// Two checks are never closer than this (a timer tick right after a network-change check is skipped).
    static let minGap: TimeInterval = 30

    /// An error the server gave that means the account itself is finished. Needs the server's JSON
    /// `error` text: a bare 403/401 without it (a CDN or WAF page) says nothing about this account.
    /// 403 "invite expired" is the expiry; 403 "region ..." (not allowed / unavailable) is about the
    /// region, not the account; any other 401/403 means the device was revoked (an expired login
    /// token is a 401 too, which the app sorts out afterwards by asking /profile).
    static func stopKind(status: Int, error: String?) -> StopKind? {
        guard status == 401 || status == 403, let error else { return nil }
        let text = error.lowercased()
        if status == 403 {
            if text.contains("expired") { return .expired }
            if text.contains("region") { return nil }
        }
        return .revoked
    }

    static func stopKind(of outcome: RuntimeConfigOutcome) -> StopKind? {
        if case .http(let status, let error) = outcome { return stopKind(status: status, error: error) }
        return nil
    }

    /// At tunnel start only an expired invite is refused outright; every other failure keeps
    /// today's behaviour (Tokyo falls back to the bundled config).
    static func blocksStart(_ outcome: RuntimeConfigOutcome) -> Bool {
        stopKind(of: outcome) == .expired
    }

    static func sameRegion(_ a: String, _ b: String) -> Bool { a.lowercased() == b.lowercased() }

    /// What to do with the answer of a follow check while `active` is the region the engine runs.
    static func decide(active: String, outcome: RuntimeConfigOutcome) -> FollowAction {
        switch outcome {
        case .network:
            return .keep
        case .http:
            if let kind = stopKind(of: outcome) { return .stop(kind) }
            return .keep
        case .config(let region):
            guard let region, !region.isEmpty, !sameRegion(region, active) else { return .keep }
            return .reload(region: region)
        }
    }

    /// The default network as far as a re-check cares: usable or not, and over which interfaces.
    struct PathSignature: Equatable {
        let satisfied: Bool
        let interfaces: [String]
    }

    /// Re-check after a network change only when there is a usable network that differs from the
    /// last one seen (the first observation is just the current state).
    static func pathChangeWarrantsCheck(previous: PathSignature?, current: PathSignature) -> Bool {
        guard let previous else { return false }
        return current.satisfied && previous != current
    }
}
