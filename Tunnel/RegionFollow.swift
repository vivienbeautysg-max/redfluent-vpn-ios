import Foundation

/// What one `GET /device/runtime-config` round trip came back with.
enum RuntimeConfigOutcome: Equatable {
    /// 200 with a runtimeConfig. `region` is the region the server says it answered with, when it says.
    case config(region: String?)
    /// The server answered with an error; `error` is its JSON `error` text when there was one.
    case http(status: Int, error: String?)
    /// No usable answer (offline, timeout, not an HTTP response).
    case network
    /// No device token / API base in the saved configuration: nothing to ask the server with.
    case notActivated
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
    /// The server now assigns another region, or the same region with another config: hot-reload the engine.
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

    /// An expired invite: refused at start with its own message (the rest of the start rules: StartPolicy).
    static func blocksStart(_ outcome: RuntimeConfigOutcome) -> Bool {
        stopKind(of: outcome) == .expired
    }

    static func sameRegion(_ a: String, _ b: String) -> Bool { a.lowercased() == b.lowercased() }

    /// What to do with the answer of a follow check while `active` is the region the engine runs.
    /// `configChanged`: the fetched config is not the one the engine runs (see `configChanged(fetched:running:)`).
    /// Same region with another config (a new server address, new routing rules) reloads too: otherwise a server
    /// move or a rule fix only reaches a phone at its next reconnect. `rejected`: the fetched config is the one
    /// that already failed to load here, so it is not tried again every 5 minutes.
    static func decide(active: String, outcome: RuntimeConfigOutcome,
                       configChanged: Bool = false, rejected: Bool = false) -> FollowAction {
        switch outcome {
        case .network, .notActivated:
            return .keep
        case .http:
            if let kind = stopKind(of: outcome) { return .stop(kind) }
            return .keep
        case .config(let region):
            if rejected { return .keep }
            if let region, !region.isEmpty, !sameRegion(region, active) { return .reload(region: region) }
            return configChanged ? .reload(region: active) : .keep
        }
    }

    /// The fetched config differs from the one the engine runs. Either side unknown is no change: never reload
    /// on a guess. Both are the server's runtimeConfig re-serialised with sorted keys, so equal means same config.
    static func configChanged(fetched: Data?, running: Data?) -> Bool {
        guard let fetched, let running else { return false }
        return fetched != running
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

/// What the tunnel does at start with the answer of `GET /device/runtime-config`.
enum StartDecision: Equatable {
    /// Connect with the config just fetched (kept as this device's last good one once the engine runs it).
    case useFetched
    /// The server could not be reached: connect with the last config the server issued to this device.
    case useLastGood
    /// Do not connect. `clearsLastGood`: the server ended this device's access, so its saved config goes too.
    case refuse(code: Int, message: String, clearsLastGood: Bool)
}

/// The start rules (pure, no I/O). A device connects only with a config the server issued to it: the one just
/// fetched or, when the server cannot be reached, the last one it got (same region, at most 30 days old).
/// There is no shared fallback config.
enum StartPolicy {
    static let lastGoodMaxAge: TimeInterval = 30 * 86_400
    /// A saved config may look up to this much newer than now (clock corrections) and still count.
    static let clockSlack: TimeInterval = 86_400
    static let unreachableMessage = "Can't reach server"
    static let notActivatedMessage = "Device not activated"
    static let notFoundMessage = "Device not found"

    static func lastGoodIsFresh(fetchedAt: Date, now: Date) -> Bool {
        let age = now.timeIntervalSince(fetchedAt)
        return age >= -clockSlack && age <= lastGoodMaxAge
    }

    /// No usable answer: offline, timeout, 5xx, 408 / 429, a 2xx without a config, or any answer without our
    /// backend's JSON `error` (a CDN / WAF / captive portal / hotel proxy page, whatever its status).
    /// Says nothing about this device's access.
    static func isUnreachable(_ outcome: RuntimeConfigOutcome) -> Bool {
        switch outcome {
        case .network:
            return true
        case .http(let status, let error):
            return error == nil || status >= 500 || status == 408 || status == 429 || (200..<300).contains(status)
        case .config, .notActivated:
            return false
        }
    }

    /// Our backend's own answer that ends this device's access. The backend always sends a JSON `error` with
    /// these, so a bare 401 / 403 / 404 is not one. Same rule as FollowPolicy.stopKind, plus 404 (unknown device).
    static func endsAccess(_ outcome: RuntimeConfigOutcome) -> Bool {
        guard case .http(let status, let error) = outcome, error != nil else { return false }
        return status == 404 || FollowPolicy.stopKind(status: status, error: error) != nil
    }

    /// - Parameters:
    ///   - region: the region the saved configuration asks for.
    ///   - detail: the failure text for the region message ("HTTP 503", "timed out", ...).
    ///   - lastGood: when and for which region the saved last good config was fetched, if there is one.
    static func decide(outcome: RuntimeConfigOutcome, region: String, detail: String,
                       lastGood: (fetchedAt: Date, region: String)?, now: Date) -> StartDecision {
        switch outcome {
        case .config:
            return .useFetched
        case .notActivated:
            return .refuse(code: 401, message: notActivatedMessage, clearsLastGood: true)
        case .http, .network:
            break
        }
        let isDefault = RuntimeConfigRequest.isDefault(region: region)
        if FollowPolicy.blocksStart(outcome) {
            return .refuse(code: 403, message: StopKind.expired.message, clearsLastGood: true)
        }
        // Signed out, deleted, revoked, unknown device, as our backend says it.
        if endsAccess(outcome), case .http(let status, _) = outcome {
            guard isDefault else {
                return .refuse(code: 210, message: RuntimeConfigRequest.failureMessage(region: region, detail: detail),
                               clearsLastGood: true)
            }
            return .refuse(code: status, message: status == 404 ? notFoundMessage : StopKind.revoked.message,
                           clearsLastGood: true)
        }
        // Unchanged: a non-default region that cannot be loaded never connects to something else.
        guard isDefault else {
            return .refuse(code: 210, message: RuntimeConfigRequest.failureMessage(region: region, detail: detail),
                           clearsLastGood: false)
        }
        if isUnreachable(outcome) {
            if let lastGood, FollowPolicy.sameRegion(lastGood.region, region),
               lastGoodIsFresh(fetchedAt: lastGood.fetchedAt, now: now) {
                return .useLastGood
            }
            return .refuse(code: 230, message: unreachableMessage, clearsLastGood: false)
        }
        // Any other answer from our backend (400, 409, 403 "region ..."): it refused this request; keep what is saved.
        guard case .http(let status, _) = outcome else {
            return .refuse(code: 230, message: unreachableMessage, clearsLastGood: false)
        }
        return .refuse(code: status, message: "Server error \(status)", clearsLastGood: false)
    }

    /// A follow check that keeps the engine running: refresh the saved config's time only when the server sent
    /// exactly the config the engine runs (both serialised with sorted keys). Anything else was never started.
    static func refreshesLastGood(fetched: Data?, running: Data?) -> Bool {
        guard let fetched, let running else { return false }
        return fetched == running
    }
}
