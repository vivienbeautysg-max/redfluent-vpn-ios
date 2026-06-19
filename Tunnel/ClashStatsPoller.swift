import Foundation
import os.log

/// Polls sing-box's clash-compatible REST API (running inside the extension
/// at 127.0.0.1:9090) every ~2 seconds and writes a `StatsSnapshot` into the
/// shared App Group container.
///
/// Implemented as a Swift `actor` so all property access is serialized — no
/// data races between the start/stop callers (provider main actor) and the
/// detached polling task.
actor ClashStatsPoller {

    // MARK: Configuration

    private let host: String
    private let port: Int
    private let interval: TimeInterval
    private let session: URLSession
    private let logger = Logger(subsystem: "com.redfluent.vpn.tunnel", category: "ClashStatsPoller")

    // MARK: State

    private var task: Task<Void, Never>?
    private var connectionStartedAt: Date?
    private var secret: String?

    // Differential bookkeeping for /traffic substitute.
    // sing-box's /traffic is a streaming chunked endpoint that
    // `URLSession.data(for:)` cannot consume — it would block until the
    // server closes the connection (never), causing perpetual 1s timeouts.
    // We instead derive instantaneous Bps from successive /connections
    // uploadTotal / downloadTotal samples.
    // Int64 — sing-box's cumulative totals routinely cross the Int32 ceiling
    // on a multi-GB session and would silently overflow on 32-bit Int hosts.
    private var previousTotalUp: Int64?
    private var previousTotalDown: Int64?
    private var previousTickAt: Date?

    // MARK: Init

    init(host: String = "127.0.0.1",
         port: Int = 9090,
         interval: TimeInterval = 2.0) {
        self.host = host
        self.port = port
        self.interval = interval

        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 1.0
        cfg.timeoutIntervalForResource = 1.0
        cfg.waitsForConnectivity = false
        cfg.urlCache = nil
        cfg.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        self.session = URLSession(configuration: cfg)
    }

    // MARK: Lifecycle

    /// Begin polling. `bootedAt` is the timestamp the provider considers the
    /// connection to have started — passed in so the duration timer never
    /// jumps backwards on the first tick.
    func start(bootedAt: Date, secret: String?) {
        guard task == nil else { return }
        self.connectionStartedAt = bootedAt
        self.secret = secret
        logger.info("ClashStatsPoller starting (every \(self.interval, privacy: .public)s)")

        let intervalNs = UInt64(interval * 1_000_000_000)
        // Plain `Task` (not `.detached`) so the loop inherits this actor's
        // executor — every tick already needs actor isolation, so the
        // detached variant just adds a needless hop per iteration.
        task = Task(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                await self.tick()
                try? await Task.sleep(nanoseconds: intervalNs)
            }
        }
    }

    func stop() async {
        logger.info("ClashStatsPoller stopping")
        task?.cancel()
        let pending = task
        task = nil
        // Await clean shutdown so any in-flight tick observes cancellation.
        await pending?.value

        // Write a final "disconnected" snapshot so the UI can react promptly.
        let snap = StatsSnapshot(
            timestamp: Date(),
            connected: false,
            connectionStartedAt: nil,
            pingMs: nil
        )
        SharedContainer.writeStats(snap)
        connectionStartedAt = nil
        previousTotalUp = nil
        previousTotalDown = nil
        previousTickAt = nil
    }

    // MARK: Polling

    private func tick() async {
        // Only /connections — /traffic is a chunked streaming endpoint
        // incompatible with URLSession.data(for:).
        let connections: ConnectionsPayload? = await fetch(path: "/connections")

        // If the API didn't respond, the daemon is probably not ready yet —
        // silently skip this tick.
        guard let connections else { return }

        let now = Date()
        let totalUp: Int64 = connections.uploadTotal ?? 0
        let totalDown: Int64 = connections.downloadTotal ?? 0

        // Compute instantaneous Bps from the difference between this and the
        // previous sample. On the very first tick we have no prior baseline,
        // so fall back to the session average (totals / time-since-boot) —
        // this gives the UI a non-zero number immediately instead of the
        // misleading 0 B/s shown for ~2 s after every connect.
        var uplinkBps: Int64 = 0
        var downlinkBps: Int64 = 0
        if let prevUp = previousTotalUp,
           let prevDown = previousTotalDown,
           let prevAt = previousTickAt {
            let elapsed = now.timeIntervalSince(prevAt)
            if elapsed > 0 {
                uplinkBps = max(0, Int64(Double(totalUp - prevUp) / elapsed))
                downlinkBps = max(0, Int64(Double(totalDown - prevDown) / elapsed))
            }
        } else if let bootedAt = connectionStartedAt {
            let sessionElapsed = now.timeIntervalSince(bootedAt)
            // Require at least 1s of session before falling back to the
            // session average. With sub-second elapsed, even a tiny totals
            // value (a few KB of handshake traffic) divides into a fake
            // multi-MB/s reading. The next tick (~2s later) will compute a
            // proper differential anyway.
            if sessionElapsed >= 1.0 {
                uplinkBps = max(0, Int64(Double(totalUp) / sessionElapsed))
                downlinkBps = max(0, Int64(Double(totalDown) / sessionElapsed))
            }
            // Otherwise leave at 0; differential will kick in on tick 2.
        }
        previousTotalUp = totalUp
        previousTotalDown = totalDown
        previousTickAt = now

        var proxy = 0
        var direct = 0
        if let conns = connections.connections {
            for c in conns {
                let chains = c.chains ?? []
                let lower = chains.map { $0.lowercased() }
                if lower.contains("direct") {
                    direct += 1
                } else {
                    // Default to "proxy" — anything routed through a non-direct
                    // chain counts as proxied. This matches Clash dashboard UX.
                    proxy += 1
                }
            }
        }

        let snap = StatsSnapshot(
            timestamp: now,
            connected: true,
            connectionStartedAt: connectionStartedAt,
            uplinkBps: uplinkBps,
            downlinkBps: downlinkBps,
            totalUp: totalUp,
            totalDown: totalDown,
            activeConnections: connections.connections?.count ?? 0,
            proxyConnections: proxy,
            directConnections: direct,
            pingMs: nil // populated by future latency probe
        )
        SharedContainer.writeStats(snap)
    }

    // MARK: HTTP

    private func fetch<T: Decodable>(path: String) async -> T? {
        guard let url = URL(string: "http://\(host):\(port)\(path)") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let secret, !secret.isEmpty {
            req.addValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await session.data(for: req)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return nil
            }
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            // Connection refused / timeout / decode error — all expected during
            // boot races. Stay quiet to avoid log spam.
            return nil
        }
    }

    // MARK: Wire types
    //
    // We intentionally model only the fields we need and mark everything
    // optional so a schema drift in upstream sing-box doesn't crash the poller.

    private struct ConnectionsPayload: Decodable {
        let connections: [ConnectionEntry]?
        let uploadTotal: Int64?
        let downloadTotal: Int64?
    }

    private struct ConnectionEntry: Decodable {
        let chains: [String]?
        // `metadata` is intentionally not decoded — only `chains` is used.
        // Skipping it avoids allocating a struct per connection on every tick.
    }
}
