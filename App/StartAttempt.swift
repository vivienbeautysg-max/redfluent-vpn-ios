import Foundation

/// An attempt to start the tunnel that the app itself began (connect() / restart()).
struct StartAttempt: Equatable {
    let startedAt: Date
    let regionID: String
}

/// Decides which "disconnected" status changes may be reported as a failed start: only an attempt the
/// app began that never reached "connected", and only within `window`.
/// connected -> reasserting -> disconnected (network change, on-demand) and starts that iOS triggers
/// by itself are not start failures; they stay a plain "Disconnected", as in 1.0.
struct StartAttemptTracker {
    static let window: TimeInterval = 90

    private(set) var attempt: StartAttempt?

    mutating func begin(regionID: String, now: Date = Date()) {
        attempt = StartAttempt(startedAt: now, regionID: regionID)
    }

    /// The tunnel came up: the attempt succeeded.
    mutating func reachedConnected() {
        attempt = nil
    }

    /// The user stopped it, or startVPNTunnel() itself threw: nothing left to report.
    mutating func cancel() {
        attempt = nil
    }

    /// The attempt a "disconnected" status change may belong to, if any. An expired one is dropped.
    mutating func attemptForDisconnect(now: Date = Date()) -> StartAttempt? {
        guard let current = attempt else { return nil }
        if now.timeIntervalSince(current.startedAt) > Self.window {
            attempt = nil
            return nil
        }
        return current
    }

    /// The failure has been reported.
    mutating func finish() {
        attempt = nil
    }
}
